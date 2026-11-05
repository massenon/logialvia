import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../administration/presentation/viewmodels/modules_actifs_view_model.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/carte_section.dart';
import '../../domain/repositories/tableau_bord_repository.dart';
import '../../../core/pdf/bouton_export_pdf.dart';
import '../../../core/database/app_database.dart';
import '../../../core/tour/tour_guide.dart';
import '../../../elevage/data/repositories/fiche_elevage_repository_drift.dart';
import '../../../elevage/data/repositories/soins_repository_drift.dart';
import '../../../elevage/domain/usecases/reporter_deces_infirmerie_usecase.dart';
import '../../../elevage/presentation/screens/widgets/modale_prophylaxie_du_jour.dart';
import '../../data/repositories/tableau_bord_repository_drift.dart';
import '../../../elevage/presentation/viewmodels/soins_view_model.dart';
import '../viewmodels/dashboard_elevage_view_model.dart';
import 'documents_pilotage.dart';
import '../viewmodels/tableau_bord_view_model.dart';
import 'dashboard_screen.dart' show ModulesActifsSeederEspeces;
import 'widgets/panneaux_pilotage.dart';

/// Dashboard Élevage — Doc F2 Ecran 2, fidele a `elevage-dashboard.html`.
class DashboardElevageScreen extends StatefulWidget {
  const DashboardElevageScreen({super.key});

  @override
  State<DashboardElevageScreen> createState() => _DashboardElevageScreenState();
}

class _DashboardElevageScreenState extends State<DashboardElevageScreen> {
  /// Cartes d'apercu des filieres non activees — elevage-dashboard.html
  /// l.141-148, l.164-171, l.187-194. Libelles repris mot pour mot.
  static const List<
    ({String moduleId, String titre, IconData icone, String texte})
  >
  _apercus = [
    (
      moduleId: 'cuniculture',
      titre: 'Lapins',
      icone: Symbols.cruelty_free,
      texte: 'Filière Cuniculture disponible — non activée pour le moment.',
    ),
    (
      moduleId: 'aviculture_classique',
      titre: 'Poulets / Pondeuses',
      icone: Symbols.egg_alt,
      texte:
          'Filière aviculture classique disponible — non activée pour le moment.',
    ),
    (
      moduleId: 'pisciculture',
      titre: 'Poissons-Chats',
      icone: Symbols.set_meal,
      texte: 'Filière Pisciculture disponible — non activée pour le moment.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final modules = context.read<ModulesActifsViewModel>();
      final especes = {
        ...TableauBordViewModel.especesPermanentes,
        for (final entree in ModulesActifsSeederEspeces.parModule.entries)
          if (modules.estActif(entree.key)) entree.value,
      };
      context.read<DashboardElevageViewModel>().charger(especes);
      _rappelProphylaxie();
    });
  }

  /// `prophylaxie-popup.js` l.4 : « Portee : dashboard.html et
  /// elevage-dashboard.html uniquement ». Le report est partage entre les deux
  /// ecrans — voir `ProphylaxieDuJour`.
  Future<void> _rappelProphylaxie() async {
    final base = context.read<AppDatabase>();
    // Les echeances non planifiees sont calculees par le depot du tableau de
    // bord : cet ecran-ci n'a pas de ViewModel d'alertes a lui.
    final rappels = await TableauBordRepositoryDrift(
      base,
    ).rappelsProphylaxie(DateTime.now());
    if (!mounted) return;

    final vm = SoinsViewModel(
      SoinsRepositoryDrift(base),
      ReporterDecesInfirmerieUseCase(fabriqueFicheElevage(base)),
    );
    try {
      await vm.charger();
      if (!mounted) return;
      await ProphylaxieDuJour.ouvrirSiNecessaire(context, vm, rappels: rappels);
    } finally {
      vm.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DashboardElevageViewModel>();
    final modules = context.watch<ModulesActifsViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EnTete(vm: vm),
          const SizedBox(height: AppSpacing.lg),
          CibleTour(
            nom: 'cartes-filieres-elevage',
            child: _GrilleCartes(vm: vm, modules: modules, apercus: _apercus),
          ),
          const SizedBox(height: AppSpacing.lg),
          _LigneMoitie(
            gauche: const CibleTour(
              nom: 'comparaison-croissance',
              child: _PanneauGmq(),
            ),
            droite: _PanneauRappelsVeterinaires(soins: vm.prochainsSoins),
          ),
          const SizedBox(height: AppSpacing.lg),
          _LigneMoitie(
            gauche: CarteSection(
              titre: 'Alertes Sanitaires du Jour',
              icone: Symbols.coronavirus,
              couleurIcone: AppColors.errorDeep,
              child: vm.alertesSanitaires.isEmpty
                  ? const EtatVide(
                      message:
                          'Aucune alerte sanitaire : aucun soin en retard, '
                          'aucun intrant sous son seuil.',
                    )
                  : Column(
                      children: [
                        for (final alerte in vm.alertesSanitaires) ...[
                          PanneauAlertes(alertes: [alerte]),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
                    ),
            ),
            droite: _BilanEconomique(vm: vm),
          ),
        ],
      ),
    );
  }
}

class _EnTete extends StatelessWidget {
  const _EnTete({required this.vm});

  final DashboardElevageViewModel vm;

  @override
  Widget build(BuildContext context) {
    // Dette Doc E9 levee : le bouton « Exporter PDF » du prototype
    // (`generateOfficialPDF()` de common.js) est desormais reel.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Symbols.monitoring, size: 24, color: AppColors.brandNavy),
        const SizedBox(width: AppSpacing.xs),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard Élevage',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandNavy,
                ),
              ),
              Text(
                'Vue consolidée — filières actives et couveuse en un seul écran.',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
        ),
        BoutonExportPdf(
          construire: () => DocumentsPilotage.dashboardElevage(vm),
        ),
      ],
    );
  }
}

class _GrilleCartes extends StatelessWidget {
  const _GrilleCartes({
    required this.vm,
    required this.modules,
    required this.apercus,
  });

  final DashboardElevageViewModel vm;
  final ModulesActifsViewModel modules;
  final List<({String moduleId, String titre, IconData icone, String texte})>
  apercus;

  @override
  Widget build(BuildContext context) {
    final cartes = <Widget>[
      for (final filiere in vm.filieres) CarteFiliere(filiere: filiere),
      if (vm.couveuse != null) CarteCouveuse(couveuse: vm.couveuse!),
      for (final apercu in apercus)
        if (!modules.estActif(apercu.moduleId))
          _CarteApercuModule(
            titre: apercu.titre,
            icone: apercu.icone,
            texte: apercu.texte,
          ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const colonnes = 3; // `md:grid-cols-3`
        final largeur =
            (constraints.maxWidth - AppSpacing.md * (colonnes - 1)) / colonnes;
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

/// Carte d'apercu d'une filiere non activee : bordure en tirets, cadenas, et
/// lien vers l'ecran d'activation.
class _CarteApercuModule extends StatelessWidget {
  const _CarteApercuModule({
    required this.titre,
    required this.icone,
    required this.texte,
  });

  final String titre;
  final IconData icone;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Opacity(
                opacity: 0.6,
                child: Row(
                  children: [
                    Icon(icone, size: 20, color: AppColors.outline),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      titre,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(
                Symbols.lock,
                size: 18,
                color: AppColors.outlineVariant,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            texte,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          InkWell(
            onTap: () => context.go('/parametres/generaux'),
            child: const Text(
              'Activer depuis Paramètres →',
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                color: AppColors.brandNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanneauGmq extends StatelessWidget {
  const _PanneauGmq();

  @override
  Widget build(BuildContext context) {
    // Le GMQ (Gain Moyen Quotidien) suppose un suivi de poids. Doc F3 §2 liste
    // bien un champ « Poids Général » dans le formulaire de saisie journaliere,
    // mais **Doc D1 ne prevoit aucune colonne de poids** dans `FICHE_JOURNEE` :
    // la donnee n'a nulle part ou etre stockee. Le graphique du prototype est
    // un `<svg>` a points ecrits en dur (elevage-dashboard.html l.201-209), il
    // ne prouve donc pas l'existence de la donnee. Section conservee avec un
    // etat explicite plutot que remplie d'une courbe inventee.
    return const CarteSection(
      titre: 'Gain Moyen Quotidien (GMQ) par Espèce — 4 Dernières Semaines',
      child: EtatVide(
        message:
            'Le GMQ nécessite un suivi de poids par journée. Le modèle de '
            'données (Doc D1, FICHE_JOURNEE) ne comporte aujourd\'hui aucune '
            'colonne de poids, alors que le formulaire de saisie de Doc F3 en '
            'prévoit un champ — écart signalé, à trancher avant l\'implémentation '
            'du module Élevage.',
      ),
    );
  }
}

class _PanneauRappelsVeterinaires extends StatelessWidget {
  const _PanneauRappelsVeterinaires({required this.soins});

  final List<ProchainSoin> soins;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Rappels Vétérinaires à Venir',
      icone: Symbols.event_repeat,
      couleurIcone: AppColors.infoBlue,
      child: soins.isEmpty
          ? const EtatVide(
              message:
                  'Aucune échéance vétérinaire planifiée. Les rappels '
                  'apparaîtront dès la première intervention programmée.',
            )
          : Column(
              children: [
                for (final soin in soins) ...[
                  InkWell(
                    onTap: () => context.go('/elevage/soins'),
                    borderRadius: AppRadius.cardRadius,
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: soin.estEnRetard
                            ? AppColors.errorContainer
                            : AppColors.surfaceZebra,
                        borderRadius: AppRadius.cardRadius,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${soin.typeSoin} — ${soin.espece}'
                                  '${soin.estEnRetard ? ' (En Retard)' : ''}',
                                  style: TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: soin.estEnRetard
                                        ? AppColors.errorDeep
                                        : AppColors.brandNavy,
                                  ),
                                ),
                                Text(
                                  soin.observations ??
                                      'Prévu le ${Formats.date(soin.datePrevue)}',
                                  style: TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontSize: 12,
                                    color: soin.estEnRetard
                                        ? AppColors.errorDeep
                                        : AppColors.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Symbols.chevron_right,
                            size: 16,
                            color: AppColors.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

class _BilanEconomique extends StatelessWidget {
  const _BilanEconomique({required this.vm});

  final DashboardElevageViewModel vm;

  @override
  Widget build(BuildContext context) {
    return CarteSection(
      titre: 'Bilan Économique Élevage (Mois)',
      icone: Symbols.query_stats,
      couleurIcone: AppColors.successDeep,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _Bloc(
                  libelle: 'Revenus Élevage',
                  valeur: Formats.nombre(vm.revenusElevage),
                  couleur: AppColors.successDeep,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              const Expanded(
                child: _Bloc(
                  libelle: 'Coûts Élevage',
                  valeur: '—',
                  couleur: AppColors.errorDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.brandGold.withValues(alpha: 0.1),
              borderRadius: AppRadius.cardRadius,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MARGE NETTE ÉLEVAGE',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.outline,
                  ),
                ),
                Text(
                  '—',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandNavy,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Revenus = ventes d\'activité Avicole du mois. Les coûts (intrants '
            'provende + vétérinaire) proviendront du module Achats & Commandes, '
            'non encore disponible — la marge ne peut donc pas être calculée.',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              height: 1.4,
              color: AppColors.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bloc extends StatelessWidget {
  const _Bloc({
    required this.libelle,
    required this.valeur,
    required this.couleur,
  });

  final String libelle;
  final String valeur;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceZebra,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            libelle.toUpperCase(),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.outline,
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: valeur),
                if (valeur != '—')
                  const TextSpan(
                    text: ' FCFA',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                  ),
              ],
            ),
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: couleur,
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneMoitie extends StatelessWidget {
  const _LigneMoitie({required this.gauche, required this.droite});

  final Widget gauche;
  final Widget droite;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: gauche),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: droite),
      ],
    );
  }
}
