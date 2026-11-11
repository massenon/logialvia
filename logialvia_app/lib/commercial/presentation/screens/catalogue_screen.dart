import '../../../core/widgets/auteur_courant.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/events/domain_event.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import 'documents_commercial.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../data/repositories/ventes_repository_drift.dart';
import '../../../elevage/domain/entities/configuration_espece.dart';
import '../../domain/entities/produit_vendable.dart';
import '../viewmodels/catalogue_view_model.dart';
import '../../../core/saisie/formats_saisie.dart';

class PageCatalogue extends StatelessWidget {
  const PageCatalogue({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CatalogueViewModel>(
      create: (context) => CatalogueViewModel(
        VentesRepositoryDrift(
          context.read<AppDatabase>(),
          context.read<EventBus>(),
        ),
      )..charger(),
      child: const CatalogueScreen(),
    );
  }
}

/// Catalogue & Seuils — Doc F4 Écran 2, fidèle à `catalogue-produits.html`.
///
/// ⚠️ **2 tableaux**, pas un seul comme le décrivait Doc F4 : le catalogue
/// complet et la liste des seuils d'alerte. C'est le nom que lui donne la barre
/// latérale — « Catalogue & Seuils ».
class CatalogueScreen extends StatelessWidget {
  const CatalogueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CatalogueViewModel>();

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
                Symbols.category,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Catalogue & Seuils',
                  style: AppTypography.pageTitle,
                ),
              ),
              BoutonExportPdf(
                construire: () => DocumentsCommercial.catalogue(vm),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Ajouter un Produit',
                icon: Symbols.add_circle,
                onPressed: () => _ouvrirFormulaire(context, vm, null),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _BandeauKpi(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Catalogue des Produits',
            cibleTour: 'tableau-catalogue',
            action: _Filtres(vm: vm),
            child: vm.produits.isEmpty
                ? const EtatVide(message: 'Aucun produit ne correspond.')
                : Column(
                    children: [
                      Container(
                        color: AppColors.surfaceZebra,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            _entete('SKU'),
                            _entete('Désignation', flex: 3),
                            _entete('Catégorie', flex: 2),
                            _entete('Stock', alignement: TextAlign.right),
                            _entete(
                              'Tarif',
                              flex: 2,
                              alignement: TextAlign.right,
                            ),
                            _entete('Actions', alignement: TextAlign.right),
                          ],
                        ),
                      ),
                      for (var i = 0; i < vm.produits.length; i++)
                        _LigneProduit(
                          produit: vm.produits[i],
                          zebre: i.isOdd,
                          vm: vm,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Seuils d\'Alerte',
            cibleTour: 'onglet-seuils',
            icone: Symbols.warning,
            couleurIcone: AppColors.errorDeep,
            child: vm.produitsSousSeuil.isEmpty
                ? const EtatVide(
                    message:
                        'Aucun produit sous son seuil d\'alerte. Cette liste se '
                        'remplit automatiquement dès qu\'un stock passe au '
                        'niveau critique.',
                  )
                : Column(
                    children: [
                      Container(
                        color: AppColors.surfaceZebra,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            _entete('Désignation', flex: 3),
                            _entete(
                              'Stock Actuel',
                              alignement: TextAlign.right,
                            ),
                            _entete(
                              'Seuil d\'Alerte',
                              alignement: TextAlign.right,
                            ),
                            _entete('Statut', alignement: TextAlign.center),
                          ],
                        ),
                      ),
                      for (var i = 0; i < vm.produitsSousSeuil.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: i.isOdd ? AppColors.surfaceZebra : null,
                            border: const Border(
                              bottom: BorderSide(
                                color: AppColors.outlineVariant,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  vm.produitsSousSeuil[i].nom,
                                  style: _texte,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${vm.produitsSousSeuil[i].stock}',
                                  textAlign: TextAlign.right,
                                  style: _texte.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.errorDeep,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '${vm.produitsSousSeuil[i].seuil}',
                                  textAlign: TextAlign.right,
                                  style: _texte,
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.errorContainer,
                                      borderRadius: AppRadius.pill,
                                    ),
                                    child: Text(
                                      vm.produitsSousSeuil[i].estEpuise
                                          ? 'Rupture'
                                          : 'Critique',
                                      style: const TextStyle(
                                        fontFamily: AppTypography.fontFamily,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.errorDeep,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static Widget _entete(
    String libelle, {
    int flex = 1,
    TextAlign alignement = TextAlign.left,
  }) => Expanded(
    flex: flex,
    child: Text(
      libelle,
      textAlign: alignement,
      style: _texte.copyWith(color: AppColors.outline),
    ),
  );
}

Future<void> _ouvrirFormulaire(
  BuildContext context,
  CatalogueViewModel vm,
  ProduitVendable? produit,
) async {
  final resultat = await AppModal.show<Resultat<ProduitVendable>>(
    context,
    title: produit == null ? 'Ajouter un Produit' : 'Modifier ${produit.nom}',
    maxWidth: 480,
    child: _FormulaireProduit(vm: vm, produit: produit),
  );
  if (resultat == null || !context.mounted) return;
  switch (resultat) {
    case Succes<ProduitVendable>():
      showAppToast(context, 'Produit enregistré.');
    case Echec<ProduitVendable>(message: final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

class _BandeauKpi extends StatelessWidget {
  const _BandeauKpi({required this.vm});

  final CatalogueViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cartes = [
      KpiCard(
        libelle: 'Produits Actifs',
        valeur: '${vm.produitsActifs}',
        accent: AppColors.brandNavy,
        icone: Symbols.category,
      ),
      KpiCard(
        libelle: 'Valeur Totale du Catalogue',
        valeur: Formats.nombre(vm.valeurCatalogue),
        unite: 'FCFA',
        accent: AppColors.successDeep,
        icone: Symbols.savings,
        detail: 'Somme stock × tarif',
      ),
      KpiCard(
        libelle: 'Produits en Stock Critique',
        valeur: '${vm.produitsCritiques}',
        accent: AppColors.errorDeep,
        icone: Symbols.warning,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final largeur = (constraints.maxWidth - AppSpacing.md * 2) / 3;
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

  final CatalogueViewModel vm;

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
                style: _texte,
                decoration: _decoration.copyWith(
                  hintText: 'Désignation ou SKU…',
                  prefixIcon: const Icon(Symbols.search, size: 16),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String?>(
              initialValue: vm.filtreCategorie,
              isExpanded: true,
              decoration: _decoration,
              style: _texte,
              items: [
                const DropdownMenuItem(value: null, child: Text('Toutes')),
                for (final c in vm.categories)
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

class _LigneProduit extends StatelessWidget {
  const _LigneProduit({
    required this.produit,
    required this.zebre,
    required this.vm,
  });

  final ProduitVendable produit;
  final bool zebre;
  final CatalogueViewModel vm;

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
          Expanded(
            child: Text(
              produit.sku ?? '—',
              style: _texte.copyWith(color: AppColors.outline),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              produit.nom,
              style: _texte.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(flex: 2, child: Text(produit.categorie, style: _texte)),
          Expanded(
            child: Text(
              '${produit.stock}',
              textAlign: TextAlign.right,
              style: _texte.copyWith(
                fontWeight: FontWeight.w700,
                color: produit.estCritique
                    ? AppColors.errorDeep
                    : AppColors.onSurface,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              produit.aUneFourchette
                  ? '${Formats.nombre(produit.prix)} – ${Formats.nombre(produit.prixMax!)}'
                  : Formats.nombre(produit.prix),
              textAlign: TextAlign.right,
              style: _texte,
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () => _ouvrirFormulaire(context, vm, produit),
                  icon: const Icon(Symbols.edit, size: 16),
                  color: AppColors.infoBlue,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Modifier',
                ),
                IconButton(
                  onPressed: () async {
                    final resultat = await vm.supprimer(
                      produit,
                      auteur: auteurCourant(context),
                    );
                    if (!context.mounted) return;
                    switch (resultat) {
                      case Succes<void>():
                        showAppToast(context, 'Produit supprimé.');
                      case Echec<void>(message: final message):
                        showAppToast(context, message, type: ToastType.error);
                    }
                  },
                  icon: const Icon(Symbols.delete, size: 16),
                  color: AppColors.errorDeep,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Supprimer',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormulaireProduit extends StatefulWidget {
  const _FormulaireProduit({required this.vm, required this.produit});

  final CatalogueViewModel vm;
  final ProduitVendable? produit;

  @override
  State<_FormulaireProduit> createState() => _FormulaireProduitState();
}

class _FormulaireProduitState extends State<_FormulaireProduit> {
  late final TextEditingController _nom;
  late final TextEditingController _prix;
  late final TextEditingController _prixMax;
  late final TextEditingController _unite;
  late final TextEditingController _stock;
  late final TextEditingController _motifCorrection;
  late final TextEditingController _seuil;
  late final TextEditingController _coutRevient;
  String? _categorie;

  /// Filière d'élevage dont le produit est la vente (`null` = aucune).
  String? _espece;
  String? _erreur;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    final p = widget.produit;
    _nom = TextEditingController(text: p?.nom ?? '');
    _prix = TextEditingController(text: p?.prix.toStringAsFixed(0) ?? '');
    _prixMax = TextEditingController(
      text: p?.prixMax?.toStringAsFixed(0) ?? '',
    );
    _unite = TextEditingController(text: p?.unite ?? 'u');
    _stock = TextEditingController(text: p?.stock.toString() ?? '0')
      ..addListener(() => setState(() {}));
    _motifCorrection = TextEditingController();
    _seuil = TextEditingController(text: p?.seuil.toString() ?? '0');
    _coutRevient = TextEditingController(
      text: p?.coutRevient?.toStringAsFixed(0) ?? '',
    );
    _categorie = p?.categorie;
    _espece = p?.espece;
  }

  @override
  void dispose() {
    _nom.dispose();
    _prix.dispose();
    _prixMax.dispose();
    _unite.dispose();
    _stock.dispose();
    _motifCorrection.dispose();
    _seuil.dispose();
    _coutRevient.dispose();
    super.dispose();
  }

  /// Vrai quand on modifie le stock d'un produit EXISTANT : le motif devient requis.
  bool get _stockModifie =>
      widget.produit != null &&
      int.tryParse(_stock.text) != widget.produit!.stock;

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.enregistrer(
      id: widget.produit?.id,
      nom: _nom.text,
      categorie: _categorie,
      prix: double.tryParse(_prix.text),
      prixMax: double.tryParse(_prixMax.text),
      unite: _unite.text,
      stock: int.tryParse(_stock.text),
      seuil: int.tryParse(_seuil.text),
      espece: _espece,
      coutRevient: double.tryParse(_coutRevient.text.trim()),
      motifCorrection: _motifCorrection.text,
    );
    if (!mounted) return;

    if (resultat is Echec<ProduitVendable>) {
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
        _champ('Désignation *', _nom),
        const SizedBox(height: AppSpacing.sm),
        const Text('CATÉGORIE', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String>(
          initialValue: _categorie,
          isExpanded: true,
          decoration: _decoration,
          style: _texte,
          hint: const Text('-- Sélectionner --', style: _texte),
          items: [
            for (final c in ProduitVendable.categories)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => setState(() => _categorie = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Sans ce choix, un produit neuf n'est rattache a AUCUNE fiche : sa
        // vente ne decrementerait ni la categorie commercialisee ni le
        // compteur de ventes du jour, et ne serait imputee a aucun centre.
        const Text(
          'FILIÈRE D\'ÉLEVAGE (FACULTATIF)',
          style: AppTypography.label,
        ),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<String?>(
          key: const ValueKey('champ-filiere'),
          initialValue: _espece,
          isExpanded: true,
          decoration: _decoration,
          style: _texte,
          items: [
            const DropdownMenuItem<String?>(
              child: Text('Aucune (produit hors élevage)'),
            ),
            for (final config in ConfigurationsEspeces.parIdentifiant.values)
              DropdownMenuItem<String?>(
                value: config.identifiant,
                child: Text(config.libelle),
              ),
          ],
          onChanged: (v) => setState(() => _espece = v),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Rattache les ventes de ce produit à la fiche de la filière : le '
          'stock vendu est déduit de sa catégorie commercialisée.',
          style: _texte.copyWith(fontSize: 11, color: AppColors.outline),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _champ(
                'Tarif Indicatif (FCFA) *',
                _prix,
                clavier: TextInputType.number,
                formatteurs: FormatteursSaisie.montant,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _champ(
                'Tarif Haut (facultatif)',
                _prixMax,
                clavier: TextInputType.number,
                formatteurs: FormatteursSaisie.montant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // Ajoute : le prototype ne connait pas le cout de revient et remplit
        // sa colonne « CMUP » avec le prix de vente. Voir Doc F4.
        _champ(
          'Coût de Revient (FCFA)',
          _coutRevient,
          clavier: TextInputType.number,
          formatteurs: FormatteursSaisie.montant,
        ),
        const Text(
          'Ce que le produit a coûté, pas ce qu\'il se vend. Sert à valoriser '
          'le stock dans le Rapport de Stocks. Laissé vide, le stock de ce '
          'produit n\'est pas valorisé — le prix de vente ne lui est jamais '
          'substitué.',
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 11,
            height: 1.4,
            color: AppColors.outline,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: _champ('Unité', _unite)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _champ(
                'Stock',
                _stock,
                clavier: TextInputType.number,
                formatteurs: FormatteursSaisie.entierPositif,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _champ(
                'Seuil d\'Alerte',
                _seuil,
                clavier: TextInputType.number,
                formatteurs: FormatteursSaisie.entierPositif,
              ),
            ),
          ],
        ),
        if (_stockModifie) ...[
          const SizedBox(height: AppSpacing.sm),
          _champ('Motif de la correction de stock', _motifCorrection),
        ],
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

  Widget _champ(
    String libelle,
    TextEditingController controleur, {
    TextInputType? clavier,
    List<TextInputFormatter>? formatteurs,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(libelle.toUpperCase(), style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: controleur,
          keyboardType: clavier,
          inputFormatters: formatteurs,
          style: _texte,
          decoration: _decoration,
        ),
      ],
    );
  }
}

const TextStyle _texte = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
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
