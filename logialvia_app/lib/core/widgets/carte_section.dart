import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../tour/tour_guide.dart';

/// Panneau blanc a titre — motif repete sur tous les tableaux de bord et la
/// majorite des ecrans internes :
/// `bg-white rounded-lg border border-outline-variant shadow-sm p-md` + un
/// `<h3 class="text-sm font-bold">`.
class CarteSection extends StatelessWidget {
  const CarteSection({
    super.key,
    required this.titre,
    required this.child,
    this.icone,
    this.couleurIcone,
    this.action,
    this.cibleTour,
  });

  final String titre;
  final Widget child;
  final IconData? icone;
  final Color? couleurIcone;

  /// Element aligne a droite du titre (lien « Voir tout », badge d'annee…).
  final Widget? action;

  /// Nom de la cible de visite guidee, si cette carte en est une.
  ///
  /// Porte par la carte plutot qu'ajoute autour d'elle : la quasi-totalite des
  /// `selector` du prototype designent un panneau ou son tableau. Une cible se
  /// declare donc en une ligne, sans reindenter l'arbre.
  final String? cibleTour;

  @override
  Widget build(BuildContext context) {
    final carte = _carte();
    return cibleTour == null
        ? carte
        : CibleTour(nom: cibleTour!, child: carte);
  }

  Widget _carte() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icone != null) ...[
                Icon(icone, size: 18, color: couleurIcone ?? AppColors.brandNavy),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text(
                  titre,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 14, // `text-sm`
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// Etat vide explicite. Une section sans donnee doit dire **pourquoi** elle est
/// vide — un panneau blanc muet laisse croire a un bug (Master Prompt §2.2).
class EtatVide extends StatelessWidget {
  const EtatVide({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12,
          height: 1.5,
          color: AppColors.outline,
        ),
      ),
    );
  }
}
