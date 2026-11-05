import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../administration/presentation/viewmodels/parametres_generaux_view_model.dart';
import '../../../core/tour/tour_guide.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/theme/app_breakpoints.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../viewmodels/comptabilite_view_model.dart';
import 'widgets/communs_compta.dart';

/// Hub Comptabilité — Doc F6, fidèle à `comptabilite-hub.html`.
///
/// Les 4 KPI du prototype sont écrits en dur (426 200 / 312 000 / 74 000 /
/// 52 %). Ici, ils sont calculés depuis les écritures réelles de l'exercice, et
/// tous les quatre viennent du **même** `ComptabiliteViewModel` que les états
/// financiers : le Résultat Cumulé affiché ici est le même nombre, au franc
/// près, que celui du Bilan et du Compte de Résultat (BR-CPT-005).
class ComptabiliteHubScreen extends StatelessWidget {
  const ComptabiliteHubScreen({super.key});

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
              const Icon(
                Symbols.account_balance,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text('Comptabilité', style: AppTypography.pageTitle),
              ),
              CibleTour(
                nom: 'compta-hub',
                child: SelecteurExercice(vm: vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Comptabilité complète SYSCOHADA — Plan Comptable, Journal, Grand '
            'Livre, Balance, États Financiers et Clôture d\'Exercice.',
            style: texteCompta.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _BandeauModuleActif(),
          const SizedBox(height: AppSpacing.lg),
          const _BandeauMecef(),
          const SizedBox(height: AppSpacing.lg),
          _Kpis(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          const _GrilleTuiles(),
        ],
      ),
    );
  }
}

class _BandeauModuleActif extends StatelessWidget {
  const _BandeauModuleActif();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.successContainer,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: AppColors.successDeep.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Symbols.check_circle,
            size: 20,
            color: AppColors.successDeep,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Module Actif — Comptabilité SYSCOHADA Complète',
                  style: grasCompta.copyWith(color: AppColors.successDeep),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Plan Comptable, Journal, Grand Livre, Balance Générale, '
                  'États Financiers (Bilan, Compte de Résultat, Flux de '
                  'Trésorerie, Notes Annexes), Clôture Périodique et Annuelle, '
                  'Comptabilité Analytique par filière.',
                  style: texteCompta.copyWith(
                    fontSize: 11,
                    color: AppColors.outline,
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

/// Bandeau de conformité MeCeF — vert si l'IFU **et** le RCCM sont renseignés,
/// rouge sinon (BR-ADM-004). Le prototype lit `localStorage` ; ici la source est
/// la table `PARAMETRES_ENTREPRISE` remplie par l'écran Paramètres Généraux.
class _BandeauMecef extends StatelessWidget {
  const _BandeauMecef();

  @override
  Widget build(BuildContext context) {
    final parametresVm = context.watch<ParametresGenerauxViewModel>();

    if (parametresVm.chargement) {
      return const SizedBox.shrink();
    }

    final parametres = parametresVm.parametres;
    final ifu = parametres.ifu?.trim() ?? '';
    final rccm = parametres.rccm?.trim() ?? '';
    final conforme = ifu.isNotEmpty && rccm.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: conforme
            ? AppColors.successContainer
            : AppColors.errorContainer,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(
          color: (conforme ? AppColors.successDeep : AppColors.errorDeep)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            conforme ? Symbols.verified : Symbols.block,
            size: 20,
            color: conforme ? AppColors.successDeep : AppColors.errorDeep,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conforme
                      ? 'Conformité Fiscale Électronique (MeCeF/e-MECeF) — '
                            'Activable'
                      : 'Conformité Fiscale Électronique (MeCeF/e-MECeF) — '
                            'En Attente de Configuration',
                  style: grasCompta.copyWith(
                    color: conforme
                        ? AppColors.successDeep
                        : AppColors.errorDeep,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (conforme)
                  Text(
                    'IFU ($ifu) et RCCM ($rccm) renseignés dans Paramètres '
                    'Généraux. Le mécanisme MeCeF peut désormais être activé '
                    'pour la facturation normalisée.',
                    style: texteCompta.copyWith(
                      fontSize: 11,
                      color: AppColors.outline,
                      height: 1.5,
                    ),
                  )
                else
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Renseignez l\'IFU et le RCCM depuis ',
                          style: texteCompta.copyWith(
                            fontSize: 11,
                            color: AppColors.errorDeep,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => context.go('/parametres/generaux'),
                        child: Text(
                          'Paramètres Généraux > Données de l\'Entreprise',
                          style: texteCompta.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.errorDeep,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.vm});

  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    final bilan = vm.bilan;
    final produits = vm.totalProduits;

    // Marge Nette = Résultat Net / Produits. Le prototype affiche « 52 % » en
    // dur sans dire de quoi il s'agit ; c'est la seule définition compatible
    // avec les 74 000 de Résultat Cumulé qu'il affiche juste à côté.
    final margeNette = produits.abs() < 0.01
        ? null
        : vm.resultatNet / produits * 100;

    // `lg:grid-cols-4` / `grid-cols-2` de comptabilite-hub.html l.102.
    final colonnes = AppBreakpoints.estLg(context) ? 4 : 2;

    final cartes = <Widget>[
      _CarteKpi(
        libelle: 'Total Actif (Bilan)',
        valeur: Formats.nombre(bilan.totalActif),
        unite: 'FCFA',
      ),
      _CarteKpi(
        libelle: 'Trésorerie (Journal)',
        valeur: Formats.nombre(vm.tresorerie),
        unite: 'FCFA',
      ),
      _CarteKpi(
        libelle: 'Résultat Cumulé',
        valeur: Formats.nombre(vm.resultatNet),
        unite: 'FCFA',
        couleur: vm.resultatNet < 0 ? AppColors.errorDeep : null,
      ),
      _CarteKpi(
        libelle: 'Marge Nette (Analytique)',
        valeur: margeNette == null
            ? '—'
            : margeNette.toStringAsFixed(0).replaceAll('-0', '0'),
        unite: margeNette == null ? null : '%',
      ),
    ];

    return GridView.count(
      crossAxisCount: colonnes,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 3.2,
      children: cartes,
    );
  }
}

class _CarteKpi extends StatelessWidget {
  const _CarteKpi({
    required this.libelle,
    required this.valeur,
    this.unite,
    this.couleur,
  });

  final String libelle;
  final String valeur;
  final String? unite;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
        boxShadow: AppShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(libelle.toUpperCase(), style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          RichText(
            text: TextSpan(
              style: AppTypography.kpiValue.copyWith(color: couleur),
              children: [
                TextSpan(text: valeur),
                if (unite != null)
                  TextSpan(
                    text: ' $unite',
                    style: texteCompta.copyWith(color: couleur),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GrilleTuiles extends StatelessWidget {
  const _GrilleTuiles();

  /// Les 8 tuiles de `comptabilite-hub.html` l.121-157, dans l'ordre.
  static const List<
    ({String titre, String sousTitre, IconData icone, String route, bool sombre})
  >
  tuiles = [
    (
      titre: 'Plan Comptable',
      sousTitre: 'Structure SYSCOHADA',
      icone: Symbols.list_alt,
      route: '/comptabilite/plan',
      sombre: false,
    ),
    (
      titre: 'Journal Comptable',
      sousTitre: 'Écritures chronologiques',
      icone: Symbols.menu_book,
      route: '/comptabilite/journal',
      sombre: false,
    ),
    (
      titre: 'Grand Livre',
      sousTitre: 'Écritures par compte, solde progressif',
      icone: Symbols.import_contacts,
      route: '/comptabilite/grand-livre',
      sombre: false,
    ),
    (
      titre: 'Balance Générale',
      sousTitre: 'Soldes de tous les comptes',
      icone: Symbols.balance,
      route: '/comptabilite/balance',
      sombre: false,
    ),
    (
      titre: 'États Financiers',
      sousTitre: 'Bilan, Résultat, Flux, Notes Annexes',
      icone: Symbols.description,
      route: '/comptabilite/etats-financiers',
      sombre: false,
    ),
    // Retablie a la demande de la Gerante. `comptabilite-hub.html` l.140
    // portait « CORRECTIF : remplace bilan-entreprise.html — page unifiee des
    // 4 etats » : la tuile avait ete supprimee du prototype. Voir
    // `BilanEntrepriseCalculator` pour pourquoi les deux ecrans coexistent.
    (
      titre: 'Bilan de l\'Entreprise',
      sousTitre: 'Ce que je possède, ce que je dois',
      icone: Symbols.account_balance_wallet,
      route: '/comptabilite/bilan',
      sombre: false,
    ),
    (
      titre: 'Clôture d\'Exercice',
      sousTitre: 'Périodique et annuelle, report à nouveau',
      icone: Symbols.event_repeat,
      route: '/comptabilite/cloture',
      sombre: false,
    ),
    (
      titre: 'Comptabilité Analytique',
      sousTitre: 'Marges réelles par filière',
      icone: Symbols.query_stats,
      route: '/comptabilite/analytique',
      sombre: false,
    ),
    (
      titre: 'Modules Actifs & IFU/RCCM',
      sousTitre: 'Configurer la conformité MeCeF',
      icone: Symbols.toggle_on,
      route: '/parametres/generaux',
      sombre: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // `sm:grid-cols-2 lg:grid-cols-3` de comptabilite-hub.html l.121.
    final colonnes = AppBreakpoints.estLg(context)
        ? 3
        : (AppBreakpoints.estSm(context) ? 2 : 1);

    return GridView.count(
      crossAxisCount: colonnes,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 4.2,
      children: [
        for (final tuile in tuiles)
          _Tuile(
            titre: tuile.titre,
            sousTitre: tuile.sousTitre,
            icone: tuile.icone,
            route: tuile.route,
            sombre: tuile.sombre,
          ),
      ],
    );
  }
}

class _Tuile extends StatefulWidget {
  const _Tuile({
    required this.titre,
    required this.sousTitre,
    required this.icone,
    required this.route,
    required this.sombre,
  });

  final String titre;
  final String sousTitre;
  final IconData icone;
  final String route;
  final bool sombre;

  @override
  State<_Tuile> createState() => _TuileState();
}

class _TuileState extends State<_Tuile> {
  bool _survol = false;

  @override
  Widget build(BuildContext context) {
    // `hover:border-brand-navy hover:shadow-md` du prototype.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _survol = true),
      onExit: (_) => setState(() => _survol = false),
      child: GestureDetector(
        onTap: () => context.go(widget.route),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: widget.sombre
                ? (_survol ? AppColors.brandNavyDark : AppColors.brandNavy)
                : AppColors.surfaceCard,
            border: widget.sombre
                ? null
                : Border.all(
                    color: _survol
                        ? AppColors.brandNavy
                        : AppColors.outlineVariant,
                  ),
            borderRadius: AppRadius.cardRadius,
            boxShadow: _survol ? AppShadows.md : AppShadows.sm,
          ),
          child: Row(
            children: [
              Icon(
                widget.icone,
                size: 28,
                color: widget.sombre
                    ? AppColors.brandGoldLight
                    : AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.titre,
                      style: AppTypography.sectionTitle.copyWith(
                        color: widget.sombre
                            ? Colors.white
                            : AppColors.brandNavy,
                      ),
                    ),
                    Text(
                      widget.sousTitre,
                      style: texteCompta.copyWith(
                        color: widget.sombre
                            ? Colors.white.withValues(alpha: 0.7)
                            : AppColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
