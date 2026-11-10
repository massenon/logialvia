import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/bandes_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/fiche_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/parametres_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/soins_repository_drift.dart';
import 'package:logialvia_app/elevage/data/seed/parametres_elevage_seeder.dart';
import 'package:logialvia_app/elevage/domain/entities/bande.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/entities/soin.dart';
import 'package:logialvia_app/elevage/presentation/screens/fiche_espece_screen.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/fiche_espece_view_model.dart';
import 'package:provider/provider.dart';

/// Mise en bande et projection du calendrier de prophylaxie.
///
/// ## Le point ouvert le plus ancien du projet
///
/// `parametres-elevage.html` annonçait un « calendrier automatique injecté
/// dans Traitements & Prophylaxie des fiches journalières ».
/// `CALENDRIER_PROPHYLAXIE` indexe ses échéances sur le **jour du cycle** —
/// arbitrage tranché par le contenu lui-même : une cure « Jour 1/4 → 4/4 », un
/// anti-stress « post-éclosion », un rappel Newcastle programmé sur l'âge du
/// sujet. Mais **aucune table ne disait quand le cycle commence**, si bien que
/// « J5 » ne se convertissait en aucune date.
///
/// `BANDES.dateMiseEnBande` (v25) est cette date. Ces tests vérifient que la
/// projection est exacte, qu'elle ne suppose rien en l'absence de bande, et
/// qu'une échéance planifiée ne se reprogramme pas.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late AppDatabase db;
  late FicheEspeceViewModel vm;
  late BandesRepositoryDrift bandes;
  late SoinsRepositoryDrift soins;

  const config = ConfigurationsEspeces.goliaths;

  setUp(() async {
    db = AppDatabase.enMemoire();
    // Les 11 echeances reelles du prototype : Goliaths a J1, J5 et J15.
    await ParametresElevageSeeder(db).executer();
    bandes = BandesRepositoryDrift(db);
    soins = SoinsRepositoryDrift(db);
    vm = FicheEspeceViewModel(
      configuration: config,
      repository: FicheElevageRepositoryDrift(db, config),
      parametresRepository: ParametresElevageRepositoryDrift(db),
      bandesRepository: bandes,
      soinsRepository: soins,
    );
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  Future<void> ouvrirLe(DateTime jour) async {
    await vm.charger();
    await vm.changerJour(jour);
  }

  Future<Bande> declarer({
    DateTime? date,
    String code = 'B1',
    int? effectif,
  }) async {
    final resultat = await vm.declarerBande(
      code: code,
      dateMiseEnBande: date ?? DateTime(2026, 8, 1),
      effectifInitial: effectif,
    );
    return (resultat as Succes<Bande>).valeur;
  }

  group('Jour de cycle', () {
    test('la mise en bande est J1, pas J0', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(date: DateTime(2026, 8, 1));

      expect(vm.jourDeCycle, 1);

      await vm.changerJour(DateTime(2026, 8, 5));
      expect(vm.jourDeCycle, 5);
    });

    test('sans bande, aucun jour de cycle n\'est supposé', () async {
      await ouvrirLe(DateTime(2026, 8, 5));

      expect(vm.bande, isNull);
      expect(vm.jourDeCycle, isNull);
      expect(vm.prophylaxieDuJour, isEmpty);
      // Le calendrier existe pour les Goliaths : c'est bien la bande qui
      // manque, et l'écran doit le dire.
      expect(vm.calendrierSansBande, isTrue);
    });

    test('un jour antérieur à la mise en place n\'est pas couvert', () async {
      await ouvrirLe(DateTime(2026, 8, 10));
      await declarer(date: DateTime(2026, 8, 10));

      await vm.changerJour(DateTime(2026, 8, 3));
      expect(vm.bande, isNull);
      expect(vm.jourDeCycle, isNull);
    });

    test('une bande clôturée ne couvre plus les jours suivants', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(date: DateTime(2026, 8, 1));

      await vm.changerJour(DateTime(2026, 8, 20));
      await vm.cloturerBande(DateTime(2026, 8, 20));
      expect(vm.bande, isNotNull);

      await vm.changerJour(DateTime(2026, 8, 21));
      expect(vm.bande, isNull);

      // Mais elle couvre toujours les jours de son cycle.
      await vm.changerJour(DateTime(2026, 8, 15));
      expect(vm.bande, isNotNull);
    });

    test('la clôture ne peut pas précéder la mise en place', () async {
      await ouvrirLe(DateTime(2026, 8, 10));
      await declarer(date: DateTime(2026, 8, 10));

      final resultat = await vm.cloturerBande(DateTime(2026, 8, 1));
      expect(resultat, isA<Echec<void>>());
    });
  });

  group('Projection du calendrier', () {
    test('les échéances du jour sont celles du jour de CYCLE', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(date: DateTime(2026, 8, 1));

      // J1 : Deparasitage.
      expect(vm.prophylaxieDuJour, hasLength(1));
      expect(vm.prophylaxieDuJour.first.echeance.traitement, 'Déparasitage');

      // J5 = 5 aout : Anti-coccidien.
      await vm.changerJour(DateTime(2026, 8, 5));
      expect(
        vm.prophylaxieDuJour.single.echeance.traitement,
        'Anti-coccidien (1/4)',
      );

      // J2 : rien.
      await vm.changerJour(DateTime(2026, 8, 2));
      expect(vm.prophylaxieDuJour, isEmpty);
    });

    test('une bande décalée décale tout le calendrier — ce que le jour du mois '
        'ne ferait pas', () async {
      await ouvrirLe(DateTime(2026, 8, 10));
      await declarer(date: DateTime(2026, 8, 10));

      // J5 du cycle = 14 aout, et non le 5.
      await vm.changerJour(DateTime(2026, 8, 14));
      expect(
        vm.prophylaxieDuJour.single.echeance.traitement,
        'Anti-coccidien (1/4)',
      );

      await vm.changerJour(DateTime(2026, 8, 5));
      expect(vm.prophylaxieDuJour, isEmpty);
    });

    test('tout le calendrier de la bande est daté', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(date: DateTime(2026, 8, 1));

      final projections = vm.prophylaxieDeLaBande;
      expect(projections, hasLength(3)); // J1, J5, J15
      expect(projections.first.datePrevue, DateTime(2026, 8, 1));
      expect(projections.last.jourDeCycle, 15);
      expect(projections.last.datePrevue, DateTime(2026, 8, 15));
    });

    test('le délai d\'attente court depuis la date projetée', () async {
      await ouvrirLe(DateTime(2026, 8, 10));
      await declarer(date: DateTime(2026, 8, 10));

      // Deparasitage a J1 : 7 jours de remanence depuis le 10 aout.
      final j1 = vm.prophylaxieDeLaBande.first;
      expect(j1.echeance.remanenceJours, 7);
      expect(j1.finRemanence, DateTime(2026, 8, 17));

      // Le vaccin de J15 n'impose aucun delai : `null`, et non la date du jour.
      final j15 = vm.prophylaxieDeLaBande.last;
      expect(j15.echeance.remanenceJours, 0);
      expect(j15.finRemanence, isNull);
    });

    test('une autre filière ne pollue pas la projection', () async {
      await ouvrirLe(DateTime(2026, 8, 6));
      await declarer(date: DateTime(2026, 8, 1));

      // Les Pintades ont une echeance a J6 (Complement Calcium), pas les
      // Goliaths.
      expect(vm.prophylaxieDuJour, isEmpty);
    });
  });

  group('Planification d\'une échéance', () {
    test('crée un soin daté, rattaché à la bande et à l\'échéance', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      final bande = await declarer(date: DateTime(2026, 8, 1));

      final projetee = vm.prophylaxieDuJour.single;
      final resultat = await vm.planifierEcheance(
        projetee: projetee,
        typeSoin: 'Vermifuge',
      );
      expect(resultat, isA<Succes<Soin>>());

      // Relecture en base : c'est le Calendrier de Soins qui doit le voir.
      final enBase = await soins.chargerSoins();
      expect(enBase, hasLength(1));
      expect(enBase.single.typeSoin, 'Vermifuge');
      expect(enBase.single.statut, StatutSoin.planifie);
      expect(enBase.single.datePrevue, DateTime(2026, 8, 1));
      expect(enBase.single.produit, 'Levamisole Volaille');
      expect(enBase.single.remanenceJours, 7);
      expect(enBase.single.bandeId, bande.id);
      expect(enBase.single.echeanceProphylaxieId, projetee.echeance.id);
      expect(enBase.single.vientDuCalendrier, isTrue);
    });

    test('la dose de l\'échéance est reprise sur le soin créé', () async {
      // Goliaths J1 : la dose n'est pas semee (echeance d'avant la v27) ; elle
      // est renseignee ici comme le ferait l'animalier dans Paramètres Élevage.
      await db.customStatement(
        "UPDATE calendrier_prophylaxie SET dose = '1 mL par litre d''eau' "
        "WHERE espece = 'goliaths' AND jour_cycle = 1",
      );
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(date: DateTime(2026, 8, 1));

      await vm.planifierEcheance(
        projetee: vm.prophylaxieDuJour.single,
        typeSoin: 'Vermifuge',
      );

      final enBase = await soins.chargerSoins();
      expect(enBase.single.dose, '1 mL par litre d\'eau');
    });

    test('sans dose renseignée, le soin n\'en invente pas', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(date: DateTime(2026, 8, 1));

      await vm.planifierEcheance(
        projetee: vm.prophylaxieDuJour.single,
        typeSoin: 'Vermifuge',
      );

      expect((await soins.chargerSoins()).single.dose, isNull);
    });

    test('une échéance déjà planifiée ne se reprogramme pas', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(date: DateTime(2026, 8, 1));

      await vm.planifierEcheance(
        projetee: vm.prophylaxieDuJour.single,
        typeSoin: 'Vermifuge',
      );

      // L'ecran doit maintenant l'afficher comme planifiee.
      final apres = vm.prophylaxieDuJour.single;
      expect(apres.estPlanifie, isTrue);

      final rejeu = await vm.planifierEcheance(
        projetee: apres,
        typeSoin: 'Vermifuge',
      );
      expect(rejeu, isA<Echec<Soin>>());
      expect(await soins.chargerSoins(), hasLength(1));
    });

    test('un type d\'action hors de la liste fermée est refusé', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(date: DateTime(2026, 8, 1));

      final resultat = await vm.planifierEcheance(
        projetee: vm.prophylaxieDuJour.single,
        typeSoin: 'Contrôle',
      );
      expect(resultat, isA<Echec<Soin>>());
      expect(await soins.chargerSoins(), isEmpty);
    });

    test('un soin effectué se distingue d\'un soin planifié', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(date: DateTime(2026, 8, 1));

      await vm.planifierEcheance(
        projetee: vm.prophylaxieDuJour.single,
        typeSoin: 'Vermifuge',
      );
      final soin = (await soins.chargerSoins()).single;
      await soins.confirmerAdministration(soin.id);
      await vm.changerJour(DateTime(2026, 8, 1));

      expect(vm.prophylaxieDuJour.single.estEffectue, isTrue);
    });

    test(
      'deux bandes successives reprogramment chacune leur calendrier',
      () async {
        await ouvrirLe(DateTime(2026, 8, 1));
        await declarer(date: DateTime(2026, 8, 1), code: 'B1');
        await vm.planifierEcheance(
          projetee: vm.prophylaxieDuJour.single,
          typeSoin: 'Vermifuge',
        );

        await vm.changerJour(DateTime(2026, 8, 20));
        await vm.cloturerBande(DateTime(2026, 8, 20));

        await vm.changerJour(DateTime(2026, 8, 21));
        await declarer(date: DateTime(2026, 8, 21), code: 'B2');

        // Meme echeance, autre bande : elle est de nouveau a planifier.
        final projetee = vm.prophylaxieDuJour.single;
        expect(projetee.echeance.traitement, 'Déparasitage');
        expect(projetee.estPlanifie, isFalse);

        await vm.planifierEcheance(projetee: projetee, typeSoin: 'Vermifuge');
        expect(await soins.chargerSoins(), hasLength(2));
      },
    );
  });

  group('Déclaration de la bande', () {
    test('le code est proposé depuis le préfixe des Paramètres', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      expect(await vm.prochainCodeBande(), 'B1');

      await declarer(code: 'B1');
      expect(await vm.prochainCodeBande(), 'B2');
    });

    test('deux bandes de la même filière ne partagent pas un code', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(code: 'B1');

      final resultat = await vm.declarerBande(
        code: 'B1',
        dateMiseEnBande: DateTime(2026, 8, 2),
      );
      expect(resultat, isA<Echec<Bande>>());
    });

    test('un code vide est refusé', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      final resultat = await vm.declarerBande(
        code: '   ',
        dateMiseEnBande: DateTime(2026, 8, 1),
      );
      expect(resultat, isA<Echec<Bande>>());
    });

    test('un effectif négatif est refusé', () async {
      await ouvrirLe(DateTime(2026, 8, 1));
      final resultat = await vm.declarerBande(
        code: 'B1',
        dateMiseEnBande: DateTime(2026, 8, 1),
        effectifInitial: -5,
      );
      expect(resultat, isA<Echec<Bande>>());
    });

    test(
      'l\'effectif déclaré ne touche PAS l\'effectif calculé de la fiche',
      () async {
        await ouvrirLe(DateTime(2026, 8, 1));
        await declarer(effectif: 500);

        // Aucune saisie journaliere : l'effectif reste a zero. L'effectif de
        // mise en bande est indicatif — le confondre avec l'effectif reel
        // rendrait faux tout le suivi de mortalite.
        expect(vm.effectifVivant, 0);
        expect(vm.bande!.effectifInitial, 500);
      },
    );
  });

  group('Rendu de la fiche', () {
    Future<void> afficher(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1500, 1600));
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
          home: ChangeNotifierProvider<FicheEspeceViewModel>.value(
            value: vm,
            child: const Scaffold(
              body: FicheEspeceScreen(configuration: config),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('sans bande, la fiche le dit au lieu de supposer un J1', (
      tester,
    ) async {
      await ouvrirLe(DateTime(2026, 8, 5));
      await afficher(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Aucune bande déclarée à cette date'), findsOneWidget);
      expect(find.text('Déclarer une Mise en Bande'), findsOneWidget);
      expect(
        find.textContaining('les échéances du calendrier ne peuvent'),
        findsOneWidget,
      );
    });

    testWidgets("avec bande, le jour de cycle et l’échéance s’affichent", (
      tester,
    ) async {
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(date: DateTime(2026, 8, 1), effectif: 300);
      await afficher(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Jour de cycle J1'), findsOneWidget);
      expect(
        find.textContaining('Bande B1 — mise en place le'),
        findsOneWidget,
      );
      expect(find.textContaining('Déparasitage'), findsOneWidget);
      expect(find.text('Planifier'), findsOneWidget);
    });

    testWidgets('une échéance planifiée ne propose plus de la planifier', (
      tester,
    ) async {
      await ouvrirLe(DateTime(2026, 8, 1));
      await declarer(date: DateTime(2026, 8, 1));
      await vm.planifierEcheance(
        projetee: vm.prophylaxieDuJour.single,
        typeSoin: 'Vermifuge',
      );
      await afficher(tester);

      expect(find.text('Déjà planifié'), findsOneWidget);
      expect(find.text('Planifier'), findsNothing);
    });
  });
}
