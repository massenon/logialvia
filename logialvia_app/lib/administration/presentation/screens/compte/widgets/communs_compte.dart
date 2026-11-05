import 'package:flutter/material.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';

const TextStyle texteCompte = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

final TextStyle grasCompte = texteCompte.copyWith(fontWeight: FontWeight.w700);

/// En-tête de page des 3 écrans — `border-b border-outline-variant pb-md`.
class EnteteCompte extends StatelessWidget {
  const EnteteCompte({
    super.key,
    required this.icone,
    required this.titre,
    required this.sousTitre,
  });

  final IconData icone;
  final String titre;
  final String sousTitre;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 26, color: AppColors.brandNavy),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(titre, style: AppTypography.pageTitle)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            sousTitre,
            style: texteCompte.copyWith(color: AppColors.outline),
          ),
        ],
      ),
    );
  }
}

/// Champ de formulaire libellé — motif commun aux 2 formulaires de F9.
class ChampCompte extends StatelessWidget {
  const ChampCompte({
    super.key,
    required this.libelle,
    required this.controleur,
    this.masque = false,
    this.lignes = 1,
    this.indication,
  });

  final String libelle;
  final TextEditingController controleur;
  final bool masque;
  final int lignes;
  final String? indication;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(libelle.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controleur,
          obscureText: masque,
          maxLines: masque ? 1 : lignes,
          minLines: masque ? 1 : lignes,
          style: texteCompte,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.surfaceCard,
            hintText: indication,
            hintStyle: texteCompte.copyWith(color: AppColors.outline),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            border: OutlineInputBorder(
              borderRadius: AppRadius.cardRadius,
              borderSide: const BorderSide(color: AppColors.outlineVariant),
            ),
          ),
        ),
      ],
    );
  }
}

/// Encart d'information — bleu par défaut (comme le prototype), gris quand il
/// énonce une limite d'implémentation plutôt qu'une consigne métier.
class NoteCompte extends StatelessWidget {
  const NoteCompte({super.key, required this.texte, this.neutre = false});

  final String texte;
  final bool neutre;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: neutre
            ? AppColors.surfaceZebra
            : AppColors.infoBlue.withValues(alpha: 0.1),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: neutre
              ? AppColors.outlineVariant
              : AppColors.infoBlue.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        texte,
        style: texteCompte.copyWith(
          fontSize: 11,
          color: AppColors.outline,
          height: 1.5,
        ),
      ),
    );
  }
}

/// En-tête de tableau — même rendu que les autres modules.
class EnteteCompte2 extends StatelessWidget {
  const EnteteCompte2({super.key, required this.colonnes});

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
                style: texteCompte.copyWith(color: AppColors.outline),
              ),
            ),
        ],
      ),
    );
  }
}

class LigneCompte extends StatelessWidget {
  const LigneCompte({super.key, required this.cellules, required this.zebre});

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
