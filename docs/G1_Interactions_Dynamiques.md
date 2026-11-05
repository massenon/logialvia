# G1 — Conception et Spécification Technique des Interactions Dynamiques

Catalogue des comportements interactifs transversaux du système — au-delà des composants statiques déjà couverts en section E.

---

## 1. Synchronisation Temps Réel Inter-Écrans

Mécanisme central déjà formalisé en Doc C1 (Domain Events). Rappel des flux critiques :

| Interaction | Écrans impliqués | Événement Dart |
|---|---|---|
| Vente validée sur le POS | `ventes_screen` (émetteur) → `gestion_stocks_screen`, `fiche_*_screen` (récepteurs) | `VenteValideeEvent` |
| Vente annulée | `ventes_screen` (émetteur) → `gestion_stocks_screen` (récepteur) | `VenteAnnuleeEvent` |
| Ajustement de stock manuel | `gestion_stocks_screen` (émetteur) → `ventes_screen` — grille produit POS (récepteur) | Notification `ChangeNotifier` du `StockProvider` partagé |
| Clôture d'exercice | `cloture_exercice_screen` (émetteur) → `journal_comptable_screen`, `bilan_entreprise_screen` (récepteurs) | `ExerciceClotureEvent` |

**Règle d'implémentation** : un écran qui affiche une donnée partagée (stock, ventes) DOIT être un `Consumer`/`Selector` du `Provider` global correspondant — jamais une copie locale de la donnée chargée une seule fois à l'ouverture de l'écran, sous peine d'afficher une valeur périmée après une action faite ailleurs (c'est précisément le bug qu'avait `ventes.html` avant sa correction : `PRODUCTS` codé en dur, déconnecté du stock réel).

---

## 2. Cascade de Recalcul (Fiches d'Élevage)

Comportement déjà détaillé en Doc 05 §5 — rappelé ici comme **interaction dynamique déclenchée par l'utilisateur**, pas seulement comme formule :

```
Utilisateur modifie le jour J (deja saisi)
        │
        ▼
  Sauvegarde declenchee
        │
        ▼
  Recalcul du jour J
        │
        ▼
  Boucle : jour J+1, J+2, ... jusqu'au premier jour non saisi
        │
        ▼
  Rafraichissement visuel du tableau des 31 jours (DataTable, Doc E4)
  SANS rechargement de page/ecran — mise a jour reactive via ChangeNotifier
```

**Attente utilisateur** : le tableau mensuel doit refléter la cascade **immédiatement** après la sauvegarde, sans action supplémentaire (pas de bouton "Actualiser" requis pour voir l'effet de la cascade).

---

## 3. Filtrage & Recherche en Direct (DataTables)

Comportement déjà spécifié en Doc E4 §5 — rappel de la règle de réactivité : chaque frappe clavier dans le champ de recherche déclenche un nouveau filtrage, sans bouton de validation. Pour éviter un recalcul excessif sur de grands volumes (NFRS-PERF), un `debounce` léger est acceptable :

```dart
Timer? _debounce;
void onSearchChanged(String value) {
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 200), () => viewModel.rechercher(value));
}
```

---

## 4. Calculs Réactifs en Direct (Formulaire de Saisie)

Pattern observé sur le prototype (`oninput="computeEffectifAndFeedLive()"`) : à chaque frappe dans un champ de mouvement (Achat/Naissance/Vente/Mort/Don), l'effectif projeté et les sous-effectifs par catégorie se recalculent **avant même la sauvegarde**, en aperçu, pour que l'utilisateur voie l'effet de sa saisie avant de valider.

```dart
class FicheJournaliereViewModel extends ChangeNotifier {
  int _achat = 0, _ne = 0, _vente = 0;
  Map<String, int> _mortsParCategorie = {};

  // Getters calcules a la volee, PAS stockes — recalcules a chaque notifyListeners()
  int get effectifJeunePreview => CalculEffectifParCategorie.categorieJeune(
    prevCat: _prevJeune, achat: _achat, ne: _ne,
    mortCat: _mortsParCategorie['jeune'] ?? 0, donCat: _donsParCategorie['jeune'] ?? 0);

  void onAchatChanged(String value) {
    _achat = int.tryParse(value) ?? 0;
    notifyListeners(); // recalcule et rafraichit l'aperçu, SANS toucher la base
  }
}
```

**Règle** : ce calcul d'aperçu ne persiste rien — seule l'action explicite du bouton "Enregistrer" (Doc F3) écrit en base. La distinction aperçu/persistance doit être structurellement claire dans le code (deux méthodes distinctes du ViewModel, jamais la même méthode appelée pour les deux cas).

---

## 5. Comportement de Chargement (Loading States)

Toute opération asynchrone (lecture/écriture base de données, génération PDF) affiche un indicateur de chargement cohérent :

```dart
enum LoadState { idle, loading, success, error }

class BaseViewModel extends ChangeNotifier {
  LoadState state = LoadState.idle;
  String? errorMessage;

  Future<void> executerAvecLoading(Future<void> Function() action) async {
    state = LoadState.loading; notifyListeners();
    try {
      await action();
      state = LoadState.success;
    } catch (e) {
      state = LoadState.error; errorMessage = e.toString();
    }
    notifyListeners();
  }
}
```

**Seuil d'affichage** : un indicateur de chargement (spinner) ne s'affiche que si l'opération dépasse ~150ms — en-dessous, un flash de spinner serait plus perturbant qu'utile (cohérent avec NFRS-PERF-01, opérations censées être quasi-instantanées en local).
