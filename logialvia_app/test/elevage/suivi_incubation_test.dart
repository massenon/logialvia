import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/elevage/domain/entities/cycle_incubation.dart';
import 'package:logialvia_app/elevage/domain/services/suivi_incubation.dart';

/// Couveuse multi-âges — incubation en continu, lots et sous-lots, TER.
void main() {
  const suivi = SuiviIncubation();
  final j0 = DateTime(2026, 8, 1);

  CycleIncubation lot({
    int id = 1,
    String code = 'C-2026-001',
    EspeceCouvable espece = EspeceCouvable.goliath,
    DateTime? insertion,
    int quantite = 100,
    String statut = StatutCycle.enIncubation,
    int? blancs,
    int? gates,
    int? eclos,
    int? parentId,
    int? machineId = 1,
  }) => CycleIncubation(
    id: id,
    code: code,
    espece: espece,
    dateChargement: insertion ?? j0,
    oeufsCharges: quantite,
    statut: statut,
    oeufsBlancsJ7: blancs,
    oeufsGatesJ14: gates,
    poussinsEclos: eclos,
    lotParentId: parentId,
    machineId: machineId,
  );

  group('Durées d\'incubation', () {
    test('le Goliath incube 21 jours, la Pintade 28', () {
      expect(EspeceCouvable.goliath.dureeIncubationJours, 21);
      expect(
        EspeceCouvable.pintade.dureeIncubationJours,
        28,
        reason:
            'Le prototype ecrit `data-duree="27"`. La Gerante a corrige : 27 '
            'avancerait l\'eclosion d\'un jour, et l\'erreur se repete a '
            'chaque lot sur un couvoir en continu.',
      );
    });

    test('les mirages tombent aux mêmes jours pour les deux espèces', () {
      expect(EspeceCouvable.jourMirage1, 7);
      expect(EspeceCouvable.jourMirage2, 14);
    });
  });

  group('Calendrier propre à chaque lot', () {
    test('mirages et éclosion se calculent depuis la date d\'insertion', () {
      final goliath = lot(insertion: DateTime(2026, 8, 1));

      expect(goliath.dateMirage1, DateTime(2026, 8, 8));
      expect(goliath.dateMirage2, DateTime(2026, 8, 15));
      expect(goliath.dateEclosionPrevue, DateTime(2026, 8, 22));
    });

    test('une pintade éclot 7 jours après un goliath inséré le même jour', () {
      final pintade = lot(
        espece: EspeceCouvable.pintade,
        insertion: DateTime(2026, 8, 1),
      );

      expect(pintade.dateEclosionPrevue, DateTime(2026, 8, 29));
      expect(
        pintade.dateEclosionPrevue.difference(lot().dateEclosionPrevue).inDays,
        7,
      );
    });

    test('l\'âge du lot se compte depuis son insertion', () {
      final l = lot(insertion: DateTime(2026, 8, 1));

      expect(l.ageJours(DateTime(2026, 8, 1)), 0);
      expect(l.ageJours(DateTime(2026, 8, 15, 18)), 14);
    });

    test('l\'avancement est borné à 100 %', () {
      final l = lot(insertion: DateTime(2026, 8, 1));

      expect(l.avancement(DateTime(2026, 8, 1)), 0);
      expect(l.avancement(DateTime(2026, 8, 11)), closeTo(10 / 21, 0.001));
      expect(
        l.avancement(DateTime(2026, 9, 30)),
        1,
        reason: 'Un lot au-dela de son terme affiche 100 %, pas 110 %.',
      );
    });

    test('un sous-lot suit son propre calendrier, pas celui du parent', () {
      final parent = lot(id: 1, insertion: DateTime(2026, 8, 1));
      final sousLot = lot(id: 2, parentId: 1, insertion: DateTime(2026, 8, 22));

      expect(sousLot.dateEclosionPrevue, DateTime(2026, 9, 12));
      expect(
        sousLot.dateEclosionPrevue,
        isNot(parent.dateEclosionPrevue),
        reason:
            'C\'est tout l\'objet du suivi multi-ages : chaque lot a son '
            'horloge.',
      );
    });
  });

  group('Taux d\'Éclosion Réel — TER = E(21/28) / (E(0) − [B(7) + M(14)])', () {
    test('la formule s\'applique sur les œufs retenus, pas sur l\'initial', () {
      // 100 oeufs, 10 clairs, 5 gates -> 85 retenus ; 68 eclos.
      final l = lot(quantite: 100, blancs: 10, gates: 5, eclos: 68);

      expect(l.oeufsRetenusApresMirages, 85);
      expect(l.tauxEclosionReel, closeTo(80.0, 0.001));
      expect(
        l.tauxEclosionBrut,
        closeTo(68.0, 0.001),
        reason:
            'Le taux brut rapporte au depart : il confond une mauvaise '
            'incubation avec une mauvaise fecondation.',
      );
    });

    test('sans mirage saisi, le TER se rabat sur la quantité initiale', () {
      final l = lot(quantite: 100, eclos: 80);

      expect(l.oeufsRetenusApresMirages, 100);
      expect(l.tauxEclosionReel, closeTo(80.0, 0.001));
      expect(l.tauxEclosionReel, l.tauxEclosionBrut);
    });

    test('le TER n\'existe pas tant que l\'éclosion n\'est pas saisie', () {
      expect(lot(blancs: 10, gates: 5).tauxEclosionReel, isNull);
    });

    test('un lot entièrement vidé aux mirages n\'a pas de TER', () {
      final l = lot(quantite: 20, blancs: 15, gates: 5, eclos: 0);

      expect(l.oeufsRetenusApresMirages, 0);
      expect(
        l.tauxEclosionReel,
        isNull,
        reason:
            'Afficher 0 % laisserait croire a un echec d\'incubation la ou il '
            'n\'y avait plus rien a faire eclore.',
      );
    });

    test('un TER de 100 % est possible et n\'est pas plafonné à tort', () {
      final l = lot(quantite: 50, blancs: 10, gates: 0, eclos: 40);
      expect(l.tauxEclosionReel, 100);
    });

    test('le taux d\'œufs clairs mesure la fécondation, pas l\'incubation', () {
      final l = lot(quantite: 200, blancs: 40, gates: 10, eclos: 135);

      expect(l.tauxOeufsClairs, closeTo(20.0, 0.001));
      expect(l.tauxEclosionReel, closeTo(90.0, 0.001));
      expect(
        l.tauxEclosionBrut,
        closeTo(67.5, 0.001),
        reason:
            'Un ecart brut/reel de 22 points designe les reproducteurs, pas '
            'la couveuse.',
      );
    });
  });

  group('TER moyen à une date t', () {
    test('il est pondéré par les œufs retenus, pas moyenné sur les taux', () {
      final lots = [
        // 300 retenus, 270 eclos -> 90 %
        lot(id: 1, quantite: 300, blancs: 0, gates: 0, eclos: 270),
        // 10 retenus, 1 eclos -> 10 %
        lot(id: 2, quantite: 10, blancs: 0, gates: 0, eclos: 1),
      ];

      final ter = suivi.terMoyenA(lots, DateTime(2026, 9, 1));

      expect(ter, closeTo(271 / 310 * 100, 0.001));
      expect(
        ter,
        greaterThan(80),
        reason:
            'La moyenne arithmetique des taux donnerait 50 % : un lot de 10 '
            'oeufs effondrerait un couvoir par ailleurs excellent.',
      );
    });

    test('les lots dont l\'éclosion est postérieure à t sont exclus', () {
      final lots = [
        lot(id: 1, insertion: DateTime(2026, 8, 1), eclos: 80), // eclos 22/08
        lot(id: 2, insertion: DateTime(2026, 8, 20), eclos: 90), // eclos 10/09
      ];

      // Au 25 aout, seul le premier lot est arrive a terme.
      expect(suivi.terMoyenA(lots, DateTime(2026, 8, 25)), closeTo(80, 0.001));
      expect(suivi.terMoyenA(lots, DateTime(2026, 9, 30)), closeTo(85, 0.001));
    });

    test('sans aucune éclosion, il n\'y a pas de moyenne', () {
      expect(suivi.terMoyenA([lot()], DateTime(2026, 9, 1)), isNull);
      expect(suivi.terMoyenA(const [], DateTime(2026, 9, 1)), isNull);
    });
  });

  group('Alertes aux dates critiques', () {
    test('le mirage 1 se déclenche à J+7 et pas avant', () {
      final lots = [lot(insertion: DateTime(2026, 8, 1))];

      expect(suivi.alertes(lots, DateTime(2026, 8, 7)), isEmpty);

      final a = suivi.alertes(lots, DateTime(2026, 8, 8));
      expect(a.map((x) => x.type), contains(TypeEcheance.mirage1));
      expect(a.first.estAujourdhui, isTrue);
    });

    test('une échéance reste due tant que la saisie manque', () {
      final lots = [lot(insertion: DateTime(2026, 8, 1))];

      final a = suivi.alertes(lots, DateTime(2026, 8, 20));
      final mirage1 = a.firstWhere((x) => x.type == TypeEcheance.mirage1);

      expect(
        mirage1.joursDecart,
        12,
        reason:
            'Un couvoir en continu se rate par les mirages oublies : l\'alerte '
            'ne doit pas disparaitre d\'elle-meme.',
      );
      expect(mirage1.estEnRetard, isTrue);
    });

    test('une échéance saisie ne se rappelle plus', () {
      final lots = [lot(insertion: DateTime(2026, 8, 1), blancs: 12)];

      final types = suivi
          .alertes(lots, DateTime(2026, 8, 20))
          .map((a) => a.type);
      expect(types, isNot(contains(TypeEcheance.mirage1)));
      expect(types, contains(TypeEcheance.mirage2));
    });

    test('les plus en retard remontent en premier', () {
      final lots = [
        lot(id: 1, insertion: DateTime(2026, 8, 10)),
        lot(id: 2, insertion: DateTime(2026, 8, 1)),
      ];

      final a = suivi.alertes(lots, DateTime(2026, 8, 20));
      expect(a.first.joursDecart, greaterThanOrEqualTo(a.last.joursDecart));
    });

    test('un lot éclos ne génère plus aucune alerte', () {
      final lots = [
        lot(
          insertion: DateTime(2026, 8, 1),
          statut: StatutCycle.eclosionEffectuee,
          eclos: 80,
        ),
      ];

      expect(suivi.alertes(lots, DateTime(2026, 9, 30)), isEmpty);
    });

    test('les échéances à venir se préparent, sans être des retards', () {
      final lots = [lot(insertion: DateTime(2026, 8, 1))];

      final aVenir = suivi.echeancesAVenir(
        lots,
        DateTime(2026, 8, 6),
        jours: 3,
      );
      expect(aVenir.map((a) => a.type), [TypeEcheance.mirage1]);
      expect(aVenir.single.joursDecart, -2);
      expect(aVenir.single.estEnRetard, isFalse);
    });

    test('la pintade est alertée 7 jours après le goliath', () {
      final lots = [
        lot(id: 1, insertion: DateTime(2026, 8, 1)),
        lot(
          id: 2,
          espece: EspeceCouvable.pintade,
          insertion: DateTime(2026, 8, 1),
        ),
      ];

      final au22 = suivi.alertes(lots, DateTime(2026, 8, 22));
      final eclosions = au22.where((a) => a.type == TypeEcheance.eclosion);
      expect(
        eclosions.map((a) => a.lot.id),
        [1],
        reason:
            'La pintade n\'eclot que le 29 : l\'alerter le 22 ferait '
            'ouvrir la machine pour rien.',
      );
    });
  });

  group('Lots et sous-lots — traçabilité des remplacements', () {
    final lots = [
      lot(
        id: 1,
        code: 'C-2026-001',
        insertion: DateTime(2026, 8, 1),
        eclos: 80,
      ),
      lot(
        id: 2,
        code: 'C-2026-002',
        parentId: 1,
        insertion: DateTime(2026, 8, 22),
        eclos: 90,
      ),
      lot(
        id: 3,
        code: 'C-2026-003',
        parentId: 2,
        insertion: DateTime(2026, 9, 12),
      ),
      lot(id: 9, code: 'C-2026-009', insertion: DateTime(2026, 8, 5)),
    ];

    test('la lignée suit la chaîne des remplacements, dans l\'ordre', () {
      final lignee = suivi.lignee(lots, 1);

      expect(lignee.map((l) => l.code), [
        'C-2026-001',
        'C-2026-002',
        'C-2026-003',
      ]);
      expect(
        lignee.map((l) => l.id),
        isNot(contains(9)),
        reason: 'Un lot d\'une autre lignee ne doit pas s\'y glisser.',
      );
    });

    test('on remonte au lot d\'origine depuis n\'importe quel maillon', () {
      final racine = suivi.racineDe(lots, lots[2]);
      expect(racine?.code, 'C-2026-001');
    });

    test('un lot racine est sa propre racine', () {
      expect(suivi.racineDe(lots, lots[3])?.code, 'C-2026-009');
    });

    test('le TER de la lignée mesure la place dans la machine', () {
      // 100 + 100 retenus, 80 + 90 eclos.
      final ter = suivi.terDeLaLignee(lots, 1, DateTime(2026, 10, 1));
      expect(ter, closeTo(85, 0.001));
    });

    test('un sous-lot expose sa date et sa quantité de remplacement', () {
      final sousLot = lots[1];

      expect(sousLot.estSousLot, isTrue);
      expect(sousLot.dateRemplacement, DateTime(2026, 8, 22));
      expect(sousLot.quantiteRemplacee, 100);
    });

    test('un lot racine n\'a ni date ni quantité de remplacement', () {
      expect(lots[3].estSousLot, isFalse);
      expect(lots[3].dateRemplacement, isNull);
      expect(lots[3].quantiteRemplacee, isNull);
    });

    test('une référence circulaire ne fait pas boucler la remontée', () {
      // Cas impossible par construction, mais une base corrompue le produirait.
      final circulaires = [lot(id: 1, parentId: 2), lot(id: 2, parentId: 1)];
      expect(suivi.racineDe(circulaires, circulaires.first), isNotNull);
    });
  });

  group('Occupation des machines', () {
    test('seuls les lots en incubation occupent la machine', () {
      final lots = [
        lot(id: 1, machineId: 1, quantite: 100, blancs: 10),
        lot(
          id: 2,
          machineId: 1,
          quantite: 50,
          statut: StatutCycle.eclosionEffectuee,
          eclos: 40,
        ),
        lot(id: 3, machineId: 2, quantite: 200),
      ];

      expect(suivi.occupation(lots, 1), 90);
      expect(suivi.occupation(lots, 2), 200);
      expect(suivi.occupation(lots, 3), 0);
    });
  });

  group('Contrat JSON', () {
    test('le document porte lots, machines, alertes et TER', () {
      final lots = [lot(insertion: DateTime(2026, 8, 1), blancs: 10)];
      const machines = [
        MachineIncubateur(id: 1, code: 'INC-01', libelle: 'Couveuse 1'),
      ];

      final json = suivi.versJson(lots, machines, DateTime(2026, 8, 20));

      expect(
        json.keys,
        containsAll(['genereLe', 'terMoyen', 'lots', 'machines', 'alertes']),
      );
      expect((json['lots']! as List), hasLength(1));
      expect((json['machines']! as List), hasLength(1));
      expect((json['alertes']! as List), isNotEmpty);
    });

    test('un lot expose toutes les variables de la formule', () {
      final json = lot(
        quantite: 100,
        blancs: 10,
        gates: 5,
        eclos: 68,
      ).versJson(DateTime(2026, 8, 25));

      expect(json['quantiteInitiale'], 100);
      expect(json['oeufsBlancsJ7'], 10);
      expect(json['oeufsGatesJ14'], 5);
      expect(json['oeufsEclos'], 68);
      expect(json['oeufsRetenusApresMirages'], 85);
      expect(json['tauxEclosionReel'], closeTo(80, 0.001));
      expect(json['dateMirage1'], startsWith('2026-08-08'));
      expect(json['dateEclosionPrevue'], startsWith('2026-08-22'));
    });

    test('les dates sont en ISO 8601, exploitables par un client', () {
      final json = lot().versJson(DateTime(2026, 8, 25));
      expect(
        DateTime.parse(json['dateInsertion']! as String),
        DateTime(2026, 8, 1),
      );
    });
  });
}
