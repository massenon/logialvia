import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/administration/data/repositories/preferences_poste_repository.dart';
import 'package:logialvia_app/comptabilite/data/repositories/pieces_cloture_drift.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_clotures_poste.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_ecritures_poste.dart';
import 'package:logialvia_app/comptabilite/data/sync/table_exercices_poste.dart';
import 'package:logialvia_app/comptabilite/domain/services/report_a_nouveau.dart';
import 'package:logialvia_app/comptabilite/presentation/viewmodels/comptabilite_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';

/// Report à nouveau et clôture annuelle SYSCOHADA — `47c_`.
///
/// Les chiffres attendus sont calculés À LA MAIN (jeu 2024) :
///
/// | pièce | écriture |
/// |---|---|
/// | apport | 531 D 1 000 000 / 101 C 1 000 000 |
/// | vente | 531 D 600 000 / 701 C 600 000 |
/// | achat | 601 D 250 000 / 401 C 250 000 |
/// | dépense | 624 D 50 000 / 531 C 50 000 |
/// | immobilisation | 231 D 300 000 / 531 C 300 000 |
///
/// Produits 600 000 ; charges 250 000 + 50 000 = 300 000 ; **résultat 300 000**.
/// Soldes de bilan à la fin de 2024 : 531 D 1 250 000 (1 000 + 600 − 50 − 300) ; 231 D
/// 300 000 ; 101 C 1 000 000 ; 401 C 250 000.
/// Affectation : réserve légale 30 000 (10 %), dividendes 100 000, report à nouveau 170 000.
/// À-nouveaux 2025 : D 531 1 250 000 + D 231 300 000 = 1 550 000 ; C 101 1 000 000 + C 401
/// 250 000 + C 111 30 000 + C 465 100 000 + C 121 170 000 = 1 550 000.
void main() {
  late AppDatabase db;
  late ComptabiliteViewModel vm;
  late ComptabiliteRepositoryDrift repo;

  Future<void> piece(
    String numero,
    int annee,
    int mois,
    List<(String, double, double)> lignes,
  ) => repo.enregistrerPiece(
    date: DateTime(annee, mois, 10, 10),
    journalCode: 'OD',
    numeroPiece: numero,
    lignes: [
      for (final (c, d, k) in lignes)
        LigneAEcrire(numeroCompte: c, debit: d, credit: k, libelle: numero),
    ],
  );

  Future<void> jeu2024() async {
    await piece('P1', 2024, 1, [('531', 1000000, 0), ('101', 0, 1000000)]);
    await piece('P2', 2024, 2, [('531', 600000, 0), ('701', 0, 600000)]);
    await piece('P3', 2024, 3, [('601', 250000, 0), ('401', 0, 250000)]);
    await piece('P4', 2024, 4, [('624', 50000, 0), ('531', 0, 50000)]);
    await piece('P5', 2024, 5, [('231', 300000, 0), ('531', 0, 300000)]);
  }

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    for (final a in [2024, 2025]) {
      await db
          .into(db.exerciceComptable)
          .insertOnConflictUpdate(
            ExerciceComptableCompanion.insert(annee: Value(a)),
          );
    }
    await db
        .into(db.planComptable)
        .insert(
          PlanComptableCompanion.insert(
            numeroCompte: '231',
            libelle: 'Bâtiments',
            classe: '2',
          ),
        );
    repo = ComptabiliteRepositoryDrift(db);
    await jeu2024();
    vm = ComptabiliteViewModel(repo);
    await vm.charger();
    await vm.changerExercice(2024);
  });

  tearDown(() => db.close());

  Future<List<EcritureRow>> lignes(int annee, String journal) =>
      (db.select(db.ecritureComptable)..where(
            (e) =>
                e.exerciceAnnee.equals(annee) & e.journalCode.equals(journal),
          ))
          .get();

  double solde(List<EcritureRow> l, String compte) => l
      .where((e) => e.numeroCompte == compte)
      .fold(0.0, (s, e) => s + e.debit - e.credit);

  const affectation = AffectationResultat(
    reserveLegale: 30000,
    dividendes: 100000,
  );

  group('calcul de la clôture (fonction pure)', () {
    test('résultat 300 000, trois pièces, à-nouveaux équilibrés à 1 550 000', () {
      final c = vm.apercuCloture(affectation);
      expect(c.bloquee, isFalse);
      expect(c.resultat, 300000);
      expect(c.pieces.map((p) => p.numeroPiece), [
        'CL-2024-RESULTAT',
        'CL-2024-AFFECTATION',
        'AN-2025',
      ]);
      final res = c.pieces[0];
      // 601 et 624 créditées (charges soldées), 701 débitée, 131 créditée du résultat.
      expect(res.totalDebit, 600000);
      expect(res.totalCredit, 600000);
      final affect = c.pieces[1];
      expect(affect.totalDebit, 300000);
      expect(
        {for (final l in affect.lignes) l.numeroCompte: l.credit},
        {'131': 0, '111': 30000, '465': 100000, '121': 170000},
      );
      final an = c.aNouveaux!;
      expect(an.totalDebit, 1550000);
      expect(an.totalCredit, 1550000);
      expect(c.soldesReportes, {
        '231': 300000,
        '531': 1250000,
        '101': -1000000,
        '401': -250000,
        '111': -30000,
        '465': -100000,
        '121': -170000,
      });
      // Jamais de classe 6, 7 ni 8 dans les à-nouveaux.
      expect(an.lignes.any((l) => '678'.contains(l.numeroCompte[0])), isFalse);
    });

    test('sans décision : tout le bénéfice au report à nouveau 121', () {
      final c = vm.apercuCloture();
      expect(c.soldesReportes['121'], -300000);
      expect(c.soldesReportes.containsKey('111'), isFalse);
    });

    test('perte : 139 débité au 129, report débiteur', () async {
      await piece('P6', 2024, 6, [('624', 800000, 0), ('531', 0, 800000)]);
      await vm.charger();
      final c = vm.apercuCloture();
      // Produits 600 000 − charges 1 100 000 = −500 000.
      expect(c.resultat, -500000);
      final affect = c.pieces[1];
      expect(affect.lignes.map((l) => (l.numeroCompte, l.debit, l.credit)), [
        ('129', 500000, 0),
        ('139', 0, 500000),
      ]);
      expect(c.soldesReportes['129'], 500000);
      expect(c.aNouveaux!.totalDebit, c.aNouveaux!.totalCredit);
    });

    test(
      'affectation refusée : dépasse le bénéfice, ou dividende sur une perte',
      () {
        expect(
          vm
              .apercuCloture(const AffectationResultat(dividendes: 300001))
              .bloquee,
          isTrue,
        );
        expect(
          const AffectationResultat(dividendes: 1).valider(-100),
          contains('Aucune distribution'),
        );
        expect(
          const AffectationResultat(
            dividendes: 250000,
          ).valider(300000, reportDebiteurAnterieur: 100000),
          contains('absorber'),
        );
        expect(
          const AffectationResultat(reserveLegale: -1).valider(300000),
          isNotNull,
        );
      },
    );

    test('la classe 8 entre dans le résultat net (HAO, impôt)', () async {
      await db
          .into(db.planComptable)
          .insert(
            PlanComptableCompanion.insert(
              numeroCompte: '891',
              libelle: 'Impôt sur le résultat',
              classe: '8',
            ),
          );
      await piece('P7', 2024, 7, [('891', 75000, 0), ('531', 0, 75000)]);
      await vm.charger();
      expect(vm.resultatNet, 225000);
      expect(vm.apercuCloture().resultat, 225000);
    });
  });

  group('clôture écrite au poste', () {
    test(
      'écrit CL en 2024 et AN en 2025, verrouille, solde les classes 6/7',
      () async {
        await repo.cloturerExercice(2024, affectation: affectation);

        final cl = await lignes(2024, 'CL');
        expect(cl, isNotEmpty);
        expect(cl.every((e) => e.isLocked), isTrue);
        final toutes2024 = await (db.select(
          db.ecritureComptable,
        )..where((e) => e.exerciceAnnee.equals(2024))).get();
        for (final c in ['601', '624', '701', '131']) {
          expect(solde(toutes2024, c), 0, reason: 'compte $c soldé');
        }
        // 121 : 170 000 créditeur après l'affectation.
        expect(solde(toutes2024, '121'), -170000);

        final an = await lignes(2025, 'AN');
        expect(an.length, 7);
        expect(solde(an, '531'), 1250000);
        expect(an.fold<double>(0, (s, e) => s + e.debit), 1550000);
        expect(an.fold<double>(0, (s, e) => s + e.credit), 1550000);
        expect(
          an.every((e) => e.syncStatus == 'synced' && e.origine == null),
          isTrue,
          reason: 'dérivées : jamais envoyées',
        );
        expect(await repo.exerciceEstCloture(2024), isTrue);
        expect(
          (await repo.chargerAffectation(2024)).dividendes,
          100000,
          reason: 'la décision est gardée avec la clôture',
        );
      },
    );

    test('idempotente : clôturer deux fois ne duplique rien', () async {
      await repo.cloturerExercice(2024, affectation: affectation);
      final avant = (await db.select(db.ecritureComptable).get()).length;
      final date = (await (db.select(
        db.exerciceComptable,
      )..where((e) => e.annee.equals(2024))).getSingle()).dateCloture;

      await repo.cloturerExercice(2024, affectation: affectation);
      await repo.cloturerExercice(2024);

      expect((await db.select(db.ecritureComptable).get()).length, avant);
      expect(
        (await (db.select(
          db.exerciceComptable,
        )..where((e) => e.annee.equals(2024))).getSingle()).dateCloture,
        date,
      );
      // Identifiants déterministes : rejouer l'écriture des pièces ne crée rien.
      final calcul = vm.apercuCloture(affectation);
      expect(
        await PiecesClotureDrift(
          db,
        ).inserer(calcul.pieces.last, verrouillee: false),
        isFalse,
      );
    });

    test(
      'refusée si la balance est déséquilibrée, rien n\'est écrit',
      () async {
        await db
            .into(db.ecritureComptable)
            .insert(
              EcritureComptableCompanion.insert(
                exerciceAnnee: 2024,
                numeroCompte: '531',
                dateEcriture: DateTime(2024, 8, 1),
                debit: const Value(1000),
                libelle: 'ligne seule',
              ),
            );
        await vm.charger();
        expect(await vm.cloturerExercice(roleId: 'admin'), isA<Echec<void>>());
        await expectLater(
          repo.cloturerExercice(2024),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('déséquilibrée'),
            ),
          ),
        );
        expect(await lignes(2025, 'AN'), isEmpty);
        expect(await repo.exerciceEstCloture(2024), isFalse);
      },
    );

    test(
      'les écritures de clôture ne se modifient ni ne se suppriment à la main',
      () async {
        await repo.cloturerExercice(2024, affectation: affectation);
        await expectLater(
          repo.supprimerPiece(exerciceAnnee: 2025, numeroPiece: 'AN-2025'),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          repo.supprimerPiece(
            exerciceAnnee: 2024,
            numeroPiece: 'CL-2024-RESULTAT',
          ),
          throwsA(isA<StateError>()),
        );
        await expectLater(
          repo.enregistrerPiece(
            date: DateTime(2025, 2, 1),
            journalCode: 'AN',
            numeroPiece: 'X',
            lignes: const [
              LigneAEcrire(
                numeroCompte: '531',
                debit: 1,
                credit: 0,
                libelle: 'x',
              ),
              LigneAEcrire(
                numeroCompte: '101',
                debit: 0,
                credit: 1,
                libelle: 'x',
              ),
            ],
          ),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'rouvrir annule les à-nouveaux et les écritures de clôture ; on peut reclôturer',
      () async {
        await repo.cloturerExercice(2024, affectation: affectation);
        await repo.rouvrirExercice(2024, utilisateurId: '1');

        expect(await lignes(2024, 'CL'), isEmpty);
        expect(await lignes(2025, 'AN'), isEmpty);
        expect(await repo.exerciceEstCloture(2024), isFalse);
        final toutes = await (db.select(
          db.ecritureComptable,
        )..where((e) => e.exerciceAnnee.equals(2024))).get();
        expect(toutes.every((e) => !e.isLocked), isTrue);
        expect((await repo.chargerAffectation(2024)).totalDistribue, 0);

        await repo.cloturerExercice(2024);
        expect((await lignes(2025, 'AN')).length, 5);
      },
    );

    test('rouvrir est refusé si l\'exercice suivant est clôturé', () async {
      await repo.cloturerExercice(2024);
      await repo.cloturerExercice(2025);
      await expectLater(
        repo.rouvrirExercice(2024, utilisateurId: '1'),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'rouvrir est refusé tant que le viewmodel n\'est pas administratrice',
      () async {
        await repo.cloturerExercice(2024);
        await vm.charger();
        expect(
          await vm.rouvrirExercice(roleId: 'comptable', utilisateurId: '2'),
          isA<Echec<void>>(),
        );
        expect(
          await vm.rouvrirExercice(roleId: 'admin', utilisateurId: '1'),
          isA<Succes<void>>(),
        );
      },
    );
  });

  group('états de N+1 : ils partent de l\'ouverture', () {
    Future<void> ouvrir2025(bool cloture) async {
      if (cloture) await repo.cloturerExercice(2024, affectation: affectation);
      await piece('V25', 2025, 2, [('531', 200000, 0), ('701', 0, 200000)]);
      await vm.charger();
      await vm.changerExercice(2025);
    }

    test(
      'après clôture : bilan 2025 = 1 750 000 des deux côtés, résultat 200 000',
      () async {
        await ouvrir2025(true);
        // Actif : immobilisation 300 000 + trésorerie 1 250 000 + 200 000 = 1 750 000.
        // Passif : capital 1 000 000 + réserves 30 000 + report 170 000 + résultat 200 000 +
        // dettes 250 000 + dividendes 100 000 = 1 750 000.
        final b = vm.bilan;
        expect(b.totalActif, 1750000);
        expect(b.totalPassif, 1750000);
        expect(b.estEquilibre, isTrue);
        expect(vm.resultatNet, 200000);
        expect(vm.ouvertureParANouveaux, isTrue);
        expect(
          b.passif
              .firstWhere((p) => p.libelle == 'Réserves et Report à Nouveau')
              .montant,
          200000,
        );
        expect(vm.bilanEntreprise.estEquilibre, isTrue);
      },
    );

    test(
      'TAFIRE 2025 : ouverture 1 250 000 = 5xx reportés, clôture 1 450 000',
      () async {
        await ouvrir2025(true);
        final t = vm.tafire;
        expect(t.tresorerieOuverture, 1250000);
        expect(t.fluxExploitation, 200000);
        expect(t.fluxInvestissement, 0);
        expect(t.fluxFinancement, 0);
        expect(t.tresorerieCloture, 1450000);
        expect(t.tresorerieCloture, vm.tresorerieNette);
        expect(vm.tresorerie, 1450000);
      },
    );

    test(
      'balance 2025 : ouverture = à-nouveaux, équilibrée, comptes de gestion à zéro',
      () async {
        await ouvrir2025(true);
        final l = vm.balance;
        expect(l.fold<double>(0, (s, x) => s + x.ouvertureDebit), 1550000);
        expect(l.fold<double>(0, (s, x) => s + x.ouvertureCredit), 1550000);
        expect(vm.balanceEstEquilibree, isTrue);
        expect(l.any((x) => x.numeroCompte == '601'), isFalse);
        final c531 = l.firstWhere((x) => x.numeroCompte == '531');
        expect(
          (c531.ouvertureDebit, c531.mouvementsDebit, c531.finalDebit),
          (1250000, 200000, 1450000),
        );
      },
    );

    test('grand livre 2025 du 531 : ouverture 1 250 000 reportée', () async {
      await ouvrir2025(true);
      vm.selectionnerCompte('531');
      expect(vm.soldeOuvertureCompte, 1250000);
      expect(vm.soldeFinalCompte, 1450000);
    });

    test(
      '2024 clôturé se lit encore « avant affectation » : résultat 300 000, bilan équilibré',
      () async {
        await ouvrir2025(true);
        await vm.changerExercice(2024);
        expect(vm.resultatNet, 300000);
        expect(vm.compteResultat.resultatNet, 300000);
        expect(vm.bilan.estEquilibre, isTrue);
        expect(vm.bilan.totalActif, 1550000);
        // Le journal montre les écritures de clôture ; l'analytique ne les voit pas.
        expect(vm.ecrituresDuJournal.any((e) => e.journalCode == 'CL'), isTrue);
        expect(vm.ecritures.any((e) => e.journalCode == 'CL'), isFalse);
        // La balance de 2024 lit le livre complet : 701 y est soldé.
        expect(
          vm.balance.firstWhere((x) => x.numeroCompte == '701').finalCredit,
          0,
        );
        expect(vm.balanceEstEquilibree, isTrue);
      },
    );

    test(
      'sans clôture : l\'ouverture est une clôture virtuelle (121 provisoire), bilan équilibré',
      () async {
        await ouvrir2025(false);
        expect(vm.ouvertureParANouveaux, isFalse);
        expect(vm.soldesOuverture['531'], 1250000);
        expect(vm.soldesOuverture['121'], -300000);
        expect(
          vm.soldesOuverture.keys.any((c) => '678'.contains(c[0])),
          isFalse,
        );
        expect(vm.bilan.totalActif, 1750000);
        expect(vm.bilan.estEquilibre, isTrue);
        expect(vm.tafire.tresorerieCloture, vm.tresorerieNette);
      },
    );

    test(
      'identité du TAFIRE avec dotations aux amortissements (28) et dettes financières',
      () async {
        for (final (n, l, c) in [
          ('281', 'Amortissements', '2'),
          ('681', 'Dotations amortissements', '6'),
          ('161', 'Emprunts', '1'),
        ]) {
          await db
              .into(db.planComptable)
              .insert(
                PlanComptableCompanion.insert(
                  numeroCompte: n,
                  libelle: l,
                  classe: c,
                ),
              );
        }
        await repo.cloturerExercice(2024, affectation: affectation);
        // 2025 : emprunt 400 000 encaissé, amortissement 30 000, vente à crédit 100 000.
        await piece('E1', 2025, 1, [('531', 400000, 0), ('161', 0, 400000)]);
        await piece('A1', 2025, 12, [('681', 30000, 0), ('281', 0, 30000)]);
        await piece('V2', 2025, 3, [('411', 100000, 0), ('701', 0, 100000)]);
        await vm.charger();
        await vm.changerExercice(2025);
        final t = vm.tafire;
        // Résultat 100 000 − 30 000 = 70 000 ; non décaissé +30 000 ; BFR : créances +100 000
        // et dettes (401 250 000 + 465 100 000) inchangées → −100 000. Exploitation 0.
        expect(t.fluxExploitation, 0);
        expect(t.fluxInvestissement, 0);
        expect(t.fluxFinancement, 400000);
        expect(t.tresorerieCloture, 1650000);
        expect(t.tresorerieCloture, vm.tresorerieNette);
        expect(vm.bilan.estEquilibre, isTrue);
        // L'amortissement minore l'actif immobilisé : 300 000 − 30 000.
        expect(
          vm.bilan.actif
              .firstWhere((p) => p.libelle == 'Total Actif Immobilisé')
              .montant,
          270000,
        );
      },
    );
  });

  group('synchronisation de la clôture', () {
    test(
      'les pièces CL/AN ne partent jamais ; le fait de clôture porte l\'affectation',
      () async {
        await repo.cloturerExercice(2024, affectation: affectation);

        // Aucune ligne CL/AN à envoyer : le serveur les engendre lui-même.
        final aEnvoyer = await TableEcrituresPoste(db).aEnvoyer();
        expect(aEnvoyer.every((p) => p.corps['journal_code'] == 'OD'), isTrue);

        final faits = await TableCloturesExercicePoste(db).aEnvoyer();
        expect(faits, hasLength(1));
        expect(faits.single.corps['annee'], 2024);
        expect(faits.single.corps['affectation'], {
          'reserve_legale': 30000.0,
          'autres_reserves': 0.0,
          'dividendes': 100000.0,
        });
      },
    );

    test(
      'un serveur qui sert des pièces AN : elles sont absorbées, une seule fois',
      () async {
        final pieceId = PiecesClotureDrift.idPiece('an:2025');
        Map<String, dynamic> piece() => {
          'id': pieceId,
          'numero_piece': 'AN-2025',
          'date_ecriture': DateTime(2025, 1, 1, 12).toUtc().toIso8601String(),
          'exercice_annee': 2025,
          'journal_code': 'AN',
          'device_id': 'web',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'lignes': [
            {
              'id': PiecesClotureDrift.idLigne('an:2025', '531'),
              'numero_compte': '531',
              'debit': 100.0,
              'credit': 0.0,
              'libelle': 'À-nouveau',
            },
            {
              'id': PiecesClotureDrift.idLigne('an:2025', '101'),
              'numero_compte': '101',
              'debit': 0.0,
              'credit': 100.0,
              'libelle': 'À-nouveau',
            },
          ],
        };
        final table = TableEcrituresPoste(db);
        expect((await table.absorber([piece()])).absorbees, 1);
        expect((await table.absorber([piece()])).absorbees, 0);
        expect(await lignes(2025, 'AN'), hasLength(2));
      },
    );

    test(
      'la réouverture venue du serveur (rouvert_le) rouvre l\'exercice et retire CL/AN ; sans rouvert_le, jamais',
      () async {
        await repo.cloturerExercice(2024, affectation: affectation);
        await (db.update(
          db.exerciceComptable,
        )..where((e) => e.annee.equals(2024))).write(
          const ExerciceComptableCompanion(syncStatus: Value('synced')),
        );
        final table = TableExercicesPoste(db);
        Map<String, dynamic> ligne({String? rouvertLe}) => {
          'annee': 2024,
          'is_cloture': false,
          'date_cloture': null,
          'rouvert_le': rouvertLe,
        };

        await table.absorber([ligne()]);
        expect(await repo.exerciceEstCloture(2024), isTrue);

        await table.absorber([
          ligne(rouvertLe: DateTime.now().toUtc().toIso8601String()),
        ]);
        expect(await repo.exerciceEstCloture(2024), isFalse);
        expect(await lignes(2024, 'CL'), isEmpty);
        expect(await lignes(2025, 'AN'), isEmpty);
      },
    );

    test(
      'un serveur qui refuse la clôture : exercice rouvert ici, CL et AN retirés',
      () async {
        await repo.cloturerExercice(2024, affectation: affectation);
        await TableCloturesExercicePoste(db).marquerConflit(
          TableCloturesExercicePoste.idDeLExercice(2024),
          'Droit insuffisant',
        );
        expect(await repo.exerciceEstCloture(2024), isFalse);
        expect(await lignes(2024, 'CL'), isEmpty);
        expect(await lignes(2025, 'AN'), isEmpty);
      },
    );

    test(
      'rouvrir est refusé au poste quand le serveur a accepté la clôture (fait partagé)',
      () async {
        await repo.cloturerExercice(2024);
        await PreferencesPosteRepository(
          db,
        ).memoriserAppairage(codePoste: 'P1', compte: 'g', le: DateTime.now());
        await (db.update(
          db.exerciceComptable,
        )..where((e) => e.annee.equals(2024))).write(
          const ExerciceComptableCompanion(syncStatus: Value('synced')),
        );
        await expectLater(
          repo.rouvrirExercice(2024, utilisateurId: '1'),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('conformité au contrat de synchronisation', () {
    test(
      'identifiants déterministes de la clôture (partagés avec le serveur)',
      () {
        // Valeurs calculées par `uuidDeterministe` : `ReportANouveauTest` (Laravel) les
        // retrouve à l'identique.
        expect(
          PiecesClotureDrift.idPiece('cloture:2026:resultat'),
          '6d8b152a-62f8-57ae-a525-cb336a28a3c3',
        );
        expect(
          PiecesClotureDrift.idPiece('an:2027'),
          'f8658418-261c-542b-9baa-5a6204579d85',
        );
        expect(
          PiecesClotureDrift.idLigne('an:2027', '531'),
          '735d7a68-4f35-5cd8-8097-0400f95b9bc6',
        );
        expect(
          PiecesClotureDrift.idLigne('an:2025', '531'),
          isNot(PiecesClotureDrift.idLigne('an:2025', '231')),
        );
      },
    );
  });
}
