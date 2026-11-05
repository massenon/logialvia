import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/services/calcul_fiche_journaliere.dart';

/// Tests du document le plus critique du projet (Doc 05).
///
/// Strict Avoid §2 impose de couvrir explicitement les cas limites qui ont
/// historiquement casse : effectif de depart nul, mortalite egale a l'effectif,
/// vente superieure au stock disponible, et surtout la separation stricte des
/// mouvements par categorie.
void main() {
  const goliaths = ConfigurationsEspeces.goliaths;
  const calcul = CalculFicheJournaliere(goliaths);

  group('Séparation stricte par catégorie — le bug historique n°1', () {
    test(
      'une mortalité sur une seule catégorie ne touche QUE cette catégorie',
      () {
        final resultat = calcul.calculerJour(
          effectifsVeille: const [40, 30, 24],
          effectifTotalVeille: 94,
          mouvements: const MouvementsJour(
            mortsParCategorie: [0, 0, 5], // 5 morts, uniquement sur Mature
            donsParCategorie: [0, 0, 0],
          ),
        );

        // Poussins et Goliathau sont STRICTEMENT inchanges. Avec l'ancienne
        // repartition en % fixe, les 3 categories auraient bouge.
        expect(resultat.categorie(0), 40);
        expect(resultat.categorie(1), 30);
        expect(resultat.categorie(2), 19);
        expect(resultat.effectifTotal, 89);
      },
    );

    test('achats et naissances alimentent uniquement la catégorie jeune', () {
      final resultat = calcul.calculerJour(
        effectifsVeille: const [40, 30, 24],
        effectifTotalVeille: 94,
        mouvements: const MouvementsJour(achat: 10, ne: 5),
      );

      expect(resultat.categorie(0), 55); // 40 + 10 + 5
      expect(resultat.categorie(1), 30); // inchangé
      expect(resultat.categorie(2), 24); // inchangé
      expect(resultat.effectifTotal, 109);
    });

    test('la vente est déduite du Goliathau, PAS du Mature '
        '(malgré le libellé « Mature — Éligible à la Vente »)', () {
      final resultat = calcul.calculerJour(
        effectifsVeille: const [40, 30, 24],
        effectifTotalVeille: 94,
        mouvements: const MouvementsJour(vente: 6),
      );

      expect(resultat.categorie(0), 40);
      expect(resultat.categorie(1), 24); // 30 − 6 : c'est bien ici
      expect(resultat.categorie(2), 24); // Mature intact
      expect(resultat.effectifTotal, 88);
    });

    test('les dons se comportent comme les morts, catégorie par catégorie', () {
      final resultat = calcul.calculerJour(
        effectifsVeille: const [40, 30, 24],
        effectifTotalVeille: 94,
        mouvements: const MouvementsJour(donsParCategorie: [3, 0, 2]),
      );

      expect(resultat.categorie(0), 37);
      expect(resultat.categorie(1), 30);
      expect(resultat.categorie(2), 22);
      expect(resultat.effectifTotal, 89);
    });

    test('mouvements combinés sur toutes les catégories', () {
      final resultat = calcul.calculerJour(
        effectifsVeille: const [40, 30, 24],
        effectifTotalVeille: 94,
        mouvements: const MouvementsJour(
          achat: 5,
          ne: 3,
          vente: 4,
          mortsParCategorie: [2, 1, 1],
          donsParCategorie: [1, 0, 0],
        ),
      );

      expect(resultat.categorie(0), 45); // 40 + 5 + 3 − 2 − 1
      expect(resultat.categorie(1), 25); // 30 − 4 − 1
      expect(resultat.categorie(2), 23); // 24 − 1
      // 94 + 8 − 4 (morts) − 4 (vente) − 1 (don) = 93
      expect(resultat.effectifTotal, 93);
      expect(resultat.parCategorie.reduce((a, b) => a + b), 93);
    });
  });

  group('Cas limites (Strict Avoid §2)', () {
    test('effectif de départ à zéro ne produit aucun négatif', () {
      final resultat = calcul.calculerJour(
        effectifsVeille: const [0, 0, 0],
        effectifTotalVeille: 0,
        mouvements: const MouvementsJour(mortsParCategorie: [5, 5, 5]),
      );

      expect(resultat.parCategorie, [0, 0, 0]);
      expect(resultat.effectifTotal, 0);
      // Taux de mortalite sur un effectif nul : 0, pas une division par zero.
      expect(resultat.tauxMortalite, 0);
    });

    test('mortalité égale à l\'effectif total le ramène à zéro', () {
      final resultat = calcul.calculerJour(
        effectifsVeille: const [40, 30, 24],
        effectifTotalVeille: 94,
        mouvements: const MouvementsJour(mortsParCategorie: [40, 30, 24]),
      );

      expect(resultat.parCategorie, [0, 0, 0]);
      expect(resultat.effectifTotal, 0);
      expect(resultat.tauxMortalite, 100);
    });

    test(
      'une vente supérieure au stock est bornée à zéro, jamais négative',
      () {
        final resultat = calcul.calculerJour(
          effectifsVeille: const [40, 30, 24],
          effectifTotalVeille: 94,
          mouvements: const MouvementsJour(vente: 999),
        );

        expect(resultat.categorie(1), 0);
        expect(resultat.effectifTotal, 0);
      },
    );

    test('une journée sans aucun mouvement laisse tout inchangé', () {
      final resultat = calcul.calculerJour(
        effectifsVeille: const [40, 30, 24],
        effectifTotalVeille: 94,
        mouvements: const MouvementsJour(),
      );

      expect(resultat.parCategorie, [40, 30, 24]);
      expect(resultat.effectifTotal, 94);
      expect(resultat.tauxMortalite, 0);
    });
  });

  group('Taux de mortalité du jour', () {
    test('(morts ÷ effectif J-1) × 100', () {
      expect(
        CalculFicheJournaliere.tauxMortaliteJour(2, 94),
        closeTo(2.13, 0.01),
      );
      expect(CalculFicheJournaliere.tauxMortaliteJour(0, 94), 0);
    });

    test('effectif J-1 nul renvoie 0 sans exception', () {
      expect(CalculFicheJournaliere.tauxMortaliteJour(3, 0), 0);
    });
  });

  group('Répartition initiale (Doc 05 §2 — ratio 35/35/reste)', () {
    test('répartit un effectif de base sur les 3 catégories', () {
      final repartition = calcul.repartitionInitiale(94);

      expect(repartition[0], 33); // jeune : 35 % arrondi
      expect(repartition[1], 33); // commercialisée : 35 %
      expect(repartition[2], 28); // reste
      expect(repartition.reduce((a, b) => a + b), 94);
    });

    test('un effectif de base nul donne des zéros, pas une erreur', () {
      expect(calcul.repartitionInitiale(0), [0, 0, 0]);
    });

    test('la somme est toujours exactement l\'effectif de base', () {
      for (final base in [1, 7, 31, 94, 187, 410]) {
        final repartition = calcul.repartitionInitiale(base);
        expect(
          repartition.reduce((a, b) => a + b),
          base,
          reason: 'la répartition doit conserver le total pour base=$base',
        );
      }
    });
  });

  group('Provende — le total somme TOUTES les catégories (bug Doc 05 §4)', () {
    test('Goliaths : 30 / 60 / 110 g par jour', () {
      // 40×30 + 30×60 + 24×110 = 1200 + 1800 + 2640 = 5640
      expect(calcul.provendeTotaleGrammes(const [40, 30, 24]), 5640);
    });

    test(
      'Pondeuses : les 4 catégories sont sommées, pas seulement Pondeuse',
      () {
        const calculPondeuses = CalculFicheJournaliere(
          ConfigurationsEspeces.pondeuses,
        );
        // 10×30 + 20×60 + 30×80 + 40×110 = 300 + 1200 + 2400 + 4400 = 8300
        final total = calculPondeuses.provendeTotaleGrammes(const [
          10,
          20,
          30,
          40,
        ]);
        expect(total, 8300);
        // Le bug historique ne comptait que la derniere categorie (4400).
        expect(total, isNot(4400));
      },
    );

    test('effectifs nuls donnent une provende nulle', () {
      expect(calcul.provendeTotaleGrammes(const [0, 0, 0]), 0);
    });
  });

  group('Poids moyen', () {
    test('poids total ÷ effectif, arrondi', () {
      expect(
        CalculFicheJournaliere.poidsMoyenGrammes(
          poidsTotalGrammes: 263200,
          effectif: 94,
        ),
        2800,
      );
    });

    test('effectif nul renvoie 0 sans division par zéro', () {
      expect(
        CalculFicheJournaliere.poidsMoyenGrammes(
          poidsTotalGrammes: 5000,
          effectif: 0,
        ),
        0,
      );
    });
  });

  group('Stock d\'œufs Pondeuses — le bug le plus grave du projet', () {
    test(
      'SRH + pondus − cassés = Total Stock, moins sorties = Stock Final',
      () {
        final jour = CalculStockOeufs.calculerJour(
          srhOuverture: 120,
          oeufsPondus: 400,
          oeufsCasses: 10,
          sortiesPlateaux: 3,
        );

        expect(jour.srh, 120);
        expect(jour.totalStock, 510); // 120 + (400 − 10)
        expect(jour.sortiesOeufs, 90); // 3 plateaux × 30
        expect(jour.stockFinal, 420);
      },
    );

    test(
      'le SRH du lendemain est le Stock Final de la veille, PAS son Total Stock',
      () {
        final jour1 = CalculStockOeufs.calculerJour(
          srhOuverture: 100,
          oeufsPondus: 300,
          oeufsCasses: 0,
          sortiesPlateaux: 5, // 150 œufs sortis
        );
        expect(jour1.totalStock, 400);
        expect(jour1.stockFinal, 250);

        final jour2 = CalculStockOeufs.calculerJour(
          srhOuverture: jour1.stockFinal,
          oeufsPondus: 200,
          oeufsCasses: 0,
          sortiesPlateaux: 0,
        );

        // La regle : SRH(J+1) = StockFinal(J) = 250, et surtout PAS
        // TotalStock(J) = 400. C'est exactement l'erreur historique.
        expect(jour2.srh, 250);
        expect(jour2.srh, isNot(jour1.totalStock));
        expect(jour2.totalStock, 450);
      },
    );

    test('un jour sans sortie fait coïncider Total Stock et Stock Final '
        '— c\'est ce qui masquait le bug', () {
      final jour = CalculStockOeufs.calculerJour(
        srhOuverture: 100,
        oeufsPondus: 200,
        oeufsCasses: 0,
        sortiesPlateaux: 0,
      );

      expect(jour.totalStock, jour.stockFinal);
    });

    test('chaîne de 5 jours consécutifs avec sorties variables', () {
      // Tracage manuel exige par Strict Avoid §2 avant de considerer une
      // fonction de calcul terminee.
      const pondus = [300, 280, 310, 290, 305];
      const casses = [5, 0, 10, 2, 0];
      const sorties = [0, 4, 0, 6, 3]; // en plateaux

      var srh = 0;
      final stocksFinaux = <int>[];
      for (var i = 0; i < 5; i++) {
        final jour = CalculStockOeufs.calculerJour(
          srhOuverture: srh,
          oeufsPondus: pondus[i],
          oeufsCasses: casses[i],
          sortiesPlateaux: sorties[i],
        );
        stocksFinaux.add(jour.stockFinal);
        srh = jour.stockFinal;
      }

      // J1 : 0 + 295 = 295, −0   -> 295
      // J2 : 295 + 280 = 575, −120 -> 455
      // J3 : 455 + 300 = 755, −0   -> 755
      // J4 : 755 + 288 = 1043, −180 -> 863
      // J5 : 863 + 305 = 1168, −90 -> 1078
      expect(stocksFinaux, [295, 455, 755, 863, 1078]);
    });

    test('les sorties ne peuvent pas rendre le stock négatif', () {
      final jour = CalculStockOeufs.calculerJour(
        srhOuverture: 10,
        oeufsPondus: 20,
        oeufsCasses: 0,
        sortiesPlateaux: 99,
      );
      expect(jour.stockFinal, 0);
    });

    test('plus d\'œufs cassés que pondus ne produit pas de négatif', () {
      final jour = CalculStockOeufs.calculerJour(
        srhOuverture: 50,
        oeufsPondus: 10,
        oeufsCasses: 40,
        sortiesPlateaux: 0,
      );
      expect(jour.totalStock, 50); // 50 + 0
    });
  });

  group('Configuration des espèces', () {
    test(
      'chaque fiche à 3 catégories a bien une jeune et une commercialisée',
      () {
        for (final config in [
          ConfigurationsEspeces.goliaths,
          ConfigurationsEspeces.pintades,
          ConfigurationsEspeces.lapins,
          ConfigurationsEspeces.poissonsChats,
          ConfigurationsEspeces.poulets,
        ]) {
          expect(config.categories, hasLength(3), reason: config.identifiant);
          expect(
            config.indexCategorieJeune,
            isNonNegative,
            reason: config.identifiant,
          );
          expect(
            config.indexCategorieCommercialisee,
            isNonNegative,
            reason: config.identifiant,
          );
          expect(
            config.indexCategorieJeune,
            isNot(config.indexCategorieCommercialisee),
            reason: config.identifiant,
          );
        }
      },
    );

    test('Pondeuses a 4 catégories (Doc 05 §4)', () {
      expect(ConfigurationsEspeces.pondeuses.categories, hasLength(4));
      // Achat sur Poussin Ponte, vente sur Pondeuse.
      expect(ConfigurationsEspeces.pondeuses.indexCategorieJeune, 0);
      expect(ConfigurationsEspeces.pondeuses.indexCategorieCommercialisee, 3);
    });

    test('la correspondance des catégories suit Doc 05 §3', () {
      expect(ConfigurationsEspeces.goliaths.categories.map((c) => c.libelle), [
        'Poussins',
        'Goliathau',
        'Mature',
      ]);
      expect(ConfigurationsEspeces.lapins.categories.map((c) => c.libelle), [
        'Lapereau',
        'Chair',
        'Reproducteur',
      ]);
      expect(
        ConfigurationsEspeces.poissonsChats.categories.map((c) => c.libelle),
        ['Alevin', 'Juvénile', 'Mature'],
      );
    });
  });
}
