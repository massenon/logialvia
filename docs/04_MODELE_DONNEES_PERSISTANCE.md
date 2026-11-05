# 04 — Modèle de Données & Persistance (Drift/SQLite)

Traduction fidèle de `assets/js/logialvia-store.js` (couche de synchronisation `localStorage` déjà construite et validée côté web) vers un schéma **Drift** (SQLite) pour Flutter Desktop.

**Principe directeur** : chaque fonction JS de `LogiALVIASync` a un équivalent Dart 1:1 dans `data/repositories/`. Aucune logique métier nouvelle n'est inventée — uniquement traduite.

---

## 1. Tables Drift

### `ProduitsVendables` (équivalent de `DEFAULT_STOCK` / `getStock()`)

```dart
import 'package:drift/drift.dart' hide Column;
import 'package:drift/drift.dart' as drift;

class ProduitsVendables extends drift.Table {
  drift.IntColumn get id => integer().autoIncrement()();
  drift.TextColumn get name => text()();
  drift.TextColumn get cat => text()();          // 'Avicole' | 'Commerce Annexe'
  drift.RealColumn get price => real()();          // prix indicatif bas
  drift.RealColumn get priceMax => real().nullable()(); // prix indicatif haut (fourchette)
  drift.TextColumn get unit => text()();           // 'u', 'sujet(s)', 'lot(s)', 'paire(s)'
  drift.TextColumn get icon => text()();           // nom d'icone Material Symbols
  drift.IntColumn get stock => integer()();
  drift.IntColumn get threshold => integer()();
  drift.TextColumn get espece => text().nullable()(); // 'goliaths' | 'pintades' | null
}
```

### `Intrants` (équivalent de `DEFAULT_INTRANTS` / `getIntrants()`)

```dart
class Intrants extends drift.Table {
  drift.TextColumn get code => text()();  // cle primaire textuelle, ex: 'INT-001'
  drift.TextColumn get name => text()();
  drift.TextColumn get cat => text()();   // 'Intrants Provende' | 'Marchandises' | 'Veterinaire'
  drift.IntColumn get stock => integer()();
  drift.TextColumn get unit => text()();
  drift.IntColumn get threshold => integer()();
  drift.IntColumn get pmp => integer()(); // prix unitaire moyen pondere, FCFA

  @override
  Set<drift.Column> get primaryKey => {code};
}
```

### `Ventes` (équivalent de `DEFAULT_VENTES` / `addVente()` / `getVentes()`)

```dart
class Ventes extends drift.Table {
  drift.TextColumn get ref => text()();  // cle primaire textuelle, ex: 'V-2026-148'
  drift.TextColumn get client => text()();
  drift.DateTimeColumn get dateVente => dateTime()();
  drift.TextColumn get mode => text()();    // 'Especes' | 'Mobile Money' | 'Avance (Solde Restant Du)'
  drift.TextColumn get status => text()();  // 'Payee' | 'Avance' | 'Annulee'
  drift.RealColumn get total => real()();
  drift.RealColumn get paye => real()();
  drift.TextColumn get motifAnnulation => text().nullable()();

  @override
  Set<drift.Column> get primaryKey => {ref};
}
```

### `LignesVente` (équivalent des objets `lignes[]` imbriqués dans chaque vente)

> En JS, `lignes` est un tableau imbriqué dans l'objet vente (`localStorage` = JSON libre). En SQL relationnel, ceci devient une table séparée avec clé étrangère — **seul écart structurel réel entre les deux implémentations**, imposé par la nature relationnelle de SQLite.

```dart
class LignesVente extends drift.Table {
  drift.IntColumn get id => integer().autoIncrement()();
  drift.TextColumn get venteRef => text().references(Ventes, #ref)();
  drift.IntColumn get produitId => integer().references(ProduitsVendables, #id)();
  drift.TextColumn get name => text()();  // denormalise volontairement (nom au moment de la vente)
  drift.RealColumn get qte => real()();
  drift.RealColumn get pu => real()();
  drift.TextColumn get espece => text().nullable()();
}
```

### `FicheVentesJour` (équivalent de `recordFicheVente()` / `getFicheVenteDuJour()`)

```dart
class FicheVentesJour extends drift.Table {
  drift.IntColumn get id => integer().autoIncrement()();
  drift.TextColumn get espece => text()();      // 'goliaths' | 'pintades' | 'lapins' | ...
  drift.DateTimeColumn get date => dateTime()(); // normalisee a minuit (jour seul)
  drift.IntColumn get qte => integer()();
}
```

### `FicheJournee` (une ligne par jour saisi, par espèce — coeur des 5 fiches d'élevage)

> Cette table n'existe pas explicitement dans `logialvia-store.js` (les fiches gèrent leur propre état en mémoire JS, `monthData`/`plMonthData`) — c'est la **persistance Flutter** de cet état, absente côté web par choix (prototype sans backend). Structure dérivée directement de la logique réelle documentée au **Doc 05**.

```dart
class FicheJournee extends drift.Table {
  drift.IntColumn get id => integer().autoIncrement()();
  drift.TextColumn get espece => text()();       // identifie quelle fiche
  drift.DateTimeColumn get date => dateTime()();
  drift.IntColumn get achat => integer().withDefault(const drift.Constant(0))();
  drift.IntColumn get ne => integer().withDefault(const drift.Constant(0))();
  drift.IntColumn get vente => integer().withDefault(const drift.Constant(0))();
  // Morts et Dons par categorie : colonnes dynamiques selon l'espece (voir Doc 05
  // pour le detail exact par fiche — mortPoussin/mortGoliathau/mortMature, etc.)
  drift.IntColumn get mortCat1 => integer().withDefault(const drift.Constant(0))();
  drift.IntColumn get mortCat2 => integer().withDefault(const drift.Constant(0))();
  drift.IntColumn get mortCat3 => integer().withDefault(const drift.Constant(0))();
  drift.IntColumn get mortCat4 => integer().nullable()(); // Pondeuses uniquement (4 categories)
  drift.IntColumn get donCat1 => integer().withDefault(const drift.Constant(0))();
  drift.IntColumn get donCat2 => integer().withDefault(const drift.Constant(0))();
  drift.IntColumn get donCat3 => integer().withDefault(const drift.Constant(0))();
  drift.IntColumn get donCat4 => integer().nullable()();
  drift.IntColumn get effectif => integer()();
  drift.IntColumn get effCat1Day => integer()();  // sous-effectif reel par categorie (Doc 05)
  drift.IntColumn get effCat2Day => integer()();
  drift.IntColumn get effCat3Day => integer()();
  drift.IntColumn get effCat4Day => integer().nullable()();
  drift.RealColumn get poidsGeneralG => real()();
  drift.BoolColumn get traitementValide => boolean().withDefault(const drift.Constant(false))();
  drift.TextColumn get traitementObs => text().withDefault(const drift.Constant(''))();
  drift.BoolColumn get isRecorded => boolean().withDefault(const drift.Constant(false))();
  // Champs specifiques Pondeuses uniquement (Doc 05, section SRH/TS/Stock Final)
  drift.IntColumn get srh => integer().nullable()();
  drift.IntColumn get ts => integer().nullable()();
  drift.IntColumn get osPlateaux => integer().nullable()();
  drift.IntColumn get stockFinalOeufs => integer().nullable()();
  drift.IntColumn get oeufsPondus => integer().nullable()();
  drift.IntColumn get oeufsCasses => integer().nullable()();
}
```

---

## 2. Correspondance Fonction JS → Repository Dart

| Fonction dans `logialvia-store.js` | Méthode équivalente dans `data/repositories/` |
|---|---|
| `getStock()` | `StockRepository.getAllProduits()` |
| `addStockItem()` | `StockRepository.ajouterProduit()` |
| `updateStockItem()` | `StockRepository.modifierProduit()` |
| `deleteStockItem()` | `StockRepository.supprimerProduit()` |
| `decrementStock()` / `incrementStock()` | `StockRepository.ajusterStock(id, delta)` |
| `getIntrants()` / `addIntrant()` / `updateIntrant()` / `deleteIntrant()` | `IntrantsRepository` (CRUD symétrique) |
| `addVente()` | `VentesRepository.enregistrerVente()` — **doit** dans une seule transaction : insérer la vente + les lignes, décrémenter le stock de chaque ligne, incrémenter `FicheVentesJour` pour chaque `espece` non-nulle |
| `annulerVente()` | `VentesRepository.annulerVente()` — restitue le stock des lignes |
| `getFicheVenteDuJour()` | `FicheRepository.getVenteDuJour(espece, date)` |

### Transaction critique — `enregistrerVente()`

L'équivalent JS fait 3 choses de façon synchrone et implicite (JS mono-thread). En Dart/SQLite, ces 3 opérations **doivent être explicitement enveloppées dans `database.transaction(() async { ... })`** pour garantir l'atomicité (soit tout réussit, soit rien n'est appliqué) :

```dart
Future<String> enregistrerVente(NouvelleVente vente) async {
  return database.transaction(() async {
    final ref = await _genererReference();
    await database.into(database.ventes).insert(/* ... */);
    for (final ligne in vente.lignes) {
      await database.into(database.lignesVente).insert(/* ... */);
      await ajusterStock(ligne.produitId, -ligne.qte);
      if (ligne.espece != null) {
        await _incrementerFicheVenteJour(ligne.espece!, DateTime.now(), ligne.qte);
      }
    }
    return ref;
  });
}
```

---

## 3. Données d'Amorçage (Seed) — à préserver, pas à réinventer

Les valeurs de `DEFAULT_STOCK`, `DEFAULT_INTRANTS` et `DEFAULT_VENTES` du fichier JS constituent des **données réelles déjà validées** (cohérentes avec le Dashboard et le module Clients/Créances du prototype — ex. Goliath mature = 31 sujets, Pintade mature = 28 sujets, Maïs = 18kg en stock critique). Elles doivent être migrées **telles quelles** dans une méthode `seedInitialData()` appelée à la première ouverture de la base, pas réinventées avec des valeurs différentes.

⚠️ Point de vigilance déjà rencontré une fois lors de la construction du store JS : les `id` référencés dans les lignes de `DEFAULT_VENTES` doivent correspondre exactement aux `id` de `DEFAULT_STOCK` (une erreur de ce type a été trouvée et corrigée pendant le développement — vérifier par recoupement croisé avant de considérer le seed Dart terminé).
