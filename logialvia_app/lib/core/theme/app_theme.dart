import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_typography.dart';

/// Theme global — traduction des tokens Doc 01 en `ThemeData`.
/// Toute couleur/typographie d'ecran doit venir d'ici ou des classes `App*`,
/// jamais d'une valeur hexadecimale en dur (Master Prompt §4).
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.surfaceBg,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.brandNavy,
        secondary: AppColors.brandGold,
        surface: AppColors.surfaceCard,
        error: AppColors.errorDeep,
        onSurface: AppColors.onSurface,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: AppTypography.fontFamily,
        bodyColor: AppColors.onSurface,
        displayColor: AppColors.onSurface,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceCard,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      ),
      tooltipTheme: const TooltipThemeData(
        textStyle: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12,
          color: Colors.white,
        ),
      ),
    );
  }
}
