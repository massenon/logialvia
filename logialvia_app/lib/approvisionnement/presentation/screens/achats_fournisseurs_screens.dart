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
import '../viewmodels/approvisionnement_view_model.dart';
import 'widgets/communs_appro.dart';
import '../../../core/saisie/formats_saisie.dart';

/// Achats & Commandes — Doc F5 Écran 2, fidèle à `achats-commandes.html`.
///
/// Flux « panier d'achat » symétrique du POS, mais pour les intrants.
class AchatsScreen extends StatelessWidget {
  const AchatsScreen({super.key});

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
                Symbols.local_shipping,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Achats & Commandes',
                  style: AppTypography.pageTitle,
                ),
              ),
              BoutonExportPdf(construire: () => DocumentsAppro.achats(vm)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _KpiAchats(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: _ChoixIntrants(vm: vm)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _PanierAchat(vm: vm)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            cibleTour: 'achats-tableau',
            titre: 'Commandes',
            child: vm.achats.isEmpty
                ? const EtatVide(
                    message:
                        'Aucune commande enregistrée. Composez un panier '
                        'ci-dessus pour en créer une.',
                  )
                : Column(
                    children: [
                      const EnteteTableauAppro(
                        colonnes: [
                          ('Référence', 2, TextAlign.left),
                          ('Date', 2, TextAlign.left),
                          ('Fournisseur', 3, TextAlign.left),
                          ('Montant', 2, TextAlign.right),
                          ('Mode', 2, TextAlign.left),
                          ('Statut', 2, TextAlign.center),
                          ('Action', 2, TextAlign.right),
                        ],
                      ),
                      for (var i = 0; i < vm.achats.length; i++)
                        () {
                          final a = vm.achats[i];
                          return LigneTableauAppro(
                            zebre: i.isOdd,
                            cellules: [
                              (
                                Text(
                                  a.reference,
                                  style: grasAppro.copyWith(
                                    color: AppColors.brandNavy,
                                  ),
                                ),
                                2,
                              ),
                              (Text(Formats.date(a.date), style: texteAppro), 2),
                              (Text(a.fournisseurNom, style: texteAppro), 3),
                              (
                                Text(
                                  Formats.nombre(a.total),
                                  textAlign: TextAlign.right,
                                  style: texteAppro,
                                ),
                                2,
                              ),
                              (Text(a.mode ?? '—', style: texteAppro), 2),
                              (
                                Center(
                                  child: PastilleAppro(
                                    libelle: a.statut,
                                    fond: a.estLivre
                                        ? AppColors.successContainer
                                        : AppColors.brandGold.withValues(
                                            alpha: 0.2,
                                          ),
                                    couleurTexte: a.estLivre
                                        ? AppColors.successDeep
                                        : AppColors.brandNavy,
                                  ),
                                ),
                                2,
                              ),
                              (
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: a.statut == StatutAchat.commande
                                      ? TextButton(
                                          onPressed: () async {
                                            final r = await vm.receptionner(a);
                                            if (!context.mounted) return;
                                            switch (r) {
                                              case Succes<void>():
                                                showAppToast(
                                                  context,
                                                  'Commande réceptionnée : '
                                                  'stock et PMP mis à jour.',
                                                );
                                              case Echec<void>(
                                                message: final m,
                                              ):
                                                showAppToast(
                                                  context,
                                                  m,
                                                  type: ToastType.error,
                                                );
                                            }
                                          },
                                          child: const Text(
                                            'Réceptionner',
                                            style: TextStyle(
                                              fontFamily:
                                                  AppTypography.fontFamily,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        )
                                      : Text(
                                          a.soldeDu > 0
                                              ? 'Reste ${Formats.nombre(a.soldeDu)} F'
                                              : 'Soldée',
                                          textAlign: TextAlign.right,
                                          style: texteAppro.copyWith(
                                            color: a.soldeDu > 0
                                                ? AppColors.errorDeep
                                                : AppColors.outline,
                                          ),
                                        ),
                                ),
                                2,
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

class _KpiAchats extends StatelessWidget {
  const _KpiAchats({required this.vm});

  final ApprovisionnementViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cartes = [
      KpiCard(
        libelle: 'Commandes en Cours',
        valeur: '${vm.commandesEnCours}',
        accent: AppColors.brandGold,
        icone: Symbols.local_shipping,
      ),
      KpiCard(
        libelle: 'Montant Total Engagé',
        valeur: Formats.nombre(vm.montantTotalEngage),
        unite: 'FCFA',
        accent: AppColors.brandNavy,
        icone: Symbols.request_quote,
        detail: 'Commandes non encore réceptionnées',
      ),
      KpiCard(
        libelle: 'Achats Cumulés (Mois)',
        valeur: Formats.nombre(vm.achatsCumulesMois),
        unite: 'FCFA',
        accent: AppColors.successDeep,
        icone: Symbols.shopping_cart,
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

class _ChoixIntrants extends StatelessWidget {
  const _ChoixIntrants({required this.vm});

  final ApprovisionnementViewModel vm;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Intrants à Commander',
      child: LayoutBuilder(
        builder: (context, constraints) {
          const colonnes = 3;
          final largeur =
              (constraints.maxWidth - AppSpacing.sm * (colonnes - 1)) / colonnes;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final intrant in vm.tousLesIntrants)
                SizedBox(
                  width: largeur,
                  child: InkWell(
                    onTap: () => vm.ajouterAuPanier(intrant),
                    borderRadius: AppRadius.cardRadius,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        border: Border.all(
                          color: intrant.estCritique
                              ? AppColors.errorDeep.withValues(alpha: 0.4)
                              : AppColors.outlineVariant,
                        ),
                        borderRadius: AppRadius.cardRadius,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            intrant.nom,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: grasAppro,
                          ),
                          Text(
                            '${intrant.stock} ${intrant.unite} · seuil '
                            '${intrant.seuil}',
                            style: texteAppro.copyWith(
                              fontSize: 11,
                              color: intrant.estCritique
                                  ? AppColors.errorDeep
                                  : AppColors.outline,
                            ),
                          ),
                          Text(
                            'PMP ${Formats.nombre(intrant.pmp)} F',
                            style: texteAppro.copyWith(
                              color: AppColors.brandNavy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PanierAchat extends StatelessWidget {
  const _PanierAchat({required this.vm});

  final ApprovisionnementViewModel vm;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Panier d\'Achat',
      icone: Symbols.shopping_cart,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (vm.panierVide)
            const EtatVide(
              message: 'Cliquez sur un intrant pour l\'ajouter.',
            )
          else
            for (final ligne in vm.panier)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        ligne.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: texteAppro,
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: TextFormField(
                        initialValue: ligne.quantite.toStringAsFixed(0),
                        keyboardType: TextInputType.number,
                        inputFormatters: FormatteursSaisie.entierPositif,
                        textAlign: TextAlign.center,
                        style: texteAppro,
                        decoration: decorationAppro,
                        onChanged: (v) => vm.changerLignePanier(
                          ligne.intrantCode,
                          quantite: double.tryParse(v) ?? 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 64,
                      child: TextFormField(
                        initialValue: ligne.prixUnitaire.toStringAsFixed(0),
                        keyboardType: TextInputType.number,
                        inputFormatters: FormatteursSaisie.montant,
                        textAlign: TextAlign.center,
                        style: texteAppro,
                        decoration: decorationAppro,
                        onChanged: (v) => vm.changerLignePanier(
                          ligne.intrantCode,
                          prixUnitaire: double.tryParse(v) ?? 0,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => vm.retirerDuPanier(ligne.intrantCode),
                      icon: const Icon(Symbols.close, size: 16),
                      color: AppColors.errorDeep,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
          const Divider(height: AppSpacing.lg),
          const Text('FOURNISSEUR *', style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<int>(
            initialValue: vm.fournisseurSelectionne,
            isExpanded: true,
            decoration: decorationAppro,
            style: texteAppro,
            hint: const Text('-- Sélectionner --', style: texteAppro),
            items: [
              for (final f in vm.fournisseurs)
                DropdownMenuItem(value: f.id, child: Text(f.nom)),
            ],
            onChanged: (v) => vm.fournisseurSelectionne = v,
          ),
          if (vm.fournisseurs.isEmpty)
            Text(
              'Créez d\'abord un fournisseur depuis l\'écran Fournisseurs.',
              style: texteAppro.copyWith(
                fontSize: 11,
                color: AppColors.errorDeep,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: vm.modeAchat,
            isExpanded: true,
            decoration: decorationAppro.copyWith(labelText: 'Mode de règlement'),
            style: texteAppro,
            items: const [
              DropdownMenuItem(value: 'Espèces', child: Text('Espèces')),
              DropdownMenuItem(
                value: 'Mobile Money',
                child: Text('Mobile Money'),
              ),
              DropdownMenuItem(value: 'Crédit', child: Text('Crédit')),
            ],
            onChanged: (v) => vm.modeAchat = v ?? 'Espèces',
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 40,
            child: TextField(
              keyboardType: TextInputType.number,
              inputFormatters: FormatteursSaisie.montant,
              onChanged: (v) => vm.montantRegle = double.tryParse(v) ?? 0,
              style: texteAppro,
              decoration: decorationAppro.copyWith(labelText: 'Montant réglé'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Checkbox(
                value: vm.livreeImmediatement,
                activeColor: AppColors.brandNavy,
                onChanged: (v) => vm.livreeImmediatement = v ?? true,
              ),
              const Expanded(
                child: Text(
                  'Livrée immédiatement (met à jour stock et PMP)',
                  style: texteAppro,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Text('TOTAL', style: AppTypography.label),
              const Spacer(),
              Text(
                Formats.montant(vm.totalPanier),
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandNavy,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Valider la Commande',
            icon: Symbols.local_shipping,
            fullWidth: true,
            height: 44,
            onPressed: vm.panierVide
                ? null
                : () async {
                    final resultat = await vm.validerCommande();
                    if (!context.mounted) return;
                    switch (resultat) {
                      case Succes<Achat>(valeur: final achat):
                        showAppToast(
                          context,
                          'Commande ${achat.reference} enregistrée.',
                        );
                      case Echec<Achat>(message: final m):
                        showAppToast(context, m, type: ToastType.error);
                    }
                  },
          ),
        ],
      ),
    );
  }
}

/// Fournisseurs — Doc F5 Écran 3, fidèle à `fournisseurs.html`.
///
/// ⚠️ **2 tableaux et 4 KPI**, là où Doc F5 n'en décrivait qu'un seul sans KPI.
/// C'est le miroir exact de l'écran Clients & Créances.
class FournisseursScreen extends StatelessWidget {
  const FournisseursScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ApprovisionnementViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    final maintenant = DateTime.now();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.contact_page,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text('Fournisseurs', style: AppTypography.pageTitle),
              ),
              BoutonExportPdf(
                construire: () => DocumentsAppro.fournisseurs(vm),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Ajouter un Fournisseur',
                icon: Symbols.add_circle,
                onPressed: () => _ajouterFournisseur(context, vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _KpiFournisseurs(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Fournisseurs',
            child: vm.fournisseurs.isEmpty
                ? const EtatVide(
                    message:
                        'Aucun fournisseur enregistré. Il en faut au moins un '
                        'pour pouvoir passer une commande.',
                  )
                : Column(
                    children: [
                      const EnteteTableauAppro(
                        colonnes: [
                          ('Nom', 3, TextAlign.left),
                          ('Téléphone', 2, TextAlign.left),
                          ('Fournit', 3, TextAlign.left),
                          ('Commandes', 1, TextAlign.center),
                          ('Total Achats', 2, TextAlign.right),
                          ('Solde Dû', 2, TextAlign.right),
                        ],
                      ),
                      for (var i = 0; i < vm.fournisseurs.length; i++)
                        () {
                          final f = vm.fournisseurs[i];
                          return LigneTableauAppro(
                            zebre: i.isOdd,
                            cellules: [
                              (Text(f.nom, style: grasAppro), 3),
                              (Text(f.telephone ?? '—', style: texteAppro), 2),
                              (Text(f.fournit ?? '—', style: texteAppro), 3),
                              (
                                Center(
                                  child: Text(
                                    '${f.nombreCommandes}',
                                    style: texteAppro,
                                  ),
                                ),
                                1,
                              ),
                              (
                                Text(
                                  Formats.nombre(f.totalAchats),
                                  textAlign: TextAlign.right,
                                  style: texteAppro,
                                ),
                                2,
                              ),
                              (
                                Text(
                                  Formats.nombre(f.soldeDu),
                                  textAlign: TextAlign.right,
                                  style: grasAppro.copyWith(
                                    color: f.aUneDette
                                        ? AppColors.errorDeep
                                        : AppColors.successDeep,
                                  ),
                                ),
                                2,
                              ),
                            ],
                          );
                        }(),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Dettes Fournisseurs',
            icone: Symbols.request_quote,
            couleurIcone: AppColors.errorDeep,
            child: vm.dettes.isEmpty
                ? const EtatVide(
                    message:
                        'Aucune dette ouverte. Les commandes non entièrement '
                        'réglées apparaissent ici.',
                  )
                : Column(
                    children: [
                      const EnteteTableauAppro(
                        colonnes: [
                          ('Fournisseur', 3, TextAlign.left),
                          ('Référence Achat', 2, TextAlign.left),
                          ('Montant Total', 2, TextAlign.right),
                          ('Déjà Réglé', 2, TextAlign.right),
                          ('Solde Dû', 2, TextAlign.right),
                          ('Ancienneté', 1, TextAlign.center),
                          ('Action', 2, TextAlign.right),
                        ],
                      ),
                      for (var i = 0; i < vm.dettes.length; i++)
                        () {
                          final d = vm.dettes[i];
                          return LigneTableauAppro(
                            zebre: i.isOdd,
                            cellules: [
                              (Text(d.fournisseurNom, style: grasAppro), 3),
                              (Text(d.reference, style: texteAppro), 2),
                              (
                                Text(
                                  Formats.nombre(d.total),
                                  textAlign: TextAlign.right,
                                  style: texteAppro,
                                ),
                                2,
                              ),
                              (
                                Text(
                                  Formats.nombre(d.paye),
                                  textAlign: TextAlign.right,
                                  style: texteAppro,
                                ),
                                2,
                              ),
                              (
                                Text(
                                  Formats.nombre(d.soldeDu),
                                  textAlign: TextAlign.right,
                                  style: grasAppro.copyWith(
                                    color: AppColors.errorDeep,
                                  ),
                                ),
                                2,
                              ),
                              (
                                Center(
                                  child: PastilleAppro(
                                    libelle: '${d.ancienneteJours(maintenant)} j',
                                    fond: d.estAncienne(maintenant)
                                        ? AppColors.errorContainer
                                        : AppColors.surfaceZebra,
                                    couleurTexte: d.estAncienne(maintenant)
                                        ? AppColors.errorDeep
                                        : AppColors.outline,
                                  ),
                                ),
                                1,
                              ),
                              (
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => _regler(context, vm, d),
                                    child: const Text(
                                      'Régler',
                                      style: TextStyle(
                                        fontFamily: AppTypography.fontFamily,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                2,
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

  Future<void> _ajouterFournisseur(
    BuildContext context,
    ApprovisionnementViewModel vm,
  ) async {
    final resultat = await AppModal.show<Resultat<Fournisseur>>(
      context,
      title: 'Ajouter un Fournisseur',
      maxWidth: 400,
      child: _FormulaireFournisseur(vm: vm),
    );
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes<Fournisseur>():
        showAppToast(context, 'Fournisseur enregistré.');
      case Echec<Fournisseur>(message: final m):
        showAppToast(context, m, type: ToastType.error);
    }
  }

  Future<void> _regler(
    BuildContext context,
    ApprovisionnementViewModel vm,
    Achat achat,
  ) async {
    final resultat = await AppModal.show<Resultat<void>>(
      context,
      title: 'Régler ${achat.reference}',
      maxWidth: 380,
      child: _FormulaireReglement(vm: vm, achat: achat),
    );
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes<void>():
        showAppToast(context, 'Règlement enregistré.');
      case Echec<void>(message: final m):
        showAppToast(context, m, type: ToastType.error);
    }
  }
}

class _KpiFournisseurs extends StatelessWidget {
  const _KpiFournisseurs({required this.vm});

  final ApprovisionnementViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cartes = [
      KpiCard(
        libelle: 'Fournisseurs Actifs',
        valeur: '${vm.fournisseursActifs}',
        accent: AppColors.brandNavy,
        icone: Symbols.contact_page,
      ),
      KpiCard(
        libelle: 'Dette Totale',
        valeur: Formats.nombre(vm.detteTotale),
        unite: 'FCFA',
        accent: AppColors.errorDeep,
        icone: Symbols.request_quote,
      ),
      KpiCard(
        libelle: 'Achats Cumulés (Mois)',
        valeur: Formats.nombre(vm.achatsCumulesMois),
        unite: 'FCFA',
        accent: AppColors.brandGold,
        icone: Symbols.shopping_cart,
      ),
      KpiCard(
        libelle: 'Dettes Soldées (Mois)',
        valeur: '${vm.dettesSoldeesMois}',
        accent: AppColors.successDeep,
        icone: Symbols.check_circle,
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

class _FormulaireFournisseur extends StatefulWidget {
  const _FormulaireFournisseur({required this.vm});

  final ApprovisionnementViewModel vm;

  @override
  State<_FormulaireFournisseur> createState() => _FormulaireFournisseurState();
}

class _FormulaireFournisseurState extends State<_FormulaireFournisseur> {
  final _nom = TextEditingController();
  final _telephone = TextEditingController();
  final _adresse = TextEditingController();
  final _fournit = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    _adresse.dispose();
    _fournit.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.creerFournisseur(
      nom: _nom.text,
      telephone: _telephone.text,
      adresse: _adresse.text,
      fournit: _fournit.text,
    );
    if (!mounted) return;

    if (resultat is Echec<Fournisseur>) {
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
        ChampAppro(libelle: 'Nom *', controleur: _nom),
        const SizedBox(height: AppSpacing.sm),
        ChampAppro(libelle: 'Téléphone', controleur: _telephone),
        const SizedBox(height: AppSpacing.sm),
        ChampAppro(libelle: 'Adresse', controleur: _adresse),
        const SizedBox(height: AppSpacing.sm),
        ChampAppro(
          libelle: 'Fournit',
          controleur: _fournit,
          note: 'Ex. « Maïs, Soja »',
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

class _FormulaireReglement extends StatefulWidget {
  const _FormulaireReglement({required this.vm, required this.achat});

  final ApprovisionnementViewModel vm;
  final Achat achat;

  @override
  State<_FormulaireReglement> createState() => _FormulaireReglementState();
}

class _FormulaireReglementState extends State<_FormulaireReglement> {
  final _montant = TextEditingController();
  String? _erreur;
  bool _enCours = false;

  @override
  void dispose() {
    _montant.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    setState(() {
      _enCours = true;
      _erreur = null;
    });
    final resultat = await widget.vm.reglerDette(
      reference: widget.achat.reference,
      montant: double.tryParse(_montant.text),
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
          child: Text(
            '${widget.achat.fournisseurNom}\nSolde dû : '
            '${Formats.montant(widget.achat.soldeDu)}',
            style: texteAppro,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ChampAppro(
          libelle: 'Montant Réglé (FCFA) *',
          controleur: _montant,
          clavier: TextInputType.number,
          formatteurs: FormatteursSaisie.montant,
          note: 'Un versement supérieur au solde est borné au reste dû.',
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
