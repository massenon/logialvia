import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Carte d'indicateur — Doc E2 §3, structure fidele a `dashboard.html` l.135-139.
///
/// REGLE NON NEGOCIABLE (Doc E7 §1) : la carte affiche **toujours** son libelle
/// et un texte de valeur. `valeur` est un `String` non-nullable precisement pour
/// rendre impossible une carte vide — un indicateur a zero affiche « 0 », un
/// indicateur non applicable affiche « — », jamais du blanc.
///
/// PIEGE EVITE (Doc K4 §6, bug reellement rencontre sur AgriERP) : Flutter
/// refuse un `Border` a couleurs non uniformes combine a un `borderRadius`.
/// La bordure gauche coloree (`border-l-4 border-l-*` cote web) est donc une
/// bande superposee dans un `Stack` clippe, pas un cote de `Border`.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.accent,
    this.unite,
    this.detail,
    this.icone,
  });

  final String libelle;
  final String valeur;
  final Color accent;
  final String? unite;
  final String? detail;
  final IconData? icone;

  static const double _epaisseurBande = 4; // `border-l-4`

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadows.sm,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.cardRadius,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                border: Border.all(color: AppColors.outlineVariant),
                borderRadius: AppRadius.cardRadius,
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md + _epaisseurBande,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          libelle.toUpperCase(),
                          style: AppTypography.caption,
                        ),
                      ),
                      if (icone != null) Icon(icone, size: 18, color: accent),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: valeur),
                        if (unite != null)
                          TextSpan(
                            text: ' $unite',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 24, // `md:text-2xl`
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        color: AppColors.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _epaisseurBande,
              child: ColoredBox(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}
