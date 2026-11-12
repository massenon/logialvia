import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../administration/presentation/viewmodels/auth_view_model.dart';
import '../../../administration/presentation/viewmodels/modules_actifs_view_model.dart';
import '../../../core/formatage/formats.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/database/app_database.dart';
import '../../../core/tour/tour_guide.dart';
import '../../../core/widgets/carte_section.dart';
import '../../../elevage/data/repositories/fiche_elevage_repository_drift.dart';
import '../../../elevage/data/repositories/soins_repository_drift.dart';
import '../../../elevage/domain/usecases/reporter_deces_infirmerie_usecase.dart';
import '../../../elevage/presentation/screens/widgets/modale_prophylaxie_du_jour.dart';
import 'widgets/modale_stock_critique.dart';
import '../../../elevage/presentation/viewmodels/soins_view_model.dart';
import '../viewmodels/alertes_view_model.dart';
import '../viewmodels/tableau_bord_view_model.dart';
import 'widgets/bandeau_kpi.dart';
import 'widgets/graphiques_pilotage.dart';
import 'widgets/panneaux_pilotage.dart';

/// Tableau de Bord Principal — Doc F2 Ecran 1, fidele a `dashboard.html`.
///
/// ⚠️ Ordre des sections corrige par rapport a Doc F2, qui en decrivait 4.
/// Le HTML reel en compte 7, dans cet ordre :
///   1. En-tete de bienvenue + 2 actions rapides
///   2. Filtre de periode + export d'etat
///   3. Bandeau de 8 KPI
///   4. Courbe CA vs Depenses (8/12) + Alertes Critiques (4/12)
///   5. Cartes de recensement par filiere + Couveuse
///   6. Statistiques de Ventes + Transactions Recentes
///   7. Activites du Jour + Meilleures Ventes du Mois
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  Set<String> get _especesActives {
    final modules = context.read<ModulesActifsViewModel>();
    return {
      ...TableauBordViewModel.especesPermanentes,
      for (final entree in ModulesActifsSeederEspeces.parModule.entries)
        if (modules.estActif(entree.key)) entree.value,
    };
  }

  Future<void> _charger() async {
    await context.read<TableauBordViewModel>().charger(_especesActives);
    if (mounted) await context.read<AlertesViewModel>().rafraichir();
    // La sante des animaux passe avant le reste : la prophylaxie s'affiche en
    // premier, le stock ensuite.
    if (mounted) await _rappelProphylaxie();
    if (!mounted) return;
    await AlertesStockCritique.ouvrirSiNecessaire(
      context,
      context.read<AlertesViewModel>().articlesSousSeuil,
    );
  }

  /// Popup « Prophylaxie du Jour » — `assets/js/prophylaxie-popup.js`, dont la
  /// portee est « dashboard.html et elevage-dashboard.html uniquement ».
  ///
  /// Le ViewModel des soins n'est pas fourni a cet ecran : la popup est le seul
  /// element du tableau de bord qui en depende, et l'injecter globalement ferait
  /// relire `SOINS_CALENDRIER` a chaque navigation. Il est donc construit ici,
  /// utilise, puis libere.
  Future<void> _rappelProphylaxie() async {
    final base = context.read<AppDatabase>();
    // Les echeances du calendrier non planifiees viennent des alertes, deja
    // rafraichies : les recalculer ici les ferait lire deux fois.
    final rappels = context.read<AlertesViewModel>().rappelsProphylaxie;
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
    final vm = context.watch<TableauBordViewModel>();
    final alertes = context.watch<AlertesViewModel>();

    if (vm.chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _EnTeteBienvenue(),
          const SizedBox(height: AppSpacing.md),
          CibleTour(
            nom: 'filtre-periode',
            child: _FiltrePeriode(
              debut: vm.debutPeriode,
              fin: vm.finPeriode,
              onChange: (debut, fin) =>
                  vm.definirPeriode(debut, fin, _especesActives),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          CibleTour(
            nom: 'kpi-panel',
            child: BandeauKpi(indicateurs: vm.indicateurs),
          ),
          const SizedBox(height: AppSpacing.lg),
          _LigneDouze(
            gauche: CibleTour(
              nom: 'graphique-ca-depenses',
              child: CarteSection(
                titre: 'CA vs Dépenses — 6 derniers mois',
                child: CourbeCaDepenses(points: vm.evolutionMensuelle),
              ),
            ),
            droite: CibleTour(
              nom: 'alertes-critiques',
              child: PanneauAlertes(alertes: alertes.alertes),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          CibleTour(
            nom: 'cartes-filieres',
            child: _GrilleFilieres(vm: vm),
          ),
          const SizedBox(height: AppSpacing.lg),
          _LigneMoitie(
            gauche: CarteSection(
              titre: 'Statistiques de Ventes',
              icone: Symbols.bar_chart,
              action: Text(
                '${DateTime.now().year}',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.outline,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                          valeur: '${Formats.nombre(vm.recettesSemaine)} F',
                          libelle: 'Revenu (semaine)',
                          couleur: AppColors.brandNavy,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(
                        child: _MiniStat(
                          valeur: '—',
                          libelle: 'Dépenses (semaine)',
                          couleur: AppColors.errorDeep,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  BarresRecettesDepenses(points: vm.evolutionJournaliere),
                ],
              ),
            ),
            droite: TransactionsRecentes(ventes: vm.ventesRecentes),
          ),
          const SizedBox(height: AppSpacing.lg),
          _LigneMoitie(
            gauche: FilActivites(activites: vm.activites),
            droite: TableauMeilleuresVentes(lignes: vm.meilleuresVentes),
          ),
        ],
      ),
    );
  }
}

/// Correspondance module basculable -> espece, reprise du seeder pour eviter de
/// la redefinir ici (source unique, Strict Avoid §12).
class ModulesActifsSeederEspeces {
  ModulesActifsSeederEspeces._();

  static const Map<String, String> parModule = {
    'pisciculture': 'poissons-chats',
    'cuniculture': 'lapins',
    'aviculture_classique': 'poulets',
    'heliciculture': 'escargots',
    'ovins': 'ovins',
  };
}

class _EnTeteBienvenue extends StatelessWidget {
  const _EnTeteBienvenue();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthViewModel>().session;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // La main est une **icone**, plus un emoji.
              //
              // `dashboard.html` salue avec le caractere U+1F44B. Aucune police
              // du projet ne le porte : Windows le rend avec sa police systeme
              // d'emoji, et partout ailleurs -- capture d'ecran du manuel,
              // poste sans cette police -- il sortait en carre vide. Material
              // Symbols, elle, est embarquee : le geste est le meme, il
              // s'affiche partout, et il prend la couleur de la marque.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      'Bienvenue, ${session?.utilisateur.nom ?? ''}',
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 20, // `text-xl`
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandNavy,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Symbols.waving_hand,
                    size: 20,
                    color: AppColors.brandGold,
                    fill: 1,
                  ),
                ],
              ),
              Text(
                'Rapport généré le ${Formats.date(DateTime.now())} '
                'à ${Formats.heure(DateTime.now())} · ALLMANY ET COMPAGNIE',
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
        ),
        AppButton(
          label: 'Enregistrer une Vente',
          icon: Symbols.point_of_sale,
          onPressed: () => context.go('/ventes'),
        ),
        const SizedBox(width: AppSpacing.xs),
        AppButton(
          label: 'Dashboard Élevage',
          icon: Symbols.monitoring,
          variant: AppButtonVariant.outline,
          onPressed: () => context.go('/elevage/dashboard'),
        ),
      ],
    );
  }
}

/// `#tour-date-filter` — dashboard.html l.107-126.
///
/// Le selecteur « -- Choisir un état / rapport -- » et son bouton ne font, cote
/// web, que **rediriger** vers l'ecran correspondant (`exportReport()`,
/// dashboard.html l.385-400) — aucun PDF n'y est produit malgre l'icone. Les 6
/// ecrans cibles existent desormais tous : le selecteur est restaure avec son
/// comportement reel, la navigation, et son libelle dit ce qu'il fait.
class _FiltrePeriode extends StatefulWidget {
  const _FiltrePeriode({
    required this.debut,
    required this.fin,
    required this.onChange,
  });

  final DateTime debut;
  final DateTime fin;
  final void Function(DateTime debut, DateTime fin) onChange;

  @override
  State<_FiltrePeriode> createState() => _FiltrePeriodeState();
}

class _FiltrePeriodeState extends State<_FiltrePeriode> {
  String? _etat;

  /// Les 6 entrees de `exportReport()` et leur route reelle.
  static const List<({String libelle, String route})> _etats = [
    (libelle: 'État des Stocks', route: '/stocks'),
    (libelle: 'État du Cycle d\'Élevage', route: '/elevage/dashboard'),
    (libelle: 'État des Cycles de Couveuse', route: '/elevage/couveuse'),
    (libelle: 'État des Recettes et Dépenses', route: '/rapports'),
    (libelle: 'État des Créances et Avances', route: '/clients'),
    (libelle: 'Rapport Mensuel de Synthèse', route: '/rapports'),
  ];

  Future<void> _choisir(BuildContext context, {required bool estDebut}) async {
    final choisie = await showDatePicker(
      context: context,
      initialDate: estDebut ? widget.debut : widget.fin,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      locale: const Locale('fr'),
    );
    if (choisie == null) return;
    widget.onChange(
      estDebut ? choisie : widget.debut,
      estDebut ? widget.fin : choisie,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          const Icon(
            Symbols.calendar_month,
            size: 18,
            color: AppColors.outline,
          ),
          const SizedBox(width: AppSpacing.xs),
          // ECART_DELIBERE : `<input type="date">` n'a pas d'equivalent Flutter
          // natif — remplace par `showDatePicker`, meme intention fonctionnelle
          // (Master Prompt §3.3).
          _BoutonDate(
            date: widget.debut,
            onTap: () => _choisir(context, estDebut: true),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Text(
            'au',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: AppTypography.textXs,
              color: AppColors.outline,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _BoutonDate(
            date: widget.fin,
            onTap: () => _choisir(context, estDebut: false),
          ),
          const Spacer(),
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              initialValue: _etat,
              isExpanded: true,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: AppTypography.textXs,
                color: AppColors.onSurface,
              ),
              hint: const Text(
                '-- Ouvrir un état / rapport --',
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 12,
                  color: AppColors.outline,
                ),
              ),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AppColors.surfaceCard,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: AppRadius.cardRadius,
                  borderSide: const BorderSide(color: AppColors.outlineVariant),
                ),
              ),
              items: [
                for (final etat in _etats)
                  DropdownMenuItem(
                    value: etat.libelle,
                    child: Text(
                      etat.libelle,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: AppTypography.textXs,
                      ),
                    ),
                  ),
              ],
              onChanged: (valeur) {
                if (valeur == null) return;
                setState(() => _etat = valeur);
                // Le prototype **redirige** : l'export se fait sur l'ecran
                // cible, qui porte son propre bouton PDF.
                final route = _etats
                    .firstWhere((e) => e.libelle == valeur)
                    .route;
                context.go(route);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BoutonDate extends StatelessWidget {
  const _BoutonDate({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        minimumSize: const Size(0, 32),
      ),
      child: Text(
        Formats.date(date),
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: AppTypography.textXs,
          color: AppColors.onSurface,
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.valeur,
    required this.libelle,
    required this.couleur,
  });

  final String valeur;
  final String libelle;
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
            valeur,
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: couleur,
            ),
          ),
          Text(
            libelle,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              color: AppColors.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _GrilleFilieres extends StatelessWidget {
  const _GrilleFilieres({required this.vm});

  final TableauBordViewModel vm;

  @override
  Widget build(BuildContext context) {
    final cartes = <Widget>[
      for (final filiere in vm.filieres) CarteFiliere(filiere: filiere),
      if (vm.couveuse != null) CarteCouveuse(couveuse: vm.couveuse!),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // `md:grid-cols-3`
        const colonnes = 3;
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

/// Disposition `lg:grid-cols-12` avec un bloc en `col-span-8` et l'autre en
/// `col-span-4`.
class _LigneDouze extends StatelessWidget {
  const _LigneDouze({required this.gauche, required this.droite});

  final Widget gauche;
  final Widget droite;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 8, child: gauche),
          const SizedBox(width: AppSpacing.md),
          Expanded(flex: 4, child: droite),
        ],
      ),
    );
  }
}

/// Disposition `lg:grid-cols-2`.
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
