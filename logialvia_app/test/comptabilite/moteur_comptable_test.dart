import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/comptabilite/domain/entities/comptabilite.dart';
import 'package:logialvia_app/comptabilite/domain/services/moteur_comptable.dart';

Ecriture ecriture({
  required String compte,
  double debit = 0,
  double credit = 0,
  DateTime? date,
  String libelle = 'Test',
}) => Ecriture(
  id: '0',
  exerciceAnnee: 2026,
  numeroCompte: compte,
  date: date ?? DateTime(2026, 6, 15),
  debit: debit,
  credit: credit,
  libelle: libelle,
  journalCode: 'OD',
);

void main() {
  group('Partie double — validation d\'une écriture', () {
    test('refuse débit ET crédit sur la même ligne', () {
      expect(
        EcritureValidator.valider(
          debit: 100,
          credit: 50,
          libelle: 'Test',
          numeroCompte: '571',
        ),
        isNotNull,
      );
    });

    test('refuse une ligne sans montant', () {
      expect(
        EcritureValidator.valider(
          debit: 0,
          credit: 0,
          libelle: 'Test',
          numeroCompte: '571',
        ),
        isNotNull,
      );
    });

    test('refuse un montant négatif, un libellé ou un compte vide', () {
      expect(
        EcritureValidator.valider(
          debit: -1,
          credit: 0,
          libelle: 'Test',
          numeroCompte: '571',
        ),
        isNotNull,
      );
      expect(
        EcritureValidator.valider(
          debit: 100,
          credit: 0,
          libelle: '  ',
          numeroCompte: '571',
        ),
        isNotNull,
      );
      expect(
        EcritureValidator.valider(
          debit: 100,
          credit: 0,
          libelle: 'Test',
          numeroCompte: null,
        ),
        isNotNull,
      );
    });

    test('accepte une ligne valide', () {
      expect(
        EcritureValidator.valider(
          debit: 100,
          credit: 0,
          libelle: 'Vente',
          numeroCompte: '571',
        ),
        isNull,
      );
    });

    test('une pièce doit être équilibrée, ligne à ligne ne suffit pas', () {
      expect(
        EcritureValidator.validerLot(const [
          (debit: 12000.0, credit: 0.0),
          (debit: 0.0, credit: 11000.0),
        ]),
        isNotNull,
      );
      expect(
        EcritureValidator.validerLot(const [
          (debit: 3500.0, credit: 0.0),
          (debit: 8500.0, credit: 0.0),
          (debit: 0.0, credit: 12000.0),
        ]),
        isNull,
      );
    });
  });

  group('BR-CPT-007 — sens du solde selon la nature du compte', () {
    test('classes 2, 3 et 6 sont débitrices par nature', () {
      for (final classe in ['2', '3', '6']) {
        expect(
          CompteComptable(
            numero: '${classe}01',
            libelle: 'X',
            classe: classe,
          ).estDebiteurParNature,
          isTrue,
          reason: 'classe $classe',
        );
      }
    });

    test('classes 1 et 7 sont créditrices par nature', () {
      for (final classe in ['1', '7']) {
        expect(
          CompteComptable(
            numero: '${classe}01',
            libelle: 'X',
            classe: classe,
          ).estDebiteurParNature,
          isFalse,
          reason: 'classe $classe',
        );
      }
    });

    test('la classe 4 est bidirectionnelle — Clients débiteur, Fournisseurs '
        'créditeur, et Doc F6 §2 les mettait tous deux du même côté', () {
      const clients = CompteComptable(
        numero: '411',
        libelle: 'Clients',
        classe: '4',
      );
      const fournisseurs = CompteComptable(
        numero: '401',
        libelle: 'Fournisseurs',
        classe: '4',
      );
      const avances = CompteComptable(
        numero: '419',
        libelle: 'Clients — Avances Reçues',
        classe: '4',
      );

      expect(clients.estDebiteurParNature, isTrue);
      expect(fournisseurs.estDebiteurParNature, isFalse);
      // 419 est en classe 4 comme 411, mais crediteur : une regle fondee sur
      // la seule classe se tromperait.
      expect(avances.estDebiteurParNature, isFalse);
    });

    test('la trésorerie (classe 5) est débitrice', () {
      const caisse = CompteComptable(
        numero: '571',
        libelle: 'Caisse',
        classe: '5',
      );
      expect(caisse.estDebiteurParNature, isTrue);
    });
  });

  group('Grand Livre — solde progressif', () {
    test('sur un compte débiteur, le débit fait monter le solde', () {
      const caisse = CompteComptable(
        numero: '571',
        libelle: 'Caisse',
        classe: '5',
      );

      final lignes = const GrandLivreCalculator().calculer(
        compte: caisse,
        soldeOuverture: 100000,
        ecritures: [
          ecriture(compte: '571', debit: 12000, date: DateTime(2026, 6, 1)),
          ecriture(compte: '571', credit: 5000, date: DateTime(2026, 6, 2)),
          ecriture(compte: '571', debit: 3000, date: DateTime(2026, 6, 3)),
        ],
      );

      expect(lignes.map((l) => l.soldeProgressif), [112000, 107000, 110000]);
    });

    test('sur un compte de produits, c\'est le crédit qui fait monter', () {
      const ventes = CompteComptable(
        numero: '702',
        libelle: 'Ventes',
        classe: '7',
      );

      final lignes = const GrandLivreCalculator().calculer(
        compte: ventes,
        soldeOuverture: 0,
        ecritures: [
          ecriture(compte: '702', credit: 12000, date: DateTime(2026, 6, 1)),
          ecriture(compte: '702', credit: 8000, date: DateTime(2026, 6, 2)),
        ],
      );

      expect(lignes.last.soldeProgressif, 20000);
    });

    test(
      'les écritures sont triées chronologiquement, quel que soit l\'ordre',
      () {
        const caisse = CompteComptable(
          numero: '571',
          libelle: 'Caisse',
          classe: '5',
        );

        final lignes = const GrandLivreCalculator().calculer(
          compte: caisse,
          soldeOuverture: 0,
          ecritures: [
            ecriture(compte: '571', debit: 300, date: DateTime(2026, 6, 3)),
            ecriture(compte: '571', debit: 100, date: DateTime(2026, 6, 1)),
            ecriture(compte: '571', debit: 200, date: DateTime(2026, 6, 2)),
          ],
        );

        expect(lignes.map((l) => l.soldeProgressif), [100, 300, 600]);
      },
    );
  });

  group('Balance Générale — BR-CPT-004', () {
    const comptes = [
      CompteComptable(numero: '571', libelle: 'Caisse', classe: '5'),
      CompteComptable(numero: '702', libelle: 'Ventes Avicoles', classe: '7'),
      CompteComptable(numero: '602', libelle: 'Achats Matières', classe: '6'),
    ];

    test('une comptabilité en partie double est toujours équilibrée', () {
      final lignes = const BalanceCalculator().calculer(
        comptes: comptes,
        ecrituresAnterieures: const [],
        ecrituresPeriode: [
          ecriture(compte: '571', debit: 12000),
          ecriture(compte: '702', credit: 12000),
          ecriture(compte: '602', debit: 5000),
          ecriture(compte: '571', credit: 5000),
        ],
      );

      expect(BalanceGeneraleValidator.estEquilibree(lignes), isTrue);
      expect(BalanceGeneraleValidator.ecart(lignes), closeTo(0, 0.01));
    });

    test('une écriture déséquilibrée est détectée', () {
      final lignes = const BalanceCalculator().calculer(
        comptes: comptes,
        ecrituresAnterieures: const [],
        ecrituresPeriode: [
          ecriture(compte: '571', debit: 12000),
          ecriture(compte: '702', credit: 11000), // 1 000 manquants
        ],
      );

      expect(BalanceGeneraleValidator.estEquilibree(lignes), isFalse);
      expect(BalanceGeneraleValidator.ecart(lignes), closeTo(1000, 0.01));
    });

    test('un solde n\'apparaît que d\'un seul côté', () {
      final lignes = const BalanceCalculator().calculer(
        comptes: comptes,
        ecrituresAnterieures: const [],
        ecrituresPeriode: [
          ecriture(compte: '571', debit: 12000),
          ecriture(compte: '702', credit: 12000),
        ],
      );

      final caisse = lignes.firstWhere((l) => l.numeroCompte == '571');
      expect(caisse.finalDebit, 12000);
      expect(caisse.finalCredit, 0);

      final ventes = lignes.firstWhere((l) => l.numeroCompte == '702');
      expect(ventes.finalDebit, 0);
      expect(ventes.finalCredit, 12000);
    });

    test('les soldes d\'ouverture viennent des écritures antérieures', () {
      final lignes = const BalanceCalculator().calculer(
        comptes: comptes,
        ecrituresAnterieures: [
          ecriture(compte: '571', debit: 50000, date: DateTime(2026, 1, 5)),
        ],
        ecrituresPeriode: [ecriture(compte: '571', debit: 12000)],
      );

      final caisse = lignes.single;
      expect(caisse.ouvertureDebit, 50000);
      expect(caisse.mouvementsDebit, 12000);
      expect(caisse.finalDebit, 62000);
    });

    test('un compte sans mouvement n\'apparaît pas dans la balance', () {
      final lignes = const BalanceCalculator().calculer(
        comptes: comptes,
        ecrituresAnterieures: const [],
        ecrituresPeriode: [ecriture(compte: '571', debit: 1)],
      );
      expect(lignes, hasLength(1));
    });
  });

  group('BR-CPT-005 — Résultat Net, source unique', () {
    final ecritures = [
      // Ventes 20 000
      ecriture(compte: '702', credit: 12000),
      ecriture(compte: '701', credit: 8000),
      // Charges 9 000
      ecriture(compte: '602', debit: 6000),
      ecriture(compte: '604', debit: 3000),
      // Contrepartie trésorerie
      ecriture(compte: '571', debit: 20000),
      ecriture(compte: '571', credit: 9000),
    ];

    test('Résultat = Produits − Charges', () {
      final soldes = SoldesComptes.depuis(ecritures);
      expect(CalculerResultatNet.produits(soldes), 20000);
      expect(CalculerResultatNet.charges(soldes), 9000);
      expect(CalculerResultatNet.calculer(soldes), 11000);
    });

    test('le Bilan, le Compte de Résultat et le TAFIRE affichent le MÊME '
        'résultat — c\'est l\'exigence de BR-CPT-005', () {
      final soldes = SoldesComptes.depuis(ecritures);
      final source = CalculerResultatNet.calculer(soldes);

      final compteResultat = const CompteResultatCalculator().calculer(soldes);
      final bilan = const BilanCalculator().calculer(soldes);
      final tafire = const TafireCalculator().calculer(
        soldes: soldes,
        soldesOuverture: SoldesComptes.depuis(const []),
      );

      expect(compteResultat.resultatNet, source);

      final posteBilan = bilan.passif.firstWhere(
        (p) => p.libelle == 'Résultat Net de l\'Exercice',
      );
      expect(posteBilan.montant, source);

      final posteTafire = tafire.postes.firstWhere(
        (p) => p.libelle == 'Résultat Net de l\'Exercice',
      );
      expect(posteTafire.montant, source);
    });

    test('une perte donne un résultat négatif', () {
      final soldes = SoldesComptes.depuis([
        ecriture(compte: '702', credit: 5000),
        ecriture(compte: '602', debit: 8000),
      ]);
      expect(CalculerResultatNet.calculer(soldes), -3000);
    });

    test('sans aucune écriture, le résultat est nul', () {
      expect(CalculerResultatNet.calculer(SoldesComptes.depuis(const [])), 0);
    });
  });

  group('Bilan — équilibre Actif = Passif', () {
    test('un apport en capital équilibre le bilan', () {
      // 101 Capital 500 000 au crédit, 531 Caisse 500 000 au débit.
      final soldes = SoldesComptes.depuis([
        ecriture(compte: '571', debit: 500000),
        ecriture(compte: '101', credit: 500000),
      ]);

      final bilan = const BilanCalculator().calculer(soldes);
      expect(bilan.totalActif, 500000);
      expect(bilan.totalPassif, 500000);
      expect(bilan.estEquilibre, isTrue);
    });

    test('une vente comptant conserve l\'équilibre', () {
      final soldes = SoldesComptes.depuis([
        ecriture(compte: '571', debit: 500000),
        ecriture(compte: '101', credit: 500000),
        ecriture(compte: '571', debit: 12000),
        ecriture(compte: '702', credit: 12000),
      ]);

      final bilan = const BilanCalculator().calculer(soldes);
      // Actif : tresorerie 512 000. Passif : capital 500 000 + resultat 12 000.
      expect(bilan.totalActif, 512000);
      expect(bilan.totalPassif, 512000);
      expect(bilan.estEquilibre, isTrue);
    });

    test('une vente à crédit place la créance à l\'actif', () {
      final soldes = SoldesComptes.depuis([
        ecriture(compte: '571', debit: 3500),
        ecriture(compte: '411', debit: 8500),
        ecriture(compte: '702', credit: 12000),
      ]);

      final bilan = const BilanCalculator().calculer(soldes);
      final creances = bilan.actif.firstWhere(
        (p) => p.libelle == 'Créances et Emplois Assimilés',
      );
      expect(creances.montant, 8500);
      expect(bilan.estEquilibre, isTrue);
    });

    test('un achat à crédit place la dette au passif', () {
      final soldes = SoldesComptes.depuis([
        ecriture(compte: '602', debit: 30000),
        ecriture(compte: '571', credit: 10000),
        ecriture(compte: '401', credit: 20000),
      ]);

      final bilan = const BilanCalculator().calculer(soldes);
      final dettes = bilan.passif.firstWhere(
        (p) => p.libelle == 'Dettes Circulantes',
      );
      expect(dettes.montant, 20000);
      expect(bilan.estEquilibre, isTrue);
    });

    test('un bilan vide est équilibré à zéro', () {
      final bilan = const BilanCalculator().calculer(
        SoldesComptes.depuis(const []),
      );
      expect(bilan.totalActif, 0);
      expect(bilan.totalPassif, 0);
      expect(bilan.estEquilibre, isTrue);
    });
  });

  group('Compte de Résultat — cascade SYSCOHADA', () {
    test('marge commerciale = ventes marchandises − achats marchandises', () {
      final soldes = SoldesComptes.depuis([
        ecriture(compte: '701', credit: 18500),
        ecriture(compte: '601', debit: 11000),
      ]);

      final cr = const CompteResultatCalculator().calculer(soldes);
      final marge = cr.postes.firstWhere(
        (p) => p.libelle == 'MARGE COMMERCIALE',
      );
      expect(marge.montant, 7500);
    });

    test('la valeur ajoutée retranche les consommations de tiers', () {
      final soldes = SoldesComptes.depuis([
        ecriture(compte: '702', credit: 100000),
        ecriture(compte: '602', debit: 30000),
        ecriture(compte: '604', debit: 5000),
      ]);

      final cr = const CompteResultatCalculator().calculer(soldes);
      final va = cr.postes.firstWhere((p) => p.libelle == 'VALEUR AJOUTÉE');
      // 100 000 − 0 (marchandises) − (30 000 + 5 000)
      expect(va.montant, 65000);
    });

    test('la cascade se termine sur le même résultat que la source unique', () {
      final soldes = SoldesComptes.depuis([
        ecriture(compte: '702', credit: 100000),
        ecriture(compte: '701', credit: 18500),
        ecriture(compte: '602', debit: 30000),
        ecriture(compte: '601', debit: 11000),
        ecriture(compte: '604', debit: 5000),
      ]);

      final cr = const CompteResultatCalculator().calculer(soldes);
      final dernierPoste = cr.postes.last;
      expect(dernierPoste.libelle, 'RÉSULTAT NET DE L\'EXERCICE');
      expect(dernierPoste.montant, cr.resultatNet);
      expect(cr.resultatNet, 72500); // 118 500 − 46 000
    });
  });

  group('TAFIRE', () {
    test('la trésorerie de clôture = ouverture + variation', () {
      final ouverture = SoldesComptes.depuis([
        ecriture(compte: '571', debit: 50000, date: DateTime(2025, 12, 31)),
        ecriture(compte: '101', credit: 50000, date: DateTime(2025, 12, 31)),
      ]);
      final soldes = SoldesComptes.depuis([
        ecriture(compte: '571', debit: 50000, date: DateTime(2025, 12, 31)),
        ecriture(compte: '101', credit: 50000, date: DateTime(2025, 12, 31)),
        ecriture(compte: '571', debit: 12000),
        ecriture(compte: '702', credit: 12000),
      ]);

      final tafire = const TafireCalculator().calculer(
        soldes: soldes,
        soldesOuverture: ouverture,
      );

      expect(tafire.tresorerieOuverture, 50000);
      expect(
        tafire.tresorerieCloture,
        tafire.tresorerieOuverture + tafire.variation,
      );
    });

    test('le flux d\'exploitation part du résultat net', () {
      final soldes = SoldesComptes.depuis([
        ecriture(compte: '571', debit: 12000),
        ecriture(compte: '702', credit: 12000),
      ]);
      final tafire = const TafireCalculator().calculer(
        soldes: soldes,
        soldesOuverture: SoldesComptes.depuis(const []),
      );

      expect(tafire.fluxExploitation, 12000);
    });
  });
}
