# K1 — Standards de Code & Conventions

Applique concrètement les exigences de qualité posées en Master Prompt §4 et Strict Avoid.

---

## 1. Conventions de Nommage

| Élément | Convention | Exemple |
|---|---|---|
| Fichier | `snake_case` | `fiche_goliaths_screen.dart` |
| Classe | `PascalCase` | `FicheGoliathsScreen` |
| Variable, méthode | `camelCase` | `calculerEffectifJour()` |
| Constante | `camelCase` (Dart n'utilise pas `SCREAMING_CASE`) | `static const double xs = 4.0;` |
| Nom métier (méthode de `usecase`) | Verbe métier français explicite, jamais l'implémentation technique (rappel Strict Avoid §11) | `enregistrerVente()`, pas `insertRow()` |

## 2. `analysis_options.yaml` — configuration obligatoire

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    unused_element: true          # detecte le code mort, Strict Avoid §12
    avoid_print: true             # jamais de print() en production, utiliser un logger
    prefer_const_constructors: true
    always_declare_return_types: true
    avoid_dynamic_calls: true
    unnecessary_this: true
    require_trailing_commas: true # facilite les diffs de revue de code

analyzer:
  errors:
    todo: ignore   # les TODO(dette) sont volontaires, Strict Avoid §4 — pas des erreurs
  exclude:
    - "**/*.g.dart" # fichiers generes par Drift/build_runner
```

## 3. Structure d'un Fichier `usecase`

```dart
/// BR-VTE-002 : atomicite de la transaction de vente.
/// Cf. Doc B6 pour la regle metier complete.
class EnregistrerVenteUseCase {
  final VenteRepository _repository;
  const EnregistrerVenteUseCase(this._repository);

  Future<Vente> executer(NouvelleVenteParams params) async {
    // 1. Validation (Doc E6)
    // 2. Persistance atomique (Doc D1)
    // 3. Publication de l'evenement de domaine (Doc C1 §4)
  }
}
```

**Règle** : un `usecase` = une classe = une méthode publique principale (`executer()` ou nom métier explicite), pas une classe fourre-tout avec 10 méthodes non liées.

## 4. Commentaires — Quand et Comment

| Situation | Commentaire attendu |
|---|---|
| Implémentation d'une règle métier (`BR-XXX`) | `// BR-ELV-008: SRH(J+1) = StockFinal(J), pas TS(J)` |
| Écart délibéré du prototype web | `// ECART_DELIBERE: <select> web -> DropdownButton, pas d'equivalent exact` |
| Dette technique acceptée temporairement | `// TODO(dette): <description et justification>` |
| Code évident (`i++`, un getter simple) | **Aucun commentaire** — le code doit être lisible sans, sinon c'est le code qui doit être clarifié, pas commenté |

## 5. Organisation des Imports

```dart
// 1. Dart/Flutter SDK
import 'package:flutter/material.dart';
// 2. Packages tiers (ordre alphabetique)
import 'package:drift/drift.dart' hide Column;
import 'package:provider/provider.dart';
// 3. Imports internes au projet (chemins relatifs ou package:logialvia_app/...)
import '../../core/theme/app_colors.dart';
import '../domain/usecases/enregistrer_vente_usecase.dart';
```

## 6. Formatage Automatique — Obligatoire Avant Chaque Commit

```bash
dart format .
flutter analyze
```
Aucun fichier n'est commité sans être passé par `dart format` — élimine toute discussion de style dans les revues de code, qui doivent se concentrer sur la logique.

## 7. Taille Maximale Recommandée par Fichier

- Écran (`*_screen.dart`) : privilégier la décomposition en widgets privés dans `widgets/` (Doc C1 §6) dès que le fichier dépasse ~300 lignes
- `ViewModel` : une responsabilité claire par classe — si un `ViewModel` gère plusieurs préoccupations non liées, le découper

## 8. Gestion des Erreurs — Pattern Uniforme

```dart
sealed class Resultat<T> {}
class Succes<T> extends Resultat<T> { final T valeur; Succes(this.valeur); }
class Echec<T> extends Resultat<T> { final String message; Echec(this.message); }

// Usage dans un usecase :
Future<Resultat<Vente>> executer(...) async {
  try {
    final vente = await _repository.enregistrer(...);
    return Succes(vente);
  } catch (e) {
    return Echec('Impossible d\'enregistrer la vente : ${e.toString()}');
  }
}
```
Évite les exceptions non gérées qui remonteraient jusqu'à l'UI sans message utilisateur clair (cohérent avec G2 §2, aucune action silencieuse — y compris les échecs).
