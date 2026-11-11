import '../../../administration/domain/services/service_archivage.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../domain/services/numerotation_pieces.dart';
import '../../../administration/data/sync/depot_demandes_referentiel.dart';
import '../../../administration/data/repositories/preferences_poste_repository.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../../elevage/data/sync/identifiants_elevage.dart';
import '../../../core/events/domain_event.dart';
import '../../../comptabilite/data/repositories/comptabilite_repository_drift.dart';
import '../../../comptabilite/domain/usecases/generer_ecritures_automatiques.dart';
import '../../domain/entities/produit_vendable.dart';
import '../../domain/entities/livraison.dart';
import '../../domain/entities/client.dart';
import '../../domain/entities/vente.dart';
import '../../domain/repositories/ventes_repository.dart';
import '../../../comptabilite/domain/plan_syscohada.dart';

class VentesRepositoryDrift implements VentesRepository {
  VentesRepositoryDrift(this._db, this._bus)
    : _ecritures = GenererEcrituresAutomatiques(
        ComptabiliteRepositoryDrift(_db),
      );

  final AppDatabase _db;
  final EventBus _bus;

  /// BR-CPT-003 — génération des écritures de vente.
  final GenererEcrituresAutomatiques _ecritures;

  /// Ventile un panier entre les comptes de produits selon la catégorie du
  /// produit : « Commerce Annexe » → 707, tout le reste → 701.
  /// Ventile un panier par **(compte, centre analytique)**.
  ///
  /// Le compte répond à la question comptable — 707 pour le commerce annexe,
  /// 701 pour l'avicole — et le centre à la question de gestion : de quelle
  /// filière vient ce revenu.
  ///
  /// ⚠️ Sans ce second axe, tout l'avicole tombait dans un seul bloc alors que
  /// `comptabilite-analytique.html` l.146-149 ventile bien **Goliaths** et
  /// **Pintades** séparément. Le centre vient de `PRODUITS_VENDABLES.espece`
  /// pour un animal vivant, de la catégorie sinon.
  Future<Map<CleVentilationVente, double>> _ventilerVente(
    List<LignePanier> panier,
  ) async {
    final taux = await _tauxParGroupe();
    final ventilation = <CleVentilationVente, double>{};
    for (final ligne in panier) {
      final produit = await (_db.select(
        _db.produitsVendables,
      )..where((p) => p.id.equals(ligne.produitId))).getSingleOrNull();
      final cle = _cle(produit, taux);
      ventilation[cle] = (ventilation[cle] ?? 0) + ligne.total;
    }
    return ventilation;
  }

  /// Taux de TVA (en %) par groupe de taxe (`groupes_taxe`) : le prix d'une ligne de vente est
  /// TTC, la TVA s'en extrait au taux du groupe du produit (A exonéré : 0, B : 18 %).
  Future<Map<String, double>> _tauxParGroupe() async {
    final groupes = await _db.select(_db.groupesTaxe).get();
    return {for (final g in groupes) g.code: g.taux};
  }

  /// Taux des frais de livraison facturés : celui du panier s'il est unique, sinon 0 (exonéré).
  static double _tauxLivraison(Map<CleVentilationVente, double> ventilation) {
    final taux = {for (final cle in ventilation.keys) cle.$3};
    return taux.length == 1 ? taux.first : 0;
  }

  CleVentilationVente _cle(ProduitVendableRow? produit, Map<String, double> taux) {
    final tauxProduit = taux[produit?.groupeTaxe ?? 'A'] ?? 0.0;
    if (produit?.cat == 'Commerce Annexe') {
      return (PlanSyscohada.ventesMarchandises, 'Commerce Annexe', tauxProduit);
    }
    return (
      PlanSyscohada.ventesProduitsFinis,
      // `espece` porte l'identifiant de la filiere ; a defaut le produit est
      // avicole sans filiere identifiee (oeufs vendus au detail, par exemple)
      // et reste non impute plutot que rattache arbitrairement.
      _centreDepuisEspece(produit?.espece),
      tauxProduit,
    );
  }

  static String? _centreDepuisEspece(String? espece) => switch (espece) {
    'goliaths' => 'Goliaths',
    'pintades' => 'Pintades',
    'lapins' => 'Lapins',
    'escargots' => 'Escargots',
    'ovins' => 'Ovins',
    'poissons-chats' => 'Poissons-Chats',
    'poulets' => 'Poulets',
    'pondeuses' => 'Pondeuses',
    _ => null,
  };

  /// Même ventilation, sur les lignes déjà enregistrées — contrepassation.
  ///
  /// L'écriture inverse doit porter **les mêmes centres** que l'écriture
  /// d'origine, sans quoi l'annulation d'une vente de goliaths retirerait du
  /// revenu à un autre centre.
  Future<Map<CleVentilationVente, double>> _ventilerLignesEnregistrees(
    List<LigneVenteRow> lignes,
  ) async {
    final taux = await _tauxParGroupe();
    final ventilation = <CleVentilationVente, double>{};
    for (final ligne in lignes) {
      final produit = await (_db.select(
        _db.produitsVendables,
      )..where((p) => p.id.equals(ligne.produitId))).getSingleOrNull();
      final cle = _cle(produit, taux);
      ventilation[cle] = (ventilation[cle] ?? 0) + ligne.qte * ligne.pu;
    }
    return ventilation;
  }

  @override
  Future<List<ProduitVendable>> chargerCatalogue() async {
    final lignes = await (_db.select(
      _db.produitsVendables,
    )..orderBy([(p) => OrderingTerm.asc(p.name)])).get();
    return lignes.map(_produitVersDomaine).toList();
  }

  @override
  Future<List<Vente>> chargerVentes({int limite = 200}) async {
    // Strict Avoid §8 : pagination des le depart sur une table a croissance
    // illimitee, jamais ajoutee apres coup.
    final ventes =
        await (_db.select(_db.ventes)
              ..orderBy([(v) => OrderingTerm.desc(v.dateVente)])
              ..limit(limite))
            .get();
    if (ventes.isEmpty) return const [];

    final references = ventes.map((v) => v.ref).toList();
    final lignes = await (_db.select(
      _db.lignesVente,
    )..where((l) => l.venteRef.isIn(references))).get();

    final lignesParVente = <String, List<LigneVente>>{};
    for (final ligne in lignes) {
      lignesParVente
          .putIfAbsent(ligne.venteRef, () => [])
          .add(
            LigneVente(
              produitId: ligne.produitId,
              nom: ligne.name,
              quantite: ligne.qte,
              prixUnitaire: ligne.pu,
              espece: ligne.espece,
            ),
          );
    }

    return [
      for (final v in ventes)
        _venteVersDomaine(v, lignesParVente[v.ref] ?? const []),
    ];
  }

  @override
  Future<Vente?> chargerVente(String reference) async {
    final vente = await (_db.select(
      _db.ventes,
    )..where((v) => v.ref.equals(reference))).getSingleOrNull();
    if (vente == null) return null;

    final lignes = await (_db.select(
      _db.lignesVente,
    )..where((l) => l.venteRef.equals(reference))).get();

    return _venteVersDomaine(vente, [
      for (final l in lignes)
        LigneVente(
          produitId: l.produitId,
          nom: l.name,
          quantite: l.qte,
          prixUnitaire: l.pu,
          espece: l.espece,
        ),
    ]);
  }

  /// ## Transaction atomique — BR-VTE-002
  ///
  /// C'est le point que le Master Prompt §2.3 désigne nommément comme l'échec à
  /// ne pas reproduire : côté web, `validateSale()` générait une référence
  /// aléatoire **sans rien persister**. Ici, les 4 écritures sont dans une
  /// seule transaction Drift — si l'une échoue, aucune n'est appliquée.
  @override
  Future<ResultatEncaissement> enregistrerVente({
    required String client,
    required String mode,
    required String statut,
    required double montantPaye,
    required List<LignePanier> panier,
    String? clientId,
    Livraison? livraison,
    String? ligneMobileMoney,
    DateTime? echeance,
    DateTime? date,
  }) async {
    final maintenant = date ?? DateTime.now();
    // Les frais d'une livraison **facturee separement** entrent dans le total :
    // c'est la seule lecture coherente du libelle. Le prototype affiche le
    // champ sans jamais l'ajouter.
    final total =
        panier.fold<double>(0, (s, l) => s + l.total) +
        (livraison?.supplementFacture ?? 0);

    final vente = await _db.transaction(() async {
      final reference = await _prochaineReference(maintenant.year);

      // 1. La vente
      await _db
          .into(_db.ventes)
          .insert(
            VentesCompanion.insert(
              ref: reference,
              client: client,
              clientId: Value(await _clientRetenu(client, clientId)),
              dateVente: maintenant,
              mode: mode,
              status: statut,
              total: total,
              paye: montantPaye,
              livraisonMode: Value(livraison?.mode.code),
              livraisonFrais: Value(livraison?.frais),
              livraisonAdresse: Value(livraison?.adresse),
              livraisonContact: Value(livraison?.contact),
              ligneMobileMoney: Value(ligneMobileMoney),
              echeance: Value(echeance),
            ),
          );

      for (final ligne in panier) {
        // 2. Les lignes
        await _db
            .into(_db.lignesVente)
            .insert(
              LignesVenteCompanion.insert(
                venteRef: reference,
                produitId: ligne.produitId,
                name: ligne.nom,
                qte: ligne.quantite,
                pu: ligne.prixUnitaire,
                espece: Value(ligne.espece),
              ),
            );

        // 3. Le decrement de stock, borne a 0 (BR-ELV-001 par extension).
        await _decrementerStock(ligne.produitId, ligne.quantite.round());

        // 4. Le compteur de ventes du jour de la fiche d'elevage
        //    (BR-ELV-010), si le produit est un animal vivant.
        if (ligne.espece != null) {
          await _ajusterFicheVentesJour(
            espece: ligne.espece!,
            date: maintenant,
            delta: ligne.quantite.round(),
          );
        }
      }

      return Vente(
        reference: reference,
        client: client,
        date: maintenant,
        mode: mode,
        statut: statut,
        total: total,
        paye: montantPaye,
        ligneMobileMoney: ligneMobileMoney,
        echeance: echeance,
        lignes: [
          for (final l in panier)
            LigneVente(
              produitId: l.produitId,
              nom: l.nom,
              quantite: l.quantite,
              prixUnitaire: l.prixUnitaire,
              espece: l.espece,
              unite: l.unite,
            ),
        ],
      );
    });

    // BR-CPT-003 — ecritures comptables, APRES la transaction de vente : une
    // vente reste valide meme si le mois comptable est cloture (l'ecriture est
    // alors refusee et signalee, pas la vente).
    final ventilationVente = await _ventilerVente(panier);
    await _ecritures.pourVente(
      reference: vente.reference,
      date: vente.date,
      mode: mode,
      statut: statut,
      total: total,
      paye: montantPaye,
      ventilation: ventilationVente,
      fraisLivraison: livraison?.supplementFacture ?? 0,
      tauxLivraison: _tauxLivraison(ventilationVente),
    );

    // Publie APRES la transaction : notifier des ecrans d'une ecriture qui
    // aurait pu etre annulee serait pire que ne rien notifier.
    _bus.publier(
      VenteValideeEvent(
        venteRef: vente.reference,
        lignes: [
          for (final l in panier)
            LigneVenteInfo(
              produitId: l.produitId,
              quantite: l.quantite,
              espece: l.espece,
            ),
        ],
      ),
    );

    return ResultatEncaissement(vente: vente);
  }

  @override
  Future<void> annulerVente({
    required String reference,
    required String motif,
  }) async {
    final lignesInfo = <LigneVenteInfo>[];
    Map<CleVentilationVente, double> ventilation = const {};
    VenteRow? venteAnnulee;

    await _db.transaction(() async {
      final vente = await (_db.select(
        _db.ventes,
      )..where((v) => v.ref.equals(reference))).getSingleOrNull();
      if (vente == null) {
        throw StateError('Vente $reference introuvable.');
      }
      if (vente.status == StatutVente.annulee) {
        throw StateError('Vente $reference déjà annulée.');
      }

      final lignes = await (_db.select(
        _db.lignesVente,
      )..where((l) => l.venteRef.equals(reference))).get();

      venteAnnulee = vente;
      ventilation = await _ventilerLignesEnregistrees(lignes);

      for (final ligne in lignes) {
        // Restitution du stock (FRS-VTE-05).
        await _incrementerStock(ligne.produitId, ligne.qte.round());

        // Le compteur de la fiche d'elevage doit etre decremente : sans cela,
        // une vente annulee continuerait de compter comme une sortie du jour.
        if (ligne.espece != null) {
          await _ajusterFicheVentesJour(
            espece: ligne.espece!,
            date: vente.dateVente,
            delta: -ligne.qte.round(),
          );
        }

        lignesInfo.add(
          LigneVenteInfo(
            produitId: ligne.produitId,
            quantite: ligne.qte,
            espece: ligne.espece,
          ),
        );
      }

      // BR-VTE-004 : annulation logique, jamais de suppression physique.
      await (_db.update(
        _db.ventes,
      )..where((v) => v.ref.equals(reference))).write(
        VentesCompanion(
          status: const Value(StatutVente.annulee),
          motifAnnulation: Value(motif),
          // Toute modification locale repasse la vente a envoyer.
          syncStatus: const Value('pending'),
          syncMotif: const Value(null),
          updatedAt: Value(instantSaisie()),
        ),
      );
    });

    // Contrepassation comptable — une ecriture ne se supprime pas, elle
    // s'annule par une ecriture inverse.
    final annulee = venteAnnulee;
    if (annulee != null) {
      await _ecritures.pourAnnulationVente(
        reference: reference,
        date: DateTime.now(),
        mode: annulee.mode,
        total: annulee.total,
        paye: annulee.paye,
        ventilation: ventilation,
        // Les frais d'une livraison facturée font partie du total : l'écriture
        // de vente les a crédités, la contrepassation les reprend.
        fraisLivraison: annulee.livraisonMode == ModeLivraison.facturee.code
            ? (annulee.livraisonFrais ?? 0)
            : 0,
        tauxLivraison: _tauxLivraison(ventilation),
      );
    }

    _bus.publier(VenteAnnuleeEvent(venteRef: reference, lignes: lignesInfo));
  }

  @override
  Future<void> enregistrerPaiement({
    required String reference,
    required double montant,
  }) async {
    String? modeVente;
    // Ce qui est REELLEMENT encaisse : le versement borne au reste du.
    var encaisse = 0.0;

    await _db.transaction(() async {
      final vente = await (_db.select(
        _db.ventes,
      )..where((v) => v.ref.equals(reference))).getSingleOrNull();
      if (vente == null) throw StateError('Vente $reference introuvable.');
      if (vente.status == StatutVente.annulee) {
        throw StateError('Une vente annulée ne peut pas être encaissée.');
      }

      modeVente = vente.mode;

      // Ne jamais encaisser plus que le total dû.
      final nouveauPaye = (vente.paye + montant).clamp(0.0, vente.total);
      encaisse = nouveauPaye - vente.paye;

      await (_db.update(
        _db.ventes,
      )..where((v) => v.ref.equals(reference))).write(
        VentesCompanion(
          paye: Value(nouveauPaye),
          // Doc F4 Écran 3 : si `paye == total`, le statut passe de
          // 'Avance' à 'Payée'.
          status: Value(
            nouveauPaye >= vente.total ? StatutVente.payee : StatutVente.avance,
          ),
          syncStatus: const Value('pending'),
          syncMotif: const Value(null),
          updatedAt: Value(instantSaisie()),
        ),
      );
    });

    // Encaissement d'une creance : Tresorerie au debit, Clients au credit — du
    // montant REELLEMENT encaisse. Comptabiliser le versement saisi (borne dans
    // la vente mais pas dans l'ecriture) creditait 411 de plus que la creance.
    await _ecritures.pourReglement(
      reference: reference,
      date: DateTime.now(),
      mode: modeVente ?? 'Espèces',
      montant: encaisse,
      estEncaissement: true,
    );
  }

  @override
  Future<List<ClientChoix>> chargerClientsChoix() async {
    final lignes = await (_db.select(
      _db.clients,
    )..orderBy([(c) => OrderingTerm.asc(c.nom)])).get();
    return [
      for (final c in lignes)
        ClientChoix(id: c.id, nom: c.nom, telephone: c.telephone),
    ];
  }

  @override
  Future<ProduitVendable> creerProduit(ProduitVendable produit) async {
    final id = nouvelUuid();
    await _db
        .into(_db.produitsVendables)
        .insert(
          ProduitsVendablesCompanion.insert(
            id: Value(id),
            sku: Value(produit.sku),
            name: produit.nom,
            cat: produit.categorie,
            price: produit.prix,
            priceMax: Value(produit.prixMax),
            unit: produit.unite,
            icon: produit.icone,
            stock: produit.stock,
            threshold: produit.seuil,
            espece: Value(produit.espece),
            coutRevient: Value(produit.coutRevient),
          ),
        );
    await DepotDemandesReferentiel(_db).proposerProduit(id);
    await _journaliserCorrection(
      produitId: id,
      article: produit.nom,
      variation: produit.stock,
      motif: 'Stock initial (catalogue)',
    );
    return ProduitVendable(
      id: id,
      sku: produit.sku,
      nom: produit.nom,
      categorie: produit.categorie,
      prix: produit.prix,
      prixMax: produit.prixMax,
      unite: produit.unite,
      icone: produit.icone,
      stock: produit.stock,
      seuil: produit.seuil,
      espece: produit.espece,
      coutRevient: produit.coutRevient,
    );
  }

  @override
  Future<void> mettreAJourProduit(
    ProduitVendable produit, {
    String? motifCorrection,
  }) async {
    final avant = await (_db.select(
      _db.produitsVendables,
    )..where((p) => p.id.equals(produit.id))).getSingleOrNull();
    await (_db.update(
      _db.produitsVendables,
    )..where((p) => p.id.equals(produit.id))).write(
      ProduitsVendablesCompanion(
        name: Value(produit.nom),
        cat: Value(produit.categorie),
        price: Value(produit.prix),
        priceMax: Value(produit.prixMax),
        unit: Value(produit.unite),
        icon: Value(produit.icone),
        stock: Value(produit.stock),
        threshold: Value(produit.seuil),
        espece: Value(produit.espece),
        coutRevient: Value(produit.coutRevient),
      ),
    );
    // Le catalogue appartient au serveur : le poste PROPOSE (`46_` §4.3).
    await DepotDemandesReferentiel(_db).proposerProduit(produit.id);
    // Une correction de stock laisse une trace (journal partagé, jamais un stock).
    if (avant != null) {
      await _journaliserCorrection(
        produitId: produit.id,
        article: produit.nom,
        variation: produit.stock - avant.stock,
        motif: (motifCorrection?.trim().isNotEmpty ?? false)
            ? motifCorrection!.trim()
            : 'Correction de stock (catalogue)',
      );
    }
  }

  /// Trace d'une correction de stock de CE poste. Rien si le stock n'a pas bougé.
  Future<void> _journaliserCorrection({
    required String produitId,
    required String article,
    required int variation,
    required String motif,
  }) async {
    if (variation == 0) return;
    await _db
        .into(_db.mouvementsProduit)
        .insert(
          MouvementsProduitCompanion.insert(
            horodatage: DateTime.now(),
            produitId: produitId,
            article: article,
            motif: motif,
            quantite: variation.toDouble(),
          ),
        );
  }

  @override
  Future<void> supprimerProduit(
    String produitId, {
    String? utilisateurId,
    String? utilisateurNom,
  }) async {
    final ligne = await (_db.select(
      _db.produitsVendables,
    )..where((p) => p.id.equals(produitId))).getSingleOrNull();

    // Le journal des corrections référence le produit : il part avec lui (une
    // même transaction, rien n'est effacé si l'archivage échoue).
    await _db.transaction(() async {
      await (_db.delete(
        _db.mouvementsProduit,
      )..where((m) => m.produitId.equals(produitId))).go();
      await ServiceArchivage(_db).archiver(
        type: TypeArchivable.produits,
        cle: produitId,
        designation: ligne?.name ?? 'Produit #$produitId',
        utilisateurId: utilisateurId,
        utilisateurNom: utilisateurNom,
      );
    });
    // Les autres postes l'apprennent (pierre tombale, jamais d'effacement serveur).
    if (ligne != null) {
      await DepotDemandesReferentiel(_db).proposerArchivageProduit(ligne);
    }
  }

  // ---------------------------------------------------------------- internes

  /// Référence officielle : `V-P2-2026-001` pour un poste appairé (DV-21),
  /// `V-2026-001` sinon. Séquence continue par poste et par année.
  Future<String> _prochaineReference(int annee) async {
    final code = await PreferencesPosteRepository(_db).codeAttribue();
    final prefixe = NumerotationPieces.prefixeVente(annee, code);
    final existantes = await (_db.select(
      _db.ventes,
    )..where((v) => v.ref.like('$prefixe%'))).get();

    var maximum = 0;
    for (final vente in existantes) {
      final numero = NumerotationPieces.sequence(vente.ref, prefixe);
      if (numero != null && numero > maximum) maximum = numero;
    }
    return NumerotationPieces.composer(prefixe, maximum + 1);
  }

  /// Le client CHOISI dans la liste s'il existe ; sinon celui que désigne le nom
  /// (voir [_resoudreClient]).
  Future<String?> _clientRetenu(String nom, String? clientId) async {
    if (clientId != null) {
      final existe = await (_db.select(
        _db.clients,
      )..where((c) => c.id.equals(clientId))).getSingleOrNull();
      if (existe != null) return clientId;
    }
    return _resoudreClient(nom);
  }

  /// Le client que désigne ce nom, **s'il n'y en a qu'un** (casse et espaces
  /// ignorés). Deux homonymes : `null`, on ne devine pas qui a acheté.
  Future<String?> _resoudreClient(String nom) async {
    final cherche = nom.trim().toLowerCase();
    if (cherche.isEmpty) return null;
    final trouves = (await _db.select(_db.clients).get()).where(
      (c) => c.nom.trim().toLowerCase() == cherche,
    );
    return trouves.length == 1 ? trouves.first.id : null;
  }

  Future<void> _decrementerStock(String produitId, int quantite) async {
    final produit = await (_db.select(
      _db.produitsVendables,
    )..where((p) => p.id.equals(produitId))).getSingleOrNull();
    if (produit == null) return;

    await (_db.update(
      _db.produitsVendables,
    )..where((p) => p.id.equals(produitId))).write(
      ProduitsVendablesCompanion(
        stock: Value((produit.stock - quantite).clamp(0, 1 << 30)),
      ),
    );
  }

  Future<void> _incrementerStock(String produitId, int quantite) async {
    final produit = await (_db.select(
      _db.produitsVendables,
    )..where((p) => p.id.equals(produitId))).getSingleOrNull();
    if (produit == null) return;

    await (_db.update(
      _db.produitsVendables,
    )..where((p) => p.id.equals(produitId))).write(
      ProduitsVendablesCompanion(stock: Value(produit.stock + quantite)),
    );
  }

  /// `FICHE_VENTES_JOUR` — compteur cumulatif **de CE poste** (`46a_`) : une ligne par
  /// (espece, date) avec `origine` vide. Les compteurs des autres postes sont des
  /// lignes a part (leur `origine`) que cette methode ne touche JAMAIS : la vente d'un
  /// autre poste n'incremente pas mon compteur, elle arrive par sa propre ligne.
  Future<void> _ajusterFicheVentesJour({
    required String espece,
    required DateTime date,
    required int delta,
  }) async {
    final jour = DateTime(date.year, date.month, date.day);
    final poste = await PreferencesPosteRepository(_db).identifiantPoste();

    final existant =
        await (_db.select(_db.ficheVentesJour)..where(
              (f) =>
                  f.espece.equals(espece) &
                  f.date.equals(jour) &
                  f.origine.isNull(),
            ))
            .getSingleOrNull();

    if (existant == null) {
      if (delta <= 0) return;
      await _db
          .into(_db.ficheVentesJour)
          .insert(
            FicheVentesJourCompanion.insert(
              // Deterministe : (espece, date, poste). Un compteur jamais duplique.
              id: Value(identifiantVentesJour(espece, jour, poste)),
              espece: espece,
              date: jour,
              qte: Value(delta),
              syncStatus: const Value('pending'),
              updatedAt: Value(instantSaisie()),
            ),
          );
      return;
    }

    await (_db.update(
      _db.ficheVentesJour,
    )..where((f) => f.id.equals(existant.id))).write(
      FicheVentesJourCompanion(
        qte: Value((existant.qte + delta).clamp(0, 1 << 30)),
        syncStatus: const Value('pending'),
        syncMotif: const Value(null),
        updatedAt: Value(instantSaisie()),
      ),
    );
  }

  ProduitVendable _produitVersDomaine(ProduitVendableRow ligne) =>
      ProduitVendable(
        id: ligne.id,
        sku: ligne.sku,
        nom: ligne.name,
        categorie: ligne.cat,
        prix: ligne.price,
        prixMax: ligne.priceMax,
        unite: ligne.unit,
        icone: ligne.icon,
        stock: ligne.stock,
        seuil: ligne.threshold,
        espece: ligne.espece,
        coutRevient: ligne.coutRevient,
      );

  Vente _venteVersDomaine(VenteRow ligne, List<LigneVente> lignes) => Vente(
    reference: ligne.ref,
    client: ligne.client,
    date: ligne.dateVente,
    mode: ligne.mode,
    statut: ligne.status,
    total: ligne.total,
    paye: ligne.paye,
    motifAnnulation: ligne.motifAnnulation,
    lignes: lignes,
    ligneMobileMoney: ligne.ligneMobileMoney,
    echeance: ligne.echeance,
  );
}
