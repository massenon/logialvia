import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/planificateur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
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

  testWidgets('poste jamais appairé : rien (il fonctionne seul, hors ligne)', (
    t,
  ) async {
    await t.runAsync(planificateur.demarrer);
    await afficher(t);
    expect(find.byKey(const Key('indicateur-synchro')), findsNothing);
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
    expect(infobulle(t), contains('Cliquer pour synchroniser maintenant'));
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

  testWidgets('un clic lance une synchronisation', (t) async {
    await t.runAsync(() async {
      await appairer();
      await planificateur.demarrer();
    });
    await afficher(t);
    final avant = serveur.journal.where((j) => j.contains('pull')).length;

    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('indicateur-synchro')));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    expect(serveur.journal.where((j) => j.contains('pull')).length, avant + 1);
  });
}
