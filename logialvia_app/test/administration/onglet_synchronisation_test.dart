import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/administration/presentation/screens/widgets/onglet_synchronisation.dart';
import 'package:logialvia_app/administration/presentation/viewmodels/synchronisation_view_model.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/widgets/app_button.dart';
import 'package:logialvia_app/core/sync/depot_etat_synchronisation.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/depot_journal_synchronisation.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/planificateur_synchronisation.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:provider/provider.dart';

/// L'onglet « Synchronisation » : état, historique, refusés, cohérence.
void main() {
  late AppDatabase db;
  late PlanificateurSynchronisation planificateur;
  late SynchronisationViewModel vm;
  late Directory export;

  setUpAll(() => initializeDateFormatting('fr_FR'));

  setUp(() {
    db = AppDatabase.enMemoire();
    final preferences = PreferencesPosteRepository(db);
    final client = MockClient((_) async => http.Response('{}', 200));
    final depot = DepotJetonSyncMemoire();
    planificateur = PlanificateurSynchronisation(
      moteur: MoteurSynchronisationPoste(
        preferences: preferences,
        depot: depot,
        appairage: ServiceAppairage(
          preferences: preferences,
          depot: depot,
          client: client,
        ),
        tables: [TableClientsPoste(db)],
        client: client,
      ),
    );
    export = Directory.systemTemp.createTempSync('logialvia_export');
    vm = SynchronisationViewModel(
      planificateur,
      DepotJournalSynchronisation(db),
      DepotEtatSynchronisation(db),
      export,
    );
  });

  tearDown(() async {
    vm.dispose();
    planificateur.dispose();
    await db.close();
    if (export.existsSync()) export.deleteSync(recursive: true);
  });

  Future<void> afficher(WidgetTester t) async {
    await vm.charger();
    await t.binding.setSurfaceSize(const Size(1300, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<SynchronisationViewModel>.value(
            value: vm,
            child: const SingleChildScrollView(child: OngletSynchronisation()),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<String> client(String nom, {String statut = 'pending'}) async {
    await db
        .into(db.clients)
        .insert(ClientsCompanion.insert(nom: nom, syncStatus: Value(statut)));
    return (await (db.select(
      db.clients,
    )..where((c) => c.nom.equals(nom))).getSingle()).id;
  }

  testWidgets(
    'poste neuf : quatre blocs, rien en attente, états vides explicites',
    (t) async {
      await afficher(t);

      expect(find.text('État du poste'), findsOneWidget);
      expect(
        find.text('Historique des 10 dernières tentatives'),
        findsOneWidget,
      );
      expect(find.text('Refusés par le serveur'), findsOneWidget);
      expect(find.text('Cohérence'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
      expect(find.textContaining('EN ATTENTE · À JOUR'), findsOneWidget);
      expect(
        find.textContaining('Dernière réception : Jamais'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Aucune tentative enregistrée'),
        findsOneWidget,
      );
      expect(find.textContaining('Aucune ligne refusée'), findsOneWidget);
      expect(find.byKey(const Key('bouton-synchroniser')), findsOneWidget);
    },
  );

  testWidgets(
    'le compteur dit ce qui attend, l\'historique montre les cycles',
    (t) async {
      await client('A');
      await client('B');
      await DepotJournalSynchronisation(db).enregistrer(
        debut: DateTime(2026, 11, 11, 9, 30),
        duree: const Duration(seconds: 1),
        declencheur: 'manuel',
        rapport: const RapportSynchronisation(
          IssueSynchronisation.terminee,
          'ok',
          recues: 7,
          envoyees: 3,
        ),
      );
      await afficher(t);

      expect(find.textContaining('EN ATTENTE'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byKey(const Key('synchro-historique')), findsOneWidget);
      expect(find.text('Réussie'), findsOneWidget);
      expect(find.text('Manuel'), findsOneWidget);
      expect(
        find.textContaining('Dernière réception : 11/11/2026'),
        findsOneWidget,
      );
      expect(find.textContaining('Dernier envoi : 11/11/2026'), findsOneWidget);
    },
  );

  testWidgets('une ligne refusée : motif, filtre par table, « Remettre en file »', (
    t,
  ) async {
    final id = await client('Dupont');
    await TableClientsPoste(db).marquerConflit(id, 'Téléphone invalide');
    await afficher(t);

    expect(find.text('Clients · Dupont'), findsOneWidget);
    expect(find.text('Téléphone invalide'), findsOneWidget);
    expect(find.byKey(const Key('filtre-refus-clients')), findsOneWidget);

    // Le bouton existe pour la ligne ; la même action passe ici par le ViewModel
    // (le toast du bouton lance un minuteur que le faux temps du test n'attend pas).
    expect(find.widgetWithText(AppButton, 'Remettre en file'), findsOneWidget);
    await t.runAsync(() => vm.remettreEnFile(table: 'clients', id: id));
    planificateur.dispose();
    await t.pump();

    expect(find.text('Clients · Dupont'), findsNothing);
    expect(find.textContaining('Aucune ligne refusée'), findsOneWidget);
    expect((await db.select(db.clients).get()).single.syncStatus, 'pending');
  });

  testWidgets('« Vérifier la cohérence » donne le résultat table par table', (
    t,
  ) async {
    await client('A', statut: 'synced');
    final refuse = await client('B');
    await TableClientsPoste(db).marquerConflit(refuse, 'refus');
    await afficher(t);

    expect(find.byKey(const Key('coherence-resume')), findsNothing);
    await t.tap(find.byKey(const Key('verifier-coherence')));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('coherence-tableau')), findsOneWidget);
    expect(
      find.text('Poste non appairé : contrôle local seulement.'),
      findsOneWidget,
      reason: 'hors appairage, seul le contrôle local est possible',
    );
    expect(
      find.textContaining('1 table(s) avec des lignes refusées'),
      findsOneWidget,
    );
    expect(find.text('1 écart(s)'), findsOneWidget);
  });

  testWidgets(
    '« Exporter le journal » écrit un CSV dans le dossier d\'export',
    (t) async {
      await DepotJournalSynchronisation(db).enregistrer(
        debut: DateTime(2026, 11, 11, 9),
        duree: const Duration(seconds: 1),
        declencheur: 'routine',
        rapport: const RapportSynchronisation(
          IssueSynchronisation.terminee,
          'ok',
        ),
      );
      await afficher(t);

      await t.runAsync(() async {
        await vm.exporterJournal();
      });

      final fichiers = export
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      expect(fichiers, hasLength(1));
      expect(fichiers.single.readAsStringSync(), contains('routine'));
    },
  );
}
