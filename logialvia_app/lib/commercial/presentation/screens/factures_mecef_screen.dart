import 'package:material_ui/material_ui.dart';
import '../../../core/sync/planificateur_synchronisation.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/saisie/formats_saisie.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/tour/tour_guide.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_modal.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../data/repositories/factures_mecef_repository_drift.dart';
import '../../domain/entities/facture_mecef.dart';
import '../viewmodels/factures_mecef_view_model.dart';
import 'documents_mecef.dart';

/// Écran Facturation MeCeF — factures de vente et factures d'avoir.
///
/// ## Pourquoi un écran séparé du point de vente
///
/// Encaisser et facturer ne sont pas le même geste. La caisse enregistre un
/// paiement ; la facture engage l'entreprise devant l'administration fiscale.
/// Les mélanger obligerait à facturer chaque vente au comptoir, y compris
/// celles dont le client ne veut pas de facture — et rendrait l'émission d'un
/// avoir impossible sans toucher à la vente d'origine.
class PageFacturesMecef extends StatelessWidget {
  const PageFacturesMecef({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (ctx) => FacturesMecefViewModel(
        FacturesMecefRepositoryDrift(ctx.read<AppDatabase>()),
        ctx.read<AppDatabase>(),
        // Une facture émise au web se transmet après réservation au serveur (`47a2_`).
        reserverTransmission: _reservation(ctx),
      )..charger(),
      child: const _Ecran(),
    );
  }
}

/// La réservation du moteur de synchronisation, s'il existe (absent des tests d'écran).
Future<Resultat<void>> Function(String)? _reservation(BuildContext ctx) {
  try {
    return ctx.read<PlanificateurSynchronisation>().moteur.reserverTransmission;
  } on ProviderNotFoundException {
    return null;
  }
}

class _Ecran extends StatelessWidget {
  const _Ecran();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FacturesMecefViewModel>();

    if (vm.chargement && vm.factures.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EnTete(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          if (!vm.transmissionConfiguree) ...[
            const _BandeauTransmissionNonConfiguree(),
            const SizedBox(height: AppSpacing.lg),
          ],
          CibleTour(
            nom: 'mecef-kpi',
            child: _BandeauKpi(vm: vm),
          ),
          const SizedBox(height: AppSpacing.lg),
          CibleTour(
            nom: 'mecef-filtres',
            child: _BarreFiltres(vm: vm),
          ),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Factures et avoirs',
            icone: Symbols.receipt_long,
            cibleTour: 'mecef-tableau',
            child: vm.facturesFiltrees.isEmpty
                ? EtatVide(
                    message: vm.factures.isEmpty
                        ? 'Aucune facture émise. Utilisez « Émettre une '
                              'Facture » pour facturer une vente encaissée.'
                        : 'Aucune facture ne correspond à ces filtres.',
                  )
                : _TableauFactures(vm: vm),
          ),
        ],
      ),
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.vm});

  final FacturesMecefViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Symbols.receipt_long, size: 24, color: AppColors.brandGold),
        const SizedBox(width: AppSpacing.xs),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Facturation MeCeF', style: AppTypography.pageTitle),
              Text(
                'Factures de vente et factures d\'avoir, conformité fiscale.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
        ),
        CibleTour(
          nom: 'mecef-emettre',
          child: AppButton(
            label: 'Émettre une Facture',
            icon: Symbols.post_add,
            onPressed: () => _ouvrirEmission(context, vm),
          ),
        ),
      ],
    );
  }
}

/// Bandeau d'avertissement quand la transmission automatique n'est pas prête.
class _BandeauTransmissionNonConfiguree extends StatelessWidget {
  const _BandeauTransmissionNonConfiguree();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.brandGold),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.warning, size: 18, color: AppColors.brandGold),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Transmission e-MECeF non configurée. Les factures sont émises '
              'et imprimables, mais restent « À transmettre » : elles ne '
              'valent pas facture normalisée. Renseignez l\'URL du service et '
              'le jeton dans Paramètres Général, ou reportez le code de '
              'normalisation à la main une fois la facture transmise.',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.brandGold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BandeauKpi extends StatelessWidget {
  const _BandeauKpi({required this.vm});

  final FacturesMecefViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cartes = [
      KpiCard(
        libelle: 'Facturé Net',
        valeur: Formats.montant(vm.totalFactureNet),
        accent: AppColors.brandGold,
        icone: Symbols.payments,
        detail: 'Factures de vente moins avoirs',
      ),
      KpiCard(
        libelle: 'À Transmettre',
        valeur: '${vm.nombreATransmettre}',
        accent: AppColors.brandGold,
        icone: Symbols.pending,
        detail: 'Non encore normalisées',
      ),
      KpiCard(
        libelle: 'Normalisées',
        valeur: '${vm.nombreNormalisees}',
        accent: AppColors.successDeep,
        icone: Symbols.verified,
        detail: 'Code MeCeF reçu de la DGI',
      ),
      KpiCard(
        libelle: 'Rejetées',
        valeur: '${vm.nombreRejetees}',
        accent: AppColors.errorDeep,
        icone: Symbols.error,
        detail: 'Transmission refusée',
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < cartes.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(child: cartes[i]),
        ],
      ],
    );
  }
}

class _BarreFiltres extends StatelessWidget {
  const _BarreFiltres({required this.vm});

  final FacturesMecefViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: vm.definirRecherche,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
            ),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Symbols.search, size: 18),
              hintText: 'Rechercher une référence ou un client…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        for (final statut in [null, ...StatutFacture.values]) ...[
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: ChoiceChip(
              label: Text(
                statut?.libelle ?? 'Toutes',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                ),
              ),
              selected: vm.filtreStatut == statut,
              onSelected: (_) => vm.definirFiltreStatut(statut),
            ),
          ),
        ],
      ],
    );
  }
}

class _TableauFactures extends StatelessWidget {
  const _TableauFactures({required this.vm});

  final FacturesMecefViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _EnteteTableau(),
        for (final f in vm.facturesFiltrees) _LigneFacture(facture: f, vm: vm),
      ],
    );
  }
}

class _EnteteTableau extends StatelessWidget {
  const _EnteteTableau();

  static const TextStyle _style = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppColors.outline,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('RÉFÉRENCE', style: _style)),
          Expanded(flex: 2, child: Text('DATE', style: _style)),
          Expanded(flex: 3, child: Text('CLIENT', style: _style)),
          Expanded(
            flex: 3,
            child: Text('TOTAL TTC', style: _style, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 3,
            // Le montant est cale a droite : sans cette marge, son en-tete et
            // celui du statut se touchaient et se lisaient « TOTAL TTCSTATUT ».
            child: Padding(
              padding: EdgeInsets.only(left: AppSpacing.md),
              child: Text('STATUT', style: _style),
            ),
          ),
          Expanded(flex: 4, child: Text('ACTIONS', style: _style)),
        ],
      ),
    );
  }
}

class _LigneFacture extends StatelessWidget {
  const _LigneFacture({required this.facture, required this.vm});

  final FactureMecef facture;
  final FacturesMecefViewModel vm;

  static const TextStyle _texte = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 12,
    color: AppColors.onSurface,
  );

  @override
  Widget build(BuildContext context) {
    final estAvoir = facture.type == TypeFacture.avoir;
    final signe = estAvoir ? -1 : 1;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  estAvoir ? Symbols.undo : Symbols.description,
                  size: 16,
                  color: estAvoir ? AppColors.errorDeep : AppColors.brandNavy,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    facture.reference,
                    style: _texte.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(Formats.date(facture.date), style: _texte),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  facture.client,
                  style: _texte,
                  overflow: TextOverflow.ellipsis,
                ),
                if (facture.origineRef != null)
                  Text(
                    'sur ${facture.origineRef}',
                    style: _texte.copyWith(
                      fontSize: 10,
                      color: AppColors.outline,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              Formats.montant(signe * facture.totalTtc),
              style: _texte.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.right,
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: _Pastille(facture: facture),
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                BoutonExportPdf(
                  construire: () => DocumentsMecef.facture(facture),
                ),
                if (facture.estDUnAutrePoste && !facture.estNormalisee)
                  const Tooltip(
                    message: FacturesMecefViewModel.messageAutrePoste,
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      child: Icon(
                        Symbols.devices,
                        size: 18,
                        color: AppColors.outline,
                      ),
                    ),
                  ),
                if (!facture.estNormalisee && !facture.estDUnAutrePoste)
                  _ActionIcone(
                    tooltip: 'Transmettre à e-MECeF',
                    icone: Symbols.cloud_upload,
                    onPressed: () => _transmettre(context, vm, facture),
                  ),
                if (!facture.estNormalisee && !facture.estDUnAutrePoste)
                  _ActionIcone(
                    tooltip: 'Saisir le code de normalisation',
                    icone: Symbols.edit_note,
                    onPressed: () => _ouvrirNormalisation(context, vm, facture),
                  ),
                if (facture.type == TypeFacture.vente)
                  _ActionIcone(
                    tooltip: 'Émettre un avoir',
                    icone: Symbols.undo,
                    couleur: AppColors.errorDeep,
                    onPressed: () => _ouvrirAvoir(context, vm, facture),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La pastille de statut. Une facture rejetée affiche **pourquoi** au survol :
/// un statut sans explication laisse l'utilisatrice sans recours.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.facture});

  final FactureMecef facture;

  @override
  Widget build(BuildContext context) {
    final (couleur, fond) = switch (facture.statut) {
      StatutFacture.normalisee => (
        AppColors.successDeep,
        AppColors.successContainer,
      ),
      StatutFacture.rejetee => (AppColors.errorDeep, AppColors.errorContainer),
      StatutFacture.aTransmettre => (
        AppColors.brandGold,
        AppColors.surfaceZebra,
      ),
    };

    final pastille = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: fond, borderRadius: AppRadius.pill),
      child: Text(
        facture.statut.libelle,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: couleur,
        ),
      ),
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: facture.erreurTransmission == null
          ? pastille
          : Tooltip(message: facture.erreurTransmission!, child: pastille),
    );
  }
}

// ---------------------------------------------------------------- actions

Future<void> _transmettre(
  BuildContext context,
  FacturesMecefViewModel vm,
  FactureMecef facture,
) async {
  final resultat = await vm.transmettre(facture.reference);
  if (!context.mounted) return;
  switch (resultat) {
    case Succes<void>():
      showAppToast(context, 'Facture ${facture.reference} normalisée.');
    case Echec<void>(message: final message):
      showAppToast(context, message, type: ToastType.error);
  }
}

/// Émission d'une facture à partir d'une vente encaissée.
Future<void> _ouvrirEmission(
  BuildContext context,
  FacturesMecefViewModel vm,
) async {
  if (vm.ventesSansFacture.isEmpty) {
    showAppToast(
      context,
      'Toutes les ventes encaissées sont déjà facturées.',
      type: ToastType.error,
    );
    return;
  }

  var venteRef = vm.ventesSansFacture.first.ref;
  final ifu = TextEditingController();
  final adresse = TextEditingController();

  await AppModal.show<void>(
    context,
    title: 'Émettre une facture de vente',
    maxWidth: 560,
    child: StatefulBuilder(
      builder: (ctx, rafraichir) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Etiquette('Vente à facturer *'),
          DropdownButtonFormField<String>(
            initialValue: venteRef,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.onSurface,
            ),
            items: [
              for (final v in vm.ventesSansFacture)
                DropdownMenuItem(
                  value: v.ref,
                  child: Text(
                    '${v.ref} — ${v.client} — ${Formats.montant(v.total)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (valeur) =>
                rafraichir(() => venteRef = valeur ?? venteRef),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Etiquette('IFU du client'),
          TextField(
            controller: ifu,
            inputFormatters: FormatteursSaisie.entierPositif,
            style: _saisie,
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'Facultatif — un particulier n\'en a pas',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _Etiquette('Adresse du client'),
          TextField(
            controller: adresse,
            style: _saisie,
            decoration: const InputDecoration(isDense: true),
          ),
        ],
      ),
    ),
    actions: [
      Builder(
        builder: (ctx) => AppButton(
          label: 'Émettre la Facture',
          icon: Symbols.post_add,
          onPressed: () async {
            final resultat = await vm.emettrePourVente(
              venteRef: venteRef,
              clientIfu: ifu.text.trim().isEmpty ? null : ifu.text.trim(),
              clientAdresse: adresse.text.trim().isEmpty
                  ? null
                  : adresse.text.trim(),
            );
            if (!ctx.mounted) return;
            switch (resultat) {
              case Succes<FactureMecef>(valeur: final facture):
                Navigator.of(ctx).pop();
                showAppToast(ctx, 'Facture ${facture.reference} émise.');
              case Echec<FactureMecef>(message: final message):
                showAppToast(ctx, message, type: ToastType.error);
            }
          },
        ),
      ),
    ],
  );

  ifu.dispose();
  adresse.dispose();
}

/// Émission d'un avoir sur une facture existante.
Future<void> _ouvrirAvoir(
  BuildContext context,
  FacturesMecefViewModel vm,
  FactureMecef origine,
) async {
  final motif = TextEditingController();

  await AppModal.show<void>(
    context,
    title: 'Émettre un avoir sur ${origine.reference}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.errorContainer,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Text(
            'L\'avoir reprend l\'intégralité de la facture '
            '${origine.reference} : ${Formats.montant(origine.totalTtc)} TTC. '
            'La facture d\'origine n\'est pas modifiée — elle est '
            'contrepassée.',
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.errorDeep,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _Etiquette('Motif de l\'avoir *'),
        TextField(
          controller: motif,
          maxLines: 2,
          style: _saisie,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Erreur de facturation, retour, annulation…',
          ),
        ),
      ],
    ),
    actions: [
      Builder(
        builder: (ctx) => AppButton(
          label: 'Émettre l\'Avoir',
          icon: Symbols.undo,
          variant: AppButtonVariant.danger,
          onPressed: () async {
            final resultat = await vm.emettreAvoir(
              factureOrigine: origine.reference,
              motif: motif.text,
            );
            if (!ctx.mounted) return;
            switch (resultat) {
              case Succes<FactureMecef>(valeur: final avoir):
                Navigator.of(ctx).pop();
                showAppToast(ctx, 'Avoir ${avoir.reference} émis.');
              case Echec<FactureMecef>(message: final message):
                showAppToast(ctx, message, type: ToastType.error);
            }
          },
        ),
      ),
    ],
  );

  motif.dispose();
}

/// Report manuel du retour de la DGI.
Future<void> _ouvrirNormalisation(
  BuildContext context,
  FacturesMecefViewModel vm,
  FactureMecef facture,
) async {
  final code = TextEditingController(text: facture.codeMecef ?? '');
  final nim = TextEditingController(text: facture.nim ?? vm.mecefNim ?? '');
  final compteur = TextEditingController(text: facture.compteur ?? '');
  final lien = TextEditingController(text: facture.lienVerification ?? '');

  await AppModal.show<void>(
    context,
    title: 'Normalisation de ${facture.reference}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceZebra,
            borderRadius: AppRadius.cardRadius,
          ),
          child: const Text(
            'Reportez ici ce que la DGI a rendu. Sans code ni NIM réels, la '
            'facture reste « À transmettre » : le document imprimé le dit, et '
            'c\'est ce qui protège l\'entreprise.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.outline,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _Etiquette('Code MeCeF/DGI *'),
        TextField(
          controller: code,
          style: _saisie,
          decoration: const InputDecoration(isDense: true),
        ),
        const SizedBox(height: AppSpacing.md),
        const _Etiquette('NIM *'),
        TextField(
          controller: nim,
          style: _saisie,
          decoration: const InputDecoration(isDense: true),
        ),
        const SizedBox(height: AppSpacing.md),
        const _Etiquette('Compteur'),
        TextField(
          controller: compteur,
          style: _saisie,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Tel quel : 12/50',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _Etiquette('Lien de vérification'),
        TextField(
          controller: lien,
          style: _saisie,
          decoration: const InputDecoration(isDense: true),
        ),
      ],
    ),
    actions: [
      Builder(
        builder: (ctx) => AppButton(
          label: 'Enregistrer',
          icon: Symbols.verified,
          onPressed: () async {
            final resultat = await vm.normaliserManuellement(
              reference: facture.reference,
              codeMecef: code.text,
              nim: nim.text,
              compteur: compteur.text.trim().isEmpty
                  ? null
                  : compteur.text.trim(),
              lienVerification: lien.text.trim().isEmpty
                  ? null
                  : lien.text.trim(),
            );
            if (!ctx.mounted) return;
            switch (resultat) {
              case Succes<void>():
                Navigator.of(ctx).pop();
                showAppToast(ctx, 'Facture ${facture.reference} normalisée.');
              case Echec<void>(message: final message):
                showAppToast(ctx, message, type: ToastType.error);
            }
          },
        ),
      ),
    ],
  );

  code.dispose();
  nim.dispose();
  compteur.dispose();
  lien.dispose();
}

const TextStyle _saisie = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 12,
  color: AppColors.onSurface,
);

class _Etiquette extends StatelessWidget {
  const _Etiquette(this.texte);

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        texte,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
        ),
      ),
    );
  }
}

/// Un bouton d'action de tableau, ramené à son icône.
///
/// Un `IconButton` Material impose 48x48 et 8 px de marge de chaque côté :
/// quatre d'entre eux sur une ligne de tableau débordent. Le même correctif
/// avait déjà été nécessaire sur la colonne Actions du Cycle Couveuse.
class _ActionIcone extends StatelessWidget {
  const _ActionIcone({
    required this.tooltip,
    required this.icone,
    required this.onPressed,
    this.couleur,
  });

  final String tooltip;
  final IconData icone;
  final VoidCallback onPressed;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icone, size: 18, color: couleur),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }
}
