import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/resultat/resultat.dart';
import '../../../core/theme/app_breakpoints.dart';
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
import '../../data/repositories/cycle_couveuse_repository_drift.dart';
import '../../domain/entities/cycle_incubation.dart';
import '../viewmodels/cycle_couveuse_view_model.dart';
import 'widgets/modales_couveuse.dart';

/// Point d'entrée de l'écran Cycle Couveuse.
class PageCycleCouveuse extends StatelessWidget {
  const PageCycleCouveuse({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CycleCouveuseViewModel>(
      create: (context) => CycleCouveuseViewModel(
        CycleCouveuseRepositoryDrift(context.read<AppDatabase>()),
      )..charger(),
      child: const CycleCouveuseScreen(),
    );
  }
}

/// Cycle Couveuse — Doc F3, fidèle à `cycle-couveuse.html`.
///
/// ⚠️ Les 4 KPI réels sont **Cycles en Cours / Poussins Attendus / Taux
/// Éclosion Moyen / Taux Perte Moyen** (l.105-120), et non ceux que Doc F3
/// listait.
class CycleCouveuseScreen extends StatelessWidget {
  const CycleCouveuseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CycleCouveuseViewModel>();

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
              const Icon(Symbols.egg, size: 24, color: AppColors.brandGold),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text('Cycle Couveuse', style: AppTypography.pageTitle),
              ),
              _SelecteurReference(vm: vm),
              const SizedBox(width: AppSpacing.sm),
              BoutonExportPdf(
                construire: () => DocumentsElevage.couveuse(vm),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Déclarer un Nouveau Cycle',
                cibleTour: 'bouton-declarer-cycle',
                icon: Symbols.add_circle,
                onPressed: () => _ouvrirCreation(context, vm),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _BandeauKpi(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          // Suivi multi-ages : les echeances passent AVANT le tableau. Sur un
          // couvoir en continu, un mirage oublie ne se rattrape pas.
          if (vm.alertes.isNotEmpty) ...[
            _BandeauAlertes(vm: vm),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (vm.echeancesAVenir.isNotEmpty) ...[
            _ProchainesEcheances(vm: vm),
            const SizedBox(height: AppSpacing.lg),
          ],
          CarteSection(
            titre: 'Parc d\'Incubateurs',
            icone: Symbols.inventory_2,
            action: AppButton(
              label: 'Ajouter un Incubateur',
              icon: Symbols.add,
              variant: AppButtonVariant.outline,
              onPressed: () => _ouvrirCreationMachine(context, vm),
            ),
            child: _ParcIncubateurs(vm: vm),
          ),
          const SizedBox(height: AppSpacing.lg),
          CarteSection(
            titre: 'Lots d\'Incubation',
            cibleTour: 'tableau-cycles',
            action: _Filtres(vm: vm),
            child: vm.cycles.isEmpty
                ? const EtatVide(
                    message:
                        'Aucun cycle d\'incubation enregistré. Utilisez '
                        '« Déclarer un Nouveau Cycle » pour en créer un.',
                  )
                : _TableauCycles(vm: vm),
          ),
        ],
      ),
    );
  }

  Future<void> _ouvrirCreation(
    BuildContext context,
    CycleCouveuseViewModel vm,
  ) async {
    final resultat = await afficherModaleCreationCycle(context, vm);
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes<CycleIncubation>(valeur: final cycle):
        showAppToast(
          context,
          'Cycle ${cycle.code} enregistré avec succès.',
        );
      case Echec<CycleIncubation>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }

  Future<void> _ouvrirCreationMachine(
    BuildContext context,
    CycleCouveuseViewModel vm,
  ) async {
    final resultat = await afficherModaleNouvelleMachine(context, vm);
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes<MachineIncubateur>(valeur: final machine):
        showAppToast(context, 'Incubateur ${machine.code} enregistré.');
      case Echec<MachineIncubateur>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

/// Date de référence — « Situation au … ».
///
/// Tout ce que cet écran affiche est daté : l'âge d'un lot, les échéances
/// atteintes, le TER. Le prototype calculait implicitement à « aujourd'hui »,
/// ce qui interdit de reconstituer l'état du couvoir un jour donné — la
/// question que pose une éclosion décevante : *que valait ce lot au mirage ?*
class _SelecteurReference extends StatelessWidget {
  const _SelecteurReference({required this.vm});

  final CycleCouveuseViewModel vm;

  @override
  Widget build(BuildContext context) {
    final aujourdhui = DateTime.now();
    final estAujourdhui =
        vm.reference.year == aujourdhui.year &&
        vm.reference.month == aujourdhui.month &&
        vm.reference.day == aujourdhui.day;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: () async {
            final choisie = await showDatePicker(
              context: context,
              initialDate: vm.reference,
              firstDate: DateTime(2020),
              lastDate: DateTime(DateTime.now().year + 2, 12, 31),
              locale: const Locale('fr'),
            );
            if (choisie != null) vm.definirReference(choisie);
          },
          icon: const Icon(Symbols.event, size: 16),
          label: Text('Situation au ${Formats.date(vm.reference)}'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            foregroundColor: estAujourdhui
                ? AppColors.onSurface
                : AppColors.brandNavy,
            side: BorderSide(
              color: estAujourdhui
                  ? AppColors.outlineVariant
                  : AppColors.brandGold,
            ),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
          ),
        ),
        if (!estAujourdhui) ...[
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            icon: const Icon(Symbols.today, size: 18),
            tooltip: 'Revenir à aujourd\'hui',
            onPressed: () => vm.definirReference(DateTime.now()),
          ),
        ],
      ],
    );
  }
}

/// Échéances des 3 prochains jours.
///
/// Séparées des alertes à dessein : ce qui est **dû** et ce qui **arrive** ne
/// demandent pas la même chose. Les mélanger ferait perdre l'urgence des
/// premières.
class _ProchainesEcheances extends StatelessWidget {
  const _ProchainesEcheances({required this.vm});

  final CycleCouveuseViewModel vm;

  @override
  Widget build(BuildContext context) {
    final aVenir = vm.echeancesAVenir;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.upcoming,
                size: 20,
                color: AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '${aVenir.length} échéance(s) dans les 3 prochains jours',
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final echeance in aVenir)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.infoBlue,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${echeance.lot.code} · ${echeance.type.libelle} — '
                      '${echeance.type.detail}',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    Formats.date(echeance.dateEcheance),
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.outline,
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

/// Le parc d'incubateurs et leur occupation réelle.
///
/// Une incubation continue suppose plusieurs machines : c'est ce qui permet à
/// des lots d'âges différents de cohabiter. L'occupation compte les **œufs
/// retenus après mirages**, pas les œufs chargés — un œuf clair retiré au J+7
/// ne prend plus de place.
class _ParcIncubateurs extends StatelessWidget {
  const _ParcIncubateurs({required this.vm});

  final CycleCouveuseViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (vm.machines.isEmpty) {
      return const EtatVide(
        message:
            'Aucun incubateur déclaré. Les lots peuvent être suivis sans '
            'machine, mais aucune occupation ne sera calculée.',
      );
    }

    return LayoutBuilder(
      builder: (context, contraintes) {
        final colonnes = AppBreakpoints.estXl(context) ? 3 : 2;
        final largeur =
            (contraintes.maxWidth - AppSpacing.md * (colonnes - 1)) / colonnes;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final machine in vm.machines)
              SizedBox(
                width: largeur,
                child: _CarteMachine(machine: machine, vm: vm),
              ),
          ],
        );
      },
    );
  }
}

class _CarteMachine extends StatelessWidget {
  const _CarteMachine({required this.machine, required this.vm});

  final MachineIncubateur machine;
  final CycleCouveuseViewModel vm;

  @override
  Widget build(BuildContext context) {
    final occupation = vm.occupation(machine.id);
    final lots = vm.tousLesLots
        .where((l) => l.machineId == machine.id && l.estEnCours)
        .length;
    final capacite = machine.capaciteOeufs;
    final remplissage = capacite == null || capacite <= 0
        ? null
        : occupation / capacite;
    final surcharge = remplissage != null && remplissage > 1;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(
          color: surcharge ? AppColors.errorDeep : AppColors.outlineVariant,
        ),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.thermostat,
                size: 18,
                color: AppColors.brandGold,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  machine.code,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
              ),
              Text(
                '$lots lot(s)',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 11,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            machine.libelle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 11,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            capacite == null
                ? '$occupation œufs en incubation'
                : '$occupation / $capacite œufs',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: surcharge ? AppColors.errorDeep : AppColors.onSurface,
            ),
          ),
          if (remplissage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: AppRadius.pill,
              child: LinearProgressIndicator(
                value: remplissage.clamp(0, 1),
                minHeight: 6,
                backgroundColor: AppColors.surfaceZebra,
                valueColor: AlwaysStoppedAnimation(
                  surcharge ? AppColors.errorDeep : AppColors.successDeep,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              surcharge
                  ? 'Capacité annoncée dépassée'
                  : '${Formats.pourcentage(remplissage * 100)} de la capacité',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 10,
                color: surcharge ? AppColors.errorDeep : AppColors.outline,
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Capacité non renseignée — aucun taux de remplissage',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 10,
                color: AppColors.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BandeauKpi extends StatelessWidget {
  const _BandeauKpi({required this.vm});

  final CycleCouveuseViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cartes = [
      KpiCard(
        libelle: 'Cycles en Cours',
        valeur: '${vm.cyclesEnCours}',
        accent: AppColors.brandGold,
        icone: Symbols.egg,
      ),
      KpiCard(
        libelle: 'Poussins Attendus',
        valeur: vm.tauxEclosionMoyen == null ? '—' : '${vm.poussinsAttendus}',
        accent: AppColors.brandNavy,
        icone: Symbols.query_stats,
        detail: vm.tauxEclosionMoyen == null
            ? 'Nécessite au moins une éclosion enregistrée'
            : null,
      ),
      KpiCard(
        libelle: 'Œufs en Incubation',
        valeur: '${vm.oeufsEnIncubation}',
        accent: AppColors.brandNavy,
        icone: Symbols.egg_alt,
        detail: vm.machines.isEmpty
            ? null
            : '${vm.machines.length} incubateur(s)',
      ),
      KpiCard(
        libelle: 'Taux d\'Éclosion Réel',
        // TER pondere par les oeufs RETENUS apres mirages — voir
        // `SuiviIncubation.terMoyenA`. « — » et non « 0 % » : une moyenne sur
        // zero eclosion n'existe pas.
        valeur: vm.tauxEclosionReelMoyen == null
            ? '—'
            : Formats.pourcentage(vm.tauxEclosionReelMoyen!),
        accent: AppColors.successDeep,
        icone: Symbols.check_circle,
        detail: 'Après retrait des œufs clairs et gâtés',
      ),
      KpiCard(
        libelle: 'Taux Brut Moyen',
        valeur: vm.tauxEclosionMoyen == null
            ? '—'
            : Formats.pourcentage(vm.tauxEclosionMoyen!),
        accent: AppColors.brandGold,
        icone: Symbols.trending_down,
        detail: 'Rapporté aux œufs chargés',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // 5 cartes depuis le suivi multi-ages.
        final largeur = (constraints.maxWidth - AppSpacing.md * 4) / 5;
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

/// Bandeau des échéances atteintes ou dépassées.
///
/// Sur un couvoir en incubation continue, plusieurs lots d'âges différents
/// cohabitent : c'est le seul endroit où l'on voit d'un coup ce qui est dû
/// aujourd'hui. Un mirage oublié ne se rattrape pas — l'œuf clair laissé une
/// semaine de plus pourrit et contamine ses voisins.
class _BandeauAlertes extends StatelessWidget {
  const _BandeauAlertes({required this.vm});

  final CycleCouveuseViewModel vm;

  @override
  Widget build(BuildContext context) {
    final alertes = vm.alertes;
    final enRetard = alertes.where((a) => a.estEnRetard).length;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: enRetard > 0
            ? AppColors.errorContainer
            : AppColors.brandGold.withValues(alpha: 0.12),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                enRetard > 0 ? Symbols.warning : Symbols.notifications_active,
                size: 20,
                color: enRetard > 0
                    ? AppColors.errorDeep
                    : AppColors.brandNavy,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  enRetard > 0
                      ? '${alertes.length} échéance(s) du couvoir, dont '
                            '$enRetard en retard'
                      : '${alertes.length} échéance(s) du couvoir aujourd\'hui',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: enRetard > 0
                        ? AppColors.errorDeep
                        : AppColors.brandNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final alerte in alertes.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: alerte.estEnRetard
                          ? AppColors.errorDeep
                          : AppColors.brandGold,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '${alerte.lot.code} · ${alerte.type.libelle} — '
                      '${alerte.type.detail}'
                      '${alerte.lot.machineCode == null ? '' : ' · ${alerte.lot.machineCode}'}',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    alerte.estAujourdhui
                        ? 'aujourd\'hui'
                        : 'depuis ${alerte.joursDecart} j',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: alerte.estEnRetard
                          ? AppColors.errorDeep
                          : AppColors.outline,
                    ),
                  ),
                ],
              ),
            ),
          if (alertes.length > 6)
            Text(
              'et ${alertes.length - 6} autre(s) — voir le tableau ci-dessous.',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 11,
                color: AppColors.outline,
              ),
            ),
        ],
      ),
    );
  }
}

/// Les deux mirages d'un lot : valeur saisie, ou bouton de saisie si l'échéance
/// est atteinte.
class _CellulesMirages extends StatelessWidget {
  const _CellulesMirages({required this.lot, required this.vm});

  final CycleIncubation lot;
  final CycleCouveuseViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Mirage(
          lot: lot,
          vm: vm,
          jour: EspeceCouvable.jourMirage1,
          valeur: lot.oeufsBlancsJ7,
          echeance: lot.dateMirage1,
        ),
        const SizedBox(width: AppSpacing.xs),
        _Mirage(
          lot: lot,
          vm: vm,
          jour: EspeceCouvable.jourMirage2,
          valeur: lot.oeufsGatesJ14,
          echeance: lot.dateMirage2,
        ),
      ],
    );
  }
}

class _Mirage extends StatelessWidget {
  const _Mirage({
    required this.lot,
    required this.vm,
    required this.jour,
    required this.valeur,
    required this.echeance,
  });

  final CycleIncubation lot;
  final CycleCouveuseViewModel vm;
  final int jour;
  final int? valeur;
  final DateTime echeance;

  bool get _premier => jour == EspeceCouvable.jourMirage1;

  @override
  Widget build(BuildContext context) {
    final saisi = valeur != null;
    final du =
        lot.estEnCours &&
        !saisi &&
        !DateTime(
          vm.reference.year,
          vm.reference.month,
          vm.reference.day,
        ).isBefore(DateTime(echeance.year, echeance.month, echeance.day));

    // Trois etats distincts : saisi, du, pas encore. Un « 0 » afficherait la
    // meme chose qu'un mirage fait sans oeuf clair — ce n'est pas pareil.
    final (fond, bordure, encre, texte) = saisi
        ? (
            AppColors.successContainer,
            AppColors.successDeep,
            AppColors.successDeep,
            '$valeur retiré${valeur! > 1 ? 's' : ''}',
          )
        : du
        ? (
            AppColors.errorContainer,
            AppColors.errorDeep,
            AppColors.errorDeep,
            'À saisir',
          )
        : (
            AppColors.surfaceCard,
            AppColors.outlineVariant,
            AppColors.outline,
            Formats.date(echeance),
          );

    return Expanded(
      child: Tooltip(
        message: _premier
            ? 'Mirage 1 (J+${EspeceCouvable.jourMirage1}) — œufs clairs, '
                  'jamais fécondés. Prévu le ${Formats.date(echeance)}.'
            : 'Mirage 2 (J+${EspeceCouvable.jourMirage2}) — œufs gâtés, '
                  'embryon arrêté. Prévu le ${Formats.date(echeance)}.',
        child: InkWell(
          onTap: lot.estEnCours ? () => _saisir(context) : null,
          borderRadius: AppRadius.cardRadius,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            decoration: BoxDecoration(
              color: fond,
              border: Border.all(color: bordure),
              borderRadius: AppRadius.cardRadius,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _premier ? 'MIRAGE 1' : 'MIRAGE 2',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: encre,
                  ),
                ),
                Text(
                  texte,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11,
                    fontWeight: du || saisi
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: encre,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saisir(BuildContext context) async {
    final resultat = await afficherModaleMirage(context, vm, lot, jour);
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes<void>():
        showAppToast(context, 'Mirage enregistré sur ${lot.code}.');
      case Echec<void>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}

class _Filtres extends StatelessWidget {
  const _Filtres({required this.vm});

  final CycleCouveuseViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Deroulant(
          valeur: vm.filtreStatut,
          libelleVide: 'Tous les statuts',
          options: const {'en_cours': 'En cours', 'eclos': 'Éclos'},
          onChange: vm.definirFiltreStatut,
        ),
        const SizedBox(width: AppSpacing.sm),
        _Deroulant(
          valeur: vm.filtreEspece,
          libelleVide: 'Toutes espèces',
          options: {
            for (final e in EspeceCouvable.values) e.identifiant: e.libelle,
          },
          onChange: vm.definirFiltreEspece,
        ),
      ],
    );
  }
}

class _Deroulant extends StatelessWidget {
  const _Deroulant({
    required this.valeur,
    required this.libelleVide,
    required this.options,
    required this.onChange,
  });

  final String? valeur;
  final String libelleVide;
  final Map<String, String> options;
  final ValueChanged<String?> onChange;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: valeur,
        isDense: true,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12,
          color: AppColors.onSurface,
        ),
        items: [
          DropdownMenuItem(value: null, child: Text(libelleVide)),
          for (final entree in options.entries)
            DropdownMenuItem(value: entree.key, child: Text(entree.value)),
        ],
        onChanged: onChange,
      ),
    );
  }
}

class _TableauCycles extends StatelessWidget {
  const _TableauCycles({required this.vm});

  final CycleCouveuseViewModel vm;

  /// ECART_DELIBERE — `cycle-couveuse.html` ne pose **aucune** taille sur ses
  /// cellules : ni sur les `<td>`, ni sur le `<table class="w-full rtable">`,
  /// ni sur aucun de leurs ancetres. Elles heritent donc des **16 px** de la
  /// racine, alors que ses propres en-tetes sont en `text-[12px]` et que 433
  /// des 444 cellules mesurables du prototype sont en `text-xs` (13,6 px).
  ///
  /// Reproduire ces 16 px donnerait, sur ce seul ecran, des cellules plus
  /// grandes que le corps de texte courant et que toutes les autres tables de
  /// l'application. C'est un oubli du prototype, pas une intention : la table
  /// est alignee sur les autres.
  static const TextStyle _cellule = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: AppTypography.textXs,
    color: AppColors.onSurface,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: AppColors.surfaceZebra,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              _entete('Lot', flex: 2),
              _entete('Espèce'),
              _entete('Machine'),
              _entete('Chargés', alignement: TextAlign.right),
              _entete('Âge', alignement: TextAlign.center),
              _entete('Mirages', flex: 2, alignement: TextAlign.center),
              _entete('Éclosion Prévue'),
              _entete('TER', alignement: TextAlign.right),
              _entete('Statut', alignement: TextAlign.center),
              _entete('Actions', flex: 3, alignement: TextAlign.right),
            ],
          ),
        ),
        for (var i = 0; i < vm.cycles.length; i++)
          _Ligne(cycle: vm.cycles[i], zebre: i.isOdd, vm: vm),
      ],
    );
  }

  static Widget _entete(
    String libelle, {
    int flex = 1,
    TextAlign alignement = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        libelle,
        textAlign: alignement,
        style: _cellule.copyWith(color: AppColors.outline),
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
    required this.cycle,
    required this.zebre,
    required this.vm,
  });

  final CycleIncubation cycle;
  final bool zebre;
  final CycleCouveuseViewModel vm;

  /// Vrai si ce lot appartient a une chaine de remplacements — soit qu'il
  /// remplace un lot, soit qu'il a lui-meme ete remplace.
  bool get _aUneLignee =>
      cycle.estSousLot || vm.tousLesLots.any((l) => l.lotParentId == cycle.id);

  @override
  Widget build(BuildContext context) {
    final joursRestants = cycle.joursAvantEclosion(vm.reference);
    final imminente = cycle.estEnCours && joursRestants >= 0 && joursRestants <= 3;

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
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cycle.code,
                  style: _TableauCycles._cellule.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandNavy,
                  ),
                ),
                // Un sous-lot dit de quel lot il reprend la place : c'est
                // l'historique des remplacements, lisible ligne par ligne.
                if (cycle.estSousLot)
                  Text(
                    '↳ remplace ${cycle.lotParentCode ?? '—'}',
                    style: _TableauCycles._cellule.copyWith(
                      fontSize: 10,
                      color: AppColors.outline,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Text(cycle.espece.libelle, style: _TableauCycles._cellule),
          ),
          Expanded(
            child: Text(
              cycle.machineCode ?? '—',
              style: _TableauCycles._cellule.copyWith(
                color: cycle.machineCode == null ? AppColors.outline : null,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${cycle.oeufsCharges}',
              textAlign: TextAlign.right,
              style: _TableauCycles._cellule,
            ),
          ),
          Expanded(
            child: Text(
              cycle.estEnCours
                  ? 'J+${cycle.ageJours(vm.reference)}'
                  : Formats.date(cycle.dateChargement),
              textAlign: TextAlign.center,
              style: _TableauCycles._cellule,
            ),
          ),
          Expanded(flex: 2, child: _CellulesMirages(lot: cycle, vm: vm)),
          Expanded(
            child: Text(
              // Calculee, jamais saisie — duree propre a l'espece.
              Formats.date(cycle.dateEclosionPrevue),
              style: _TableauCycles._cellule.copyWith(
                fontWeight: imminente ? FontWeight.w700 : FontWeight.w400,
                color: imminente ? AppColors.errorDeep : null,
              ),
            ),
          ),
          Expanded(
            child: Text(
              cycle.tauxEclosionReel == null
                  ? '—'
                  : Formats.pourcentage(cycle.tauxEclosionReel!),
              textAlign: TextAlign.right,
              style: _TableauCycles._cellule.copyWith(
                fontWeight: FontWeight.w700,
              ),
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
                  color: switch (cycle.statut) {
                    StatutCycle.enIncubation => AppColors.brandGold.withValues(
                      alpha: 0.2,
                    ),
                    StatutCycle.remplace => AppColors.infoBlue.withValues(
                      alpha: 0.15,
                    ),
                    _ => AppColors.successContainer,
                  },
                  borderRadius: AppRadius.pill,
                ),
                child: Text(
                  cycle.statut,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: switch (cycle.statut) {
                      StatutCycle.enIncubation => AppColors.brandNavy,
                      StatutCycle.remplace => AppColors.infoBlue,
                      _ => AppColors.successDeep,
                    },
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            // flex 3 et non 2 : la colonne porte jusqu'a quatre commandes
            // depuis que l'historique des remplacements s'y ouvre. A flex 2,
            // la rangee debordait de quelques pixels — un `RenderFlex
            // overflowed`, pas un simple defaut d'esthetique.
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // La lignee n'a de sens que s'il y a eu remplacement : un lot
                // seul n'a pas d'historique a montrer.
                if (_aUneLignee)
                  IconButton(
                    icon: const Icon(Symbols.account_tree, size: 18),
                    color: AppColors.brandNavy,
                    tooltip: 'Historique des remplacements',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () => afficherModaleLignee(context, vm, cycle),
                  ),
                if (cycle.estEnCours) ...[
                  // Fond plein rouge, a la demande de la Gerante : c'est
                  // l'action qui cloture le lot et fait entrer les poussins
                  // dans les effectifs. Elle doit se voir du premier coup
                  // d'oeil dans une ligne qui en porte quatre.
                  ElevatedButton(
                    onPressed: () => _ouvrirEclosion(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.errorDeep,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      minimumSize: const Size(0, 30),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.cardRadius,
                      ),
                    ),
                    child: const Text(
                      'Éclosion',
                      style: TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Symbols.edit, size: 18),
                    color: AppColors.infoBlue,
                    tooltip: 'Modifier le lot',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _ouvrirEdition(context),
                  ),
                  IconButton(
                    icon: const Icon(Symbols.delete, size: 18),
                    color: AppColors.errorDeep,
                    tooltip: 'Supprimer le lot',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _ouvrirSuppression(context),
                  ),
                ] else ...[
                  Text(
                    '${cycle.poussinsEclos ?? 0} poussins',
                    textAlign: TextAlign.right,
                    style: _TableauCycles._cellule.copyWith(
                      color: AppColors.outline,
                    ),
                  ),
                  // Un cycle eclos n'est ni modifiable ni supprimable : ses
                  // poussins sont deja dans les effectifs et son taux dans les
                  // statistiques. L'icone dit pourquoi plutot que de laisser
                  // un bouton grise sans explication.
                  const SizedBox(width: AppSpacing.xs),
                  const Tooltip(
                    message:
                        'Un cycle éclos ne se modifie plus : ses poussins sont '
                        'entrés dans les effectifs et son taux d\'éclosion '
                        'dans les statistiques.',
                    child: Icon(
                      Symbols.lock,
                      size: 15,
                      color: AppColors.outline,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _ouvrirEdition(BuildContext context) async {
    final resultat = await afficherModaleEditionCycle(context, vm, cycle);
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes():
        showAppToast(context, 'Cycle ${cycle.code} modifié.');
      case Echec(:final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }

  Future<void> _ouvrirSuppression(BuildContext context) async {
    final resultat = await afficherModaleSuppressionCycle(context, vm, cycle);
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes():
        showAppToast(
          context,
          'Cycle ${cycle.code} supprimé.',
          type: ToastType.warning,
        );
      case Echec(:final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }

  Future<void> _ouvrirEclosion(BuildContext context) async {
    final resultat = await afficherModaleEclosion(context, vm, cycle);
    if (resultat == null || !context.mounted) return;
    switch (resultat) {
      case Succes<void>():
        showAppToast(context, 'Éclosion du cycle ${cycle.code} enregistrée.');
      case Echec<void>(message: final message):
        showAppToast(context, message, type: ToastType.error);
    }
  }
}
