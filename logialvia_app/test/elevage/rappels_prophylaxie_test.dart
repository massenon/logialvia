import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/elevage/domain/entities/bande.dart';
import 'package:logialvia_app/elevage/domain/entities/parametres_elevage.dart';
import 'package:logialvia_app/elevage/domain/entities/soin.dart';
import 'package:logialvia_app/elevage/domain/services/rappels_prophylaxie.dart';

/// Les échéances de prophylaxie échues et jamais planifiées.
///
/// ## Le silence que ces tests cassent
///
/// Le rappel du tableau de bord ne lisait que le registre des soins. Une
/// échéance J5 dont la date réelle était hier, et que personne n'était allé
/// planifier, ne déclenchait donc rien — le rappel se taisait exactement dans
/// le cas de l'oubli, celui pour lequel il existe.
void main() {
  final miseEnBande = DateTime(2026, 8, 1);
  final aujourdhui = DateTime(2026, 8, 20);

  Bande bande({
    String id = 'bande-1',
    String espece = 'goliaths',
    String code = 'B-2026-001',
    DateTime? cloture,
  }) => Bande(
    id: id,
    espece: espece,
    code: code,
    dateMiseEnBande: miseEnBande,
    dateCloture: cloture,
  );

  EcheanceProphylaxie echeance({
    String id = '1',
    String espece = 'goliaths',
    required int jour,
    String traitement = 'Vaccin Newcastle',
  }) => EcheanceProphylaxie(
    id: id,
    espece: espece,
    jourCycle: jour,
    traitement: traitement,
    produit: 'ND-Lasota',
    remanenceJours: 0,
  );

  group('Détection', () {
    test('une échéance échue et non planifiée est rappelée', () {
      final rappels = RappelsProphylaxie(
        bandes: [bande()],
        echeances: [echeance(jour: 5)],
        soins: const [],
      ).dues(aujourdhui);

      expect(rappels, hasLength(1));
      expect(rappels.single.espece, 'goliaths');
      expect(rappels.single.projetee.jourDeCycle, 5);
      // J5 depuis le 1er aout = le 5 aout ; 15 jours de retard le 20.
      expect(rappels.single.datePrevue, DateTime(2026, 8, 5));
      expect(rappels.single.joursDeRetard, 15);
      expect(rappels.single.enRetard, isTrue);
    });

    test('une échéance encore à venir ne dit rien', () {
      final rappels = RappelsProphylaxie(
        bandes: [bande()],
        echeances: [echeance(jour: 60)],
        soins: const [],
      ).dues(aujourdhui);

      expect(
        rappels,
        isEmpty,
        reason:
            'Rappeler une échéance qui n\'est pas due noierait celles qui le '
            'sont.',
      );
    });

    test('l\'échéance du jour même est rappelée, sans retard', () {
      // J20 depuis le 1er aout tombe le 20 aout.
      final rappels = RappelsProphylaxie(
        bandes: [bande()],
        echeances: [echeance(jour: 20)],
        soins: const [],
      ).dues(aujourdhui);

      expect(rappels, hasLength(1));
      expect(rappels.single.joursDeRetard, 0);
      expect(rappels.single.enRetard, isFalse);
    });
  });

  group('Ce qui fait taire un rappel', () {
    test('une échéance déjà planifiée sort de la liste', () {
      final soin = Soin(
        id: '1',
        espece: 'goliaths',
        datePrevue: DateTime(2026, 8, 5),
        typeSoin: 'Vaccination',
        statut: StatutSoin.planifie,
        produit: 'ND-Lasota',
        remanenceJours: 0,
        bandeId: 'bande-1',
        echeanceProphylaxieId: '1',
      );

      final rappels = RappelsProphylaxie(
        bandes: [bande()],
        echeances: [echeance(jour: 5)],
        soins: [soin],
      ).dues(aujourdhui);

      expect(
        rappels,
        isEmpty,
        reason:
            'Planifiée, l\'échéance devient un soin daté : c\'est le rappel '
            'des soins qui en a désormais la charge.',
      );
    });

    test('une bande clôturée n\'attend plus rien', () {
      final rappels = RappelsProphylaxie(
        bandes: [bande(cloture: DateTime(2026, 8, 10))],
        echeances: [echeance(jour: 5)],
        soins: const [],
      ).dues(aujourdhui);

      expect(rappels, isEmpty);
    });

    test('sans bande, aucune date n\'est calculable — donc aucun rappel', () {
      final rappels = RappelsProphylaxie(
        bandes: const [],
        echeances: [echeance(jour: 5)],
        soins: const [],
      ).dues(aujourdhui);

      expect(
        rappels,
        isEmpty,
        reason:
            'Sans date de mise en bande, « J5 » ne désigne aucun jour. '
            'Supposer un départ au 1er du mois inventerait une échéance.',
      );
    });

    test('une échéance d\'une autre espèce ne concerne pas la bande', () {
      final rappels = RappelsProphylaxie(
        bandes: [bande()],
        echeances: [echeance(jour: 5, espece: 'pintades')],
        soins: const [],
      ).dues(aujourdhui);

      expect(rappels, isEmpty);
    });
  });

  group('Ordre et regroupement', () {
    test('les plus anciennes échéances viennent en premier', () {
      final rappels = RappelsProphylaxie(
        bandes: [bande()],
        echeances: [
          echeance(id: '1', jour: 15, traitement: 'Vermifuge'),
          echeance(id: '2', jour: 3, traitement: 'Anti-stress'),
          echeance(id: '3', jour: 8, traitement: 'Anti-coccidien'),
        ],
        soins: const [],
      ).dues(aujourdhui);

      expect(
        rappels.map((r) => r.echeance.traitement),
        ['Anti-stress', 'Anti-coccidien', 'Vermifuge'],
        reason:
            'Un traitement oublié il y a trois semaines est plus urgent que '
            'celui d\'avant-hier.',
      );
    });

    test('les espèces concernées se comptent sans doublon', () {
      final rappels = RappelsProphylaxie(
        bandes: [
          bande(),
          bande(id: 'bande-2', espece: 'pintades', code: 'B-2026-002'),
        ],
        echeances: [
          echeance(id: '1', jour: 5),
          echeance(id: '2', jour: 8),
          echeance(id: '3', jour: 5, espece: 'pintades'),
        ],
        soins: const [],
      ).dues(aujourdhui);

      expect(rappels, hasLength(3));
      expect(
        RappelsProphylaxie.especesConcernees(rappels),
        {'goliaths', 'pintades'},
        reason: 'C\'est le nombre de fiches à ouvrir, pas le nombre de lignes.',
      );
    });
  });
}
