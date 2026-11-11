import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/formatage/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/carte_section.dart';
import 'documents_comptables.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import '../viewmodels/comptabilite_view_model.dart';
import 'widgets/communs_compta.dart';

/// Comptabilité Analytique — Doc F6 §7, d'après `comptabilite-analytique.html`.
///
/// ## ⚠️ Écart assumé et signalé : les centres affichés ne sont pas ceux du
/// prototype
///
/// Le prototype affiche trois centres — **Goliaths, Pintades, Commerce
/// Annexe** — avec des montants écrits en dur dans son script (58 000 / 40 000
/// / 44 000 de revenus). Ces chiffres ne sont dérivés d'aucune donnée : ils
/// sont posés « pour être cohérents avec `rapports-exports.html` ».
///
/// Reproduire cette ventilation supposerait un **axe analytique** sur
/// `ECRITURE_COMPTABLE` — une colonne « centre de coût » que Doc D1 ne prévoit
/// pas, qu'aucun écran ne saisit, et qui de toute façon ne saurait pas répartir
/// un sac de maïs entre plusieurs espèces qui le partagent.
///
/// Cet écran affiche donc la seule ventilation que le grand livre permet
/// réellement : **Avicole** (702 / 602 + 604) et **Commerce Annexe** (701 /
/// 601) — la même que le KPI « Chiffre d'Affaires » du tableau de bord. Les
/// charges de structure non affectables sont montrées à part au lieu d'être
/// réparties arbitrairement, et le manque est énoncé à l'écran.
class ComptabiliteAnalytiqueScreen extends StatelessWidget {
  const ComptabiliteAnalytiqueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ComptabiliteViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    final centres = vm.centresAnalytiques;
    final totalRevenus = centres.fold<double>(0, (s, c) => s + c.revenus);
    final totalCouts = centres.fold<double>(0, (s, c) => s + c.couts);
    final totalMarge = totalRevenus - totalCouts;
    final tauxTotal = totalRevenus.abs() < 0.01
        ? null
        : totalMarge / totalRevenus * 100;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.insights,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Comptabilité Analytique',
                  style: AppTypography.pageTitle,
                ),
              ),
              SelecteurExercice(vm: vm),
              const SizedBox(width: AppSpacing.md),
              BoutonExportPdf(
                construire: () => DocumentsComptables.analytique(vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Marges réelles par activité, calculées sur les écritures de '
            'l\'exercice ${vm.exercice}.',
            style: texteCompta.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _NoteLimite(),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Marges par centre de profit',
            cibleTour: 'tableau-analytique',
            icone: Symbols.table_rows,
            child: totalRevenus.abs() < 0.01 && totalCouts.abs() < 0.01
                ? EtatVide(
                    message:
                        'Aucun produit ni charge d\'exploitation sur '
                        'l\'exercice ${vm.exercice}. Les marges apparaîtront '
                        'dès la première vente enregistrée.',
                  )
                : Column(
                    children: [
                      const EnteteCompta(
                        colonnes: [
                          ('CENTRE DE COÛT / PROFIT', 5, TextAlign.left),
                          ('REVENUS', 2, TextAlign.right),
                          ('COÛTS DIRECTS', 2, TextAlign.right),
                          ('MARGE', 2, TextAlign.right),
                          ('TAUX DE MARGE', 2, TextAlign.right),
                        ],
                      ),
                      for (var i = 0; i < centres.length; i++)
                        LigneCompta(
                          zebre: i.isOdd,
                          cellules: [
                            (
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    centres[i].nom,
                                    style: grasCompta.copyWith(
                                      color: AppColors.brandNavy,
                                    ),
                                  ),
                                  Text(
                                    centres[i].detail,
                                    style: texteCompta.copyWith(
                                      fontSize: 10,
                                      color: AppColors.outline,
                                    ),
                                  ),
                                ],
                              ),
                              5,
                            ),
                            (
                              Text(
                                montantOuTiret(centres[i].revenus),
                                textAlign: TextAlign.right,
                                style: montantCompta.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.successDeep,
                                ),
                              ),
                              2,
                            ),
                            (
                              Text(
                                montantOuTiret(centres[i].couts),
                                textAlign: TextAlign.right,
                                style: montantCompta.copyWith(
                                  color: AppColors.errorDeep,
                                ),
                              ),
                              2,
                            ),
                            (
                              Text(
                                montantOuTiret(centres[i].marge),
                                textAlign: TextAlign.right,
                                style: montantCompta.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: centres[i].marge < 0
                                      ? AppColors.errorDeep
                                      : AppColors.brandNavy,
                                ),
                              ),
                              2,
                            ),
                            (
                              Text(
                                centres[i].tauxMarge == null
                                    ? '—'
                                    : Formats.pourcentage(
                                        centres[i].tauxMarge!,
                                      ),
                                textAlign: TextAlign.right,
                                style: montantCompta.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              2,
                            ),
                          ],
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.brandGold.withValues(alpha: 0.1),
                          border: const Border(
                            top: BorderSide(
                              color: AppColors.brandNavy,
                              width: 2,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Text('TOTAL', style: grasCompta),
                            ),
                            for (final valeur in [
                              montantOuTiret(totalRevenus),
                              montantOuTiret(totalCouts),
                              montantOuTiret(totalMarge),
                              tauxTotal == null
                                  ? '—'
                                  : Formats.pourcentage(tauxTotal),
                            ])
                              Expanded(
                                flex: 2,
                                child: Text(
                                  valeur,
                                  textAlign: TextAlign.right,
                                  style: grasCompta.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (vm.chargesNonAffectees.abs() >= 0.01)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Row(
                            children: [
                              const Icon(
                                Symbols.info,
                                size: 16,
                                color: AppColors.outline,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  'Charges de structure non affectées à un '
                                  'centre : '
                                  '${Formats.montant(vm.chargesNonAffectees)} '
                                  '(locations, assurances, transports, charges '
                                  'diverses). Elles pèsent sur le résultat net '
                                  'mais ne sont pas réparties arbitrairement '
                                  'entre les activités.',
                                  style: texteCompta.copyWith(
                                    color: AppColors.outline,
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Comparaison Visuelle des Marges',
            icone: Symbols.bar_chart,
            child: totalRevenus.abs() < 0.01
                ? const EtatVide(
                    message:
                        'Le graphique apparaîtra dès qu\'un revenu sera '
                        'enregistré.',
                  )
                : Column(
                    children: [
                      for (final centre in centres)
                        _BarreMarge(
                          centre: centre,
                          maximum: centres
                              .map((c) => c.revenus)
                              .fold<double>(0, (a, b) => a > b ? a : b),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NoteLimite extends StatelessWidget {
  const _NoteLimite();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.brandGold.withValues(alpha: 0.12),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.brandGold),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Symbols.info, size: 20, color: AppColors.brandNavy),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ventilation par activité, et non par filière',
                  style: grasCompta.copyWith(color: AppColors.brandNavy),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Une répartition Goliaths / Pintades / Lapins / Poissons-'
                  'chats exigerait un axe analytique sur chaque écriture : le '
                  'modèle de données n\'en comporte pas, et aucun écran ne le '
                  'saisit. Un sac de provende nourrit d\'ailleurs plusieurs '
                  'espèces à la fois — le rattacher à une seule serait une '
                  'estimation, pas une comptabilité. Les marges ci-dessous '
                  'sont calculées sur les comptes réellement mouvementés.',
                  style: texteCompta.copyWith(
                    color: AppColors.onSurface,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarreMarge extends StatelessWidget {
  const _BarreMarge({required this.centre, required this.maximum});

  final CentreAnalytique centre;
  final double maximum;

  @override
  Widget build(BuildContext context) {
    final ratio = maximum.abs() < 0.01
        ? 0.0
        : (centre.revenus / maximum).clamp(0.0, 1.0);
    final ratioMarge = centre.revenus.abs() < 0.01
        ? 0.0
        : (centre.marge / centre.revenus).clamp(0.0, 1.0) * ratio;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(centre.nom, style: grasCompta)),
              Text(
                '${Formats.montant(centre.marge)} de marge sur '
                '${Formats.montant(centre.revenus)}',
                style: texteCompta.copyWith(color: AppColors.outline),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Barre de revenus, dont la part sombre represente la marge.
          ClipRRect(
            borderRadius: AppRadius.pill,
            child: Container(
              height: 14,
              color: AppColors.surfaceZebra,
              child: Stack(
                children: [
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(color: AppColors.brandGoldLight),
                  ),
                  FractionallySizedBox(
                    widthFactor: ratioMarge,
                    child: Container(color: AppColors.brandNavy),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
