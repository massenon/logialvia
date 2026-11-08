import '../../../core/widgets/auteur_courant.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../approvisionnement/data/repositories/approvisionnement_repository_drift.dart';
import '../../../approvisionnement/domain/entities/approvisionnement.dart';
import '../../../approvisionnement/presentation/viewmodels/approvisionnement_view_model.dart';
import '../../../core/database/app_database.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import 'documents_elevage.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import '../../data/repositories/parametres_elevage_repository_drift.dart';
import '../../domain/entities/configuration_espece.dart';
import '../../domain/entities/parametres_elevage.dart';
import '../viewmodels/parametres_elevage_view_model.dart';
import '../../../core/saisie/formats_saisie.dart';

const TextStyle _texte = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

final TextStyle _gras = _texte.copyWith(fontWeight: FontWeight.w700);

final TextStyle _mono = _texte.copyWith(
  fontFamily: 'monospace',
  fontWeight: FontWeight.w700,
);

final InputDecoration _decoration = InputDecoration(
  isDense: true,
  filled: true,
  fillColor: AppColors.surfaceCard,
  hintStyle: _texte.copyWith(color: AppColors.outline),
  contentPadding: const EdgeInsets.symmetric(
    horizontal: AppSpacing.md,
    vertical: AppSpacing.sm,
  ),
  border: OutlineInputBorder(
    borderRadius: AppRadius.cardRadius,
    borderSide: const BorderSide(color: AppColors.outlineVariant),
  ),
);

/// Page Paramètres Élevage — fournit le ViewModel partagé par les 4 onglets.
class PageParametresElevage extends StatelessWidget {
  const PageParametresElevage({super.key});

  @override
  Widget build(BuildContext context) {
    // L'onglet « Intrants de Provende » administre la table `INTRANTS`, qui
    // appartient au module Approvisionnement. On reutilise son ViewModel plutot
    // que d'ecrire une seconde logique de validation et de suppression : celle
    // de F5 connait deja les cles etrangeres qui interdisent d'effacer un
    // intrant deja mouvemente.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ParametresElevageViewModel>(
          create: (context) => ParametresElevageViewModel(
            ParametresElevageRepositoryDrift(context.read<AppDatabase>()),
          )..charger(),
        ),
        ChangeNotifierProvider<ApprovisionnementViewModel>(
          create: (context) => ApprovisionnementViewModel(
            ApprovisionnementRepositoryDrift(context.read<AppDatabase>()),
          )..charger(),
        ),
      ],
      child: const ParametresElevageScreen(),
    );
  }
}

/// Paramètres Élevage — Doc F3, fidèle à `parametres-elevage.html`.
///
/// « Configuration des barèmes utilisés automatiquement dans les fiches de
/// saisie journalière. » Cette phrase du prototype est tenue au sens propre :
/// modifier une ration ici change réellement la provende calculée sur la fiche
/// de l'espèce concernée (voir `CalculFicheJournaliere.rationsConfigurees`).
class ParametresElevageScreen extends StatefulWidget {
  const ParametresElevageScreen({super.key});

  @override
  State<ParametresElevageScreen> createState() =>
      _ParametresElevageScreenState();
}

class _ParametresElevageScreenState extends State<ParametresElevageScreen> {
  int _onglet = 0;

  static const List<({String titre, IconData icone})> _onglets = [
    (titre: 'Rationnement', icone: Symbols.restaurant),
    (titre: 'Calendriers Prophylaxie', icone: Symbols.vaccines),
    (titre: 'Intrants de Provende', icone: Symbols.inventory_2),
    (titre: 'Numérotation Bandes & Sujets', icone: Symbols.tag),
  ];

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ParametresElevageViewModel>();

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
              const Icon(Symbols.tune, size: 24, color: AppColors.brandNavy),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Paramètres Élevage',
                  style: AppTypography.pageTitle,
                ),
              ),
              // Exporte l'onglet affiche, comme le fait `exportPeTab()`.
              BoutonExportPdf(
                construire: () =>
                    DocumentsElevage.parametres(_onglet, vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Configuration des barèmes utilisés automatiquement dans les '
            'fiches de saisie journalière.',
            style: _texte.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.outlineVariant),
              ),
            ),
            // `overflow-x-auto` du prototype : la barre defile plutot que de
            // deborder. Sans lui, un libelle un peu long fait lever
            // `RenderFlex overflowed` a chaque affichage de l'ecran.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _onglets.length; i++)
                    InkWell(
                      onTap: () => setState(() => _onglet = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              width: 2,
                              color: i == _onglet
                                  ? AppColors.brandNavy
                                  : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _onglets[i].icone,
                              size: 16,
                              color: i == _onglet
                                  ? AppColors.brandNavy
                                  : AppColors.outline,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              _onglets[i].titre,
                              style: _gras.copyWith(
                                color: i == _onglet
                                    ? AppColors.brandNavy
                                    : AppColors.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          switch (_onglet) {
            0 => _OngletRationnement(vm: vm),
            1 => _OngletProphylaxie(vm: vm),
            2 => _OngletProvende(vm: vm),
            _ => _OngletNumerotation(vm: vm),
          },
        ],
      ),
    );
  }
}

// =========================================================== Onglet 1

class _OngletRationnement extends StatelessWidget {
  const _OngletRationnement({required this.vm});

  final ParametresElevageViewModel vm;

  /// Libellés de catégories réellement utilisés par les fiches journalières.
  /// Un stade qui n'y figure pas ne pilote aucun calcul — l'écran le dit.
  static Set<String> _categoriesDe(String espece) {
    final config = ConfigurationsEspeces.parIdentifiant[espece];
    if (config == null) return const {};
    return config.categories.map((c) => c.libelle).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final baremes = vm.baremesFiltres;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Ration normative en grammes/tête/jour — utilisée pour le '
                'calcul automatique dans les fiches journalières.',
                style: _texte.copyWith(color: AppColors.outline),
              ),
            ),
            AppButton(
              label: 'Ajouter',
              icon: Symbols.add_circle,
              onPressed: () => _formulaireAjoutRation(context, vm),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: '${baremes.length} barème(s)',
          cibleTour: 'tableau-rationnement',
          icone: Symbols.restaurant,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 260,
                child: TextFormField(
                  key: ValueKey('ration-${vm.rechercheRation.isEmpty}'),
                  initialValue: vm.rechercheRation,
                  style: _texte,
                  decoration: _decoration.copyWith(
                    hintText: 'Rechercher un stade physiologique…',
                    prefixIcon: const Icon(
                      Symbols.search,
                      size: 18,
                      color: AppColors.outline,
                    ),
                  ),
                  onChanged: vm.definirRechercheRation,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: vm.especeRation,
                  isDense: true,
                  style: _texte,
                  hint: const Text('Toutes espèces', style: _texte),
                  items: [
                    const DropdownMenuItem<String?>(
                      child: Text('Toutes espèces', style: _texte),
                    ),
                    for (final e in EspecesParametrables.toutes)
                      DropdownMenuItem<String?>(
                        value: e.id,
                        child: Text(e.libelle, style: _texte),
                      ),
                  ],
                  onChanged: vm.definirEspeceRation,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Réinitialiser',
                icon: Symbols.filter_alt_off,
                variant: AppButtonVariant.outline,
                height: 34,
                onPressed: vm.reinitialiserFiltresRation,
              ),
            ],
          ),
          child: baremes.isEmpty
              ? const EtatVide(
                  message: 'Aucun barème ne correspond à ces filtres.',
                )
              : Column(
                  children: [
                    const _Entete(
                      colonnes: [
                        ('ESPÈCE', 2, TextAlign.left),
                        ('STADE PHYSIOLOGIQUE', 4, TextAlign.left),
                        ('RATION (G/TÊTE/J)', 2, TextAlign.right),
                        ('CONFIRMÉ ?', 4, TextAlign.left),
                        ('ACTIONS', 2, TextAlign.right),
                      ],
                    ),
                    for (var i = 0; i < baremes.length; i++)
                      _LigneRation(
                        bareme: baremes[i],
                        zebre: i.isOdd,
                        vm: vm,
                        pilotUnCalcul: _categoriesDe(
                          baremes[i].espece,
                        ).contains(baremes[i].stade),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _LigneRation extends StatelessWidget {
  const _LigneRation({
    required this.bareme,
    required this.zebre,
    required this.vm,
    required this.pilotUnCalcul,
  });

  final BaremeRation bareme;
  final bool zebre;
  final ParametresElevageViewModel vm;
  final bool pilotUnCalcul;

  @override
  Widget build(BuildContext context) {
    return _Ligne(
      zebre: zebre,
      cellules: [
        (
          Text(
            EspecesParametrables.libelle(bareme.espece),
            style: _gras.copyWith(color: AppColors.brandNavy),
          ),
          2,
        ),
        (
          Row(
            children: [
              Flexible(
                child: Text(
                  bareme.stade,
                  style: _texte,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!pilotUnCalcul) ...[
                const SizedBox(width: AppSpacing.xs),
                Tooltip(
                  message:
                      'Ce stade ne correspond à aucune catégorie de la fiche '
                      '${EspecesParametrables.libelle(bareme.espece)} : il est '
                      'documentaire et ne pilote aucun calcul de provende.',
                  child: const Icon(
                    Symbols.info,
                    size: 14,
                    color: AppColors.outline,
                  ),
                ),
              ],
            ],
          ),
          4,
        ),
        (
          Text(
            '${bareme.rationGrammesParJour} g/j',
            textAlign: TextAlign.right,
            style: _mono,
          ),
          2,
        ),
        (
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: bareme.confirme
                    ? AppColors.successContainer
                    : AppColors.brandGold.withValues(alpha: 0.2),
                borderRadius: AppRadius.pill,
              ),
              child: Text(
                bareme.badge,
                style: _texte.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: bareme.confirme
                      ? AppColors.successDeep
                      : AppColors.brandNavy,
                ),
              ),
            ),
          ),
          4,
        ),
        (
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(Symbols.edit, size: 18),
                color: AppColors.brandNavy,
                tooltip: 'Modifier la ration',
                visualDensity: VisualDensity.compact,
                onPressed: () => _formulaireEditionRation(context, vm, bareme),
              ),
              IconButton(
                icon: const Icon(Symbols.delete, size: 18),
                color: AppColors.outline,
                tooltip: 'Supprimer le barème',
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmerSuppressionBareme(context, vm, bareme),
              ),
            ],
          ),
          2,
        ),
      ],
    );
  }
}

Future<void> _formulaireAjoutRation(
  BuildContext context,
  ParametresElevageViewModel vm,
) async {
  final stadeCtrl = TextEditingController();
  final rationCtrl = TextEditingController();
  var espece = EspecesParametrables.toutes.first.id;

  await AppModal.show<void>(
    context,
    title: 'Ajouter une Ration',
    child: StatefulBuilder(
      builder: (ctx, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('ESPÈCE', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String>(
            initialValue: espece,
            isExpanded: true,
            style: _texte,
            decoration: _decoration,
            items: [
              for (final e in EspecesParametrables.toutes)
                DropdownMenuItem(
                  value: e.id,
                  child: Text(e.libelle, style: _texte),
                ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => espece = v);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('STADE PHYSIOLOGIQUE', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: stadeCtrl,
            style: _texte,
            decoration: _decoration.copyWith(hintText: 'Ex. Adulte'),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('RATION (G/TÊTE/J)', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: rationCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: FormatteursSaisie.entierPositif,
            style: _gras,
            decoration: _decoration,
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceZebra,
              borderRadius: AppRadius.cardRadius,
            ),
            child: Text(
              'Pour que ce barème pilote réellement le calcul de provende, le '
              'stade doit porter le libellé exact d\'une catégorie de la fiche '
              'de l\'espèce (par exemple « Poussins », « Goliathau », '
              '« Mature »). Un autre libellé reste documentaire.',
              style: _texte.copyWith(
                fontSize: 11,
                color: AppColors.outline,
                height: 1.5,
              ),
            ),
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
          label: 'Ajouter',
          onPressed: () async {
            final resultat = await vm.ajouterBareme(
              espece: espece,
              stade: stadeCtrl.text,
              ration: rationCtrl.text,
            );
            if (!ctx.mounted) return;
            switch (resultat) {
              case Succes():
                Navigator.of(ctx).pop();
                showAppToast(
                  ctx,
                  'Ration ajoutée pour '
                  '${EspecesParametrables.libelle(espece)} / '
                  '${stadeCtrl.text.trim()}.',
                );
              case Echec(:final message):
                showAppToast(ctx, message, type: ToastType.error);
            }
          },
        ),
      ),
    ],
  );

  stadeCtrl.dispose();
  rationCtrl.dispose();
}

Future<void> _formulaireEditionRation(
  BuildContext context,
  ParametresElevageViewModel vm,
  BaremeRation bareme,
) async {
  final rationCtrl = TextEditingController(
    text: '${bareme.rationGrammesParJour}',
  );

  await AppModal.show<void>(
    context,
    title:
        'Modifier — ${EspecesParametrables.libelle(bareme.espece)} / '
        '${bareme.stade}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('NOUVELLE RATION (G/TÊTE/J)', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: rationCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: FormatteursSaisie.entierPositif,
          style: _gras,
          decoration: _decoration,
          autofocus: true,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'La provende calculée sur la fiche '
          '${EspecesParametrables.libelle(bareme.espece)} sera recalculée avec '
          'cette valeur dès le prochain affichage.',
          style: _texte.copyWith(color: AppColors.outline, height: 1.5),
        ),
      ],
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
            final resultat = await vm.modifierRation(
              bareme: bareme,
              ration: rationCtrl.text,
            );
            if (!ctx.mounted) return;
            switch (resultat) {
              case Succes():
                Navigator.of(ctx).pop();
                showAppToast(
                  ctx,
                  'Ration mise à jour : ${rationCtrl.text.trim()} g/j.',
                );
              case Echec(:final message):
                showAppToast(ctx, message, type: ToastType.error);
            }
          },
        ),
      ),
    ],
  );

  rationCtrl.dispose();
}

Future<void> _confirmerSuppressionBareme(
  BuildContext context,
  ParametresElevageViewModel vm,
  BaremeRation bareme,
) async {
  final confirme = await AppModal.show<bool>(
    context,
    title: 'Confirmer la Suppression ?',
    child: Text(
      'Le barème « ${bareme.stade} » de '
      '${EspecesParametrables.libelle(bareme.espece)} sera supprimé.\n\n'
      'La fiche journalière retombera alors sur la ration de référence de '
      'l\'espèce pour cette catégorie — le calcul de provende ne devient pas '
      'nul, il revient à sa valeur d\'origine.',
      style: _texte.copyWith(height: 1.5),
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
          label: 'Supprimer',
          variant: AppButtonVariant.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ),
    ],
  );

  if (confirme != true || !context.mounted) return;
  final resultat = await vm.supprimerBareme(
    bareme,
    auteur: auteurCourant(context),
  );
  if (!context.mounted) return;
  switch (resultat) {
    case Succes():
      showAppToast(context, 'Barème supprimé.', type: ToastType.warning);
    case Echec(:final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

// =========================================================== Onglet 2

class _OngletProphylaxie extends StatelessWidget {
  const _OngletProphylaxie({required this.vm});

  final ParametresElevageViewModel vm;

  @override
  Widget build(BuildContext context) {
    final echeances = vm.echeancesFiltrees;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Calendrier daté depuis la mise en bande, puis affiché dans '
                '« Traitements & Prophylaxie » des fiches journalières.',
                style: _texte.copyWith(color: AppColors.outline),
              ),
            ),
            AppButton(
              label: 'Ajouter une Échéance',
              icon: Symbols.add_circle,
              onPressed: () => _formulaireEcheance(context, vm, null),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            border: Border.all(color: AppColors.outlineVariant),
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: [
              for (final e in EspecesParametrables.toutes) ...[
                _PastilleEspece(
                  libelle: '${e.emoji} ${e.libelle}',
                  active: vm.especeProphylaxie == e.id,
                  onTap: () => vm.changerEspeceProphylaxie(e.id),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              const Spacer(),
              SizedBox(
                width: 280,
                child: TextFormField(
                  initialValue: vm.rechercheProphylaxie,
                  style: _texte,
                  decoration: _decoration.copyWith(
                    hintText: 'Rechercher un traitement, un produit…',
                    prefixIcon: const Icon(
                      Symbols.search,
                      size: 16,
                      color: AppColors.outline,
                    ),
                  ),
                  onChanged: vm.definirRechercheProphylaxie,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre:
              'Calendrier — ${EspecesParametrables.libelle(vm.especeProphylaxie)}',
          icone: Symbols.vaccines,
          child: echeances.isEmpty
              ? const EtatVide(
                  message: 'Aucune échéance ne correspond à ces filtres.',
                )
              : Column(
                  children: [
                    const _Entete(
                      colonnes: [
                        ('JOUR DU CYCLE', 2, TextAlign.center),
                        ('TRAITEMENT', 4, TextAlign.left),
                        ('PRODUIT', 3, TextAlign.left),
                        ('DOSE', 4, TextAlign.left),
                        ('RÉMANENCE', 2, TextAlign.center),
                        ('ACTIONS', 2, TextAlign.right),
                      ],
                    ),
                    for (var i = 0; i < echeances.length; i++)
                      _Ligne(
                        zebre: i.isOdd,
                        cellules: [
                          (
                            Text(
                              echeances[i].libelleJour,
                              textAlign: TextAlign.center,
                              style: _mono.copyWith(
                                color: AppColors.brandNavy,
                              ),
                            ),
                            2,
                          ),
                          (
                            Text(
                              echeances[i].traitement,
                              style: _gras,
                              overflow: TextOverflow.ellipsis,
                            ),
                            4,
                          ),
                          (
                            Text(
                              echeances[i].produit,
                              style: _texte,
                              overflow: TextOverflow.ellipsis,
                            ),
                            3,
                          ),
                          (
                            Tooltip(
                              message: echeances[i].dose ?? 'Dose non renseignée',
                              child: Text(
                                echeances[i].dose ?? '—',
                                maxLines: 2,
                                style: echeances[i].dose == null
                                    ? _texte.copyWith(color: AppColors.outline)
                                    : _texte,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            4,
                          ),
                          (
                            Text(
                              echeances[i].remanenceJours > 0
                                  ? '${echeances[i].remanenceJours}j'
                                  : '—',
                              textAlign: TextAlign.center,
                              style: echeances[i].remanenceJours > 0
                                  ? _gras.copyWith(color: AppColors.errorDeep)
                                  : _texte.copyWith(color: AppColors.outline),
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
                                  tooltip: 'Éditer',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _formulaireEcheance(
                                    context,
                                    vm,
                                    echeances[i],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Symbols.delete, size: 18),
                                  color: AppColors.errorDeep,
                                  tooltip: 'Supprimer',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _confirmerSuppressionEcheance(
                                    context,
                                    vm,
                                    echeances[i],
                                  ),
                                ),
                              ],
                            ),
                            2,
                          ),
                        ],
                      ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
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
                child: Text(
                  'Ce calendrier est le référentiel des soins à programmer. '
                  'Ses échéances sont indexées sur le jour du cycle : elles se datent '
                  'depuis la mise en bande, déclarée sur chaque fiche d\'élevage. La '
                  'section « Traitements & Prophylaxie » de la saisie journalière affiche '
                  'alors les échéances du jour, et chacune peut être planifiée dans le '
                  'Calendrier de Soins. Sans bande déclarée, aucune échéance n\'est '
                  'datable — la fiche le signale au lieu de supposer un début de cycle.',
                  style: _texte.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PastilleEspece extends StatelessWidget {
  const _PastilleEspece({
    required this.libelle,
    required this.active,
    required this.onTap,
  });

  final String libelle;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.pill,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: active ? AppColors.brandNavy : null,
          borderRadius: AppRadius.pill,
          border: Border.all(
            color: active ? AppColors.brandNavy : AppColors.outlineVariant,
          ),
        ),
        child: Text(
          libelle,
          style: _gras.copyWith(
            color: active ? Colors.white : AppColors.outline,
          ),
        ),
      ),
    );
  }
}

Future<void> _formulaireEcheance(
  BuildContext context,
  ParametresElevageViewModel vm,
  EcheanceProphylaxie? existante,
) async {
  final jourCtrl = TextEditingController(
    text: existante == null ? '' : '${existante.jourCycle}',
  );
  final traitementCtrl = TextEditingController(
    text: existante?.traitement ?? '',
  );
  final produitCtrl = TextEditingController(text: existante?.produit ?? '');
  final doseCtrl = TextEditingController(text: existante?.dose ?? '');
  final remanenceCtrl = TextEditingController(
    text: '${existante?.remanenceJours ?? 0}',
  );

  await AppModal.show<void>(
    context,
    title: existante == null
        ? 'Ajouter une Échéance de Prophylaxie'
        : 'Éditer l\'Échéance de Prophylaxie',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Espèce : ${EspecesParametrables.libelle(existante?.espece ?? vm.especeProphylaxie)}',
          style: _gras.copyWith(color: AppColors.brandNavy),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('JOUR DU CYCLE *', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: jourCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: FormatteursSaisie.entierPositif,
          style: _texte,
          decoration: _decoration.copyWith(hintText: 'Ex. 5'),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('TRAITEMENT *', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: traitementCtrl,
          style: _texte,
          decoration: _decoration.copyWith(hintText: 'Ex. Anti-coccidien'),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('PRODUIT *', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: produitCtrl,
          style: _texte,
          decoration: _decoration.copyWith(hintText: 'Ex. Amprolium'),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('DOSE', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: doseCtrl,
          maxLines: 2,
          style: _texte,
          decoration: _decoration.copyWith(
            hintText: 'Ex. 1 mL pour 50 kg, voie sous-cutanée (la notice prévaut)',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'RÉMANENCE (JOURS)',
          style: AppTypography.label.copyWith(color: AppColors.errorDeep),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: remanenceCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: FormatteursSaisie.entierPositif,
          style: _texte,
          decoration: _decoration,
        ),
      ],
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
            final resultat = await vm.enregistrerEcheance(
              existante: existante,
              jour: jourCtrl.text,
              traitement: traitementCtrl.text,
              produit: produitCtrl.text,
              remanence: remanenceCtrl.text,
              dose: doseCtrl.text,
            );
            if (!ctx.mounted) return;
            switch (resultat) {
              case Succes():
                Navigator.of(ctx).pop();
                showAppToast(
                  ctx,
                  existante == null
                      ? 'Échéance ajoutée au calendrier de prophylaxie.'
                      : 'Échéance de prophylaxie modifiée.',
                );
              case Echec(:final message):
                showAppToast(ctx, message, type: ToastType.error);
            }
          },
        ),
      ),
    ],
  );

  jourCtrl.dispose();
  traitementCtrl.dispose();
  produitCtrl.dispose();
  doseCtrl.dispose();
  remanenceCtrl.dispose();
}

Future<void> _confirmerSuppressionEcheance(
  BuildContext context,
  ParametresElevageViewModel vm,
  EcheanceProphylaxie echeance,
) async {
  final confirme = await AppModal.show<bool>(
    context,
    title: 'Confirmer la Suppression ?',
    child: Text(
      'L\'échéance « ${echeance.traitement} » (${echeance.libelleJour}) sera '
      'retirée du calendrier de '
      '${EspecesParametrables.libelle(echeance.espece)}.',
      style: _texte.copyWith(height: 1.5),
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
          label: 'Supprimer',
          variant: AppButtonVariant.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ),
    ],
  );

  if (confirme != true || !context.mounted) return;
  final resultat = await vm.supprimerEcheance(
    echeance,
    auteur: auteurCourant(context),
  );
  if (!context.mounted) return;
  switch (resultat) {
    case Succes():
      showAppToast(
        context,
        'Échéance de prophylaxie supprimée.',
        type: ToastType.warning,
      );
    case Echec(:final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

// =========================================================== Onglet 3

class _OngletProvende extends StatelessWidget {
  const _OngletProvende({required this.vm});

  final ParametresElevageViewModel vm;

  @override
  Widget build(BuildContext context) {
    final provendes = vm.provendesFiltrees;
    final appro = context.watch<ApprovisionnementViewModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Intrants entrant dans la composition de la provende — '
                'synchronisés avec Gestion Stocks et la Fabrication de '
                'Provende.',
                style: _texte.copyWith(color: AppColors.outline),
              ),
            ),
            AppButton(
              label: 'Ajouter',
              icon: Symbols.add_circle,
              onPressed: () => formulaireIntrantProvende(context, vm, appro),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CarteSection(
          titre: '${provendes.length} intrant(s) de provende',
          icone: Symbols.inventory_2,
          action: SizedBox(
            width: 280,
            child: TextFormField(
              initialValue: vm.rechercheProvende,
              style: _texte,
              decoration: _decoration.copyWith(
                hintText: 'Rechercher un intrant…',
                prefixIcon: const Icon(
                  Symbols.search,
                  size: 18,
                  color: AppColors.outline,
                ),
              ),
              onChanged: vm.definirRechercheProvende,
            ),
          ),
          child: provendes.isEmpty
              ? EtatVide(
                  message: vm.provendes.isEmpty
                      ? 'Aucun intrant de provende enregistré. Utilisez '
                            '« Ajouter » pour en créer un — il sera aussitôt '
                            'disponible dans la Fabrication de Provende et '
                            'dans Gestion Stocks.'
                      : 'Aucun intrant ne correspond à cette recherche.',
                )
              : Column(
                  children: [
                    const _Entete(
                      colonnes: [
                        ('CODE', 2, TextAlign.left),
                        ('INTRANT', 5, TextAlign.left),
                        ('STOCK ACTUEL', 3, TextAlign.right),
                        ('SEUIL D\'ALERTE', 3, TextAlign.right),
                        ('PRIX INDICATIF (FCFA/KG)', 4, TextAlign.right),
                        ('ACTIONS', 2, TextAlign.right),
                      ],
                    ),
                    for (var i = 0; i < provendes.length; i++)
                      _Ligne(
                        zebre: i.isOdd,
                        cellules: [
                          (
                            Text(
                              provendes[i].code,
                              style: _mono.copyWith(fontSize: 11),
                            ),
                            2,
                          ),
                          (Text(provendes[i].nom, style: _gras), 5),
                          (
                            Text(
                              '${Formats.nombre(provendes[i].stock)} '
                              '${provendes[i].unite}',
                              textAlign: TextAlign.right,
                              style: provendes[i].critique
                                  ? _gras.copyWith(color: AppColors.errorDeep)
                                  : _texte,
                            ),
                            3,
                          ),
                          (
                            Text(
                              '${Formats.nombre(provendes[i].seuil)} '
                              '${provendes[i].unite}',
                              textAlign: TextAlign.right,
                              style: _texte.copyWith(color: AppColors.outline),
                            ),
                            3,
                          ),
                          (
                            Text(
                              Formats.nombre(provendes[i].prixIndicatif),
                              textAlign: TextAlign.right,
                              style: _texte,
                            ),
                            4,
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
                                  onPressed: () => formulaireIntrantProvende(
                                    context,
                                    vm,
                                    appro,
                                    existant: provendes[i],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Symbols.delete, size: 18),
                                  color: AppColors.errorDeep,
                                  tooltip: 'Supprimer',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () =>
                                      confirmerSuppressionIntrantProvende(
                                        context,
                                        vm,
                                        appro,
                                        provendes[i],
                                      ),
                                ),
                              ],
                            ),
                            2,
                          ),
                        ],
                      ),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.outlineVariant),
                        ),
                      ),
                      child: Text(
                        'La quantité en stock ne se saisit pas ici : elle ne '
                        'bouge que par une réception de commande, une '
                        'fabrication de provende ou un ajustement '
                        'd\'inventaire — chacun laissant sa trace dans le '
                        'journal des mouvements. Le prix indicatif affiché est '
                        'le Prix Moyen Pondéré réellement calculé par le module '
                        'Approvisionnement.',
                        style: _texte.copyWith(
                          fontSize: 11,
                          color: AppColors.outline,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Modale d'ajout et de modification d'un intrant de provende.
///
/// Elle écrit dans `INTRANTS`, table du module Approvisionnement : c'est son
/// ViewModel qui est utilisé, avec ses validations déjà éprouvées, plutôt
/// qu'une seconde logique parallèle.
///
/// **Le stock n'est volontairement pas modifiable** — voir [TypeProvende]. À la
/// création il part de 0 : un intrant existe d'abord, il se remplit ensuite par
/// une réception de commande.
Future<void> formulaireIntrantProvende(
  BuildContext context,
  ParametresElevageViewModel vm,
  ApprovisionnementViewModel appro, {
  TypeProvende? existant,
}) async {
  final nomCtrl = TextEditingController(text: existant?.nom ?? '');
  final uniteCtrl = TextEditingController(text: existant?.unite ?? 'kg');
  final seuilCtrl = TextEditingController(
    text: existant == null ? '0' : existant.seuil.round().toString(),
  );
  final pmpCtrl = TextEditingController(
    text: existant == null ? '0' : existant.prixIndicatif.round().toString(),
  );

  await AppModal.show<void>(
    context,
    title: existant == null
        ? 'Ajouter un Intrant de Provende'
        : 'Modifier — ${existant.nom}',
    maxWidth: 520,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (existant != null) ...[
          Row(
            children: [
              const Text('CODE', style: AppTypography.label),
              const SizedBox(width: AppSpacing.sm),
              Text(existant.code, style: _mono),
              const Spacer(),
              Text(
                'Stock actuel : ${Formats.nombre(existant.stock)} '
                '${existant.unite}',
                style: _texte.copyWith(color: AppColors.outline),
              ),
            ],
          ),
          const Divider(height: AppSpacing.lg),
        ],
        const Text('DÉSIGNATION *', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: nomCtrl,
          autofocus: existant == null,
          style: _texte,
          decoration: _decoration.copyWith(hintText: 'ex : Son de blé'),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('UNITÉ', style: AppTypography.label),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    controller: uniteCtrl,
                    style: _texte,
                    decoration: _decoration.copyWith(hintText: 'kg'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('SEUIL D\'ALERTE', style: AppTypography.label),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    controller: seuilCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: FormatteursSaisie.entierPositif,
                    style: _texte,
                    decoration: _decoration,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('PRIX INDICATIF (FCFA)', style: AppTypography.label),
                  const SizedBox(height: AppSpacing.xs),
                  TextField(
                    controller: pmpCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: FormatteursSaisie.montant,
                    style: _texte,
                    decoration: _decoration,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceZebra,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Text(
            existant == null
                ? 'Le nouvel intrant démarre à 0 en stock : il se remplit par '
                      'une réception de commande, jamais par une saisie '
                      'directe. Il apparaîtra aussitôt dans la Fabrication de '
                      'Provende et dans Gestion Stocks.'
                : 'La quantité en stock ne se modifie pas ici. Pour la '
                      'corriger, utilisez l\'ajustement d\'inventaire de '
                      'Gestion Stocks — l\'écart y est journalisé.',
            style: _texte.copyWith(
              fontSize: 11,
              color: AppColors.outline,
              height: 1.5,
            ),
          ),
        ),
      ],
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
          label: existant == null ? 'Ajouter' : 'Enregistrer',
          onPressed: () async {
            final resultat = await appro.enregistrerIntrant(
              code: existant?.code,
              nom: nomCtrl.text,
              categorie: Intrant.categories.first, // « Intrants Provende »
              // Le stock n'est jamais saisi : conserve a l'identique en
              // modification, 0 a la creation.
              stock: existant?.stock.round() ?? 0,
              unite: uniteCtrl.text,
              seuil: int.tryParse(seuilCtrl.text.trim()),
              pmp: int.tryParse(pmpCtrl.text.trim()),
            );

            if (!ctx.mounted) return;
            switch (resultat) {
              case Succes():
                // Les deux ViewModels lisent la meme table : celui des
                // parametres doit relire pour refleter l'ecriture.
                await vm.charger();
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                showAppToast(
                  ctx,
                  existant == null
                      ? '${nomCtrl.text.trim()} ajouté aux intrants de '
                            'provende.'
                      : 'Intrant ${existant.code} modifié.',
                );
              case Echec(:final message):
                showAppToast(ctx, message, type: ToastType.error);
            }
          },
        ),
      ),
    ],
  );

  nomCtrl.dispose();
  uniteCtrl.dispose();
  seuilCtrl.dispose();
  pmpCtrl.dispose();
}

/// Avertissement de suppression.
///
/// La suppression échoue si l'intrant figure déjà dans une commande ou un
/// mouvement : la clé étrangère de `LIGNES_ACHAT` et `MOUVEMENTS_INTRANT` s'y
/// oppose, et c'est voulu — effacer un intrant déjà mouvementé rendrait
/// illisible l'historique qui le référence. Le message le dit.
Future<void> confirmerSuppressionIntrantProvende(
  BuildContext context,
  ParametresElevageViewModel vm,
  ApprovisionnementViewModel appro,
  TypeProvende provende,
) async {
  final confirme = await AppModal.show<bool>(
    context,
    title: 'Supprimer « ${provende.nom} » ?',
    maxWidth: 520,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.errorContainer,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(
              color: AppColors.errorDeep.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Symbols.warning,
                size: 20,
                color: AppColors.errorDeep,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Cette action est irréversible.',
                  style: _gras.copyWith(color: AppColors.errorDeep),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'L\'intrant ${provende.code} disparaîtra des Paramètres Élevage, de '
          'Gestion Stocks et de la Fabrication de Provende. Son stock actuel '
          'de ${Formats.nombre(provende.stock)} ${provende.unite} sera perdu, '
          'sans mouvement de sortie pour le justifier.',
          style: _texte.copyWith(height: 1.5),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Si cet intrant a déjà été commandé ou consommé, la suppression sera '
          'refusée : l\'historique qui le référence deviendrait illisible. '
          'Dans ce cas, mettez plutôt son seuil d\'alerte à 0 pour cesser d\'en '
          'être averti.',
          style: _texte.copyWith(color: AppColors.outline, height: 1.5),
        ),
      ],
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
          label: 'Supprimer définitivement',
          variant: AppButtonVariant.danger,
          onPressed: () => Navigator.of(ctx).pop(true),
        ),
      ),
    ],
  );

  if (confirme != true || !context.mounted) return;

  final intrant = appro.tousLesIntrants
      .where((i) => i.code == provende.code)
      .firstOrNull;
  if (intrant == null) return;

  final resultat = await appro.supprimerIntrant(
    intrant,
    auteur: auteurCourant(context),
  );
  if (!context.mounted) return;

  switch (resultat) {
    case Succes():
      await vm.charger();
      if (!context.mounted) return;
      showAppToast(
        context,
        '${provende.nom} supprimé.',
        type: ToastType.warning,
      );
    case Echec(:final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

class _OngletNumerotation extends StatelessWidget {
  const _OngletNumerotation({required this.vm});

  final ParametresElevageViewModel vm;

  @override
  Widget build(BuildContext context) {
    final brouillon = vm.brouillon;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 860),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Symbols.tag, size: 20, color: AppColors.brandGold),
              SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Numérotation des Bandes & Sujets Par Espèce',
                  style: AppTypography.sectionTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Formatage des identifiants générés sur le terrain, avec aperçu en '
            'temps réel.',
            style: _texte.copyWith(color: AppColors.outline),
          ),
          const SizedBox(height: AppSpacing.md),
          CarteSection(
            titre: 'Conventions par filière',
            icone: Symbols.pets,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GroupeNumerotation(
                  titre: 'Aviculture (Goliaths & Pintades)',
                  icone: Symbols.pets,
                  champs: [
                    _ChampPrefixe(
                      libelle: 'Préfixe Enclos',
                      valeur: brouillon.enclos,
                      apercu: brouillon.apercuEnclos,
                      onChange: (v) => vm.modifierBrouillon(enclos: v),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _GroupeNumerotation(
                  titre: 'Cuniculture (Lapins)',
                  icone: Symbols.cruelty_free,
                  champs: [
                    _ChampPrefixe(
                      libelle: 'Préfixe Cage',
                      valeur: brouillon.cage,
                      apercu: brouillon.apercuCage,
                      onChange: (v) => vm.modifierBrouillon(cage: v),
                    ),
                    _ChampPrefixe(
                      libelle: 'Préfixe Bande',
                      valeur: brouillon.bande,
                      apercu: brouillon.apercuBande,
                      onChange: (v) => vm.modifierBrouillon(bande: v),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _GroupeNumerotation(
                  titre: 'Pisciculture (Poissons-Chats)',
                  icone: Symbols.set_meal,
                  champs: [
                    _ChampPrefixe(
                      libelle: 'Préfixe Bassin',
                      valeur: brouillon.bassin,
                      apercu: brouillon.apercuBassin,
                      onChange: (v) => vm.modifierBrouillon(bassin: v),
                    ),
                  ],
                ),
                const Divider(height: AppSpacing.lg),
                Row(
                  children: [
                    AppButton(
                      label: 'Enregistrer Tous les Formats de Numérotation',
                      icon: Symbols.save,
                      onPressed: vm.numerotationModifiee
                          ? () => _enregistrerNumerotation(context, vm)
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    if (vm.numerotationModifiee)
                      Text(
                        'Modifications non enregistrées',
                        style: _texte.copyWith(color: AppColors.brandGold),
                      )
                    else
                      Row(
                        children: [
                          const Icon(
                            Symbols.check_circle,
                            size: 16,
                            color: AppColors.successDeep,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Formats enregistrés',
                            style: _texte.copyWith(
                              color: AppColors.successDeep,
                            ),
                          ),
                        ],
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

class _GroupeNumerotation extends StatelessWidget {
  const _GroupeNumerotation({
    required this.titre,
    required this.icone,
    required this.champs,
  });

  final String titre;
  final IconData icone;
  final List<Widget> champs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icone, size: 18, color: AppColors.brandNavy),
              const SizedBox(width: AppSpacing.xs),
              Text(
                titre.toUpperCase(),
                style: AppTypography.label.copyWith(
                  color: AppColors.brandNavy,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final champ in champs) ...[
                Expanded(child: champ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (champs.length < 2) const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChampPrefixe extends StatefulWidget {
  const _ChampPrefixe({
    required this.libelle,
    required this.valeur,
    required this.apercu,
    required this.onChange,
  });

  final String libelle;
  final String valeur;
  final String apercu;
  final ValueChanged<String> onChange;

  @override
  State<_ChampPrefixe> createState() => _ChampPrefixeState();
}

class _ChampPrefixeState extends State<_ChampPrefixe> {
  late final TextEditingController _controleur;

  @override
  void initState() {
    super.initState();
    _controleur = TextEditingController(text: widget.valeur);
  }

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.libelle.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _controleur,
          // `maxlength="4"` du prototype.
          maxLength: 4,
          style: _mono.copyWith(fontSize: 14, color: AppColors.brandNavy),
          decoration: _decoration.copyWith(counterText: ''),
          onChanged: widget.onChange,
        ),
        const SizedBox(height: AppSpacing.xs),
        RichText(
          text: TextSpan(
            style: _texte.copyWith(color: AppColors.outline),
            children: [
              const TextSpan(text: 'Aperçu : '),
              TextSpan(
                text: widget.apercu,
                style: _gras.copyWith(color: AppColors.brandNavy),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> _enregistrerNumerotation(
  BuildContext context,
  ParametresElevageViewModel vm,
) async {
  final resultat = await vm.enregistrerNumerotation();
  if (!context.mounted) return;
  switch (resultat) {
    case Succes():
      final f = vm.formats;
      showAppToast(
        context,
        'Formats de numérotation enregistrés : Enclos « ${f.enclos}1 », '
        'Cage « ${f.cage}1 », Bassin « ${f.bassin}1 ».',
      );
    case Echec(:final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

// ====================================================== Widgets communs

class _Entete extends StatelessWidget {
  const _Entete({required this.colonnes});

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
                style: _texte.copyWith(color: AppColors.outline),
              ),
            ),
        ],
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.cellules, required this.zebre});

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
