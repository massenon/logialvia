import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../../core/formatage/formats.dart';
import '../../../../core/resultat/resultat.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_modal.dart';
import '../../../domain/entities/livraison.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/tour/tour_guide.dart';
import '../../../../core/widgets/carte_section.dart';
import '../../../../core/widgets/icone_symbole.dart';
import '../../../domain/entities/produit_vendable.dart';
import '../../../domain/entities/vente.dart';
import '../../../../administration/presentation/viewmodels/modules_actifs_view_model.dart';
import '../../viewmodels/ventes_view_model.dart';
import 'modale_facture_vente.dart';
import '../../../../core/saisie/formats_saisie.dart';

/// Onglet 1 — Enregistrer Vente (POS) — Doc H1 §Onglet 1.
///
/// Disposition 2 colonnes : grille produits 2/3, panier 1/3.
class OngletPos extends StatelessWidget {
  const OngletPos({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _GrilleProduits()),
        SizedBox(width: AppSpacing.md),
        Expanded(child: _Panier()),
      ],
    );
  }
}

class _GrilleProduits extends StatelessWidget {
  const _GrilleProduits();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VentesViewModel>();

    return CarteSection(
      titre: 'Produits',
      cibleTour: 'grille-produits',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    onChanged: vm.definirRecherche,
                    style: _texte,
                    decoration: _decoration.copyWith(
                      hintText: 'Rechercher un produit…',
                      prefixIcon: const Icon(Symbols.search, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: vm.filtreCategorie,
                  isExpanded: true,
                  decoration: _decoration,
                  style: _texte,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Toutes catégories'),
                    ),
                    for (final categorie in vm.categories)
                      DropdownMenuItem(
                        value: categorie,
                        child: Text(categorie),
                      ),
                  ],
                  onChanged: vm.definirCategorie,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (vm.produitsFiltres.isEmpty)
            const EtatVide(message: 'Aucun produit ne correspond à ce filtre.')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const colonnes = 3;
                final largeur =
                    (constraints.maxWidth - AppSpacing.sm * (colonnes - 1)) /
                    colonnes;
                return Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final produit in vm.produitsFiltres)
                      SizedBox(
                        width: largeur,
                        child: _CarteProduit(produit: produit),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _CarteProduit extends StatelessWidget {
  const _CarteProduit({required this.produit});

  final ProduitVendable produit;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<VentesViewModel>();
    // Carte desactivee et grisee si le stock est epuise (Doc H1 §Onglet 1).
    final epuise = produit.estEpuise;

    return Opacity(
      opacity: epuise ? 0.5 : 1,
      child: InkWell(
        // Un clic n'ajoute JAMAIS directement : il ouvre la modale « Vente a
        // la Piece », ou la quantite et le montant global sont negocies
        // (`handleProductClick()` du prototype).
        onTap: epuise
            ? null
            : () => ouvrirModaleVenteALaPiece(context, vm, produit),
        borderRadius: AppRadius.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            border: Border.all(color: AppColors.outlineVariant),
            borderRadius: AppRadius.cardRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    IconeSymbole.depuisNom(produit.icone),
                    size: 18,
                    color: AppColors.brandNavy,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: produit.estCritique
                          ? AppColors.errorContainer
                          : AppColors.successContainer,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(
                      epuise ? 'Rupture' : '${produit.stock}',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: produit.estCritique
                            ? AppColors.errorDeep
                            : AppColors.successDeep,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                produit.nom,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _texte.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${produit.categorie} · ${produit.unite}',
                style: _texte.copyWith(fontSize: 11, color: AppColors.outline),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                produit.aUneFourchette
                    ? '${Formats.nombre(produit.prix)} – ${Formats.nombre(produit.prixMax!)} F'
                    : '${Formats.nombre(produit.prix)} F',
                style: _texte.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Panier extends StatelessWidget {
  const _Panier();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<VentesViewModel>();

    return CarteSection(
      titre: 'Panier',
      icone: Symbols.shopping_cart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (vm.panierVide)
            const EtatVide(
              message: 'Panier vide. Cliquez sur un produit pour l\'ajouter.',
            )
          else
            for (var i = 0; i < vm.panier.length; i++)
              _LignePanier(ligne: vm.panier[i], index: i),
          const Divider(height: AppSpacing.lg),
          SizedBox(
            height: 40,
            child: TextField(
              onChanged: (v) => vm.client = v,
              style: _texte,
              decoration: _decoration.copyWith(
                labelText: 'Client',
                hintText: 'Client Comptant',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          CibleTour(
            nom: 'mode-reglement',
            child: DropdownButtonFormField<String>(
              initialValue: vm.mode,
              isExpanded: true,
              decoration: _decoration.copyWith(labelText: 'Mode de règlement'),
              style: _texte,
              items: [
                for (final mode in ModeReglement.tous)
                  DropdownMenuItem(value: mode, child: Text(mode)),
              ],
              onChanged: (v) => vm.mode = v ?? ModeReglement.especes,
            ),
          ),
          // `#modal-account-select` du prototype ouvrait une modale pour faire
          // choisir parmi une seule ligne codee en dur, sans rien conserver.
          // La ligne vient de Parametres Generaux (Telephone Principal) et est
          // copiee sur la vente : la montrer suffit, la faire choisir non.
          if (vm.mode == ModeReglement.mobileMoney) ...[
            const SizedBox(height: AppSpacing.xs),
            _BandeauLigneMomo(vm: vm),
          ],
          const SizedBox(height: AppSpacing.sm),
          // Second sélecteur, ajouté après l'arbitrage de la Gérante : « Avance »
          // était jusqu'ici une troisième valeur du mode de règlement, ce qui
          // empêchait de savoir *avec quoi* une avance avait été versée.
          // Voir `ConditionPaiement`.
          DropdownButtonFormField<String>(
            initialValue: vm.condition,
            isExpanded: true,
            decoration: _decoration.copyWith(
              labelText: 'Condition de paiement',
            ),
            style: _texte,
            items: [
              for (final condition in ConditionPaiement.toutes)
                DropdownMenuItem(value: condition, child: Text(condition)),
            ],
            onChanged: (v) => vm.condition = v ?? ConditionPaiement.comptant,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 40,
            child: TextField(
              keyboardType: TextInputType.number,
              inputFormatters: FormatteursSaisie.montant,
              onChanged: (v) => vm.montantRecu = double.tryParse(v) ?? 0,
              style: _texte,
              decoration: _decoration.copyWith(
                labelText: vm.estAvance
                    ? 'Montant reçu (avance) *'
                    : 'Montant reçu',
              ),
            ),
          ),
          // « Payable le » — n'apparait que sur une vente a credit : une vente
          // comptant est soldee a l'encaissement, il n'y a rien a echoir.
          if (vm.estAvance) ...[
            const SizedBox(height: AppSpacing.sm),
            _ChampEcheance(vm: vm),
          ],
          const SizedBox(height: AppSpacing.sm),
          BoutonLivraison(vm: vm),
          const SizedBox(height: AppSpacing.md),
          // Le supplement n'apparait que s'il existe : afficher « + 0 F » sur
          // toutes les ventes serait du bruit.
          if ((vm.livraison?.supplementFacture ?? 0) > 0) ...[
            Row(
              children: [
                Text(
                  'Sous-total',
                  style: _texte.copyWith(color: AppColors.outline),
                ),
                const Spacer(),
                Text(
                  Formats.nombre(vm.totalLignes),
                  style: _texte.copyWith(color: AppColors.outline),
                ),
              ],
            ),
            Row(
              children: [
                Text(
                  'Livraison facturée',
                  style: _texte.copyWith(color: AppColors.outline),
                ),
                const Spacer(),
                Text(
                  '+ ${Formats.nombre(vm.livraison!.supplementFacture)}',
                  style: _texte.copyWith(color: AppColors.outline),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Row(
            children: [
              const Text('TOTAL', style: AppTypography.label),
              const Spacer(),
              Text(
                Formats.montant(vm.totalPanier),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.successDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Encaisser la Vente',
            icon: Symbols.point_of_sale,
            fullWidth: true,
            height: 44,
            onPressed: vm.panierVide ? null : () => _encaisser(context, vm),
          ),
        ],
      ),
    );
  }

  Future<void> _encaisser(BuildContext context, VentesViewModel vm) async {
    final resultat = await vm.encaisser();
    if (!context.mounted) return;
    switch (resultat) {
      case Succes<Vente>(valeur: final vente):
        showAppToast(
          context,
          'Vente ${vente.reference} enregistrée — '
          '${Formats.montant(vente.total)}.',
        );
        // La facture se remet au client pendant qu'il est encore au comptoir :
        // c'est le seul moment ou elle sert a quelque chose.
        await ouvrirModaleFactureVente(
          context,
          vente,
          mecefActif: context.read<ModulesActifsViewModel>().estActif('mecef'),
        );
      case Echec<Vente>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

class _LignePanier extends StatelessWidget {
  const _LignePanier({required this.ligne, required this.index});

  final int index;

  final LignePanier ligne;

  @override
  Widget build(BuildContext context) {
    final vm = context.read<VentesViewModel>();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ligne.nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _texte.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  // Quantite ET montant global — jamais « prix unitaire x qte ».
                  '${Formats.nombre(ligne.quantite)} ${ligne.unite ?? 'u'}',
                  style: _texte.copyWith(
                    fontSize: 11,
                    color: AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
          Text(
            Formats.nombre(ligne.montantGlobal),
            style: _texte.copyWith(fontWeight: FontWeight.w700),
          ),
          IconButton(
            onPressed: () => ouvrirModaleVenteALaPiece(
              context,
              vm,
              null,
              ligneAModifier: ligne,
              indexAModifier: index,
            ),
            icon: const Icon(Symbols.edit, size: 16),
            color: AppColors.brandNavy,
            visualDensity: VisualDensity.compact,
            tooltip: 'Modifier la quantité ou le montant',
          ),
          IconButton(
            onPressed: () => vm.retirerLigne(index),
            icon: const Icon(Symbols.close, size: 16),
            color: AppColors.errorDeep,
            visualDensity: VisualDensity.compact,
            tooltip: 'Retirer',
          ),
        ],
      ),
    );
  }
}

/// Champ « Payable le » — date d'exigibilité d'une vente à crédit.
///
/// Absent du prototype, qui affiche pourtant une colonne « Échéance » dans ses
/// rapports en la remplissant avec la **date de vente**. Toute créance née la
/// veille y était donc « En Retard », et la lettre de relance imprimée depuis
/// ce tableau réclamait un paiement non échu.
///
/// Le délai des Paramètres Généraux pré-remplit la date ; la caissière peut
/// l'écraser. **S'il n'est pas configuré, rien n'est proposé** : la créance
/// reste « Sans échéance » et ne sera jamais réclamée — l'encart le dit, plutôt
/// que de laisser croire à un oubli.
class _ChampEcheance extends StatelessWidget {
  const _ChampEcheance({required this.vm});

  final VentesViewModel vm;

  @override
  Widget build(BuildContext context) {
    final echeance = vm.echeance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: InkWell(
            onTap: () async {
              final choix = await showDatePicker(
                context: context,
                initialDate: echeance ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                locale: const Locale('fr'),
              );
              if (choix != null) vm.echeance = choix;
            },
            child: InputDecorator(
              decoration: _decoration.copyWith(labelText: 'Payable le'),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      echeance == null
                          ? 'Aucune échéance'
                          : Formats.date(echeance),
                      style: echeance == null
                          ? _texte.copyWith(color: AppColors.outline)
                          : _texte,
                    ),
                  ),
                  if (echeance != null)
                    InkWell(
                      onTap: () => vm.echeance = null,
                      child: const Icon(
                        Symbols.close,
                        size: 16,
                        color: AppColors.outline,
                      ),
                    )
                  else
                    const Icon(
                      Symbols.calendar_month,
                      size: 16,
                      color: AppColors.outline,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (vm.echeanceNonFixee) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            vm.delaiPaiementParDefaut == null
                ? 'Sans échéance, cette créance ne sera jamais signalée en '
                      'retard. Un délai par défaut se règle dans Paramètres '
                      'Généraux.'
                : 'Sans échéance, cette créance ne sera jamais signalée en '
                      'retard.',
            style: _texte.copyWith(
              fontSize: 11,
              height: 1.4,
              color: AppColors.outline,
            ),
          ),
        ],
      ],
    );
  }
}

/// Ligne Mobile Money creditee — remplace `#modal-account-select`.
///
/// Le prototype ouvre une modale bloquante pour choisir parmi **une seule**
/// ligne, codee en dur, et jette le choix. Le numero est en realite le
/// « Telephone Principal » de Parametres Generaux : il est affiche ici, et
/// copie sur la vente (`VENTES.ligneMobileMoney`). Le jour ou plusieurs lignes
/// existeront, ce bandeau redeviendra un selecteur.
class _BandeauLigneMomo extends StatelessWidget {
  const _BandeauLigneMomo({required this.vm});

  final VentesViewModel vm;

  @override
  Widget build(BuildContext context) {
    final manquante = vm.ligneMobileMoneyManquante;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: manquante
            ? AppColors.errorContainer
            : AppColors.brandGold.withValues(alpha: 0.1),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          Icon(
            manquante ? Symbols.warning : Symbols.smartphone,
            size: 16,
            color: manquante ? AppColors.errorDeep : AppColors.brandNavy,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              manquante
                  ? 'Aucun numéro Mobile Money enregistré — renseignez le '
                        'Téléphone Principal dans Paramètres Généraux.'
                  : 'Ligne créditée : ${vm.ligneMobileMoney}',
              style: _texte.copyWith(
                fontSize: 11,
                height: 1.4,
                color: manquante ? AppColors.errorDeep : AppColors.brandNavy,
              ),
            ),
          ),
        ],
      ),
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

/// Modale « Vente à la Pièce » — `#modal-weight` de `ventes.html`.
///
/// ## Le point que cette modale existe pour garantir
///
/// Elle demande **deux valeurs indépendantes** : la quantité, dans l'unité du
/// produit, et le **montant global de la vente**. Sa note, reprise mot pour mot
/// du prototype, dit pourquoi : « saisissez directement le montant total
/// convenu — jamais un prix unitaire multiplié automatiquement. Le prix
/// indicatif n'est qu'une fourchette de référence. »
///
/// Sur un marché de Natitingou le prix d'un sujet se négocie ; le catalogue ne
/// fournit qu'une fourchette (`prix` / `prixMax`, Doc D1). Un panier qui
/// multiplierait la quantité par le prix du catalogue facturerait un montant
/// que personne n'a convenu.
///
/// Passer [ligneAModifier] et [indexAModifier] ouvre la modale en modification
/// (`editWeightLine()` du prototype) ; sinon [produit] est ajouté au panier.
Future<void> ouvrirModaleVenteALaPiece(
  BuildContext context,
  VentesViewModel vm,
  ProduitVendable? produit, {
  LignePanier? ligneAModifier,
  int? indexAModifier,
}) async {
  final enModification = ligneAModifier != null && indexAModifier != null;

  final nom = enModification ? ligneAModifier.nom : produit!.nom;
  final unite = enModification
      ? (ligneAModifier.unite ?? 'u')
      : (produit!.unite);
  final fourchette = enModification
      ? ligneAModifier.libelleFourchette
      : (produit!.prixMax == null
            ? Formats.nombre(produit.prix)
            : '${Formats.nombre(produit.prix)} à '
                  '${Formats.nombre(produit.prixMax!)}');

  final quantiteCtrl = TextEditingController(
    text: enModification ? Formats.nombre(ligneAModifier.quantite) : '1',
  );
  final montantCtrl = TextEditingController(
    text: enModification
        ? ligneAModifier.montantGlobal.round().toString()
        : produit!.prix.round().toString(),
  );

  await AppModal.show<void>(
    context,
    title: 'Vente à la Pièce',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          enModification
              ? '$nom — modification'
              : '$nom — prix indicatif $fourchette FCFA',
          style: _texte.copyWith(color: AppColors.outline),
        ),
        const SizedBox(height: AppSpacing.md),
        // Le libelle porte l'unite reelle du produit : « Quantite (u) »,
        // « Quantite (sujet(s)) »… (`weight-qty-label` du prototype).
        Text('QUANTITÉ ($unite)', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: quantiteCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: FormatteursSaisie.entierPositif,
          autofocus: !enModification,
          style: _texte,
          decoration: _decoration.copyWith(hintText: 'ex : 2'),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'MONTANT GLOBAL DE LA VENTE (FCFA)',
          style: AppTypography.label,
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: montantCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: FormatteursSaisie.montant,
          style: _texte.copyWith(fontWeight: FontWeight.w700),
          decoration: _decoration.copyWith(hintText: 'ex : 4500'),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Vente à la pièce : saisissez directement le montant total convenu — '
          'jamais un prix unitaire multiplié automatiquement. Le prix '
          'indicatif n\'est qu\'une fourchette de référence.',
          style: _texte.copyWith(
            fontSize: 11,
            color: AppColors.outline,
            height: 1.5,
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
          label: enModification ? 'Enregistrer' : 'Ajouter au panier',
          onPressed: () {
            final quantite = double.tryParse(
              quantiteCtrl.text.trim().replaceAll(',', '.'),
            );
            final montant = double.tryParse(
              montantCtrl.text.trim().replaceAll(',', '.'),
            );

            if (quantite == null ||
                quantite <= 0 ||
                montant == null ||
                montant <= 0) {
              showAppToast(
                ctx,
                'Veuillez saisir une quantité et un montant valides.',
                type: ToastType.error,
              );
              return;
            }

            final erreur = enModification
                ? vm.modifierLigne(
                    indexAModifier,
                    quantite: quantite,
                    montantGlobal: montant,
                  )
                : vm.ajouterAuPanier(
                    produit!,
                    quantite: quantite,
                    montantGlobal: montant,
                  );

            if (erreur != null) {
              showAppToast(ctx, erreur, type: ToastType.error);
              return;
            }

            Navigator.of(ctx).pop();
            showAppToast(
              ctx,
              enModification ? 'Ligne modifiée.' : '$nom ajouté au panier.',
            );
          },
        ),
      ),
    ],
  );

  quantiteCtrl.dispose();
  montantCtrl.dispose();
}

/// Bouton « Livraison concernée » — `#livraison-toggle-btn` de `ventes.html`,
/// avec sa pastille ✓ verte quand une livraison est renseignée.
class BoutonLivraison extends StatelessWidget {
  const BoutonLivraison({super.key, required this.vm});

  final VentesViewModel vm;

  @override
  Widget build(BuildContext context) {
    final active = vm.livraisonConcernee;

    return InkWell(
      onTap: () => ouvrirModaleLivraison(context, vm),
      borderRadius: AppRadius.pill,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: AppRadius.pill,
          border: Border.all(
            color: active ? AppColors.successDeep : AppColors.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Symbols.local_shipping,
              size: 16,
              color: AppColors.brandNavy,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                active
                    ? 'Livraison — ${vm.livraison!.mode.libelle}'
                    : 'Livraison concernée',
                overflow: TextOverflow.ellipsis,
                style: _texte.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
            ),
            if (active) ...[
              const SizedBox(width: AppSpacing.xs),
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.successDeep,
                ),
                child: const Icon(Symbols.check, size: 11, color: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Modale « Livraison » — `#modal-livraison`.
///
/// ⚠️ Voir [Livraison] : le prototype affiche cette modale mais
/// `validateSale()` n'en lit **aucun** champ. Ici tout est persisté sur la
/// vente, et les frais d'une livraison facturée séparément entrent réellement
/// dans le total.
Future<void> ouvrirModaleLivraison(
  BuildContext context,
  VentesViewModel vm,
) async {
  var concernee = vm.livraisonConcernee;
  var mode = vm.livraison?.mode ?? ModeLivraison.gratuite;
  final fraisCtrl = TextEditingController(
    text: vm.livraison?.frais == null
        ? ''
        : vm.livraison!.frais!.round().toString(),
  );
  final adresseCtrl = TextEditingController(text: vm.livraison?.adresse ?? '');
  final contactCtrl = TextEditingController(text: vm.livraison?.contact ?? '');

  await AppModal.show<void>(
    context,
    title: 'Livraison',
    child: StatefulBuilder(
      builder: (ctx, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => concernee = !concernee),
            child: Row(
              children: [
                Checkbox(
                  value: concernee,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => setState(() => concernee = v ?? false),
                ),
                Expanded(
                  child: Text(
                    'Livraison concernée (cages, sujets volumineux)',
                    style: _texte.copyWith(color: AppColors.outline),
                  ),
                ),
              ],
            ),
          ),
          if (concernee) ...[
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<ModeLivraison>(
              initialValue: mode,
              isExpanded: true,
              style: _texte,
              decoration: _decoration,
              items: [
                for (final m in ModeLivraison.values)
                  DropdownMenuItem(
                    value: m,
                    child: Text(m.libelle, style: _texte),
                  ),
              ],
              onChanged: (v) =>
                  setState(() => mode = v ?? ModeLivraison.gratuite),
            ),
            // Le champ de frais n'apparait qu'en mode « facturee », comme
            // `onDeliveryModeChange()` du prototype.
            if (mode == ModeLivraison.facturee) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: fraisCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: FormatteursSaisie.montant,
                style: _texte,
                decoration: _decoration.copyWith(
                  hintText: 'Frais de livraison (FCFA)',
                  helperText: 'Ces frais s\'ajoutent au total de la vente.',
                  helperStyle: _texte.copyWith(
                    fontSize: 11,
                    color: AppColors.outline,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: adresseCtrl,
              style: _texte,
              decoration: _decoration.copyWith(
                hintText: 'Adresse de livraison',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: contactCtrl,
              style: _texte,
              decoration: _decoration.copyWith(
                hintText: 'Contact du transporteur',
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      Builder(
        builder: (ctx) => AppButton(
          label: 'Valider',
          onPressed: () {
            if (!concernee) {
              vm.definirLivraison(null);
              Navigator.of(ctx).pop();
              return;
            }

            final erreur = vm.definirLivraison(
              Livraison(
                mode: mode,
                frais: double.tryParse(
                  fraisCtrl.text.trim().replaceAll(',', '.'),
                ),
                adresse: adresseCtrl.text.trim().isEmpty
                    ? null
                    : adresseCtrl.text.trim(),
                contact: contactCtrl.text.trim().isEmpty
                    ? null
                    : contactCtrl.text.trim(),
              ),
            );

            if (erreur != null) {
              showAppToast(ctx, erreur, type: ToastType.error);
              return;
            }
            Navigator.of(ctx).pop();
          },
        ),
      ),
    ],
  );

  fraisCtrl.dispose();
  adresseCtrl.dispose();
  contactCtrl.dispose();
}
