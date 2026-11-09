import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/comptabilite/data/repositories/comptabilite_repository_drift.dart';
import 'package:logialvia_app/comptabilite/domain/entities/comptabilite.dart';
import 'package:logialvia_app/comptabilite/presentation/viewmodels/comptabilite_view_model.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/database/seed/seed_initial.dart';

/// Le JEU D'ECRITURES COMMUN au poste et au web (P8).
///
/// Les mêmes écritures, les mêmes montants et les mêmes chiffres attendus se trouvent côté
/// serveur dans `logialvia_laravel/tests/Concerns/JeuComptable.php` et
/// `tests/Feature/Web/ComptabiliteWebTest.php` : si le web et le poste s'écartent, l'un des
/// deux tests rougit. Les chiffres attendus sont écrits À LA MAIN (voir `46d_` §5), pas relus
/// d'un calcul.
///
/// Exercice N−1 : l'apport de départ (531 D 100 000 / 101 C 100 000) forme l'OUVERTURE.
/// Exercice N, P1 à P8 : apport, deux ventes, un achat, deux dépenses, un encaissement, une
/// immobilisation. Totaux : débit = crédit = 987 000.
void main() {
  late AppDatabase db;
  late ComptabiliteViewModel vm;
  final n = DateTime.now().year;

  Future<void> piece(
    String numero,
    int annee,
    int mois,
    int jour,
    String journal,
    List<(String, double, double, String?)> lignes, {
    String? venteRef,
    String? achatRef,
  }) async {
    await ComptabiliteRepositoryDrift(db).enregistrerPiece(
      date: DateTime(annee, mois, jour, 10),
      journalCode: journal,
      numeroPiece: numero,
      venteRef: venteRef,
      achatRef: achatRef,
      lignes: [
        for (final (compte, debit, credit, axe) in lignes)
          LigneAEcrire(
            numeroCompte: compte,
            debit: debit,
            credit: credit,
            libelle: 'Libelle $numero',
            axeAnalytique: axe,
          ),
      ],
    );
  }

  setUp(() async {
    db = AppDatabase.enMemoire();
    await SeedInitial(db).executer();
    await db
        .into(db.exerciceComptable)
        .insert(ExerciceComptableCompanion.insert(annee: Value(n - 1)));
    await db
        .into(db.planComptable)
        .insert(
          PlanComptableCompanion.insert(
            numeroCompte: '231',
            libelle: 'Bâtiments',
            classe: '2',
          ),
        );

    await piece('OD-P1-${n - 1}-0001', n - 1, 12, 20, 'OD', [
      ('531', 100000, 0, null),
      ('101', 0, 100000, null),
    ]);
    await piece('OD-P1-$n-0001', n, 1, 2, 'OD', [
      ('531', 500000, 0, null),
      ('101', 0, 500000, null),
    ]);
    await piece('V-P1-$n-001', n, 2, 15, 'VT', [
      ('531', 120000, 0, null),
      ('701', 0, 120000, 'Goliaths'),
    ], venteRef: 'V-P1-$n-001');
    await piece('V-P1-$n-002', n, 3, 10, 'VT', [
      ('531', 30000, 0, null),
      ('411', 50000, 0, null),
      ('707', 0, 80000, null),
    ], venteRef: 'V-P1-$n-002');
    await piece('ACH-P1-$n-001', n, 4, 12, 'AC', [
      ('601', 40000, 0, null),
      ('531', 0, 10000, null),
      ('401', 0, 30000, null),
    ], achatRef: 'ACH-P1-$n-001');
    await piece('DEP-P1-$n-0001', n, 5, 5, 'CA', [
      ('624', 15000, 0, 'Pintades'),
      ('531', 0, 15000, null),
    ]);
    await piece('DEP-P1-$n-0002', n, 5, 20, 'CA', [
      ('616', 12000, 0, null),
      ('401', 0, 12000, null),
    ]);
    await piece('REG-V-P1-$n-002', n, 6, 15, 'CA', [
      ('531', 20000, 0, null),
      ('411', 0, 20000, null),
    ], venteRef: 'V-P1-$n-002');
    await piece('OD-P1-$n-0002', n, 7, 1, 'OD', [
      ('231', 200000, 0, null),
      ('531', 0, 200000, null),
    ]);

    vm = ComptabiliteViewModel(ComptabiliteRepositoryDrift(db));
    await vm.charger();
    await vm.changerExercice(n);
  });

  tearDown(() => db.close());

  PosteEtat poste(List<PosteEtat> postes, String libelle) =>
      postes.firstWhere((p) => p.libelle == libelle);

  test('le jeu est équilibré : débit = crédit = 987 000', () {
    expect(vm.ecritures.fold<double>(0, (s, e) => s + e.debit), 987000);
    expect(vm.ecritures.fold<double>(0, (s, e) => s + e.credit), 987000);
  });

  test('résultat net 133 000 (produits 200 000, charges 67 000)', () {
    expect(vm.resultatNet, 133000);
    expect(vm.totalProduits, 200000);
    expect(vm.totalCharges, 67000);
    expect(vm.tresorerie, 445000);
  });

  test('bilan : actif = passif = 675 000, postes du jeu', () {
    final b = vm.bilan;
    expect(b.totalActif, 675000);
    expect(b.totalPassif, 675000);
    expect(b.estEquilibre, isTrue);
    expect(poste(b.actif, 'Immobilisations Corporelles').montant, 200000);
    expect(poste(b.actif, 'Créances et Emplois Assimilés').montant, 30000);
    expect(poste(b.actif, 'Trésorerie-Actif').montant, 445000);
    expect(poste(b.passif, 'Capital').montant, 500000);
    expect(poste(b.passif, 'Résultat Net de l\'Exercice').montant, 133000);
    expect(poste(b.passif, 'Dettes Circulantes').montant, 42000);
  });

  test('compte de résultat : marge 80 000, consommations 67 000, VA et EBE 133 000', () {
    final r = vm.compteResultat;
    expect(poste(r.postes, 'MARGE COMMERCIALE').montant, 80000);
    expect(poste(r.postes, 'Ventes de Produits Avicoles').montant, 120000);
    expect(
      poste(r.postes, 'Consommations en Provenance des Tiers').montant,
      -67000,
    );
    expect(poste(r.postes, 'VALEUR AJOUTÉE').montant, 133000);
    expect(poste(r.postes, 'EXCÉDENT BRUT D\'EXPLOITATION').montant, 133000);
    expect(r.resultatNet, 133000);
  });

  test('TAFIRE : exploitation 145 000, investissement −200 000, financement 267 000', () {
    final t = vm.tafire;
    expect(t.fluxExploitation, 145000);
    expect(t.fluxInvestissement, -200000);
    expect(t.fluxFinancement, 267000);
    expect(t.variation, 212000);
    expect(t.tresorerieOuverture, 100000);
    expect(t.tresorerieCloture, 312000);
    // Le bilan lit la trésorerie de l'exercice seul (445 000) : l'écart de 133 000 est
    // celui que le poste affiche (« Incohérence de … ») ; le web le reprend à l'identique.
    expect(t.tresorerieCloture - vm.tresorerie, -133000);
  });

  test('bilan de l\'entreprise : actif 475 000, passif 675 000, écart −200 000', () {
    final b = vm.bilanEntreprise;
    expect(b.totalActif, 475000);
    expect(b.totalPassif, 675000);
    expect(b.ecart, -200000);
    expect(b.estEquilibre, isFalse);
    expect(b.actif.firstWhere((p) => p.compte == '411').montant, 30000);
    expect(b.actif.firstWhere((p) => p.compte == '531').montant, 445000);
    expect(b.passif.firstWhere((p) => p.compte == '101').montant, 500000);
    expect(b.passif.firstWhere((p) => p.compte == '401').montant, 42000);
  });

  test('balance : ouverture 100 000, mouvements 987 000, soldes finaux 842 000', () {
    final l = vm.balance;
    double somme(double Function(LigneBalance) f) =>
        l.fold<double>(0, (s, x) => s + f(x));
    expect(somme((x) => x.ouvertureDebit), 100000);
    expect(somme((x) => x.ouvertureCredit), 100000);
    expect(somme((x) => x.mouvementsDebit), 987000);
    expect(somme((x) => x.mouvementsCredit), 987000);
    expect(vm.balanceTotalDebit, 842000);
    expect(vm.balanceTotalCredit, 842000);
    expect(vm.balanceEstEquilibree, isTrue);
    final c101 = l.firstWhere((x) => x.numeroCompte == '101');
    expect(
      (c101.ouvertureCredit, c101.mouvementsCredit, c101.finalCredit),
      (100000, 500000, 600000),
    );
    expect(l.firstWhere((x) => x.numeroCompte == '531').finalDebit, 545000);
    expect(l.firstWhere((x) => x.numeroCompte == '401').finalCredit, 42000);
    expect(l.any((x) => x.numeroCompte == '622'), isFalse);
  });

  test('grand livre du 531 : ouverture 100 000, débit 670 000, crédit 225 000, final 545 000', () {
    vm.selectionnerCompte('531');
    expect(vm.soldeOuvertureCompte, 100000);
    expect(vm.totalDebitCompte, 670000);
    expect(vm.totalCreditCompte, 225000);
    expect(vm.soldeFinalCompte, 545000);
    expect(
      vm.grandLivre.map((l) => l.soldeProgressif).take(4).toList(),
      [600000, 720000, 750000, 740000],
    );
  });

  test('grand livre : une période déplace l\'ouverture (740 000) sans fausser le final', () {
    vm.selectionnerCompte('531');
    vm.definirPeriodeGrandLivre(debut: DateTime(n, 5, 1));
    expect(vm.soldeOuvertureCompte, 740000);
    expect(vm.totalDebitCompte, 20000);
    expect(vm.totalCreditCompte, 215000);
    expect(vm.soldeFinalCompte, 545000);
  });

  test('grand livre : la borne de fin est incluse (au 15/06 : final 745 000)', () {
    vm.selectionnerCompte('531');
    vm.definirPeriodeGrandLivre(fin: DateTime(n, 6, 15));
    expect(vm.soldeFinalCompte, 745000);
  });

  test('grand livre d\'un compte créditeur : 701, final 120 000', () {
    vm.selectionnerCompte('701');
    expect(vm.compteCourant!.estDebiteurParNature, isFalse);
    expect(vm.soldeFinalCompte, 120000);
  });

  test('analytique : Goliaths 120 000, Pintades −15 000, Commerce 80 000, Avicole −40 000 ; structure 12 000', () {
    final c = {for (final x in vm.centresAnalytiques) x.nom: x};
    expect(c['Goliaths']!.revenus, 120000);
    expect(c['Goliaths']!.couts, 0);
    expect(c['Pintades']!.couts, 15000);
    expect(c['Commerce Annexe']!.revenus, 80000);
    expect(c['Commerce Annexe']!.detail, 'Comptes 707 et 602');
    expect(c['Avicole — filière non précisée']!.couts, 40000);
    final marges = vm.centresAnalytiques.fold<double>(0, (s, x) => s + x.marge);
    expect(marges, 145000);
    expect(vm.chargesNonAffectees, 12000);
    expect(vm.produitsNonAffectes, 0);
    // Invariant : Σ marges + produits non affectés − charges non affectées = résultat net.
    expect(
      marges + vm.produitsNonAffectes - vm.chargesNonAffectees,
      vm.resultatNet,
    );
  });

  test('dépenses : DEP-0001 payée 15 000, DEP-0002 en attente 12 000 ; fixes 12 000, variables 15 000', () {
    final d = {for (final x in vm.depenses) x.numeroPiece: x};
    expect(d.keys.toSet(), {'DEP-P1-$n-0001', 'DEP-P1-$n-0002'});
    expect(d['DEP-P1-$n-0001']!.payee, isTrue);
    expect(d['DEP-P1-$n-0001']!.montant, 15000);
    expect(d['DEP-P1-$n-0001']!.categorie, '624 - Transports');
    expect(d['DEP-P1-$n-0002']!.payee, isFalse);
    expect(d['DEP-P1-$n-0002']!.categorie, '616 - Assurances');
    expect(vm.chargesFixes, 12000);
    expect(vm.chargesVariables, 15000);
  });

  test('une dépense annulée (contrepassée) sort de la liste et rend 15 000 au résultat', () async {
    // Marque la pièce comme transmise : elle s'annule alors par l'écriture inverse.
    await (db.update(db.ecritureComptable)..where(
          (e) => e.numeroPiece.equals('DEP-P1-$n-0001'),
        ))
        .write(const EcritureComptableCompanion(syncStatus: Value('synced')));
    await vm.charger();

    expect(await vm.supprimerPiece('DEP-P1-$n-0001'), isNotNull);
    await vm.charger();

    expect(vm.depenses.map((d) => d.numeroPiece), ['DEP-P1-$n-0002']);
    expect(vm.resultatNet, 148000);
    expect(vm.chargesVariables, 0);
  });
}
