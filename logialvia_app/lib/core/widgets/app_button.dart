import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_typography.dart';
import '../tour/tour_guide.dart';

/// Bouton d'action — Doc E2 §1. 3 variantes observees sur les 31 ecrans.
enum AppButtonVariant { primary, outline, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.fullWidth = false,
    this.height = 40, // `h-10` du prototype (Doc 01 §6)
    this.uppercase = false,
    this.letterSpacing,
    this.fontSize = 12,
    this.cibleTour,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool fullWidth;
  final double height;
  final bool uppercase;
  final double? letterSpacing;
  final double fontSize;

  /// Nom de la cible de visite guidee, si ce bouton en est une. Plusieurs
  /// `selector` du prototype visent directement un bouton d'ouverture de
  /// modale (`button[onclick="openModal('modal-create-cycle')"]`).
  final String? cibleTour;

  @override
  Widget build(BuildContext context) {
    final bouton = _bouton(context);
    return cibleTour == null
        ? bouton
        : CibleTour(nom: cibleTour!, child: bouton);
  }

  Widget _bouton(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: AppRadius.cardRadius);
    final textStyle = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: letterSpacing,
    );

    final style = switch (variant) {
      AppButtonVariant.primary => ElevatedButton.styleFrom(
        backgroundColor: AppColors.brandNavy,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.brandNavy.withValues(alpha: 0.5),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
        elevation: 1,
        shape: shape,
        textStyle: textStyle,
      ),
      AppButtonVariant.outline => OutlinedButton.styleFrom(
        foregroundColor: AppColors.outline,
        side: const BorderSide(color: AppColors.outlineVariant),
        shape: shape,
        textStyle: textStyle,
      ),
      AppButtonVariant.danger => ElevatedButton.styleFrom(
        backgroundColor: AppColors.errorDeep,
        foregroundColor: Colors.white,
        elevation: 1,
        shape: shape,
        textStyle: textStyle,
      ),
    };

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16),
          const SizedBox(width: 8),
        ],
        Text(uppercase ? label.toUpperCase() : label),
      ],
    );

    final button = variant == AppButtonVariant.outline
        ? OutlinedButton(onPressed: onPressed, style: style, child: child)
        : ElevatedButton(onPressed: onPressed, style: style, child: child);

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: height,
      child: button,
    );
  }
}
