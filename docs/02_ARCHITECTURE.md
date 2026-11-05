# 02 — Architecture Logicielle LogiALVIA Flutter

## 1. Approche générale

**Clean Architecture** en 3 couches, avec **Provider + ChangeNotifier** pour la gestion d'état — approche identique à celle déjà établie et éprouvée sur le projet AgriERP Windows (nouveau projet dédié, mais mêmes conventions techniques pour cohérence et réutilisation de connaissance).

```
lib/
├── core/                          # Transversal, ne depend de rien d'autre dans lib/
│   ├── theme/                     # app_colors.dart, app_typography.dart, app_spacing.dart, app_theme.dart
│   ├── constants/                 # Routes, cles de stockage, enums partages
│   ├── widgets/                   # Composants reutilisables (Doc 06)
│   └── utils/                     # Formatters (FCFA, dates), validators
│
├── data/                          # Couche Donnees
│   ├── local/
│   │   ├── database.dart          # Definition Drift (@DriftDatabase)
│   │   └── tables/                # Une table Drift par entite (Doc 04)
│   ├── models/                    # DTOs si necessaire (souvent les classes Drift generees suffisent)
│   └── repositories/              # Implementation concrete des interfaces du domain
│
├── domain/                        # Couche Metier (independante de Flutter et de Drift)
│   ├── entities/                  # Objets metier purs
│   ├── repositories/              # Interfaces abstraites (contrats)
│   └── usecases/                  # Une classe = une action metier (ex: EnregistrerVenteUseCase)
│
└── presentation/                  # Couche UI
    ├── screens/                   # Un dossier par ecran (correspondance 1:1 avec les 31 fichiers, Doc 03)
    │   └── <nom_ecran>/
    │       ├── <nom_ecran>_screen.dart
    │       ├── <nom_ecran>_view_model.dart   # extends ChangeNotifier
    │       └── widgets/                       # Sous-composants prives a cet ecran uniquement
    └── navigation/                 # app_router.dart (Doc 07)
```

### Pourquoi ce decoupage
- **`domain/`** ne connait ni Flutter ni Drift : c'est le coeur metier testable independamment (ex: la logique de calcul du Doc 05 vit ici, dans des `usecases/`, pas dans les widgets).
- **`data/`** est la seule couche qui connait Drift/SQLite — si on change de solution de persistance un jour, seule cette couche bouge.
- **`presentation/`** ne fait aucun calcul metier directement dans les widgets — elle appelle des `ViewModel` (ChangeNotifier) qui eux-memes appellent des `usecases/`.

Cette separation repond directement a l'exigence de qualite de code demandee : **aucune duplication** (la logique de calcul n'existe qu'une fois, dans `domain/usecases/`, jamais recopiee dans chaque ecran), **composants reutilisables** (widgets communs dans `core/widgets/`), **architecture claire**.

---

## 2. Gestion d'État — Provider + ChangeNotifier

Chaque écran a son propre `ViewModel` qui étend `ChangeNotifier`, exposé via `ChangeNotifierProvider` au niveau de l'écran (pas globalement, sauf pour les données véritablement transversales comme le catalogue produits ou le stock, qui doivent être accessibles depuis plusieurs écrans simultanément — POS, Historique, Gestion des Stocks).

### Providers globaux (niveau application, dans `main.dart`)
```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => StockProvider(stockRepository)),
    ChangeNotifierProvider(create: (_) => VentesProvider(ventesRepository)),
    ChangeNotifierProvider(create: (_) => FicheEspeceProvider(ficheRepository)),
  ],
  child: const LogiALVIAApp(),
)
```

Ce choix reproduit fidèlement le rôle que joue `logialvia-store.js` côté web : **une source unique de vérité partagée**, où une vente enregistrée dans l'écran POS notifie automatiquement l'écran Historique et l'écran Gestion des Stocks — équivalent Dart de l'événement `window.dispatchEvent(new CustomEvent('logialvia:update'))` déjà implémenté en JS.

### Providers locaux (niveau écran)
Pour l'état purement local à un écran (ex : quel onglet du panneau KPI mobile est ouvert, quelle ligne de tableau est en cours d'édition), le ViewModel est scopé à l'écran via `ChangeNotifierProvider` posé directement dans le `build()` de l'écran, pas dans `main.dart`.

---

## 3. Injection de Dépendances

Pas de package DI lourd (`get_it`, `injectable`) pour un projet de cette taille — **injection manuelle par constructeur**, explicite et traçable :

```dart
// main.dart
final database = AppDatabase();
final stockRepository = StockRepositoryImpl(database);
final ventesRepository = VentesRepositoryImpl(database, stockRepository);
```

Cette approche reste lisible pour 31 écrans et évite une dépendance supplémentaire non indispensable.

---

## 4. Cible de Plateforme

**Flutter Desktop (Windows)** — confirmé par votre décision antérieure de créer un nouveau projet dédié (pas d'extension du projet AgriERP existant, mais même cible plateforme).

Implications techniques à anticiper (déjà rencontrées et documentées sur AgriERP Windows, à ré-appliquer ici) :
- `sqlite3_flutter_libs` nécessite `openSqlite3OnWindows()` avant toute utilisation de Drift sur Windows
- Les fichiers Dart qui utilisent des extensions Drift dans un contexte UI doivent `import 'package:drift/drift.dart' hide Column;` pour éviter le conflit avec `Column` de Flutter (widget de mise en page)
- Fenêtre desktop : dimensions minimales à fixer via `window_manager` ou équivalent pour cohérence avec les breakpoints `lg`/`xl` du design web (Doc 10)

---

## 5. Ce que ce document ne couvre pas encore

- Le détail exact des `usecases/` par écran → Doc 05 (Logique de Calcul) pour les fiches d'élevage, Doc 07 pour la navigation
- La liste exhaustive des packages `pubspec.yaml` → Doc 11 (Setup)
