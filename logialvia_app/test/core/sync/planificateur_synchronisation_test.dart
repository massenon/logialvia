import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/data/seed/modules_actifs_seeder.dart';
import 'package:logialvia_app/administration/data/sync/table_modules_actifs_poste.dart';
import 'package:logialvia_app/commercial/data/repositories/clients_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/planificateur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';

import 'faux_serveur_sync.dart';

/// Les déclencheurs de synchronisation (blueprint §3 et §5). Durées réelles,
/// ramenées à quelques dizaines de millisecondes.
void main() {
  late AppDatabase db;
  late FauxServeurSync serveur;
  late PreferencesPosteRepository preferences;
  late DepotJetonSyncMemoire depot;
  late ServiceAppairage appairage;
  late MoteurSynchronisationPoste moteur;
  late PlanificateurSynchronisation planificateur;
  late List<RapportSynchronisation> rapports;

  const ping = Duration(milliseconds: 25);
  const geste = Duration(milliseconds: 40);

  setUp(() async {
    db = AppDatabase.enMemoire();
    serveur = FauxServeurSync();
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: serveur.client,
    );
    moteur = MoteurSynchronisationPoste(
      preferences: preferences,
      depot: depot,
      appairage: appairage,
      tables: [TableModulesActifsPoste(db), TableClientsPoste(db)],
      client: serveur.client,
    );
    rapports = [];
    planificateur = PlanificateurSynchronisation(
      moteur: moteur,
      intervalleDemande: ping,
      intervalleRoutine: const Duration(hours: 1),
      delaiGeste: geste,
      apresSynchronisation: rapports.add,
    );
    await ModulesActifsSeeder(db).executer();
  });

  tearDown(() async {
    planificateur.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await db.close();
  });

  Future<void> appairer() async {
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }

  Future<void> attendre(bool Function() condition, {String? raison}) async {
    final fin = DateTime.now().add(const Duration(seconds: 3));
    while (!condition()) {
      if (DateTime.now().isAfter(fin)) {
        fail(raison ?? 'condition jamais remplie');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  int pulls() => serveur.journal.where((j) => j == 'GET /api/sync/pull').length;
  int demandes() =>
      serveur.journal.where((j) => j == 'GET /api/sync/demande').length;
  int pushs() =>
      serveur.journal.where((j) => j == 'POST /api/sync/push').length;
  Future<void> pause([int ms = 150]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('poste non appairé : suspendu, aucun appel, aucun minuteur', () async {
    await planificateur.demarrer();
    await pause();

    expect(planificateur.suspendu, isTrue);
    expect(serveur.journal, isEmpty);
  });

  test(
    'à l\'ouverture d\'un poste appairé : une synchronisation part aussitôt',
    () async {
      await appairer();
      await planificateur.demarrer();

      expect(pulls(), 1);
      expect(planificateur.dernierRapport!.reussie, isTrue);
      expect(rapports, hasLength(1));
    },
  );

  test(
    '« synchronise maintenant » du web : servie une fois, le poste synchronise',
    () async {
      await appairer();
      await planificateur.demarrer();
      final avant = pulls();

      serveur.demandeSynchro = true;
      await attendre(
        () => pulls() > avant,
        raison: 'la demande n\'a pas déclenché de synchronisation',
      );
      final apres = pulls();
      await pause(200);

      expect(pulls(), apres, reason: 'une seule synchronisation par demande');
      expect(
        demandes(),
        greaterThan(2),
        reason: 'le poste continue d\'interroger',
      );
    },
  );

  test(
    '« renvoyer vers ce poste » : tirage COMPLET puis acquittement, drapeau baissé',
    () async {
      serveur.ajouterClient('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Client');
      await appairer();
      await planificateur.demarrer();
      expect(await preferences.curseurTirage(), isNotNull);
      final avant = pulls();

      // Le poste a perdu des données : il a besoin de tout, pas seulement du neuf.
      await db.delete(db.clients).go();
      serveur.resyncDemandee = true;
      await attendre(
        () => serveur.acquittements > 0,
        raison: 'jamais acquitté',
      );

      expect(pulls(), greaterThan(avant));
      expect(
        await db.select(db.clients).get(),
        hasLength(1),
        reason: 'tirage complet : le client est revenu',
      );
      expect(serveur.resyncDemandee, isFalse);
      final acquittements = serveur.acquittements;
      await pause(200);
      expect(
        serveur.acquittements,
        acquittements,
        reason: 'une fois seulement',
      );
    },
  );

  test(
    'le serveur n\'est acquitté QUE si le tirage complet a réussi',
    () async {
      await appairer();
      await planificateur.demarrer();
      serveur.panneAuTirageDePage = 1;
      serveur.resyncDemandee = true;

      await attendre(
        () => rapports.length >= 2,
        raison: 'pas de nouvelle synchronisation',
      );
      expect(rapports.last.reussie, isFalse);
      expect(serveur.acquittements, 0);
      expect(
        serveur.resyncDemandee,
        isTrue,
        reason: 'le drapeau reste levé : il sera redemandé',
      );

      await attendre(
        () => serveur.acquittements > 0,
        raison: 'jamais acquitté après reprise',
      );
    },
  );

  test(
    'un geste : la saisie part après le délai, une rafale = un seul envoi',
    () async {
      await appairer();
      await planificateur.demarrer();
      final repo = ClientsRepositoryDrift(db);
      final pushsAvant = pushs();

      for (var i = 0; i < 5; i++) {
        await repo.creerClient(nom: 'Rafale $i');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await attendre(
        () => serveur.clients.length == 5,
        raison: 'les 5 clients ne sont pas partis',
      );

      expect(
        pushs() - pushsAvant,
        1,
        reason: 'temporisation : une rafale ne fait pas 5 envois',
      );
      expect(
        (await db.select(db.clients).get()).every(
          (c) => c.syncStatus == 'synced',
        ),
        isTrue,
      );
    },
  );

  test(
    'pas de boucle : ses propres écritures d\'accusé ne relancent rien',
    () async {
      await appairer();
      await planificateur.demarrer();
      await ClientsRepositoryDrift(db).creerClient(nom: 'Une fois');
      await attendre(() => serveur.clients.length == 1);
      await pause(150);
      // Exactement : 1 synchronisation à l'ouverture + 1 pour le geste. Sans la
      // garde « rien à envoyer », l'écriture de l'accusé en relancerait une 3e.
      expect(pulls(), 2, reason: 'ouverture + geste, pas une de plus');
      final a = pushs();
      final p = pulls();

      await pause(300);

      expect(pushs(), a);
      expect(
        pulls(),
        p,
        reason: 'rien de nouveau à envoyer : aucune synchronisation relancée',
      );
    },
  );

  test(
    'poste révoqué : suspension, plus aucun appel, reprise après un nouvel appairage',
    () async {
      await appairer();
      await planificateur.demarrer();
      serveur.jetonRevoque = true;

      await attendre(() => planificateur.suspendu, raison: 'jamais suspendu');
      expect(planificateur.dernierRapport!.issue, IssueSynchronisation.revoque);
      expect(await depot.lire(), isNull);
      final n = serveur.journal.length;
      await pause(250);
      expect(
        serveur.journal.length,
        n,
        reason: 'plus un seul appel : le jeton est mort',
      );

      // Nouvel appairage.
      serveur.jetonRevoque = false;
      await appairer();
      planificateur.reprendre();
      await attendre(
        () => serveur.journal.length > n,
        raison: 'pas de reprise',
      );
      expect(planificateur.suspendu, isFalse);
    },
  );

  test(
    'révocation découverte par une SYNCHRONISATION (pas par la demande) : suspension aussi',
    () async {
      final lent = PlanificateurSynchronisation(
        moteur: moteur,
        intervalleDemande: const Duration(hours: 1),
        intervalleRoutine: const Duration(hours: 1),
      );
      addTearDown(lent.dispose);
      await appairer();
      await lent.demarrer();
      serveur.jetonRevoque = true;

      final r = await lent.synchroniserMaintenant();

      expect(r!.issue, IssueSynchronisation.revoque);
      expect(
        lent.suspendu,
        isTrue,
        reason: 'un 401 en synchronisant suspend aussi',
      );
    },
  );

  test(
    'hors ligne : le poste réessaie sans bruit et rattrape son retard',
    () async {
      await appairer();
      await planificateur.demarrer();
      serveur.horsLigne = true;
      await ClientsRepositoryDrift(db).creerClient(nom: 'Pendant la coupure');
      await pause(200);

      expect(
        planificateur.suspendu,
        isFalse,
        reason: 'hors ligne n\'est pas une panne',
      );
      expect(serveur.clients, isEmpty);

      serveur.horsLigne = false;
      serveur.demandeSynchro = true;
      await attendre(
        () => serveur.clients.length == 1,
        raison: 'rattrapage jamais fait',
      );
    },
  );

  test(
    'après chaque synchronisation, le rapport est transmis (ex. rechargement des modules)',
    () async {
      serveur.ajouterModule('ovins', actif: true, espece: 'ovins');
      await appairer();
      await planificateur.demarrer();

      expect(rapports.single.referentielsMisAJour, 1);
    },
  );

  test('arrêté (dispose) : plus aucun appel', () async {
    await appairer();
    await planificateur.demarrer();
    planificateur.dispose();
    final n = serveur.journal.length;
    serveur.demandeSynchro = true;

    await pause(250);

    expect(serveur.journal.length, n);
  });

  test(
    'bouton « Synchroniser maintenant » : une seule exécution à la fois',
    () async {
      await appairer();
      final premiere = planificateur.synchroniserMaintenant();
      final seconde = await planificateur.synchroniserMaintenant();

      expect(seconde, isNull);
      expect((await premiere)!.reussie, isTrue);
    },
  );

  test(
    'bouton après un 401 : un poste suspendu peut se resynchroniser s\'il est de nouveau appairé',
    () async {
      await appairer();
      await planificateur.demarrer();
      serveur.jetonRevoque = true;
      await attendre(() => planificateur.suspendu);

      serveur.jetonRevoque = false;
      await appairer();
      final r = await planificateur.synchroniserMaintenant();

      expect(r!.reussie, isTrue);
      expect(planificateur.suspendu, isFalse);
    },
  );

  group('à la fermeture', () {
    test('une saisie en attente est envoyée avant de quitter', () async {
      await appairer();
      await planificateur.demarrer();
      await ClientsRepositoryDrift(db).creerClient(nom: 'Avant de fermer');

      final reussi = await planificateur.synchroniserALaFermeture();

      expect(reussi, isTrue);
      expect(serveur.clients, hasLength(1));
      expect((await db.select(db.clients).get()).single.syncStatus, 'synced');
    });

    test(
      'rien à envoyer : aucun appel, la fenêtre se ferme tout de suite',
      () async {
        await appairer();
        await planificateur.demarrer();
        final n = serveur.journal.length;

        final reussi = await planificateur.synchroniserALaFermeture();

        expect(reussi, isFalse);
        expect(serveur.journal.length, n);
      },
    );

    test('poste non appairé ou suspendu : rien n\'est tenté', () async {
      await planificateur.demarrer(); // non appairé : suspendu
      await ClientsRepositoryDrift(db).creerClient(nom: 'Local');

      expect(await planificateur.synchroniserALaFermeture(), isFalse);
      expect(serveur.journal, isEmpty);
    });

    test(
      'serveur lent : borné au délai, la fermeture n\'attend pas le réseau',
      () async {
        await appairer();
        await planificateur.demarrer();
        await ClientsRepositoryDrift(db).creerClient(nom: 'Réseau lent');
        serveur.delaiReponse = const Duration(seconds: 2);
        final debut = DateTime.now();

        final reussi = await planificateur.synchroniserALaFermeture(
          delai: const Duration(milliseconds: 150),
        );

        expect(reussi, isFalse);
        expect(
          DateTime.now().difference(debut),
          lessThan(const Duration(seconds: 1)),
        );
        expect(
          (await db.select(db.clients).get()).single.syncStatus,
          'pending',
          reason:
              'la saisie n\'est pas perdue : elle repartira à la prochaine ouverture',
        );
      },
    );

    test('hors ligne : renvoie false sans bloquer, saisie conservée', () async {
      await appairer();
      await planificateur.demarrer();
      await ClientsRepositoryDrift(db).creerClient(nom: 'Coupure');
      serveur.horsLigne = true;

      expect(await planificateur.synchroniserALaFermeture(), isFalse);
      expect((await db.select(db.clients).get()).single.syncStatus, 'pending');
    });
  });
}
