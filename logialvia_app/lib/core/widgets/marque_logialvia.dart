import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Partie du mot-symbole affichee en or.
/// Le prototype n'est pas uniforme : "Logi**ALVIA**" sur index.html/login.html,
/// "**Logi**ALVIA" sur welcome.html. Reproduit tel quel, pas harmonise.
enum PartieDoree { logi, alvia }

/// Mot-symbole "LogiALVIA" — present sur les 3 ecrans d'authentification.
class MarqueLogiAlvia extends StatelessWidget {
  const MarqueLogiAlvia({
    super.key,
    required this.fontSize,
    required this.fontWeight,
    required this.couleurBase,
    this.partieDoree = PartieDoree.alvia,
    this.couleurDoree = AppColors.brandGold,
    this.letterSpacing,
    this.height,
  });

  final double fontSize;
  final FontWeight fontWeight;
  final Color couleurBase;
  final PartieDoree partieDoree;
  final Color couleurDoree;
  final double? letterSpacing;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: couleurBase,
      letterSpacing: letterSpacing,
      height: height,
    );

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(
            text: 'Logi',
            style: partieDoree == PartieDoree.logi
                ? TextStyle(color: couleurDoree)
                : null,
          ),
          TextSpan(
            text: 'ALVIA',
            style: partieDoree == PartieDoree.alvia
                ? TextStyle(color: couleurDoree)
                : null,
          ),
        ],
      ),
    );
  }
}
