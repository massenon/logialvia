import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../domain/entities/tableau_bord_principal.dart';

/// Courbe « CA vs Dépenses — 6 derniers mois » — `#tour-chart`, dashboard.html
/// l.179-195.
///
/// Le prototype trace un `<svg>` **statique** : les points sont ecrits en dur
/// dans le HTML. Ici la courbe est tracee sur les donnees reellement en base
/// (Doc E7 §5, `fl_chart`) — c'est le meme graphique, alimente pour de vrai.
/// Les couleurs et le trait pointille des depenses sont ceux du prototype :
/// CA en `brand-navy` plein, Depenses en `error-deep` pointille.
class CourbeCaDepenses extends StatelessWidget {
  const CourbeCaDepenses({super.key, required this.points});

  final List<PointMensuel> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox(height: 208);

    final maxY = points
        .expand((p) => [p.chiffreAffaires, p.depenses])
        .fold<double>(0, (m, v) => v > m ? v : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 208, // `h-52`
          child: LineChart(
            LineChartData(
              minY: 0,
              // Sans aucune donnee, un maximum a 0 rendrait l'axe degenere.
              maxY: maxY == 0 ? 1 : maxY * 1.15,
              gridData: const FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: null,
              ),
              borderData: FlBorderData(
                show: true,
                border: const Border(
                  left: BorderSide(color: AppColors.outlineVariant),
                  bottom: BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    getTitlesWidget: (valeur, meta) =>
                        Text(Formats.nombre(valeur), style: _styleAxe),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 1,
                    getTitlesWidget: (valeur, meta) {
                      final index = valeur.round();
                      if (index < 0 || index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return Text(points[index].libelleMois, style: _styleAxe);
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < points.length; i++)
                      FlSpot(i.toDouble(), points[i].chiffreAffaires),
                  ],
                  color: AppColors.brandNavy,
                  barWidth: 3,
                  isCurved: false,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: [
                    for (var i = 0; i < points.length; i++)
                      FlSpot(i.toDouble(), points[i].depenses),
                  ],
                  color: AppColors.errorDeep,
                  barWidth: 3,
                  isCurved: false,
                  dashArray: const [5, 4], // `stroke-dasharray="5,4"`
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Row(
          children: [
            _Legende(
              couleur: AppColors.brandNavy,
              libelle: 'Chiffre d\'affaires',
            ),
            SizedBox(width: AppSpacing.lg),
            _Legende(couleur: AppColors.errorDeep, libelle: 'Dépenses'),
          ],
        ),
      ],
    );
  }

  static const TextStyle _styleAxe = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 10,
    color: AppColors.outline,
  );
}

/// Barres « Statistiques de Ventes » — dashboard.html l.253-264.
/// Recettes en `brand-navy`, depenses en `error-deep`, une paire par jour.
class BarresRecettesDepenses extends StatelessWidget {
  const BarresRecettesDepenses({super.key, required this.points});

  final List<PointJournalier> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox(height: 128);

    final maxY = points
        .expand((p) => [p.recettes, p.depenses])
        .fold<double>(0, (m, v) => v > m ? v : m);

    return SizedBox(
      height: 128, // `h-32`
      child: BarChart(
        BarChartData(
          maxY: maxY == 0 ? 1 : maxY * 1.15,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(
            show: true,
            border: const Border(
              bottom: BorderSide(color: AppColors.outlineVariant),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                getTitlesWidget: (valeur, meta) {
                  final index = valeur.round();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    points[index].libelleJour,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 9,
                      color: AppColors.outline,
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 4,
                barRods: [
                  BarChartRodData(
                    toY: points[i].recettes,
                    color: AppColors.brandNavy,
                    width: 14,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  BarChartRodData(
                    toY: points[i].depenses,
                    color: AppColors.errorDeep,
                    width: 14,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Legende extends StatelessWidget {
  const _Legende({required this.couleur, required this.libelle});

  final Color couleur;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          libelle,
          style: const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            color: AppColors.outline,
          ),
        ),
      ],
    );
  }
}
