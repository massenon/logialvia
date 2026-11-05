# K4 — Retour d'Expérience : Bugs Réels Rencontrés (Projet Jumeau AgriERP Flutter Desktop)

**Ce document n'existait pas dans la documentation d'origine.** Il capture des bugs **réellement rencontrés et corrigés** lors du développement effectif du projet jumeau AgriERP Windows (même stack technique : Flutter Desktop, Drift/SQLite, Provider) — des difficultés qu'aucun document de spécification, aussi rigoureux soit-il, ne peut anticiper avant la première compilation réelle. LogiALVIA utilisant exactement la même stack (Doc C1, Doc K3), ces bugs sont **des risques directement transposables**, pas des curiosités isolées à un autre projet.

**Une correction déjà appliquée suite à cet audit** : Doc K3 §6 (persistance SQLite Windows) contenait un pattern invalide (`open.overrideFor(...)`) — corrigé rétroactivement dans ce même passage grâce aux découvertes ci-dessous. C'est la preuve concrète de l'utilité de ce document : sans lui, ce bug aurait été reproduit sur LogiALVIA avant d'être détecté à la compilation.

---

## 1. Bugs de Compilation Bloquants (le projet ne compile pas du tout)

### Bug #1 — Import manquant provoquant une erreur de compilation immédiate
**Symptôme réel** : `LoginScreen()` utilisé dans `main.dart` mais jamais importé → échec de compilation.
**Cause** : import oublié lors d'un refactoring, aucun outil ne l'a signalé avant `flutter run`.
**Contrôle préventif pour LogiALVIA** : `flutter analyze` **avant** tout `flutter run` — déjà posé en Doc K1 §6, ce bug réel en est la justification concrète, pas une précaution théorique.

### Bug #2 — API SQLite invalide sous Windows (déjà corrigé rétroactivement en Doc K3 §6)
**Symptôme réel** : `open.overrideFor(OperatingSystem.windows, flutter_libs.openOnWindows)` → `OperatingSystem`, `open` et `openOnWindows` sont des API bas niveau qui n'existent pas dans `sqlite3_flutter_libs` 0.5.x et entrent en conflit avec le chargement automatique de la DLL par le plugin.
**Correction réelle appliquée** : suppression complète du bloc d'override et des imports `sqlite3`/`sqlite3_flutter_libs` correspondants — `NativeDatabase.createInBackground()` combiné à `path_provider` suffit intégralement.
**Statut sur LogiALVIA** : déjà intégré en Doc K3 §6, ne pas régresser vers l'ancien pattern.

### Bug — `const` invalide sur un widget dépendant d'une valeur runtime
**Symptôme réel** : `const _RootRouter()` → *"Not a constant expression"* à la compilation.
**Cause** : le widget racine recevait en réalité une valeur déterminée à l'exécution (l'instance de base de données), rendant l'expression non constante malgré un constructeur `const` déclaré sur la classe.
**Correction réelle** : retrait du mot-clé `const` devant l'instanciation.
**Règle à appliquer sur LogiALVIA** : ne jamais marquer `const` un widget racine qui reçoit `database`/`repository` en paramètre de constructeur — ces valeurs sont systématiquement déterminées à l'exécution (Doc C1 §4, injection manuelle par constructeur).

---

## 2. Bugs Drift — Opérateurs de Requête Invalides (le plus critique pour LogiALVIA)

**Cause racine identifiée** : Drift 2.31.0 (version réellement utilisée sur AgriERP) n'implémente pas l'opérateur `&` sur `Expression<bool>` — absent de cette version, ajouté seulement dans des versions Drift plus récentes. **Vérifier la version exacte de Drift dans `pubspec.yaml` avant de choisir un pattern.**

> ### ⚠️ Vérification faite sur LogiALVIA — la situation est **inversée** sur Drift 2.34.3
>
> Constat de compilation réel lors de l'implémentation du module Pilotage (Doc F2), sur la version que `flutter pub get` résout aujourd'hui (**Drift 2.34.3**) :
>
> | Pattern | Drift 2.31 (AgriERP) | Drift 2.34.3 (LogiALVIA) |
> |---|---|---|
> | `a & b` sur `Expression<bool>` | ❌ n'existe pas | ✅ **c'est le pattern correct** |
> | `a.and(b)` (chaînage) | ✅ correction retenue | ❌ **ne compile pas** — `Expression.and()` y est une méthode **statique** prenant un `Iterable<Expression<bool>>`, pas une méthode d'instance |
> | `p.stock.isSmallerOrEqual(p.threshold)` colonne-à-colonne | ❌ échouait | ✅ **fonctionne** — le `CustomExpression<bool>` prescrit en Bug #3b n'est plus nécessaire |
>
> **Conséquence pratique** : sur LogiALVIA, les conditions se combinent avec `&`, et les comparaisons colonne-à-colonne utilisent l'API typée — jamais de SQL brut, ce qui est *préférable* du point de vue de Strict Avoid §1. La leçon transversale de ce paragraphe reste entièrement valable : **le pattern dépend de la version, il faut la vérifier avant de choisir**. C'est précisément ce qui a évité ici de reproduire à l'aveugle une correction pourtant issue d'un projet à stack « identique ».

### Bug #3a — Combinaison de conditions avec `&`
```dart
// ECHOUE sur Drift 2.31.0 — "The operator '&' isn't defined for the type 'Expression<bool>'"
a.date.isBetweenValues(start, end) & a.status.equals('present')
```
**Correction réelle validée** :
```dart
// Option 1 -- chainage .and()
a.date.isBetweenValues(start, end).and(a.status.equals('present'))

// Option 2 -- deux .where() chaines (equivalent, parfois plus lisible)
query
  ..where((x) => x.date.isBetweenValues(start, end))
  ..where((x) => x.status.equals('present'))
```

### Bug #3b — Comparaison colonne-à-colonne
```dart
// ECHOUE -- comparaison colonne-a-colonne non supportee directement par l'API Drift
p.stockQty.isSmallerOrEqual(p.alertQty)
```
**Correction réelle validée** :
```dart
// Expression SQL brute, deleguee directement a SQLite
const CustomExpression<bool>('stock_qty <= alert_qty')
```
**Application directe à LogiALVIA** : ce pattern exact (`stock ≤ threshold`) est utilisé dans **Doc D1** pour toutes les alertes de seuil critique (`PRODUITS_VENDABLES`, `INTRANTS`). Le code Dart correspondant doit utiliser `CustomExpression<bool>`, jamais `.isSmallerOrEqual()` colonne-à-colonne :
```dart
// usecases/DetecterArticlesEnAlerteUseCase -- pattern a respecter partout ou ce
// besoin se represente (Doc D1, Doc F5 Ecran 1)
final articlesEnAlerte = await (db.select(db.produitsVendables)
  ..where((p) => const CustomExpression<bool>('stock <= threshold')))
  .get();
```

### Bug #4 — Même bug répété ailleurs dans le code (répétition = signe de pattern non documenté)
Le même bug `isSmallerOrEqual` colonne-à-colonne est réapparu dans 2 méthodes distinctes (`watchLowStockProducts`, `countLowStockProducts`) — confirmant qu'un bug non documenté se reproduit mécaniquement partout où le même besoin métier existe.
**Leçon pour LogiALVIA** : dès qu'un pattern Drift pose problème une fois, `grep` immédiatement l'ensemble du projet pour toute occurrence similaire — ne pas corriger au cas par cas au fil des découvertes (Strict Avoid §5, cohérence des patterns).

---

## 3. Bug Drift — Type de Valeur Incorrect dans un Companion

```dart
// ECHOUE -- un champ integer()() NON-NULLABLE attend un int brut dans .insert(),
// pas un Value<int> (Value<T> sert a exprimer un NULL explicite ou une absence
// de valeur pour un UPDATE partiel, pas a envelopper une valeur simple a l'insertion)
currentCount: Value(initialCount)

// Correction reelle validee
currentCount: initialCount
```
**Application à LogiALVIA** : ce piège concerne tout champ non-nullable de `FICHE_JOURNEE`, `PRODUITS_VENDABLES`, `INTRANTS` (Doc D1) lors d'un `.insert()` — vérifier systématiquement qu'aucun `Value(...)` n'enveloppe inutilement un champ non-nullable dans les `usecases` d'insertion.

---

## 4. Bug d'Architecture — Méthode Manquante sur un Contrôleur

**Symptôme réel** : `controller.watchRecentExpenses()` appelé depuis l'écran, mais `PurchaseController` n'exposait réellement que `watchRecentPurchases()` — nom différent, pas de méthode manquante par erreur de frappe simple.
**Cause probable** : l'écran a été écrit en anticipant une méthode qui n'a jamais été ajoutée au contrôleur, ou renommée sans répercuter le changement.
**Contrôle préventif pour LogiALVIA** : avant d'écrire un écran (`presentation/`) qui appelle une méthode de `ViewModel`, vérifier que cette méthode existe réellement dans le fichier du `ViewModel` — ne jamais écrire l'appel en anticipant une méthode "à créer plus tard".

---

## 5. Bug d'Architecture — Provider Non Enregistré Globalement ("Écran Rouge de la Mort")

**Symptôme réel** : les modales `ProductFormDialog` et `EmployeeFormDialog` plantaient instantanément à l'ouverture — leurs contrôleurs (`ProductController`, `HrController`) n'étaient pas trouvés dans le `BuildContext`.
**Cause** : ces contrôleurs étaient enregistrés localement quelque part dans l'arbre de widgets, pas au niveau global de `main.dart`.
**Correction réelle** : déplacement de **tous** les contrôleurs nécessaires aux modales vers le `MultiProvider` global enveloppant `AppShell` dans `main.dart`.

**Application directe à LogiALVIA** — règle déjà posée en Doc C1 §2 (Providers globaux), renforcée ici par ce cas réel :
> Toute modale accessible depuis plusieurs écrans (Doc E5, `AppModal`) doit avoir son `ViewModel`/`Provider` enregistré **globalement** dans `main.dart`, jamais localement dans un seul écran parent — sans quoi la modale plante dès qu'elle est invoquée depuis un contexte où ce Provider local n'existe pas.

```dart
// Risque : StockViewModel enregistre seulement dans gestion_stocks_screen.dart
// -> plante si la modale Ajouter Stock est un jour invoquee depuis le Dashboard
// (alerte "Commander" -> ouvre directement la modale d'ajout)

// Correct : tous les Providers de modales partagees, dans main.dart
MultiProvider(providers: [
  ChangeNotifierProvider(create: (_) => StockProvider(stockRepository)),
  ChangeNotifierProvider(create: (_) => VentesProvider(ventesRepository)),
  ChangeNotifierProvider(create: (_) => FicheEspeceProvider(ficheRepository)),
  ChangeNotifierProvider(create: (_) => ComptabiliteProvider(comptaRepository)),
  // ... TOUT provider dont une modale partagee pourrait avoir besoin
], child: const LogiALVIAApp())
```

---

## 6. Bug UI — Bordure Arrondie avec Couleurs Non-Uniformes

**Symptôme réel** (`KpiStatCard`) : `borderRadius` combiné à un `Border` dont les côtés ont des couleurs différentes (ex : bordure gauche colorée sémantiquement, Doc E7 §4) provoque une erreur ou un rendu incorrect — Flutter exige des couleurs uniformes sur un `Border` utilisé avec `borderRadius`.
**Correction réelle** : remplacer la combinaison `Border` + `borderRadius` par `ClipRRect` + `Stack` (couche de fond arrondie, bordure colorée superposée séparément).

**Application directe à LogiALVIA** : le composant `KpiCard` (Doc E2 §3) utilise précisément une bordure gauche colorée sémantiquement (`border-l-4 border-l-*` côté web) — **risque direct de reproduire ce bug exact**. Le code Dart de `KpiCard` déjà fourni utilise `Container` + une bande de couleur séparée (pas un `Border` à couleurs mixtes), ce qui évite structurellement ce piège — **à vérifier explicitement lors de l'implémentation réelle**, ne pas remplacer par un `Border` multi-couleurs par souci de "simplification" apparente.

---

## 7. Constat Architectural — Trop de Variantes de Dashboard (leçon UX, pas seulement technique)

**Constat réel sur AgriERP** : 3 tableaux de bord distincts (Général / KPI Temps Réel / Vue Exécutive DG) créaient une surcharge cognitive et une navigation confuse, en plus de dupliquer le module Rapports & Exports via un groupe de navigation "Analyses" redondant.
**Correctif appliqué** : suppression des dashboards redondants, **un seul tableau de bord avec affichage dynamique selon le rôle connecté**, suppression du groupe "Analyses" (doublon de Rapports & Exports).

**Vérification pour LogiALVIA** : Doc F2 (module Pilotage) ne définit que 2 dashboards (Principal + Élevage), avec un périmètre clairement distinct l'un de l'autre (pas de doublon) — **ce risque ne s'applique pas tel quel à LogiALVIA**, mais la règle générale reste applicable : **avant d'ajouter un nouvel écran de synthèse/rapport, vérifier explicitement qu'il ne duplique pas un écran existant** (Doc F7, Rapports & Exports, couvre déjà 6 domaines — toute nouvelle demande de "vue" doit d'abord être confrontée à cette liste).

---

## 8. Procédure de Peuplement Initial — Compte Administrateur Semeur (Seeder)

Point pratique confirmé sur AgriERP, directement applicable à LogiALVIA : au premier lancement, la base est vide — aucun compte utilisateur n'existe pour se connecter (Doc F1 Écran 3, Doc D1 `UTILISATEURS`). Un **seeder** doit créer un compte administrateur initial de façon idempotente (ne recrée pas le compte s'il existe déjà, ne réinitialise jamais les données déjà saisies par un utilisateur réel).

```dart
// data/local/seed/admin_seeder.dart
class AdminSeeder {
  final AppDatabase db;
  AdminSeeder(this.db);

  Future<void> executer() async {
    final adminExistant = await (db.select(db.utilisateurs)
      ..where((u) => u.identifiant.equals('admin')))
      .getSingleOrNull();
    if (adminExistant != null) return; // idempotent -- ne rien faire si deja seede

    await db.into(db.roles).insert(RolesCompanion.insert(id: 'admin', libelle: 'Administratrice'));
    // ... creer les 2 autres roles reels (Doc I1, corrige ci-dessous) :
    // caissier (Agent de Vente), animalier (Agent d'Elevage)

    await db.into(db.utilisateurs).insert(UtilisateursCompanion.insert(
      nom: 'Administratrice Principale',
      identifiant: 'admin',
      roleId: 'admin',
      // motDePasseHash: ... (Doc F1, hachage a definir explicitement)
    ));
  }
}

// Appele une fois au demarrage, apres ouverture de la base, avant runApp()
```

**⚠️ Correction à propager à Doc I1** : ce retour d'expérience confirme, via `sidebar.js` réel (déjà audité séparément lors d'un tour précédent), que LogiALVIA utilise **3 rôles réels** (`admin`, `animalier`, `caissier`), **pas 4** — le rôle `comptable` que Doc I1 documentait comme rôle technique séparé n'existe pas dans le fichier réel (son commentaire d'en-tête dit explicitement *"3 roles RBAC (pas 4)... aucun role comptable"*). Correction appliquée ci-dessous en fin de document.

---

## 9. Méthode d'Audit à Reproduire pour LogiALVIA (le vrai enseignement transversal)

Au-delà de chaque bug individuel, la méthode qui les a détectés est elle-même la leçon la plus transposable :
1. **Lire le code source réel avant d'écrire un correctif** — jamais de correction "à l'aveugle" sur la base d'une supposition
2. **Confirmer chaque bug par la lecture du fichier concerné**, pas par déduction théorique
3. **Après correction d'un pattern, `grep` l'ensemble du projet** pour toute occurrence similaire (Bug #4, la répétition du même bug ailleurs)
4. **Audit exhaustif final** sur l'ensemble des fichiers du projet avant de considérer une session de correctifs terminée (l'audit réel a couvert la totalité des 221 fichiers Dart du projet, pas un échantillon)

Cette méthode est directement celle déjà appliquée tout au long de cette série de documents LogiALVIA (validation systématique HTML5/JS après chaque modification, vérification par script Python indépendant des calculs comptables) — ce retour d'expérience Flutter en est la confirmation qu'elle reste valable, changement de langage et de plateforme inclus.

---

## 10. Correction Appliquée à Doc I1 (Matrice RBAC) suite à ce Retour d'Expérience

Le tableau de rôles de Doc I1 est corrigé pour refléter les **3 rôles réels confirmés** (`admin`, `animalier`, `caissier`) — le rôle `comptable` en tant que 4ᵉ rôle technique distinct est retiré ; les permissions qui lui étaient attribuées (Comptabilité, Rapports financiers) sont reportées sur `admin`, seul rôle ayant réellement accès à la section Comptabilité dans `sidebar.js` (`data-role-group="admin"` sur toute la section, confirmé ligne par ligne).
