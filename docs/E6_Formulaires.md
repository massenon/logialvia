# E6 — Formulaires — Spécification Complète

## 1. Anatomie d'un Champ (fidèle au pattern `.invalid-feedback` du prototype)

```
LIBELLÉ EN MAJUSCULES *          ← AppTypography.label, * si requis
┌──────────────────────────┐
│ valeur saisie              │    ← bordure rouge si invalide
└──────────────────────────┘
Ce champ est obligatoire.        ← texte d'erreur, visible uniquement si invalide
```

Déjà implémenté dans `AppFormField` (Doc E2 section 8). Ce document précise les **règles de validation par type de champ**, non couvertes dans E2.

---

## 2. Règles de Validation par Type

| Type de champ | Règle | Message d'erreur type |
|---|---|---|
| Texte obligatoire | Non vide après `trim()` | "Ce champ est obligatoire." |
| Nombre entier | Requis + `int.tryParse() != null` + ≥ 0 sauf indication contraire | "Veuillez saisir un nombre valide." |
| Montant FCFA | Requis + ≥ 0 (voir `MontantFCFA`, Doc C1 §5) | "Veuillez saisir un montant valide." |
| Date | Requis, format cohérent avec le contexte (pas de date future pour une saisie journalière rétroactive, sauf champs d'échéance calculée) | "Veuillez sélectionner une date valide." |
| Sélection (dropdown) | Une valeur non-null doit être choisie si le champ est requis | "Veuillez sélectionner une option." |
| Quantité vs stock disponible (POS) | `qte ≤ stock_disponible` (BR-VTE-001) | "Stock insuffisant ($stock disponible)." |

---

## 3. Formulaire de Saisie Journalière — spécification dédiée (le plus complexe du système)

Ce formulaire (répété à l'identique sur les 5 fiches d'élevage, Doc F) a des règles de validation propres à sa complexité métier :

```dart
class FormulaireJournalierValidator {
  /// Valide AVANT tout calcul (Doc 05) — pas apres, pour eviter un calcul
  /// sur des valeurs invalides qui produirait un effectif incoherent silencieux.
  List<String> valider({
    required int achat, required int ne, required int vente,
    required Map<String, int> mortsParCategorie,
    required Map<String, int> donsParCategorie,
    required int effectifDisponibleCommercialise, // categorie vendue, avant la vente du jour
  }) {
    final erreurs = <String>[];
    if (achat < 0 || ne < 0 || vente < 0) erreurs.add('Les mouvements ne peuvent être négatifs.');
    if (vente > effectifDisponibleCommercialise) {
      erreurs.add('La vente ($vente) dépasse l\'effectif disponible ($effectifDisponibleCommercialise).');
    }
    mortsParCategorie.forEach((cat, val) {
      if (val < 0) erreurs.add('Mortalité $cat invalide.');
    });
    return erreurs;
  }
}
```

**Champ Effectif** : jamais dans un `AppFormField` éditable — toujours un `Text()` en lecture seule stylé identiquement (même position, même taille) mais sans `TextField` sous-jacent, pour qu'aucune interaction utilisateur ne puisse le modifier directement (BR-ELV-007, appliqué structurellement, pas seulement par une propriété `readOnly` contournable).

---

## 4. Formulaire POS — validation de panier avant encaissement

```dart
class PosValidator {
  String? validerAvantEncaissement({
    required List<LignePanier> panier,
    required String modePaiement,
    required double montantRecu,
    required double total,
  }) {
    if (panier.isEmpty) return 'Le panier est vide.';
    if (modePaiement == 'Avance (Solde Restant Dû)' && montantRecu <= 0) {
      return 'Veuillez saisir le montant reçu pour une vente à crédit.';
    }
    if (modePaiement != 'Avance (Solde Restant Dû)' && montantRecu < total) {
      return 'Le montant reçu est inférieur au total de la vente.';
    }
    return null; // valide
  }
}
```

---

## 5. Comportement de Focus & Soumission

- La touche `Entrée` dans un champ de formulaire de modale déclenche la même action que le bouton "Enregistrer" (`onFieldSubmitted` du dernier champ, ou `Focus` + `Actions` Flutter pour un comportement global cohérent sur tous les champs d'une modale)
- Après soumission réussie, tout formulaire de saisie répétée (ex : Ajouter Stock, utilisé plusieurs fois de suite) réinitialise ses champs mais **garde la modale fermée** — pas de réouverture automatique (fidèle au comportement `form.reset()` + `closeModal()` du prototype)
- Après une erreur de validation, le focus se déplace automatiquement sur le **premier** champ en erreur

---

## 6. Formats d'Affichage (rappel transversal)

- Montants : séparateur de milliers `fr-FR`, suffixe "FCFA" (jamais de symbole devise avant le nombre)
- Dates saisies : `JJ/MM/AAAA` à l'affichage, `AAAA-MM-JJ` en interne (ISO, cohérent avec la persistance SQLite `DATETIME`)
- Pourcentages (taux de mortalité, taux d'éclosion) : 1 décimale, suffixe "%"
