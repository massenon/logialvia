# 07 — Navigation & Routage entre les 31 Écrans

## 1. Structure de Navigation Globale

Le prototype web utilise une **sidebar rétractable** (chargée par `assets/js/sidebar.js` sur les 31 pages) + une **topbar fixe** (recherche, notifications, profil). Équivalent Flutter Desktop :

```
Scaffold
├── AppShell (persiste sur toute la session, ne se reconstruit pas a chaque navigation)
│   ├── NavigationRail / Drawer permanent (equivalent sidebar)
│   ├── AppTopBar (equivalent topbar : recherche, notifications, profil)
│   └── Navigator imbrique (contenu de l'ecran actif)
```

**Point d'architecture important** : la sidebar et la topbar ne doivent **pas** être reconstruites à chaque changement d'écran (elles sont statiques dans le HTML, incluses une fois par page via `<script src="assets/js/sidebar.js">`). En Flutter, ceci se traduit par un `Shell Route` (via `go_router` — voir Doc 11 pour la dépendance) qui enveloppe toutes les routes internes.

---

## 2. Arborescence de Navigation (groupée par catégorie fonctionnelle)

Reprise directe des catégories du Doc 03 :

```
├── Authentification (hors Shell — plein ecran)
│   ├── / (Splash — index.html)
│   ├── /welcome (welcome.html)
│   └── /login (login.html)
│
└── AppShell (sidebar + topbar communes)
    ├── Pilotage
    │   ├── /dashboard
    │   └── /elevage/dashboard
    │
    ├── Production Élevage
    │   ├── /elevage/goliaths
    │   ├── /elevage/pintades
    │   ├── /elevage/lapins
    │   ├── /elevage/poulets-pondeuses   (2 onglets internes : Poulets | Pondeuses)
    │   ├── /elevage/poissons-chats
    │   ├── /elevage/couveuse
    │   └── /elevage/soins
    │
    ├── Ventes & Clients
    │   ├── /ventes                       (4 onglets internes : Vente | Devis | Historique | Retours)
    │   ├── /catalogue
    │   └── /clients
    │
    ├── Stocks & Achats
    │   ├── /stocks
    │   ├── /achats
    │   └── /fournisseurs
    │
    ├── Comptabilité
    │   ├── /depenses
    │   ├── /comptabilite               (hub)
    │   ├── /comptabilite/journal
    │   ├── /comptabilite/plan
    │   ├── /comptabilite/analytique
    │   ├── /comptabilite/cloture
    │   └── /comptabilite/bilan
    │
    ├── Rapports
    │   └── /rapports
    │
    └── Paramètres & Compte
        ├── /parametres/elevage
        ├── /parametres/generaux
        ├── /profil
        ├── /aide
        └── /contact
```

---

## 3. Package de Routage recommandé

`go_router` — gère nativement les Shell Routes (sidebar/topbar persistantes), les routes nommées, et la navigation profonde (deep-linking), pertinent même en desktop pour la structure d'URL interne et la gestion du bouton "précédent" éventuel.

```dart
// lib/core/router/app_router.dart (Doc C1 §7, arborescence par Bounded Context)
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
    GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),

    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/dashboard', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/elevage/dashboard', builder: (_, __) => const ElevageDashboardScreen()),
        GoRoute(path: '/elevage/goliaths', builder: (_, __) => const FicheGoliathsScreen()),
        GoRoute(path: '/elevage/pintades', builder: (_, __) => const FichePintadesScreen()),
        GoRoute(path: '/elevage/lapins', builder: (_, __) => const FicheLapinsScreen()),
        GoRoute(path: '/elevage/poulets-pondeuses', builder: (_, __) => const FichePouletsPondeusesScreen()),
        GoRoute(path: '/elevage/poissons-chats', builder: (_, __) => const FichePoissonsChatsScreen()),
        GoRoute(path: '/elevage/couveuse', builder: (_, __) => const CycleCouveuseScreen()),
        GoRoute(path: '/elevage/soins', builder: (_, __) => const SoinsCalendrierScreen()),
        GoRoute(path: '/ventes', builder: (_, __) => const VentesScreen()),
        GoRoute(path: '/catalogue', builder: (_, __) => const CatalogueProduitsScreen()),
        GoRoute(path: '/clients', builder: (_, __) => const RelancesClientsScreen()),
        GoRoute(path: '/stocks', builder: (_, __) => const GestionStocksScreen()),
        GoRoute(path: '/achats', builder: (_, __) => const AchatsCommandesScreen()),
        GoRoute(path: '/fournisseurs', builder: (_, __) => const FournisseursScreen()),
        GoRoute(path: '/depenses', builder: (_, __) => const SaisieDepensesScreen()),
        GoRoute(path: '/comptabilite', builder: (_, __) => const ComptabiliteHubScreen()),
        GoRoute(path: '/comptabilite/journal', builder: (_, __) => const JournalComptableScreen()),
        GoRoute(path: '/comptabilite/plan', builder: (_, __) => const PlanComptableScreen()),
        GoRoute(path: '/comptabilite/analytique', builder: (_, __) => const ComptabiliteAnalytiqueScreen()),
        GoRoute(path: '/comptabilite/cloture', builder: (_, __) => const ClotureExerciceScreen()),
        GoRoute(path: '/comptabilite/bilan', builder: (_, __) => const BilanEntrepriseScreen()),
        GoRoute(path: '/rapports', builder: (_, __) => const RapportsExportsScreen()),
        GoRoute(path: '/parametres/elevage', builder: (_, __) => const ParametresElevageScreen()),
        GoRoute(path: '/parametres/generaux', builder: (_, __) => const ParametresGenerauxScreen()),
        GoRoute(path: '/profil', builder: (_, __) => const MonProfilScreen()),
        GoRoute(path: '/aide', builder: (_, __) => const AideAProposScreen()),
        GoRoute(path: '/contact', builder: (_, __) => const ContactEditeurScreen()),
      ],
    ),
  ],
);
```

---

## 4. Onglets Internes — `ventes_screen.dart` et `fiche_poulets_pondeuses_screen.dart`

Ces 2 écrans gèrent leurs sous-vues via `TabController`, **pas** via des sous-routes (conformément à la contrainte 1:1 du Doc 03) :

```dart
class VentesScreen extends StatefulWidget {
  const VentesScreen({super.key});
  @override
  State<VentesScreen> createState() => _VentesScreenState();
}

class _VentesScreenState extends State<VentesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 4, vsync: this);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabBar(controller: _tabController, isScrollable: true, tabs: const [
        Tab(text: 'Enregistrer Vente'), Tab(text: 'Devis Prestations'),
        Tab(text: 'Historique des Ventes'), Tab(text: 'Retours et Avoirs'),
      ]),
      Expanded(child: TabBarView(controller: _tabController, children: const [
        PosPanel(), DevisPanel(), HistoriquePanel(), RetoursPanel(),
      ])),
    ]);
  }
}
```

---

## 5. Navigation Contextuelle (liens croisés entre écrans)

Plusieurs écrans du prototype se lient entre eux directement (ex : `feed-autonomy-alert` dans une fiche pointe vers `achats-commandes.html` via `<a href="achats-commandes.html">Commander Stock</a>`). Équivalent Dart :

```dart
// Dans une fiche d'elevage, alerte autonomie alimentaire
TextButton(
  onPressed: () => context.go('/achats'),
  child: const Text('Commander Stock'),
)
```

**Règle** : toute navigation contextuelle identifiée dans le HTML source (liens `href="*.html"` internes) doit être reproduite avec `context.go('/route-equivalente')`, en s'appuyant sur la table de correspondance du Doc 03 — jamais de lien mort.

---

## 6. Rôle & Permissions (RBAC) — impact sur la navigation

Le prototype a un sélecteur de rôle de test (`#rbac-role-switcher` : Admin / Caissier / Animalier / Comptable) qui restreint l'accès à certains écrans selon le rôle. Cette logique doit être portée dans le `redirect` de `go_router` :

```dart
GoRoute(
  path: '/comptabilite',
  redirect: (context, state) {
    final role = context.read<AuthProvider>().currentRole;
    if (role != 'admin') return '/dashboard';
    return null; // pas de redirection, acces autorise
  },
  builder: (_, __) => const ComptabiliteHubScreen(),
),
```
