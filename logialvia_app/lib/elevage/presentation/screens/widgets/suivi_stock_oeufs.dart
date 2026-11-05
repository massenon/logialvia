import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/champ_saisie_nombre.dart';
import '../../../domain/services/calcul_fiche_journaliere.dart';

/// Section « Suivi du Stock d'Œufs » — **unique à l'onglet Pondeuses**
/// (Doc H2 §Onglet 2, Doc 05 §4).
///
/// Disposition fidèle au schéma de Doc H2 :
/// ```
/// Stock Hier (SRH) : [lecture seule]
/// Œufs Pondus : [saisie]   Œufs Cassés : [saisie]
/// Total Stock (TS) : [lecture seule, calculé]
/// Sorties (Plateaux) : [saisie]
/// Stock Final : [lecture seule, calculé]
/// ```
///
/// **SRH, TS et Stock Final ne sont jamais saisissables** (BR-ELV-008). Ils
/// sont rendus par des `Text`, pas par des champs en lecture seule : l'invariant
/// est structurel et non contournable.
class SuiviStockOeufs extends StatelessWidget {
  const SuiviStockOeufs({
    super.key,
    required this.resultat,
    required this.oeufsPondus,
    required this.oeufsCasses,
    required this.sortiesPlateaux,
    required this.onChangePondus,
    required this.onChangeCasses,
    required this.onChangeSorties,
  });

  final ResultatStockOeufs resultat;
  final int oeufsPondus;
  final int oeufsCasses;
  final int sortiesPlateaux;
  final ValueChanged<int> onChangePondus;
  final ValueChanged<int> onChangeCasses;
  final ValueChanged<int> onChangeSorties;

  bool get _cassesInvalides => oeufsCasses > oeufsPondus;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.brandGold.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.brandGold.withValues(alpha: 0.3)),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Symbols.egg, size: 18, color: AppColors.brandGold),
              SizedBox(width: AppSpacing.xs),
              Text(
                'SUIVI DU STOCK D\'ŒUFS',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _ValeurCalculee(
            libelle: 'Stock Hier (SRH)',
            valeur: resultat.srh,
            // Rappel affiche : c'est le Stock Final de la veille, pas son TS.
            note: 'Stock Final de la veille',
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: ChampSaisieNombre(
                  libelle: 'Œufs Pondus',
                  valeur: oeufsPondus,
                  onChange: onChangePondus,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ChampSaisieNombre(
                  libelle: 'Œufs Cassés',
                  valeur: oeufsCasses,
                  onChange: onChangeCasses,
                  erreur: _cassesInvalides
                      ? 'Ne peut dépasser les œufs pondus.'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _ValeurCalculee(
            libelle: 'Total Stock (TS)',
            valeur: resultat.totalStock,
            note: '= (Pondus − Cassés) + SRH',
          ),
          const SizedBox(height: AppSpacing.sm),
          ChampSaisieNombre(
            libelle: 'Sorties (Plateaux)',
            valeur: sortiesPlateaux,
            onChange: onChangeSorties,
            note: '${resultat.sortiesOeufs} œufs '
                '(${CalculStockOeufs.oeufsParPlateau} par plateau)',
          ),
          const SizedBox(height: AppSpacing.sm),
          _ValeurCalculee(
            libelle: 'Stock Final',
            valeur: resultat.stockFinal,
            note: '= TS − Sorties · devient le SRH de demain',
            miseEnAvant: true,
          ),
        ],
      ),
    );
  }
}

class _ValeurCalculee extends StatelessWidget {
  const _ValeurCalculee({
    required this.libelle,
    required this.valeur,
    required this.note,
    this.miseEnAvant = false,
  });

  final String libelle;
  final int valeur;
  final String note;
  final bool miseEnAvant;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: AppRadius.cardRadius,
        border: miseEnAvant
            ? Border.all(color: AppColors.brandNavy.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  libelle.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy,
                  ),
                ),
                Text(
                  note,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11,
                    color: AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$valeur',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: miseEnAvant ? 20 : 16,
              fontWeight: FontWeight.w900,
              color: AppColors.brandNavy,
            ),
          ),
        ],
      ),
    );
  }
}
