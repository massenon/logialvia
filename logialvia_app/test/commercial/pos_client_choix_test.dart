import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/commercial/data/repositories/clients_repository_drift.dart';
import 'package:logialvia_app/commercial/data/repositories/ventes_repository_drift.dart';
import 'package:logialvia_app/commercial/domain/entities/client.dart';
import 'package:logialvia_app/commercial/presentation/screens/widgets/onglet_pos.dart';
import 'package:logialvia_app/commercial/presentation/viewmodels/ventes_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/events/domain_event.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:provider/provider.dart';

/// Le client de la vente se CHOISIT dans la liste : deux « Mama Rita » ne se
/// confondent plus.
void main() {
  late AppDatabase db;
  late VentesViewModel vm;
  late ClientChoix rita1;
  late ClientChoix rita2;
  late ClientChoix dossou;

  setUpAll(() => initializeDateFormatting('fr_FR'));

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    final clients = ClientsRepositoryDrift(db);
    ClientChoix choix(Client c) =>
        ClientChoix(id: c.id, nom: c.nom, telephone: c.telephone);
    rita1 = choix(
      await clients.creerClient(nom: 'Mama Rita', telephone: '97000001'),
    );
    rita2 = choix(
      await clients.creerClient(nom: 'Mama Rita', telephone: '97000002'),
    );
    dossou = choix(await clients.creerClient(nom: 'DOSSOU Félicité'));
    vm = VentesViewModel(VentesRepositoryDrift(db, EventBus()), db);
    await vm.charger();
  });

  tearDown(() async => db.close());

  Future<String> encaisserUnGoliath() async {
    final goliath = (await VentesRepositoryDrift(
      db,
      EventBus(),
    ).chargerCatalogue()).firstWhere((p) => p.nom == 'Goliath mature');
    expect(
      vm.ajouterAuPanier(goliath, quantite: 1, montantGlobal: goliath.prix),
      isNull,
    );
    vm.montantRecu = goliath.prix;
    final r = await vm.encaisser();
    switch (r) {
      case Succes(:final valeur):
        return valeur.reference;
      case Echec(:final message):
        fail('Encaissement refusé : $message');
    }
  }

  Future<String?> clientIdDe(String ref) async => (await (db.select(
    db.ventes,
  )..where((v) => v.ref.equals(ref))).getSingle()).clientId;

  group('suggestions', () {
    test(
      'contient la saisie, casse ignorée ; vide ou sans correspondance : rien',
      () {
        expect(
          vm.suggestionsClients('rita').map((c) => c.id),
          containsAll([rita1.id, rita2.id]),
        );
        expect(vm.suggestionsClients('DOSSOU').map((c) => c.id), [dossou.id]);
        expect(vm.suggestionsClients(''), isEmpty);
        expect(vm.suggestionsClients('   '), isEmpty);
        expect(vm.suggestionsClients('zzz'), isEmpty);
      },
    );

    test('au plus 8 suggestions', () async {
      final repo = ClientsRepositoryDrift(db);
      for (var i = 0; i < 12; i++) {
        await repo.creerClient(nom: 'Client $i');
      }
      await vm.charger();
      expect(vm.suggestionsClients('client'), hasLength(8));
    });

    test('le téléphone distingue deux homonymes', () {
      final r = vm.suggestionsClients('Mama Rita');
      expect(r.map((c) => c.telephone), containsAll(['97000001', '97000002']));
    });
  });

  group('choix du client', () {
    test('choisir mémorise le nom ET l\'identifiant', () {
      vm.choisirClient(rita2);
      expect(vm.client, 'Mama Rita');
      expect(vm.clientId, rita2.id);
    });

    test(
      'retoucher le texte oublie le choix ; le retaper à l\'identique le garde',
      () {
        vm.choisirClient(rita2);
        vm.client = 'Mama Rita'; // le champ renvoie le même texte
        expect(vm.clientId, rita2.id);

        vm.client = 'Mama Rit';
        expect(
          vm.clientId,
          isNull,
          reason: 'le nom affiché n\'est plus celui du client choisi',
        );
      },
    );

    test(
      'nom ambigu sans choix : le dit ; après choix, ou nom unique : non',
      () {
        vm.client = 'Mama Rita';
        expect(vm.clientAmbigu, isTrue);
        vm.choisirClient(rita1);
        expect(vm.clientAmbigu, isFalse);
        vm.client = 'DOSSOU Félicité';
        expect(vm.clientAmbigu, isFalse);
        vm.client = 'Client Comptant';
        expect(vm.clientAmbigu, isFalse);
      },
    );

    test('vider le panier oublie le client choisi', () {
      vm.choisirClient(rita1);
      vm.viderPanier();
      expect(vm.clientId, isNull);
      expect(vm.client, '');
    });
  });

  group('la vente va au BON client', () {
    test(
      'deux « Mama Rita » : celle qui est choisie reçoit la vente',
      () async {
        vm.choisirClient(rita2);
        expect(await clientIdDe(await encaisserUnGoliath()), rita2.id);

        vm.choisirClient(rita1);
        expect(await clientIdDe(await encaisserUnGoliath()), rita1.id);
      },
    );

    test('deux « Mama Rita » tapées à la main : aucune devinée', () async {
      vm.client = 'Mama Rita';
      expect(await clientIdDe(await encaisserUnGoliath()), isNull);
    });

    test('un nom unique tapé à la main : retrouvé quand même', () async {
      vm.client = 'dossou félicité';
      expect(await clientIdDe(await encaisserUnGoliath()), dossou.id);
    });

    test('nom libre : aucun client', () async {
      expect(await clientIdDe(await encaisserUnGoliath()), isNull);
    });

    test(
      'un identifiant périmé (client supprimé entre-temps) retombe sur le nom',
      () async {
        vm.choisirClient(
          const ClientChoix(
            id: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
            nom: 'DOSSOU Félicité',
          ),
        );
        expect(await clientIdDe(await encaisserUnGoliath()), dossou.id);
      },
    );
  });

  group('écran', () {
    Future<void> afficher(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(1300, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<VentesViewModel>.value(
              value: vm,
              child: const SingleChildScrollView(child: OngletPos()),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets(
      'taper propose les clients avec leur téléphone ; en choisir un le sélectionne',
      (t) async {
        await afficher(t);

        await t.enterText(find.byKey(const Key('pos-client')), 'rita');
        await t.pumpAndSettle();
        expect(find.text('97000001'), findsOneWidget);
        expect(find.text('97000002'), findsOneWidget);

        await t.tap(find.byKey(Key('pos-client-${rita2.id}')));
        await t.pumpAndSettle();

        expect(vm.clientId, rita2.id);
        expect(find.byKey(const Key('pos-client-ambigu')), findsNothing);
      },
    );

    testWidgets(
      'nom ambigu tapé sans choisir : un message invite à choisir dans la liste',
      (t) async {
        await afficher(t);

        await t.enterText(find.byKey(const Key('pos-client')), 'Mama Rita');
        await t.pumpAndSettle();

        expect(find.byKey(const Key('pos-client-ambigu')), findsOneWidget);
        expect(
          find.textContaining('choisissez-en un dans la liste'),
          findsOneWidget,
        );
      },
    );

    testWidgets('un nom libre ne déclenche aucune suggestion ni message', (
      t,
    ) async {
      await afficher(t);

      await t.enterText(find.byKey(const Key('pos-client')), 'Client Comptant');
      await t.pumpAndSettle();

      expect(find.byKey(const Key('pos-client-ambigu')), findsNothing);
      expect(vm.clientId, isNull);
    });

    testWidgets('sans client : le champ reste vide et la vente se fait', (
      t,
    ) async {
      await afficher(t);
      expect(find.byKey(const Key('pos-client')), findsOneWidget);
      expect(vm.client, '');
    });
  });
}
