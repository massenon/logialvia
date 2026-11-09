import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/comptabilite/domain/entities/comptabilite.dart';
import 'package:logialvia_app/comptabilite/domain/plan_syscohada.dart';
import 'package:logialvia_app/comptabilite/domain/usecases/generer_ecritures_automatiques.dart';
import 'package:logialvia_app/comptabilite/presentation/viewmodels/comptabilite_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';

/// Plan SYSCOHADA révisé et TVA ventilée (`47p_`) — jeux chiffrés à la main, rejoués à
/// l'identique côté web (`PlanSyscohadaTest`, `EcrituresAutomatiquesAchatsTest`).
void main() {
  late AppDatabase db;
  late ComptabiliteRepositoryDrift repo;
  late GenererEcrituresAutomatiques generation;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    repo = ComptabiliteRepositoryDrift(db);
    generation = GenererEcrituresAutomatiques(repo);
  });

  tearDown(() => db.close());

  Future<List<(String, double, double)>> piece(String numero) async {
    final l = await db
        .customSelect(
          'SELECT numero_compte, debit, credit FROM ecriture_comptable '
          'WHERE numero_piece = ? ORDER BY debit DESC, numero_compte',
          variables: [Variable.withString(numero)],
        )
        .get();
    return [
      for (final x in l)
        (
          x.read<String>('numero_compte'),
          x.read<double>('debit'),
          x.read<double>('credit'),
        ),
    ];
  }

  group('le plan', () {
    test('numéros uniques, classe = 1er chiffre, libellés renseignés', () {
      final numeros = <String>{};
      for (final c in PlanSyscohada.comptes) {
        expect(numeros.add(c.numero), isTrue, reason: 'doublon ${c.numero}');
        expect(c.numero.startsWith(c.classe), isTrue, reason: c.numero);
        expect(c.libelle.trim(), isNotEmpty);
        expect(
          RegExp(r'^[1-7]\d{1,3}$').hasMatch(c.numero),
          isTrue,
          reason: c.numero,
        );
      }
    });

    test('chaque constante de PlanSyscohada est un compte du plan', () {
      final plan = {for (final c in PlanSyscohada.comptes) c.numero};
      for (final n in [
        PlanSyscohada.capital,
        PlanSyscohada.reserveLegale,
        PlanSyscohada.autresReserves,
        PlanSyscohada.reportCrediteur,
        PlanSyscohada.reportDebiteur,
        PlanSyscohada.resultatBenefice,
        PlanSyscohada.resultatPerte,
        PlanSyscohada.stockMarchandises,
        PlanSyscohada.stockMatieres,
        PlanSyscohada.fournisseurs,
        PlanSyscohada.clients,
        PlanSyscohada.clientsAvances,
        PlanSyscohada.tvaCollectee,
        PlanSyscohada.tvaCollecteeServices,
        PlanSyscohada.tvaDeductible,
        PlanSyscohada.dividendesAPayer,
        PlanSyscohada.mobileMoney,
        PlanSyscohada.caisse,
        PlanSyscohada.achatsMarchandises,
        PlanSyscohada.achatsMatieres,
        PlanSyscohada.fraisVeterinaires,
        PlanSyscohada.transports,
        PlanSyscohada.locations,
        PlanSyscohada.assurances,
        PlanSyscohada.chargesDiverses,
        PlanSyscohada.ventesMarchandises,
        PlanSyscohada.ventesProduitsFinis,
        PlanSyscohada.produitsAccessoires,
        PlanSyscohada.fraisLivraison,
      ]) {
        expect(plan, contains(n));
      }
    });

    test(
      'les numéros officiels du SYSCOHADA révisé (écarts du prototype corrigés)',
      () {
        expect(PlanSyscohada.achatsMarchandises, '601');
        expect(PlanSyscohada.achatsMatieres, '602');
        expect(PlanSyscohada.ventesMarchandises, '701');
        expect(PlanSyscohada.ventesProduitsFinis, '702');
        expect(PlanSyscohada.produitsAccessoires, '707');
        expect(PlanSyscohada.caisse, '571');
        expect(PlanSyscohada.mobileMoney, '552');
        expect(PlanSyscohada.locations, '622');
        expect(PlanSyscohada.assurances, '625');
        expect(PlanSyscohada.tvaCollectee, '4431');
        expect(PlanSyscohada.tvaDeductible, '4452');
      },
    );

    test('le semis crée tout le plan officiel, une seule fois', () async {
      final n = await db.select(db.planComptable).get();
      expect(n.length, PlanSyscohada.comptes.length);
      for (final c in PlanSyscohada.comptes) {
        expect(
          n.where((x) => x.numeroCompte == c.numero).single.libelle,
          c.libelle,
        );
      }
    });

    test(
      'sens naturel : TVA collectée créditrice, TVA récupérable et 409 débitrices',
      () {
        CompteComptable compte(String n) =>
            CompteComptable(numero: n, libelle: 'x', classe: n[0]);
        expect(compte('4431').estDebiteurParNature, isFalse);
        expect(compte('4441').estDebiteurParNature, isFalse);
        expect(compte('4452').estDebiteurParNature, isTrue);
        expect(compte('4449').estDebiteurParNature, isTrue);
        expect(compte('409').estDebiteurParNature, isTrue);
        expect(compte('401').estDebiteurParNature, isFalse);
        expect(compte('419').estDebiteurParNature, isFalse);
        expect(compte('571').estDebiteurParNature, isTrue);
      },
    );
  });

  group('TVA : extraction du TTC (arrondie au franc)', () {
    test('valeurs faites à la main', () {
      expect(PlanSyscohada.tvaDuTtc(11800, 18), 1800); // 11 800 × 18 / 118
      expect(PlanSyscohada.tvaDuTtc(1180, 18), 180);
      expect(PlanSyscohada.tvaDuTtc(1000, 18), 153); // 152,54 → 153
      expect(PlanSyscohada.tvaDuTtc(5000, 18), 763); // 762,71 → 763
      expect(PlanSyscohada.tvaDuTtc(6000, 0), 0);
      expect(PlanSyscohada.tvaDuTtc(0, 18), 0);
    });
  });

  group('achats taxables : HT / TVA déductible (4452)', () {
    test(
      'achat de matières 59 000 TTC à 18 % non réglé : 602 D 50 000, 4452 D 9 000, 401 C 59 000',
      () async {
        await generation.pourAchat(
          reference: 'ACH-1',
          date: DateTime.now(),
          mode: 'Espèces',
          total: 59000,
          paye: 0,
          ventilation: {(PlanSyscohada.achatsMatieres, 18.0): 59000},
        );
        expect(await piece('ACH-1'), [
          ('602', 50000.0, 0.0),
          ('4452', 9000.0, 0.0),
          ('401', 0.0, 59000.0),
        ]);
      },
    );

    test(
      'achat mixte (matières taxables, vétérinaire exonéré) réglé en partie',
      () async {
        await generation.pourAchat(
          reference: 'ACH-2',
          date: DateTime.now(),
          mode: 'Mobile Money',
          total: 70800, // 59 000 taxables + 11 800 exonérés
          paye: 20000,
          ventilation: {
            (PlanSyscohada.achatsMatieres, 18.0): 59000,
            (PlanSyscohada.fraisVeterinaires, 0.0): 11800,
          },
        );
        expect(await piece('ACH-2'), [
          ('602', 50000.0, 0.0),
          ('604', 11800.0, 0.0),
          ('4452', 9000.0, 0.0),
          ('401', 0.0, 50800.0),
          ('552', 0.0, 20000.0),
        ]);
      },
    );

    test('achat exonéré (taux 0) : aucune TVA, tout en charge', () async {
      await generation.pourAchat(
        reference: 'ACH-3',
        date: DateTime.now(),
        mode: 'Espèces',
        total: 12000,
        paye: 12000,
        ventilation: {(PlanSyscohada.achatsMatieres, 0.0): 12000},
      );
      expect(await piece('ACH-3'), [
        ('602', 12000.0, 0.0),
        ('571', 0.0, 12000.0),
      ]);
    });
  });

  group('le résultat ne contient plus de TVA', () {
    test(
      'vente 11 800 TTC (1 800 de TVA) − achat 5 900 TTC (900 de TVA) : résultat 5 000',
      () async {
        await generation.pourVente(
          reference: 'V-1',
          date: DateTime.now(),
          mode: 'Espèces',
          statut: 'Payée',
          total: 11800,
          paye: 11800,
          ventilation: {
            (PlanSyscohada.ventesMarchandises, 'Commerce Annexe', 18.0): 11800,
          },
        );
        await generation.pourAchat(
          reference: 'A-1',
          date: DateTime.now(),
          mode: 'Espèces',
          total: 5900,
          paye: 5900,
          ventilation: {(PlanSyscohada.achatsMarchandises, 18.0): 5900},
        );
        final vm = ComptabiliteViewModel(repo);
        await vm.charger();
        // Produits 10 000 − charges 5 000 : ni les 1 800 collectés ni les 900 déductibles.
        expect(vm.resultatNet, 5000);
        // TVA due au 4441 non écrite (déclaration) ; à ce stade 4431 − 4452 = 900 à reverser.
        final s = await db
            .customSelect(
              "SELECT numero_compte AS c, SUM(debit) - SUM(credit) AS s FROM ecriture_comptable "
              "WHERE numero_compte IN ('4431', '4452') GROUP BY numero_compte",
            )
            .get();
        final soldes = {
          for (final x in s) x.read<String>('c'): x.read<double>('s'),
        };
        expect(soldes, {'4431': -1800.0, '4452': 900.0});
        // Le bilan reste équilibré : la TVA collectée est une dette, la déductible une créance.
        expect(vm.bilan.estEquilibre, isTrue);
      },
    );
  });
}
