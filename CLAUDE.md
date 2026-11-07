# CLAUDE.md — LogiALVIA

Logiciel de gestion intégrée (ERP desktop, hors-ligne) pour **ALLMANY ET COMPAGNIE** :
élevage multi-filières, ventes/POS, stocks & achats, comptabilité SYSCOHADA, rapports,
administration. Interface et code métier **entièrement en français**.

## Organisation du dépôt

| Chemin | Contenu |
|---|---|
| `logialvia_app/` | Application Flutter (cible principale : **Windows desktop**) |
| `docs/` | Documentation SDLC (44 docs). Point d'entrée : `docs/INDEX_MAITRE.md` |
| `docs/manuel/` | Manuel utilisateur PDF + captures/libellés **générés par les tests** |
| `logo/` | Logos sources |
| `logialvia_app/dist/` | Build Windows livré (zip ~35 Mo, versionné) |
| `logialvia_app/outils/` | Scripts : génération du manuel, icône, reset mot de passe admin |

## Commandes (depuis `logialvia_app/`)

```bash
flutter pub get
flutter analyze                     # doit rester à "No issues found!"
flutter test                        # ~990 tests, ~2 min
flutter test test/elevage/          # un dossier / un fichier
dart run build_runner build --delete-conflicting-outputs   # après toute modif de table Drift
flutter build windows --release
```

SDK : Dart `^3.12.2` / Flutter `>=3.41` (vérifié avec Flutter 3.47.9).

⚠️ `test/manuel/captures_test.dart` **réécrit** `docs/manuel/captures/*.png` et
`docs/manuel/libelles/*.json`, et son contenu dépend de la date du jour. Ne pas committer
ces fichiers après un simple `flutter test` ; les restaurer avec
`git checkout -- docs/manuel` sauf régénération volontaire du manuel.

## Architecture

Clean Architecture + DDD, découpage par **Bounded Context** (Doc C1) :

```
lib/
  main.dart            # init fenêtre, reprise/restauration de base, MultiProvider, GoRouter
  core/                # transverse : database (Drift), router, theme, widgets, pdf, events, saisie, tour
  administration/      # auth, utilisateurs/rôles, paramètres, sauvegardes, corbeille
  elevage/             # fiches par filière, couveuse, soins/prophylaxie
  commercial/          # ventes/POS, clients, devis, factures e-MECeF
  approvisionnement/   # intrants, achats, fournisseurs, provende
  comptabilite/        # moteur comptable, journal, grand livre, balance, états financiers, clôture
  pilotage/            # tableaux de bord, alertes
  rapports/            # rapports & exports (lecture seule, sans table propre)
```

Chaque contexte suit `data/` (tables Drift, repositories `*_drift.dart`, seeders) →
`domain/` (entités, services, use cases, interfaces de repository) →
`presentation/` (screens, viewmodels `ChangeNotifier`).

- **État** : `provider`. Tout ViewModel partagé entre écrans/modales est enregistré
  globalement dans `main.dart` (Doc K4 §5).
- **Persistance** : Drift/SQLite, une seule `AppDatabase` (`core/database/app_database.dart`,
  `versionSchema = 26`, migrations idempotentes testées). `app_database.g.dart` est généré
  et versionné.
- **Navigation** : `go_router`, 3 routes publiques (`/`, `/welcome`, `/login`) puis un
  `ShellRoute` (sidebar/topbar) ; accès contrôlé par `PermissionService` (RBAC 3 rôles, Doc I1)
  et modules actifs (Doc I2).
- **Événements de domaine** : `core/events/domain_event.dart` (`EventBus` unique).
- **PDF** : générateur unique `core/pdf/` avec Roboto statique embarquée (hors-ligne).
- **Secrets** (jeton e-MECeF, SMTP) : `flutter_secure_storage`, jamais en base.

## Conventions

- Lints stricts (`analysis_options.yaml`) : virgules finales, `const`, pas de `print`.
- Commentaires et identifiants en français, références aux docs (`Doc F3 §2`).
- `TODO(dette): ...` pour la dette assumée (ignorée par l'analyseur).
- Avant de coder une règle métier, lire le doc F*/B6 du module et `docs/A2_STRICT_AVOID.md`,
  `docs/K1_Standards_Code.md`, `docs/K4_Retour_Experience_Bugs_Reels.md`.
