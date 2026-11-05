import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

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
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/carte_section.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../data/repositories/fiche_elevage_repository_drift.dart';
import '../../data/repositories/soins_repository_drift.dart';
import '../../domain/entities/configuration_espece.dart';
import '../../domain/entities/soin.dart';
import '../../domain/usecases/reporter_deces_infirmerie_usecase.dart';
import '../viewmodels/soins_view_model.dart';
import 'widgets/modales_soins.dart';

class PageSoinsCalendrier extends StatelessWidget {
  const PageSoinsCalendrier({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SoinsViewModel>(
      create: (context) =>
          SoinsViewModel(
            SoinsRepositoryDrift(context.read<AppDatabase>()),
            ReporterDecesInfirmerieUseCase(
              fabriqueFicheElevage(context.read<AppDatabase>()),
            ),
          )..charger(),
      child: const SoinsCalendrierScreen(),
    );
  }
}

/// Soins & Calendrier — Doc F3, fidèle à `soins-calendrier.html`.
///
/// ⚠️ Structure réelle : **3 onglets** (Registre / Doses / Suivi Infirmerie) et
/// 4 KPI qui ne sont **aucun** de ceux que listait Doc F3.
class SoinsCalendrierScreen extends StatefulWidget {
  const SoinsCalendrierScreen({super.key});

  @override
  State<SoinsCalendrierScreen> createState() => _SoinsCalendrierScreenState();
}

class _SoinsCalendrierScreenState extends State<SoinsCalendrierScreen> {
  int _onglet = 0;

  static const List<String> _onglets = [
    'Registre des Soins',
    'Calendrier des Doses',
    'Suivi Infirmerie',
  ];

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SoinsViewModel>();

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
                Symbols.vaccines,
                size: 24,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Soins & Calendrier',
                  style: AppTypography.pageTitle,
                ),
              ),
              BoutonExportPdf(
                construire: () => DocumentsElevage.soins(vm),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Nouveau Soin',
                icon: Symbols.add_circle,
                onPressed: () => _nouveauSoin(context, vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _BandeauKpi(vm: vm),
          if (vm.remanencesActives.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _BanniereRemanence(soins: vm.remanencesActives),
          ],
          const SizedBox(height: AppSpacing.lg),
          // `overflow-x-auto` du prototype : la barre defile plutot que de
          // deborder. Sans lui, un libelle un peu long fait lever
          // `RenderFlex overflowed` a chaque affichage de l'ecran.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _onglets.length; i++)
                  _Onglet(
                    libelle: _onglets[i],
                    actif: i == _onglet,
                    onTap: () => setState(() => _onglet = i),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          switch (_onglet) {
            0 => _OngletRegistre(vm: vm),
            1 => _OngletCalendrier(vm: vm),
            _ => _OngletInfirmerie(vm: vm),
          },
        ],
      ),
    );
  }

  Future<void> _nouveauSoin(BuildContext context, SoinsViewModel vm) async {
    final resultat = await afficherModaleNouveauSoin(context, vm);
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes<Soin>():
        showAppToast(context, 'Soin enregistré avec succès.');
      case Echec<Soin>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

class _BandeauKpi extends StatelessWidget {
  const _BandeauKpi({required this.vm});

  final SoinsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cartes = [
      KpiCard(
        libelle: 'Doses Administrées (Mois)',
        valeur: '${vm.dosesAdministreesMois}',
        accent: AppColors.brandNavy,
        icone: Symbols.vaccines,
      ),
      KpiCard(
        libelle: 'Planifiées à Venir',
        valeur: '${vm.planifieesAVenir}',
        accent: AppColors.brandGold,
        icone: Symbols.event_upcoming,
      ),
      KpiCard(
        libelle: 'En Quarantaine / Traitement',
        valeur: '${vm.enQuarantaineOuTraitement}',
        accent: AppColors.infoBlue,
        icone: Symbols.medication,
      ),
      KpiCard(
        libelle: 'Coût Vétérinaire (Mois)',
        valeur: Formats.nombre(vm.coutVeterinaireMois),
        unite: 'FCFA',
        accent: AppColors.successDeep,
        icone: Symbols.payments,
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

/// Bannière de délai d'attente en cours.
///
/// AJOUT ASSUME : le prototype saisit une « rémanence » mais ne l'exploite
/// jamais. La laisser inerte en ferait une donnée morte, alors qu'elle porte
/// une contrainte commerciale réelle — les produits d'un animal sous délai
/// d'attente ne sont pas vendables.
class _BanniereRemanence extends StatelessWidget {
  const _BanniereRemanence({required this.soins});

  final List<Soin> soins;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        border: Border.all(color: AppColors.errorDeep.withValues(alpha: 0.3)),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Symbols.schedule, size: 18, color: AppColors.errorDeep),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${soins.length} délai(s) d\'attente en cours — produits non '
                  'commercialisables',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.errorDeep,
                  ),
                ),
                for (final soin in soins)
                  Text(
                    '${_libelleEspece(soin.espece)} · ${soin.typeSoin}'
                    '${soin.produit == null ? '' : ' (${soin.produit})'} — '
                    'jusqu\'au ${Formats.date(soin.finRemanence!)}',
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 12,
                      color: AppColors.errorDeep,
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

class _Onglet extends StatelessWidget {
  const _Onglet({
    required this.libelle,
    required this.actif,
    required this.onTap,
  });

  final String libelle;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: actif ? AppColors.brandNavy : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          libelle,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: AppTypography.textXs,
            fontWeight: FontWeight.w700,
            color: actif ? AppColors.brandNavy : AppColors.outline,
          ),
        ),
      ),
    );
  }
}

/// Cellule de tableau — `<td class="text-xs">`, relevé 24 fois dans
/// `soins-calendrier.html`. Voir `AppTypography.textXs`.
const TextStyle _cellule = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: AppTypography.textXs,
  color: AppColors.onSurface,
);

String _libelleEspece(String identifiant) =>
    ConfigurationsEspeces.parIdentifiant[identifiant]?.libelle ?? identifiant;

/// Onglet 1 — registre des soins (l.148-158).
class _OngletRegistre extends StatelessWidget {
  const _OngletRegistre({required this.vm});

  final SoinsViewModel vm;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Registre des Soins',
      action: _Filtres(vm: vm),
      child: vm.soins.isEmpty
          ? const EtatVide(
              message:
                  'Aucun soin enregistré. Utilisez « Nouveau Soin » pour en '
                  'consigner un, ou planifiez une intervention à venir.',
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
                      _entete('Date'),
                      _entete('Lot / Espèce'),
                      _entete('Type d\'action', flex: 2),
                      _entete('Produit'),
                      _entete('Dose'),
                      _entete('Statut', alignement: TextAlign.center),
                      _entete('Actions', alignement: TextAlign.right),
                    ],
                  ),
                ),
                for (var i = 0; i < vm.soins.length; i++)
                  _LigneSoin(soin: vm.soins[i], zebre: i.isOdd, vm: vm),
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
      style: _cellule.copyWith(color: AppColors.outline),
    ),
  );
}

class _LigneSoin extends StatelessWidget {
  const _LigneSoin({
    required this.soin,
    required this.zebre,
    required this.vm,
  });

  final Soin soin;
  final bool zebre;
  final SoinsViewModel vm;

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
          Expanded(child: Text(Formats.date(soin.datePrevue), style: _cellule)),
          Expanded(child: Text(_libelleEspece(soin.espece), style: _cellule)),
          Expanded(flex: 2, child: Text(soin.typeSoin, style: _cellule)),
          Expanded(child: Text(soin.produit ?? '—', style: _cellule)),
          Expanded(child: Text(soin.dose ?? '—', style: _cellule)),
          Expanded(child: Center(child: _BadgeStatut(statut: soin.statut))),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: soin.estEffectue
                  ? Text(
                      'Administré',
                      style: _cellule.copyWith(color: AppColors.outline),
                    )
                  : TextButton(
                      onPressed: () async {
                        final resultat = await vm.confirmerAdministration(soin);
                        if (!context.mounted) return;
                        switch (resultat) {
                          case Succes<void>():
                            showAppToast(context, 'Administration confirmée.');
                          case Echec<void>(message: final m):
                            showAppToast(context, m, type: ToastType.error);
                        }
                      },
                      child: const Text(
                        'Confirmer',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeStatut extends StatelessWidget {
  const _BadgeStatut({required this.statut});

  final String statut;

  @override
  Widget build(BuildContext context) {
    // Code couleur de Doc F3 §2 : Effectué/vert, Planifié/or, En retard/rouge,
    // En cours/bleu.
    final (fond, texte) = switch (statut) {
      StatutSoin.effectue => (
        AppColors.successContainer,
        AppColors.successDeep,
      ),
      StatutSoin.enRetard => (AppColors.errorContainer, AppColors.errorDeep),
      StatutSoin.traitementEnCours => (
        AppColors.infoBlue.withValues(alpha: 0.1),
        AppColors.infoBlue,
      ),
      _ => (
        AppColors.brandGold.withValues(alpha: 0.2),
        AppColors.brandNavy,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(color: fond, borderRadius: AppRadius.pill),
      child: Text(
        statut,
        style: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: texte,
        ),
      ),
    );
  }
}

class _Filtres extends StatelessWidget {
  const _Filtres({required this.vm});

  final SoinsViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: vm.filtreCategorie,
            isDense: true,
            style: _cellule,
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Toutes catégories'),
              ),
              for (final type in TypeSoin.tous)
                DropdownMenuItem(value: type, child: Text(type)),
            ],
            onChanged: vm.definirFiltreCategorie,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        DropdownButtonHideUnderline(
          child: DropdownButton<String?>(
            value: vm.filtreEspece,
            isDense: true,
            style: _cellule,
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Toutes espèces'),
              ),
              for (final config
                  in ConfigurationsEspeces.parIdentifiant.values.toSet())
                DropdownMenuItem(
                  value: config.identifiant,
                  child: Text(config.libelle),
                ),
            ],
            onChanged: vm.definirFiltreEspece,
          ),
        ),
      ],
    );
  }
}

/// Onglet 2 — grille Lot/Bande × jours du mois (l.192-194).
class _OngletCalendrier extends StatelessWidget {
  const _OngletCalendrier({required this.vm});

  final SoinsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final maintenant = DateTime.now();
    final nombreJours = DateTime(
      maintenant.year,
      maintenant.month + 1,
      0,
    ).day;

    // Une ligne par espèce ayant au moins un soin ce mois-ci.
    final especes = vm.soins
        .where(
          (s) =>
              s.datePrevue.year == maintenant.year &&
              s.datePrevue.month == maintenant.month,
        )
        .map((s) => s.espece)
        .toSet()
        .toList();

    return CarteSection(
      titre: 'Calendrier des Doses — ${Formats.date(maintenant).substring(3)}',
      // `soins-calendrier.html` l.177 : l'onglet porte son propre bouton, le
      // seul moyen d'ajouter une echeance depuis le planning.
      action: Builder(
        builder: (ctx) => AppButton(
          label: 'Planifier une Intervention',
          icon: Symbols.add_circle,
          onPressed: () => _planifier(ctx, vm),
        ),
      ),
      child: especes.isEmpty
          ? const EtatVide(
              message:
                  'Aucune intervention programmée ce mois-ci. Le calendrier se '
                  'remplira dès la première planification.',
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _celluleLot('Lot / Bande', entete: true),
                      for (var j = 1; j <= nombreJours; j++)
                        _celluleJour(
                          '$j',
                          aujourdhui: j == maintenant.day,
                          entete: true,
                        ),
                    ],
                  ),
                  for (final espece in especes)
                    Row(
                      children: [
                        _celluleLot(_libelleEspece(espece)),
                        for (var j = 1; j <= nombreJours; j++)
                          _pastilleJour(
                            vm.soins.where(
                              (s) =>
                                  s.espece == espece &&
                                  s.datePrevue.year == maintenant.year &&
                                  s.datePrevue.month == maintenant.month &&
                                  s.datePrevue.day == j,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _planifier(BuildContext context, SoinsViewModel vm) async {
    final resultat = await afficherModalePlanifierIntervention(context, vm);
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes<Soin>(valeur: final soin):
        showAppToast(
          context,
          'Intervention « ${soin.typeSoin} » planifiée pour le '
          '${Formats.date(soin.datePrevue)}.',
        );
      case Echec<Soin>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }

  static Widget _celluleLot(String libelle, {bool entete = false}) => Container(
    width: 160,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm,
    ),
    decoration: BoxDecoration(
      color: entete ? AppColors.surfaceZebra : null,
      border: const Border(
        right: BorderSide(color: AppColors.outlineVariant),
        bottom: BorderSide(color: AppColors.outlineVariant),
      ),
    ),
    child: Text(
      libelle,
      style: _cellule.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: entete ? AppColors.outline : AppColors.brandNavy,
      ),
    ),
  );

  static Widget _celluleJour(
    String libelle, {
    bool aujourdhui = false,
    bool entete = false,
  }) => Container(
    width: 40,
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: aujourdhui
          ? AppColors.brandNavy.withValues(alpha: 0.1)
          : (entete ? AppColors.surfaceZebra : null),
      border: const Border(
        left: BorderSide(color: AppColors.outlineVariant),
        bottom: BorderSide(color: AppColors.outlineVariant),
      ),
    ),
    child: Text(
      libelle,
      style: _cellule.copyWith(
        fontSize: 10,
        fontWeight: aujourdhui ? FontWeight.w800 : FontWeight.w700,
        color: aujourdhui ? AppColors.brandNavy : AppColors.outline,
      ),
    ),
  );

  static Widget _pastilleJour(Iterable<Soin> soins) {
    if (soins.isEmpty) return _celluleJour('');
    final soin = soins.first;
    final couleur = switch (soin.statut) {
      StatutSoin.effectue => AppColors.successDeep,
      StatutSoin.enRetard => AppColors.errorDeep,
      StatutSoin.traitementEnCours => AppColors.infoBlue,
      _ => AppColors.brandGold,
    };

    return Container(
      width: 40,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.outlineVariant),
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Tooltip(
        message: '${soin.typeSoin} — ${soin.statut}',
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// Onglet 3 — infirmerie (l.236-243).
class _OngletInfirmerie extends StatelessWidget {
  const _OngletInfirmerie({required this.vm});

  final SoinsViewModel vm;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Suivi Infirmerie',
      action: AppButton(
        label: 'Nouvelle Entrée',
        icon: Symbols.add_circle,
        height: 32,
        onPressed: () => _nouvelleEntree(context),
      ),
      child: vm.infirmerie.isEmpty
          ? const EtatVide(
              message:
                  'Aucun sujet en infirmerie. Les entrées apparaîtront ici '
                  'avec leur niveau d\'isolement et leur statut.',
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
                      _entete('Date d\'Entrée'),
                      _entete('Lot / Sujet', flex: 2),
                      _entete('Motif', flex: 2),
                      _entete('Niveau d\'Isolement'),
                      _entete('Statut', alignement: TextAlign.center),
                      _entete('Actions', flex: 2, alignement: TextAlign.right),
                    ],
                  ),
                ),
                for (var i = 0; i < vm.infirmerie.length; i++)
                  _LigneInfirmerie(
                    entree: vm.infirmerie[i],
                    zebre: i.isOdd,
                    vm: vm,
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
      style: _cellule.copyWith(color: AppColors.outline),
    ),
  );

  Future<void> _nouvelleEntree(BuildContext context) async {
    final resultat = await afficherModaleEntreeInfirmerie(context, vm);
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes<EntreeInfirmerie>():
        showAppToast(context, 'Entrée d\'infirmerie enregistrée.');
      case Echec<EntreeInfirmerie>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

class _LigneInfirmerie extends StatelessWidget {
  const _LigneInfirmerie({
    required this.entree,
    required this.zebre,
    required this.vm,
  });

  final EntreeInfirmerie entree;
  final bool zebre;
  final SoinsViewModel vm;

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
          Expanded(child: Text(Formats.date(entree.dateEntree), style: _cellule)),
          Expanded(flex: 2, child: Text(entree.sujet, style: _cellule)),
          Expanded(flex: 2, child: Text(entree.motif, style: _cellule)),
          Expanded(child: Text(entree.niveauIsolement, style: _cellule)),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: switch (entree.statut) {
                    StatutInfirmerie.decede => AppColors.errorContainer,
                    StatutInfirmerie.reintegre => AppColors.successContainer,
                    _ => AppColors.infoBlue.withValues(alpha: 0.1),
                  },
                  borderRadius: AppRadius.pill,
                ),
                child: Text(
                  entree.statut,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: switch (entree.statut) {
                      StatutInfirmerie.decede => AppColors.errorDeep,
                      StatutInfirmerie.reintegre => AppColors.successDeep,
                      _ => AppColors.infoBlue,
                    },
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: entree.estEnCours
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _cloturer(
                          context,
                          StatutInfirmerie.reintegre,
                        ),
                        child: const Text(
                          'Réintégrer',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _confirmerDeces(context),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.errorDeep,
                        ),
                        child: const Text(
                          'Décès',
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entree.dateSortie == null
                            ? '—'
                            : 'Clôturé le ${Formats.date(entree.dateSortie!)}',
                        textAlign: TextAlign.right,
                        style: _cellule.copyWith(color: AppColors.outline),
                      ),
                      // Un décès porté sur la fiche et un décès laissé à la
                      // charge de l'animalier ne se distinguent par rien
                      // d'autre. Sans cette mention, personne ne peut savoir
                      // si la perte a déjà été comptée.
                      if (entree.estDecede)
                        Text(
                          entree.reporteEnFiche
                              ? 'Mortalité portée sur la fiche'
                              : 'Mortalité non reportée',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 10,
                            color: entree.reporteEnFiche
                                ? AppColors.successDeep
                                : AppColors.outline,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmerDeces(BuildContext context) async {
    final choix = await afficherModaleConfirmationDeces(context, entree);
    if (choix == null || !context.mounted) return;
    await _cloturer(
      context,
      StatutInfirmerie.decede,
      categorieMortalite: choix.indexCategorie,
    );
  }

  Future<void> _cloturer(
    BuildContext context,
    String statut, {
    int? categorieMortalite,
  }) async {
    final resultat = await vm.cloturerEntree(
      entree: entree,
      statut: statut,
      categorieMortalite: categorieMortalite,
    );
    if (!context.mounted) return;
    switch (resultat) {
      case Succes<void>():
        showAppToast(
          context,
          categorieMortalite == null
              ? 'Entrée clôturée : ${statut.toLowerCase()}.'
              : "Décès enregistré et porté sur la fiche d'élevage.",
        );
      case Echec<void>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}
