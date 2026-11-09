import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/comptabilite/domain/entities/comptabilite.dart';
import 'package:logialvia_app/comptabilite/domain/services/bilan_entreprise.dart';
import 'package:logialvia_app/comptabilite/domain/services/moteur_comptable.dart';

Ecriture ligne({required String compte, double debit = 0, double credit = 0}) =>
    Ecriture(
      id: '0',
      exerciceAnnee: 2026,
      numeroCompte: compte,
      date: DateTime(2026, 6, 15),
      debit: debit,
      credit: credit,
      libelle: 'Test',
      journalCode: 'OD',
    );

BilanEntreprise calculer(List<Ecriture> ecritures) =>
    const BilanEntrepriseCalculator().calculer(SoldesComptes.depuis(ecritures));

void main() {
  group('Bilan de l\'Entreprise — les 7 postes', () {
    test('chaque poste lit son propre compte', () {
      final bilan = calculer([
        ligne(compte: '311', debit: 186400), // stocks
        ligne(compte: '411', debit: 7000), // clients
        ligne(compte: '512', debit: 225000), // Mobile Money
        ligne(compte: '531', debit: 87000), // caisse
        ligne(compte: '101', credit: 493400), // capital
        ligne(compte: '401', credit: 12000), // fournisseurs
      ]);

      expect(bilan.actif.map((p) => p.montant), [186400, 7000, 225000, 87000]);
      expect(bilan.totalActif, 505400);

      // Capital 493 400 + resultat 0 + dettes 12 000.
      expect(bilan.passif.map((p) => p.montant), [493400, 0, 12000]);
      expect(bilan.totalPassif, 505400);
      expect(bilan.estEquilibre, isTrue);
      expect(bilan.ecart, 0);
    });

    test('les comptes de passif sont présentés en positif', () {
      final bilan = calculer([ligne(compte: '401', credit: 12000)]);
      final fournisseurs = bilan.passif.last;

      expect(fournisseurs.compte, '401');
      expect(
        fournisseurs.montant,
        12000,
        reason:
            'Une dette de 12 000 s\'affiche 12 000, pas −12 000 : le passif '
            'répond à « d\'où vient l\'argent », pas à un sens de solde.',
      );
    });

    test('le résultat de l\'exercice vient du moteur, pas d\'un compte 13', () {
      // BR-CPT-005 : le resultat est produits − charges, calcule.
      final bilan = calculer([
        ligne(compte: '531', debit: 100000),
        ligne(compte: '701', credit: 100000), // vente
        ligne(compte: '601', debit: 26000), // achat
        ligne(compte: '401', credit: 26000),
      ]);

      final resultat = bilan.passif[1];
      expect(resultat.compte, '13');
      expect(resultat.montant, 74000);
    });

    test('les stocks agrègent les comptes 31 et 32', () {
      final bilan = calculer([
        ligne(compte: '311', debit: 100000),
        ligne(compte: '321', debit: 86400),
      ]);
      expect(bilan.actif.first.montant, 186400);
      expect(bilan.actif.first.compte, '31/32');
    });
  });

  group('L\'équilibre est un contrôle, pas une mise en scène', () {
    test('sans apport au 101, l\'écart est exposé au lieu d\'être absorbé', () {
      // Exactement la situation que le prototype masquait : il posait
      // capitalInitial = totalActif − dettes − resultat, donc l'egalite
      // tombait juste par construction.
      final bilan = calculer([
        ligne(compte: '531', debit: 87000),
        ligne(compte: '401', credit: 12000),
        ligne(compte: '601', debit: 12000), // pour equilibrer l'ecriture
      ]);

      expect(bilan.estEquilibre, isFalse);
      expect(
        bilan.ecart,
        87000,
        reason:
            'Passif = 0 de capital − 12 000 de resultat + 12 000 de dettes '
            '= 0. Les 87 000 en caisse n\'ont aucune origine enregistree, '
            'et c\'est exactement ce que l\'ecran doit dire.',
      );
    });

    test('un bilan sans aucune écriture est vide, pas équilibré', () {
      final bilan = calculer(const []);

      expect(bilan.estVide, isTrue);
      expect(
        bilan.totalActif,
        0,
        reason: 'Aucun bien ne peut figurer a l\'actif d\'un exercice vierge.',
      );
    });

    test('un écart au centime ne déclenche pas d\'alerte', () {
      final bilan = calculer([
        ligne(compte: '531', debit: 1000.004),
        ligne(compte: '101', credit: 1000),
      ]);
      expect(bilan.estEquilibre, isTrue);
    });

    test('un passif supérieur à l\'actif donne un écart négatif', () {
      final bilan = calculer([ligne(compte: '101', credit: 50000)]);

      expect(bilan.ecart, -50000);
      expect(bilan.estEquilibre, isFalse);
    });
  });

  group('Cohérence avec l\'onglet Bilan des États Financiers', () {
    test('les deux bilans annoncent le même résultat net (BR-CPT-005)', () {
      final ecritures = [
        ligne(compte: '531', debit: 100000),
        ligne(compte: '701', credit: 100000),
        ligne(compte: '601', debit: 26000),
        ligne(compte: '401', credit: 26000),
      ];
      final soldes = SoldesComptes.depuis(ecritures);

      final simplifie = const BilanEntrepriseCalculator().calculer(soldes);
      final reglementaire = const BilanCalculator().calculer(soldes);

      expect(simplifie.passif[1].montant, CalculerResultatNet.calculer(soldes));

      final resultatReglementaire = reglementaire.passif.firstWhere(
        (p) => p.libelle.contains('Résultat'),
      );
      expect(
        resultatReglementaire.montant,
        simplifie.passif[1].montant,
        reason:
            'Les deux ecrans lisent les memes ecritures : un resultat net '
            'different d\'un ecran a l\'autre violerait BR-CPT-005.',
      );
    });
  });
}
