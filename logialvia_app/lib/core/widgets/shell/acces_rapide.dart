import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../administration/presentation/viewmodels/modules_actifs_view_model.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Menu flottant « Accès Rapide » — `toggleSpeciesQuickNav()` de `common.js`,
/// panneau construit par `sidebar.js` l.104-128.
///
/// ## Ce que le prototype en dit
///
/// > « Menu flottant autonome (accès rapide élevage & modules). **Indépendant
/// > du toggle du sidebar** — reste accessible que le sidebar soit ouvert,
/// > replié (desktop) ou masqué (mobile). Bouton rond fixe en bas à droite qui
/// > ouvre un panneau offcanvas avec 10 raccourcis maximum. »
///
/// C'est précisément son intérêt : quand la Gérante replie la barre latérale
/// pour gagner de la place sur une fiche de saisie, elle garde un accès direct
/// aux écrans qu'elle enchaîne le plus. Sans ce menu, replier la barre latérale
/// coupe toute navigation.
///
/// Le bouton se décale à `right: 80px` quand la barre est repliée
/// (`toggleSidebarDesktop()`), pour ne pas recouvrir le ruban qui la remplace.
class AccesRapide extends StatefulWidget {
  const AccesRapide({super.key, required this.sidebarRepliee});

  final bool sidebarRepliee;

  @override
  State<AccesRapide> createState() => _AccesRapideState();
}

class _AccesRapideState extends State<AccesRapide>
    with SingleTickerProviderStateMixin {
  bool _ouvert = false;

  /// Les 12 raccourcis de `sidebar.js`, dans l'ordre exact, séparateurs
  /// compris. `moduleId` reprend l'attribut `data-module` : une filière
  /// désactivée disparaît du panneau (Doc I2 §3), comme côté web.
  static const List<
    ({String? libelle, IconData? icone, String? route, String? moduleId})
  >
  _entrees = [
    (
      libelle: 'Cycle Couveuse',
      icone: Symbols.egg,
      route: '/elevage/couveuse',
      moduleId: null,
    ),
    (
      libelle: 'Fiche Goliaths',
      icone: Symbols.pets,
      route: '/elevage/goliaths',
      moduleId: null,
    ),
    (
      libelle: 'Fiche Pintades',
      icone: Symbols.pets,
      route: '/elevage/pintades',
      moduleId: null,
    ),
    (
      libelle: 'Fiche Poissons-Chats',
      icone: Symbols.set_meal,
      route: '/elevage/poissons-chats',
      moduleId: 'pisciculture',
    ),
    (libelle: null, icone: null, route: null, moduleId: null), // séparateur
    (
      libelle: 'Soins & Calendrier',
      icone: Symbols.vaccines,
      route: '/elevage/soins',
      moduleId: null,
    ),
    (libelle: null, icone: null, route: null, moduleId: null), // séparateur
    (
      libelle: 'Point de Vente',
      icone: Symbols.point_of_sale,
      route: '/ventes',
      moduleId: null,
    ),
    (
      libelle: 'Gestion Stocks',
      icone: Symbols.inventory_2,
      route: '/stocks',
      moduleId: null,
    ),
    (
      libelle: 'Tableau de Bord',
      icone: Symbols.dashboard,
      route: '/dashboard',
      moduleId: null,
    ),
    (
      libelle: 'Comptabilité',
      icone: Symbols.account_balance,
      route: '/comptabilite',
      moduleId: null,
    ),
    (
      libelle: 'Grand Livre',
      icone: Symbols.import_contacts,
      route: '/comptabilite/grand-livre',
      moduleId: null,
    ),
    (
      libelle: 'États Financiers',
      icone: Symbols.description,
      route: '/comptabilite/etats-financiers',
      moduleId: null,
    ),
    (
      libelle: 'Bilan de l\'Entreprise',
      icone: Symbols.account_balance_wallet,
      route: '/comptabilite/bilan',
      moduleId: null,
    ),
    (
      libelle: 'Rapports & États',
      icone: Symbols.picture_as_pdf,
      route: '/rapports',
      moduleId: null,
    ),
  ];

  void _basculer() => setState(() => _ouvert = !_ouvert);

  @override
  Widget build(BuildContext context) {
    final modules = context.watch<ModulesActifsViewModel>();
    // `style="right:16px"`, ou 80px quand la barre laterale est repliee.
    final droite = widget.sidebarRepliee ? 80.0 : 16.0;

    return Stack(
      children: [
        // Voile — `#species-quick-nav-backdrop`, `bg-black/40`.
        if (_ouvert)
          Positioned.fill(
            child: GestureDetector(
              onTap: _basculer,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.4),
              ),
            ),
          ),
        // Bouton rond — `bottom:88px`.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          bottom: 88,
          right: droite,
          child: _BoutonRond(ouvert: _ouvert, onTap: _basculer),
        ),
        // Panneau offcanvas droit — `w-72`, `translate-x-full`, 300 ms.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          top: 0,
          bottom: 0,
          right: _ouvert ? 0 : -288,
          width: 288,
          child: _Panneau(
            entrees: _entrees,
            modules: modules,
            onFermer: _basculer,
          ),
        ),
      ],
    );
  }
}

class _BoutonRond extends StatelessWidget {
  const _BoutonRond({required this.ouvert, required this.onTap});

  final bool ouvert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Accès rapide Élevage & Modules',
      child: Material(
        color: AppColors.brandNavy,
        shape: const CircleBorder(),
        elevation: 6,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              ouvert ? Symbols.close : Symbols.apps,
              size: 24,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _Panneau extends StatelessWidget {
  const _Panneau({
    required this.entrees,
    required this.modules,
    required this.onFermer,
  });

  final List<({String? libelle, IconData? icone, String? route, String? moduleId})>
  entrees;
  final ModulesActifsViewModel modules;
  final VoidCallback onFermer;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceCard,
      elevation: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.brandNavy,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(
                  Symbols.apps,
                  size: 20,
                  color: AppColors.brandGold,
                ),
                const SizedBox(width: AppSpacing.xs),
                const Expanded(
                  child: Text(
                    'Accès Rapide',
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onFermer,
                  icon: const Icon(Symbols.close, color: Colors.white70),
                  tooltip: 'Fermer',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.sm),
              children: [
                for (final entree in entrees)
                  if (entree.libelle == null)
                    const Divider(height: AppSpacing.md)
                  else if (entree.moduleId == null ||
                      modules.estActif(entree.moduleId!))
                    _Raccourci(
                      libelle: entree.libelle!,
                      icone: entree.icone!,
                      route: entree.route!,
                      onNavigation: onFermer,
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Raccourci extends StatelessWidget {
  const _Raccourci({
    required this.libelle,
    required this.icone,
    required this.route,
    required this.onNavigation,
  });

  final String libelle;
  final IconData icone;
  final String route;
  final VoidCallback onNavigation;

  /// Les 5 premiers raccourcis sont navy, les suivants or — `text-brand-navy`
  /// contre `text-brand-gold` dans `sidebar.js`.
  static const Set<String> _routesNavy = {
    '/elevage/couveuse',
    '/elevage/goliaths',
    '/elevage/pintades',
    '/elevage/poissons-chats',
  };

  @override
  Widget build(BuildContext context) {
    final couleur = _routesNavy.contains(route)
        ? AppColors.brandNavy
        : (route == '/elevage/soins'
              ? AppColors.infoBlue
              : AppColors.brandGold);

    return InkWell(
      onTap: () {
        onNavigation();
        context.go(route);
      },
      borderRadius: AppRadius.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Icon(icone, size: 22, color: couleur),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                libelle,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ombre du panneau — `shadow-2xl` du prototype.
List<BoxShadow> get ombrePanneauAccesRapide => AppShadows.xxl;
