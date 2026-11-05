import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../administration/presentation/screens/auth/login_screen.dart';
import '../../administration/presentation/screens/compte/pages_compte.dart';
import '../../administration/presentation/screens/parametres_generaux_screen.dart';
import '../../administration/presentation/screens/auth/splash_screen.dart';
import '../../administration/presentation/screens/auth/welcome_screen.dart';
import '../../administration/presentation/viewmodels/auth_view_model.dart';
import '../../administration/presentation/viewmodels/modules_actifs_view_model.dart';
import '../../approvisionnement/presentation/screens/pages_approvisionnement.dart';
import '../../commercial/presentation/screens/catalogue_screen.dart';
import '../../commercial/presentation/screens/factures_mecef_screen.dart';
import '../../commercial/presentation/screens/clients_screen.dart';
import '../../commercial/presentation/screens/ventes_screen.dart';
import '../../comptabilite/presentation/screens/pages_comptabilite.dart';
import '../../elevage/domain/entities/configuration_espece.dart';
import '../../elevage/presentation/screens/cycle_couveuse_screen.dart';
import '../../elevage/presentation/screens/statistiques_mirages_screen.dart';
import '../../elevage/presentation/screens/page_fiche_espece.dart';
import '../../elevage/presentation/screens/parametres_elevage_screen.dart';
import '../../elevage/presentation/screens/page_poulets_pondeuses.dart';
import '../../elevage/presentation/screens/soins_calendrier_screen.dart';
import '../../pilotage/presentation/screens/dashboard_elevage_screen.dart';
import '../../pilotage/presentation/screens/dashboard_screen.dart';
import '../../rapports/presentation/screens/inventaire_screen.dart';
import '../../rapports/presentation/screens/rapports_exports_screen.dart';
import '../widgets/shell/app_shell.dart';
import 'ecran_a_venir.dart';
import 'navigation_model.dart';
import 'permission_service.dart';

/// Routage global — Doc E3 §2/§3.
///
/// Les 3 ecrans d'authentification sont hors `ShellRoute` (plein ecran) ; tous
/// les ecrans internes sont enveloppes par [AppShell], qui n'est donc construit
/// qu'une fois pour toute la session (Doc E3 §1).
class AppRouter {
  AppRouter._();

  /// Routes accessibles sans session ouverte.
  static const Set<String> routesPubliques = {'/', '/welcome', '/login'};

  /// Ecrans deja implementes. Toute autre route de [NavigationModel] est servie
  /// par [EcranAVenir] — jamais un lien mort (Doc E3 §5).
  static final Map<String, Widget Function()> _ecransImplementes = {
    '/dashboard': () => const DashboardScreen(),
    '/elevage/dashboard': () => const DashboardElevageScreen(),
    // Les fiches d'elevage partagent UN SEUL ecran, parametre par la
    // configuration de l'espece (Strict Avoid §5 et §15).
    '/elevage/goliaths': () =>
        const PageFicheEspece(configuration: ConfigurationsEspeces.goliaths),
    '/elevage/pintades': () =>
        const PageFicheEspece(configuration: ConfigurationsEspeces.pintades),
    '/elevage/lapins': () =>
        const PageFicheEspece(configuration: ConfigurationsEspeces.lapins),
    '/elevage/poissons-chats': () => const PageFicheEspece(
      configuration: ConfigurationsEspeces.poissonsChats,
    ),
    '/elevage/couveuse': () => const PageCycleCouveuse(),
    '/elevage/mirages': () => const PageStatistiquesMirages(),
    '/elevage/soins': () => const PageSoinsCalendrier(),
    // Seul ecran a onglets internes du module (Doc E3 §4).
    '/elevage/poulets-pondeuses': () => const PagePouletsPondeuses(),
    '/parametres/generaux': () => const PageParametresGeneraux(),
    '/parametres/elevage': () => const PageParametresElevage(),
    '/ventes': () => const PageVentes(),
    '/catalogue': () => const PageCatalogue(),
    '/clients': () => const PageClients(),
    '/stocks': () => const PageGestionStocks(),
    '/achats': () => const PageAchats(),
    '/fournisseurs': () => const PageFournisseurs(),
    // Module F6 — Comptabilite SYSCOHADA.
    '/depenses': () => const PageSaisieDepenses(),
    '/comptabilite': () => const PageComptabiliteHub(),
    '/comptabilite/grand-livre': () => const PageGrandLivre(),
    '/comptabilite/balance': () => const PageBalanceGenerale(),
    '/comptabilite/etats-financiers': () => const PageEtatsFinanciers(),
    '/comptabilite/bilan': () => const PageBilanEntreprise(),
    '/comptabilite/journal': () => const PageJournalComptable(),
    '/comptabilite/plan': () => const PagePlanComptable(),
    '/comptabilite/cloture': () => const PageClotureExercice(),
    '/comptabilite/analytique': () => const PageComptabiliteAnalytique(),
    // Module F7 — Rapports & Etats.
    '/rapports': () => const PageRapports(),
    '/inventaire': () => const PageInventaire(),
    // Module F-MECEF — conformite fiscale (visible si le module est actif).
    '/factures-mecef': () => const PageFacturesMecef(),
    // Module F9 — Compte Utilisateur.
    '/profil': () => const PageMonProfil(),
    '/aide': () => const PageAideAPropos(),
    '/contact': () => const PageContactEditeur(),
  };

  /// Ecrans hors barre laterale, atteints depuis le hub Comptabilite — comme
  /// cote web, ou `sidebar.js` ne liste que 4 des 8 ecrans du module et ou les
  /// 4 autres ne sont accessibles que par les tuiles de `comptabilite-hub.html`.
  static const Map<String, String> _routesHubComptabilite = {
    '/comptabilite/journal': 'Journal Comptable',
    '/comptabilite/plan': 'Plan Comptable',
    '/comptabilite/cloture': 'Clôture d\'Exercice',
    '/comptabilite/analytique': 'Comptabilité Analytique',
  };

  /// Document de specification de chaque ecran restant, pour que l'ecran
  /// d'attente dise ou est ecrite la specification correspondante.
  static const Map<String, String> _specificationParRoute = {
    '/elevage/couveuse': 'Doc F3 — Production Élevage',
    '/elevage/goliaths': 'Doc F3 — Production Élevage',
    '/elevage/pintades': 'Doc F3 — Production Élevage',
    '/elevage/poissons-chats': 'Doc F3 — Production Élevage',
    '/elevage/lapins': 'Doc F3 — Production Élevage',
    '/elevage/poulets-pondeuses': 'Doc F3 / Doc H2 — Poulets & Pondeuses',
    '/elevage/soins': 'Doc F3 — Calendrier de Soins',
    '/parametres/elevage': 'Doc F3 — Paramètres Élevage',
    '/ventes': 'Doc F4 / Doc H1 — Ventes & Clients',
    '/clients': 'Doc F4 — Clients et Créances',
    '/achats': 'Doc F5 — Stocks & Achats',
    '/fournisseurs': 'Doc F5 — Fournisseurs',
    '/depenses': 'Doc F6 — Saisie des Dépenses',
    '/stocks': 'Doc F5 — Gestion des Stocks',
    '/catalogue': 'Doc F5 — Catalogue & Seuils',
    '/comptabilite': 'Doc F6 — Comptabilité',
    '/comptabilite/grand-livre': 'Doc F6 — Grand Livre',
    '/comptabilite/balance': 'Doc F6 — Balance Générale',
    '/comptabilite/etats-financiers': 'Doc F6 — États Financiers',
    '/comptabilite/bilan': 'Doc F6 — Bilan de l\'Entreprise',
    '/comptabilite/journal': 'Doc F6 — Journal Comptable',
    '/comptabilite/plan': 'Doc F6 — Plan Comptable',
    '/comptabilite/cloture': 'Doc F6 — Clôture d\'Exercice',
    '/comptabilite/analytique': 'Doc F6 — Comptabilité Analytique',
    '/parametres/generaux': 'Doc F8 — Paramètres & Administration',
    '/elevage/mirages': 'Doc F3 — Statistiques des Mirages',
    '/rapports': 'Doc F7 — Rapports & Exports',
    '/inventaire': 'Doc F7 — Inventaire daté et valorisé',
    '/factures-mecef': 'BR-ADM-004 — Facturation normalisée MeCeF',
    '/profil': 'Doc F9 — Compte Utilisateur',
    '/aide': 'Doc F9 — Aide & À Propos',
    '/contact': 'Doc F9 — Contactez l\'Éditeur',
  };

  /// Routes hors barre laterale, atteignables depuis le menu profil.
  static const Map<String, String> _routesMenuProfil = {
    '/profil': 'Mon Profil',
    '/aide': 'Aide & À Propos',
    '/contact': 'Contactez l\'Éditeur',
  };

  static GoRouter creer(
    AuthViewModel auth,
    ModulesActifsViewModel modulesActifs,
  ) {
    return GoRouter(
      initialLocation: '/',
      refreshListenable: Listenable.merge([auth, modulesActifs]),
      redirect: (context, state) {
        final route = state.matchedLocation;
        if (routesPubliques.contains(route)) return null;

        final session = auth.session;
        if (session == null) return '/login';

        // RBAC — Doc I1 §4, branche dans le `redirect` comme specifie Doc E3 §6.
        if (!PermissionService.estAutorise(session.role.id, route)) {
          return '/dashboard';
        }

        // Module desactive — Doc I2 §3 : la route devient inaccessible meme par
        // navigation directe, en plus de disparaitre de la barre laterale.
        final moduleRequis = _moduleRequisPour(route);
        if (moduleRequis != null && !modulesActifs.estActif(moduleRequis)) {
          return '/elevage/dashboard';
        }

        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
        GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        ShellRoute(
          builder: (context, state, child) =>
              AppShell(routeActive: state.matchedLocation, child: child),
          routes: _routesInternes(),
        ),
      ],
    );
  }

  static String? _moduleRequisPour(String route) {
    for (final groupe in NavigationModel.groupes) {
      for (final entree in groupe.entrees) {
        if (entree.route == route) return entree.moduleId;
      }
    }
    return null;
  }

  static List<RouteBase> _routesInternes() {
    final routes = <RouteBase>[];

    void ajouter(String chemin, String libelle) {
      final constructeur = _ecransImplementes[chemin];
      routes.add(
        GoRoute(
          path: chemin,
          builder: constructeur != null
              ? (_, _) => constructeur()
              : (_, _) => EcranAVenir(
                  titre: libelle,
                  documentSource:
                      _specificationParRoute[chemin] ?? 'Documentation LogiALVIA',
                ),
        ),
      );
    }

    for (final groupe in NavigationModel.groupes) {
      for (final entree in groupe.entrees) {
        ajouter(entree.route, entree.libelle);
      }
    }
    _routesHubComptabilite.forEach(ajouter);
    _routesMenuProfil.forEach(ajouter);

    return routes;
  }
}
