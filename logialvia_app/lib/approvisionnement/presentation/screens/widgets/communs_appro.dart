import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

const TextStyle texteAppro = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

final TextStyle grasAppro = texteAppro.copyWith(fontWeight: FontWeight.w700);

final InputDecoration decorationAppro = InputDecoration(
  isDense: true,
  filled: true,
  fillColor: AppColors.surfaceCard,
  hintStyle: texteAppro.copyWith(color: AppColors.outline),
  labelStyle: texteAppro,
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  ),
  border: OutlineInputBorder(
    borderRadius: AppRadius.cardRadius,
    borderSide: const BorderSide(color: AppColors.outlineVariant),
  ),
);

/// En-tête de tableau partagé par les 3 écrans du module.
class EnteteTableauAppro extends StatelessWidget {
  const EnteteTableauAppro({super.key, required this.colonnes});

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
                style: texteAppro.copyWith(color: AppColors.outline),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ligne de tableau zébrée.
class LigneTableauAppro extends StatelessWidget {
  const LigneTableauAppro({
    super.key,
    required this.cellules,
    required this.zebre,
  });

  final List<(Widget, int)> cellules;
  final bool zebre;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: zebre ? AppColors.surfaceZebra : null,
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

/// Pastille de statut.
class PastilleAppro extends StatelessWidget {
  const PastilleAppro({
    super.key,
    required this.libelle,
    required this.fond,
    required this.couleurTexte,
  });

  final String libelle;
  final Color fond;
  final Color couleurTexte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(color: fond, borderRadius: AppRadius.pill),
      child: Text(
        libelle,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: couleurTexte,
        ),
      ),
    );
  }
}

/// Champ de saisie étiqueté.
class ChampAppro extends StatelessWidget {
  const ChampAppro({
    super.key,
    required this.libelle,
    required this.controleur,
    this.clavier,
    this.formatteurs,
    this.note,
  });

  final String libelle;
  final TextEditingController controleur;
  final TextInputType? clavier;

  /// Filtre de frappe — voir `FormatteursSaisie`.
  final List<TextInputFormatter>? formatteurs;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(libelle.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controleur,
          keyboardType: clavier,
        inputFormatters: formatteurs,
          style: texteAppro,
          decoration: decorationAppro,
        ),
        if (note != null)
          Text(
            note!,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              color: AppColors.outline,
            ),
          ),
      ],
    );
  }
}
