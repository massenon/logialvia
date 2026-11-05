import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/formatage/formats.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/tour/tour_guide.dart';
import '../../domain/services/bilan_entreprise.dart';
import '../viewmodels/comptabilite_view_model.dart';
import 'documents_comptables.dart';
import 'widgets/communs_compta.dart';

/// Bilan de l'Entreprise — porté de `prototype_html/bilan-entreprise.html`.
///
/// Deux colonnes, ACTIF et PASSIF, sept lignes en tout. C'est le bilan que la
/// Gérante lit ; l'onglet « Bilan » des États Financiers est celui que le
/// comptable dépose. Voir `BilanEntrepriseCalculator` pour la raison d'être des
/// deux écrans et pour l'écart de traitement du Capital Initial.
class BilanEntrepriseScreen extends StatelessWidget {
  const BilanEntrepriseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ComptabiliteViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    final bilan = vm.bilanEntreprise;
    // `lg:grid-cols-2` (bilan-entreprise.html l.19) — MediaQuery, jamais les
    // contraintes locales (Doc K3 §4).
    final deuxColonnes = AppBreakpoints.estLg(context);

    final actif = _CarteBilan(
      titre: 'ACTIF',
      postes: bilan.actif,
      libelleTotal: 'TOTAL ACTIF',
      total: bilan.totalActif,
    );
    final passif = _CarteBilan(
      titre: 'PASSIF',
      postes: bilan.passif,
      libelleTotal: 'TOTAL PASSIF',
      total: bilan.totalPassif,
      // L'écart n'est pas ajouté au total : il montre ce qui manque au passif,
      // il ne le complète pas. Le total reste celui des écritures réelles.
      ecartNonEnregistre: bilan.estEquilibre || bilan.estVide
          ? null
          : bilan.ecart,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.account_balance_wallet,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Bilan de l\'Entreprise',
                  style: AppTypography.pageTitle,
                ),
              ),
              SelecteurExercice(vm: vm),
              const SizedBox(width: AppSpacing.md),
              BoutonExportPdf(
                construire: () => DocumentsComptables.bilanEntreprise(vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Exercice ${vm.exercice} — au ${Formats.date(DateTime.now())}. '
            'Ce que possède l\'entreprise à gauche, d\'où provient cet argent '
            'à droite.',
            style: texteCompta.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.lg),
          CibleTour(
            nom: 'bandeau-equilibre',
            child: _BandeauEquilibreBilan(bilan: bilan),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (deuxColonnes)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: actif),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: passif),
                ],
              ),
            )
          else ...[
            actif,
            const SizedBox(height: AppSpacing.md),
            passif,
          ],
        ],
      ),
    );
  }
}

/// Le bandeau `#equilibre-banner` du prototype.
///
/// Chez lui il est vert par construction — le Capital Initial est calculé pour
/// que l'égalité tombe juste. Ici il rend un verdict : il peut être rouge, et
/// dans ce cas il dit quoi faire.
class _BandeauEquilibreBilan extends StatelessWidget {
  const _BandeauEquilibreBilan({required this.bilan});

  final BilanEntreprise bilan;

  @override
  Widget build(BuildContext context) {
    final (fond, bordure, teinte, icone, message) = switch (bilan) {
      final b when b.estVide => (
        AppColors.surfaceZebra,
        AppColors.outlineVariant,
        AppColors.outline,
        Symbols.info,
        'Aucune écriture sur l\'exercice ${_exercice(context)} : il n\'y a '
            'encore ni bien à inscrire à l\'actif, ni dette au passif.',
      ),
      final b when b.estEquilibre => (
        AppColors.successContainer,
        AppColors.successDeep.withValues(alpha: 0.3),
        AppColors.successDeep,
        Symbols.check_circle,
        'Bilan équilibré — Total Actif = Total Passif = '
            '${Formats.montant(b.totalActif)}.',
      ),
      final b => (
        AppColors.errorContainer,
        AppColors.errorDeep.withValues(alpha: 0.3),
        AppColors.errorDeep,
        Symbols.warning,
        'Écart de ${Formats.montant(b.ecart.abs())} entre l\'actif et le '
            'passif. ${_diagnostic(b)}',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: bordure),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 22, color: teinte),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: texteCompta.copyWith(
                fontWeight: FontWeight.w700,
                color: teinte,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _exercice(BuildContext context) =>
      '${context.read<ComptabiliteViewModel>().exercice}';

  /// Un déséquilibre a deux causes possibles, et elles n'appellent pas la même
  /// correction. Les distinguer évite d'envoyer la Gérante chercher une erreur
  /// de saisie là où il ne manque qu'un apport initial.
  static String _diagnostic(BilanEntreprise b) {
    if (b.ecart > 0) {
      return 'L\'entreprise détient des biens dont l\'origine n\'a pas été '
          'enregistrée — le plus souvent l\'apport de départ. Saisissez-le au '
          'compte 101 (Capital) depuis le Journal Comptable.';
    }
    return 'Le passif dépasse l\'actif : une ressource est enregistrée sans '
        'l\'emploi correspondant. Vérifiez le Journal Comptable — une écriture '
        'de contrepartie manque probablement.';
  }
}

/// Une des deux cartes. Bandeau navy, lignes zébrées, pied doré — reprise de
/// `bilan-entreprise.html` l.20-44.
class _CarteBilan extends StatelessWidget {
  const _CarteBilan({
    required this.titre,
    required this.postes,
    required this.libelleTotal,
    required this.total,
    this.ecartNonEnregistre,
  });

  final String titre;
  final List<PosteBilanEntreprise> postes;
  final String libelleTotal;
  final double total;
  final double? ecartNonEnregistre;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.brandNavy,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Text(
              titre,
              style: texteCompta.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          for (var i = 0; i < postes.length; i++)
            _LignePoste(poste: postes[i], impaire: i.isOdd),
          if (ecartNonEnregistre != null)
            _LigneEcart(montant: ecartNonEnregistre!),
          Container(
            decoration: BoxDecoration(
              color: AppColors.brandGold.withValues(alpha: 0.1),
              border: const Border(
                top: BorderSide(color: AppColors.brandNavy, width: 2),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(child: Text(libelleTotal, style: grasCompta)),
                Text(
                  '${Formats.nombre(total)} FCFA',
                  style: montantCompta.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LignePoste extends StatelessWidget {
  const _LignePoste({required this.poste, required this.impaire});

  final PosteBilanEntreprise poste;
  final bool impaire;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: impaire ? AppColors.surfaceZebra : AppColors.surfaceCard,
        border: const Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: poste.libelle),
                  TextSpan(
                    text: '  (${poste.compte})',
                    style: texteCompta.copyWith(
                      color: AppColors.outline,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              style: texteCompta,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            // Un poste à zéro s'affiche « — » : un 0 se confond visuellement
            // avec un montant, un tiret dit qu'il n'y a rien.
            poste.montant.abs() < 0.01 ? '—' : Formats.nombre(poste.montant),
            style: poste.montant.abs() < 0.01
                ? montantCompta.copyWith(color: AppColors.outline)
                : montantCompta.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// La ligne que le prototype n'a pas, parce qu'il déduisait le capital.
class _LigneEcart extends StatelessWidget {
  const _LigneEcart({required this.montant});

  final double montant;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.errorContainer,
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          const Icon(Symbols.warning, size: 16, color: AppColors.errorDeep),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Origine non enregistrée — à saisir au compte 101',
              style: texteCompta.copyWith(
                color: AppColors.errorDeep,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            Formats.nombre(montant),
            style: montantCompta.copyWith(
              color: AppColors.errorDeep,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
