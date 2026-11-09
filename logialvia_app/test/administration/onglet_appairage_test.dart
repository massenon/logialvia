import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/commercial/data/repositories/clients_repository_drift.dart';
import 'package:logialvia_app/commercial/data/sync/table_clients_poste.dart';
import 'package:logialvia_app/core/sync/moteur_synchronisation.dart';
import 'package:logialvia_app/core/sync/planificateur_synchronisation.dart';
import 'package:logialvia_app/administration/presentation/screens/widgets/onglet_appairage.dart';
import 'package:logialvia_app/administration/presentation/viewmodels/appairage_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/sync/depot_jeton_sync.dart';
import 'package:logialvia_app/core/sync/service_appairage.dart';
import 'package:provider/provider.dart';

import '../core/sync/faux_serveur_sync.dart';

/// L'onglet Appairage, de la saisie à l'état affiché, contre un faux serveur.
void main() {
  late AppDatabase db;
  late DepotJetonSyncMemoire depot;
  late AppairageViewModel vm;
  late PlanificateurSynchronisation planificateur;
  late List<http.Request> requetes;
  late Future<http.Response> Function(http.Request) serveur;
  late FauxServeurSync fauxSync;

  http.Response json(int s, Map<String, dynamic> c) => http.Response(
    jsonEncode(c),
    s,
    headers: {'content-type': 'application/json'},
  );

  setUpAll(() => initializeDateFormatting('fr_FR'));

  setUp(() async {
    db = AppDatabase.enMemoire();
    depot = DepotJetonSyncMemoire();
    requetes = [];
    fauxSync = FauxServeurSync();
    serveur = (_) async => json(200, {
      'token': '1|jeton',
      'must_change_password': false,
      'poste': {'id': 'x', 'code': 'P3'},
    });
    final preferences = PreferencesPosteRepository(db);
    final client = MockClient((r) {
      requetes.add(r);
      if (r.url.path.startsWith('/api/sync/')) {
        return fauxSync.repondre(r);
      }
      return serveur(r);
    });
    final appairage = ServiceAppairage(
      preferences: preferences,
      depot: depot,
      client: client,
    );
    planificateur = PlanificateurSynchronisation(
      moteur: MoteurSynchronisationPoste(
        preferences: preferences,
        depot: depot,
        appairage: appairage,
        tables: [TableClientsPoste(db)],
        client: client,
      ),
    );
    vm = AppairageViewModel(appairage, planificateur);
    await vm.charger();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  /// `testWidgets` + arrêt des minuteurs du planificateur DANS le corps du test :
  /// un appairage les arme, et testWidgets refuse toute minuterie en attente.
  void cas(String nom, Future<void> Function(WidgetTester) corps) {
    testWidgets(nom, (t) async {
      try {
        await corps(t);
      } finally {
        planificateur.dispose();
      }
    });
  }

  Future<void> afficher(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangeNotifierProvider<AppairageViewModel>.value(
            value: vm,
            child: const SingleChildScrollView(child: OngletAppairage()),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> saisir(WidgetTester t, {String mdp = 'secret'}) async {
    await t.enterText(
      find.byKey(const Key('appairage-adresse')),
      '192.168.1.5:8000',
    );
    await t.enterText(
      find.byKey(const Key('appairage-identifiant')),
      'gerante',
    );
    await t.enterText(find.byKey(const Key('appairage-mot-de-passe')), mdp);
  }

  cas('poste neuf : non appairé, formulaire visible, identifiant affiché', (
    t,
  ) async {
    await afficher(t);

    expect(find.textContaining('Poste non appairé'), findsOneWidget);
    expect(find.text('Appairer ce poste'), findsOneWidget);
    expect(find.text(vm.etat!.identifiantPoste), findsOneWidget);
    expect(find.text('Non attribué'), findsOneWidget);
  });

  cas('le mot de passe est masqué', (t) async {
    await afficher(t);
    final champ = t.widget<TextField>(
      find.byKey(const Key('appairage-mot-de-passe')),
    );
    expect(champ.obscureText, isTrue);
  });

  cas('appairer : bandeau vert, code du poste, formulaire remplacé', (t) async {
    await afficher(t);
    await saisir(t);
    await t.tap(find.text('Appairer'));
    await t.pumpAndSettle();

    expect(
      find.textContaining('Poste appairé au serveur (code P3)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('seuls les CLIENTS sont synchronisés'),
      findsOneWidget,
      reason: 'appairé ne doit pas être pris pour synchronisé',
    );
    expect(find.text('Appairer ce poste'), findsNothing);
    expect(find.text('P3'), findsOneWidget);
    expect(
      requetes.first.url.toString(),
      'http://192.168.1.5:8000/api/auth/login',
    );
  });

  cas('le champ mot de passe est vidé dès l\'envoi', (t) async {
    final attente = Completer<http.Response>();
    serveur = (_) => attente.future;
    await afficher(t);
    await saisir(t, mdp: 'MotSecret123');
    await t.tap(find.text('Appairer'));
    await t.pump();

    final champ = t.widget<TextField>(
      find.byKey(const Key('appairage-mot-de-passe')),
    );
    expect(champ.controller!.text, isEmpty);
    expect(
      find.text('Connexion…'),
      findsOneWidget,
      reason: 'bouton occupé : pas de double envoi',
    );

    attente.complete(
      json(401, {'message': 'Identifiant ou mot de passe incorrect.'}),
    );
    await t.pumpAndSettle();
  });

  cas('refus : le message du serveur est affiché, le formulaire reste', (
    t,
  ) async {
    serveur = (_) async =>
        json(401, {'message': 'Identifiant ou mot de passe incorrect.'});
    await afficher(t);
    await saisir(t);
    await t.tap(find.text('Appairer'));
    await t.pumpAndSettle();

    expect(find.text('Identifiant ou mot de passe incorrect.'), findsOneWidget);
    expect(find.text('Appairer ce poste'), findsOneWidget);
  });

  cas('serveur injoignable : message « hors ligne », pas d\'erreur rouge', (
    t,
  ) async {
    serveur = (_) async => throw http.ClientException('coupé');
    await afficher(t);
    await saisir(t);
    await t.tap(find.text('Appairer'));
    await t.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('appairage-message')),
        matching: find.textContaining('hors ligne'),
      ),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  cas('déconnecter demande confirmation puis efface l\'appairage', (t) async {
    await afficher(t);
    await saisir(t);
    await t.tap(find.text('Appairer'));
    await t.pumpAndSettle();

    await t.tap(find.text('Déconnecter ce poste'));
    await t.pumpAndSettle();
    expect(find.text('Déconnecter ce poste ?'), findsOneWidget);

    // Annuler ne change rien.
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(await depot.lire(), '1|jeton');

    await t.tap(find.text('Déconnecter ce poste'));
    await t.pumpAndSettle();
    await t.tap(find.text('Déconnecter'));
    await t.pumpAndSettle();

    expect(await depot.lire(), isNull);
    expect(find.textContaining('Poste non appairé'), findsOneWidget);
    // Laisse le toast de confirmation expirer (sinon : minuterie en attente).
    await t.pump(const Duration(seconds: 10));
    await t.pumpAndSettle();
  });

  cas('tester la connexion avec un jeton révoqué : repasse non appairé', (
    t,
  ) async {
    await afficher(t);
    await saisir(t);
    await t.tap(find.text('Appairer'));
    await t.pumpAndSettle();

    serveur = (_) async => json(401, {'message': 'Non authentifié.'});
    await t.tap(find.text('Tester la connexion'));
    await t.pumpAndSettle();

    expect(find.textContaining('n\'est plus appairé'), findsOneWidget);
    expect(find.text('Appairer ce poste'), findsOneWidget);
  });

  cas('Synchroniser maintenant : envoie les clients et dit le résultat', (
    t,
  ) async {
    await afficher(t);
    await saisir(t);
    await t.tap(find.text('Appairer'));
    await t.pumpAndSettle();
    await ClientsRepositoryDrift(db).creerClient(nom: 'Mama Rita');

    await t.tap(find.text('Synchroniser maintenant'));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('synchro-message')), findsOneWidget);
    expect(find.textContaining('Synchronisation terminée'), findsOneWidget);
    expect(find.textContaining('1 envoyée(s)'), findsOneWidget);
    expect(fauxSync.clients, hasLength(1));
  });

  cas('hors ligne : la synchronisation le dit sans erreur rouge', (t) async {
    await afficher(t);
    await saisir(t);
    await t.tap(find.text('Appairer'));
    await t.pumpAndSettle();
    fauxSync.horsLigne = true;

    await t.tap(find.text('Synchroniser maintenant'));
    await t.pumpAndSettle();

    expect(
      find.textContaining('hors ligne, tout reste à envoyer'),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });
}
