import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../domain/entities/journee_elevage.dart';

/// Tableau mensuel des 31 jours — Doc F3 §3.
///
/// Colonnes : Date, Achat, Né, Vente, Morts, Dons, Effectif.
/// Un clic sur une ligne **charge ce jour dans le formulaire de saisie**, il ne
/// navigue pas vers un autre écran (Doc F3 §3).
///
/// `ListView.builder` et non une `Column` : la liste fait 28 à 31 lignes ici,
/// mais c'est la règle posée par Strict Avoid §8 pour toute liste dont la
/// taille dépend des données.
class TableauMensuel extends StatelessWidget {
  const TableauMensuel({
    super.key,
    required this.nombreJours,
    required this.journees,
    required this.jourActif,
    required this.moisAffiche,
    required this.onSelectionner,
  });

  final int nombreJours;
  final Map<int, JourneeElevage> journees;
  final int jourActif;
  final DateTime moisAffiche;
  final ValueChanged<int> onSelectionner;

  static const List<String> _colonnes = [
    'Date',
    'Achat',
    'Né',
    'Vente',
    'Morts',
    'Dons',
    'Effectif',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppColors.surfaceZebra,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                for (var i = 0; i < _colonnes.length; i++)
                  Expanded(
                    flex: i == 0 ? 2 : 1,
                    child: Text(
                      _colonnes[i],
                      textAlign: i == 0 ? TextAlign.left : TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.outline,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 360,
            child: ListView.builder(
              itemCount: nombreJours,
              itemBuilder: (context, index) {
                final jour = index + 1;
                return _Ligne(
                  jour: jour,
                  journee: journees[jour],
                  moisAffiche: moisAffiche,
                  actif: jour == jourActif,
                  zebre: index.isOdd,
                  onTap: () => onSelectionner(jour),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.jour,
    required this.journee,
    required this.moisAffiche,
    required this.actif,
    required this.zebre,
    required this.onTap,
  });

  final int jour;
  final JourneeElevage? journee;
  final DateTime moisAffiche;
  final bool actif;
  final bool zebre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final saisie = journee?.isRecorded ?? false;

    final style = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: AppTypography.textXs,
      // Un jour non saisi est visuellement distinct d'un jour a zero : sans
      // cela, l'utilisatrice ne peut pas savoir ce qui reste a saisir.
      color: saisie ? AppColors.onSurface : AppColors.outlineVariant,
      fontWeight: actif ? FontWeight.w700 : FontWeight.w400,
    );

    String cellule(int? valeur) => saisie ? '${valeur ?? 0}' : '—';

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: actif
              ? AppColors.brandNavy.withValues(alpha: 0.08)
              : (zebre ? AppColors.surfaceZebra : null),
          border: const Border(
            bottom: BorderSide(color: AppColors.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                '${jour.toString().padLeft(2, '0')}/'
                '${moisAffiche.month.toString().padLeft(2, '0')}',
                style: style.copyWith(
                  fontWeight: FontWeight.w700,
                  color: actif ? AppColors.brandNavy : style.color,
                ),
              ),
            ),
            _Cellule(cellule(journee?.achat), style),
            _Cellule(cellule(journee?.ne), style),
            _Cellule(cellule(journee?.vente), style),
            _Cellule(cellule(journee?.totalMorts), style),
            _Cellule(cellule(journee?.totalDons), style),
            _Cellule(
              cellule(journee?.effectif),
              style.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cellule extends StatelessWidget {
  const _Cellule(this.valeur, this.style);

  final String valeur;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(valeur, textAlign: TextAlign.center, style: style),
    );
  }
}
