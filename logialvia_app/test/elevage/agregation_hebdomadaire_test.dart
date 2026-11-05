import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/elevage/domain/entities/journee_elevage.dart';
import 'package:logialvia_app/elevage/domain/services/agregation_hebdomadaire.dart';

/// Vue Hebdomadaire — `renderWeeklyGrid()` de `fiche-goliaths.html` l.794.
void main() {
  const agregation = AgregationHebdomadaire();

  JourneeElevage journee({
    required int jour,
    int achat = 0,
    int ne = 0,
    int vente = 0,
    List<int> morts = const [0, 0, 0],
    required int effectif,
    bool saisie = true,
  }) => JourneeElevage(
    espece: 'goliaths',
    date: DateTime(2026, 8, jour),
    achat: achat,
    ne: ne,
    vente: vente,
    mortsParCategorie: morts,
    donsParCategorie: const [0, 0, 0],
    effectif: effectif,
    effectifsParCategorie: const [0, 0, 0],
    isRecorded: saisie,
  );

  group('Découpe du mois — le prototype la codait en dur', () {
    test('un mois de 31 jours donne 4 semaines, la dernière de 10', () {
      expect(agregation.decouper(31), [(1, 7), (8, 14), (15, 21), (22, 31)]);
    });

    test('février ne fabrique pas de jours qui n\'existent pas', () {
      expect(
        agregation.decouper(28),
        [(1, 7), (8, 14), (15, 21), (22, 28)],
        reason:
            'Le prototype ecrit `[[1,7],[8,14],[15,21],[22,31]]` en dur et '
            'etiquette « 22-31 aout » : en fevrier il annoncerait 3 jours '
            'inexistants.',
      );
    });

    test('une année bissextile va jusqu\'au 29', () {
      expect(agregation.decouper(29).last, (22, 29));
    });

    test('un mois de 30 jours aussi', () {
      expect(agregation.decouper(30).last, (22, 30));
    });
  });

  group('Cumuls de la semaine', () {
    test('les entrées et sorties sont additionnées jour par jour', () {
      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 100,
        journees: {
          1: journee(jour: 1, achat: 10, effectif: 110),
          3: journee(jour: 3, ne: 5, morts: const [2, 0, 0], effectif: 113),
          6: journee(jour: 6, vente: 3, morts: const [0, 1, 0], effectif: 109),
        },
      );

      final s1 = semaines.first;
      expect(s1.cumulAchats, 10);
      expect(s1.cumulNaissances, 5);
      expect(s1.cumulMorts, 3);
      expect(s1.cumulVentes, 3);
    });

    test('l\'effectif de fin est celui du dernier jour saisi', () {
      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 100,
        journees: {
          1: journee(jour: 1, effectif: 110),
          6: journee(jour: 6, effectif: 109),
        },
      );

      expect(
        semaines.first.effectifFin,
        109,
        reason:
            'Le 7 n\'est pas saisi : la semaine se termine sur le dernier '
            'chiffre reellement connu.',
      );
    });

    test('la semaine 2 démarre à l\'effectif du soir du 7', () {
      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 100,
        journees: {
          7: journee(jour: 7, effectif: 95),
          9: journee(jour: 9, morts: const [5, 0, 0], effectif: 90),
        },
      );

      expect(semaines[1].effectifDebut, 95);
      expect(semaines[1].effectifFin, 90);
    });

    test('la première semaine démarre au report du mois précédent', () {
      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 82,
        journees: {2: journee(jour: 2, effectif: 82)},
      );

      expect(semaines.first.effectifDebut, 82);
    });
  });

  group('Taux de mortalité de la semaine', () {
    test('il rapporte les morts à l\'effectif de départ', () {
      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 200,
        journees: {
          3: journee(jour: 3, morts: const [4, 0, 0], effectif: 196),
        },
      );

      expect(semaines.first.tauxMortalite, 2.0);
    });

    test('sans effectif de départ, il n\'y a pas de taux — pas zéro', () {
      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 0,
        journees: const {},
      );

      expect(
        semaines.first.tauxMortalite,
        isNull,
        reason:
            'Afficher « 0,0 % » laisserait croire a une semaine sans perte, '
            'alors qu\'il n\'y a simplement aucun sujet.',
      );
    });
  });

  group('Semaines sans aucune saisie', () {
    test('la ligne existe mais ne porte aucun chiffre', () {
      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 100,
        journees: {1: journee(jour: 1, effectif: 100)},
      );

      expect(semaines, hasLength(4));
      expect(semaines.first.aDesJourneesSaisies, isTrue);
      for (final s in semaines.skip(1)) {
        expect(
          s.aDesJourneesSaisies,
          isFalse,
          reason:
              'La semaine ${s.numero} fait partie du mois : sa ligne reste '
              'visible, mais elle affiche des tirets, pas des zeros.',
        );
      }
    });

    test('une journée non enregistrée est ignorée', () {
      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 100,
        journees: {
          2: journee(jour: 2, achat: 50, effectif: 150, saisie: false),
        },
      );

      expect(semaines.first.cumulAchats, 0);
      expect(semaines.first.aDesJourneesSaisies, isFalse);
    });
  });

  group('Cohérence avec le tableau quotidien', () {
    test('la somme des 4 semaines égale le total du mois', () {
      final journees = {
        for (var j = 1; j <= 31; j++)
          j: journee(
            jour: j,
            achat: 1,
            ne: 2,
            vente: 1,
            morts: const [1, 0, 0],
            effectif: 100 + j,
          ),
      };

      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 100,
        journees: journees,
      );

      expect(semaines.fold<int>(0, (s, w) => s + w.cumulAchats), 31);
      expect(semaines.fold<int>(0, (s, w) => s + w.cumulNaissances), 62);
      expect(semaines.fold<int>(0, (s, w) => s + w.cumulMorts), 31);
      expect(semaines.fold<int>(0, (s, w) => s + w.cumulVentes), 31);
      expect(
        semaines.last.effectifFin,
        131,
        reason: 'La derniere semaine se termine sur le 31.',
      );
    });
  });
}
