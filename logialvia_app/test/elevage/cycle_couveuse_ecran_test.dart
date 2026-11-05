import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/cycle_couveuse_repository_drift.dart';
import 'package:logialvia_app/elevage/domain/entities/cycle_incubation.dart';
import 'package:logialvia_app/elevage/presentation/screens/cycle_couveuse_screen.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/cycle_couveuse_view_model.dart';
import 'package:provider/provider.dart';

/// L'écran Cycle Couveuse, restructuré pour l'incubation continue.
///
/// Le suivi multi-âges existait dans le domaine depuis v21 — machines,
/// mirages, sous-lots, TER, alertes — mais l'écran n'en exposait qu'une
/// partie : on ne pouvait **déclarer aucun incubateur**, la date de référence
/// n'était réglable nulle part, et la chaîne des remplacements n'était visible
/// dans aucun écran. Un référentiel qu'aucun écran n'alimente est un
/// référentiel vide ; une lignée que personne ne voit ne trace rien.
///
/// Ces tests montent l'écran pour de bon : ils vérifient que les quatre
/// sections répondent, pas seulement que le ViewModel calcule juste.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late AppDatabase db;
  late CycleCouveuseViewModel vm;

  final reference = DateTime(2026, 8, 20);

  setUp(() async {
    db = AppDatabase.enMemoire();
    vm = CycleCouveuseViewModel(CycleCouveuseRepositoryDrift(db));
    await vm.charger();
    vm.definirReference(reference);
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  Future<void> afficher(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ChangeNotifierProvider<CycleCouveuseViewModel>.value(
          value: vm,
          child: const Scaffold(body: CycleCouveuseScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<CycleIncubation> creer({
    EspeceCouvable espece = EspeceCouvable.goliath,
    DateTime? date,
    int oeufs = 200,
    int? machineId,
  }) async {
    final resultat = await vm.creerCycle(
      espece: espece,
      dateChargement: date ?? DateTime(2026, 8, 1),
      oeufsCharges: oeufs,
      machineId: machineId,
    );
    return (resultat as Succes<CycleIncubation>).valeur;
  }

  Future<MachineIncubateur> creerMachine({
    String code = 'INC-01',
    int? capacite,
  }) async {
    final resultat = await vm.creerMachine(
      code: code,
      libelle: 'Couveuse atelier',
      capaciteOeufs: capacite,
    );
    return (resultat as Succes<MachineIncubateur>).valeur;
  }

  group("L'écran s'affiche sans lever d'exception", () {
    testWidgets('couvoir vide', (tester) async {
      await afficher(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Cycle Couveuse'), findsOneWidget);
    });

    testWidgets('couvoir peuplé, avec machines et lots', (tester) async {
      final machine = await creerMachine(capacite: 528);
      await creer(machineId: machine.id);
      await creer(
        espece: EspeceCouvable.pintade,
        date: DateTime(2026, 8, 10),
        oeufs: 150,
        machineId: machine.id,
      );
      await afficher(tester);
      expect(tester.takeException(), isNull);
    });
  });

  group('Parc d\'incubateurs', () {
    testWidgets('sans machine, la section le dit au lieu de rester vide', (
      tester,
    ) async {
      await afficher(tester);
      expect(find.text('Parc d\'Incubateurs'), findsOneWidget);
      expect(find.textContaining('Aucun incubateur déclaré'), findsOneWidget);
    });

    testWidgets('une machine affiche son occupation réelle', (tester) async {
      final machine = await creerMachine(capacite: 500);
      final lot = await creer(oeufs: 200, machineId: machine.id);
      // 20 clairs retires au premier mirage : ils ne prennent plus de place.
      await vm.enregistrerMirage(
        lot: lot,
        jour: EspeceCouvable.jourMirage1,
        oeufsRetires: 20,
      );

      await afficher(tester);

      expect(find.text('INC-01'), findsWidgets);
      expect(find.text('180 / 500 œufs'), findsOneWidget);
    });

    testWidgets('sans capacité annoncée, aucun taux n\'est inventé', (
      tester,
    ) async {
      final machine = await creerMachine();
      await creer(oeufs: 120, machineId: machine.id);

      await afficher(tester);

      expect(find.text('120 œufs en incubation'), findsOneWidget);
      expect(find.textContaining('Capacité non renseignée'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('une surcharge est signalée, jamais bloquée', (tester) async {
      final machine = await creerMachine(capacite: 100);
      await creer(oeufs: 250, machineId: machine.id);

      await afficher(tester);

      expect(find.text('250 / 100 œufs'), findsOneWidget);
      expect(find.text('Capacité annoncée dépassée'), findsOneWidget);
    });
  });

  group('Date de référence', () {
    testWidgets('la situation affichée est datée', (tester) async {
      await creer();
      await afficher(tester);

      expect(find.textContaining('Situation au'), findsOneWidget);
      expect(find.textContaining('20/08/2026'), findsWidgets);
    });

    test('l\'âge et les alertes suivent la date choisie', () async {
      await creer(date: DateTime(2026, 8, 1));

      vm.definirReference(DateTime(2026, 8, 8));
      expect(vm.tousLesLots.first.ageJours(vm.reference), 7);
      expect(vm.alertes, isNotEmpty); // le mirage 1 est dû

      vm.definirReference(DateTime(2026, 8, 3));
      expect(vm.tousLesLots.first.ageJours(vm.reference), 2);
      expect(vm.alertes, isEmpty); // rien n'est encore dû
    });
  });

  group('Prochaines échéances', () {
    testWidgets('les échéances à venir sont séparées de celles qui sont dues', (
      tester,
    ) async {
      // Charge le 2026-08-15 : le mirage 1 tombe le 22, soit dans 2 jours.
      await creer(date: DateTime(2026, 8, 15));
      await afficher(tester);

      expect(find.textContaining('dans les 3 prochains jours'), findsOneWidget);
    });
  });

  group('Historique des remplacements', () {
    testWidgets('la lignée s\'ouvre depuis la ligne du lot', (tester) async {
      final machine = await creerMachine(capacite: 400);
      final parent = await creer(oeufs: 200, machineId: machine.id);
      await vm.enregistrerEclosion(
        cycle: parent,
        poussinsEclos: 150,
        oeufsPerdus: 50,
        oeufsRemplacement: 180,
        dateRemplacement: DateTime(2026, 8, 22),
      );

      await afficher(tester);

      final bouton = find.byTooltip('Historique des remplacements');
      expect(bouton, findsWidgets);

      await tester.tap(bouton.first);
      await tester.pumpAndSettle();

      expect(find.text('Historique des Remplacements'), findsOneWidget);
      expect(
        find.textContaining('2 occupation(s) successive(s)'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('un lot sans remplacement n\'affiche pas d\'historique', (
      tester,
    ) async {
      await creer();
      await afficher(tester);
      expect(find.byTooltip('Historique des remplacements'), findsNothing);
    });

    test('le TER de la lignée pondère toutes les occupations', () async {
      final parent = await creer(oeufs: 200, date: DateTime(2026, 8, 1));
      await vm.enregistrerMirage(
        lot: parent,
        jour: EspeceCouvable.jourMirage1,
        oeufsRetires: 20,
      );
      await vm.enregistrerMirage(
        lot: vm.tousLesLots.firstWhere((l) => l.id == parent.id),
        jour: EspeceCouvable.jourMirage2,
        oeufsRetires: 10,
      );
      await vm.enregistrerEclosion(
        cycle: vm.tousLesLots.firstWhere((l) => l.id == parent.id),
        poussinsEclos: 153,
        oeufsPerdus: 17,
        oeufsRemplacement: 200,
        dateRemplacement: DateTime(2026, 8, 22),
      );

      final racine = vm.tousLesLots.firstWhere((l) => l.id == parent.id);

      // ⚠️ Le TER est daté : à une date où l'éclosion n'était pas encore
      // prévue, il n'existe pas. Renvoyer 0 laisserait croire à un échec.
      expect(vm.terDeLaLignee(racine.id), isNull);

      // Passé le terme : 153 / (200 - 30) = 90 %. Le sous-lot n'a pas encore
      // éclos, il ne pèse donc pas dans la moyenne.
      vm.definirReference(DateTime(2026, 8, 25));
      expect(vm.terDeLaLignee(racine.id), closeTo(90, 0.01));
    });
  });

  group('Capacité du parc', () {
    test('reste nulle tant qu\'aucune machine ne l\'annonce', () async {
      await creerMachine();
      expect(vm.capaciteTotale, isNull);
    });

    test('additionne les seules capacités connues', () async {
      await creerMachine(code: 'INC-01', capacite: 500);
      await creerMachine(code: 'INC-02', capacite: 300);
      await creerMachine(code: 'INC-03');
      expect(vm.capaciteTotale, 800);
    });
  });
}
