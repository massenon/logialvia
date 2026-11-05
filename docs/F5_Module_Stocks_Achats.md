# F5 — Module : Stocks & Achats

**État : les 3 écrans sont implémentés.**

---

## ⚠️ Corrections après audit des 3 fichiers HTML

### Écran 1 — Gestion des Stocks : **2 tableaux**, pas un

Le 2ᵉ est le **journal des mouvements** (`gestion-stocks.html` l.170-175 : Date/Heure · Référence · Article · Type · Motif · Quantité), absent de la version précédente de ce document.

**Table `MOUVEMENTS_INTRANT` : présente dans l'ERD de Doc D1, jamais définie dans le dictionnaire** — aucune colonne n'y était spécifiée. Créée en schéma v10. Sans elle, ni ce tableau ni le KPI « Mouvements (7j) » n'existent.

Le 4ᵉ KPI réel est **« Mouvements (7j) »**, et non « Dernier Mouvement ».

### Écran 3 — Fournisseurs : **2 tableaux et 4 KPI**, là où ce document n'en décrivait qu'un sans KPI

C'est le **miroir exact** de l'écran Clients & Créances (Doc F4) :

| | Clients (F4) | Fournisseurs (F5) |
|---|---|---|
| KPI 1 | Clients Enregistrés | Fournisseurs Actifs |
| KPI 2 | Solde Total Restant Dû | Dette Totale |
| KPI 3 | Soldes Anciens (>10j) | Achats Cumulés (Mois) |
| KPI 4 | Événements CRM (7j) | Dettes Soldées (Mois) |
| Tableau 2 | Créances (Ancienneté, Action) | Dettes (Ancienneté, Action) |

Colonnes réelles du 1ᵉʳ tableau : Nom · Téléphone · **Fournit** · Total Achats · Solde Dû. Ni « Contact » ni « Adresse » n'y figurent, et **`fournit` était absente de Doc D1** — ajoutée en v10.

### Colonnes manquantes à `ACHATS`

Doc D1 décrivait `ACHATS` comme « symétrique à `VENTES` » sans en tirer les conséquences : ni `paye` ni `mode` n'y figuraient. Sans `paye`, le tableau des dettes fournisseurs (« Déjà Réglé » / « Solde Dû ») était **incalculable**. Les deux colonnes sont ajoutées en v10.

---

## ⚠️ Règle du PMP — déduite, signalée comme telle

`INTRANTS.pmp` est nommée « Prix Moyen Pondéré » dans Doc D1, mais **aucun document ne dit comment elle évolue**. Sans règle, la colonne resterait figée à sa valeur de seed et la valorisation du stock serait fausse dès la première réception à un prix différent — or c'est elle qui alimente le KPI « Valeur Totale Stock ».

Formule appliquée à chaque réception, moyenne pondérée standard :

```
PMP' = (stock × PMP + quantité reçue × prix d'achat) ÷ (stock + quantité reçue)
```

Vérifié par test : 18 kg à 600 F + 82 kg à 700 F → PMP 682, valorisation 68 200 F. Sans recalcul, le PMP serait resté à 600 et la valorisation aurait **sous-estimé le stock de 8 200 F**.

C'est la définition usuelle du PMP en comptabilité de stock. **À confirmer avec la Gérante** si une autre méthode (FIFO, dernier prix connu) est pratiquée sur l'exploitation.

---

## Ajustement d'inventaire — traçabilité effective

La modale remplace le stock théorique par le stock physique constaté, et **journalise l'écart** dans `MOUVEMENTS_INTRANT` (BR-ADM-003). Sans ce journal, remplacer un stock théorique par un stock constaté effacerait silencieusement l'écart — c'est précisément ce que la traçabilité doit empêcher. Vérifié par test dans les deux sens (écart négatif et positif).

---

## Réserve — l'écriture comptable de l'achat n'est pas générée

Ce document prescrit que la validation d'une commande livrée « génère l'écriture comptable associée (BR-CPT-003, Débit Achats / Crédit Fournisseur ou Caisse) ». **Ce n'est pas fait** : le module Comptabilité (Doc F6) n'existe pas encore, il n'y a donc ni plan comptable ni exercice où écrire. La réception met bien à jour stock, PMP et journal des mouvements ; le volet comptable devra être branché avec F6.

---

Écrans concernés : `gestion-stocks.html` → `gestion_stocks_screen.dart`, `achats-commandes.html` → `achats_commandes_screen.dart`, `fournisseurs.html` → `fournisseurs_screen.dart`.

---

## Écran 1 — Gestion des Stocks (`gestion-stocks.html`)

Gère les **Intrants** (`INTRANTS`, Doc D1) — provende, produits vétérinaires, marchandises — distincts des produits vendables (F4). CRUD complet déjà spécifié en détail (Doc E5).

### Structure
1. KPI : Valeur Totale du Stock d'Intrants, Articles en Alerte Critique, Nombre d'Articles, Dernier Mouvement
2. `DataTable` (Doc E4) : Désignation, Catégorie, Stock, Seuil, Valeur, Statut, Actions (Modifier/Supprimer)
3. En-tête : recherche + filtre par catégorie (Intrants Provende / Marchandises / Vétérinaire) + bouton "Ajouter"

### Formulaire Ajouter/Modifier (Doc E5 §1/§2)
Champs : Désignation, Catégorie, Quantité, Unité, Seuil d'Alerte, Prix Unitaire (PMP).

### Bouton "Ajustement d'Inventaire" (action spécifique, pas un CRUD standard)
Modale dédiée : Stock Théorique (pré-rempli depuis la base) vs Stock Physique Constaté (saisi par l'utilisateur) → calcule l'écart → à validation, remplace le stock théorique par le stock physique constaté et journalise l'ajustement (traçabilité, BR-ADM-003).

---

## Écran 2 — Achats & Commandes (`achats-commandes.html` → `achats_commandes_screen.dart`)

### Structure
1. KPI : Commandes en Cours, Montant Total Engagé, Livraisons Attendues cette Semaine
2. `DataTable` : Référence, Fournisseur, Date, Statut (Commandé/Livré/Partiel), Montant, Actions
3. Bouton "Nouvelle Commande" → ouvre un flux similaire au POS (Doc H, onglet POS) mais pour les intrants : sélection fournisseur, ajout d'intrants au "panier d'achat", validation

### Règle Métier
La validation d'une commande livrée incrémente le stock des `INTRANTS` concernés (symétrique à `BR-VTE-002` mais en sens inverse) et génère l'écriture comptable associée (BR-CPT-003, Débit Achats / Crédit Fournisseur ou Caisse selon le mode de règlement).

---

## Écran 3 — Fournisseurs (`fournisseurs.html` → `fournisseurs_screen.dart`)

### Structure
1. `DataTable` : Nom, Contact, Adresse, Nombre de Commandes, Montant Total Commandé, Actions
2. Bouton "Ajouter un Fournisseur" (modale Ajouter standard)
3. Clic sur une ligne → Offcanvas de détail (Doc E4 §4) listant l'historique des commandes de ce fournisseur

---

## Fabrication de Provende — `#modal-fabrication` (implémentée après la recette K2)

### L'exigence

La note de la modale de `gestion-stocks.html` invoque une obligation contractuelle :

> « Toute sortie d'intrant pour la fabrication de provende doit être justifiée par cette opération — **jamais une simple sortie de stock isolée** (Cahier des Charges Technique §6.2, §8.3). »

Autrement dit : on ne sort pas 25 kg de maïs « comme ça ». Une sortie d'intrant de provende est toujours la contrepartie d'une fabrication, et les intrants sont décrémentés **en une seule opération**.

### ⚠️ Ce que le prototype ne fait pas

`confirmFabrication()` affiche `showToast('Fabrication de provende enregistrée — stocks des 5 intrants décrémentés automatiquement.')` puis **ne décrémente rien**. Le toast affirme le contraire de ce qui se passe : c'est le patron interdit par le Master Prompt §2.3, aggravé par un message mensonger.

Seul son **contrôle de stock** est réel : `computeFabricationTotal()` compare chaque quantité au disponible et affiche l'alerte dès la saisie. Ce comportement est repris tel quel, libellé compris (« Maïs (18 kg dispo) »).

### Ce qui est livré

| Élément | Comportement |
|---|---|
| Bouton « Fabrication de Provende » | En-tête de Gestion des Stocks, icône `blender` |
| Ligne par intrant de provende | Nom, unité, **stock disponible** affiché (rouge si sous seuil), champ de quantité |
| Composition par défaut | 25/10/5/3/2 kg — celle du prototype |
| Alerte de stock | Apparaît **dès la saisie**, pas au clic (`#fab-alert`) |
| Total Provende Fabriquée | Recalculé à chaque frappe |
| Validation | Décrémente les stocks **et** journalise une sortie par intrant |

L'opération est **atomique** : une première passe vérifie tous les stocks avant la moindre écriture. Décrémenter au fil de l'eau puis échouer sur le dernier intrant laisserait les précédents amputés d'une fabrication qui n'a pas eu lieu — un test le vérifie explicitement, en composant une fabrication dont seul le 3ᵉ intrant est en dépassement.

Chaque sortie porte :
- le type `Sortie` et une **quantité signée négative** (Doc D1) ;
- une **référence commune** `FAB-2026-0001`, séquencée sur l'exercice ;
- un motif portant le total fabriqué : « Fabrication de provende — 18 kg (FAB-2026-0001) ».

Les 5 intrants ne sont pas codés en dur : ce sont ceux de catégorie « Intrants Provende » de la table `INTRANTS`. Ajouter un 6ᵉ ingrédient depuis Gestion des Stocks le fait apparaître dans la modale.

### Écarts assumés, signalés

1. **Aucun stock de provende n'est créé en sortie.** Le prototype ne modélise pas la provende fabriquée comme un article : elle est consommée par les fiches d'élevage via le barème de rationnement (Doc F3), pas stockée. Créer un article « Provende » supposerait de décider de son unité, de son seuil et de sa valorisation — trois valeurs qu'aucune source ne fournit. **À arbitrer.**
2. **Aucune écriture comptable.** Une fabrication est un transfert interne de matière première : les intrants ont déjà été chargés en 601 à l'achat, et aucun mouvement de trésorerie n'a lieu. Une écriture de variation de stock supposerait une comptabilité d'inventaire permanent, que le module ne tient pas (voir Doc F6 §10.9, Note 3).
3. **Pas de recette enregistrée.** Le prototype ne mémorise aucune composition type : chaque fabrication se saisit intégralement. Une table de recettes serait un ajout, pas une traduction.

### Vérification

`flutter analyze` 0 problème · `flutter test` **396 tests au vert** dont **11 dédiés** · `flutter build windows --debug` compilé, application relancée · schéma **inchangé (v14)** — l'opération n'utilise que `INTRANTS` et `MOUVEMENTS_INTRANT`, déjà en place.
