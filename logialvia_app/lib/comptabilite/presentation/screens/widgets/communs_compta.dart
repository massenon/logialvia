import 'package:flutter/material.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../domain/entities/comptabilite.dart';
import '../../viewmodels/comptabilite_view_model.dart';

const TextStyle texteCompta = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

final TextStyle grasCompta = texteCompta.copyWith(fontWeight: FontWeight.w700);

/// Les montants comptables s'alignent en chiffres de largeur fixe : sans cela,
/// une colonne de montants ne se lit pas en diagonale.
final TextStyle montantCompta = texteCompta.copyWith(
  fontFeatures: const [FontFeature.tabularFigures()],
);

final InputDecoration decorationCompta = InputDecoration(
  isDense: true,
  filled: true,
  fillColor: AppColors.surfaceCard,
  hintStyle: texteCompta.copyWith(color: AppColors.outline),
  labelStyle: texteCompta,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  ),
  border: OutlineInputBorder(
    borderRadius: AppRadius.cardRadius,
    borderSide: const BorderSide(color: AppColors.outlineVariant),
  ),
);

/// Affiche un montant, ou un tiret si nul — un zéro dans une colonne de
/// montants comptables est du bruit visuel.
String montantOuTiret(double valeur) =>
    valeur.abs() < 0.01 ? '—' : Formats.nombre(valeur);

class EnteteCompta extends StatelessWidget {
  const EnteteCompta({super.key, required this.colonnes});

  final List<(String, int, TextAlign)> colonnes;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceZebra,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          for (final (libelle, flex, alignement) in colonnes)
            Expanded(
              flex: flex,
              child: Text(
                libelle,
                textAlign: alignement,
                style: texteCompta.copyWith(color: AppColors.outline),
              ),
            ),
        ],
      ),
    );
  }
}

class LigneCompta extends StatelessWidget {
  const LigneCompta({
    super.key,
    required this.cellules,
    required this.zebre,
    this.couleurFond,
  });

  final List<(Widget, int)> cellules;
  final bool zebre;
  final Color? couleurFond;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: couleurFond ?? (zebre ? AppColors.surfaceZebra : null),
        border: const Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          for (final (widget, flex) in cellules)
            Expanded(flex: flex, child: widget),
        ],
      ),
    );
  }
}

/// Bandeau d'équilibre — vert si équilibré, rouge sinon (BR-CPT-004).
class BandeauEquilibre extends StatelessWidget {
  const BandeauEquilibre({
    super.key,
    required this.equilibre,
    required this.ecart,
    required this.libelle,
  });

  final bool equilibre;
  final double ecart;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: equilibre ? AppColors.successContainer : AppColors.errorContainer,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: equilibre ? AppColors.successDeep : AppColors.errorDeep,
        ),
      ),
      child: Row(
        children: [
          Icon(
            equilibre ? Icons.check_circle : Icons.error,
            size: 18,
            color: equilibre ? AppColors.successDeep : AppColors.errorDeep,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              equilibre
                  ? '$libelle — équilibré'
                  : '$libelle — écart de ${Formats.montant(ecart.abs())}. '
                        'Une clôture est impossible tant qu\'il subsiste '
                        '(BR-CPT-004).',
              style: texteCompta.copyWith(
                fontWeight: FontWeight.w600,
                color: equilibre ? AppColors.successDeep : AppColors.errorDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sélecteur d'exercice, commun à tous les écrans du module.
class SelecteurExercice extends StatelessWidget {
  const SelecteurExercice({super.key, required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('EXERCICE', style: AppTypography.label),
        const SizedBox(width: AppSpacing.sm),
        DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: vm.exercices.contains(vm.exercice) ? vm.exercice : null,
            isDense: true,
            style: grasCompta,
            items: [
              for (final annee in vm.exercices)
                DropdownMenuItem(value: annee, child: Text('$annee')),
            ],
            onChanged: (v) {
              if (v != null) vm.changerExercice(v);
            },
          ),
        ),
        if (vm.exerciceEstCloture) ...[
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.errorContainer,
              borderRadius: AppRadius.pill,
            ),
            child: Text(
              'Clôturé',
              style: texteCompta.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.errorDeep,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Ligne d'un état financier (Bilan, Compte de Résultat, TAFIRE).
class LignePosteEtat extends StatelessWidget {
  const LignePosteEtat({super.key, required this.poste});

  final PosteEtat poste;

  @override
  Widget build(BuildContext context) {
    final style = poste.estTotal
        ? grasCompta.copyWith(fontSize: 14, color: AppColors.brandNavy)
        : (poste.estSousTotal
              ? grasCompta.copyWith(color: AppColors.brandNavy)
              : texteCompta);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: poste.estTotal ? AppSpacing.sm : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: poste.estTotal
            ? AppColors.brandNavy.withValues(alpha: 0.07)
            : (poste.estSousTotal ? AppColors.surfaceZebra : null),
        border: poste.estTotal || poste.estSousTotal
            ? const Border(top: BorderSide(color: AppColors.outlineVariant))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(poste.libelle, style: style),
                if (poste.detail != null)
                  Text(
                    poste.detail!,
                    style: texteCompta.copyWith(
                      fontSize: 10,
                      color: AppColors.outline,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              montantOuTiret(poste.montant),
              textAlign: TextAlign.right,
              style: style.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: poste.montant < 0 && !poste.estTotal
                    ? AppColors.errorDeep
                    : style.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
