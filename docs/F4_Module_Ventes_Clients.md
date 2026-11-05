# F4 — Module : Ventes & Clients

**État : les 3 écrans sont implémentés.**

---

## ⚠️ Écrans 2 et 3 — corrections après audit du HTML réel

### Écran 2 — Catalogue : **2 tableaux**, pas un seul

`catalogue-produits.html` comporte le catalogue **et** une liste dédiée aux seuils d'alerte — c'est d'ailleurs le nom que lui donne la barre latérale : « Catalogue & Seuils ».

| Tableau | Colonnes réelles |
|---|---|
| Catalogue | **SKU** · Désignation · Catégorie · Stock · Tarif · Actions |
| Seuils d'Alerte | Désignation · Stock Actuel · Seuil d'Alerte · Statut · Action |

**Colonne `SKU` absente de Doc D1** — 1ʳᵉ colonne du tableau réel. Ajoutée en schéma v9. Aucune règle de codification n'étant documentée, le format `PRD-NNN` séquentiel est un choix explicite, signalé comme tel dans le code. Le SKU d'un produit existant n'est jamais réécrit lors d'une modification.

**Champs réels de la modale** : Désignation \*, Catégorie, Tarif Indicatif (FCFA) \*, Seuil d'Alerte.

**Garde-fou** : un produit figurant dans des ventes déjà enregistrées ne peut pas être supprimé — la clé étrangère depuis `LIGNES_VENTE` s'y oppose, et c'est voulu : l'historique doit rester lisible. Le message d'erreur l'explique au lieu d'afficher un échec technique.

### Écran 3 — Clients & Créances : **3 tableaux**, et 3 KPI sur 4 étaient faux

Les 4 KPI réels (`relances-clients.html` l.98-110) :

| KPI réel | Ce que documentait la version précédente |
|---|---|
| Clients Enregistrés | Nombre de Clients ✅ |
| Solde Total Restant Dû | Créances Totales (équivalent) |
| **Soldes Anciens (>10j)** | ❌ « Clients en Retard » |
| **Événements CRM (7j)** | ❌ « Créance Moyenne » |

**3 tableaux** : Clients (Nom · Téléphone · **Date de Naissance** · Total Achats · Solde Actuel), Créances (Client · Référence Vente · Montant Total · Déjà Réglé · Solde Restant Dû · **Ancienneté** · Action), et **Événements CRM** (Client · Type d'Événement · Date · Jours Restants · **Dernier Contact** · Action).

**2 colonnes absentes de Doc D1**, ajoutées en v9 : `CLIENTS.dateNaissance` et `CLIENTS.dernierContact`. La première est la source des « Événements CRM » **et** de l'alerte « Anniversaire client demain » du tableau de bord (Doc F2) — sans elle, cette alerte n'avait aucune origine possible.

### Correction de la règle de calcul du solde

Doc F4 prescrivait de recalculer `CLIENTS.soldeCreance` « à chaque nouvelle vente à crédit ou paiement partiel ». **Le solde n'est pas stocké mais recalculé à chaque lecture** depuis `VENTES` : un cumul dérivé finit toujours par diverger de sa source, et ce projet a déjà connu ce type d'incohérence silencieuse. La colonne reste déclarée pour rester conforme à D1, mais elle n'est pas lue.

Conséquence vérifiée par test : annuler une vente à crédit fait tomber le total d'achats **et** le solde du client à zéro, sans aucune écriture de correction.

### Écart assumé — bouton « Relancer »

Le prototype affiche un bouton « Relancer » alors qu'**aucune passerelle SMS ou téléphonie n'existe** (Doc B1 §6, hors périmètre). Prétendre envoyer un message serait mensonger. Le bouton est libellé « Marquer contacté » et **horodate réellement** la colonne « Dernier Contact » — la relance elle-même reste à faire par téléphone, ce que le message de confirmation dit explicitement.

---

## Le point le plus surveillé de tout le projet — l'atomicité de la vente

Le Master Prompt §2.3 désigne nommément l'échec à ne pas reproduire :

> « Un bouton qui affiche un toast de succès sans réellement écrire en base est un bug […]. Ce projet a déjà souffert de ce pattern côté web (`validateSale()` qui générait une référence aléatoire sans rien persister) — **ne jamais le reproduire côté Flutter**. »

L'encaissement effectue **4 écritures dans une seule transaction Drift** (BR-VTE-002, Doc D1 §4) :

1. la vente (`VENTES`)
2. ses lignes (`LIGNES_VENTE`)
3. le décrément du stock de chaque produit (`PRODUITS_VENDABLES`)
4. l'incrément du compteur de ventes du jour de la fiche d'élevage (`FICHE_VENTES_JOUR`), si le produit est un animal vivant — c'est la synchronisation POS → Fiche que Doc C1 §1 identifie comme le cœur du système

**Vérifié par test, et la vérification porte sur la base, jamais sur la valeur retournée.** Un test insère volontairement une ligne référençant un produit inexistant : la clé étrangère la refuse, **toute la transaction est annulée**, et le test vérifie que le stock du produit valide est resté à 31 — sans transaction, il aurait été décrémenté à 30 pour une vente qui n'existe pas.

L'annulation est symétrique : restitution du stock **et** décrément du compteur de la fiche, dans une transaction également. Sans ce second point, une vente annulée continuerait de compter comme une sortie du jour sur la fiche d'élevage.

### Portée du bus d'événements — écart assumé avec Doc C1 §4

Doc C1 §4 prescrit que la communication inter-contextes passe par des événements de domaine. Appliqué à la lettre, cela signifierait décrémenter le stock puis publier un événement mettant à jour la fiche d'élevage de façon asynchrone — **ce qui romprait l'atomicité exigée par BR-VTE-002**. Un plantage entre les deux laisserait un stock décrémenté sans vente répercutée.

**Choix retenu** : toutes les écritures sont dans une seule transaction ; le bus sert ensuite à **notifier** les ViewModels ouverts qu'ils doivent se rafraîchir. Le découplage visé par C1 §4 est préservé là où il compte — aucun `usecase` n'appelle le ViewModel d'un autre contexte — sans sacrifier une règle métier à un principe d'architecture.

### Précision de calcul — `paye` sur une vente comptant

Une vente réglée en Espèces ou Mobile Money est soldée : `paye` vaut le **total**, pas le montant remis en main (qui peut inclure la monnaie à rendre). Seule une vente en Avance enregistre le montant réellement reçu. Sans cette distinction, le KPI « Soldes Restant Dus » du tableau de bord aurait affiché des créances fantômes.

---

Écrans concernés : `ventes.html` (4 onglets internes) → `ventes_screen.dart`, `catalogue-produits.html` → `catalogue_produits_screen.dart`, `relances-clients.html` → `relances_clients_screen.dart`.

Détail exhaustif des 4 onglets de `ventes_screen.dart` : voir Doc H (Spécifications par Onglet). Ce document couvre le périmètre écran.

---

## Écran 1 — Ventes (`ventes.html`, 4 onglets : Enregistrer Vente / Devis / Historique / Retours)

### KPI globaux (persistants au-dessus des onglets, ne changent pas selon l'onglet actif)
| KPI | Calcul |
|---|---|
| CA du Jour | Somme `total` des ventes non-annulées du jour |
| Panier Moyen | CA du Jour ÷ nombre de ventes du jour |
| Ventes en Attente (Avance) | Compte des ventes `status='Avance'` |

**Boutons/Structure des onglets** : voir Doc H pour le détail complet (grille produits, panier, encaissement pour l'onglet POS ; filtre/DataTable pour Historique ; etc.)

---

## Écran 2 — Catalogue Produits (`catalogue-produits.html` → `catalogue_produits_screen.dart`)

### Structure
1. KPI : Nombre de Produits Actifs, Valeur Totale du Catalogue (somme stock × prix), Produits en Stock Critique
2. `DataTable` (Doc E4) : Désignation, Catégorie, Prix (ou fourchette), Unité, Stock, Statut, Actions
3. Bouton "Ajouter un Produit" (modale Ajouter, Doc E5)

### Différence avec Gestion des Stocks (F5)
Ce catalogue gère les **produits vendables** (`PRODUITS_VENDABLES`, Doc D1) — animaux vivants et commerce annexe. Il ne doit **jamais** être confondu avec la gestion des intrants (F5), même si l'interface visuelle est similaire (BR-VTE-006, Doc C1 §2 sur la séparation des Bounded Contexts).

### Formulaire Ajouter/Modifier Produit
Champs : Désignation, Catégorie (Avicole/Commerce Annexe), Prix (et Prix Max optionnel pour fourchette), Unité, Stock initial, Seuil d'alerte, Espèce liée (optionnel, dropdown des filières actives — Doc I2).

---

## Écran 3 — Clients & Créances (`relances-clients.html` → `relances_clients_screen.dart`)

### Structure
1. KPI : Nombre de Clients, Créances Totales, Clients en Retard, Créance Moyenne
2. `DataTable` : Nom, Téléphone, Solde Créance, Dernière Vente, Statut (À jour / En retard), Actions
3. Bouton "Ajouter un Client" (modale Ajouter)
4. Action par ligne : "Relancer" (déclenche une action de rappel — SMS/appel selon le canal disponible, hors périmètre technique de cette conversion si aucune passerelle n'est intégrée, B1 §6)

### Règle de Calcul — Solde Créance
`CLIENTS.soldeCreance` = somme des `VENTES.total - VENTES.paye` pour toutes les ventes de ce client en statut `'Avance'`, non soldées. Recalculé à chaque nouvelle vente à crédit ou à chaque paiement partiel enregistré.

### Bouton "Enregistrer un Paiement" (sur une créance existante)
Modale dédiée (pas une modale Ajouter/Modifier générique — un formulaire spécifique : Montant Reçu, Date). À la validation : incrémente `VENTES.paye` de la vente concernée, recalcule le solde, si `paye == total` alors `status` passe de `'Avance'` à `'Payée'`.

## Échéances de paiement — le défaut qui produisait des lettres de relance injustifiées

**Tranché avec la Gérante : délai par défaut paramétrable + saisie au cas par cas.**

### Ce qui n'allait pas

`CreanceClient.echeance` retournait `dateVente`. Donc :

```
joursDeRetard = aujourd'hui − date de vente
enRetard      = joursDeRetard > 0
```

**Toute vente à crédit faite hier ou avant était affichée « En Retard »**, avec un compteur de jours qui mesurait en réalité son ancienneté. Tant que la colonne n'était qu'un affichage, le défaut restait cosmétique et il était documenté comme tel.

Il a changé de nature le jour où la **colonne Actions des créances** a été branchée : la lettre de relance s'imprime depuis ce tableau. La Gérante pouvait donc envoyer une mise en demeure — un document signé, adressé à un vrai client — pour une créance de la veille, mentionnant un retard qui n'existait pas.

Même défaut sur les dettes fournisseurs (`echeance => dateAchat`). Le prototype allait plus loin : sa seule dette est datée du `06/08/2026` avec une échéance au `05/08/2026`, **exigible la veille de son propre engagement**.

### Ce qui a été fait

| Où | Quoi |
|---|---|
| `VENTES.echeance`, `ACHATS.echeance` | DATETIME nullable (v17) |
| `PARAMETRES_ENTREPRISE.delaiPaiementJours` | INTEGER nullable (v17) |
| Paramètres Généraux | nouvelle carte « **Conditions de Vente** » |
| Point de vente | champ « **Payable le** », visible uniquement en Avance |
| Rapports | l'échéance vient de la base ; nouveau statut « **Sans échéance** » |
| Lettre de relance | change de ton et de titre quand aucune échéance n'existe |

### Aucun délai n'est inventé

Le nombre de jours réellement pratiqué chez ALLMANY n'a pas été communiqué. Le réglage est donc **laissé vide**, et tant qu'il l'est :

- passer une vente en « Avance » ne propose **aucune** date ;
- la créance est enregistrée « **Sans échéance** » ;
- elle apparaît bien dans les créances, avec son solde dû, mais **n'est jamais déclarée en retard** ;
- le PDF s'intitule « **Rappel de Solde** » et non « Lettre de Relance », et écrit « présente un solde restant à régler » au lieu de « reste impayée à ce jour ».

Un encart le dit sur les deux écrans concernés, et indique où fixer le délai.

### « Sans échéance » n'est pas « À échoir »

Les deux se distinguent : la première dit qu'**aucune date n'a été fixée**, la seconde qu'une date existe et n'est pas encore atteinte. Les confondre reviendrait à affirmer un délai que personne n'a convenu — exactement l'erreur d'origine, à l'envers.

Un délai saisi à 0 ou négatif compte comme non fixé : mieux vaut ne rien affirmer qu'affirmer faux.

### Le comportement est verrouillé par les tests

Douze tests sur le flux POS → créance, plus quatre réécrits dans les rapports — dont deux qui verrouillaient l'ancien comportement fautif et affirmaient que « l'échéance vaut la date de vente ». Ils affirment maintenant l'inverse, avec la raison inscrite dans le `reason`.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **520 tests au vert** · build **release** compilé, packagé et lancé · migration **v16 → v17**, lignes existantes laissées à NULL.

## Coût de revient — le stock était valorisé au prix de vente

### La preuve, chiffrée

`rapports-exports.html` l.693-698 définit son tableau de stocks avec une colonne `cmup` — *Coût Moyen Unitaire Pondéré*. Comparée au catalogue de `catalogue-produits.html` l.224-227 :

| Produit | `price` (catalogue) | `cmup` (rapport) |
|---|---|---|
| Poussin d'un jour | 400 | **400** |
| Goliath mature | 6 000 | **6 000** |

Le « coût » est le prix de vente, à l'identique. Le portage l'avait reproduit fidèlement (`cmup: p.price`), avec une note à l'écran.

### Pourquoi c'est un vrai problème

Valoriser un stock à son prix de vente le **surévalue** et **anticipe une marge non réalisée** : un goliath encore dans l'enclos n'a pas rapporté 6 000 F, il a coûté de la provende et des traitements. Le KPI « Valeur Totale du Stock » du Rapport de Stocks additionnait donc des recettes espérées, pas des dépenses engagées.

### Ce qui a été fait — migration v18

`PRODUITS_VENDABLES.coutRevient` (REAL, nullable), saisi dans la fiche produit du Catalogue.

| Notion | Getter | Sens |
|---|---|---|
| Valeur à la vente | `valeurStock` | ce que la ferme **espère encaisser** |
| Valeur au coût | `valeurStockAuCout` | ce qu'elle a **dépensé** |
| Marge unitaire | `margeUnitaire` | l'écart, `null` sans coût |

Le Rapport de Stocks valorise désormais les produits finis au **coût de revient**. Les intrants gardent leur **PMP**, qui est un vrai coût d'achat recalculé à chaque réception — celui-là n'a jamais été un prix de vente.

### Le prix de vente n'est jamais substitué

Quand le coût n'est pas renseigné, la ligne affiche « — » et « **Non valorisé** », et **n'entre dans aucun total**. Le KPI le dit : « Hors N article(s) sans coût de revient renseigné ». Un total muet sur 6 articles non valorisés se lirait comme un total complet.

Les produits existants restent donc à `null` : reconduire le prix de vente comme coût perpétuerait exactement la surévaluation qu'on corrige.

### Deux contrôles de saisie

- Un coût **négatif** est refusé.
- Un coût **supérieur au tarif** est refusé, et non simplement signalé : chaque vente serait à perte. Si c'est vrai, c'est le prix qu'il faut corriger, pas le coût qu'il faut accepter en silence. Un coût **égal** au tarif passe — une marge nulle est un fait, pas une erreur.

### Ce que la Gérante doit faire

Saisir le coût de revient produit par produit dans le Catalogue. Tant qu'il ne l'est pas, le Rapport de Stocks ne ment plus — il dit simplement qu'il ne sait pas.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **532 tests au vert** dont 12 dédiés · build **release** compilé, packagé et lancé · migration **v17 → v18**.
