import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/sync/depot_demandes_referentiel.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_produits_poste.dart';
import 'package:logialvia_app/commercial/data/sync/table_ventes_poste.dart';
import 'package:logialvia_app/commercial/domain/entities/produit_vendable.dart';
import 'package:logialvia_app/commercial/domain/entities/vente.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:logialvia_app/elevage/data/repositories/bandes_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/fiche_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/sync/identifiants_elevage.dart';
import 'package:logialvia_app/elevage/data/sync/table_bandes_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_fiches_journee_poste.dart';
import 'package:logialvia_app/elevage/data/sync/table_ventes_jour_poste.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/entities/journee_elevage.dart';
import 'package:logialvia_app/elevage/domain/usecases/enregistrer_journee_usecase.dart';
import 'package:logialvia_app/elevage/domain/services/calcul_fiche_journaliere.dart';

import '../core/sync/faux_serveur_sync.dart';

/// Palier 7a — fiches journalières, compteurs de ventes du jour et bandes entre
/// postes, contre un faux serveur qui rejoue les règles du vrai (`46a_`).
class _Poste {
  _Poste(this.serveur) : db = AppDatabase.enMemoire() {
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: serveur.client,
    );
    fiches = TableFichesJourneePoste(db);
    compteurs = TableVentesJourPoste(db);
    bandesSync = TableBandesPoste(db);
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: appairage,
      demandes: DepotDemandesReferentiel(db),
      tables: [
        TableProduitsPoste(db),
        TableClientsPoste(db),
        TableVentesPoste(db),
        fiches,
        compteurs,
        bandesSync,
      ],
      client: serveur.client,
    );
    bus = EventBus();
    ventes = VentesRepositoryDrift(db, bus);
    bandesDepot = BandesRepositoryDrift(db);
  }

  final FauxServeurSync serveur;
  final AppDatabase db;
  late final PreferencesPosteRepository preferences;
  late final DepotJetonSyncMemoire depot;
  late final ServiceAppairage appairage;
  late final MoteurSynchronisationPoste moteur;
  late final TableFichesJourneePoste fiches;
  late final TableVentesJourPoste compteurs;
  late final TableBandesPoste bandesSync;
  late final EventBus bus;
  late final VentesRepositoryDrift ventes;
  late final BandesRepositoryDrift bandesDepot;

  Future<void> demarrer() async {
    await SeedInitial(db).executer();
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }

  Future<String> identifiant() => preferences.identifiantPoste();

  FicheElevageRepositoryDrift get depotFiches =>
      FicheElevageRepositoryDrift(db, ConfigurationsEspeces.goliaths);

  /// Saisit une journée par le VRAI cas d'usage (calculs, cascade).
  Future<void> saisir(
    DateTime jour, {
    int achat = 0,
    int ne = 0,
    List<int> morts = const [0, 0, 0],
    String? observation,
    ConfigurationEspece configuration = ConfigurationsEspeces.goliaths,
  }) async {
    final cas = EnregistrerJourneeUseCase(
      FicheElevageRepositoryDrift(db, configuration),
      configuration,
    );
    final r = await cas.executer(
      date: jour,
      mouvements: MouvementsJour(
        achat: achat,
        ne: ne,
        mortsParCategorie: morts,
        donsParCategorie: const [0, 0, 0],
      ),
      traitementObs: observation,
    );
    expect(r, isA<Succes<JourneeElevage>>(), reason: 'la saisie doit réussir');
  }

  Future<List<FicheJourneeRow>> lesFiches() => (db.select(
    db.ficheJournee,
  )..orderBy([(f) => OrderingTerm.asc(f.date)])).get();

  Future<List<FicheVenteJourRow>> lesCompteurs() => db
      .select(db.ficheVentesJour)
      .get()
      .then((l) => l..sort((a, b) => a.id.compareTo(b.id)));

  Future<List<BandeRow>> lesBandes() =>
      (db.select(db.bandes)..orderBy([(b) => OrderingTerm.asc(b.code)])).get();

  Future<String> vendre(String nomProduit, {double qte = 1}) async {
    final catalogue = await ventes.chargerCatalogue();
    final ProduitVendable p = catalogue.firstWhere((x) => x.nom == nomProduit);
    final r = await ventes.enregistrerVente(
      client: 'Client Comptant',
      mode: ModeReglement.especes,
      statut: StatutVente.payee,
      montantPaye: p.prix * qte,
      panier: [
        LignePanier(
          produitId: p.id,
          nom: p.nom,
          montantGlobal: p.prix * qte,
          quantite: qte,
          stockDisponible: p.stock,
          prixIndicatif: p.prix,
          prixIndicatifMax: p.prixMax,
          espece: p.espece,
          unite: p.unite,
        ),
      ],
    );
    return r.vente.reference;
  }
}

Map<String, dynamic> _ligneFiche(
  String espece,
  DateTime jour, {
  String? id,
  Map<String, dynamic> surcharge = const {},
  String? instant,
}) => {
  'id': id ?? identifiantFicheJournee(espece, jour),
  'espece': espece,
  'date': jourCivil(jour),
  'achat': 0,
  'ne': 0,
  'vente': 0,
  'mort_cat1': 0,
  'mort_cat2': 0,
  'mort_cat3': 0,
  'mort_cat4': null,
  'don_cat1': 0,
  'don_cat2': 0,
  'don_cat3': 0,
  'don_cat4': null,
  'effectif': 10,
  'eff_cat1_day': 4,
  'eff_cat2_day': 3,
  'eff_cat3_day': 3,
  'eff_cat4_day': null,
  'srh': null,
  'ts': null,
  'stock_final_oeufs': null,
  'oeufs_pondus': null,
  'oeufs_casses': null,
  'sorties_plateaux': null,
  'poids_general_g': null,
  'traitement_obs': null,
  'traitement_valide': false,
  'is_recorded': true,
  'updated_at': instant ?? instantSaisie(),
  ...surcharge,
};

Map<String, dynamic> _ligneBande(
  String code, {
  String? id,
  String espece = 'goliaths',
  Map<String, dynamic> surcharge = const {},
  String? instant,
}) => {
  'id': id ?? nouvelUuid(),
  'espece': espece,
  'code': code,
  'date_mise_en_bande': '2026-10-01',
  'effectif_initial': 100,
  'date_cloture': null,
  'observations': null,
  'updated_at': instant ?? instantSaisie(),
  ...surcharge,
};

void main() {
  late FauxServeurSync serveur;
  final postes = <_Poste>[];

  Future<_Poste> poste() async {
    final p = _Poste(serveur);
    postes.add(p);
    await p.demarrer();
    return p;
  }

  setUp(() {
    serveur = FauxServeurSync();
    postes.clear();
  });

  tearDown(() async {
    for (final p in postes) {
      await p.db.close();
    }
  });

  final jour = DateTime(2026, 11, 5);

  group('fiches journalières', () {
    test(
      'la saisie d\'une journée est à envoyer, avec un UUID déterministe (espèce, date)',
      () async {
        final a = await poste();
        await a.saisir(jour, achat: 10);

        final f = (await a.lesFiches()).single;
        expect(f.id, identifiantFicheJournee('goliaths', jour));
        expect(f.syncStatus, 'pending');
        expect(DateTime.parse(f.updatedAt).isUtc, isTrue);
      },
    );

    test(
      'envoi : le serveur reçoit la ligne entière, la date civile, et le poste la marque synchronisée',
      () async {
        final a = await poste();
        await a.saisir(jour, achat: 10, observation: 'RAS');

        final r = await a.moteur.synchroniser();

        expect(r.reussie, isTrue, reason: r.message);
        expect(r.refusees, 0);
        final s = serveur.fichesJournee.values.single;
        expect(s['date'], '2026-11-05');
        expect(s['espece'], 'goliaths');
        expect(s['effectif'], 10);
        expect(s['traitement_obs'], 'RAS');
        expect((await a.lesFiches()).single.syncStatus, 'synced');
      },
    );

    test(
      'deux postes, même jour : la saisie la plus RÉCENTE gagne, en bloc, et les deux convergent',
      () async {
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        await a.saisir(jour, achat: 10, observation: 'saisie de A');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await b.saisir(jour, achat: 25, observation: 'saisie de B');

        // Désordre : B se connecte d'abord, A ensuite, puis un tour pour chacun.
        await b.moteur.synchroniser();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await a.moteur.synchroniser();

        final fa = (await a.lesFiches()).single;
        final fb = (await b.lesFiches()).single;
        expect(serveur.fichesJournee, hasLength(1));
        expect(fa.id, fb.id);
        expect(fa.effectif, 25, reason: 'la ligne de B, entière');
        expect(fa.traitementObs, 'saisie de B');
        expect(fb.effectif, 25);
        expect(fa.syncStatus, 'synced');
      },
    );

    test(
      'deux postes : la saisie plus ancienne arrivée en retard ne l\'emporte pas',
      () async {
        final a = await poste();
        final b = await poste();
        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        await b.saisir(jour, achat: 25, observation: 'B (ancienne)');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await a.saisir(jour, achat: 10, observation: 'A (récente)');

        await a.moteur.synchroniser();
        await b.moteur
            .synchroniser(); // B arrive en retard avec une saisie ancienne
        await a.moteur.synchroniser();

        expect((await a.lesFiches()).single.traitementObs, 'A (récente)');
        expect((await b.lesFiches()).single.traitementObs, 'A (récente)');
        expect(
          serveur.fichesJournee.values.single['traitement_obs'],
          'A (récente)',
        );
      },
    );

    test(
      'absorber la fiche d\'un autre poste n\'a AUCUN effet de bord : pas de cascade sur les jours suivants',
      () async {
        final b = await poste();
        // B a saisi le 6 : son effectif (6e) découle de sa propre veille (vide).
        await b.saisir(jour.add(const Duration(days: 1)), achat: 7);
        final avant = (await b.lesFiches()).single;

        // Un autre poste envoie le 5 (50 sujets) : le 6 de B ne doit PAS être recalculé.
        final r = await b.fiches.absorber([
          _ligneFiche(
            'goliaths',
            jour,
            surcharge: {'effectif': 50, 'eff_cat1_day': 50, 'eff_cat2_day': 0},
          ),
        ]);

        expect(r.absorbees, 1);
        final fiches = await b.lesFiches();
        expect(fiches, hasLength(2));
        final lendemain = fiches.last;
        expect(lendemain.effectif, avant.effectif);
        expect(lendemain.updatedAt, avant.updatedAt);
        expect(lendemain.syncStatus, 'pending');
        expect(await b.lesCompteurs(), isEmpty);
        expect(await (b.db.select(b.db.ventes)).get(), isEmpty);
      },
    );

    test(
      'une saisie locale non envoyée PLUS RÉCENTE est conservée ; une plus ancienne est supplantée',
      () async {
        final b = await poste();
        await b.saisir(jour, achat: 7);
        final locale = (await b.lesFiches()).single;
        final plusTot = DateTime.parse(
          locale.updatedAt,
        ).subtract(const Duration(seconds: 5)).toIso8601String();
        final plusTard = DateTime.parse(
          locale.updatedAt,
        ).add(const Duration(seconds: 5)).toIso8601String();

        final ancienne = await b.fiches.absorber([
          _ligneFiche('goliaths', jour, instant: plusTot),
        ]);
        expect(ancienne.conservees, 1);
        expect((await b.lesFiches()).single.effectif, locale.effectif);

        final recente = await b.fiches.absorber([
          _ligneFiche(
            'goliaths',
            jour,
            instant: plusTard,
            surcharge: {'effectif': 99},
          ),
        ]);
        expect(recente.supplantees, 1);
        expect((await b.lesFiches()).single.effectif, 99);
        expect((await b.lesFiches()).single.syncStatus, 'synced');
      },
    );

    test(
      'absorbeur STRICT : une ligne incohérente est refusée et comptée, jamais lissée',
      () async {
        final b = await poste();
        final bonne = _ligneFiche('goliaths', jour);
        final r = await b.fiches.absorber([
          _ligneFiche(
            'goliaths',
            jour,
            id: nouvelUuid(),
          ), // UUID qui n'est pas la clé
          {..._ligneFiche('goliaths', jour), 'id': 'pas-un-uuid'},
          _ligneFiche('dragons', jour), // filière inconnue
          {
            ..._ligneFiche('goliaths', jour),
            'date': '2026-02-31',
          }, // jour inexistant
          {..._ligneFiche('goliaths', jour), 'effectif': -3}, // négatif
          {
            ..._ligneFiche('goliaths', jour),
            'achat': null,
          }, // obligatoire absent
          {
            ..._ligneFiche('goliaths', jour),
            'mort_cat4': -1,
          }, // facultatif négatif
          {
            ..._ligneFiche('goliaths', jour),
            'is_recorded': 1,
          }, // pas un booléen
          {..._ligneFiche('goliaths', jour), 'updated_at': 'hier'},
          bonne,
        ]);

        expect(r.refusees, 9);
        expect(r.absorbees, 1);
        expect(await b.lesFiches(), hasLength(1));
        expect(
          (await b.lesFiches()).single.id,
          identifiantFicheJournee('goliaths', jour),
          reason:
              'la ligne retenue est celle dont l\'UUID est le calcul de sa clé',
        );
      },
    );

    test(
      'une ligne homonyme (même espèce et date, autre UUID) est refusée, jamais écrasée',
      () async {
        final b = await poste();
        await b.db
            .into(b.db.ficheJournee)
            .insert(
              FicheJourneeCompanion.insert(
                espece: 'goliaths',
                date: jour,
                effectif: const Value(5),
              ),
            );

        final r = await b.fiches.absorber([_ligneFiche('goliaths', jour)]);

        expect(r.refusees, 1);
        expect((await b.lesFiches()).single.effectif, 5);
      },
    );

    test(
      'refus du serveur : la fiche devient conflit avec le motif, et n\'est plus renvoyée en boucle',
      () async {
        final a = await poste();
        // Une fiche à UUID aléatoire (saisie directe, hors cas d'usage) : le serveur
        // la refuse, car son UUID n'est pas celui de sa clé.
        await a.db
            .into(a.db.ficheJournee)
            .insert(
              FicheJourneeCompanion.insert(
                espece: 'goliaths',
                date: jour,
                effectif: const Value(5),
              ),
            );

        final r = await a.moteur.synchroniser();

        expect(r.refusees, 1);
        final f = (await a.lesFiches()).single;
        expect(f.syncStatus, 'conflict');
        expect(f.syncMotif, contains('ne correspond pas'));
        expect(serveur.fichesJournee, isEmpty);
        final r2 = await a.moteur.synchroniser();
        expect(r2.envoyees, 0);
      },
    );

    test(
      'hors ligne n\'est pas une erreur : tout reste à envoyer, puis part au retour du réseau',
      () async {
        final a = await poste();
        await a.saisir(jour, achat: 10);
        serveur.horsLigne = true;

        final r = await a.moteur.synchroniser();

        expect(r.issue, IssueSynchronisation.horsLigne);
        expect((await a.lesFiches()).single.syncStatus, 'pending');
        serveur.horsLigne = false;
        expect((await a.moteur.synchroniser()).reussie, isTrue);
        expect(serveur.fichesJournee, hasLength(1));
      },
    );

    test(
      'une saisie faite PENDANT l\'envoi repart au prochain envoi (l\'accusé ne l\'efface pas)',
      () async {
        final a = await poste();
        await a.saisir(jour, achat: 10);
        serveur.pendantEnvoi = () async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
          await a.saisir(jour, achat: 12);
        };

        await a.moteur.synchroniser();
        expect((await a.lesFiches()).single.syncStatus, 'pending');

        await a.moteur.synchroniser();
        expect((await a.lesFiches()).single.syncStatus, 'synced');
        expect(serveur.fichesJournee.values.single['effectif'], 12);
      },
    );

    test(
      'ressaisir une journée DÉJÀ synchronisée la remet à envoyer, avec un instant plus récent',
      () async {
        final a = await poste();
        await a.saisir(jour, achat: 10);
        await a.moteur.synchroniser();
        final avant = (await a.lesFiches()).single;
        expect(avant.syncStatus, 'synced');
        await Future<void>.delayed(const Duration(milliseconds: 5));

        await a.saisir(jour, achat: 12);

        final apres = (await a.lesFiches()).single;
        expect(apres.syncStatus, 'pending');
        expect(
          DateTime.parse(
            apres.updatedAt,
          ).isAfter(DateTime.parse(avant.updatedAt)),
          isTrue,
        );
        expect(apres.id, avant.id, reason: 'toujours la même ligne');
      },
    );

    test(
      'remise à zéro du serveur : le poste purge ses fiches et compte celles qu\'il n\'avait pas envoyées',
      () async {
        final a = await poste();
        await a.saisir(jour, achat: 10);
        await a.moteur.synchroniser();
        await a.saisir(jour.add(const Duration(days: 1)), achat: 3);
        serveur.remettreAZero();

        final r = await a.moteur.synchroniser();

        expect(r.remiseAZero, isTrue);
        expect(r.saisiesPerdues, greaterThanOrEqualTo(1));
        expect(await a.lesFiches(), isEmpty);
      },
    );

    test('purger compte seulement les fiches non synchronisées', () async {
      final a = await poste();
      await a.saisir(jour, achat: 10);
      await a.moteur.synchroniser();
      await a.saisir(jour.add(const Duration(days: 1)), achat: 3);

      expect(await a.fiches.purger(), 1);
      expect(await a.lesFiches(), isEmpty);
    });
  });

  group('compteur des ventes du jour : une ligne par poste, sommée à la lecture', () {
    final aujourdhui = DateTime.now();
    final minuit = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);

    test(
      'la vente incrémente MON compteur (origine vide, UUID déterministe), l\'annulation le décrémente',
      () async {
        final a = await poste();
        final ref = await a.vendre('Goliath mature', qte: 2);

        var c = (await a.lesCompteurs()).single;
        expect(c.qte, 2);
        expect(c.origine, isNull);
        expect(c.syncStatus, 'pending');
        expect(
          c.id,
          identifiantVentesJour('goliaths', minuit, await a.identifiant()),
        );

        await a.ventes.annulerVente(reference: ref, motif: 'Erreur');
        c = (await a.lesCompteurs()).single;
        expect(c.qte, 0);
        expect(c.syncStatus, 'pending');
      },
    );

    test(
      'deux postes vendent : chacun a SA ligne, les deux lisent la SOMME, sans double comptage',
      () async {
        final a = await poste();
        final b = await poste();
        await a.vendre('Goliath mature', qte: 2);
        await b.vendre('Goliath mature', qte: 3);

        await a.moteur.synchroniser();
        await b.moteur.synchroniser();
        await a.moteur.synchroniser();
        // Une seconde passe ne change rien (rejeu idempotent).
        await b.moteur.synchroniser();
        await a.moteur.synchroniser();

        expect(serveur.ventesJour, hasLength(2));
        for (final p in [a, b]) {
          final lignes = await p.lesCompteurs();
          expect(lignes, hasLength(2));
          expect(lignes.where((c) => c.origine == null), hasLength(1));
          final lecture = await p.depotFiches.venteDuJour(
            espece: 'goliaths',
            date: minuit,
          );
          expect(lecture, 5);
        }
        // Les lignes d'un autre poste portent SON identifiant.
        final chezA = await a.lesCompteurs();
        expect(
          chezA.singleWhere((c) => c.origine != null).origine,
          await b.identifiant(),
        );
      },
    );

    test(
      'absorber la VENTE d\'un autre poste n\'incrémente pas mon compteur : il arrive par sa propre ligne',
      () async {
        final a = await poste();
        final b = await poste();
        await a.vendre('Goliath mature', qte: 2);
        await a.moteur.synchroniser();

        await b.moteur.synchroniser();

        expect(await (b.db.select(b.db.ventes)).get(), hasLength(1));
        final lignes = await b.lesCompteurs();
        expect(lignes, hasLength(1));
        expect(lignes.single.origine, await a.identifiant());
        expect(lignes.single.qte, 2);
        expect(lignes.where((c) => c.origine == null), isEmpty);
      },
    );

    test(
      'vendre APRÈS avoir reçu le compteur d\'un autre poste ouvre MA ligne et ne touche pas la sienne',
      () async {
        final a = await poste();
        final b = await poste();
        await a.vendre('Goliath mature', qte: 2);
        await a.moteur.synchroniser();
        await b.moteur.synchroniser(); // B reçoit le compteur de A
        final idA = await a.identifiant();

        await b.vendre('Goliath mature', qte: 3);

        final lignes = await b.lesCompteurs();
        expect(lignes, hasLength(2));
        expect(lignes.singleWhere((c) => c.origine == null).qte, 3);
        expect(
          lignes.singleWhere((c) => c.origine == idA).qte,
          2,
          reason: 'le compteur de A est intact',
        );
        expect(
          await b.depotFiches.venteDuJour(espece: 'goliaths', date: minuit),
          5,
        );
      },
    );

    test('je n\'envoie jamais le compteur d\'un autre poste', () async {
      final a = await poste();
      final b = await poste();
      await a.vendre('Goliath mature', qte: 2);
      await a.moteur.synchroniser();
      await b.moteur.synchroniser();
      // Même si la ligne d'un autre poste est marquée à envoyer, elle ne part pas.
      await (b.db.update(
        b.db.ficheVentesJour,
      )).write(const FicheVentesJourCompanion(syncStatus: Value('pending')));

      expect(await b.compteurs.aEnvoyer(), isEmpty);
    });

    test(
      'mon compteur qui revient d\'un tirage complet sur base vide reprend l\'origine vide : pas de seconde ligne, pas de double comptage',
      () async {
        final a = await poste();
        await a.vendre('Goliath mature', qte: 2);
        await a.moteur.synchroniser();
        // Restauration : la base perd ses compteurs mais garde son identifiant.
        await a.db.delete(a.db.ficheVentesJour).go();
        await a.preferences.definirCurseurTirage(null);

        await a.moteur.synchroniser();

        var lignes = await a.lesCompteurs();
        expect(lignes, hasLength(1));
        expect(lignes.single.origine, isNull, reason: 'c\'est le MIEN');
        expect(lignes.single.qte, 2);

        await a.vendre('Goliath mature', qte: 1);
        lignes = await a.lesCompteurs();
        expect(lignes, hasLength(1), reason: 'toujours une seule ligne');
        expect(lignes.single.qte, 3);
        expect(
          await a.depotFiches.venteDuJour(espece: 'goliaths', date: minuit),
          3,
        );
      },
    );

    test(
      'absorbeur STRICT : identifiant qui n\'est pas celui du poste, poste absent, quantité négative',
      () async {
        final a = await poste();
        const autre = '3f0f1b0e-7a53-4b6e-9b1f-0a1b2c3d4e5f';
        Map<String, dynamic> ligne({
          String? id,
          Object? poste = autre,
          Object? qte = 2,
          String espece = 'goliaths',
        }) => {
          'id': id ?? identifiantVentesJour(espece, minuit, autre),
          'espece': espece,
          'date': jourCivil(minuit),
          'qte': qte,
          'device_id': poste,
          'updated_at': instantSaisie(),
        };

        final r = await a.compteurs.absorber([
          ligne(id: nouvelUuid()),
          ligne(poste: null),
          ligne(qte: -1),
          ligne(qte: 1.5),
          ligne(espece: 'dragons'),
          ligne(),
        ]);

        expect(r.refusees, 5);
        expect(r.absorbees, 1);
        expect((await a.lesCompteurs()).single.origine, autre);
      },
    );

    test(
      'refus du serveur : le compteur devient conflit avec le motif',
      () async {
        final a = await poste();
        await a.db
            .into(a.db.ficheVentesJour)
            .insert(
              FicheVentesJourCompanion.insert(
                espece: 'goliaths',
                date: minuit,
                qte: const Value(2),
              ),
            );

        final r = await a.moteur.synchroniser();

        expect(r.refusees, 1);
        final c = (await a.lesCompteurs()).single;
        expect(c.syncStatus, 'conflict');
        expect(c.syncMotif, contains('compteur'));
      },
    );

    test(
      'remise à zéro : tous les compteurs partent, seuls MES compteurs non envoyés sont comptés perdus',
      () async {
        final a = await poste();
        final b = await poste();
        await b.vendre('Goliath mature', qte: 3);
        await b.moteur.synchroniser();
        await a.moteur.synchroniser(); // reçoit le compteur de B
        await a.vendre('Goliath mature', qte: 2); // non envoyé
        serveur.remettreAZero();

        final r = await a.moteur.synchroniser();

        expect(r.remiseAZero, isTrue);
        expect(await a.lesCompteurs(), isEmpty);
        expect(r.saisiesPerdues, greaterThanOrEqualTo(1));
      },
    );

    test(
      'purger ne compte comme perdus que MES compteurs non envoyés, jamais ceux d\'un autre poste',
      () async {
        final a = await poste();
        final b = await poste();
        await b.vendre('Goliath mature', qte: 3);
        await b.moteur.synchroniser();
        await a.moteur.synchroniser(); // A détient le compteur de B
        await a.vendre('Goliath mature', qte: 2); // le mien, non envoyé
        // Même un compteur étranger marqué à envoyer n'est pas « à moi ».
        await (a.db.update(
          a.db.ficheVentesJour,
        )..where((c) => c.origine.isNotNull())).write(
          const FicheVentesJourCompanion(syncStatus: Value('pending')),
        );

        expect(await a.compteurs.purger(), 1);
        expect(await a.lesCompteurs(), isEmpty);
      },
    );
  });

  group('bandes', () {
    test(
      'création : à envoyer ; le serveur la reçoit ; l\'autre poste la reçoit ; la clôture (dernier écrivain) redescend',
      () async {
        final a = await poste();
        final b = await poste();
        final bande = await a.bandesDepot.creerBande(
          espece: 'goliaths',
          code: 'B1',
          dateMiseEnBande: DateTime(2026, 10, 1),
          effectifInitial: 100,
          observations: 'Lot 1',
        );
        expect((await a.lesBandes()).single.syncStatus, 'pending');

        await a.moteur.synchroniser();
        await b.moteur.synchroniser();

        final chezB = (await b.lesBandes()).single;
        expect(chezB.id, bande.id);
        expect(chezB.code, 'B1');
        expect(chezB.effectifInitial, 100);
        expect(chezB.dateMiseEnBande, DateTime(2026, 10, 1));
        expect(chezB.syncStatus, 'synced');

        await Future<void>.delayed(const Duration(milliseconds: 5));
        await b.bandesDepot.cloturerBande(
          id: bande.id,
          dateCloture: DateTime(2026, 11, 1),
        );
        await b.moteur.synchroniser();
        await a.moteur.synchroniser();

        expect((await a.lesBandes()).single.dateCloture, DateTime(2026, 11, 1));
      },
    );

    test(
      'même code « B2 » créé hors ligne par deux postes : refus visible du second, rien n\'est fusionné ni perdu',
      () async {
        final a = await poste();
        final b = await poste();
        await a.bandesDepot.creerBande(
          espece: 'goliaths',
          code: 'B2',
          dateMiseEnBande: DateTime(2026, 10, 1),
        );
        await b.bandesDepot.creerBande(
          espece: 'goliaths',
          code: 'B2',
          dateMiseEnBande: DateTime(2026, 10, 20),
        );

        await a.moteur.synchroniser();
        final rb = await b.moteur.synchroniser();
        await a.moteur.synchroniser();

        expect(rb.refusees, 1, reason: 'le serveur refuse la seconde');
        expect(rb.refuseesALaReception, 1, reason: 'B refuse celle de A');
        final chezB = await b.lesBandes();
        expect(chezB, hasLength(1));
        expect(chezB.single.dateMiseEnBande, DateTime(2026, 10, 20));
        expect(chezB.single.syncStatus, 'conflict');
        expect(
          chezB.single.syncMotif,
          'Ce code de bande est déjà utilisé pour cette filière.',
        );
        expect(
          (await a.lesBandes()).single.dateMiseEnBande,
          DateTime(2026, 10, 1),
        );
        expect(serveur.bandes, hasLength(1));
      },
    );

    test('le même code dans deux filières différentes est accepté', () async {
      final a = await poste();
      await a.bandesDepot.creerBande(
        espece: 'goliaths',
        code: 'B1',
        dateMiseEnBande: DateTime(2026, 10, 1),
      );
      await a.bandesDepot.creerBande(
        espece: 'pintades',
        code: 'B1',
        dateMiseEnBande: DateTime(2026, 10, 1),
      );

      final r = await a.moteur.synchroniser();

      expect(r.refusees, 0, reason: r.message);
      expect(serveur.bandes, hasLength(2));
    });

    test('absorbeur STRICT : refus comptés, jamais lissés', () async {
      final b = await poste();
      final r = await b.bandesSync.absorber([
        _ligneBande('B1', id: 'pas-un-uuid'),
        _ligneBande('B1', espece: 'dragons'),
        _ligneBande('  '),
        _ligneBande('B1', surcharge: {'date_mise_en_bande': '2026-13-01'}),
        _ligneBande('B1', surcharge: {'date_cloture': '2026-09-01'}),
        _ligneBande('B1', surcharge: {'date_cloture': 'bientôt'}),
        _ligneBande('B1', surcharge: {'effectif_initial': -5}),
        _ligneBande('B1', surcharge: {'effectif_initial': 'beaucoup'}),
        _ligneBande('B1', surcharge: {'updated_at': 'hier'}),
        _ligneBande('B-ok'),
      ]);

      expect(r.refusees, 9);
      expect(r.absorbees, 1);
      expect((await b.lesBandes()).single.code, 'B-ok');
    });

    test('la clôture le jour de la mise en place est acceptée', () async {
      final b = await poste();
      final r = await b.bandesSync.absorber([
        _ligneBande('B1', surcharge: {'date_cloture': '2026-10-01'}),
      ]);

      expect(r.absorbees, 1);
    });

    test(
      'saisie locale plus récente conservée, plus ancienne supplantée',
      () async {
        final b = await poste();
        final bande = await b.bandesDepot.creerBande(
          espece: 'goliaths',
          code: 'B1',
          dateMiseEnBande: DateTime(2026, 10, 1),
        );
        final locale = (await b.lesBandes()).single;
        final plusTot = DateTime.parse(
          locale.updatedAt,
        ).subtract(const Duration(seconds: 5)).toIso8601String();
        final plusTard = DateTime.parse(
          locale.updatedAt,
        ).add(const Duration(seconds: 5)).toIso8601String();

        final ancienne = await b.bandesSync.absorber([
          _ligneBande(
            'B1',
            id: bande.id,
            instant: plusTot,
            surcharge: {'observations': 'serveur'},
          ),
        ]);
        expect(ancienne.conservees, 1);
        expect((await b.lesBandes()).single.observations, isNull);

        final recente = await b.bandesSync.absorber([
          _ligneBande(
            'B1',
            id: bande.id,
            instant: plusTard,
            surcharge: {'observations': 'serveur'},
          ),
        ]);
        expect(recente.supplantees, 1);
        expect((await b.lesBandes()).single.observations, 'serveur');
      },
    );

    test(
      'l\'effectif RÉEL n\'est jamais synchronisé : aucune colonne pour le porter, et la ligne envoyée n\'en contient pas',
      () async {
        final a = await poste();
        await a.bandesDepot.creerBande(
          espece: 'goliaths',
          code: 'B1',
          dateMiseEnBande: DateTime(2026, 10, 1),
          effectifInitial: 100,
        );

        final envoi = (await a.bandesSync.aEnvoyer()).single.corps;

        expect(envoi.keys.toSet(), {
          'id',
          'espece',
          'code',
          'date_mise_en_bande',
          'effectif_initial',
          'date_cloture',
          'observations',
          'updated_at',
        }, reason: 'ni effectif réel, ni effectif calculé');
      },
    );

    test(
      'remise à zéro : les bandes locales sont purgées, les non envoyées comptées',
      () async {
        final a = await poste();
        await a.bandesDepot.creerBande(
          espece: 'goliaths',
          code: 'B1',
          dateMiseEnBande: DateTime(2026, 10, 1),
        );
        await a.moteur.synchroniser();
        await a.bandesDepot.creerBande(
          espece: 'goliaths',
          code: 'B2',
          dateMiseEnBande: DateTime(2026, 10, 5),
        );
        serveur.remettreAZero();

        final r = await a.moteur.synchroniser();

        expect(r.remiseAZero, isTrue);
        expect(await a.lesBandes(), isEmpty);
        expect(r.saisiesPerdues, greaterThanOrEqualTo(1));
      },
    );
  });
}
