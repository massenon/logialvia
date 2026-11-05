# 11 — Installation & Setup

## ⚠️ Préalable — contrainte de mon environnement

Ces commandes n'ont **pas été exécutées ni vérifiées** dans mon environnement de travail (pas de SDK Flutter installé, pas d'accès réseau à `pub.dev`). Elles sont rédigées à partir des conventions Flutter/Drift standards et de l'expérience déjà acquise sur le projet AgriERP Windows. **Vous devez les exécuter et corriger vous-même** les éventuels écarts de version.

---

## 1. Prérequis Système

| Outil | Version minimale recommandée | Vérification |
|---|---|---|
| Flutter SDK | 3.19+ (canal stable) | `flutter --version` |
| Dart SDK | Inclus avec Flutter | `dart --version` |
| Visual Studio 2022 (Windows Desktop) | Avec charge de travail "Développement Desktop en C++" | Requis pour compiler la cible Windows |
| Git | Toute version récente | `git --version` |

```bash
flutter doctor -v
```
Corriger tout élément marqué `[✗]` avant de continuer, en particulier la ligne "Visual Studio - develop Windows apps".

---

## 2. Création du Projet

```bash
flutter create --platforms=windows logialvia_app
cd logialvia_app
flutter config --enable-windows-desktop
```

---

## 3. Dépendances (`pubspec.yaml`)

```yaml
name: logialvia_app
description: LogiALVIA - Gestion integree ALLMANY ET COMPAGNIE
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # State management
  provider: ^6.1.2

  # Persistance locale (equivalent de logialvia-store.js / localStorage)
  drift: ^2.16.0
  sqlite3_flutter_libs: ^0.5.20
  path_provider: ^2.1.3
  path: ^1.9.0

  # Navigation
  go_router: ^14.2.0

  # Formatage dates / devises (FCFA)
  intl: ^0.19.0

  # Icones fideles au web (Material Symbols Outlined)
  material_symbols_icons: ^4.2719.0
  # -> A CONFIRMER : voir Doc 01 section 5, alternative = Icons natif Flutter

  # Impression / Export PDF (facture, rapports)
  printing: ^5.13.1
  pdf: ^3.11.0

  # Desktop window management (dimensions, titre de fenetre)
  window_manager: ^0.3.9

dev_dependencies:
  flutter_test:
    sdk: flutter
  drift_dev: ^2.16.0
  build_runner: ^2.4.9
  flutter_lints: ^4.0.0
```

```bash
flutter pub get
```

---

## 4. Police Roboto en Asset Local

Nécessaire pour un fonctionnement hors-ligne fidèle (voir Doc 01 section 2). Télécharger les 4 poids requis (400/600/700/800) depuis Google Fonts, puis :

```yaml
# pubspec.yaml
flutter:
  fonts:
    - family: Roboto
      fonts:
        - asset: assets/fonts/Roboto-Regular.ttf
          weight: 400
        - asset: assets/fonts/Roboto-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Roboto-Bold.ttf
          weight: 700
        - asset: assets/fonts/Roboto-ExtraBold.ttf
          weight: 800
```

---

## 5. Configuration SQLite pour Windows Desktop

**Point de vigilance critique**, déjà rencontré sur AgriERP Windows — sans ceci, l'application plante au démarrage sur Windows :

**⚠️ Correction critique** (Retour d'expérience réel, Doc K4) : la version précédente de cette section recommandait un `open.overrideFor(OperatingSystem.windows, ...)` — **ce pattern s'est révélé invalide en pratique** sur le projet jumeau AgriERP Windows. `OperatingSystem`, `open` et `openOnWindows` sont des API bas niveau qui n'existent pas dans `sqlite3_flutter_libs` 0.5.x et entrent en conflit avec le chargement automatique de la DLL par le plugin. Le vrai correctif, confirmé par compilation réelle sous Windows :

```dart
// lib/core/database/database.dart (Doc C1 §7, arborescence par Bounded Context)
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// AUCUNE fonction d'override necessaire — NativeDatabase.createInBackground()
// combine a sqlite3_flutter_libs (deja dans pubspec.yaml, Doc K3 §3) suffit
// intégralement sur Windows Desktop. Le plugin gere seul la resolution de
// sqlite3.dll, sans intervention manuelle.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'logialvia.db'));
    return NativeDatabase.createInBackground(file);
  });
}

// main.dart : aucun appel d'initialisation SQLite specifique requis avant runApp()
void main() {
  runApp(const LogiALVIAApp());
}
```

**Ne jamais réintroduire** `open.overrideFor(...)`, `DynamicLibrary.open('sqlite3.dll')` manuel, ni aucune référence à `OperatingSystem` de `package:sqlite3/open.dart` dans ce projet — ce sont exactement les symptômes du bug déjà rencontré et corrigé (Doc K4 §1, Bug #2).

---

## 6. Piège d'Import — conflit `Column` Drift vs Flutter

**Deuxième point de vigilance critique**, déjà rencontré et documenté sur AgriERP Windows. `Column` est à la fois un widget Flutter (mise en page verticale) et une classe Drift (colonne de table SQL) — le même nom, deux significations totalement différentes.

```dart
// ❌ Dans un fichier qui melange UI Flutter et definitions de table Drift
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
// ERREUR DE COMPILATION : Column est ambigu

// ✅ Dans les fichiers de DEFINITION DE TABLE (data/local/tables/*.dart)
import 'package:drift/drift.dart'; // Column = colonne SQL, OK, pas de widget ici

// ✅ Dans les fichiers UI qui importent aussi Drift (rare, mais arrive
//    pour les Stream de donnees reactives)
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart'; // Column = widget, sans ambiguite
```

**Règle simple à appliquer partout** : tout fichier dans `presentation/` qui a besoin d'importer Drift (rare — normalement seul `data/` en a besoin) doit systématiquement écrire `hide Column`.

### Même piège, deuxième occurrence réelle — `isNull` / `isNotNull` dans les tests

Rencontré à la compilation lors de l'écriture des tests du module Pilotage (Doc F2). Drift exporte `isNull` et `isNotNull` (des **expressions SQL**), `flutter_test` exporte les matchers du même nom. Tout fichier de test qui importe les deux échoue :

```dart
// ❌ ambiguous_import sur isNull / isNotNull
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

// ✅ Dans un fichier de test qui manipule des Companions Drift
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
```

**Règle généralisée** : à chaque import de `package:drift/drift.dart` hors de `data/`, se demander quels noms entrent en collision avec la bibliothèque d'en face — `Column` face à Flutter, `isNull`/`isNotNull` face à `flutter_test`. Le `hide` est la réponse dans les deux cas.

---

## 6-TER. Piège Drift — `insertOnConflictUpdate()` cible la clé primaire, pas vos contraintes `UNIQUE`

**Bug réellement rencontré et corrigé** lors de l'implémentation du module Élevage (Doc F3), détecté uniquement parce qu'un test couvrait le réenregistrement d'un même jour.

`FICHE_JOURNEE` a une clé primaire technique `id` auto-incrémentée **et** une contrainte métier `UNIQUE(espece, date)` (Doc D1). `insertOnConflictUpdate()` résout le conflit sur la **clé primaire** : un `id` auto-généré n'entre jamais en collision, donc l'insertion partait systématiquement en violation de la contrainte `UNIQUE` au lieu de mettre la ligne à jour.

```dart
// ❌ Ne met jamais a jour : le conflit vise `id`, qui ne collisionne jamais
await db.into(db.ficheJournee).insertOnConflictUpdate(companion);

// ✅ Cible explicite sur la contrainte metier
await db.into(db.ficheJournee).insert(
  companion,
  onConflict: DoUpdate(
    (_) => companion,
    target: [db.ficheJournee.espece, db.ficheJournee.date],
  ),
);
```

**Règle** : dès qu'une table a une clé primaire technique *et* une contrainte d'unicité métier, `insertOnConflictUpdate()` sans `target` est presque toujours faux. Concerne aussi `FICHE_VENTES_JOUR` (`UNIQUE(espece, date)`), `NOTES_ANNEXES` (`UNIQUE(exerciceAnnee, numeroNote)`) et `CLOTURES_PERIODIQUES`.

**Leçon secondaire, plus importante encore** : l'erreur était **invisible**, avalée par un `catch (e)` qui renvoyait un `Echec` générique. L'écran affichait l'ancienne valeur sans message d'erreur. Tout `catch` large doit journaliser le détail technique sous `kDebugMode` (Doc I3 §3) — sans quoi il transforme un bug franc en anomalie silencieuse.

---

## 6-BIS. Contrainte de version réelle — `intl` et `flutter_localizations`

La liste de dépendances de §3 indique `intl: ^0.19.0`. **Cette contrainte est incompatible** avec `flutter_localizations`, requis pour franciser les composants Material (sélecteur de date, menus) conformément à Doc A1 §5 : le SDK Flutter y épingle `intl 0.20.2`.

```
Because logialvia_app depends on flutter_localizations from sdk which depends
on intl 0.20.2, intl 0.20.2 is required.
```

La contrainte réelle du projet est donc `intl: ^0.20.2`, imposée par le SDK et non choisie.

---

## 7. Génération du Code Drift

Après toute modification d'une table dans `data/local/tables/` :

```bash
dart run build_runner build --delete-conflicting-outputs
```

En développement actif, préférer le mode watch :
```bash
dart run build_runner watch --delete-conflicting-outputs
```

---

## 8. Fenêtre Desktop — dimensions initiales

Pour cohérence avec les breakpoints `lg`/`xl` du design web (Doc 10) :

```dart
// main.dart
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // CORRECTIF : aucun appel SQLite specifique requis ici — voir §6 ci-dessus,
  // NativeDatabase.createInBackground() suffit seul.

  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1440, 900),        // correspond au breakpoint xl (1280px+) du prototype
    minimumSize: Size(1024, 700), // correspond au breakpoint lg
    center: true,
    title: 'LogiALVIA — ALLMANY ET COMPAGNIE',
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const LogiALVIAApp());
}
```

---

## 9. Premier Lancement

```bash
flutter analyze          # DOIT etre execute et corrige avant tout usage —
                          # je n'ai pas pu le faire de mon cote (Doc 00)
flutter run -d windows
```

## 10. Build de Production

```bash
flutter build windows --release
```
L'exécutable se trouve dans `build/windows/x64/runner/Release/`.

---

## 11. Checklist Post-Setup (avant de commencer l'implémentation des écrans)

- [ ] `flutter doctor -v` sans `[✗]`
- [ ] `flutter pub get` réussi sans conflit de version
- [ ] `dart run build_runner build` réussi (génère `database.g.dart` et équivalents)
- [ ] `flutter run -d windows` lance une fenêtre vide sans erreur
- [ ] Police Roboto visible (tester un `Text()` simple avec `fontFamily: 'Roboto'`)
- [ ] Base SQLite créée au bon emplacement (vérifier via `getApplicationSupportDirectory()`) et accessible en écriture
- [ ] Décision tranchée sur le package d'icônes (Doc 01 section 5) avant de commencer Doc 06/08
