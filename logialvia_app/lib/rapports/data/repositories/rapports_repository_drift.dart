import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../approvisionnement/domain/entities/approvisionnement.dart';
import '../../../elevage/domain/entities/configuration_espece.dart';
import '../../../elevage/domain/entities/cycle_incubation.dart';
import '../../../elevage/domain/entities/parametres_elevage.dart';
import '../../../elevage/domain/entities/soin.dart';
import '../../../elevage/domain/services/calcul_fiche_journaliere.dart';
import '../../domain/entities/rapports.dart';

abstract class RapportsRepository {
  /// Charge les 6 états d'un coup : ils partagent la même période et les mêmes
  /// écritures, les recharger onglet par onglet multiplierait les requêtes sans
  /// rien apporter.
  Future<DonneesRapports> charger({
    required DateTime debut,
    required DateTime fin,
    DateTime? aujourdhui,
  });
}

/// Modèle de lecture transverse — Doc F7.
///
/// **Aucune écriture.** Ce dépôt ne fait que lire, agréger et présenter ce que
/// les autres modules ont enregistré. Toutes les valeurs affichées par l'écran
/// Rapports proviennent d'ici ; aucune n'est saisie ni recopiée du prototype.
class RapportsRepositoryDrift implements RapportsRepository {
  const RapportsRepositoryDrift(this._db);

  final AppDatabase _db;

  @override
  Future<DonneesRapports> charger({
    required DateTime debut,
    required DateTime fin,
    DateTime? aujourdhui,
  }) async {
    // Borne haute inclusive : une opération du 08/08 doit entrer dans « au 08/08 ».
    final finInclusive = DateTime(fin.year, fin.month, fin.day, 23, 59, 59);
    final debutJour = DateTime(debut.year, debut.month, debut.day);
    final maintenant = aujourdhui ?? DateTime.now();

    final comptes = await _db.select(_db.planComptable).get();
    final libelleParCompte = {
      for (final c in comptes) c.numeroCompte: c.libelle,
    };

    return DonneesRapports(
      recettesDepenses: await _recettesDepenses(
        debutJour,
        finInclusive,
        libelleParCompte,
      ),
      comptesTresorerie: await _comptesTresorerie(debutJour, libelleParCompte),
      mouvementsTresorerie: await _mouvementsTresorerie(
        debutJour,
        finInclusive,
      ),
      creances: await _creances(maintenant),
      dettes: await _dettes(maintenant),
      recensement: await _recensement(debutJour, finInclusive),
      mouvementsElevage: await _mouvementsElevage(debutJour, finInclusive),
      couvoir: await _couvoir(),
      stocks: await _stocks(),
      effectifTotal: await _effectifTotal(),
      sujetsMalades: await _sujetsMalades(),
      cyclesEnCours: await _cyclesEnCours(),
      tauxEclosionMoyen: await _tauxEclosionMoyen(),
    );
  }

  // ------------------------------------------- Onglet 1 : Recettes/Dépenses

  /// Une ligne **par compte de gestion mouvementé**, comme le prototype qui
  /// agrège par catégorie SYSCOHADA (`701`, `707`, `601`, `628`) et non par
  /// écriture individuelle.
  Future<List<LigneRecetteDepense>> _recettesDepenses(
    DateTime debut,
    DateTime fin,
    Map<String, String> libelleParCompte,
  ) async {
    final ecritures =
        await (_db.select(_db.ecritureComptable)
              ..where(
                (e) =>
                    e.dateEcriture.isBiggerOrEqualValue(debut) &
                    e.dateEcriture.isSmallerOrEqualValue(fin) &
                    // Les écritures de clôture (CL) et d'à-nouveaux (AN) ne sont ni des
                    // recettes, ni des dépenses, ni des mouvements de trésorerie : les
                    // compter doublerait les totaux (`47c_`).
                    e.journalCode.isNotIn(const ['AN', 'CL']),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.numeroCompte)]))
            .get();

    final encaissements = <String, double>{};
    final decaissements = <String, double>{};
    final pieces = <String, String>{};

    for (final e in ecritures) {
      // Classe 7 = produits (credites), classe 6 = charges (debitees).
      // Les mouvements de tresorerie et de tiers ne sont ni une recette ni une
      // depense : ce sont des contreparties, les compter doublerait les totaux.
      if (e.numeroCompte.startsWith('7')) {
        encaissements[e.numeroCompte] =
            (encaissements[e.numeroCompte] ?? 0) + e.credit - e.debit;
      } else if (e.numeroCompte.startsWith('6')) {
        decaissements[e.numeroCompte] =
            (decaissements[e.numeroCompte] ?? 0) + e.debit - e.credit;
      } else {
        continue;
      }
      pieces.putIfAbsent(e.numeroCompte, () => e.numeroPiece ?? '—');
    }

    final periode = _libellePeriode(debut, fin);
    final numeros = {...encaissements.keys, ...decaissements.keys}.toList()
      ..sort();

    return [
      for (final numero in numeros)
        LigneRecetteDepense(
          periode: periode,
          numeroPiece: pieces[numero] ?? '—',
          categorie:
              '$numero - ${libelleParCompte[numero] ?? 'Compte inconnu'}',
          centre: CentresProfit.pourCompte(numero),
          encaissement: encaissements[numero] ?? 0,
          decaissement: decaissements[numero] ?? 0,
        ),
    ];
  }

  static String _libellePeriode(DateTime debut, DateTime fin) {
    const mois = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre',
    ];
    if (debut.year == fin.year && debut.month == fin.month) {
      return '${mois[debut.month - 1]} ${debut.year}';
    }
    return '${mois[debut.month - 1]} ${debut.year} — '
        '${mois[fin.month - 1]} ${fin.year}';
  }

  // ------------------------------------------------ Onglet 2 : Trésorerie

  /// Comptes de classe 5, avec leur solde **avant** le début de la période.
  Future<List<CompteTresorerie>> _comptesTresorerie(
    DateTime debut,
    Map<String, String> libelleParCompte,
  ) async {
    final comptes =
        await (_db.select(_db.planComptable)
              ..where((p) => p.classe.equals('5'))
              ..orderBy([(p) => OrderingTerm.asc(p.numeroCompte)]))
            .get();

    final resultat = <CompteTresorerie>[];
    for (final compte in comptes) {
      final anterieures =
          await (_db.select(_db.ecritureComptable)..where(
                (e) =>
                    e.numeroCompte.equals(compte.numeroCompte) &
                    e.dateEcriture.isSmallerThanValue(debut),
              ))
              .get();
      final solde = anterieures.fold<double>(
        0,
        (s, e) => s + e.debit - e.credit,
      );
      resultat.add(
        CompteTresorerie(
          numero: compte.numeroCompte,
          libelle: libelleParCompte[compte.numeroCompte] ?? compte.libelle,
          soldeOuverture: solde,
        ),
      );
    }
    return resultat;
  }

  Future<List<MouvementTresorerie>> _mouvementsTresorerie(
    DateTime debut,
    DateTime fin,
  ) async {
    final ecritures =
        await (_db.select(_db.ecritureComptable)
              ..where(
                (e) =>
                    e.dateEcriture.isBiggerOrEqualValue(debut) &
                    e.dateEcriture.isSmallerOrEqualValue(fin) &
                    // Les écritures de clôture (CL) et d'à-nouveaux (AN) ne sont ni des
                    // recettes, ni des dépenses, ni des mouvements de trésorerie : les
                    // compter doublerait les totaux (`47c_`).
                    e.journalCode.isNotIn(const ['AN', 'CL']),
              )
              ..orderBy([
                (e) => OrderingTerm.asc(e.dateEcriture),
                (e) => OrderingTerm.asc(e.id),
              ]))
            .get();

    return [
      for (final e in ecritures)
        if (e.numeroCompte.startsWith('5'))
          MouvementTresorerie(
            date: e.dateEcriture,
            compte: CompteTresorerie.libelleCourt(e.numeroCompte),
            typeOperation: _typeOperation(e.venteRef, e.achatRef, e.debit > 0),
            libelle: e.libelle,
            entree: e.debit,
            sortie: e.credit,
          ),
    ];
  }

  /// « Vente POS », « Décaissement Achat », « Acompte Client »… — les libellés
  /// du prototype, déduits de l'origine réelle de l'écriture.
  static String _typeOperation(
    String? venteRef,
    String? achatRef,
    bool estEntree,
  ) {
    if (venteRef != null) return estEntree ? 'Vente POS' : 'Annulation Vente';
    if (achatRef != null) {
      return estEntree ? 'Remboursement Achat' : 'Décaissement Achat';
    }
    return estEntree ? 'Encaissement Divers' : 'Décaissement Divers';
  }

  // -------------------------------------------------- Onglet 3 : Créances

  Future<List<CreanceClient>> _creances(DateTime aujourdhui) async {
    final ventes =
        await (_db.select(_db.ventes)
              ..where((v) => v.paye.isSmallerThan(v.total))
              ..orderBy([(v) => OrderingTerm.asc(v.dateVente)]))
            .get();

    final clients = await _db.select(_db.clients).get();
    final codeParNom = <String, String>{};
    for (var i = 0; i < clients.length; i++) {
      codeParNom[clients[i].nom] = 'CLI-${(i + 1).toString().padLeft(3, '0')}';
    }

    return [
      for (final v in ventes)
        // Une vente annulee n'est plus une creance : son encours a ete
        // contrepasse (BR-CPT-003).
        if (v.status != 'Annulée')
          CreanceClient(
            code: codeParNom[v.client] ?? '—',
            client: v.client,
            numeroFacture: v.ref,
            dateVente: v.dateVente,
            montantInitial: v.total,
            acomptes: v.paye,
            aujourdhui: aujourdhui,
            echeance: v.echeance,
          ),
    ];
  }

  // --------------------------------------------------- Onglet 4 : Dettes

  Future<List<DetteFournisseur>> _dettes(DateTime aujourdhui) async {
    final achats =
        await (_db.select(_db.achats)
              ..where((a) => a.paye.isSmallerThan(a.total))
              ..orderBy([(a) => OrderingTerm.asc(a.dateAchat)]))
            .get();

    final fournisseurs = await _db.select(_db.fournisseurs).get();
    final nomParId = {for (final f in fournisseurs) f.id: f.nom};

    return [
      for (final a in achats)
        if (a.statut != StatutAchat.annule)
          DetteFournisseur(
            code: 'FRN-${a.fournisseurId.toString().padLeft(3, '0')}',
            fournisseur: nomParId[a.fournisseurId] ?? 'Fournisseur inconnu',
            reference: a.ref,
            dateAchat: a.dateAchat,
            montantTotal: a.total,
            regle: a.paye,
            aujourdhui: aujourdhui,
            echeance: a.echeance,
          ),
    ];
  }

  // -------------------------------------------------- Onglet 5 : Élevage

  /// Filières réellement suivies par une fiche journalière.
  static const List<ConfigurationEspece> _filieres = [
    ConfigurationsEspeces.goliaths,
    ConfigurationsEspeces.pintades,
    ConfigurationsEspeces.lapins,
    ConfigurationsEspeces.escargots,
    ConfigurationsEspeces.bovins,
    ConfigurationsEspeces.poissonsChats,
    ConfigurationsEspeces.poulets,
    ConfigurationsEspeces.pondeuses,
  ];

  Future<List<FicheJourneeRow>> _journees(
    String espece,
    DateTime debut,
    DateTime fin,
  ) =>
      (_db.select(_db.ficheJournee)
            ..where(
              (f) =>
                  f.espece.equals(espece) &
                  f.date.isBiggerOrEqualValue(debut) &
                  f.date.isSmallerOrEqualValue(fin),
            )
            ..orderBy([(f) => OrderingTerm.asc(f.date)]))
          .get();

  Future<List<LigneRecensement>> _recensement(
    DateTime debut,
    DateTime fin,
  ) async {
    final resultat = <LigneRecensement>[];

    for (final filiere in _filieres) {
      final journees = await _journees(filiere.identifiant, debut, fin);
      if (journees.isEmpty) continue;

      final derniere = journees.last;
      final indexJeune = filiere.indexCategorieJeune;
      final effectifs = [
        derniere.effCat1Day,
        derniere.effCat2Day,
        derniere.effCat3Day,
        derniere.effCat4Day ?? 0,
      ];

      // « Géniteurs / Matures » = derniere categorie ; « Jeunes » = celle qui
      // recoit achats et naissances, plus la suivante quand elle existe.
      final indexMature = filiere.categories.length - 1;
      final jeunes = effectifs
          .take(filiere.categories.length)
          .toList()
          .asMap()
          .entries
          .where((e) => e.key != indexMature)
          .fold<int>(0, (s, e) => s + e.value);

      var morts = 0;
      var dons = 0;
      for (final j in journees) {
        morts += j.mortCat1 + j.mortCat2 + j.mortCat3 + (j.mortCat4 ?? 0);
        dons += j.donCat1 + j.donCat2 + j.donCat3 + (j.donCat4 ?? 0);
      }

      final malades = await _sujetsMalades(espece: filiere.identifiant);

      resultat.add(
        LigneRecensement(
          lot: filiere.libelle,
          effectifTotal: derniere.effectif,
          effectifMatures: effectifs[indexMature],
          libelleJeunes:
              filiere.categories[indexJeune < 0 ? 0 : indexJeune].libelle,
          effectifJeunes: jeunes,
          mortsPeriode: morts,
          donsPeriode: dons,
          effectifMalade: malades,
        ),
      );
    }

    return resultat;
  }

  Future<List<LigneMouvementElevage>> _mouvementsElevage(
    DateTime debut,
    DateTime fin,
  ) async {
    final resultat = <LigneMouvementElevage>[];

    // Les baremes de rationnement pilotent la colonne « Provende Servie ».
    final baremes = await _db.select(_db.baremesRation).get();
    final taux = [
      for (final t in await _db.select(_db.tauxRationPoids).get())
        TauxRationPoids(
          id: t.id,
          espece: t.espece,
          poidsMinG: t.poidsMinG,
          poidsMaxG: t.poidsMaxG,
          tauxPourcent: t.tauxPourcent,
          confirme: t.confirme,
        ),
    ];

    for (final filiere in _filieres) {
      final journees = await _journees(filiere.identifiant, debut, fin);
      if (journees.isEmpty) continue;

      final derniere = journees.last;
      var quantiteVendue = 0;
      for (final j in journees) {
        quantiteVendue += j.vente;
      }

      // Montant reel des ventes de l'espece sur la periode, lu sur les lignes
      // de vente — jamais reconstitue a partir d'un prix moyen.
      final lignes =
          await (_db.select(_db.lignesVente).join([
                innerJoin(
                  _db.ventes,
                  _db.ventes.ref.equalsExp(_db.lignesVente.venteRef),
                ),
              ])..where(
                _db.lignesVente.espece.equals(filiere.identifiant) &
                    _db.ventes.dateVente.isBiggerOrEqualValue(debut) &
                    _db.ventes.dateVente.isSmallerOrEqualValue(fin) &
                    _db.ventes.status.equals('Annulée').not(),
              ))
              .get();
      final montant = lignes.fold<double>(0, (s, r) {
        final ligne = r.readTable(_db.lignesVente);
        return s + ligne.qte * ligne.pu;
      });

      final calcul = CalculFicheJournaliere(
        filiere,
        rationsConfigurees: {
          for (final b in baremes)
            if (b.espece == filiere.identifiant)
              b.stade: b.rationGrammesParJour,
        },
        tauxParClasse: taux,
      );
      // Meme calcul que la fiche : une filiere rationnee en % du poids vif doit
      // afficher le meme chiffre dans le rapport que sur son ecran.
      final provende = calcul.provendeTotaleGrammes([
        derniere.effCat1Day,
        derniere.effCat2Day,
        derniere.effCat3Day,
        derniere.effCat4Day ?? 0,
      ], poidsTotalGrammes: derniere.poidsGeneralG);

      resultat.add(
        LigneMouvementElevage(
          lot: filiere.libelle,
          quantiteVendue: quantiteVendue,
          montantVente: montant,
          effectifFinal: derniere.effectif,
          traitementAdministre: await _dernierTraitement(
            filiere.identifiant,
            debut,
            fin,
          ),
          signesObserves: await _signesObserves(
            filiere.identifiant,
            debut,
            fin,
          ),
          provendeServieGrammes: provende,
        ),
      );
    }

    return resultat;
  }

  /// Dernier soin **réalisé** sur la période — pas un soin planifié, qui n'a
  /// par définition pas encore été administré.
  Future<String> _dernierTraitement(
    String espece,
    DateTime debut,
    DateTime fin,
  ) async {
    final soins =
        await (_db.select(_db.soinsCalendrier)
              ..where(
                (s) =>
                    s.espece.equals(espece) &
                    s.statut.equals(StatutSoin.effectue) &
                    s.datePrevue.isBiggerOrEqualValue(debut) &
                    s.datePrevue.isSmallerOrEqualValue(fin),
              )
              ..orderBy([(s) => OrderingTerm.desc(s.datePrevue)])
              ..limit(1))
            .get();

    if (soins.isEmpty) return 'Aucun traitement administré';
    final soin = soins.first;
    final produit = soin.produit;
    return produit == null || produit.isEmpty
        ? soin.typeSoin
        : '${soin.typeSoin} ($produit)';
  }

  /// Motifs réellement saisis à l'Infirmerie — jamais un texte générique.
  Future<String> _signesObserves(
    String espece,
    DateTime debut,
    DateTime fin,
  ) async {
    final cas =
        await (_db.select(_db.infirmerie)
              ..where(
                (i) =>
                    i.espece.equals(espece) &
                    i.dateEntree.isBiggerOrEqualValue(debut) &
                    i.dateEntree.isSmallerOrEqualValue(fin),
              )
              ..orderBy([(i) => OrderingTerm.desc(i.dateEntree)]))
            .get();

    if (cas.isEmpty) return 'Aucun signe observé';
    final motifs = <String>{for (final c in cas) c.motif};
    return '${cas.length} sujet(s) — ${motifs.join(', ')}';
  }

  Future<List<LigneCouvoir>> _couvoir() async {
    final cycles = await (_db.select(
      _db.cycleCouveuse,
    )..orderBy([(c) => OrderingTerm.desc(c.dateIncubation)])).get();

    return [
      for (final c in cycles)
        LigneCouvoir(
          codeLot: c.codeIncubation,
          miseEnCouvoir: c.dateIncubation,
          // ⚠️ La duree d'incubation depend de l'espece (Doc F3, corrige) :
          // Goliath 21 jours, Pintade 28 jours. Un `+21` universel avancerait
          // l'eclosion d'une pintade de 6 jours.
          eclosionAttendue: c.dateIncubation.add(
            Duration(days: DureesIncubation.pourEspece(c.espece)),
          ),
          oeufsCouves: c.oeufsCouves,
          nes: c.poussinsNes,
          mortsAuDemarrage: c.poussinsNes == null
              ? null
              : c.oeufsCouves - c.poussinsNes!,
          statut: c.statut,
        ),
    ];
  }

  Future<int> _effectifTotal() async {
    var total = 0;
    for (final filiere in _filieres) {
      final derniere =
          await (_db.select(_db.ficheJournee)
                ..where((f) => f.espece.equals(filiere.identifiant))
                ..orderBy([(f) => OrderingTerm.desc(f.date)])
                ..limit(1))
              .getSingleOrNull();
      total += derniere?.effectif ?? 0;
    }
    return total;
  }

  Future<int> _sujetsMalades({String? espece}) async {
    final requete = _db.select(_db.infirmerie)
      ..where((i) => i.statut.equals(StatutInfirmerie.enCours));
    if (espece != null) {
      requete.where((i) => i.espece.equals(espece));
    }
    return (await requete.get()).length;
  }

  Future<int> _cyclesEnCours() async {
    final cycles = await (_db.select(
      _db.cycleCouveuse,
    )..where((c) => c.statut.equals(StatutCycle.enIncubation))).get();
    return cycles.length;
  }

  Future<double?> _tauxEclosionMoyen() async {
    final eclos = await (_db.select(
      _db.cycleCouveuse,
    )..where((c) => c.poussinsNes.isNotNull())).get();
    if (eclos.isEmpty) return null;

    final couves = eclos.fold<int>(0, (s, c) => s + c.oeufsCouves);
    if (couves == 0) return null;
    final nes = eclos.fold<int>(0, (s, c) => s + (c.poussinsNes ?? 0));
    return nes / couves * 100;
  }

  // --------------------------------------------------- Onglet 6 : Stocks

  Future<List<LigneStock>> _stocks() async {
    final intrants = await (_db.select(
      _db.intrants,
    )..orderBy([(i) => OrderingTerm.asc(i.code)])).get();
    final produits = await (_db.select(
      _db.produitsVendables,
    )..orderBy([(p) => OrderingTerm.asc(p.id)])).get();

    return [
      for (final i in intrants)
        LigneStock(
          sku: i.code,
          designation: i.name,
          categorie: LigneStock.categorieIntrant,
          stockFinal: i.stock.toDouble(),
          unite: i.unit,
          cmup: i.pmp.toDouble(),
          seuil: i.threshold.toDouble(),
        ),
      for (final p in produits)
        LigneStock(
          // `sku` est nullable dans D1 ; le repli sur l'id evite une cellule
          // vide, jamais toleree (Doc E7 §1).
          sku: p.sku ?? 'PRD-${p.id.toString().padLeft(3, '0')}',
          designation: p.name,
          categorie: LigneStock.categorieProduitFini,
          stockFinal: p.stock.toDouble(),
          unite: p.unit,
          // Le cout de revient, s'il est renseigne (v18). `null` sinon : le
          // prix de vente n'est JAMAIS substitue. Le prototype le fait — sa
          // colonne « CMUP » reprend le prix du catalogue a l'identique —, ce
          // qui surevalue le stock et anticipe une marge non realisee.
          cmup: p.coutRevient,
          seuil: p.threshold.toDouble(),
        ),
    ];
  }
}

/// Durées d'incubation réelles — `cycle-couveuse.html` l.232-233.
class DureesIncubation {
  DureesIncubation._();

  static const int goliath = 21;
  static const int pintade = 28;

  static int pourEspece(String espece) {
    final normalise = espece.toLowerCase();
    if (normalise.contains('pintade')) return pintade;
    return goliath;
  }
}
