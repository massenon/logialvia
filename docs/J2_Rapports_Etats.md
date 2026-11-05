# J2 — Rapports et États

Complète Doc F7 (structure d'écran) avec le détail des états financiers et opérationnels attendus du système, ancrés dans les règles comptables déjà posées (Doc B6, Doc J1).

---

## 1. États Financiers Réglementaires (SYSCOHADA)

**Structure détaillée complète : voir Doc F6** (module Comptabilité, entièrement reconstruit pour ce niveau d'exigence — Grand Livre et Balance Générale comme écrans à part entière, Bilan/Compte de Résultat/TAFIRE/Notes Annexes regroupés dans l'écran États Financiers). Ce document J2 ne couvre que **l'export** de ces états, pas leur structure de calcul.

| État | Écran source | Structure détaillée |
|---|---|---|
| Journal Comptable | `journal_comptable_screen.dart` | Doc F6 Écran 3 |
| Grand Livre | `grand_livre_screen.dart` | Doc F6 §2 |
| Balance Générale | `balance_generale_screen.dart` | Doc F6 §3 |
| Bilan | `etats_financiers_screen.dart`, Onglet 1 | Doc F6 §4, structure SYSCOHADA Actif/Passif complète |
| Compte de Résultat | `etats_financiers_screen.dart`, Onglet 2 | Doc F6 §4, structure en cascade (Marge → VA → EBE → RAO → Résultat Net) |
| Tableau des Flux de Trésorerie (TAFIRE) | `etats_financiers_screen.dart`, Onglet 3 | Doc F6 §4, 3 flux (Exploitation/Investissement/Financement) |
| Notes Annexes | `etats_financiers_screen.dart`, Onglet 4 | Doc F6 §4, 5 notes structurées |

## 2. États Opérationnels (spécifiques au métier de l'exploitation)

| État | Contenu | Source |
|---|---|---|
| Récapitulatif Mensuel par Espèce | Mouvements du mois (achat/né/vente/mort/don), effectif début/fin, taux de mortalité | `FICHE_JOURNEE` filtré par espèce et mois |
| Bilan Technico-Économique | Coût de production vs revenus par filière | Croisement `FICHE_JOURNEE` + `LIGNES_VENTE.espece` + comptabilité analytique (Doc F6 Écran 5) |
| État des Stocks | Photo instantanée : produits vendables + intrants, valeur totale, articles critiques | `PRODUITS_VENDABLES` + `INTRANTS` |
| Historique des Ventes (période libre) | Détail transactionnel filtré | `VENTES` + `LIGNES_VENTE` |
| Analyse Clients/Créances | Soldes, ancienneté des créances | `CLIENTS` |

## 3. Format de Sortie — Cohérent avec Doc E9

Tout état de ce document réutilise `FacturePdfGenerator` généralisé (Doc E9 §5) — en-tête entreprise, tableau de données, pied de page. Le contenu du tableau varie par type d'état, la structure visuelle reste identique.

```dart
class EtatPdfGenerator {
  Future<Uint8List> genererEtat({
    required String titre,
    required List<String> colonnes,
    required List<List<String>> lignes,
    String? sousTotal,
  }) async {
    // Reutilise la structure de FacturePdfGenerator (Doc E9), tableau generique
    // au lieu du tableau specifique aux lignes de vente
  }
}
```

## 4. Filtres Communs à Tous les États

Plage de dates (obligatoire pour tout état transactionnel), filière/module (pour les états opérationnels), exercice comptable (pour les états financiers — permet de consulter un exercice clôturé en lecture seule, Doc J1 §4).

## 5. Fréquence et Déclenchement

Tous les états sont générés **à la demande** (pas de génération automatique planifiée dans le périmètre actuel, B1 §6) — l'utilisateur sélectionne l'état et la période, prévisualise (Doc F7 §3), puis exporte.
