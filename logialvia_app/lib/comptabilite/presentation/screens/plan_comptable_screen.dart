import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/resultat/resultat.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import 'documents_comptables.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import '../../domain/entities/comptabilite.dart';
import '../viewmodels/comptabilite_view_model.dart';
import 'widgets/communs_compta.dart';

/// Plan Comptable — Doc F6, fidèle à `plan-comptable.html`.
///
/// ## Écart constaté entre deux écrans du prototype, corrigé ici
///
/// `saisie-depenses.html` impute les dépenses sur les comptes **613, 616, 624
/// et 628**, qui ne figurent dans aucune ligne du tableau `PLAN_COMPTABLE` de
/// `plan-comptable.html`. Côté web les deux pages ont chacune leur tableau
/// JavaScript, l'incohérence reste invisible. Ici les deux écrans lisent la
/// même table : les 4 comptes sont ajoutés au socle
/// (`PlanComptableSeeder.comptesDepensesAjoutes`), avec les libellés exacts de
/// l'écran des dépenses.
class PlanComptableScreen extends StatefulWidget {
  const PlanComptableScreen({super.key});

  @override
  State<PlanComptableScreen> createState() => _PlanComptableScreenState();
}

class _PlanComptableScreenState extends State<PlanComptableScreen> {
  String _recherche = '';
  String? _classe;
  bool _afficherArchives = false;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ComptabiliteViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    final terme = _recherche.trim().toLowerCase();
    final comptes = vm.plan.where((c) {
      if (!_afficherArchives && c.archive) return false;
      if (_classe != null && c.classe != _classe) return false;
      if (terme.isEmpty) return true;
      return c.numero.contains(terme) ||
          c.libelle.toLowerCase().contains(terme);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.list_alt,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text('Plan Comptable', style: AppTypography.pageTitle),
              ),
              BoutonExportPdf(
                construire: () =>
                    DocumentsComptables.planComptable(vm, comptes),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Nouveau Compte',
                icon: Symbols.add,
                onPressed: () => _formulaireCompte(context, vm, null),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Comptes SYSCOHADA Révisée utilisés par le moteur d\'écritures '
            'automatiques.',
            style: texteCompta.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: '${comptes.length} compte(s)',
            cibleTour: 'tableau-plan-comptable',
            icone: Symbols.account_tree,
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 240,
                  child: TextFormField(
                    initialValue: _recherche,
                    style: texteCompta,
                    decoration: decorationCompta.copyWith(
                      hintText: 'Rechercher un compte…',
                      prefixIcon: const Icon(
                        Symbols.search,
                        size: 18,
                        color: AppColors.outline,
                      ),
                    ),
                    onChanged: (v) => setState(() => _recherche = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _classe,
                    isDense: true,
                    style: texteCompta,
                    hint: const Text('Classe : Toutes', style: texteCompta),
                    items: [
                      const DropdownMenuItem<String?>(
                        child: Text('Classe : Toutes', style: texteCompta),
                      ),
                      for (final entree
                          in CompteComptable.libellesClasses.entries)
                        DropdownMenuItem<String?>(
                          value: entree.key,
                          child: Text(entree.value, style: texteCompta),
                        ),
                    ],
                    onChanged: (v) => setState(() => _classe = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _afficherArchives,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) =>
                          setState(() => _afficherArchives = v ?? false),
                    ),
                    const Text('Archivés', style: texteCompta),
                  ],
                ),
              ],
            ),
            child: comptes.isEmpty
                ? const EtatVide(message: 'Aucun compte ne correspond.')
                : Column(
                    children: [
                      const EnteteCompta(
                        colonnes: [
                          ('N° COMPTE', 2, TextAlign.left),
                          ('INTITULÉ', 6, TextAlign.left),
                          ('CLASSE', 3, TextAlign.left),
                          ('SENS', 2, TextAlign.left),
                          ('ACTIONS', 2, TextAlign.right),
                        ],
                      ),
                      for (var i = 0; i < comptes.length; i++)
                        _LigneCompte(
                          compte: comptes[i],
                          zebre: i.isOdd,
                          vm: vm,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _LigneCompte extends StatelessWidget {
  const _LigneCompte({
    required this.compte,
    required this.zebre,
    required this.vm,
  });

  final CompteComptable compte;
  final bool zebre;
  final ComptabiliteViewModel vm;

  @override
  Widget build(BuildContext context) {
    return LigneCompta(
      zebre: zebre,
      cellules: [
        (
          Text(
            compte.numero,
            style: texteCompta.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              color: compte.archive ? AppColors.outline : null,
            ),
          ),
          2,
        ),
        (
          Row(
            children: [
              Flexible(
                child: Text(
                  compte.libelle,
                  style: texteCompta.copyWith(
                    color: compte.archive ? AppColors.outline : null,
                    decoration: compte.archive
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (compte.archive) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceZebra,
                    borderRadius: AppRadius.pill,
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: Text(
                    'Archivé',
                    style: texteCompta.copyWith(
                      fontSize: 10,
                      color: AppColors.outline,
                    ),
                  ),
                ),
              ],
            ],
          ),
          6,
        ),
        (
          Text(
            CompteComptable.libellesClasses[compte.classe] ?? compte.classe,
            style: texteCompta,
          ),
          3,
        ),
        (
          Text(
            compte.estDebiteurParNature ? 'Débiteur' : 'Créditeur',
            style: texteCompta.copyWith(color: AppColors.outline),
          ),
          2,
        ),
        (
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Symbols.edit, size: 18),
                color: AppColors.infoBlue,
                tooltip: 'Modifier',
                visualDensity: VisualDensity.compact,
                onPressed: () => _formulaireCompte(context, vm, compte),
              ),
              IconButton(
                icon: Icon(
                  compte.archive ? Symbols.unarchive : Symbols.archive,
                  size: 18,
                ),
                color: compte.archive
                    ? AppColors.successDeep
                    : AppColors.errorDeep,
                tooltip: compte.archive ? 'Réactiver' : 'Archiver',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmerArchivage(context, vm, compte),
              ),
            ],
          ),
          2,
        ),
      ],
    );
  }
}

Future<void> _confirmerArchivage(
  BuildContext context,
  ComptabiliteViewModel vm,
  CompteComptable compte,
) async {
  if (compte.archive) {
    final resultat = await vm.basculerArchive(compte);
    if (!context.mounted) return;
    switch (resultat) {
      case Succes():
        showAppToast(context, 'Compte ${compte.numero} réactivé.');
      case Echec(:final message):
        showAppToast(context, message, type: ToastType.error);
    }
    return;
  }

  final confirme = await AppModal.show<bool>(
    context,
    title: 'Archiver le compte ${compte.numero} ?',
    child: Text(
      'Un compte archivé n\'est plus proposé à la saisie, mais ses écritures '
      'restent au Journal, au Grand Livre et dans la Balance : les états '
      'financiers déjà publiés ne changent pas.\n\n'
      'L\'archivage est réversible.',
      style: texteCompta.copyWith(height: 1.5),
    ),
    actions: [
      Builder(
        builder: (ctx) => AppButton(
          label: 'Annuler',
          variant: AppButtonVariant.outline,
          onPressed: () => Navigator.of(ctx).pop(false),
        ),
      ),
      Builder(
        builder: (ctx) => AppButton(
          label: 'Archiver',
          variant: AppButtonVariant.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ),
    ],
  );

  if (confirme != true || !context.mounted) return;

  final resultat = await vm.basculerArchive(compte);
  if (!context.mounted) return;
  switch (resultat) {
    case Succes():
      showAppToast(context, 'Compte ${compte.numero} archivé.');
    case Echec(:final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

/// Modale « Nouveau Compte » / « Modifier le Compte ».
///
/// En modification, le **numéro est en lecture seule** : il est la clé étrangère
/// de toutes les écritures déjà passées, le renommer les orphelinerait.
Future<void> _formulaireCompte(
  BuildContext context,
  ComptabiliteViewModel vm,
  CompteComptable? existant,
) async {
  final numeroCtrl = TextEditingController(text: existant?.numero ?? '');
  final libelleCtrl = TextEditingController(text: existant?.libelle ?? '');
  var classe = existant?.classe ?? '6';

  await AppModal.show<void>(
    context,
    title: existant == null ? 'Nouveau Compte' : 'Modifier le Compte',
    child: StatefulBuilder(
      builder: (ctx, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('N° DE COMPTE', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: numeroCtrl,
            readOnly: existant != null,
            style: grasCompta.copyWith(fontFamily: 'monospace'),
            decoration: decorationCompta.copyWith(
              hintText: 'Ex. 624',
              fillColor: existant != null
                  ? AppColors.surfaceZebra
                  : AppColors.surfaceCard,
              helperText: existant != null
                  ? 'Le numéro d\'un compte existant ne peut pas changer : il '
                        'référence toutes ses écritures.'
                  : 'Le 1ᵉʳ chiffre doit correspondre à la classe choisie.',
              helperMaxLines: 3,
              helperStyle: texteCompta.copyWith(
                fontSize: 11,
                color: AppColors.outline,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('INTITULÉ', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: libelleCtrl,
            style: texteCompta,
            decoration: decorationCompta.copyWith(
              hintText: 'Ex. Transports',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('CLASSE', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String>(
            initialValue: classe,
            isExpanded: true,
            style: texteCompta,
            decoration: decorationCompta,
            items: [
              for (final entree in CompteComptable.libellesClasses.entries)
                DropdownMenuItem(
                  value: entree.key,
                  child: Text(entree.value, style: texteCompta),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => classe = v);
            },
          ),
        ],
      ),
    ),
    actions: [
      Builder(
        builder: (ctx) => AppButton(
          label: 'Annuler',
          variant: AppButtonVariant.outline,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ),
      Builder(
        builder: (ctx) => AppButton(
          label: 'Enregistrer',
          onPressed: () async {
            final resultat = existant == null
                ? await vm.creerCompte(
                    numero: numeroCtrl.text,
                    libelle: libelleCtrl.text,
                    classe: classe,
                  )
                : await vm.modifierCompte(
                    numero: existant.numero,
                    libelle: libelleCtrl.text,
                    classe: classe,
                  );

            if (!ctx.mounted) return;
            switch (resultat) {
              case Succes():
                Navigator.of(ctx).pop();
                showAppToast(
                  ctx,
                  existant == null
                      ? 'Compte ${numeroCtrl.text.trim()} créé.'
                      : 'Compte ${existant.numero} modifié.',
                );
              case Echec(:final message):
                showAppToast(ctx, message, type: ToastType.error);
            }
          },
        ),
      ),
    ],
  );

  numeroCtrl.dispose();
  libelleCtrl.dispose();
}
