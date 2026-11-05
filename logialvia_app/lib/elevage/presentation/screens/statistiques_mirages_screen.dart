import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/tour/tour_guide.dart';
import '../../../core/widgets/carte_section.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../data/repositories/cycle_couveuse_repository_drift.dart';
import '../../domain/entities/cycle_incubation.dart';
import '../../domain/services/statistiques_mirages.dart';
import '../viewmodels/cycle_couveuse_view_model.dart';

class PageStatistiquesMirages extends StatelessWidget {
  const PageStatistiquesMirages({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CycleCouveuseViewModel>(
      create: (context) => CycleCouveuseViewModel(
        CycleCouveuseRepositoryDrift(context.read<AppDatabase>()),
      )..charger(),
      child: const StatistiquesMiragesScreen(),
    );
  }
}

/// Écran **Statistiques des Mirages** — d'où vient une mauvaise éclosion.
///
/// ## Ce que le TER seul ne dit pas
///
/// Trois causes distinctes se cachent derrière un même taux décevant, et les
/// mirages sont ce qui permet de les séparer :
///
/// - beaucoup de **clairs** au J+7 → œufs jamais fécondés : c'est le troupeau
///   reproducteur qui est en cause, pas la machine ;
/// - beaucoup de **gâtés** au J+14 → embryons démarrés puis arrêtés : c'est la
///   conduite de l'incubation (température, hygrométrie, retournement) ;
/// - peu d'**éclos** sur les œufs retenus → la fin d'incubation.
///
/// Les additionner dans un « taux de perte » unique reviendrait à jeter
/// l'information au moment précis où elle devient utile.
class StatistiquesMiragesScreen extends StatelessWidget {
  const StatistiquesMiragesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CycleCouveuseViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    final stats = StatistiquesMirages(vm.cycles);
    final manquants = stats.miragesManquants(vm.reference);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Symbols.visibility,
                size: 24,
                color: AppColors.brandGold,
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text(
                  'Statistiques des Mirages',
                  style: AppTypography.pageTitle,
                ),
              ),
              _Filtres(vm: vm),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Le mirage sépare ce que le taux d\'éclosion confond : un œuf clair '
            'n\'a jamais été fécondé, un œuf gâté a démarré puis s\'est arrêté. '
            'Le premier accuse les reproducteurs, le second la conduite de la '
            'machine.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          CibleTour(
            nom: 'mirages-kpi',
            child: _BandeauKpi(stats: stats),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (manquants.isNotEmpty) ...[
            _AlerteManquants(lots: manquants),
            const SizedBox(height: AppSpacing.lg),
          ],
          CarteSection(
            titre: 'Détail par lot',
            icone: Symbols.egg,
            cibleTour: 'mirages-tableau',
            child: stats.parLot.isEmpty
                ? const EtatVide(
                    message:
                        'Aucun lot d\'incubation ne correspond à ces filtres.',
                  )
                : _TableauLots(lignes: stats.parLot),
          ),
        ],
      ),
    );
  }
}

class _Filtres extends StatelessWidget {
  const _Filtres({required this.vm});

  final CycleCouveuseViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<String?>(
          value: vm.filtreEspece,
          hint: const Text('Toutes filières', style: _champ),
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem<String?>(
              child: Text('Toutes filières', style: _champ),
            ),
            for (final espece in EspeceCouvable.values)
              DropdownMenuItem<String?>(
                value: espece.identifiant,
                child: Text(espece.libelle, style: _champ),
              ),
          ],
          onChanged: vm.definirFiltreEspece,
        ),
        DropdownButton<int?>(
          value: vm.filtreMachine,
          hint: const Text('Tous incubateurs', style: _champ),
          underline: const SizedBox.shrink(),
          items: [
            const DropdownMenuItem<int?>(
              child: Text('Tous incubateurs', style: _champ),
            ),
            for (final machine in vm.machines)
              DropdownMenuItem<int?>(
                value: machine.id,
                child: Text(machine.code, style: _champ),
              ),
          ],
          onChanged: vm.definirFiltreMachine,
        ),
      ],
    );
  }
}

class _BandeauKpi extends StatelessWidget {
  const _BandeauKpi({required this.stats});

  final StatistiquesMirages stats;

  @override
  Widget build(BuildContext context) {
    String taux(double? valeur) =>
        valeur == null ? '—' : Formats.pourcentage(valeur);

    final cartes = [
      KpiCard(
        libelle: 'Œufs Chargés',
        valeur: '${stats.chargesTotal}',
        accent: AppColors.brandNavy,
        icone: Symbols.egg,
        detail: '${stats.nombreLots} lot(s)',
      ),
      KpiCard(
        libelle: 'Clairs (J+7)',
        valeur: '${stats.clairsTotal}',
        accent: AppColors.errorDeep,
        icone: Symbols.visibility_off,
        // Rapporte aux seuls lots MIRES : sinon un mirage oublie ferait
        // baisser le taux, et la negligence ressemblerait a un bon resultat.
        detail: 'Infertilité ${taux(stats.tauxInfertilite)} — reproducteurs',
      ),
      KpiCard(
        libelle: 'Gâtés (J+14)',
        valeur: '${stats.gatesTotal}',
        accent: AppColors.errorDeep,
        icone: Symbols.heart_broken,
        detail:
            'Mortalité embryonnaire ${taux(stats.mortaliteEmbryonnaire)} — '
            'conduite',
      ),
      KpiCard(
        libelle: 'Œufs Retenus',
        valeur: '${stats.retenusTotal}',
        accent: AppColors.brandGold,
        icone: Symbols.filter_alt,
        detail: 'Après les deux mirages',
      ),
      KpiCard(
        libelle: 'Taux d\'Éclosion Réel',
        valeur: taux(stats.ter),
        accent: AppColors.successDeep,
        icone: Symbols.check_circle,
        detail: 'Éclos ÷ œufs retenus',
      ),
      KpiCard(
        libelle: 'Perte Totale',
        valeur: taux(stats.tauxPerte),
        accent: AppColors.errorDeep,
        icone: Symbols.trending_down,
        detail: 'Sur les lots clôturés seulement',
      ),
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

class _AlerteManquants extends StatelessWidget {
  const _AlerteManquants({required this.lots});

  final List<CycleIncubation> lots;

  @override
  Widget build(BuildContext context) {
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
              '${lots.length} lot(s) attendent un mirage échu : '
              '${lots.map((l) => l.code).join(', ')}. '
              'Tant qu\'il manque, les taux ci-dessus sont faux : un mirage '
              'oublié gonfle le dénominateur du TER et fait passer une bonne '
              'couvée pour une mauvaise.',
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                color: AppColors.errorDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableauLots extends StatelessWidget {
  const _TableauLots({required this.lignes});

  final List<StatistiquesLot> lignes;

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
          child: const Row(
            children: [
              _Entete('Lot', flex: 2),
              _Entete('Espèce'),
              _Entete('Chargés', alignement: TextAlign.right),
              _Entete('Clairs J+7', flex: 2, alignement: TextAlign.right),
              _Entete('Gâtés J+14', flex: 2, alignement: TextAlign.right),
              _Entete('Retenus', alignement: TextAlign.right),
              _Entete('Éclos', alignement: TextAlign.right),
              _Entete('TER', alignement: TextAlign.right),
              _Entete('Perte', alignement: TextAlign.right),
            ],
          ),
        ),
        for (var i = 0; i < lignes.length; i++)
          _Ligne(stat: lignes[i], zebre: i.isOdd),
      ],
    );
  }
}

class _Entete extends StatelessWidget {
  const _Entete(
    this.libelle, {
    this.flex = 1,
    this.alignement = TextAlign.left,
  });

  final String libelle;
  final int flex;
  final TextAlign alignement;

  @override
  Widget build(BuildContext context) => Expanded(
    flex: flex,
    child: Text(libelle, textAlign: alignement, style: AppTypography.caption),
  );
}

class _Ligne extends StatelessWidget {
  const _Ligne({required this.stat, required this.zebre});

  final StatistiquesLot stat;
  final bool zebre;

  @override
  Widget build(BuildContext context) {
    Widget cellule(
      String texte, {
      int flex = 1,
      TextAlign alignement = TextAlign.left,
      Color? couleur,
      bool gras = false,
    }) => Expanded(
      flex: flex,
      child: Text(
        texte,
        textAlign: alignement,
        style: _TableauLots._cellule.copyWith(
          color: couleur,
          fontWeight: gras ? FontWeight.w700 : null,
        ),
      ),
    );

    String avecTaux(int? valeur, double? taux) {
      // « — » et non « 0 » : un mirage non fait ne dit pas qu'il n'y avait
      // aucun oeuf clair.
      if (valeur == null) return 'Non mirés';
      return taux == null
          ? '$valeur'
          : '$valeur  (${Formats.pourcentage(taux)})';
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: zebre ? AppColors.surfaceZebra : AppColors.surfaceCard,
        border: const Border(
          bottom: BorderSide(color: AppColors.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          cellule(stat.lot.code, flex: 2, gras: true),
          cellule(stat.lot.espece.libelle),
          cellule('${stat.charges}', alignement: TextAlign.right),
          cellule(
            avecTaux(stat.clairs, stat.tauxInfertilite),
            flex: 2,
            alignement: TextAlign.right,
            couleur: stat.mirage1Fait ? AppColors.errorDeep : AppColors.outline,
          ),
          cellule(
            avecTaux(stat.gates, stat.mortaliteEmbryonnaire),
            flex: 2,
            alignement: TextAlign.right,
            couleur: stat.mirage2Fait ? AppColors.errorDeep : AppColors.outline,
          ),
          cellule(
            '${stat.retenus}',
            alignement: TextAlign.right,
            gras: true,
          ),
          cellule(
            stat.eclos == null ? '—' : '${stat.eclos}',
            alignement: TextAlign.right,
            couleur: stat.eclos == null ? AppColors.outline : null,
          ),
          cellule(
            stat.ter == null ? '—' : Formats.pourcentage(stat.ter!),
            alignement: TextAlign.right,
            gras: true,
            couleur: stat.ter == null
                ? AppColors.outline
                : AppColors.successDeep,
          ),
          cellule(
            stat.tauxPerte == null
                ? '—'
                : Formats.pourcentage(stat.tauxPerte!),
            alignement: TextAlign.right,
            couleur: stat.tauxPerte == null
                ? AppColors.outline
                : AppColors.errorDeep,
          ),
        ],
      ),
    );
  }
}

const TextStyle _champ = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 12,
  color: AppColors.onSurface,
);
