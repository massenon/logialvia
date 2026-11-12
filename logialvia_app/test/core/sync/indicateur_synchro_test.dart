import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/identifiant_poste.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/planificateur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:logialvia_app/core/widgets/app_button.dart';
import 'package:logialvia_app/core/widgets/shell/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'faux_serveur_sync.dart';

/// L'indicateur de la barre du haut dit l'état RÉEL de la synchronisation.
void main() {
  late AppDatabase db;
  late FauxServeurSync serveur;
  late PlanificateurSynchronisation planificateur;
  late DepotJetonSyncMemoire depot;
  late PreferencesPosteRepository preferences;

  setUpAll(() => initializeDateFormatting('fr_FR'));

  setUp(() {
    db = AppDatabase.enMemoire();
    serveur = FauxServeurSync();
    preferences = PreferencesPosteRepository(db);
    depot = DepotJetonSyncMemoire();
    final appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: serveur.client,
    );
    planificateur = PlanificateurSynchronisation(
      moteur: MoteurSynchronisationPoste(
        preferences: preferences,
        depot: depot,
        appairage: appairage,
        tables: [TableClientsPoste(db)],
        client: serveur.client,
      ),
      intervalleDemande: const Duration(hours: 1),
      intervalleRoutine: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    planificateur.dispose();
    await db.close();
  });

  Future<void> afficher(WidgetTester t, {bool avecPlanificateur = true}) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: avecPlanificateur
              ? ChangeNotifierProvider<PlanificateurSynchronisation>.value(
                  value: planificateur,
                  child: const IndicateurSynchro(),
                )
              : const IndicateurSynchro(),
        ),
      ),
    );
  }

  Future<void> appairer() async {
    await preferences.definirAdresseServeur('http://serveur.test');
    await preferences.memoriserAppairage(
      codePoste: 'P1',
      compte: 'g',
      le: DateTime.now(),
    );
    await depot.ecrire('1|jeton');
  }

  Icon icone(WidgetTester t) => t.widget<Icon>(
    find.descendant(
      of: find.byKey(const Key('indicateur-synchro')),
      matching: find.byType(Icon),
    ),
  );

  String infobulle(WidgetTester t) => t
      .widget<IconButton>(find.byKey(const Key('indicateur-synchro')))
      .tooltip!;

  testWidgets('sans planificateur dans l\'arbre : rien, et pas d\'erreur', (
    t,
  ) async {
    await afficher(t, avecPlanificateur: false);
    expect(find.byKey(const Key('indicateur-synchro')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('poste jamais appairé : visible, il le dit (hors ligne)', (
    t,
  ) async {
    await t.runAsync(planificateur.demarrer);
    await afficher(t);
    expect(find.byKey(const Key('indicateur-synchro')), findsOneWidget);
    expect(icone(t).icon, Symbols.link_off);
    expect(infobulle(t), contains('Poste non appairé'));
    expect(infobulle(t), contains('Paramètres > Appairage'));

    // Le modal s'ouvre, dit la même chose, et « Synchroniser maintenant » est inactif.
    await t.tap(find.byKey(const Key('indicateur-synchro')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('synchro-modale-etat')), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const Key('synchro-modale-resume'))).data,
      contains('Poste non appairé'),
    );
    final bouton = t.widget<AppButton>(
      find.byKey(const Key('synchro-maintenant')),
    );
    expect(bouton.onPressed, isNull);
  });

  testWidgets('synchronisé : nuage coché, heure de la synchronisation', (
    t,
  ) async {
    await t.runAsync(() async {
      await appairer();
      await planificateur.demarrer();
    });
    await afficher(t);

    expect(icone(t).icon, Symbols.cloud_done);
    expect(infobulle(t), startsWith('Synchronisé à '));
    expect(
      infobulle(t),
      contains('Cliquer pour le détail de la synchronisation'),
    );
  });

  testWidgets(
    'hors ligne : nuage barré, saisies conservées — pas une erreur rouge',
    (t) async {
      await t.runAsync(() async {
        await appairer();
        serveur.horsLigne = true;
        await planificateur.synchroniserMaintenant();
      });
      await afficher(t);

      expect(icone(t).icon, Symbols.cloud_off);
      expect(icone(t).color, isNot(const Color(0xFFB3261E)));
      expect(infobulle(t), contains('saisies sont conservées'));
    },
  );

  testWidgets('révoqué : le dit et renvoie vers Paramètres > Appairage', (
    t,
  ) async {
    await t.runAsync(() async {
      await appairer();
      await planificateur.demarrer();
      serveur.jetonRevoque = true;
      await planificateur.synchroniserMaintenant();
    });
    await afficher(t);

    expect(icone(t).icon, Symbols.link_off);
    expect(infobulle(t), contains('Paramètres > Appairage'));
  });

  testWidgets('refus du serveur : à vérifier, avec le message', (t) async {
    await t.runAsync(() async {
      await appairer();
      serveur.panneAuTirageDePage = 1;
      await planificateur.synchroniserMaintenant();
    });
    await afficher(t);

    expect(icone(t).icon, Symbols.sync_problem);
    expect(infobulle(t), contains('Erreur interne'));
  });

  testWidgets(
    'un clic ouvre le modal ; « Synchroniser maintenant » lance un cycle',
    (t) async {
      await t.runAsync(() async {
        await appairer();
        await planificateur.demarrer();
      });
      await afficher(t);
      final avant = serveur.journal.where((j) => j.contains('pull')).length;

      // Le clic seul ne synchronise plus : il ouvre le détail.
      await t.tap(find.byKey(const Key('indicateur-synchro')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('synchro-modale-etat')), findsOneWidget);
      expect(find.byKey(const Key('synchro-modale-resume')), findsOneWidget);
      expect(serveur.journal.where((j) => j.contains('pull')).length, avant);

      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('synchro-maintenant')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();

      expect(
        serveur.journal.where((j) => j.contains('pull')).length,
        avant + 1,
      );
      expect(find.byKey(const Key('synchro-modale-etat')), findsNothing);
    },
  );

  testWidgets('le modal dit l\'état du dernier cycle et se ferme', (t) async {
    await t.runAsync(() async {
      await appairer();
      await planificateur.synchroniserMaintenant();
    });
    await afficher(t);

    await t.tap(find.byKey(const Key('indicateur-synchro')));
    await t.pumpAndSettle();

    expect(find.text('Synchronisation'), findsWidgets);
    expect(find.textContaining('Dernière tentative à'), findsOneWidget);
    expect(find.text('Envoyées au serveur'), findsOneWidget);
    expect(find.text('Reçues des autres postes'), findsOneWidget);

    await t.tap(find.text('Fermer'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('synchro-modale-etat')), findsNothing);
  });

  testWidgets(
    'horloge en avance : icône d\'horloge, et la modale de synchronisation le dit',
    (t) async {
      addTearDown(() => horlogePoste = DateTime.now);
      await t.runAsync(() async {
        await appairer();
        horlogePoste = () => DateTime.now().add(const Duration(days: 2));
        await planificateur.synchroniserMaintenant();
      });
      await afficher(t);

      expect(icone(t).icon, Symbols.schedule);
      expect(infobulle(t), contains('avance de 2 jours'));

      await t.tap(find.byKey(const Key('indicateur-synchro')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('synchro-modale-horloge')), findsOneWidget);
      expect(
        find.textContaining('corrigez la date et l\'heure du poste'),
        findsWidgets,
      );
      await t.tap(find.text('Fermer'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('synchro-modale-horloge')), findsNothing);
    },
  );
}
