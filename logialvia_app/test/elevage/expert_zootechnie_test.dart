import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/database/app_database.dart';
import 'package:logialvia_app/core/resultat/resultat.dart';
import 'package:logialvia_app/elevage/data/repositories/fiche_elevage_repository_drift.dart';
import 'package:logialvia_app/elevage/data/repositories/soins_repository_drift.dart';
import 'package:logialvia_app/elevage/data/sync/identifiants_elevage.dart';
import 'package:logialvia_app/elevage/domain/entities/cycle_incubation.dart';
import 'package:logialvia_app/elevage/domain/entities/configuration_espece.dart';
import 'package:logialvia_app/elevage/domain/entities/journee_elevage.dart';
import 'package:logialvia_app/elevage/domain/services/agregation_hebdomadaire.dart';
import 'package:logialvia_app/elevage/domain/services/calcul_fiche_journaliere.dart';
import 'package:logialvia_app/elevage/domain/services/controle_vraisemblance.dart';
import 'package:logialvia_app/elevage/domain/services/reperes_zootechniques.dart';
import 'package:logialvia_app/elevage/domain/usecases/enregistrer_journee_usecase.dart';

/// Lot « expert zootechnicien » (`47e_`) : repères chiffrés, contrôle de vraisemblance,
/// taux de mortalité et rations. Chaque valeur attendue est calculée à la main dans le
/// commentaire du cas.
void main() {
  group('Mortalité : seuils DV-13 (comparaisons strictes)', () {
    test('du jour : 1 % et 2 % ne déclenchent rien, au-delà oui', () {
      expect(
        ReperesZootechniques.niveauMortaliteJour(1.0),
        NiveauAlerte.normal,
      );
      expect(
        ReperesZootechniques.niveauMortaliteJour(1.01),
        NiveauAlerte.avertissement,
      );
      expect(
        ReperesZootechniques.niveauMortaliteJour(2.0),
        NiveauAlerte.avertissement,
      );
      expect(
        ReperesZootechniques.niveauMortaliteJour(2.01),
        NiveauAlerte.critique,
      );
    });

    test('cumulée : 10 % et 20 % ne déclenchent rien, au-delà oui', () {
      expect(
        ReperesZootechniques.niveauMortaliteCumul(10),
        NiveauAlerte.normal,
      );
      expect(
        ReperesZootechniques.niveauMortaliteCumul(10.5),
        NiveauAlerte.avertissement,
      );
      expect(
        ReperesZootechniques.niveauMortaliteCumul(20),
        NiveauAlerte.avertissement,
      );
      expect(
        ReperesZootechniques.niveauMortaliteCumul(20.1),
        NiveauAlerte.critique,
      );
    });

    test(
      'lot de 200 : avertissement à 3 morts (1,5 %), critique à 5 (2,5 %)',
      () {
        expect(
          ReperesZootechniques.niveauMortaliteJour(2 / 200 * 100),
          NiveauAlerte.normal,
          reason: '2 morts = 1 % pile : strict, donc rien.',
        );
        expect(
          ReperesZootechniques.niveauMortaliteJour(3 / 200 * 100),
          NiveauAlerte.avertissement,
        );
        expect(
          ReperesZootechniques.niveauMortaliteJour(5 / 200 * 100),
          NiveauAlerte.critique,
        );
      },
    );

    test('lot de 200 cumulé : avertissement à 21 morts, critique à 41', () {
      double t(int m) => m / 200 * 100;
      expect(
        ReperesZootechniques.niveauMortaliteCumul(t(20)),
        NiveauAlerte.normal,
      );
      expect(
        ReperesZootechniques.niveauMortaliteCumul(t(21)),
        NiveauAlerte.avertissement,
      );
      expect(
        ReperesZootechniques.niveauMortaliteCumul(t(40)),
        NiveauAlerte.avertissement,
      );
      expect(
        ReperesZootechniques.niveauMortaliteCumul(t(41)),
        NiveauAlerte.critique,
      );
    });

    test(
      'taux cumulé : base = effectif de départ + entrées (12 morts / 240)',
      () {
        // 100 au départ + 140 entrées = 240 exposés ; 12 morts = 5,0 %.
        expect(
          ReperesZootechniques.tauxMortaliteCumule(
            morts: 12,
            effectifDepart: 100,
            entrees: 140,
          ),
          closeTo(5.0, 1e-9),
        );
        // Sans entrées : 3 morts / 100 = 3 % (cas historique de RM-ELV-08).
        expect(
          ReperesZootechniques.tauxMortaliteCumule(
            morts: 3,
            effectifDepart: 100,
            entrees: 0,
          ),
          closeTo(3.0, 1e-9),
        );
        // Aucun effectif exposé : pas de taux (jamais 0 %).
        expect(
          ReperesZootechniques.tauxMortaliteCumule(
            morts: 2,
            effectifDepart: 0,
            entrees: 0,
          ),
          isNull,
        );
      },
    );
  });

  group('GMQ et indice de consommation', () {
    test('GMQ = (poids final − poids initial) ÷ jours', () {
      // 500 g -> 1 850 g en 27 jours = 50 g/j.
      expect(
        ReperesZootechniques.gmqGrammesParJour(
          poidsMoyenInitialG: 500,
          poidsMoyenFinalG: 1850,
          jours: 27,
        ),
        closeTo(50, 1e-9),
      );
    });

    test('GMQ négatif possible, nul si aucun jour écoulé', () {
      expect(
        ReperesZootechniques.gmqGrammesParJour(
          poidsMoyenInitialG: 1000,
          poidsMoyenFinalG: 900,
          jours: 10,
        ),
        closeTo(-10, 1e-9),
      );
      expect(
        ReperesZootechniques.gmqGrammesParJour(
          poidsMoyenInitialG: 1,
          poidsMoyenFinalG: 2,
          jours: 0,
        ),
        isNull,
      );
    });

    test('IC = aliment ÷ gain de poids ; pas de gain, pas d\'IC', () {
      // 3 000 kg d'aliment pour 1 500 kg de gain : IC 2,0.
      expect(
        ReperesZootechniques.indiceConsommation(
          alimentConsomme: 3000,
          gainPoidsTotal: 1500,
        ),
        closeTo(2.0, 1e-9),
      );
      expect(
        ReperesZootechniques.indiceConsommation(
          alimentConsomme: 3000,
          gainPoidsTotal: 0,
        ),
        isNull,
      );
      expect(
        ReperesZootechniques.indiceConsommation(
          alimentConsomme: 3000,
          gainPoidsTotal: -5,
        ),
        isNull,
      );
    });
  });

  group('Durées d\'incubation : les constantes du Dart sont exactes', () {
    test('Goliath (poule) 21 j, pintade 28 j', () {
      expect(EspeceCouvable.goliath.dureeIncubationJours, 21);
      expect(EspeceCouvable.pintade.dureeIncubationJours, 28);
    });

    test('table de référence : poule 21, pintade 28, canard 28, caille 17', () {
      const d = ReperesZootechniques.dureesIncubationJours;
      expect(d['poule'], 21);
      expect(d['pintade'], 28);
      expect(d['canard'], 28);
      expect(d['canard de Barbarie'], 35);
      expect(d['caille'], 17);
      expect(d['dinde'], 28);
    });
  });

  group('Contrôle de vraisemblance d\'une journée', () {
    const poulets = ConfigurationsEspeces.poulets;
    const pondeuses = ConfigurationsEspeces.pondeuses;

    ResultatControle controle(
      ConfigurationEspece config, {
      required List<int> veille,
      required MouvementsJour mouvements,
      int? poids,
      int? pondus,
      int? casses,
      int? sorties,
      int stock = 0,
    }) {
      final calcul = CalculFicheJournaliere(config);
      final total = veille.fold<int>(0, (s, v) => s + v);
      final jour = calcul.calculerJour(
        effectifsVeille: veille,
        effectifTotalVeille: total,
        mouvements: mouvements,
      );
      return ControleVraisemblance(config).controlerJournee(
        effectifsVeille: veille,
        mouvements: mouvements,
        effectifsDuJour: jour,
        effectifTotalVeille: total,
        poidsTotalGrammes: poids,
        oeufsPondus: pondus,
        oeufsCasses: casses,
        sortiesPlateaux: sorties,
        stockOeufsDisponible: stock,
      );
    }

    test('une saisie normale ne dit rien', () {
      final r = controle(
        poulets,
        veille: [100, 50, 30],
        mouvements: const MouvementsJour(mortsParCategorie: [1, 0, 0]),
      );
      expect(r.erreurs, isEmpty);
      expect(r.avertissements, isEmpty);
    });

    test('mortalité supérieure à l\'effectif de la catégorie : refusée', () {
      final r = controle(
        poulets,
        veille: [10, 50, 30],
        mouvements: const MouvementsJour(mortsParCategorie: [12, 0, 0]),
      );
      expect(r.estValide, isFalse);
      expect(
        r.erreurs.single,
        'Morts et dons de « Poussin » (12) : supérieurs à l\'effectif '
        'disponible (10). Saisissez d\'abord les entrées (achats, naissances) ou '
        'corrigez la mortalité.',
      );
    });

    test('les entrées du jour comptent dans l\'effectif disponible', () {
      // 0 en veille + 100 achetés : 12 morts le jour d'arrivée sont possibles.
      final r = controle(
        poulets,
        veille: [0, 0, 0],
        mouvements: const MouvementsJour(
          achat: 100,
          mortsParCategorie: [12, 0, 0],
        ),
      );
      expect(r.erreurs, isEmpty);
    });

    test('morts + dons cumulés comparés à l\'effectif (6 + 5 > 10)', () {
      final r = controle(
        poulets,
        veille: [10, 0, 0],
        mouvements: const MouvementsJour(
          mortsParCategorie: [6, 0, 0],
          donsParCategorie: [5, 0, 0],
        ),
      );
      expect(r.erreurs, hasLength(1));
      expect(r.erreurs.single, contains('(11)'));
      expect(r.erreurs.single, contains('(10)'));
    });

    test('œufs pondus supérieurs aux pondeuses : refusé', () {
      final r = controle(
        pondeuses,
        veille: [0, 0, 0, 100],
        mouvements: const MouvementsJour(),
        pondus: 101,
        casses: 0,
        sorties: 0,
      );
      expect(r.erreurs.single, startsWith('Les œufs pondus (101) dépassent'));
      expect(r.erreurs.single, contains('(100)'));
    });

    test('taux de ponte de 100 % : accepté mais exceptionnel (> 96 %)', () {
      final r = controle(
        pondeuses,
        veille: [0, 0, 0, 100],
        mouvements: const MouvementsJour(),
        pondus: 100,
        casses: 0,
        sorties: 0,
      );
      expect(r.erreurs, isEmpty);
      expect(
        r.avertissements.single,
        'Taux de ponte de 100 % : au-delà de 96 % c\'est exceptionnel. '
        'Vérifiez le décompte des œufs.',
      );
    });

    test('œufs cassés > 10 % des pondus : à vérifier', () {
      final r = controle(
        pondeuses,
        veille: [0, 0, 0, 100],
        mouvements: const MouvementsJour(),
        pondus: 80,
        casses: 12,
        sorties: 0,
      );
      expect(r.avertissements.single, contains('15 % des œufs pondus'));
    });

    test('sorties de plateaux au-delà du stock : stock ramené à 0', () {
      // 3 plateaux = 90 œufs ; stock disponible 60.
      final r = controle(
        pondeuses,
        veille: [0, 0, 0, 100],
        mouvements: const MouvementsJour(),
        pondus: 60,
        casses: 0,
        sorties: 3,
        stock: 60,
      );
      expect(
        r.avertissements.single,
        'Les sorties (90 œufs) dépassent le stock disponible (60) : le stock '
        'final sera ramené à 0.',
      );
    });

    test('pesée aberrante : 12 500 g par poulet', () {
      // 100 sujets, pesée de 1 250 000 g = 12 500 g de moyenne (repère 30 à 6 000 g).
      final r = controle(
        poulets,
        veille: [0, 0, 100],
        mouvements: const MouvementsJour(),
        poids: 1250000,
      );
      expect(r.erreurs, isEmpty);
      expect(
        r.avertissements.single,
        'Poids moyen de 12500 g par sujet : hors des repères Poulets (30 à '
        '6000 g). Vérifiez l\'unité (la pesée se saisit en grammes) et '
        'l\'effectif.',
      );
    });

    test('pesée normale (1 800 g de moyenne) : rien', () {
      final r = controle(
        poulets,
        veille: [0, 0, 100],
        mouvements: const MouvementsJour(),
        poids: 180000,
      );
      expect(r.avertissements, isEmpty);
    });

    test('pesée sans sujet vivant', () {
      final r = controle(
        poulets,
        veille: [0, 0, 0],
        mouvements: const MouvementsJour(),
        poids: 500,
      );
      expect(
        r.avertissements.single,
        "Une pesée est saisie alors qu'aucun sujet vivant n'est comptabilisé.",
      );
    });

    test('mortalité du jour : 1,5 % avertit, 2,5 % est critique', () {
      final avert = controle(
        poulets,
        veille: [200, 0, 0],
        mouvements: const MouvementsJour(mortsParCategorie: [3, 0, 0]),
      );
      expect(avert.avertissements.single, contains('1,5 %'));
      expect(avert.avertissements.single, contains('avertissement'));

      final critique = controle(
        poulets,
        veille: [200, 0, 0],
        mouvements: const MouvementsJour(mortsParCategorie: [5, 0, 0]),
      );
      expect(critique.avertissements.single, contains('2,5 %'));
      expect(critique.avertissements.single, contains('critique'));
    });

    test('ventes au-delà de la catégorie commercialisée : avertissement', () {
      final r = controle(
        poulets,
        veille: [0, 10, 0],
        mouvements: const MouvementsJour(vente: 15),
      );
      expect(r.erreurs, isEmpty);
      expect(
        r.avertissements.single,
        'Les ventes du jour (15) dépassent l\'effectif de « Poulette » (10) : '
        'la fiche sera ramenée à 0. Vérifiez les entrées déjà saisies.',
      );
    });

    test('repères de poids : une fourchette par filière, jamais inversée', () {
      for (final id in ConfigurationsEspeces.parIdentifiant.keys) {
        final r = ReperesZootechniques.poidsMoyenPlausibleG(id);
        expect(r.max, greaterThan(r.min), reason: id);
      }
      expect(ReperesZootechniques.poidsMoyenPlausibleG('bovins').min, 15000);
      expect(ReperesZootechniques.poidsMoyenPlausibleG('escargots').max, 250);
    });
  });

  group('Enregistrement : l\'impossible est refusé, rien n\'est écrit', () {
    late AppDatabase db;
    late FicheElevageRepositoryDrift repository;
    late EnregistrerJourneeUseCase usecase;

    setUp(() {
      db = AppDatabase.enMemoire();
      repository = FicheElevageRepositoryDrift(
        db,
        ConfigurationsEspeces.poulets,
      );
      usecase = EnregistrerJourneeUseCase(
        repository,
        ConfigurationsEspeces.poulets,
      );
    });
    tearDown(() async => db.close());

    test('plus de morts que de sujets : Echec et aucune fiche', () async {
      final r = await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(
          achat: 10,
          mortsParCategorie: [11, 0, 0],
        ),
      );
      expect(r, isA<Echec<JourneeElevage>>());
      expect(
        await repository.chargerJour(
          espece: 'poulets',
          date: DateTime(2026, 8, 1),
        ),
        isNull,
      );
    });

    test('exactement tous les sujets morts : accepté (11 = 11)', () async {
      final r = await usecase.executer(
        date: DateTime(2026, 8, 1),
        mouvements: const MouvementsJour(
          achat: 11,
          mortsParCategorie: [11, 0, 0],
        ),
      );
      expect(r, isA<Succes<JourneeElevage>>());
    });
  });

  group('Taux hebdomadaire : l\'effectif exposé inclut les entrées', () {
    const agregation = AgregationHebdomadaire();

    JourneeElevage jour(
      int j, {
      int achat = 0,
      List<int> morts = const [0, 0, 0],
      required int effectif,
      bool saisie = true,
    }) => JourneeElevage(
      espece: 'goliaths',
      date: DateTime(2026, 8, j),
      achat: achat,
      ne: 0,
      vente: 0,
      mortsParCategorie: morts,
      donsParCategorie: const [0, 0, 0],
      effectif: effectif,
      effectifsParCategorie: const [0, 0, 0],
      isRecorded: saisie,
    );

    test('bande arrivée en cours de semaine : 200 achetés, 5 morts = 2,5 %', () {
      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 0,
        journees: {
          2: jour(2, achat: 200, morts: const [5, 0, 0], effectif: 195),
        },
      );
      // Avant : effectif de départ 0 -> « — ». Maintenant : 5 / (0 + 200) = 2,5 %.
      expect(semaines.first.tauxMortalite, closeTo(2.5, 1e-9));
    });

    test('sans entrée, le taux est inchangé (début 100, 3 morts = 3,0 %)', () {
      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 100,
        journees: {
          3: jour(3, morts: const [3, 0, 0], effectif: 97),
        },
      );
      expect(semaines.first.tauxMortalite, closeTo(3.0, 1e-9));
    });

    test('une veille non saisie garde le dernier effectif connu', () {
      // Jour 7 non saisi : la semaine 2 part de l'effectif du jour 6 (80), pas de
      // l'effectif de début de mois (100).
      final semaines = agregation.calculer(
        nombreJoursDuMois: 31,
        effectifInitial: 100,
        journees: {
          6: jour(6, effectif: 80),
          7: jour(7, effectif: 0, saisie: false),
          9: jour(9, morts: const [4, 0, 0], effectif: 76),
        },
      );
      expect(semaines[1].effectifDebut, 80);
      expect(semaines[1].tauxMortalite, closeTo(5.0, 1e-9));
    });
  });

  group('Rations : le barème modifié doit avoir un effet', () {
    test('lapins : « Sevré / Lapereaux » du barème pilote « Lapereau »', () {
      const calcul = CalculFicheJournaliere(
        ConfigurationsEspeces.lapins,
        rationsConfigurees: {'Sevré / Lapereaux': 45, 'Chair / Jeune': 90},
      );
      expect(calcul.rationCategorie(0), 45);
      expect(calcul.rationCategorie(1), 90);
      // Valeur de reference du code : 120 g/j (Q-ELV-2), celle du bareme seme.
      expect(calcul.rationCategorie(2), 120);
    });

    test('pintades : le stade semé « Alevins » pilote « Poussins »', () {
      const calcul = CalculFicheJournaliere(
        ConfigurationsEspeces.pintades,
        rationsConfigurees: {'Alevins': 35},
      );
      expect(calcul.rationCategorie(0), 35);
    });

    test('le libellé exact prime sur l\'équivalent', () {
      const calcul = CalculFicheJournaliere(
        ConfigurationsEspeces.pintades,
        rationsConfigurees: {'Poussins': 40, 'Alevins': 35},
      );
      expect(calcul.rationCategorie(0), 40);
    });

    test('poissons-chats : repli par tête cohérent avec la biomasse', () {
      // Alevin de ~2 g à 15 % = 0,3 g ; juvénile de 50 g à 4 % = 2 g ; adulte de 500 g
      // à 1,5 % = 7,5 g. Les rations par tête restent dans le même ordre de grandeur.
      final c = ConfigurationsEspeces.poissonsChats.categories;
      expect(c.map((k) => k.rationGrammesParJour), [1, 3, 8]);
      // 1 000 juvéniles à 3 g = 3 kg/j, contre 60 kg/j avec l'ancienne valeur (60 g).
      const calcul = CalculFicheJournaliere(
        ConfigurationsEspeces.poissonsChats,
      );
      expect(calcul.provendeTotaleGrammes([0, 1000, 0]), 3000);
    });
  });

  group('Couveuse : mirage et éclosion à une date possible', () {
    CycleIncubation lot(EspeceCouvable espece) => CycleIncubation(
      id: 'lot',
      code: 'C-1',
      espece: espece,
      dateChargement: DateTime(2026, 8, 1),
      oeufsCharges: 100,
      statut: 'En Incubation',
    );

    test('mirage J+7 : refusé à J+4, accepté à J+5', () {
      final l = lot(EspeceCouvable.goliath);
      expect(
        ControleVraisemblanceCouveuse.erreurMirage(
          lot: l,
          jour: 7,
          date: DateTime(2026, 8, 5),
        ),
        "Le mirage à J+7 ne peut pas se faire avant J+5 : ce lot n'a que 4 jours "
        "d'incubation.",
      );
      expect(
        ControleVraisemblanceCouveuse.erreurMirage(
          lot: l,
          jour: 7,
          date: DateTime(2026, 8, 6),
        ),
        isNull,
      );
    });

    test('mirage J+14 : refusé à J+11, accepté à J+12', () {
      final l = lot(EspeceCouvable.pintade);
      expect(
        ControleVraisemblanceCouveuse.erreurMirage(
          lot: l,
          jour: 14,
          date: DateTime(2026, 8, 12),
        ),
        isNotNull,
      );
      expect(
        ControleVraisemblanceCouveuse.erreurMirage(
          lot: l,
          jour: 14,
          date: DateTime(2026, 8, 13),
        ),
        isNull,
      );
    });

    test('éclosion Goliath (21 j) : impossible à J+16, possible à J+17', () {
      final l = lot(EspeceCouvable.goliath);
      expect(
        ControleVraisemblanceCouveuse.erreurEclosion(
          lot: l,
          date: DateTime(2026, 8, 17),
        ),
        "Éclosion impossible : ce lot n'a que 16 jours d'incubation, Goliath "
        'incube 21 jours (éclosion possible à partir de J+17).',
      );
      expect(
        ControleVraisemblanceCouveuse.erreurEclosion(
          lot: l,
          date: DateTime(2026, 8, 18),
        ),
        isNull,
      );
    });

    test('éclosion pintade (28 j) : impossible à J+23, possible à J+24', () {
      final l = lot(EspeceCouvable.pintade);
      expect(
        ControleVraisemblanceCouveuse.erreurEclosion(
          lot: l,
          date: DateTime(2026, 8, 24),
        ),
        contains('Pintade incube 28 jours'),
      );
      expect(
        ControleVraisemblanceCouveuse.erreurEclosion(
          lot: l,
          date: DateTime(2026, 8, 25),
        ),
        isNull,
      );
    });
  });

  group(
    'Soin du calendrier : identifiant déterministe (pas de doublon entre postes)',
    () {
      test(
        'même (bande, échéance) => même UUID ; un soin libre reste aléatoire',
        () async {
          final db1 = AppDatabase.enMemoire();
          final db2 = AppDatabase.enMemoire();
          addTearDown(db1.close);
          addTearDown(db2.close);
          const bande = '11111111-1111-4111-8111-111111111111';
          const echeance = '22222222-2222-4222-8222-222222222222';
          Future<String> poser(AppDatabase db) async =>
              (await SoinsRepositoryDrift(db).enregistrerSoin(
                espece: 'goliaths',
                date: DateTime(2026, 11, 5),
                typeSoin: 'Vaccination',
                statut: 'Planifié',
                bandeId: bande,
                echeanceProphylaxieId: echeance,
              )).id;
          final a = await poser(db1);
          final b = await poser(db2);
          expect(a, b);
          expect(a, identifiantSoinProphylaxie(bande, echeance));
          final libre1 = await SoinsRepositoryDrift(db1).enregistrerSoin(
            espece: 'goliaths',
            date: DateTime(2026, 11, 5),
            typeSoin: 'Vitamines',
            statut: 'Planifié',
          );
          final libre2 = await SoinsRepositoryDrift(db1).enregistrerSoin(
            espece: 'goliaths',
            date: DateTime(2026, 11, 5),
            typeSoin: 'Vitamines',
            statut: 'Planifié',
          );
          expect(libre1.id, isNot(libre2.id));
        },
      );
    },
  );

  group('GMQ d\'une filière sur ses pesées', () {
    test(
      '(1 850 g - 500 g) / 27 j = 50 g/j, poids moyens = pesée / effectif',
      () {
        final r = ReperesZootechniques.gmqSurPesees([
          (date: DateTime(2026, 10, 12), poidsTotalG: 50000, effectif: 100),
          (date: DateTime(2026, 11, 8), poidsTotalG: 180000, effectif: 97),
        ]);
        expect(r, isNotNull);
        expect(r!.jours, 27);
        expect(r.poidsMoyenInitialG, 500);
        expect(r.poidsMoyenFinalG, closeTo(1855.67, 0.01));
        expect(r.gmqGrammesParJour, closeTo(50.2, 0.1));
      },
    );

    test('moins de deux pesées, ou le même jour : pas de GMQ', () {
      expect(
        ReperesZootechniques.gmqSurPesees([
          (date: DateTime(2026, 11, 8), poidsTotalG: 50000, effectif: 100),
        ]),
        isNull,
      );
      expect(
        ReperesZootechniques.gmqSurPesees([
          (date: DateTime(2026, 11, 8), poidsTotalG: 50000, effectif: 100),
          (date: DateTime(2026, 11, 8), poidsTotalG: 60000, effectif: 100),
        ]),
        isNull,
      );
    });

    test(
      'une pesée sans effectif est ignorée (jamais de division par zéro)',
      () {
        expect(
          ReperesZootechniques.gmqSurPesees([
            (date: DateTime(2026, 10, 1), poidsTotalG: 50000, effectif: 0),
            (date: DateTime(2026, 11, 8), poidsTotalG: 60000, effectif: 100),
          ]),
          isNull,
        );
      },
    );
  });
}
