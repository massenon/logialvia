import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logialvia_app/administration/presentation/screens/compte/widgets/communs_compte.dart';
import 'package:logialvia_app/approvisionnement/presentation/screens/widgets/communs_appro.dart';
import 'package:logialvia_app/comptabilite/presentation/screens/widgets/communs_compta.dart';
import 'package:logialvia_app/core/theme/app_colors.dart';
import 'package:logialvia_app/core/theme/app_spacing.dart';
import 'package:logialvia_app/core/theme/app_typography.dart';
import 'package:logialvia_app/rapports/presentation/screens/widgets/communs_rapports.dart';

/// L'échelle du Design System, verrouillée sur le prototype.
///
/// ## Le défaut que ces tests figent
///
/// `assets/css/common.css` l.44 pose
/// `.text-xs { font-size: 0.85rem !important; }` — soit **13,6 px**, la racine
/// valant 16. Ce fichier est chargé par **35 des 41 pages**, donc par toutes
/// les pages applicatives : la surcharge est **globale**.
///
/// Le portage l'avait lue comme une particularité des trois écrans
/// d'authentification, qui se contentent de la redéclarer en ligne. Résultat :
/// 13,6 px au Splash, à l'Accueil et à la Connexion, **12 px partout
/// ailleurs** — alors que `text-xs` est la classe la plus employée du
/// prototype (1381 emplois). Tout le reste de l'application était rendu 12 %
/// trop petit.
///
/// Mesuré par `outils/audit_typographie.py`, qui refuse de deviner : il ne
/// compte que les tailles posées explicitement sur l'élément.
void main() {
  group('`text-xs` vaut 13,6 px, pas 12', () {
    test('la valeur vient de 0.85rem sur une racine de 16 px', () {
      expect(AppTypography.textXs, 0.85 * 16);
      expect(AppTypography.textXs, 13.6);
    });

    test('elle n\'est surtout pas retombée aux 12 px de Tailwind', () {
      expect(
        AppTypography.textXs,
        isNot(12),
        reason:
            'La surcharge `!important` de common.css bat la règle utilitaire. '
            'Revenir à 12 px rendrait 1381 emplois du prototype trop petits.',
      );
    });
  });

  group('Tableaux — les cellules sont plus grandes que les en-têtes', () {
    test('la cellule est un `text-xs`', () {
      // 433 des 444 cellules mesurables sont en `text-xs`.
      expect(AppTypography.tableCell.fontSize, AppTypography.textXs);
    });

    test('l\'en-tête est un `text-[12px]`', () {
      // 196 en-tetes qui posent leur taille sont en `text-[12px]`.
      expect(AppTypography.tableHeader.fontSize, 12);
      expect(AppTypography.tableHeader.fontWeight, FontWeight.w700);
      expect(AppTypography.tableHeader.color, AppColors.outline);
    });

    test('en-tête de tableau et intitulé de KPI sont le même style', () {
      // `text-[12px] text-outline font-bold uppercase` : 196 en-tetes et
      // 86 intitules de KPI. Deux definitions jumelles finiraient par
      // diverger.
      expect(
        identical(AppTypography.tableHeader, AppTypography.caption),
        isTrue,
      );
    });
    test('l\'écart entre les deux est bien celui du prototype', () {
      expect(
        AppTypography.tableCell.fontSize,
        greaterThan(AppTypography.tableHeader.fontSize!),
        reason:
            'Le prototype fait ses cellules plus grandes que ses en-têtes. '
            'Les égaliser — ce que faisait le portage — aplatit la '
            'hiérarchie de toutes les tables de l\'application.',
      );
    });
  });

  group('Libellés de formulaire', () {
    test('12 px, gras, brand-navy — relevé 147 fois', () {
      expect(AppTypography.label.fontSize, 12);
      expect(AppTypography.label.fontWeight, FontWeight.w700);
      expect(AppTypography.label.color, AppColors.brandNavy);
    });

    test("aucun crénage : le prototype n’en demande pas", () {
      // `uppercase` n'ajoute aucun tracking, et les classes `tracking-*`
      // n'apparaissent que sur quelques elements decoratifs des ecrans
      // d'accueil — jamais sur un libelle de champ. Le `letterSpacing: 0.4`
      // du portage etait une invention.
      expect(AppTypography.label.letterSpacing, isNull);
    });

    test("le libellé ne diffère de l’intitulé que par la couleur", () {
      expect(AppTypography.label.fontSize, AppTypography.caption.fontSize);
      expect(AppTypography.label.fontWeight, AppTypography.caption.fontWeight);
      expect(AppTypography.label.color, isNot(AppTypography.caption.color));
    });
  });

  group('Les styles de base de chaque contexte suivent l\'échelle', () {
    test('aucun ne redescend à 12 px de son côté', () {
      // Ces quatre styles portent l'essentiel du texte courant de leur
      // module : les laisser diverger reintroduirait le defaut module par
      // module, sans que rien ne le signale.
      final bases = <String, TextStyle>{
        'texteCompta': texteCompta,
        'texteAppro': texteAppro,
        'texteCompte': texteCompte,
        'texteRapport': texteRapport,
      };

      bases.forEach((nom, style) {
        expect(
          style.fontSize,
          AppTypography.textXs,
          reason: '$nom a divergé de l\'échelle.',
        );
      });
    });
  });

  group('L\'échelle d\'espacement est celle de tailwind-config.js', () {
    test('xs/sm/md/lg/xl valent 4/8/16/24/32', () {
      expect(AppSpacing.xs, 4);
      expect(AppSpacing.sm, 8);
      expect(AppSpacing.md, 16);
      expect(AppSpacing.lg, 24);
      expect(AppSpacing.xl, 32);
    });
  });

  group('La palette est celle de tailwind-config.js', () {
    test('les 15 couleurs officielles, à la valeur exacte', () {
      // « Charte graphique LogiALVIA - CDCT §10.4, valeurs officielles, ne
      // jamais approximer » — commentaire du prototype lui-meme.
      const attendues = <String, (Color, int)>{
        'brand-navy': (AppColors.brandNavy, 0xFF1F3864),
        'brand-navy-dark': (AppColors.brandNavyDark, 0xFF152847),
        'brand-gold': (AppColors.brandGold, 0xFFB58B2A),
        'brand-gold-light': (AppColors.brandGoldLight, 0xFFD4A94D),
        'surface-bg': (AppColors.surfaceBg, 0xFFF2F2F2),
        'surface-card': (AppColors.surfaceCard, 0xFFFFFFFF),
        'surface-zebra': (AppColors.surfaceZebra, 0xFFF7F7F8),
        'outline-variant': (AppColors.outlineVariant, 0xFFD8DCE3),
        'outline': (AppColors.outline, 0xFF6B7280),
        'on-surface': (AppColors.onSurface, 0xFF1A1D23),
        'error-deep': (AppColors.errorDeep, 0xFFB33A3A),
        'error-container': (AppColors.errorContainer, 0xFFFBE3E3),
        'success-deep': (AppColors.successDeep, 0xFF3A7D44),
        'success-container': (AppColors.successContainer, 0xFFE1F0E3),
        'info-blue': (AppColors.infoBlue, 0xFF2563EB),
      };

      attendues.forEach((nom, paire) {
        final (couleur, valeur) = paire;
        expect(
          couleur.toARGB32(),
          valeur,
          reason: '$nom ne correspond plus à tailwind-config.js.',
        );
      });
    });
  });
}
