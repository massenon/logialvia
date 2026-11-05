import 'package:drift/drift.dart';

import '../../../commercial/data/repositories/ventes_repository_drift.dart';
import '../../../commercial/domain/entities/vente.dart';
import '../../../commercial/data/repositories/factures_mecef_repository_drift.dart';
import '../../../core/database/app_database.dart';
import '../../../core/events/domain_event.dart';
import '../../../core/resultat/resultat.dart';
import '../../../elevage/data/repositories/bandes_repository_drift.dart';
import '../../../elevage/data/repositories/cycle_couveuse_repository_drift.dart';
import '../../../elevage/data/repositories/fiche_elevage_repository_drift.dart';
import '../../../elevage/data/repositories/soins_repository_drift.dart';
import '../../../elevage/domain/entities/configuration_espece.dart';
import '../../../elevage/domain/entities/cycle_incubation.dart';
import '../../../elevage/domain/entities/soin.dart';
import '../../../elevage/domain/services/calcul_fiche_journaliere.dart';
import '../../../elevage/domain/usecases/enregistrer_journee_usecase.dart';

/// Ce qu'un peuplement de démonstration a produit.
class BilanDemonstration {
  const BilanDemonstration(this.lignesParTable);

  final Map<String, int> lignesParTable;

  int get total => lignesParTable.values.fold(0, (s, v) => s + v);
}

/// Peuple un mois d'activité crédible — **données de test uniquement**.
///
/// ## Pourquoi ce seeder existe
///
/// Tous les écrans avaient été vérifiés sur une base quasi vide : 4 ventes,
/// 0 client, 0 soin. Or un écran vide ne prouve presque rien. Les trois vrais
/// défauts trouvés sur ce projet — un débordement de 4,2 px dans une colonne
/// d'actions, une base qui ne démarrait plus, un descripteur de fichier laissé
/// ouvert — sont **tous** venus de l'exécution, aucun d'une relecture.
///
/// Un tableau vide ne déborde jamais. Un KPI sans données affiche « — » et ne
/// révèle ni un format cassé ni une somme fausse. Il fallait de la matière.
///
/// ## Ce seeder passe par les **vrais** chemins d'écriture
///
/// Les ventes passent par `VentesRepository.enregistrerVente`, les journées par
/// `EnregistrerJourneeUseCase`, les mirages et éclosions par leur dépôt. Rien
/// n'est inséré directement dans les tables quand un chemin métier existe :
/// écrire à la main produirait des données que l'application n'aurait jamais pu
/// créer elle-même — et les écrans afficheraient alors une réalité qui n'existe
/// pas.
///
/// ## ⚠️ Réservé au mode « Données de Test »
///
/// L'appelant doit avoir vérifié `PARAMETRES_ENTREPRISE.modeDonneesTest`. Ce
/// seeder ajoute de l'activité fictive : sur une exploitation en service, elle
/// se mélangerait à la vraie. `ServiceReinitialisation` sait la retirer.
class SeedDemonstration {
  const SeedDemonstration(this._db);

  final AppDatabase _db;

  /// Point de départ : le mois se déroule **jusqu'à** cette date.
  Future<BilanDemonstration> executer({DateTime? jusqua}) async {
    final fin = jusqua ?? DateTime.now();
    final debut = DateTime(
      fin.year,
      fin.month,
      fin.day,
    ).subtract(const Duration(days: 29));

    final bilan = <String, int>{};

    bilan['clients'] = await _clients();
    bilan['ventes'] = await _ventes(debut, fin);
    bilan['mouvements_intrant'] = await _mouvementsIntrants(debut, fin);
    bilan['bandes'] = await _bandes(debut);
    bilan['fiche_journee'] = await _fichesElevage(debut, fin);
    bilan['cycle_couveuse'] = await _couveuse(debut, fin);
    bilan['soins_calendrier'] = await _soins(debut, fin);
    bilan['infirmerie'] = await _infirmerie(debut);
    bilan['factures'] = await _facturesMecef();

    return BilanDemonstration(bilan);
  }

  // ------------------------------------------------------- facturation MeCeF

  /// Active le module MeCeF et facture quelques ventes.
  ///
  /// Les trois pièces produites couvrent les trois états qu'un utilisateur
  /// rencontre : une facture normalisée, une facture en attente de
  /// transmission, et un avoir. Un écran de démonstration où tout serait au
  /// même statut n'apprendrait rien.
  ///
  /// Le code MeCeF posé ici est **fictif et le dit** : ces données servent la
  /// prise en main, pas la comptabilité.
  Future<int> _facturesMecef() async {
    // BR-ADM-004 : le module n'est activable qu'avec IFU et RCCM.
    await (_db.update(
      _db.parametresEntreprise,
    )..where((p) => p.id.equals(1))).write(
      const ParametresEntrepriseCompanion(
        ifu: Value('0201234567890'),
        rccm: Value('RB/NAT/26 B 1234'),
        mecefActif: Value(true),
      ),
    );

    final depot = FacturesMecefRepositoryDrift(_db);
    final ventes = await depot.ventesSansFacture();
    if (ventes.length < 3) return 0;

    final premiere = await depot.emettrePourVente(venteRef: ventes[0].ref);
    await depot.normaliser(
      reference: premiere.reference,
      codeMecef: 'DEMO-${premiere.reference}',
      nim: 'NIM-DEMONSTRATION',
      compteur: '1/50',
    );

    final deuxieme = await depot.emettrePourVente(venteRef: ventes[1].ref);
    await depot.emettreAvoir(
      factureOrigine: deuxieme.reference,
      motif: 'Erreur de facturation — quantité surestimée',
    );

    // La troisieme reste « A transmettre » : c'est l'etat le plus frequent
    // sur un poste hors ligne.
    await depot.emettrePourVente(venteRef: ventes[2].ref);

    return 4;
  }

  // ---------------------------------------------------------------- clients

  static const List<(String, String, String)> _clientsFictifs = [
    ('AGOSSOU Prudence', '97 12 34 56', 'Natitingou, quartier Kantaborifa'),
    ('DOSSOU Félicité', '96 45 78 21', 'Natitingou, route de Boukoumbé'),
    ('SIDI ALI Moussa', '95 03 66 14', 'Tanguiéta, marché central'),
    ('Restaurant Le Baobab', '94 88 21 09', 'Natitingou, centre-ville'),
    ('KOMBETTO Adjara', '66 74 12 33', 'Perma, village'),
  ];

  Future<int> _clients() async {
    for (final (nom, tel, _) in _clientsFictifs) {
      await _db
          .into(_db.clients)
          .insert(
            ClientsCompanion.insert(nom: nom, telephone: Value(tel)),
            mode: InsertMode.insertOrIgnore,
          );
    }
    return _clientsFictifs.length;
  }

  // ----------------------------------------------------------------- ventes

  Future<int> _ventes(DateTime debut, DateTime fin) async {
    final depot = VentesRepositoryDrift(_db, EventBus());
    final produits = await (_db.select(
      _db.produitsVendables,
    )..where((p) => p.stock.isBiggerThanValue(0))).get();
    if (produits.isEmpty) return 0;

    var creees = 0;
    // Une vente tous les deux jours : assez pour remplir un journal, pas assez
    // pour rendre les ecrans illisibles.
    for (var jour = 0; jour <= 29; jour += 2) {
      final date = debut.add(Duration(days: jour));
      if (date.isAfter(fin)) break;

      final produit = produits[jour % produits.length];
      final quantite = 1 + (jour % 4);
      final montant = produit.price * quantite;

      // Un tiers a credit : sans creances, l'ecran Clients et les relances
      // resteraient vides, et la lettre de relance ne serait jamais eprouvee.
      final aCredit = jour % 6 == 0;
      final client = _clientsFictifs[jour % _clientsFictifs.length].$1;

      await depot.enregistrerVente(
        client: aCredit ? client : 'Client Comptant',
        mode: jour % 4 == 0 ? ModeReglement.mobileMoney : ModeReglement.especes,
        statut: aCredit ? StatutVente.avance : StatutVente.payee,
        montantPaye: aCredit ? (montant * 0.4).roundToDouble() : montant,
        panier: [
          LignePanier(
            produitId: produit.id,
            nom: produit.name,
            montantGlobal: montant,
            quantite: quantite.toDouble(),
            stockDisponible: produit.stock,
            prixIndicatif: produit.price,
            espece: produit.espece,
            unite: produit.unit,
          ),
        ],
        ligneMobileMoney: jour % 4 == 0 ? '97 00 00 00' : null,
        echeance: aCredit ? date.add(const Duration(days: 30)) : null,
        date: date,
      );
      creees++;
    }
    return creees;
  }

  // ------------------------------------------------------------- intrants

  Future<int> _mouvementsIntrants(DateTime debut, DateTime fin) async {
    final intrants = await _db.select(_db.intrants).get();
    if (intrants.isEmpty) return 0;

    var poses = 0;
    for (var jour = 0; jour <= 29; jour++) {
      final date = debut.add(Duration(days: jour));
      if (date.isAfter(fin)) break;

      // Une reception hebdomadaire, des sorties quotidiennes de provende :
      // c'est le rythme reel d'une ferme, et c'est ce qui donne un inventaire
      // dont les mouvements expliquent le stock.
      if (jour % 7 == 0) {
        final article = intrants[jour % intrants.length];
        await _mouvement(article, date, 20, 'Entrée', 'Réception commande');
        poses++;
      }
      final provende = intrants.first;
      await _mouvement(provende, date, -2, 'Sortie', 'Distribution du jour');
      poses++;
    }
    return poses;
  }

  Future<void> _mouvement(
    IntrantRow article,
    DateTime date,
    double quantite,
    String type,
    String motif,
  ) async {
    await _db
        .into(_db.mouvementsIntrant)
        .insert(
          MouvementsIntrantCompanion.insert(
            horodatage: DateTime(date.year, date.month, date.day, 8),
            intrantCode: article.code,
            article: article.name,
            type: type,
            motif: motif,
            quantite: quantite,
          ),
        );
    // Le stock suit le mouvement : les laisser diverger produirait exactement
    // l'incoherence que l'ecran Inventaire est cense signaler.
    await (_db.update(
      _db.intrants,
    )..where((i) => i.code.equals(article.code))).write(
      IntrantsCompanion(stock: Value((article.stock + quantite).round())),
    );
  }

  // -------------------------------------------------------------- élevage

  Future<int> _bandes(DateTime debut) async {
    final depot = BandesRepositoryDrift(_db);
    var creees = 0;
    for (final config in const [
      ConfigurationsEspeces.goliaths,
      ConfigurationsEspeces.pintades,
    ]) {
      await depot.creerBande(
        espece: config.identifiant,
        code: 'B1',
        dateMiseEnBande: debut,
        effectifInitial: 250,
        observations: 'Bande de démonstration',
      );
      creees++;
    }
    return creees;
  }

  Future<int> _fichesElevage(DateTime debut, DateTime fin) async {
    var saisies = 0;

    for (final config in const [
      ConfigurationsEspeces.goliaths,
      ConfigurationsEspeces.pintades,
    ]) {
      final depot = FicheElevageRepositoryDrift(_db, config);
      final usecase = EnregistrerJourneeUseCase(depot, config);

      for (var jour = 0; jour <= 29; jour++) {
        final date = debut.add(Duration(days: jour));
        if (date.isAfter(fin)) break;

        // Le premier jour pose l'effectif ; les suivants le font vivre.
        final achat = jour == 0 ? 250 : 0;
        final morts = jour % 5 == 0 ? [1, 0, 0] : [0, 0, 0];
        final dons = jour == 12 ? [0, 0, 2] : [0, 0, 0];

        final resultat = await usecase.executer(
          date: date,
          mouvements: MouvementsJour(
            achat: achat,
            ne: jour % 9 == 0 && jour > 0 ? 4 : 0,
            mortsParCategorie: morts,
            donsParCategorie: dons,
          ),
          poidsGeneralG: 1200 + jour * 35,
          traitementObs: jour % 7 == 0 ? 'Vitamines dans l\'eau' : null,
          traitementValide: jour % 7 == 0,
        );
        if (resultat is Succes) saisies++;
      }
    }
    return saisies;
  }

  Future<int> _couveuse(DateTime debut, DateTime fin) async {
    final depot = CycleCouveuseRepositoryDrift(_db);

    final machine = await depot.creerMachine(
      code: 'INC-01',
      libelle: 'Couveuse atelier 528 œufs',
      capaciteOeufs: 528,
    );
    await depot.creerMachine(
      code: 'INC-02',
      libelle: 'Couveuse annexe 264 œufs',
      capaciteOeufs: 264,
    );

    var lots = 0;

    // Lot 1 : clôturé, mirages faits, remplacé — la lignée complète.
    final premier = await depot.creer(
      espece: EspeceCouvable.goliath,
      dateChargement: debut,
      oeufsCharges: 200,
      machineId: machine.id,
    );
    lots++;
    await depot.enregistrerMirage(
      cycleId: premier.id,
      jour: EspeceCouvable.jourMirage1,
      oeufsRetires: 22,
    );
    await depot.enregistrerMirage(
      cycleId: premier.id,
      jour: EspeceCouvable.jourMirage2,
      oeufsRetires: 11,
    );
    if (!debut.add(const Duration(days: 21)).isAfter(fin)) {
      await depot.enregistrerEclosion(
        cycleId: premier.id,
        poussinsEclos: 149,
        oeufsPerdus: 18,
        oeufsRemplacement: 180,
        especeRemplacement: EspeceCouvable.goliath,
        dateRemplacement: debut.add(const Duration(days: 21)),
      );
      lots++;
    }

    // Lot 2 : en cours, premier mirage fait, second attendu — c'est le cas
    // qui doit declencher l'alerte de l'ecran des mirages.
    final second = await depot.creer(
      espece: EspeceCouvable.pintade,
      dateChargement: fin.subtract(const Duration(days: 16)),
      oeufsCharges: 150,
      machineId: machine.id,
    );
    lots++;
    await depot.enregistrerMirage(
      cycleId: second.id,
      jour: EspeceCouvable.jourMirage1,
      oeufsRetires: 19,
    );

    // Lot 3 : tout frais, aucun mirage du.
    await depot.creer(
      espece: EspeceCouvable.goliath,
      dateChargement: fin.subtract(const Duration(days: 3)),
      oeufsCharges: 120,
      machineId: machine.id,
    );
    lots++;

    return lots;
  }

  Future<int> _soins(DateTime debut, DateTime fin) async {
    final depot = SoinsRepositoryDrift(_db);
    var poses = 0;

    final programme = [
      (
        0,
        'goliaths',
        'Vermifuge',
        'Levamisole Volaille',
        7,
        StatutSoin.effectue,
      ),
      (
        5,
        'goliaths',
        'Traitement curatif',
        'Amprolium',
        5,
        StatutSoin.effectue,
      ),
      (15, 'goliaths', 'Vaccination', 'Vaccin HB1', 0, StatutSoin.effectue),
      (24, 'pintades', 'Vitamines', 'CalciBoost', 0, StatutSoin.planifie),
      (32, 'pintades', 'Vaccination', 'Vaccin Gumboro', 0, StatutSoin.planifie),
    ];

    for (final (jour, espece, type, produit, remanence, statut) in programme) {
      final date = debut.add(Duration(days: jour));
      await depot.enregistrerSoin(
        espece: espece,
        date: date,
        typeSoin: type,
        statut: date.isAfter(fin) ? StatutSoin.planifie : statut,
        produit: produit,
        dose: '1 mesure / 20 L',
        remanenceJours: remanence,
        veterinaire: 'SIDI ALI Raïmatou',
        coutFcfa: 2500 + jour * 100,
      );
      poses++;
    }
    return poses;
  }

  Future<int> _infirmerie(DateTime debut) async {
    final depot = SoinsRepositoryDrift(_db);
    await depot.enregistrerEntreeInfirmerie(
      sujet: 'Goliath #G-014',
      motif: 'Boiterie, isolement préventif',
      niveauIsolement: NiveauIsolement.infirmerie,
      dateEntree: debut.add(const Duration(days: 18)),
      espece: 'goliaths',
    );
    await depot.enregistrerEntreeInfirmerie(
      sujet: 'Pintade #P-003',
      motif: 'Suspicion Newcastle',
      niveauIsolement: NiveauIsolement.quarantaineStricte,
      dateEntree: debut.add(const Duration(days: 25)),
      espece: 'pintades',
    );
    return 2;
  }
}
