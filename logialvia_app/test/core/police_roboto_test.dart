import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/core/theme/app_typography.dart';

/// La police Roboto, enfin fournie — et surtout : réellement variable.
///
/// ## Pourquoi ce test existe
///
/// Le dépôt n'avait aucun `.ttf`. Reprendre ceux du SDK Flutter n'aurait rien
/// changé : la série embarquée par le moteur est **statique**
/// (100/300/400/500/700/900), sans 600 ni 800. Or l'application pose
/// `FontWeight.w600` 22 fois et `w800` 23 fois, et le prototype web
/// `font-semibold` 315 fois et `font-extrabold` 127 fois — servis par Google
/// Fonts avec la fonte **variable**. Ces deux graisses étaient donc rendues par
/// la voisine la plus proche : l'écart de rendu que Doc K3 §4 signalait.
///
/// Déclarer une fonte variable dans `pubspec.yaml` ne prouve rien tant que
/// personne n'a vérifié que Flutter applique bien l'axe `wght`. Si la
/// correspondance ne se faisait pas, **tout** le texte tomberait sur l'instance
/// par défaut (400) : une régression massive, et parfaitement silencieuse.
///
/// Ces tests mesurent donc de vraies largeurs de texte.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final chargeur = FontLoader('Roboto')
      ..addFont(rootBundle.load('assets/fonts/Roboto-Variable.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Roboto-Italic-Variable.ttf'));
    await chargeur.load();
  });

  /// Largeur rendue d'un texte à une graisse donnée.
  double largeur(FontWeight graisse, {FontStyle? style}) {
    final peintre = TextPainter(
      text: TextSpan(
        // Une chaîne longue : l'écart entre deux graisses est de l'ordre du
        // pour cent, il faut de quoi le mesurer.
        text: 'Effectif Vivant — Taux de Mortalité Cumulé 12,5 % (FCFA)',
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 32,
          fontWeight: graisse,
          fontStyle: style ?? FontStyle.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return peintre.width;
  }

  group('La fonte variable applique réellement l\'axe wght', () {
    test('600 se distingue de 500 ET de 700 — les deux voisines statiques', () {
      final w500 = largeur(FontWeight.w500);
      final w600 = largeur(FontWeight.w600);
      final w700 = largeur(FontWeight.w700);

      // Avec la serie statique du moteur, 600 tombait sur l'une des deux : une
      // des deux egalites serait vraie. C'est exactement ce qu'on refuse.
      expect(
        w600,
        isNot(w500),
        reason: 'w600 rendu comme du Medium : l\'axe wght n\'est pas appliqué.',
      );
      expect(
        w600,
        isNot(w700),
        reason: 'w600 rendu comme du Bold : l\'axe wght n\'est pas appliqué.',
      );
    });

    test('800 se distingue de 700 et de 900', () {
      expect(largeur(FontWeight.w800), isNot(largeur(FontWeight.w700)));
      expect(largeur(FontWeight.w800), isNot(largeur(FontWeight.w900)));
    });

    test('la largeur croît avec la graisse, de 100 à 900', () {
      final largeurs = [for (final g in FontWeight.values) largeur(g)];
      for (var i = 1; i < largeurs.length; i++) {
        expect(
          largeurs[i],
          greaterThanOrEqualTo(largeurs[i - 1]),
          reason:
              'La graisse ${FontWeight.values[i]} rend plus étroit que la '
              'précédente : l\'axe est appliqué à l\'envers ou pas du tout.',
        );
      }
      // Et l'amplitude totale doit etre reelle, pas un arrondi.
      expect(largeurs.last, greaterThan(largeurs.first));
    });
  });

  group('L\'italique a sa propre fonte', () {
    test('l\'italique ne rend pas comme le romain', () {
      expect(
        largeur(FontWeight.w400, style: FontStyle.italic),
        isNot(largeur(FontWeight.w400)),
        reason:
            'Sans fonte italique déclarée, Flutter retombe sur le romain — le '
            'texte annoncé en italique s\'afficherait droit.',
      );
    });

    test('l\'italique varie aussi en graisse', () {
      expect(
        largeur(FontWeight.w800, style: FontStyle.italic),
        isNot(largeur(FontWeight.w400, style: FontStyle.italic)),
      );
    });
  });
}
