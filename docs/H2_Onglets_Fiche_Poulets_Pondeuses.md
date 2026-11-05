# H2 — Spécifications Fonctionnelles Détaillées — Onglets de `fiche_poulets_pondeuses_screen.dart`

2 onglets internes. Structure de base commune au patron des fiches d'élevage (Doc F3) — ce document détaille les écarts et spécificités propres à chaque onglet.

---

## Onglet 1 — Poulets (chair)

Suit le patron commun standard à 3 catégories (Doc F3) sans écart particulier.

### KPIs
| KPI | Calcul |
|---|---|
| Effectif Actuel | `effectif` du dernier jour saisi (données `plMonthData` côté web → `FICHE_JOURNEE` où `espece='poulets'`) |
| Mortalité du Mois | Somme `mortPoussin + mortPoulette + mortAdulte` du mois |
| Taux de Mortalité | `(mortalité / effectif début mois) × 100` |
| Ventes du Mois | Somme `vente` du mois |

### Formulaire & Validations
Standard (Doc F3, Doc E6 §3) — 3 catégories : Poussin / Poulette / Adulte.

### DataTable
Tableau mensuel 31 jours standard (Doc E4, Doc F3 §3).

---

## Onglet 2 — Pondeuses (ponte) — le plus complexe du système

**Écart avec le patron commun** : 4 catégories au lieu de 3 (BR-ELV-007/009), **et** une section supplémentaire absente de toutes les autres fiches — le Suivi du Stock d'Œufs (SRH/TS/Stock Final, BR-ELV-008, Doc 05 §4).

### KPIs (4 cartes, différentes du patron standard)
| KPI | Calcul |
|---|---|
| Effectif Pondeuses | `effCat4Day` (catégorie Pondeuse) du dernier jour |
| Stock d'Œufs Actuel | `stockFinalOeufs` du dernier jour saisi |
| Taux de Ponte | `oeufsPondus du jour ÷ effCat4Day × 100` |
| Alerte Autonomie Alimentaire | Comparaison provende disponible vs `provendeTotal` (Doc 05 §4) — badge rouge si rupture prévisible sous 7 jours |

### Structure — Section Rationnement (4 lignes, pas 3)
`DataTable` compacte intégrée au formulaire : Poussin Ponte / Poussin Croissance / Poulette / Pondeuse — chaque ligne : Effectif (lecture seule, calculé), Ration Normative (g/tête, valeur de référence), Provende Servie (g, calculée = Effectif × Ration).

**Ligne de total** : somme des 4 lignes (BR-ELV-009 — bug historique corrigé : le total ne doit jamais se limiter à la seule ligne Pondeuse).

### Structure — Section Suivi du Stock d'Œufs (unique à cet onglet)
```
┌──────────────────────────────────────────┐
│ Stock Hier (SRH) : [lecture seule]          │
│ Œufs Pondus : [saisie]  Œufs Cassés : [saisie]│
│ Total Stock (TS) : [lecture seule, calcule]   │
│ Sorties (Plateaux) : [saisie]                 │
│ Stock Final : [lecture seule, calcule]        │
└──────────────────────────────────────────┘
```

### Formulaire & Validations — champs spécifiques
| Champ | Validation | Référence |
|---|---|---|
| Œufs Pondus | Requis, ≥ 0 | — |
| Œufs Cassés | ≥ 0, ≤ Œufs Pondus | — |
| Sorties (Plateaux) | ≥ 0 | Converti en œufs : `osPlateaux × 30` |
| SRH, TS, Stock Final | **Toujours lecture seule** | BR-ELV-008, ne jamais rendre saisissable |

### Calcul (rappel direct de Doc 05 §4, reposé ici au niveau du formulaire pour éviter toute implémentation qui l'oublierait)
```dart
final srhOuverture = jourPrecedent.stockFinalOeufs; // JAMAIS jourPrecedent.ts
final ts = (oeufsPondus - oeufsCasses) + srhOuverture;
final stockFinal = ts - (osPlateaux * 30);
```

### ⚠️ Manque critique du modèle de données — corrigé en schéma v6

`FICHE_JOURNEE` (Doc D1) stockait `srh`, `ts` et `stockFinalOeufs` — c'est-à-dire les **3 résultats** — mais **aucune des 3 saisies qui les produisent** : ni `oeufsPondus`, ni `oeufsCasses`, ni `sortiesPlateaux`.

Deux conséquences, toutes deux exactement le scénario du bug historique de ce projet :
1. **Rouvrir un jour déjà saisi** aurait affiché un formulaire vide ; un réenregistrement aurait alors écrasé le stock par des zéros.
2. **La cascade de Doc 05 §5**, qui doit recalculer SRH/TS/Stock Final des jours suivants, n'avait pas les entrées nécessaires pour le faire — elle n'aurait pu recalculer que les effectifs, laissant le stock d'œufs figé sur un SRH devenu faux. Silencieusement.

Les 3 colonnes ont été ajoutées. La cascade recalcule désormais **effectifs ET stock d'œufs**, et 15 tests dédiés couvrent les deux bugs historiques séparément (persistance des saisies, puis SRH = Stock Final de la veille), plus le traçage manuel sur 5 jours à sorties variables qu'exige Strict Avoid §2.

### Implémentation

L'écran réutilise le `FicheEspeceScreen` générique des 5 fiches (Doc F3) : la section « Suivi du Stock d'Œufs » n'apparaît que lorsque la configuration d'espèce est celle des Pondeuses. Les 4 catégories, les 4 lignes de rationnement et le total sur les 4 lignes découlent eux aussi de la configuration, sans branchement conditionnel par espèce.

Les 2 onglets ont **chacun leur propre ViewModel** : `poulets` et `pondeuses` sont deux espèces distinctes en base, avec des historiques, des catégories et un suivi de stock séparés. Les partager mélangerait deux fiches.

**SRH, TS et Stock Final sont rendus par des `Text`, pas par des champs en lecture seule** — l'invariant BR-ELV-008 est structurel, donc non contournable, plutôt que porté par une propriété `readOnly`.

### DataTable — Tableau Mensuel Pondeuses (colonnes étendues vs patron standard)
Colonnes supplémentaires par rapport au tableau standard (Doc F3 §3) : SRH, TS, Sorties, Stock Final — visibles uniquement sur cet onglet, absentes du tableau des 4 autres fiches et de l'onglet Poulets.

### Boutons
Identiques au patron standard (Enregistrer, sélecteur de date) — aucun bouton additionnel spécifique à cet onglet.

---

## Point de Vigilance Transversal (rappel maximal — 3ᵉ occurrence dans cette série, volontaire)

Le bug SRH/TS a été le plus grave et le plus silencieux de tout le projet LogiALVIA côté web (deux bugs distincts, corrigés séparément — Doc 05 §4). Sa répétition dans ce document H2, après Doc 05 et Doc F3, est délibérée : c'est le seul point de toute cette documentation où je choisis la redondance plutôt que la concision, précisément parce que c'est le point où une lecture rapide et une traduction Dart pressée reproduiraient le plus probablement une régression déjà vécue une fois sur ce projet.
