import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/carte_kpi_lisere.dart';
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

/// Balance Générale — Doc F6 §3, fidèle à `balance-generale.html`.
///
/// Format standard à **6 colonnes** : Ouverture D/C, Mouvements D/C, Final D/C.
/// BR-CPT-004 : le total des soldes finaux débiteurs doit égaler le total des
/// soldes finaux créditeurs — c'est le contrôle qui bloque toute clôture.
class BalanceGeneraleScreen extends StatelessWidget {
  const BalanceGeneraleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ComptabiliteViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Symbols.balance, size: 24, color: AppColors.brandNavy),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text('Balance Générale', style: AppTypography.pageTitle),
              ),
              SelecteurExercice(vm: vm),
              const SizedBox(width: AppSpacing.md),
              // `bal-periode-select` (balance-generale.html l.67).
              _SelecteurPerimetre(vm: vm),
              const SizedBox(width: AppSpacing.md),
              BoutonExportPdf(
                construire: () => DocumentsComptables.balance(vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Synthèse des soldes de tous les comptes utilisés sur la période — '
            'vérification de l\'équilibre avant clôture.',
            style: texteCompta.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.lg),
          _KpisBalance(vm: vm),
          if (!vm.balanceEstEquilibree) ...[
            const SizedBox(height: AppSpacing.lg),
            const _AlerteDesequilibre(),
          ],
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            cibleTour: 'balance-tableau',
            titre: 'Soldes par compte — exercice ${vm.exercice}',
            icone: Symbols.table_rows,
            child: vm.balance.isEmpty
                ? EtatVide(
                    message:
                        'Aucun compte n\'a été mouvementé sur l\'exercice '
                        '${vm.exercice}. La balance apparaîtra dès la première '
                        'vente, le premier achat ou la première dépense.',
                  )
                : _TableauBalance(vm: vm),
          ),
        ],
      ),
    );
  }
}

class _KpisBalance extends StatelessWidget {
  const _KpisBalance({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final equilibree = vm.balanceEstEquilibree;

    return Row(
      children: [
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Total Débits (Soldes Finaux)',
            valeur: Formats.montant(vm.balanceTotalDebit),
            accent: AppColors.successDeep,
            couleurValeur: AppColors.successDeep,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Total Crédits (Soldes Finaux)',
            valeur: Formats.montant(vm.balanceTotalCredit),
            accent: AppColors.errorDeep,
            couleurValeur: AppColors.errorDeep,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: CarteKpiLisere(
            libelle: 'Écart (doit être 0)',
            valeur: Formats.montant(vm.balanceEcart.abs()),
            accent: equilibree ? AppColors.successDeep : AppColors.errorDeep,
            couleurValeur: equilibree
                ? AppColors.successDeep
                : AppColors.errorDeep,
            fond: equilibree
                ? AppColors.successContainer
                : AppColors.errorContainer,
          ),
        ),
      ],
    );
  }
}

class _AlerteDesequilibre extends StatelessWidget {
  const _AlerteDesequilibre();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.errorDeep.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Symbols.warning, size: 20, color: AppColors.errorDeep),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balance Déséquilibrée — BR-CPT-004',
                  style: grasCompta.copyWith(color: AppColors.errorDeep),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Une anomalie de saisie doit être corrigée avant toute '
                  'clôture (périodique ou annuelle) de l\'exercice.',
                  style: texteCompta.copyWith(
                    fontSize: 11,
                    color: AppColors.errorDeep,
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

class _TableauBalance extends StatelessWidget {
  const _TableauBalance({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final lignes = vm.balance;
    final totalOuvD = lignes.fold<double>(0, (s, l) => s + l.ouvertureDebit);
    final totalOuvC = lignes.fold<double>(0, (s, l) => s + l.ouvertureCredit);
    final totalMovD = lignes.fold<double>(0, (s, l) => s + l.mouvementsDebit);
    final totalMovC = lignes.fold<double>(0, (s, l) => s + l.mouvementsCredit);

    return Column(
      children: [
        // En-tete a 2 niveaux : 3 groupes de 2 colonnes Debit/Credit.
        Container(
          color: AppColors.surfaceZebra,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Row(
                  children: [
                    const Expanded(flex: 5, child: SizedBox()),
                    for (final groupe in [
                      'SOLDE OUVERTURE',
                      'MOUVEMENTS PÉRIODE',
                      'SOLDE FINAL',
                    ])
                      Expanded(
                        flex: 4,
                        child: Text(
                          groupe,
                          textAlign: TextAlign.center,
                          style: texteCompta.copyWith(
                            color: AppColors.outline,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  bottom: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        'N° COMPTE',
                        style: texteCompta.copyWith(color: AppColors.outline),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        'LIBELLÉ',
                        style: texteCompta.copyWith(color: AppColors.outline),
                      ),
                    ),
                    for (var i = 0; i < 6; i++)
                      Expanded(
                        flex: 2,
                        child: Text(
                          i.isEven ? 'Débit' : 'Crédit',
                          textAlign: TextAlign.right,
                          style: texteCompta.copyWith(color: AppColors.outline),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < lignes.length; i++)
          LigneCompta(
            zebre: i.isOdd,
            cellules: [
              (
                Text(
                  lignes[i].numeroCompte,
                  style: texteCompta.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                2,
              ),
              (
                Text(
                  lignes[i].libelle,
                  style: texteCompta,
                  overflow: TextOverflow.ellipsis,
                ),
                3,
              ),
              (_Montant(lignes[i].ouvertureDebit), 2),
              (_Montant(lignes[i].ouvertureCredit), 2),
              (_Montant(lignes[i].mouvementsDebit), 2),
              (_Montant(lignes[i].mouvementsCredit), 2),
              (
                _Montant(
                  lignes[i].finalDebit,
                  gras: true,
                  couleur: AppColors.successDeep,
                ),
                2,
              ),
              (
                _Montant(
                  lignes[i].finalCredit,
                  gras: true,
                  couleur: AppColors.errorDeep,
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
          color: AppColors.brandNavy,
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  'TOTAUX',
                  style: grasCompta.copyWith(color: Colors.white),
                ),
              ),
              for (final total in [
                totalOuvD,
                totalOuvC,
                totalMovD,
                totalMovC,
                vm.balanceTotalDebit,
                vm.balanceTotalCredit,
              ])
                Expanded(
                  flex: 2,
                  child: Text(
                    Formats.nombre(total),
                    textAlign: TextAlign.right,
                    style: grasCompta.copyWith(
                      color: Colors.white,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        BandeauEquilibre(
          equilibre: vm.balanceEstEquilibree,
          ecart: vm.balanceEcart,
          libelle: 'Total débiteur = total créditeur',
        ),
      ],
    );
  }
}

class _Montant extends StatelessWidget {
  const _Montant(this.valeur, {this.gras = false, this.couleur});

  final double valeur;
  final bool gras;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final nul = valeur.abs() < 0.01;
    return Text(
      montantOuTiret(valeur),
      textAlign: TextAlign.right,
      style: montantCompta.copyWith(
        fontWeight: gras && !nul ? FontWeight.w700 : FontWeight.w400,
        color: nul ? AppColors.outline : couleur,
      ),
    );
  }
}

/// Sélecteur « Mois en cours / Exercice complet » — `bal-periode-select`.
///
/// Il déplace la frontière entre le solde d'ouverture et les mouvements de la
/// période, pas seulement les lignes affichées. Voir
/// `ComptabiliteViewModel.balance`.
class _SelecteurPerimetre extends StatelessWidget {
  const _SelecteurPerimetre({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<bool>(
        value: vm.balanceMoisCourant,
        isDense: true,
        style: grasCompta,
        items: [
          DropdownMenuItem(
            value: true,
            child: Text('Mois en cours — ${vm.libelleMoisBalance}'),
          ),
          DropdownMenuItem(
            value: false,
            child: Text('Exercice complet — ${vm.exercice}'),
          ),
        ],
        onChanged: (v) => vm.definirPerimetreBalance(moisCourant: v ?? false),
      ),
    );
  }
}
