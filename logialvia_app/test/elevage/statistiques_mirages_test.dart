import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/elevage/domain/entities/cycle_incubation.dart';
import 'package:logialvia_app/elevage/domain/services/statistiques_mirages.dart';

/// Les mirages séparent ce que le taux d'éclosion confond.
///
/// ## Ce que ces tests protègent
///
/// Un mauvais TER a trois causes possibles, et les additionner revient à jeter
/// l'information au moment où elle sert :
///
/// - **clairs au J+7** → œufs jamais fécondés, le troupeau reproducteur est en
///   cause, pas la machine ;
/// - **gâtés au J+14** → embryons démarrés puis arrêtés, c'est la conduite de
///   l'incubation ;
/// - **peu d'éclos sur les retenus** → la fin d'incubation.
///
/// Les dénominateurs ne sont donc pas interchangeables, et c'est là que se
/// jouent les erreurs silencieuses.
void main() {
  CycleIncubation lot({
    required String code,
    int charges = 200,
    int? clairs,
    int? gates,
    int? eclos,
    DateTime? chargement,
    EspeceCouvable espece = EspeceCouvable.goliath,
  }) => CycleIncubation(
    id: 'lot-${code.hashCode}',
    code: code,
    espece: espece,
    dateChargement: chargement ?? DateTime(2026, 8, 1),
    oeufsCharges: charges,
    poussinsEclos: eclos,
    statut: eclos == null
        ? StatutCycle.enIncubation
        : StatutCycle.eclosionEffectuee,
    oeufsBlancsJ7: clairs,
    oeufsGatesJ14: gates,
  );

  group('Un lot pris isolément', () {
    test('l\'infertilité rapporte les clairs aux œufs chargés', () {
      final s = StatistiquesLot(lot: lot(code: 'C1', charges: 200, clairs: 30));
      expect(s.tauxInfertilite, closeTo(15, 0.01));
    });

    test('la mortalité embryonnaire écarte les clairs du dénominateur', () {
      // 200 charges, 30 clairs retires : 170 oeufs vivaient encore au J+14.
      // 17 gates sur 170 font 10 %, et non 8,5 % sur 200.
      final s = StatistiquesLot(
        lot: lot(code: 'C1', charges: 200, clairs: 30, gates: 17),
      );
      expect(
        s.mortaliteEmbryonnaire,
        closeTo(10, 0.01),
        reason:
            'Les clairs ne sont pas morts, ils n\'ont jamais vécu. Les '
            'compter au dénominateur diluerait le taux et masquerait un '
            'vrai défaut de conduite.',
      );
    });

    test('le TER rapporte les éclos aux seuls œufs retenus', () {
      final s = StatistiquesLot(
        lot: lot(code: 'C1', charges: 200, clairs: 20, gates: 10, eclos: 153),
      );
      // 200 - 30 = 170 retenus ; 153 / 170 = 90 %.
      expect(s.ter, closeTo(90, 0.01));
      // Le taux brut, lui, tombe a 76,5 % — c'est la meme couvee.
      expect(s.tauxBrut, closeTo(76.5, 0.01));
    });

    test('un mirage non fait donne `null`, jamais zéro', () {
      final s = StatistiquesLot(lot: lot(code: 'C1'));
      expect(s.tauxInfertilite, isNull);
      expect(s.mortaliteEmbryonnaire, isNull);
      expect(
        s.mirage1Fait,
        isFalse,
        reason:
            'Un mirage non fait ne dit pas qu\'il n\'y avait aucun œuf clair.',
      );
    });

    test('un mirage à zéro se distingue d\'un mirage non fait', () {
      final fait = StatistiquesLot(lot: lot(code: 'C1', clairs: 0));
      expect(fait.mirage1Fait, isTrue);
      expect(fait.tauxInfertilite, 0);
    });

    test('la perte n\'existe que sur un lot clôturé', () {
      expect(StatistiquesLot(lot: lot(code: 'C1')).tauxPerte, isNull);
      final clos = StatistiquesLot(
        lot: lot(code: 'C1', charges: 200, eclos: 150),
      );
      expect(clos.pertes, 50);
      expect(clos.tauxPerte, closeTo(25, 0.01));
    });
  });

  group('Agrégat sur plusieurs lots', () {
    test('l\'infertilité ne compte que les lots réellement mirés', () {
      final stats = StatistiquesMirages([
        lot(code: 'C1', charges: 100, clairs: 20),
        lot(code: 'C2', charges: 100), // mirage non fait
      ]);

      // 20 clairs sur les 100 oeufs du seul lot mire = 20 %.
      expect(
        stats.tauxInfertilite,
        closeTo(20, 0.01),
        reason:
            'Rapporter aux 200 œufs des deux lots donnerait 10 % : la '
            'négligence ressemblerait à un bon résultat.',
      );
    });

    test('le TER de l\'ensemble ne porte que sur les lots éclos', () {
      final stats = StatistiquesMirages([
        lot(code: 'C1', charges: 200, clairs: 20, gates: 10, eclos: 153),
        lot(code: 'C2', charges: 300), // encore en machine
      ]);
      expect(stats.ter, closeTo(90, 0.01));
    });

    test('sans aucune éclosion, le TER est `null` et non zéro', () {
      final stats = StatistiquesMirages([lot(code: 'C1')]);
      expect(stats.ter, isNull);
      expect(stats.tauxPerte, isNull);
    });

    test('les œufs retenus retirent bien les deux mirages', () {
      final stats = StatistiquesMirages([
        lot(code: 'C1', charges: 200, clairs: 20, gates: 10),
      ]);
      expect(stats.chargesTotal, 200);
      expect(stats.retenusTotal, 170);
    });
  });

  group('Mirages échus et non saisis', () {
    test('un mirage dû mais absent est signalé', () {
      final stats = StatistiquesMirages([
        lot(code: 'C1', chargement: DateTime(2026, 8, 1)),
      ]);

      // Au 5 aout, le mirage 1 (J+7 = le 8) n'est pas encore du.
      expect(stats.miragesManquants(DateTime(2026, 8, 5)), isEmpty);

      // Au 8, il l'est.
      expect(stats.miragesManquants(DateTime(2026, 8, 8)), hasLength(1));
    });

    test('un lot déjà miré ne remonte plus', () {
      final stats = StatistiquesMirages([
        lot(code: 'C1', chargement: DateTime(2026, 8, 1), clairs: 12, gates: 4),
      ]);
      expect(stats.miragesManquants(DateTime(2026, 8, 20)), isEmpty);
    });

    test('un lot clôturé ne réclame plus de mirage', () {
      final stats = StatistiquesMirages([
        lot(code: 'C1', chargement: DateTime(2026, 8, 1), eclos: 150),
      ]);
      expect(stats.miragesManquants(DateTime(2026, 9, 1)), isEmpty);
    });
  });

  group('Fenêtre d\'éclosion', () {
    test('elle s\'étend de deux jours de part et d\'autre', () {
      final goliath = lot(code: 'C1', chargement: DateTime(2026, 8, 1));
      // Goliath : 21 jours -> 22 aout.
      expect(goliath.dateEclosionPrevue, DateTime(2026, 8, 22));
      expect(goliath.eclosionAuPlusTot, DateTime(2026, 8, 20));
      expect(goliath.eclosionAuPlusTard, DateTime(2026, 8, 24));
    });

    test('la pintade incube 28 jours, pas 27', () {
      final pintade = lot(
        code: 'C2',
        chargement: DateTime(2026, 8, 1),
        espece: EspeceCouvable.pintade,
      );
      expect(pintade.dateEclosionPrevue, DateTime(2026, 8, 29));
    });
  });
}
