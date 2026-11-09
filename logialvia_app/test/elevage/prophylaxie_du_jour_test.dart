import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/fiche_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/soins_repository_drift.dart';
import 'package:logialvia_app/elevage/domain/entities/bande.dart';
import 'package:logialvia_app/elevage/domain/entities/parametres_elevage.dart';
import 'package:logialvia_app/elevage/domain/entities/soin.dart';
import 'package:logialvia_app/elevage/domain/services/prophylaxie_de_la_bande.dart';
import 'package:logialvia_app/elevage/domain/services/rappels_prophylaxie.dart';
import 'package:logialvia_app/elevage/domain/usecases/reporter_deces_infirmerie_usecase.dart';
import 'package:logialvia_app/elevage/presentation/screens/widgets/modale_prophylaxie_du_jour.dart';
import 'package:logialvia_app/elevage/presentation/viewmodels/soins_view_model.dart';

/// Popup « Prophylaxie du Jour » — `assets/js/prophylaxie-popup.js`, Doc K2 §B.
void main() {
  late AppDatabase db;
  late SoinsViewModel vm;

  final maintenant = DateTime(2026, 8, 17, 9);
  DateTime jour(int decalage) =>
      DateTime(2026, 8, 17).add(Duration(days: decalage));

  setUpAll(() => initializeDateFormatting('fr_FR'));

  setUp(() async {
    db = AppDatabase.enMemoire();
    vm = SoinsViewModel(
      SoinsRepositoryDrift(db),
      ReporterDecesInfirmerieUseCase(fabriqueFicheElevage(db)),
    );
    await vm.charger();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  Future<Soin> planifier({
    required DateTime date,
    String espece = 'goliaths',
    String type = 'Vaccination',
    bool dejaEffectue = false,
    int remanence = 0,
  }) async {
    final resultat = await vm.enregistrerSoin(
      espece: espece,
      date: date,
      typeSoin: type,
      remanenceJours: remanence,
      dejaEffectue: dejaEffectue,
    );
    return (resultat as Succes<Soin>).valeur;
  }

  group('Ce que la popup retient', () {
    test('un soin dû aujourd\'hui est retenu', () async {
      await planifier(date: jour(0));
      expect(ProphylaxieDuJour.aTraiter(vm, maintenant), hasLength(1));
    });

    test('un soin en retard est retenu — écart délibéré', () async {
      await planifier(date: jour(-3));
      expect(
        ProphylaxieDuJour.aTraiter(vm, maintenant),
        hasLength(1),
        reason:
            'Le prototype ne regarde que le jour meme. Un traitement oublie '
            'hier est plus urgent que celui d\'aujourd\'hui : l\'omettre '
            'reviendrait a l\'enterrer.',
      );
    });

    test('un soin de demain ne l\'est pas', () async {
      await planifier(date: jour(1));
      expect(ProphylaxieDuJour.aTraiter(vm, maintenant), isEmpty);
    });

    test('un soin déjà administré ne l\'est pas', () async {
      await planifier(date: jour(0), dejaEffectue: true);
      expect(ProphylaxieDuJour.aTraiter(vm, maintenant), isEmpty);
    });

    test('les plus anciens viennent en premier', () async {
      await planifier(date: jour(0), type: 'Vitamines');
      await planifier(date: jour(-5), type: 'Vermifuge');
      await planifier(date: jour(-1), type: 'Vaccination');

      expect(
        ProphylaxieDuJour.aTraiter(vm, maintenant).map((s) => s.typeSoin),
        ['Vermifuge', 'Vaccination', 'Vitamines'],
      );
    });

    test('un soin dû en fin de journée compte pour aujourd\'hui', () async {
      await planifier(date: DateTime(2026, 8, 17, 23, 30));
      expect(ProphylaxieDuJour.aTraiter(vm, maintenant), hasLength(1));
    });
  });

  group('« Marquer fait » écrit en base, sans état parallèle', () {
    test('le soin passe à Effectué et quitte la liste', () async {
      final soin = await planifier(date: jour(0));
      expect(ProphylaxieDuJour.aTraiter(vm, maintenant), hasLength(1));

      final resultat = await vm.confirmerAdministration(soin);
      expect(resultat, isA<Succes<void>>());

      expect(
        ProphylaxieDuJour.aTraiter(vm, maintenant),
        isEmpty,
        reason:
            'Le prototype coche la ligne dans localStorage et laisse le soin '
            'en « Planifie » : deux verites pour un meme traitement.',
      );
      expect(vm.soins.single.statut, StatutSoin.effectue);
    });

    test('la validation est visible depuis l\'écran Soins', () async {
      final soin = await planifier(date: jour(0));
      await vm.confirmerAdministration(soin);

      // Un second ViewModel, comme si la Gerante ouvrait l'ecran Soins.
      final autre = SoinsViewModel(
        SoinsRepositoryDrift(db),
        ReporterDecesInfirmerieUseCase(fabriqueFicheElevage(db)),
      );
      await autre.charger();
      expect(autre.soins.single.estEffectue, isTrue);
      autre.dispose();
    });

    test('valider deux fois le même soin est refusé', () async {
      final soin = await planifier(date: jour(0));
      await vm.confirmerAdministration(soin);

      expect(
        await vm.confirmerAdministration(vm.soins.single),
        isA<Echec<void>>(),
      );
    });

    test('la rémanence reste portée par le soin validé', () async {
      final soin = await planifier(date: jour(0), remanence: 7);
      await vm.confirmerAdministration(soin);

      expect(
        vm.soins.single.remanenceJours,
        7,
        reason:
            'Le delai d\'attente conditionne la commercialisation : le perdre '
            'a la validation ferait vendre des sujets sous traitement.',
      );
    });
  });

  group('Rien à signaler', () {
    test('aucun soin — la popup ne s\'ouvre pas', () {
      expect(ProphylaxieDuJour.aTraiter(vm, maintenant), isEmpty);
    });

    test('tout est fait — la popup ne s\'ouvre pas', () async {
      final soin = await planifier(date: jour(0));
      await vm.confirmerAdministration(soin);
      expect(ProphylaxieDuJour.aTraiter(vm, maintenant), isEmpty);
    });
  });

  group('Échéances non planifiées — la section « À planifier »', () {
    /// Une échéance projetée, échue depuis trois jours et jamais planifiée.
    RappelProphylaxie unRappel() {
      const echeance = EcheanceProphylaxie(
        id: 7,
        espece: 'goliaths',
        jourCycle: 5,
        traitement: 'Anti-coccidien (Jour 1/4)',
        produit: 'Amprolium',
        remanenceJours: 5,
      );
      return RappelProphylaxie(
        espece: 'goliaths',
        bande: Bande(
          id: 'bande-1',
          espece: 'goliaths',
          code: 'B-2026-001',
          dateMiseEnBande: DateTime(2026, 8, 10),
        ),
        projetee: EcheanceProjetee(
          echeance: echeance,
          datePrevue: DateTime(2026, 8, 14),
          jourDeCycle: 5,
        ),
        joursDeRetard: 3,
      );
    }

    testWidgets('une échéance échue ouvre la popup, sans aucun soin daté', (
      tester,
    ) async {
      // Aucun soin au registre : avant ce correctif, la popup se taisait.
      expect(ProphylaxieDuJour.aTraiter(vm, maintenant), isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => TextButton(
              onPressed: () =>
                  ProphylaxieDuJour.afficher(ctx, vm, rappels: [unRappel()]),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(find.text('Prophylaxie du Jour'), findsOneWidget);
      expect(find.textContaining('Anti-coccidien'), findsOneWidget);
      expect(
        find.textContaining('ne sont pas encore planifiées'),
        findsOneWidget,
      );
      expect(
        find.textContaining('en retard de 3 j'),
        findsOneWidget,
        reason: 'Le retard distingue un oubli de l\'échéance du jour même.',
      );
      expect(
        find.text('Planifier'),
        findsOneWidget,
        reason:
            'La popup dit qu\'il faut y aller ; le type d\'action se choisit '
            'sur la fiche, elle ne le devine pas.',
      );
    });
  });
}
