import '../../../administration/domain/services/service_archivage.dart';
import 'package:drift/drift.dart';

import '../../../comptabilite/data/repositories/comptabilite_repository_drift.dart';
import '../../../comptabilite/domain/usecases/generer_ecritures_automatiques.dart';
import '../../../administration/data/sync/depot_demandes_referentiel.dart';
import '../../../core/database/app_database.dart';
import '../../../commercial/domain/services/numerotation_pieces.dart';
import '../../../administration/data/repositories/preferences_poste_repository.dart';
import '../../../core/sync/identifiant_poste.dart';
import '../../domain/entities/approvisionnement.dart';
import '../../domain/entities/fabrication_provende.dart';

/// Dépôt du contexte Approvisionnement — intrants, mouvements, achats,
/// fournisseurs.
abstract class ApprovisionnementRepository {
  Future<List<Intrant>> chargerIntrants();
  Future<List<MouvementIntrant>> chargerMouvements({int limite = 100});
  Future<List<Fournisseur>> chargerFournisseurs();
  Future<List<Achat>> chargerAchats({int limite = 200});

  Future<void> enregistrerIntrant(Intrant intrant, {required bool creation});
  Future<void> supprimerIntrant(
    String code, {
    String? utilisateurId,
    String? utilisateurNom,
  });

  /// Ajustement d'inventaire (Doc F5 Écran 1) : remplace le stock théorique par
  /// le stock physique constaté et **journalise l'écart** (BR-ADM-003).
  Future<void> ajusterInventaire({
    required String code,
    required int stockPhysique,
    required String motif,
  });

  /// Fabrication de provende — `#modal-fabrication` de `gestion-stocks.html`.
  ///
  /// **Une seule operation** decremente les intrants et journalise autant de
  /// mouvements : le Cahier des Charges Technique §6.2 interdit la sortie
  /// isolee d'un intrant de provende. Si un seul stock est insuffisant, rien
  /// n'est ecrit — la transaction est annulee dans son ensemble.
  ///
  /// Retourne la reference de la fabrication (« FAB-2026-0001 »).
  Future<String> fabriquerProvende(FabricationProvende fabrication);

  Future<Fournisseur> creerFournisseur({
    required String nom,
    String? telephone,
    String? adresse,
    String? fournit,
  });

  /// Enregistre une commande. Si [livree] est vrai, le stock des intrants est
  /// incrémenté, leur PMP recalculé, et les mouvements journalisés — le tout
  /// dans une seule transaction.
  Future<Achat> enregistrerAchat({
    required String fournisseurId,
    required String mode,
    required double montantPaye,
    required List<LignePanierAchat> panier,
    required bool livree,
  });

  /// Réceptionne une commande passée en statut « Commandé ».
  Future<void> receptionnerAchat(String reference);

  Future<void> reglerAchat({
    required String reference,
    required double montant,
  });
}

class ApprovisionnementRepositoryDrift implements ApprovisionnementRepository {
  ApprovisionnementRepositoryDrift(this._db)
    : _ecritures = GenererEcrituresAutomatiques(
        ComptabiliteRepositoryDrift(_db),
      );

  final AppDatabase _db;

  /// BR-CPT-003 — génération des écritures d'achat.
  final GenererEcrituresAutomatiques _ecritures;

  /// Ventile un panier d'achat entre les comptes de charges selon la catégorie
  /// de l'intrant : « Vétérinaire » → 622, « Marchandises » → 602, le reste
  /// (provende) → 601.
  Map<String, double> _ventilerAchat(
    List<LignePanierAchat> panier,
    Map<String, String> categorieParCode,
  ) {
    final ventilation = <String, double>{};
    for (final ligne in panier) {
      final categorie = categorieParCode[ligne.intrantCode];
      final compte = switch (categorie) {
        'Vétérinaire' => ComptesAutomatiques.fraisVeterinaires,
        'Marchandises' => ComptesAutomatiques.achatsMarchandises,
        _ => ComptesAutomatiques.achatsMatieres,
      };
      ventilation[compte] = (ventilation[compte] ?? 0) + ligne.total;
    }
    return ventilation;
  }

  Future<Map<String, String>> _categoriesIntrants() async {
    final lignes = await _db.select(_db.intrants).get();
    return {for (final i in lignes) i.code: i.cat};
  }

  @override
  Future<List<Intrant>> chargerIntrants() async {
    final lignes =
        await (_db.select(_db.intrants)
              ..orderBy([(i) => OrderingTerm.asc(i.name)]))
            .get();
    return [
      for (final i in lignes)
        Intrant(
          code: i.code,
          nom: i.name,
          categorie: i.cat,
          stock: i.stock,
          unite: i.unit,
          seuil: i.threshold,
          pmp: i.pmp,
        ),
    ];
  }

  @override
  Future<List<MouvementIntrant>> chargerMouvements({int limite = 100}) async {
    final lignes =
        await (_db.select(_db.mouvementsIntrant)
              ..orderBy([(m) => OrderingTerm.desc(m.horodatage)])
              ..limit(limite))
            .get();
    return [
      for (final m in lignes)
        MouvementIntrant(
          horodatage: m.horodatage,
          article: m.article,
          type: m.type,
          motif: m.motif,
          quantite: m.quantite,
          reference: m.reference,
          origine: m.origine,
        ),
    ];
  }

  @override
  Future<List<Fournisseur>> chargerFournisseurs() async {
    final lignes =
        await (_db.select(_db.fournisseurs)
              ..orderBy([(f) => OrderingTerm.asc(f.nom)]))
            .get();
    final commandes = await _db.select(_db.achats).get();

    return [
      for (final f in lignes)
        () {
          // Agregats RECALCULES depuis ACHATS, jamais stockes — meme principe
          // que pour les clients (Doc F4).
          final siennes = commandes.where(
            (a) => a.fournisseurId == f.id && a.statut != StatutAchat.annule,
          );
          return Fournisseur(
            id: f.id,
            nom: f.nom,
            telephone: f.telephone,
            adresse: f.adresse,
            fournit: f.fournit,
            nombreCommandes: siennes.length,
            totalAchats: siennes.fold<double>(0, (s, a) => s + a.total),
            soldeDu: siennes.fold<double>(0, (s, a) => s + (a.total - a.paye)),
          );
        }(),
    ];
  }

  @override
  Future<List<Achat>> chargerAchats({int limite = 200}) async {
    final commandes =
        await (_db.select(_db.achats)
              ..orderBy([(a) => OrderingTerm.desc(a.dateAchat)])
              ..limit(limite))
            .get();
    if (commandes.isEmpty) return const [];

    final fournisseurs = await _db.select(_db.fournisseurs).get();
    final nomParId = {for (final f in fournisseurs) f.id: f.nom};

    final references = commandes.map((a) => a.ref).toList();
    final lignes = await (_db.select(
      _db.lignesAchat,
    )..where((l) => l.achatRef.isIn(references))).get();

    final parAchat = <String, List<LigneAchat>>{};
    for (final l in lignes) {
      parAchat.putIfAbsent(l.achatRef, () => []).add(
        LigneAchat(
          intrantCode: l.intrantCode,
          nom: l.nom,
          quantite: l.qte,
          prixUnitaire: l.puAchat,
        ),
      );
    }

    return [
      for (final a in commandes)
        Achat(
          reference: a.ref,
          fournisseurId: a.fournisseurId,
          fournisseurNom: nomParId[a.fournisseurId] ?? '—',
          date: a.dateAchat,
          statut: a.statut,
          total: a.total,
          paye: a.paye,
          mode: a.mode,
          lignes: parAchat[a.ref] ?? const [],
        ),
    ];
  }

  @override
  Future<void> enregistrerIntrant(
    Intrant intrant, {
    required bool creation,
  }) async {
    if (creation) {
      await _db
          .into(_db.intrants)
          .insert(
            IntrantsCompanion.insert(
              code: intrant.code,
              name: intrant.nom,
              cat: intrant.categorie,
              stock: intrant.stock,
              unit: intrant.unite,
              threshold: intrant.seuil,
              pmp: intrant.pmp,
            ),
          );
      await DepotDemandesReferentiel(_db).proposerIntrant(intrant.code);
      return;
    }

    await (_db.update(
      _db.intrants,
    )..where((i) => i.code.equals(intrant.code))).write(
      IntrantsCompanion(
        name: Value(intrant.nom),
        cat: Value(intrant.categorie),
        stock: Value(intrant.stock),
        unit: Value(intrant.unite),
        threshold: Value(intrant.seuil),
        pmp: Value(intrant.pmp),
      ),
    );
    // Le référentiel appartient au serveur : le poste PROPOSE (sans stock ni PMP).
    await DepotDemandesReferentiel(_db).proposerIntrant(intrant.code);
  }

  @override
  Future<void> supprimerIntrant(
    String code, {
    String? utilisateurId,
    String? utilisateurNom,
  }) async {
    final ligne = await (_db.select(
      _db.intrants,
    )..where((i) => i.code.equals(code))).getSingleOrNull();

    await ServiceArchivage(_db).archiver(
      type: TypeArchivable.intrants,
      cle: code,
      designation: ligne == null ? code : '$code — ${ligne.name}',
      utilisateurId: utilisateurId,
      utilisateurNom: utilisateurNom,
    );
  }

  @override
  Future<void> ajusterInventaire({
    required String code,
    required int stockPhysique,
    required String motif,
  }) async {
    await _db.transaction(() async {
      final intrant = await (_db.select(
        _db.intrants,
      )..where((i) => i.code.equals(code))).getSingleOrNull();
      if (intrant == null) throw StateError('Intrant $code introuvable.');

      final ecart = stockPhysique - intrant.stock;

      await (_db.update(_db.intrants)..where((i) => i.code.equals(code))).write(
        IntrantsCompanion(stock: Value(stockPhysique)),
      );

      // BR-ADM-003 : l'ajustement doit rester tracable. Sans ce journal,
      // remplacer un stock theorique par un stock constate effacerait
      // silencieusement l'ecart.
      await _journaliser(
        intrantCode: code,
        article: intrant.name,
        type: TypeMouvement.ajustement,
        motif: motif,
        quantite: ecart.toDouble(),
      );
    });
  }

  @override
  Future<String> fabriquerProvende(FabricationProvende fabrication) async {
    return _db.transaction(() async {
      final maintenant = DateTime.now();
      final reference = await _prochaineReferenceFabrication(maintenant.year);

      // 1re passe : tout verifier AVANT d'ecrire quoi que ce soit. Decrementer
      // au fil de l'eau puis echouer sur le 5e intrant laisserait 4 stocks
      // amputes d'une fabrication qui n'a pas eu lieu.
      final intrants = <String, IntrantRow>{};
      for (final entree in fabrication.composition.entries) {
        final intrant = await (_db.select(
          _db.intrants,
        )..where((i) => i.code.equals(entree.key))).getSingleOrNull();
        if (intrant == null) {
          throw StateError('Intrant ${entree.key} introuvable.');
        }
        if (entree.value > intrant.stock) {
          throw StateError(
            'Stock insuffisant : ${intrant.name} '
            '(${intrant.stock} ${intrant.unit} dispo).',
          );
        }
        intrants[entree.key] = intrant;
      }

      final total = fabrication.totalKg;
      final motif =
          'Fabrication de provende — ${total.toStringAsFixed(0)} kg '
          '($reference)';

      for (final entree in fabrication.composition.entries) {
        final intrant = intrants[entree.key]!;
        final restant = intrant.stock - entree.value.round();

        await (_db.update(
          _db.intrants,
        )..where((i) => i.code.equals(entree.key))).write(
          IntrantsCompanion(stock: Value(restant)),
        );

        await _journaliser(
          intrantCode: entree.key,
          article: intrant.name,
          type: TypeMouvement.sortie,
          motif: motif,
          // Quantite **signee** : negative en sortie (Doc D1).
          quantite: -entree.value,
          reference: reference,
          horodatage: maintenant,
        );
      }

      return reference;
    });
  }

  /// « FAB-2026-0001 » — sequence deduite des mouvements deja journalises.
  Future<String> _prochaineReferenceFabrication(int annee) async {
    final debut = 'FAB-$annee-';
    final lignes = await (_db.select(
      _db.mouvementsIntrant,
    )..where((m) => m.reference.like('$debut%'))).get();

    var maximum = 0;
    for (final ligne in lignes) {
      final sequence = int.tryParse(
        (ligne.reference ?? '').substring(debut.length),
      );
      if (sequence != null && sequence > maximum) maximum = sequence;
    }
    return '$debut${(maximum + 1).toString().padLeft(4, '0')}';
  }

  @override
  Future<Fournisseur> creerFournisseur({
    required String nom,
    String? telephone,
    String? adresse,
    String? fournit,
  }) async {
    final id = nouvelUuid();
    await _db
        .into(_db.fournisseurs)
        .insert(
          FournisseursCompanion.insert(
            id: Value(id),
            nom: nom,
            telephone: Value(telephone),
            adresse: Value(adresse),
            fournit: Value(fournit),
          ),
        );
    return Fournisseur(
      id: id,
      nom: nom,
      telephone: telephone,
      adresse: adresse,
      fournit: fournit,
    );
  }

  @override
  Future<Achat> enregistrerAchat({
    required String fournisseurId,
    required String mode,
    required double montantPaye,
    required List<LignePanierAchat> panier,
    required bool livree,
  }) async {
    final maintenant = DateTime.now();
    final total = panier.fold<double>(0, (s, l) => s + l.total);
    final categories = await _categoriesIntrants();

    final achat = await _db.transaction(() async {
      final reference = await _prochaineReference(maintenant.year);

      await _db
          .into(_db.achats)
          .insert(
            AchatsCompanion.insert(
              ref: reference,
              fournisseurId: fournisseurId,
              dateAchat: maintenant,
              statut: livree ? StatutAchat.livre : StatutAchat.commande,
              total: total,
              paye: Value(montantPaye),
              mode: Value(mode),
            ),
          );

      for (final ligne in panier) {
        await _db
            .into(_db.lignesAchat)
            .insert(
              LignesAchatCompanion.insert(
                achatRef: reference,
                intrantCode: ligne.intrantCode,
                nom: ligne.nom,
                qte: ligne.quantite,
                puAchat: ligne.prixUnitaire,
              ),
            );
      }

      if (livree) {
        await _receptionnerLignes(reference, panier, maintenant);
      }

      final fournisseur = await (_db.select(
        _db.fournisseurs,
      )..where((f) => f.id.equals(fournisseurId))).getSingleOrNull();

      return Achat(
        reference: reference,
        fournisseurId: fournisseurId,
        fournisseurNom: fournisseur?.nom ?? '—',
        date: maintenant,
        statut: livree ? StatutAchat.livre : StatutAchat.commande,
        total: total,
        paye: montantPaye,
        mode: mode,
      );
    });

    // BR-CPT-003 : Débit Achats / Crédit Caisse ou Fournisseur selon le mode
    // de règlement — la règle que Doc F5 prescrivait sans qu'elle soit
    // implémentable tant que la comptabilité n'existait pas.
    await _ecritures.pourAchat(
      reference: achat.reference,
      date: achat.date,
      mode: mode,
      total: total,
      paye: montantPaye,
      ventilation: _ventilerAchat(panier, categories),
    );

    return achat;
  }

  @override
  Future<void> receptionnerAchat(String reference) async {
    await _db.transaction(() async {
      final achat = await (_db.select(
        _db.achats,
      )..where((a) => a.ref.equals(reference))).getSingleOrNull();
      if (achat == null) throw StateError('Commande $reference introuvable.');
      if (achat.statut != StatutAchat.commande) {
        throw StateError('Cette commande n\'est pas en attente de livraison.');
      }

      final lignes = await (_db.select(
        _db.lignesAchat,
      )..where((l) => l.achatRef.equals(reference))).get();

      await _receptionnerLignes(
        reference,
        [
          for (final l in lignes)
            LignePanierAchat(
              intrantCode: l.intrantCode,
              nom: l.nom,
              quantite: l.qte,
              prixUnitaire: l.puAchat,
              unite: '',
            ),
        ],
        DateTime.now(),
      );

      await (_db.update(_db.achats)..where((a) => a.ref.equals(reference)))
          .write(
            AchatsCompanion(
              statut: const Value(StatutAchat.livre),
              // Toute modification locale repasse l'achat a envoyer.
              syncStatus: const Value('pending'),
              syncMotif: const Value(null),
              updatedAt: Value(instantSaisie()),
            ),
          );
    });
  }

  @override
  Future<void> reglerAchat({
    required String reference,
    required double montant,
  }) async {
    String? modeAchat;

    await _db.transaction(() async {
      final achat = await (_db.select(
        _db.achats,
      )..where((a) => a.ref.equals(reference))).getSingleOrNull();
      if (achat == null) throw StateError('Commande $reference introuvable.');

      modeAchat = achat.mode;

      // Ne jamais regler plus que le total du.
      final nouveauPaye = (achat.paye + montant).clamp(0.0, achat.total);
      await (_db.update(_db.achats)..where((a) => a.ref.equals(reference)))
          .write(
            AchatsCompanion(
              paye: Value(nouveauPaye),
              syncStatus: const Value('pending'),
              syncMotif: const Value(null),
              updatedAt: Value(instantSaisie()),
            ),
          );
    });

    // Reglement d'une dette : Fournisseurs au debit, Tresorerie au credit.
    await _ecritures.pourReglement(
      reference: reference,
      date: DateTime.now(),
      mode: modeAchat ?? 'Espèces',
      montant: montant,
      estEncaissement: false,
    );
  }

  // ---------------------------------------------------------------- internes

  /// Réception : incrémente le stock, **recalcule le PMP** et journalise.
  ///
  /// ## Le PMP — règle déduite, signalée comme telle
  ///
  /// `INTRANTS.pmp` est nommée « Prix Moyen Pondéré » dans Doc D1, mais **aucun
  /// document ne dit comment elle évolue**. Sans règle, la colonne resterait
  /// figée à sa valeur de seed et la valorisation du stock serait fausse dès la
  /// première réception à un prix différent.
  ///
  /// Formule appliquée — moyenne pondérée standard :
  /// `PMP' = (stock × PMP + qté reçue × prix d'achat) ÷ (stock + qté reçue)`
  ///
  /// C'est la définition usuelle du PMP en comptabilité de stock. À confirmer
  /// avec la Gérante si une autre méthode (FIFO, dernier prix) est pratiquée.
  Future<void> _receptionnerLignes(
    String reference,
    List<LignePanierAchat> lignes,
    DateTime horodatage,
  ) async {
    for (final ligne in lignes) {
      final intrant = await (_db.select(
        _db.intrants,
      )..where((i) => i.code.equals(ligne.intrantCode))).getSingleOrNull();
      if (intrant == null) continue;

      final quantite = ligne.quantite.round();
      final nouveauStock = intrant.stock + quantite;
      final nouveauPmp = nouveauStock <= 0
          ? intrant.pmp
          : ((intrant.stock * intrant.pmp + quantite * ligne.prixUnitaire) /
                    nouveauStock)
                .round();

      await (_db.update(
        _db.intrants,
      )..where((i) => i.code.equals(ligne.intrantCode))).write(
        IntrantsCompanion(
          stock: Value(nouveauStock),
          pmp: Value(nouveauPmp),
        ),
      );

      await _journaliser(
        intrantCode: ligne.intrantCode,
        article: ligne.nom,
        type: TypeMouvement.entree,
        motif: 'Réception commande $reference',
        quantite: ligne.quantite,
        reference: reference,
        horodatage: horodatage,
      );
    }
  }

  Future<void> _journaliser({
    required String intrantCode,
    required String article,
    required String type,
    required String motif,
    required double quantite,
    String? reference,
    DateTime? horodatage,
  }) async {
    await _db
        .into(_db.mouvementsIntrant)
        .insert(
          MouvementsIntrantCompanion.insert(
            horodatage: horodatage ?? DateTime.now(),
            intrantCode: intrantCode,
            article: article,
            type: type,
            motif: motif,
            quantite: quantite,
            reference: Value(reference),
          ),
        );
  }

  /// Référence officielle : `ACH-P2-2026-001` pour un poste appairé (DV-21),
  /// `ACH-2026-001` sinon. Séquence continue par poste et par année.
  Future<String> _prochaineReference(int annee) async {
    final code = await PreferencesPosteRepository(_db).codeAttribue();
    final prefixe = NumerotationPieces.prefixeAchat(annee, code);
    final existantes = await (_db.select(
      _db.achats,
    )..where((a) => a.ref.like('$prefixe%'))).get();

    var maximum = 0;
    for (final achat in existantes) {
      final numero = NumerotationPieces.sequence(achat.ref, prefixe);
      if (numero != null && numero > maximum) maximum = numero;
    }
    return NumerotationPieces.composer(prefixe, maximum + 1);
  }
}
