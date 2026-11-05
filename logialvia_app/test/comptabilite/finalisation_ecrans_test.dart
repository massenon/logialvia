import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/comptabilite/domain/entities/comptabilite.dart';
import 'package:logialvia_app/comptabilite/presentation/viewmodels/comptabilite_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';

void main() {
  late AppDatabase db;
  late ComptabiliteViewModel vm;

  final annee = DateTime.now().year;
  final moisCourant = DateTime.now().month;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    vm = ComptabiliteViewModel(ComptabiliteRepositoryDrift(db));
    await vm.charger();
  });

  tearDown(() async {
    vm.dispose();
    await db.close();
  });

  Future<String> saisirDepense({
    required double montant,
    required DateTime date,
    String libelle = 'Transport livraison',
    String compteCharge = '613',
  }) async {
    final piece = vm.prochainNumeroPiece('DEP');
    final resultat = await vm.enregistrerPiece(
      date: date,
      journalCode: CodeJournal.caisse,
      numeroPiece: piece,
      lignes: [
        LigneAEcrire(
          numeroCompte: compteCharge,
          debit: montant,
          credit: 0,
          libelle: libelle,
        ),
        LigneAEcrire(
          numeroCompte: '531',
          debit: 0,
          credit: montant,
          libelle: libelle,
        ),
      ],
    );
    expect(resultat, isA<Succes<void>>());
    return piece;
  }

  group('Saisie Dépenses — modification d\'une pièce (`editExpense()`)', () {
    test('la pièce garde son numéro après modification', () async {
      final piece = await saisirDepense(
        montant: 12000,
        date: DateTime(annee, moisCourant, 5),
      );

      final resultat = await vm.remplacerPiece(
        numeroPiece: piece,
        date: DateTime(annee, moisCourant, 5),
        journalCode: CodeJournal.caisse,
        lignes: [
          const LigneAEcrire(
            numeroCompte: '613',
            debit: 15000,
            credit: 0,
            libelle: 'Transport livraison — corrigé',
          ),
          const LigneAEcrire(
            numeroCompte: '531',
            debit: 0,
            credit: 15000,
            libelle: 'Transport livraison — corrigé',
          ),
        ],
      );

      expect(resultat, isA<Succes<void>>());
      final depense = vm.depenses.firstWhere((d) => d.numeroPiece == piece);
      expect(
        depense.montant,
        15000,
        reason: 'Le montant corrige doit avoir remplace l\'ancien.',
      );
      expect(
        depense.numeroPiece,
        piece,
        reason:
            'Le numero figure sur le recu papier deja classe : le renumeroter '
            'rendrait le rapprochement impossible.',
      );
    });

    test('la modification ne laisse pas les anciennes lignes', () async {
      final piece = await saisirDepense(
        montant: 12000,
        date: DateTime(annee, moisCourant, 5),
      );
      final avant = vm.ecritures.length;

      await vm.remplacerPiece(
        numeroPiece: piece,
        date: DateTime(annee, moisCourant, 5),
        journalCode: CodeJournal.caisse,
        lignes: [
          const LigneAEcrire(
            numeroCompte: '616',
            debit: 8000,
            credit: 0,
            libelle: 'Reclassé en entretien',
          ),
          const LigneAEcrire(
            numeroCompte: '531',
            debit: 0,
            credit: 8000,
            libelle: 'Reclassé en entretien',
          ),
        ],
      );

      expect(
        vm.ecritures.length,
        avant,
        reason: 'Deux lignes remplacent deux lignes, elles ne s\'ajoutent pas.',
      );
      expect(
        vm.ecritures.where((e) => e.numeroCompte == '613'),
        isEmpty,
        reason: 'L\'ancienne imputation doit avoir disparu du Grand Livre.',
      );
    });

    test('la balance reste équilibrée après modification', () async {
      final piece = await saisirDepense(
        montant: 12000,
        date: DateTime(annee, moisCourant, 5),
      );

      await vm.remplacerPiece(
        numeroPiece: piece,
        date: DateTime(annee, moisCourant, 5),
        journalCode: CodeJournal.caisse,
        lignes: [
          const LigneAEcrire(
            numeroCompte: '613',
            debit: 9500,
            credit: 0,
            libelle: 'Corrigé',
          ),
          const LigneAEcrire(
            numeroCompte: '531',
            debit: 0,
            credit: 9500,
            libelle: 'Corrigé',
          ),
        ],
      );

      expect(vm.balanceEstEquilibree, isTrue);
    });

    test('une pièce déséquilibrée est refusée — BR-CPT-001', () async {
      final piece = await saisirDepense(
        montant: 12000,
        date: DateTime(annee, moisCourant, 5),
      );

      final resultat = await vm.remplacerPiece(
        numeroPiece: piece,
        date: DateTime(annee, moisCourant, 5),
        journalCode: CodeJournal.caisse,
        lignes: [
          const LigneAEcrire(
            numeroCompte: '613',
            debit: 9500,
            credit: 0,
            libelle: 'Déséquilibré',
          ),
          const LigneAEcrire(
            numeroCompte: '531',
            debit: 0,
            credit: 4000,
            libelle: 'Déséquilibré',
          ),
        ],
      );

      expect(resultat, isA<Echec<void>>());
      expect(
        vm.depenses.firstWhere((d) => d.numeroPiece == piece).montant,
        12000,
        reason: 'Un refus ne doit rien avoir touche.',
      );
    });

    test('modifier une pièce inexistante échoue proprement', () async {
      final resultat = await vm.remplacerPiece(
        numeroPiece: 'DEP-INEXISTANTE',
        date: DateTime(annee, moisCourant, 5),
        journalCode: CodeJournal.caisse,
        lignes: [
          const LigneAEcrire(
            numeroCompte: '613',
            debit: 100,
            credit: 0,
            libelle: 'X',
          ),
          const LigneAEcrire(
            numeroCompte: '531',
            debit: 0,
            credit: 100,
            libelle: 'X',
          ),
        ],
      );
      expect(resultat, isA<Echec<void>>());
    });
  });

  group('Balance Générale — périmètre mois / exercice', () {
    setUp(() async {
      // Une depense en janvier, une dans le mois courant. Si le mois courant
      // EST janvier, le test reste valide : les deux tombent dans la periode.
      await saisirDepense(montant: 30000, date: DateTime(annee, 1, 15));
      await saisirDepense(
        montant: 12000,
        date: DateTime(annee, moisCourant, 5),
      );
    });

    test('l\'exercice complet couvre les deux dépenses', () {
      vm.definirPerimetreBalance(moisCourant: false);
      final charges = vm.balance.firstWhere((l) => l.numeroCompte == '613');

      expect(charges.mouvementsDebit, 42000);
      expect(charges.ouvertureDebit, 0, reason: 'Rien ne precede l\'exercice.');
    });

    test('le mois courant bascule le reste en ouverture', () {
      if (moisCourant == 1) return; // les deux ecritures sont du meme mois

      vm.definirPerimetreBalance(moisCourant: true);
      final charges = vm.balance.firstWhere((l) => l.numeroCompte == '613');

      expect(
        charges.mouvementsDebit,
        12000,
        reason: 'Seule la depense du mois est un mouvement de la periode.',
      );
      expect(
        charges.ouvertureDebit,
        30000,
        reason:
            'Celle de janvier n\'est pas masquee : elle passe en solde '
            'd\'ouverture. La masquer donnerait un solde final faux.',
      );
    });

    test('le solde final ne dépend pas du périmètre', () {
      vm.definirPerimetreBalance(moisCourant: false);
      final finalExercice = vm.balance
          .firstWhere((l) => l.numeroCompte == '613')
          .finalDebit;

      vm.definirPerimetreBalance(moisCourant: true);
      final finalMois = vm.balance
          .firstWhere((l) => l.numeroCompte == '613')
          .finalDebit;

      expect(
        finalMois,
        finalExercice,
        reason:
            'C\'est tout l\'interet du format 6 colonnes : le solde final est '
            'le meme, seule la repartition ouverture / mouvements change.',
      );
    });

    test('la balance reste équilibrée dans les deux périmètres', () {
      for (final mois in [true, false]) {
        vm.definirPerimetreBalance(moisCourant: mois);
        expect(vm.balanceEstEquilibree, isTrue, reason: 'moisCourant=$mois');
      }
    });

    test('le libellé du sélecteur nomme un vrai mois', () {
      expect(vm.libelleMoisBalance, contains('$annee'));
      expect(vm.libelleMoisBalance.split(' ').first, isNotEmpty);
    });
  });
}
