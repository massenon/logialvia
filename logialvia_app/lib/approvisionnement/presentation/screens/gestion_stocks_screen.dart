import '../../../core/widgets/auteur_courant.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/formatage/formats.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import 'documents_appro.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../domain/entities/approvisionnement.dart';
import '../../domain/entities/fabrication_provende.dart';
import '../viewmodels/approvisionnement_view_model.dart';
import 'widgets/communs_appro.dart';
import '../../../core/saisie/formats_saisie.dart';

/// Gestion des Stocks — Doc F5 Écran 1, fidèle à `gestion-stocks.html`.
///
/// ⚠️ **2 tableaux** : les intrants et le **journal des mouvements**, ce dernier
/// absent de Doc F5. Le KPI réel est « Mouvements (7j) », pas « Dernier
/// Mouvement ».
class GestionStocksScreen extends StatelessWidget {
  const GestionStocksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ApprovisionnementViewModel>();

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
                Symbols.inventory_2,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Gestion des Stocks',
                  style: AppTypography.pageTitle,
                ),
              ),
              BoutonExportPdf(construire: () => DocumentsAppro.stocks(vm)),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Fabrication de Provende',
                cibleTour: 'bouton-fabrication',
                icon: Symbols.blender,
                variant: AppButtonVariant.outline,
                onPressed: () => ouvrirModaleFabrication(context, vm),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Ajouter un Intrant',
                icon: Symbols.add_circle,
                onPressed: () => _formulaireIntrant(context, vm, null),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _BandeauKpi(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Intrants',
            cibleTour: 'tableau-stocks',
            action: _Filtres(vm: vm),
            child: vm.intrants.isEmpty
                ? const EtatVide(message: 'Aucun intrant ne correspond.')
                : Column(
                    children: [
                      const EnteteTableauAppro(
                        colonnes: [
                          ('Désignation', 3, TextAlign.left),
                          ('Catégorie', 2, TextAlign.left),
                          ('Stock', 1, TextAlign.right),
                          ('Seuil Alerte', 1, TextAlign.right),
                          ('Valeur', 2, TextAlign.right),
                          ('Statut', 1, TextAlign.center),
                          ('Actions', 2, TextAlign.right),
                        ],
                      ),
                      for (var i = 0; i < vm.intrants.length; i++)
                        _LigneIntrant(
                          intrant: vm.intrants[i],
                          zebre: i.isOdd,
                          vm: vm,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Journal des Mouvements',
            icone: Symbols.receipt_long,
            child: vm.mouvements.isEmpty
                ? const EtatVide(
                    message:
                        'Aucun mouvement enregistré. Les réceptions de '
                        'commandes et les ajustements d\'inventaire '
                        'apparaissent ici automatiquement.',
                  )
                : Column(
                    children: [
                      const EnteteTableauAppro(
                        colonnes: [
                          ('Date / Heure', 2, TextAlign.left),
                          ('Référence', 2, TextAlign.left),
                          ('Article', 2, TextAlign.left),
                          ('Type', 1, TextAlign.left),
                          ('Motif', 3, TextAlign.left),
                          ('Quantité', 1, TextAlign.right),
                        ],
                      ),
                      for (var i = 0; i < vm.mouvements.length; i++)
                        () {
                          final m = vm.mouvements[i];
                          return LigneTableauAppro(
                            zebre: i.isOdd,
                            cellules: [
                              (
                                Text(
                                  '${Formats.date(m.horodatage)} '
                                  '${Formats.heure(m.horodatage)}',
                                  style: texteAppro,
                                ),
                                2,
                              ),
                              (
                                Text(
                                  m.reference ?? '—',
                                  style: texteAppro.copyWith(
                                    color: AppColors.outline,
                                  ),
                                ),
                                2,
                              ),
                              (Text(m.article, style: grasAppro), 2),
                              (Text(m.type, style: texteAppro), 1),
                              (Text(m.motif, style: texteAppro), 3),
                              (
                                Text(
                                  m.quantite > 0
                                      ? '+${Formats.nombre(m.quantite)}'
                                      : Formats.nombre(m.quantite),
                                  textAlign: TextAlign.right,
                                  style: grasAppro.copyWith(
                                    color: m.quantite >= 0
                                        ? AppColors.successDeep
                                        : AppColors.errorDeep,
                                  ),
                                ),
                                1,
                              ),
                            ],
                          );
                        }(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _BandeauKpi extends StatelessWidget {
  const _BandeauKpi({required this.vm});

  final ApprovisionnementViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cartes = [
      KpiCard(
        libelle: 'Valeur Totale Stock',
        valeur: Formats.nombre(vm.valeurTotaleStock),
        unite: 'FCFA',
        accent: AppColors.brandNavy,
        icone: Symbols.savings,
        detail: 'Somme stock × PMP',
      ),
      KpiCard(
        libelle: 'Intrants Sous Seuil',
        valeur: '${vm.intrantsSousSeuil}',
        accent: AppColors.errorDeep,
        icone: Symbols.warning,
      ),
      KpiCard(
        libelle: 'Articles Suivis',
        valeur: '${vm.articlesSuivis}',
        accent: AppColors.infoBlue,
        icone: Symbols.inventory_2,
      ),
      KpiCard(
        libelle: 'Mouvements (7j)',
        valeur: '${vm.mouvements7Jours}',
        accent: AppColors.brandGold,
        icone: Symbols.receipt_long,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeur = (constraints.maxWidth - AppSpacing.md * 3) / 4;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final carte in cartes) SizedBox(width: largeur, child: carte),
          ],
        );
      },
    );
  }
}

class _Filtres extends StatelessWidget {
  const _Filtres({required this.vm});

  final ApprovisionnementViewModel vm;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 380,
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 34,
              child: TextField(
                onChanged: vm.definirRecherche,
                style: texteAppro,
                decoration: decorationAppro.copyWith(
                  hintText: 'Désignation ou code…',
                  prefixIcon: const Icon(Symbols.search, size: 16),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String?>(
              initialValue: vm.filtreCategorie,
              isExpanded: true,
              decoration: decorationAppro,
              style: texteAppro,
              items: [
                const DropdownMenuItem(value: null, child: Text('Toutes')),
                for (final c in Intrant.categories)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: vm.definirCategorie,
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneIntrant extends StatelessWidget {
  const _LigneIntrant({
    required this.intrant,
    required this.zebre,
    required this.vm,
  });

  final Intrant intrant;
  final bool zebre;
  final ApprovisionnementViewModel vm;

  @override
  Widget build(BuildContext context) {
    return LigneTableauAppro(
      zebre: zebre,
      cellules: [
        (
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(intrant.nom, style: grasAppro),
              Text(
                intrant.code,
                style: texteAppro.copyWith(
                  fontSize: 11,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
          3,
        ),
        (Text(intrant.categorie, style: texteAppro), 2),
        (
          Text(
            '${intrant.stock} ${intrant.unite}',
            textAlign: TextAlign.right,
            style: grasAppro.copyWith(
              color: intrant.estCritique
                  ? AppColors.errorDeep
                  : AppColors.onSurface,
            ),
          ),
          1,
        ),
        (
          Text(
            '${intrant.seuil}',
            textAlign: TextAlign.right,
            style: texteAppro,
          ),
          1,
        ),
        (
          Text(
            Formats.nombre(intrant.valeur),
            textAlign: TextAlign.right,
            style: texteAppro,
          ),
          2,
        ),
        (
          Center(
            child: PastilleAppro(
              libelle: intrant.estCritique ? 'Critique' : 'OK',
              fond: intrant.estCritique
                  ? AppColors.errorContainer
                  : AppColors.successContainer,
              couleurTexte: intrant.estCritique
                  ? AppColors.errorDeep
                  : AppColors.successDeep,
            ),
          ),
          1,
        ),
        (
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: () => _ajustement(context, vm, intrant),
                icon: const Icon(Symbols.balance, size: 16),
                color: AppColors.brandGold,
                visualDensity: VisualDensity.compact,
                tooltip: 'Ajustement d\'inventaire',
              ),
              IconButton(
                onPressed: () => _formulaireIntrant(context, vm, intrant),
                icon: const Icon(Symbols.edit, size: 16),
                color: AppColors.infoBlue,
                visualDensity: VisualDensity.compact,
                tooltip: 'Modifier',
              ),
              IconButton(
                onPressed: () async {
                  final resultat = await vm.supprimerIntrant(
                    intrant,
                    auteur: auteurCourant(context),
                  );
                  if (!context.mounted) return;
                  switch (resultat) {
                    case Succes<void>():
                      showAppToast(context, 'Intrant supprimé.');
                    case Echec<void>(message: final m):
                      showAppToast(context, m, type: ToastType.error);
                  }
                },
                icon: const Icon(Symbols.delete, size: 16),
                color: AppColors.errorDeep,
                visualDensity: VisualDensity.compact,
                tooltip: 'Supprimer',
              ),
            ],
          ),
          2,
        ),
      ],
    );
  }
}

Future<void> _formulaireIntrant(
  BuildContext context,
  ApprovisionnementViewModel vm,
  Intrant? intrant,
) async {
  final resultat = await AppModal.show<Resultat<void>>(
    context,
    title: intrant == null ? 'Ajouter un Intrant' : 'Modifier ${intrant.nom}',
    maxWidth: 460,
    child: _FormulaireIntrant(vm: vm, intrant: intrant),
  );
  if (resultat == null || !context.mounted) return;
  switch (resultat) {
    case Succes<void>():
      showAppToast(context, 'Intrant enregistré.');
    case Echec<void>(message: final m):
      showAppToast(context, m, type: ToastType.error);
  }
}

class _FormulaireIntrant extends StatefulWidget {
  const _FormulaireIntrant({required this.vm, required this.intrant});

  final ApprovisionnementViewModel vm;
  final Intrant? intrant;

  @override
  State<_FormulaireIntrant> createState() => _FormulaireIntrantState();
}

class _FormulaireIntrantState extends State<_FormulaireIntrant> {
  late final TextEditingController _nom;
  late final TextEditingController _stock;
  late final TextEditingController _unite;
  late final TextEditingController _seuil;
  late final TextEditingController _pmp;
  String? _categorie;
  String? _erreur;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    final i = widget.intrant;
    _nom = TextEditingController(text: i?.nom ?? '');
    _stock = TextEditingController(text: i?.stock.toString() ?? '0');
    _unite = TextEditingController(text: i?.unite ?? 'kg');
    _seuil = TextEditingController(text: i?.seuil.toString() ?? '0');
    _pmp = TextEditingController(text: i?.pmp.toString() ?? '0');
    _categorie = i?.categorie;
  }

  @override
  void dispose() {
    _nom.dispose();
    _stock.dispose();
    _unite.dispose();
    _seuil.dispose();
    _pmp.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.enregistrerIntrant(
      code: widget.intrant?.code,
      nom: _nom.text,
      categorie: _categorie,
      stock: int.tryParse(_stock.text),
      unite: _unite.text,
      seuil: int.tryParse(_seuil.text),
      pmp: int.tryParse(_pmp.text),
    );
    if (!mounted) return;

    if (resultat is Echec<void>) {
      setState(() {
        _enCours = false;
        _erreur = resultat.message;
      });
      return;
    }
    Navigator.of(context).pop(resultat);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChampAppro(libelle: 'Désignation *', controleur: _nom),
        const SizedBox(height: AppSpacing.sm),
        const Text('CATÉGORIE *', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String>(
          initialValue: _categorie,
          isExpanded: true,
          decoration: decorationAppro,
          style: texteAppro,
          hint: const Text('-- Sélectionner --', style: texteAppro),
          items: [
            for (final c in Intrant.categories)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => setState(() => _categorie = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: ChampAppro(
                libelle: 'Quantité',
                controleur: _stock,
                clavier: TextInputType.number,
                formatteurs: FormatteursSaisie.entierPositif,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: ChampAppro(libelle: 'Unité', controleur: _unite)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: ChampAppro(
                libelle: 'Seuil d\'Alerte',
                controleur: _seuil,
                clavier: TextInputType.number,
                formatteurs: FormatteursSaisie.entierPositif,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ChampAppro(
                libelle: 'Prix Unitaire (PMP)',
                controleur: _pmp,
                clavier: TextInputType.number,
                formatteurs: FormatteursSaisie.montant,
                note: 'Recalculé à chaque réception',
              ),
            ),
          ],
        ),
        if (_erreur != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_erreur!, style: AppTypography.invalidFeedback),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: _enCours ? 'Enregistrement…' : 'Enregistrer',
              onPressed: _enCours ? null : _valider,
            ),
          ],
        ),
      ],
    );
  }
}

/// Modale « Ajustement d'Inventaire » — Doc F5 Écran 1.
Future<void> _ajustement(
  BuildContext context,
  ApprovisionnementViewModel vm,
  Intrant intrant,
) async {
  final resultat = await AppModal.show<Resultat<void>>(
    context,
    title: 'Ajustement d\'Inventaire — ${intrant.nom}',
    maxWidth: 420,
    child: _FormulaireAjustement(vm: vm, intrant: intrant),
  );
  if (resultat == null || !context.mounted) return;
  switch (resultat) {
    case Succes<void>():
      showAppToast(context, 'Ajustement enregistré et journalisé.');
    case Echec<void>(message: final m):
      showAppToast(context, m, type: ToastType.error);
  }
}

class _FormulaireAjustement extends StatefulWidget {
  const _FormulaireAjustement({required this.vm, required this.intrant});

  final ApprovisionnementViewModel vm;
  final Intrant intrant;

  @override
  State<_FormulaireAjustement> createState() => _FormulaireAjustementState();
}

class _FormulaireAjustementState extends State<_FormulaireAjustement> {
  late final TextEditingController _physique = TextEditingController(
    text: widget.intrant.stock.toString(),
  );
  final _motif = TextEditingController(text: 'Inventaire physique');
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _physique.dispose();
    _motif.dispose();
    super.dispose();
  }

  int get _ecart =>
      (int.tryParse(_physique.text) ?? widget.intrant.stock) -
      widget.intrant.stock;

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.ajusterInventaire(
      intrant: widget.intrant,
      stockPhysique: int.tryParse(_physique.text),
      motif: _motif.text,
    );
    if (!mounted) return;

    if (resultat is Echec<void>) {
      setState(() {
        _enCours = false;
        _erreur = resultat.message;
      });
      return;
    }
    Navigator.of(context).pop(resultat);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceZebra,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Stock théorique (base)',
                  style: texteAppro.copyWith(color: AppColors.outline),
                ),
              ),
              Text(
                '${widget.intrant.stock} ${widget.intrant.unite}',
                style: grasAppro,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ChampAppro(
          libelle: 'Stock Physique Constaté *',
          controleur: _physique,
          clavier: TextInputType.number,
          formatteurs: FormatteursSaisie.entierPositif,
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: _ecart == 0
                ? AppColors.successContainer
                : AppColors.errorContainer,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: [
              const Expanded(
                child: Text('Écart constaté', style: texteAppro),
              ),
              Text(
                _ecart > 0 ? '+$_ecart' : '$_ecart',
                style: grasAppro.copyWith(
                  fontSize: 16,
                  color: _ecart == 0
                      ? AppColors.successDeep
                      : AppColors.errorDeep,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ChampAppro(
          libelle: 'Motif *',
          controleur: _motif,
          note: 'BR-ADM-003 : l\'écart est journalisé, jamais effacé.',
        ),
        if (_erreur != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_erreur!, style: AppTypography.invalidFeedback),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton(
              label: 'Annuler',
              variant: AppButtonVariant.outline,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: _enCours ? 'Enregistrement…' : 'Valider l\'Ajustement',
              onPressed: _enCours ? null : _valider,
            ),
          ],
        ),
      ],
    );
  }
}

/// Modale « Fabrication de Provende » — `#modal-fabrication` de
/// `gestion-stocks.html`.
///
/// Voir [FabricationProvende] pour l'exigence du Cahier des Charges Technique
/// §6.2 et pour ce que le prototype annonce sans le faire.
Future<void> ouvrirModaleFabrication(
  BuildContext context,
  ApprovisionnementViewModel vm,
) async {
  final intrants = vm.intrantsDeProvende;
  if (intrants.isEmpty) {
    showAppToast(
      context,
      'Aucun intrant de catégorie « Intrants Provende » n\'est enregistré.',
      type: ToastType.error,
    );
    return;
  }

  // Composition par defaut du prototype, restreinte aux intrants qui existent.
  final controleurs = {
    for (final i in intrants)
      i.code: TextEditingController(
        text:
            (FabricationProvende.compositionParDefaut[i.code] ?? 0)
                .toStringAsFixed(0),
      ),
  };

  Map<String, double> lire() => {
    for (final entree in controleurs.entries)
      entree.key:
          double.tryParse(entree.value.text.trim().replaceAll(',', '.')) ?? 0,
  };

  await AppModal.show<void>(
    context,
    title: 'Fabrication de Provende',
    maxWidth: 560,
    child: StatefulBuilder(
      builder: (ctx, setState) {
        final fabrication = FabricationProvende(lire());
        final manquants = fabrication.manquants(intrants);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Toute sortie d\'intrant pour la fabrication de provende doit '
              'être justifiée par cette opération — jamais une simple sortie '
              'de stock isolée (Cahier des Charges Technique §6.2, §8.3).',
              style: texteAppro.copyWith(
                fontSize: 11,
                color: AppColors.outline,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final intrant in intrants)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${intrant.nom} (${intrant.unite})',
                        style: texteAppro.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${intrant.stock} dispo',
                      style: texteAppro.copyWith(
                        fontSize: 11,
                        color: intrant.estCritique
                            ? AppColors.errorDeep
                            : AppColors.outline,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: controleurs[intrant.code],
                        keyboardType: TextInputType.number,
                        inputFormatters: FormatteursSaisie.entierPositif,
                        textAlign: TextAlign.right,
                        style: texteAppro,
                        decoration: decorationAppro,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
            // `#fab-alert` — l'alerte apparait des la saisie, pas au clic.
            if (manquants.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
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
                      size: 18,
                      color: AppColors.errorDeep,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Stock insuffisant : ${manquants.join(', ')}.',
                        style: texteAppro.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.errorDeep,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceZebra,
                borderRadius: AppRadius.cardRadius,
              ),
              child: Column(
                children: [
                  const Text(
                    'TOTAL PROVENDE FABRIQUÉE',
                    style: AppTypography.label,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${Formats.nombre(fabrication.totalKg)} kg',
                    style: AppTypography.kpiValue.copyWith(fontSize: 22),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Les intrants sont décrémentés en une seule opération et chaque '
              'sortie est journalisée sous une même référence de fabrication. '
              'Si un seul stock est insuffisant, rien n\'est écrit.',
              style: texteAppro.copyWith(
                fontSize: 11,
                color: AppColors.outline,
                height: 1.5,
              ),
            ),
          ],
        );
      },
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
          label: 'Valider la Fabrication',
          icon: Symbols.blender,
          onPressed: () async {
            final resultat = await vm.fabriquerProvende(lire());
            if (!ctx.mounted) return;
            switch (resultat) {
              case Succes(:final valeur):
                Navigator.of(ctx).pop();
                showAppToast(
                  ctx,
                  'Fabrication $valeur enregistrée — stocks décrémentés et '
                  'mouvements journalisés.',
                );
              case Echec(:final message):
                showAppToast(ctx, message, type: ToastType.error);
            }
          },
        ),
      ),
    ],
  );

  for (final controleur in controleurs.values) {
    controleur.dispose();
  }
}
