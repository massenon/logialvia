import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_breakpoints.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/carte_section.dart';
import '../../../domain/entities/compte_utilisateur.dart';
import '../../viewmodels/compte_view_model.dart';
import 'widgets/communs_compte.dart';

/// Aide & À Propos — Doc F9, fidèle à `aide-a-propos.html`.
///
/// 3 sections : les 8 modules du logiciel, la FAQ repliable avec recherche, et
/// le pied de page éditeur.
class AideAProposScreen extends StatelessWidget {
  const AideAProposScreen({super.key});

  /// Les 8 vignettes de `aide-a-propos.html`, dans l'ordre, avec la route
  /// correspondante — cliquer une vignette y conduit réellement.
  static const List<({String libelle, IconData icone, String route})> modules =
      [
        (
          libelle: 'Élevage & Couveuse',
          icone: Symbols.pets,
          route: '/elevage/dashboard',
        ),
        (
          libelle: 'Ventes & Clients',
          icone: Symbols.point_of_sale,
          route: '/ventes',
        ),
        (
          libelle: 'Achats & Fournisseurs',
          icone: Symbols.local_shipping,
          route: '/achats',
        ),
        (
          libelle: 'Stocks & Catalogue',
          icone: Symbols.inventory_2,
          route: '/stocks',
        ),
        (
          libelle: 'Santé Animale',
          icone: Symbols.vaccines,
          route: '/elevage/soins',
        ),
        (
          libelle: 'Clients & Relances',
          icone: Symbols.campaign,
          route: '/clients',
        ),
        (
          libelle: 'Comptabilité',
          icone: Symbols.account_balance,
          route: '/comptabilite',
        ),
        (
          libelle: 'Rapports & États',
          icone: Symbols.picture_as_pdf,
          route: '/rapports',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CompteViewModel>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          EnteteCompte(
            icone: Symbols.help,
            titre: 'Aide & À Propos',
            sousTitre:
                'LogiALVIA ${CompteViewModel.version} — '
                '${Editeur.descriptionApplication.split(' — ').last}.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('MODULES DU LOGICIEL', style: AppTypography.label),
          const SizedBox(height: AppSpacing.sm),
          const _GrilleModules(),
          const SizedBox(height: AppSpacing.lg),
          const Text('FOIRE AUX QUESTIONS', style: AppTypography.label),
          const SizedBox(height: AppSpacing.sm),
          _Faq(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          const _PiedEditeur(),
        ],
      ),
    );
  }
}

class _GrilleModules extends StatelessWidget {
  const _GrilleModules();

  @override
  Widget build(BuildContext context) {
    // `grid-cols-2 md:grid-cols-4` du prototype.
    final colonnes = AppBreakpoints.estMd(context) ? 4 : 2;

    return GridView.count(
      crossAxisCount: colonnes,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 2.6,
      children: [
        for (final module in AideAProposScreen.modules)
          _VignetteModule(
            libelle: module.libelle,
            icone: module.icone,
            route: module.route,
          ),
      ],
    );
  }
}

class _VignetteModule extends StatelessWidget {
  const _VignetteModule({
    required this.libelle,
    required this.icone,
    required this.route,
  });

  final String libelle;
  final IconData icone;
  final String route;

  @override
  Widget build(BuildContext context) {
    // La vignette conduit reellement au module. Le prototype se contente d'une
    // carte inerte ; un lien mort serait pire, mais une carte cliquable qui ne
    // fait rien le serait tout autant (Master Prompt §2.3).
    return InkWell(
      onTap: () => context.go(route),
      borderRadius: AppRadius.cardRadius,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          border: Border.all(color: AppColors.outlineVariant),
          borderRadius: AppRadius.cardRadius,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, size: 28, color: AppColors.brandNavy),
            const SizedBox(height: AppSpacing.xs),
            Text(libelle, textAlign: TextAlign.center, style: grasCompte),
          ],
        ),
      ),
    );
  }
}

class _Faq extends StatefulWidget {
  const _Faq({required this.vm});

  final CompteViewModel vm;

  @override
  State<_Faq> createState() => _FaqState();
}

class _FaqState extends State<_Faq> {
  final Set<int> _ouvertes = {};

  @override
  Widget build(BuildContext context) {
    final questions = widget.vm.faqFiltree;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: widget.vm.rechercheFaq,
          style: texteCompte,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.surfaceCard,
            hintText: 'Rechercher dans l\'aide (ex : vente, stock, module...)',
            hintStyle: texteCompte.copyWith(color: AppColors.outline),
            prefixIcon: const Icon(
              Symbols.search,
              size: 18,
              color: AppColors.outline,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            border: OutlineInputBorder(
              borderRadius: AppRadius.cardRadius,
              borderSide: const BorderSide(color: AppColors.outlineVariant),
            ),
          ),
          onChanged: widget.vm.definirRechercheFaq,
        ),
        const SizedBox(height: AppSpacing.md),
        if (questions.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              border: Border.all(color: AppColors.outlineVariant),
              borderRadius: AppRadius.cardRadius,
            ),
            child: Center(
              child: Text(
                'Aucun résultat pour cette recherche.',
                style: texteCompte.copyWith(color: AppColors.outline),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              border: Border.all(color: AppColors.outlineVariant),
              borderRadius: AppRadius.cardRadius,
            ),
            child: Column(
              children: [
                for (var i = 0; i < questions.length; i++)
                  _ItemFaq(
                    question: questions[i],
                    ouverte: _ouvertes.contains(i),
                    derniere: i == questions.length - 1,
                    onTap: () => setState(() {
                      if (!_ouvertes.remove(i)) _ouvertes.add(i);
                    }),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ItemFaq extends StatelessWidget {
  const _ItemFaq({
    required this.question,
    required this.ouverte,
    required this.derniere,
    required this.onTap,
  });

  final QuestionAide question;
  final bool ouverte;
  final bool derniere;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        border: derniere
            ? null
            : const Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      question.question,
                      style: AppTypography.sectionTitle,
                    ),
                  ),
                  AnimatedRotation(
                    turns: ouverte ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(
                      Symbols.expand_more,
                      size: 20,
                      color: AppColors.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (ouverte)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                question.reponse,
                style: texteCompte.copyWith(
                  color: AppColors.outline,
                  height: 1.6,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PiedEditeur extends StatelessWidget {
  const _PiedEditeur();

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      cibleTour: 'aide-sommaire',
      titre: 'À propos',
      icone: Symbols.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Text(
              Editeur.descriptionApplication,
              textAlign: TextAlign.center,
              style: texteCompte.copyWith(color: AppColors.outline),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              Editeur.mentionProjet,
              textAlign: TextAlign.center,
              style: texteCompte.copyWith(
                fontSize: 11,
                color: AppColors.outline,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              'Version ${CompteViewModel.version}',
              style: grasCompte.copyWith(color: AppColors.brandNavy),
            ),
          ),
        ],
      ),
    );
  }
}
