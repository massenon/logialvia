import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/tour/scenarios_tour.dart';
import 'package:logialvia_app/core/tour/tour_guide.dart';

/// Moteur de visite guidée — `common.js` §16, Doc K2 §B.
void main() {
  setUp(RegistreTour.vider);

  Widget enveloppe(Widget enfant) => MaterialApp(home: Scaffold(body: enfant));

  group('Registre des cibles — l\'équivalent de querySelector', () {
    testWidgets('une cible montée est trouvée', (tester) async {
      await tester.pumpWidget(
        enveloppe(const CibleTour(nom: 'kpi-panel', child: Text('KPI'))),
      );

      expect(RegistreTour.existe('kpi-panel'), isTrue);
      expect(RegistreTour.rendu('kpi-panel'), isNotNull);
    });

    testWidgets('une cible démontée ne l\'est plus', (tester) async {
      await tester.pumpWidget(
        enveloppe(const CibleTour(nom: 'kpi-panel', child: Text('KPI'))),
      );
      expect(RegistreTour.existe('kpi-panel'), isTrue);

      await tester.pumpWidget(enveloppe(const Text('Autre écran')));

      expect(
        RegistreTour.existe('kpi-panel'),
        isFalse,
        reason:
            'Un selecteur CSS cesse de correspondre quand le noeud quitte le '
            'DOM ; le registre doit se comporter pareil, sinon la visite '
            'surlignerait un widget disparu.',
      );
    });

    testWidgets('une cible jamais déclarée est absente', (tester) async {
      await tester.pumpWidget(enveloppe(const Text('Écran nu')));
      expect(RegistreTour.existe('inexistante'), isFalse);
    });

    testWidgets('CibleTour n\'ajoute aucun rendu', (tester) async {
      await tester.pumpWidget(
        enveloppe(
          const CibleTour(
            nom: 'boite',
            child: SizedBox(width: 120, height: 40),
          ),
        ),
      );

      final taille = tester.getSize(find.byType(SizedBox).first);
      expect(
        taille,
        const Size(120, 40),
        reason:
            'Aucune marge, aucune bordure : le surlignage est peint par la '
            'superposition, au-dessus de l\'ecran.',
      );
    });
  });

  group('Scénarios repris du prototype', () {
    test('les 35 routes scénarisées sont déclarées', () {
      expect(ScenariosTour.parRoute, hasLength(35));
    });

    test('65 étapes au total', () {
      final total = ScenariosTour.parRoute.values.fold<int>(
        0,
        (s, e) => s + e.length,
      );
      expect(
        total,
        65,
        reason:
            '42 etapes reprises du prototype — 45 moins les 3 « Administrer '
            'une Dose », dont le selecteur #administrer-dose-form n\'existe '
            'dans aucun fichier — plus 17 redigees pour les 12 ecrans que le '
            'prototype laissait sans visite, plus 6 pour les fiches Escargots '
            'et Bovins ajoutees apres lui.',
      );
    });

    test('aucune étape n\'a de titre ou de texte vide', () {
      for (final entree in ScenariosTour.parRoute.entries) {
        for (final etape in entree.value) {
          expect(etape.titre.trim(), isNotEmpty, reason: entree.key);
          expect(etape.texte.trim(), isNotEmpty, reason: entree.key);
          expect(etape.cible.trim(), isNotEmpty, reason: entree.key);
        }
      }
    });

    test('les écrans que le prototype laissait sans visite en ont une', () {
      // Ces ecrans existent depuis toujours, mais aucune page HTML ne leur
      // avait ecrit de `TOUR_STEPS` : la Gerante ouvrait la visite guidee
      // et tombait sur le message « aucun scenario ».
      for (final route in const [
        '/clients',
        '/achats',
        '/depenses',
        '/comptabilite',
        '/comptabilite/balance',
        '/comptabilite/grand-livre',
        '/comptabilite/etats-financiers',
        '/inventaire',
        '/elevage/mirages',
        '/profil',
        '/aide',
        '/contact',
      ]) {
        expect(ScenariosTour.pour(route), isNotEmpty, reason: route);
      }
    });

    test('les deux filières ajoutées ont leur visite, sur les cibles de la fiche',
        () {
      for (final route in const ['/elevage/escargots', '/elevage/bovins']) {
        final cibles = ScenariosTour.pour(route).map((e) => e.cible).toList();
        expect(cibles, [
          'saisie-journaliere',
          'prophylaxie-du-jour',
          'bascule-hebdomadaire',
        ], reason: route);
      }
    });

    test('une route inconnue renvoie zéro étape, pas une erreur', () {
      // `common.js` §16 : mieux vaut un message honnete qu'un tour vide.
      expect(ScenariosTour.pour('/route-qui-n-existe-pas'), isEmpty);
    });

    test('l\'étape du mode de règlement ne parle plus de trois modes', () {
      final etape = ScenariosTour.pour(
        '/ventes',
      ).firstWhere((e) => e.cible == 'mode-reglement');

      expect(
        etape.texte,
        contains('Comptant'),
        reason:
            'Depuis l\'arbitrage, l\'instrument et la condition sont deux '
            'choix distincts.',
      );
      expect(etape.texte.contains('Especes, Mobile Money, ou Avance'), isFalse);
    });

    test('le bilan de l\'entreprise a bien récupéré sa visite', () {
      // L'ecran avait ete supprime a tort ; son scenario existait toujours.
      expect(ScenariosTour.pour('/comptabilite/bilan'), hasLength(1));
      expect(
        ScenariosTour.pour('/comptabilite/bilan').single.cible,
        'bandeau-equilibre',
      );
    });
  });

  group('Filtrage des étapes — le comportement de startTourGuide()', () {
    testWidgets('seules les étapes dont la cible est affichée sont retenues', (
      tester,
    ) async {
      // Le tableau de bord declare 5 etapes ; on n'en monte qu'une.
      await tester.pumpWidget(
        enveloppe(const CibleTour(nom: 'kpi-panel', child: Text('KPI'))),
      );

      final retenues = ScenariosTour.pour(
        '/dashboard',
      ).where((e) => RegistreTour.existe(e.cible)).toList();

      expect(ScenariosTour.pour('/dashboard'), hasLength(5));
      expect(retenues, hasLength(1));
      expect(retenues.single.titre, contains('Indicateurs'));
    });

    testWidgets('aucune cible affichée : aucune étape retenue', (tester) async {
      await tester.pumpWidget(enveloppe(const Text('Écran nu')));

      final retenues = ScenariosTour.pour(
        '/dashboard',
      ).where((e) => RegistreTour.existe(e.cible)).toList();

      expect(
        retenues,
        isEmpty,
        reason:
            'C\'est le cas ou le prototype affiche son message honnete plutot '
            'que de simuler un tour vide.',
      );
    });
  });
}
