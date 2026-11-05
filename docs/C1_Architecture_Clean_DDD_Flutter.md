# C1 — Architecture Logicielle Complète — Clean Architecture + DDD + Flutter Desktop

Ce document remplace et enrichit `02_ARCHITECTURE.md` (conservé comme référence historique, mais ce document C1 prévaut en cas de divergence). Il ajoute la dimension **Domain-Driven Design** absente de la première version, nécessaire pour un système à plusieurs domaines métier distincts (Élevage, Commercial, Comptabilité, Administration) qui doivent rester découplés tout en communiquant de façon fiable.

---

## 1. Pourquoi DDD sur ce Projet Précisément

`logialvia-store.js`, la couche de synchronisation déjà construite côté web, résout déjà un vrai problème DDD sans le nommer : une vente (domaine Commercial) doit notifier le domaine Élevage (compteur de vente du jour) sans que ces deux domaines ne soient étroitement couplés dans le code. Le pattern JS `window.dispatchEvent(new CustomEvent('logialvia:update'))` est un **événement de domaine** informel. Ce document formalise ce même besoin avec le vocabulaire et les garanties du DDD, pour que la traduction Dart ne perde pas cette qualité de conception déjà présente côté web.

---

## 2. Bounded Contexts (Contextes Délimités)

| Bounded Context | Responsabilité | Langage ubiquitaire propre |
|---|---|---|
| **Élevage** | Suivi journalier des effectifs par espèce et catégorie, cycle de couvoir, soins | Fiche, Effectif, Catégorie, Mortalité, Cascade, SRH/TS/Stock Final |
| **Commercial** | Vente, catalogue produit, stock vendable | Panier, Ligne de Vente, Remise, Statut (Payée/Avance/Annulée) |
| **Approvisionnement** | Intrants, fournisseurs, achats | Intrant, Seuil d'Alerte, Commande, PMP (Prix Moyen Pondéré) |
| **Comptabilité** | Journal, plan comptable, exercices | Écriture, Débit/Crédit, Exercice, Report à Nouveau, Clôture |
| **Administration** | Utilisateurs, rôles, modules actifs | Rôle, Permission, Module |

**Règle DDD appliquée** : un terme métier n'a de sens que dans son contexte. "Stock" dans le contexte Commercial désigne un produit vendable ; "Stock" dans le contexte Approvisionnement désigne un intrant. Ces deux notions ne doivent **jamais** partager la même entité de code, même si elles se ressemblent structurellement (voir Doc D1, tables `ProduitsVendables` vs `Intrants`, déjà séparées pour cette raison précise).

---

## 3. Agrégats (Aggregates) par Contexte

Un agrégat a une **racine** (Aggregate Root) qui est le seul point d'entrée pour toute modification — garantit la cohérence interne.

### Contexte Élevage
```
FicheEspece (Aggregate Root)
  └── JourneeElevage[] (Entities, une par jour du mois)
        └── contient : mouvements (achat/ne/vente/mort/don par categorie),
                        sous-effectifs calcules, et pour Pondeuses : SRH/TS/StockFinal
```
**Invariant garanti par l'agrégat** : on ne peut jamais persister une `JourneeElevage` dont l'effectif d'une catégorie serait négatif (BR-ELV-001) — la validation vit dans l'agrégat, pas dispersée dans l'UI.

### Contexte Commercial
```
Vente (Aggregate Root)
  └── LigneVente[] (Entities)

Produit (Aggregate Root, independant)
```
**Invariant garanti** : une `Vente` ne peut être créée avec une `LigneVente` dont la quantité dépasse le stock du `Produit` référencé au moment de la création (BR-VTE-001) — vérifié à la construction de l'agrégat, avant toute persistance.

### Contexte Comptabilité
```
ExerciceComptable (Aggregate Root)
  └── EcritureComptable[] (Entities)
```
**Invariant garanti** : aucune `EcritureComptable` ne peut être ajoutée ou modifiée si `ExerciceComptable.isCloture == true` (BR-CPT-001).

---

## 4. Événements de Domaine (Domain Events)

Remplace et formalise le `CustomEvent('logialvia:update')` du prototype JS. Chaque événement est une classe Dart immuable, publiée par un agrégat après une opération réussie, consommée par un `EventBus` (ou par les listeners `Provider` directement, selon la taille réelle du besoin).

```dart
// domain/events/domain_event.dart
abstract class DomainEvent {
  final DateTime occurredAt;
  DomainEvent() : occurredAt = DateTime.now();
}

class VenteValideeEvent extends DomainEvent {
  final String venteRef;
  final List<LigneVenteInfo> lignes; // produitId, qte, espece nullable
  VenteValideeEvent({required this.venteRef, required this.lignes});
}

class VenteAnnuleeEvent extends DomainEvent {
  final String venteRef;
  final List<LigneVenteInfo> lignes;
  VenteAnnuleeEvent({required this.venteRef, required this.lignes});
}

class ExerciceClotureEvent extends DomainEvent {
  final int exerciceAnneeCloturee;
  ExerciceClotureEvent({required this.exerciceAnneeCloturee});
}
```

### Qui écoute quoi (table de routage des événements)

| Événement | Émis par | Consommé par |
|---|---|---|
| `VenteValideeEvent` | `usecases/EnregistrerVenteUseCase` (Commercial) | `StockProvider` (décrémente), `FicheEspeceProvider` (incrémente vente du jour) |
| `VenteAnnuleeEvent` | `usecases/AnnulerVenteUseCase` (Commercial) | `StockProvider` (restitue) |
| `ExerciceClotureEvent` | `usecases/ClorerExerciceUseCase` (Comptabilité) | `RapportsProvider` (invalide le cache des rapports de l'exercice clôturé) |

**Règle stricte** : un `usecase` d'un contexte ne doit **jamais** appeler directement un `Repository` d'un autre contexte. La communication inter-contextes passe uniquement par les événements de domaine ci-dessus — c'est le mécanisme qui garantit le découplage entre Élevage et Commercial (Strict Avoid §3, code spaghetti).

---

## 5. Value Objects — là où l'identité n'a pas d'importance

```dart
// domain/value_objects/montant_fcfa.dart
class MontantFCFA {
  final int valeur; // toujours un entier, jamais de decimal — FCFA n'a pas de sous-unite
  const MontantFCFA(this.valeur) : assert(valeur >= 0, 'Un montant ne peut etre negatif');

  MontantFCFA operator +(MontantFCFA other) => MontantFCFA(valeur + other.valeur);
  MontantFCFA operator -(MontantFCFA other) => MontantFCFA((valeur - other.valeur).clamp(0, 1 << 62));

  String formate() => '${valeur.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]} ')} FCFA';
}
```
Utiliser `MontantFCFA` plutôt qu'un simple `int`/`double` partout où un montant circule évite la classe d'erreurs "FCFA confondu avec une quantité" et centralise le formatage (NFRS-MAINT-02, zéro duplication).

---

## 6. Couches Techniques — reprise enrichie de Doc 02

```
lib/
├── core/                     # Inchangé — voir Doc 02 et Doc E
│
├── <bounded_context>/         # Un dossier par contexte delimite, PAS un decoupage
│   │                           # technique global data/domain/presentation en tete de projet
│   ├── domain/
│   │   ├── entities/
│   │   ├── value_objects/
│   │   ├── events/
│   │   ├── repositories/      # interfaces
│   │   └── usecases/
│   ├── data/
│   │   ├── tables/
│   │   └── repositories/      # implementations
│   └── presentation/
│       └── screens/
│
# Exemple concret :
├── elevage/
│   ├── domain/...
│   ├── data/...
│   └── presentation/screens/fiches/fiche_goliaths_screen.dart
├── commercial/
│   ├── domain/...
│   ├── data/...
│   └── presentation/screens/ventes/ventes_screen.dart
├── comptabilite/...
└── administration/...
```

**Écart avec Doc 02** : la première version proposait un découpage technique global (`data/`, `domain/`, `presentation/` à la racine). Cette version C1 le remplace par un découpage **par contexte métier d'abord**, technique ensuite — cohérent avec le principe DDD que les frontières de module suivent les frontières métier, pas les couches techniques. Ce changement est à trancher explicitement avant de commencer l'implémentation (voir question ouverte ci-dessous).

---

## 7. Décision Actée — Découpage par Bounded Context

**Tranché.** Option 1 retenue : découpage par Bounded Context (section 6), pas le découpage technique global de Doc 02. Aucun code n'existant encore au moment de cette décision (implémentation démarrant avec Claude Code), l'argument de coût de réorganisation qui motivait la prudence par défaut ne s'applique plus.

**Justification** :
1. Correspondance directe et sans ambiguïté avec la documentation par module (`lib/elevage/`↔Doc F3, `lib/commercial/`↔Doc F4, `lib/approvisionnement/`↔Doc F5, `lib/comptabilite/`↔Doc F6, `lib/administration/`↔Doc F8)
2. Rend visibles physiquement dans l'arborescence les frontières entre contextes déjà conçues (Doc G1, événements de domaine `VenteValideeEvent` etc.) — réduit le risque de couplage direct accidentel entre contextes qui devraient communiquer uniquement par événement
3. `lib/core/` reste le dossier technique transversal (thème, widgets partagés, event bus, base de données) — seul le contenu métier est réorganisé par contexte, pas l'infrastructure

**Arborescence finale** :
```
lib/
├── core/
│   ├── theme/          (app_colors, app_typography, app_spacing…)
│   ├── widgets/         (AppButton, AppFormField, AppToast, KpiCard…)
│   ├── database/        (AppDatabase Drift, connexion)
│   ├── events/          (event bus, VenteValideeEvent, ExerciceClotureEvent…)
│   └── router/          (go_router, PermissionService)
├── elevage/
│   ├── domain/          (entités Fiche, Effectif, usecases)
│   ├── data/            (repositories, DAOs Drift)
│   └── presentation/     (screens/fiches/, screens/couveuse/, screens/soins/, controllers/)
├── commercial/
│   ├── domain/
│   ├── data/
│   └── presentation/     (screens/ventes/, screens/clients/)
├── approvisionnement/
│   ├── domain/
│   ├── data/
│   └── presentation/     (screens/stocks/, screens/achats/, screens/fournisseurs/)
├── comptabilite/
│   ├── domain/
│   ├── data/
│   └── presentation/     (screens/journal/, screens/grand_livre/, screens/etats_financiers/…)
├── administration/
│   ├── domain/
│   ├── data/
│   └── presentation/     (screens/parametres/, screens/utilisateurs/)
├── pilotage/            (tableaux de bord — Doc F2, lecture seule)
├── rapports/            (Rapports & Etats — Doc F7, lecture seule, AUCUNE table)
│   ├── domain/
│   ├── data/
│   └── presentation/
└── main.dart             (MultiProvider global, Doc K4 §5 — tous les Providers partages ici,
                            jamais enregistres localement dans un seul ecran)
```

### Exception actée à la règle de dépendance — les contextes de lecture

Deux contextes ne possèdent **aucune table** et ne persistent rien : `pilotage/` (tableaux de bord, Doc F2) et `rapports/` (Rapports & États, Doc F7). Ce sont des **modèles de lecture transverses**.

Un tableau de bord et un rapport de gestion sont par nature transversaux : le Rapport Élevage croise fiches journalières, lignes de vente, soins, infirmerie et couvoir sur une même ligne. Les faire passer par des événements de domaine n'aurait aucun sens — un événement transporte un fait qui vient de se produire, pas une agrégation historique sur une période choisie par l'utilisatrice.

**Règle précisée** : ces deux contextes peuvent lire les tables des autres, en **lecture seule et sans jamais écrire**. Aucun autre contexte ne bénéficie de cette exception, et la règle générale ci-dessous reste valable pour tous les autres.
**Règle de dépendance entre contextes** : un dossier `<contexte>/domain/` ne doit jamais importer directement un `<autre_contexte>/domain/` — toute communication inter-contexte passe par `core/events/` (Doc G1). Si un usecase de `commercial/` a besoin d'une donnée d'`elevage/`, c'est un signal qu'un événement de domaine manque, pas une raison d'importer directement.

### Compléments issus de l'implémentation réelle du module F1

L'arborescence ci-dessus a été appliquée telle quelle. Trois précisions qu'elle ne couvrait pas et que le premier module a rendues nécessaires :

| Élément | Emplacement retenu | Pourquoi |
|---|---|---|
| `core/resultat/` | `Resultat<T>` / `Succes` / `Echec` | Pattern d'erreur uniforme de Doc K1 §8, utilisé par tous les contextes — sa place est dans `core/`, au même titre que `theme/` ou `widgets/` |
| `administration/presentation/screens/auth/` | Splash, Welcome, Login | Le module F1 appartient au contexte Administration : son langage ubiquitaire (Rôle, Permission, Utilisateur) est exactement celui attribué à ce contexte en §2. Créer un contexte « auth » séparé aurait scindé un même vocabulaire métier en deux |
| Tables Drift | `<contexte>/data/tables/`, remontées vers `core/database/AppDatabase` | Drift exige un `@DriftDatabase` **unique** (génération de code) pour une base unique. Chaque contexte déclare donc ses tables chez lui, mais un seul point d'entrée les assemble. C'est le seul endroit où `core/` connaît les contextes — compromis imposé par l'outil, sans impact sur le découplage métier : aucun `usecase` n'accède aux tables d'un autre contexte |

**Précision sur `core/router/`** : `PermissionService` (Doc I1 §4) y est placé plutôt que dans `administration/domain/` — il est consommé par le `redirect` de `go_router` (Doc E3 §6), et l'y loger évite une dépendance `core/` → `administration/domain/` sur une règle qui gouverne la navigation globale.
