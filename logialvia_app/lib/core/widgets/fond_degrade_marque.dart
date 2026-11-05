import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Fond plein ecran des 3 ecrans d'authentification : degrade navy + texture de
/// grain en pointilles. Mutualise ici car repete a l'identique sur index.html,
/// welcome.html et login.html (Master Prompt §4, zero duplication).
///
/// Correspondances CSS exactes :
/// - Splash  : `linear-gradient(180deg,#1F3864 0%,#152847 100%)` + filigrane 28px, opacite .05
/// - Welcome : `linear-gradient(160deg,#1F3864 0%,#152847 100%)` (aucun filigrane)
/// - Login   : `linear-gradient(165deg,#1F3864 0%,#152847 100%)` + grain 26px, rgba(255,255,255,.06) a opacite .5
class FondDegradeMarque extends StatelessWidget {
  const FondDegradeMarque({
    super.key,
    required this.child,
    required this.angleDegres,
    this.espacementPoints,
    this.couleurPoints,
  });

  final Widget child;

  /// Angle CSS du `linear-gradient` (0deg = vers le haut, sens horaire).
  final double angleDegres;

  /// `background-size` du filigrane. `null` = aucun filigrane (cas Welcome).
  final double? espacementPoints;

  /// Couleur effective d'un point, opacite comprise.
  final Color? couleurPoints;

  @override
  Widget build(BuildContext context) {
    final radians = angleDegres * math.pi / 180;
    // Vecteur de la ligne de degrade en coordonnees ecran (y vers le bas).
    final dx = math.sin(radians);
    final dy = -math.cos(radians);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-dx, -dy),
          end: Alignment(dx, dy),
          colors: const [AppColors.brandNavy, AppColors.brandNavyDark],
        ),
      ),
      child: espacementPoints == null
          ? child
          : Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FiligranePointillePainter(
                      espacement: espacementPoints!,
                      couleur: couleurPoints ?? Colors.white,
                    ),
                  ),
                ),
                Positioned.fill(child: child),
              ],
            ),
    );
  }
}

class _FiligranePointillePainter extends CustomPainter {
  const _FiligranePointillePainter({
    required this.espacement,
    required this.couleur,
  });

  final double espacement;
  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final peinture = Paint()..color = couleur;
    // `radial-gradient(circle, #fff 1px, transparent 1px)` centre dans chaque
    // tuile de `background-size` — soit un point de rayon 1px tous les N px.
    for (double y = espacement / 2; y < size.height; y += espacement) {
      for (double x = espacement / 2; x < size.width; x += espacement) {
        canvas.drawCircle(Offset(x, y), 1, peinture);
      }
    }
  }

  @override
  bool shouldRepaint(_FiligranePointillePainter oldDelegate) =>
      oldDelegate.espacement != espacement || oldDelegate.couleur != couleur;
}
