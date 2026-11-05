import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/tour/tour_guide.dart';
import '../../../core/widgets/carte_section.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../data/repositories/inventaire_repository_drift.dart';
import '../../domain/entities/inventaire.dart';
import '../viewmodels/inventaire_view_model.dart';
import 'documents_inventaire.dart';
import 'widgets/communs_rapports.dart';

class PageInventaire extends StatelessWidget {
  const PageInventaire({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<InventaireViewModel>(
      create: (context) => InventaireViewModel(
        InventaireRepositoryDrift(context.read<AppDatabase>()),
      )..charger(),
      child: const InventaireScreen(),
    );
  }
}

/// Écran **Inventaire** — l'état daté des stocks, valorisé au coût.
///
/// ## Ce que cet écran est, et ce qu'il n'est pas
///
/// Ce n'est pas un second Rapport de Stocks. Le rapport donne une photographie
/// d'aujourd'hui ; l'inventaire répond à la question du comptable : **que
/// détenait l'exploitation à une date, et d'où vient l'écart avec la date
/// précédente ?** D'où les quatre colonnes de mouvement — stock initial,
/// entrées, sorties, stock final — et l'égalité qui doit les relier.
///
/// ## Trois natures de stock, trois traitements
///
/// - **Intrants** : valorisés au **PMP**, un coût d'achat réel recalculé à
///   chaque réception.
/// - **Produits finis** : valorisés au **coût de revient**, jamais au prix de
///   vente. Un goliath encore dans l'enclos n'a pas rapporté 6 000 F, il a
///   coûté de la provende (Doc D1 v18). Sans coût renseigné, la ligne n'entre
///   dans aucun total et le KPI annonce combien d'articles il exclut.
/// - **Animaux sur pied et œufs en incubation** : **comptés, non valorisés**.
///   Leur coût dépend de la provende consommée depuis la mise en bande, que le
///   modèle ne cumule pas par lot. Les compter dit la vérité ; leur coller un
///   prix gonflerait l'actif d'une marge non réalisée.
class InventaireScreen extends StatelessWidget {
  const InventaireScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<InventaireViewModel>();

    if (vm.chargement && vm.inventaire == null) {
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
                Symbols.inventory,
                size: 24,
                color: AppColors.brandGold,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Inventaire', style: AppTypography.pageTitle),
                    Text(
                      vm.libellePeriode,
                      style: texteRapport.copyWith(color: AppColors.outline),
                    ),
                  ],
                ),
              ),
              CibleTour(
                nom: 'inventaire-export',
                child: BoutonExportPdf(
                  construire: () => DocumentsInventaire.etat(vm),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          CibleTour(
            nom: 'inventaire-filtres',
            child: _BarreFiltres(vm: vm),
          ),
          const SizedBox(height: AppSpacing.lg),
          CibleTour(
            nom: 'inventaire-kpi',
            child: _BandeauKpi(vm: vm),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (vm.inventaire?.intrantsDesequilibres.isNotEmpty ?? false) ...[
            _AlerteDesequilibre(vm: vm),
            const SizedBox(height: AppSpacing.lg),
          ],
          CarteSection(
            titre: 'Intrants — valorisés au PMP',
            icone: Symbols.inventory_2,
            cibleTour: 'inventaire-intrants',
            child: vm.intrants.isEmpty
                ? const EtatVide(
                    message: 'Aucun intrant ne correspond à ces filtres.',
                  )
                : _TableauIntrants(lignes: vm.intrants),
          ),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Produits finis — valorisés au coût de revient',
            icone: Symbols.sell,
            cibleTour: 'inventaire-produits',
            child: vm.produits.isEmpty
                ? const EtatVide(
                    message: 'Aucun produit ne correspond à ces filtres.',
                  )
                : _TableauProduits(lignes: vm.produits),
          ),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Animaux sur pied — comptés, non valorisés',
            icone: Symbols.pets,
            cibleTour: 'inventaire-effectifs',
            child: _TableauEffectifs(vm: vm),
          ),
        ],
      ),
    );
  }
}

/// Période, bornes libres et recherche.
class _BarreFiltres extends StatelessWidget {
  const _BarreFiltres({required this.vm});

  final InventaireViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final periode in PeriodeInventaire.values)
            _Pastille(
              libelle: periode.libelle,
              active: vm.periode == periode,
              onTap: periode == PeriodeInventaire.plage
                  ? null
                  : () => vm.changerPeriode(periode),
            ),
          const SizedBox(width: AppSpacing.md),
          _BoutonDate(
            libelle: 'Du',
            date: vm.debut,
            onChange: (d) => vm.definirPlage(debut: d),
          ),
          _BoutonDate(
            libelle: 'Au',
            date: vm.fin,
            onChange: (d) => vm.definirPlage(fin: d),
          ),
          SizedBox(
            width: 260,
            child: TextFormField(
              initialValue: vm.recherche,
              style: texteRapport,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppColors.surfaceCard,
                hintText: 'Rechercher un article, un code…',
                hintStyle: texteRapport.copyWith(color: AppColors.outline),
                prefixIcon: const Icon(
                  Symbols.search,
                  size: 16,
                  color: AppColors.outline,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppRadius.cardRadius,
                  borderSide: const BorderSide(color: AppColors.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.cardRadius,
                  borderSide: const BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              onChanged: vm.definirRecherche,
            ),
          ),
        ],
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  const _Pastille({
    required this.libelle,
    required this.active,
    required this.onTap,
  });

  final String libelle;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.pill,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
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
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppColors.outline,
          ),
        ),
      ),
    );
  }
}

class _BoutonDate extends StatelessWidget {
  const _BoutonDate({
    required this.libelle,
    required this.date,
    required this.onChange,
  });

  final String libelle;
  final DateTime date;
  final ValueChanged<DateTime> onChange;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        final choisie = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2020),
          lastDate: DateTime(DateTime.now().year + 1, 12, 31),
          locale: const Locale('fr'),
        );
        if (choisie != null) onChange(choisie);
      },
      icon: const Icon(Symbols.event, size: 15),
      label: Text('$libelle ${Formats.date(date)}'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        foregroundColor: AppColors.onSurface,
        side: const BorderSide(color: AppColors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      ),
    );
  }
}

class _BandeauKpi extends StatelessWidget {
  const _BandeauKpi({required this.vm});

  final InventaireViewModel vm;

  @override
  Widget build(BuildContext context) {
    final inv = vm.inventaire;
    final cartes = [
      KpiCard(
        libelle: 'Valeur Totale du Stock',
        valeur: Formats.montant(inv?.valeurTotale ?? 0),
        accent: AppColors.brandGold,
        icone: Symbols.savings,
        detail: 'Intrants au PMP + produits au coût de revient',
      ),
      KpiCard(
        libelle: 'Dont Intrants',
        valeur: Formats.montant(inv?.valeurIntrants ?? 0),
        accent: AppColors.brandNavy,
        icone: Symbols.inventory_2,
      ),
      KpiCard(
        libelle: 'Dont Produits Finis',
        valeur: Formats.montant(inv?.valeurProduits ?? 0),
        accent: AppColors.brandNavy,
        icone: Symbols.sell,
        // Taire ce que le total exclut le ferait lire comme complet.
        detail: (inv?.produitsNonValorises ?? 0) == 0
            ? null
            : 'Hors ${inv!.produitsNonValorises} article(s) sans coût de '
                  'revient renseigné',
      ),
      KpiCard(
        libelle: 'Animaux sur Pied',
        valeur: '${inv?.effectifTotal ?? 0}',
        accent: AppColors.successDeep,
        icone: Symbols.pets,
        detail: 'Comptés, non valorisés',
      ),
      // Les œufs en incubation ont été retirés du bandeau à la demande de la
      // Gérante : quatre indicateurs, pas cinq. Le compte reste calculé et
      // figure toujours sur l'état imprimé.
    ];

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final carte in cartes) SizedBox(width: 240, child: carte),
      ],
    );
  }
}

/// Signale les lignes dont les mouvements n'expliquent pas le stock.
class _AlerteDesequilibre extends StatelessWidget {
  const _AlerteDesequilibre({required this.vm});

  final InventaireViewModel vm;

  @override
  Widget build(BuildContext context) {
    final lignes = vm.inventaire!.intrantsDesequilibres;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Symbols.warning, size: 20, color: AppColors.errorDeep),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${lignes.length} article(s) dont les mouvements n\'expliquent '
              'pas le stock : ${lignes.map((l) => l.article).join(', ')}. '
              'Un inventaire doit se justifier ligne à ligne — vérifiez les '
              'mouvements de ces articles avant de signer l\'état.',
              style: texteRapport.copyWith(color: AppColors.errorDeep),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cellule de tableau — le texte courant des rapports.
Widget _c(
  String texte, {
  bool gras = false,
  TextAlign? alignement,
  Color? couleur,
}) => Text(
  texte,
  textAlign: alignement,
  style: texteRapport.copyWith(
    fontWeight: gras ? FontWeight.w700 : null,
    color: couleur,
  ),
);

/// Ligne de total, sur fond zébré — c'est la ligne que le comptable lit en
/// premier, elle doit se détacher du corps du tableau.
Widget _total(String libelle, String valeur, int largeurLibelle) =>
    LigneRapport(
      zebre: false,
      couleurFond: AppColors.surfaceZebra,
      cellules: [
        (_c(libelle, gras: true), largeurLibelle),
        (_c(valeur, gras: true, alignement: TextAlign.right), 2),
      ],
    );

class _TableauIntrants extends StatelessWidget {
  const _TableauIntrants({required this.lignes});

  final List<LigneInventaireIntrant> lignes;

  @override
  Widget build(BuildContext context) {
    final total = lignes.fold<double>(0, (s, l) => s + l.valeur);

    return Column(
      children: [
        const EnteteRapport(
          colonnes: [
            ('ARTICLE', 3, TextAlign.left),
            ('CATÉGORIE', 2, TextAlign.left),
            ('STOCK INITIAL', 2, TextAlign.right),
            ('ENTRÉES', 2, TextAlign.right),
            ('SORTIES', 2, TextAlign.right),
            ('STOCK FINAL', 2, TextAlign.right),
            ('PMP', 2, TextAlign.right),
            ('VALEUR', 2, TextAlign.right),
          ],
        ),
        for (var i = 0; i < lignes.length; i++)
          LigneRapport(
            zebre: i.isOdd,
            cellules: [
              (_c('${lignes[i].article}\n${lignes[i].code}'), 3),
              (_c(lignes[i].categorie), 2),
              (
                _c(
                  Formats.nombre(lignes[i].stockInitial),
                  alignement: TextAlign.right,
                ),
                2,
              ),
              (
                _c(
                  lignes[i].entrees == 0
                      ? '—'
                      : '+ ${Formats.nombre(lignes[i].entrees)}',
                  alignement: TextAlign.right,
                  couleur: lignes[i].entrees == 0
                      ? AppColors.outline
                      : AppColors.successDeep,
                ),
                2,
              ),
              (
                _c(
                  lignes[i].sorties == 0
                      ? '—'
                      : '− ${Formats.nombre(lignes[i].sorties)}',
                  alignement: TextAlign.right,
                  couleur: lignes[i].sorties == 0
                      ? AppColors.outline
                      : AppColors.errorDeep,
                ),
                2,
              ),
              (
                _c(
                  '${Formats.nombre(lignes[i].stockFinal)} ${lignes[i].unite}',
                  gras: true,
                  alignement: TextAlign.right,
                ),
                2,
              ),
              (
                _c(Formats.montant(lignes[i].pmp), alignement: TextAlign.right),
                2,
              ),
              (
                _c(
                  Formats.montant(lignes[i].valeur),
                  gras: true,
                  alignement: TextAlign.right,
                ),
                2,
              ),
            ],
          ),
        _total('TOTAL INTRANTS', Formats.montant(total), 15),
      ],
    );
  }
}

class _TableauProduits extends StatelessWidget {
  const _TableauProduits({required this.lignes});

  final List<LigneInventaireProduit> lignes;

  @override
  Widget build(BuildContext context) {
    final total = lignes
        .where((l) => l.estValorise)
        .fold<double>(0, (s, l) => s + l.valeur!);

    return Column(
      children: [
        const EnteteRapport(
          colonnes: [
            ('PRODUIT', 3, TextAlign.left),
            ('CATÉGORIE', 2, TextAlign.left),
            ('STOCK INITIAL', 2, TextAlign.right),
            ('SORTIES (VENTES)', 2, TextAlign.right),
            ('STOCK FINAL', 2, TextAlign.right),
            ('COÛT DE REVIENT', 2, TextAlign.right),
            ('VALEUR', 2, TextAlign.right),
          ],
        ),
        for (var i = 0; i < lignes.length; i++)
          LigneRapport(
            zebre: i.isOdd,
            cellules: [
              (_c('${lignes[i].produit}\n${lignes[i].sku}'), 3),
              (_c(lignes[i].categorie), 2),
              (_c('${lignes[i].stockInitial}', alignement: TextAlign.right), 2),
              (
                _c(
                  lignes[i].sorties == 0
                      ? '—'
                      : '− ${Formats.nombre(lignes[i].sorties)}',
                  alignement: TextAlign.right,
                  couleur: lignes[i].sorties == 0
                      ? AppColors.outline
                      : AppColors.errorDeep,
                ),
                2,
              ),
              (
                _c(
                  '${lignes[i].stockFinal} ${lignes[i].unite}',
                  gras: true,
                  alignement: TextAlign.right,
                ),
                2,
              ),
              (
                _c(
                  lignes[i].estValorise
                      ? Formats.montant(lignes[i].coutRevient!)
                      : 'Non renseigné',
                  alignement: TextAlign.right,
                  couleur: lignes[i].estValorise ? null : AppColors.outline,
                ),
                2,
              ),
              (
                _c(
                  // « Non valorise » et « 0 FCFA » ne disent pas la meme
                  // chose : un total muet se lirait comme un total complet.
                  lignes[i].estValorise
                      ? Formats.montant(lignes[i].valeur!)
                      : 'Non valorisé',
                  gras: lignes[i].estValorise,
                  alignement: TextAlign.right,
                  couleur: lignes[i].estValorise ? null : AppColors.outline,
                ),
                2,
              ),
            ],
          ),
        _total('TOTAL PRODUITS FINIS', Formats.montant(total), 13),
      ],
    );
  }
}

class _TableauEffectifs extends StatelessWidget {
  const _TableauEffectifs({required this.vm});

  final InventaireViewModel vm;

  @override
  Widget build(BuildContext context) {
    final lignes =
        vm.inventaire?.effectifs ?? const <LigneInventaireEffectif>[];

    return Column(
      children: [
        const EnteteRapport(
          colonnes: [
            ('FILIÈRE', 3, TextAlign.left),
            ('EFFECTIF', 2, TextAlign.right),
            ('DERNIÈRE SAISIE', 3, TextAlign.right),
          ],
        ),
        for (var i = 0; i < lignes.length; i++)
          LigneRapport(
            zebre: i.isOdd,
            cellules: [
              (_c(lignes[i].libelle), 3),
              (
                _c(
                  '${lignes[i].effectif}',
                  gras: true,
                  alignement: TextAlign.right,
                ),
                2,
              ),
              (
                _c(
                  // « Jamais saisie » et « effectif nul » ne disent pas la
                  // meme chose : le tableau les distingue.
                  lignes[i].dateSaisie == null
                      ? 'Jamais saisie'
                      : Formats.date(lignes[i].dateSaisie!),
                  alignement: TextAlign.right,
                  couleur: lignes[i].dateSaisie == null
                      ? AppColors.outline
                      : null,
                ),
                3,
              ),
            ],
          ),
        _total(
          'TOTAL ANIMAUX SUR PIED',
          '${vm.inventaire?.effectifTotal ?? 0} sujets',
          6,
        ),
      ],
    );
  }
}
