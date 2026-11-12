import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Compteur `− valeur +` d'une catégorie — `dayCounterStep()` du prototype
/// (fiche-goliaths.html l.170-174).
///
/// Le champ central est `readonly` côté web : la valeur ne se saisit qu'avec
/// les deux boutons. Reproduit à l'identique — c'est ce qui garantit qu'aucune
/// valeur négative ni non numérique n'entre dans le calcul.
class CompteurCategorie extends StatelessWidget {
  const CompteurCategorie({
    super.key,
    required this.libelle,
    required this.valeur,
    required this.onChange,
  });

  final String libelle;
  final int valeur;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          libelle.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            border: Border.all(color: AppColors.outlineVariant),
            borderRadius: AppRadius.cardRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              _Bouton(
                symbole: '−',
                // Jamais en dessous de zero (BR-ELV-001).
                onTap: valeur > 0 ? () => onChange(valeur - 1) : null,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$valeur',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ),
              _Bouton(symbole: '+', onTap: () => onChange(valeur + 1)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bouton extends StatelessWidget {
  const _Bouton({required this.symbole, required this.onTap});

  final String symbole;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 32,
        height: double.infinity,
        color: AppColors.surfaceZebra,
        child: Center(
          child: Text(
            symbole,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: onTap == null
                  ? AppColors.outlineVariant
                  : AppColors.brandNavy,
            ),
          ),
        ),
      ),
    );
  }
}
