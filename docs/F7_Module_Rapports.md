# F7 — Module : Rapports & Exports

**Ce document remplace la version précédente**, qui était fondée sur une inférence non vérifiée. Le contenu ci-dessous est extrait de la lecture réelle de `rapports-exports.html` (audit effectué a posteriori pour combler la réserve explicitement signalée dans `INDEX_MAITRE.md`).

Écran concerné : `rapports-exports.html` → `rapports_exports_screen.dart`. **6 onglets internes** (`switchRpTab`, `TabController` Doc E3 §4) — pas une simple liste de rapports comme initialement supposé.

---

## Structure Commune aux 6 Onglets

```
1. Bouton "Exporter PDF" (haut-droite, hors du panneau d'onglet — visible en permanence,
   exporte l'onglet actuellement actif)
2. Panneau KPI (accordeon mobile, Doc E7 §3)
3. [Selon onglet] Graphique ou visualisation complementaire
4. Filtre(s) + bouton Reinitialiser
5. DataTable (Doc E4)
```

**Bouton Export PDF — comportement réel exact** : clone le panneau DOM de l'onglet actif, retire tous les boutons/liens interactifs du clone, transmet le HTML résultant (+ dates de filtre) à un générateur PDF partagé unique `generateOfficialPDF()` — confirme et valide le pattern déjà anticipé en Doc E9 §5/J2 §3 (un seul générateur réutilisé, jamais un par type de rapport).

```dart
Future<void> exporterOngletActif(String nomOnglet, DateTimeRange? periode) async {
  final donnees = viewModel.donneesOngletActif(nomOnglet); // deja filtrees a l'ecran
  await EtatPdfGenerator().genererEtat(
    titre: nomOnglet, colonnes: donnees.colonnes, lignes: donnees.lignes,
  ); // reutilise Doc J2 §3, PAS une nouvelle implementation par onglet
}
```

---

## Onglet 1 — Recettes et Dépenses

### KPI (4 cartes)
| KPI | Valeur de référence réelle | Couleur |
|---|---|---|
| Total Recettes | 142 000 F ("Avicole + Commerce Annexe") | Vert (successDeep) |
| Total Dépenses | 68 000 F ("Intrants + Charges diverses") | Rouge (errorDeep) |
| Résultat Net | 74 000 F ("Recettes − Dépenses") | Or, fond teinté |
| Taux de Marge Brute | 52.1 % ("Résultat Net / Total Recettes") | Bleu (infoBlue) |

**Cohérence vérifiée** : 142 000 − 68 000 = 74 000 ✓. Ces valeurs sont cohérentes avec le Dashboard principal déjà documenté (Doc F2).

### Visualisation
Barres horizontales de comparaison Recettes vs Dépenses (pas un `LineChart` comme sur le Dashboard — un simple ratio en barres proportionnelles, largeur relative au montant).

```dart
Widget _barreComparative(String label, double montant, double maxMontant, Color couleur) {
  return Row(children: [
    SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 11))),
    Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(value: montant / maxMontant, color: couleur,
        backgroundColor: AppColors.surfaceZebra, minHeight: 16))),
    SizedBox(width: 64, child: Text(montant.toStringAsFixed(0), textAlign: TextAlign.right)),
  ]);
}
```

### Filtre
Dropdown "Centre de profit" : Tous / Aviculture (Goliaths/Pintades) / Commerce Annexe / Charge Générale — cohérent avec la Comptabilité Analytique (Doc F6 Écran 5).

---

## Onglet 2 — État de Trésorerie

### KPI (3 cartes)
| KPI | Valeur de référence réelle |
|---|---|
| Caisse Espèces | 87 000 FCFA |
| Mobile Money (MTN / Moov Bénin) | 225 000 FCFA |
| Trésorerie Nette Globale | 312 000 FCFA |

**Cohérence vérifiée** : 87 000 + 225 000 = 312 000 ✓ — valeur exactement cohérente avec la trésorerie déjà établie ailleurs dans le système (Dashboard, Doc F2).

### Filtre
Dropdown "Compte" : Tous / Caisse Espèces / Mobile Money.

---

## Onglet 3 — Créances Clients

### KPI (4 cartes)
| KPI | Valeur de référence réelle |
|---|---|
| Créances En Cours | 7 000 F |
| Créances en Retard | 7 000 F |
| Clients Débiteurs | 1 |
| Taux de Recouvrement | 26.3 % ("Acomptes / Montant Initial") |

**Cohérence vérifiée** : correspond exactement à AGOSSOU Prudence, seul client débiteur déjà établi (Doc B1, F4).

### Filtre
Statut : Tous / En Retard / À Échoir.

### Action Spécifique par Ligne
| Bouton | Icône | Action |
|---|---|---|
| Lettre de Relance PDF | `mail` | `exportLettreRelance(client, solde, facture)` — génère un document de relance individuel, distinct de l'export global de l'onglet |
| Saisir Encaissement | `payments` | Navigue vers `/clients` (Doc F4 Écran 3) pour enregistrer le paiement |

---

## Onglet 4 — Dettes Fournisseurs

### KPI (3 cartes)
| KPI | Valeur de référence réelle |
|---|---|
| Total Dettes Fournisseurs | 12 000 F |
| Dettes Urgentes | 12 000 F |
| Fournisseurs Créditeurs | 1 |

**Cohérence vérifiée** : correspond exactement au Fournisseur Maïs Local, déjà établi (Doc B1).

### Filtre
Statut : Tous / Urgent.

### Action par Ligne
| Bouton | Action |
|---|---|
| Saisir Décaissement / Fiche Fournisseur | Navigue vers `/fournisseurs` (Doc F5 Écran 3) |

---

## Onglet 5 — Rapport Élevage (le plus riche structurellement)

### KPI (4 cartes)
| KPI | Valeur de référence réelle |
|---|---|
| Effectif Total | 184 ("Goliaths + Pintades") |
| Sujets Malades | 2 ("Infirmerie active") |
| Taux Éclosion Moyen | 84.0 % (cycle C-2026-012) |
| Cycles en Cours | 2 ("Couveuse active") |

**Cohérence vérifiée** : 184 = 94 (Goliaths) + 90 (Pintades), exactement les effectifs globaux déjà établis (distincts des 31/28 matures — 94/90 sont les effectifs **totaux** toutes catégories confondues).

### Structure — 3 Sous-Tableaux (fidèle à la fiche manuscrite réelle de la ferme)
| Tableau | Contenu |
|---|---|
| Tableau 1 — Recensement Hebdomadaire & Structure du Cheptel | Effectifs par catégorie, toutes filières |
| Tableau 2 — Mouvements, Traitements & Ventes | Achats/Naissances/Morts/Dons/Ventes consolidés |
| Tableau 3 — Couvoir & Suivi d'Incubation | Cycles en cours, taux d'éclosion (lien direct avec Doc F3, écran Cycle Couveuse) |

Cette structure à 3 tableaux est la **transposition numérique directe** de la fiche "Suivi Hebdomadaire de l'Élevage" mentionnée dans le cadrage initial du projet — confirmation que ce rapport consolidé reprend fidèlement le même regroupement que le papier d'origine, pas une réorganisation arbitraire.

---

## Onglet 6 — Rapport de Stocks

### KPI (3 cartes — calculées dynamiquement, pas des valeurs statiques)
| KPI | Source de calcul |
|---|---|
| Valeur Totale du Stock | Somme (stock × prix) sur `INTRANTS` + `PRODUITS_VENDABLES` (Doc D1) |
| Articles en Alerte | Compte des articles où `stock ≤ threshold` |
| Références Actives | Compte total des lignes des deux tables |

**Différence avec les 5 autres onglets** : ces 3 KPIs sont marqués `id="stk-*"` avec valeur `—` dans le HTML source, calculés par JavaScript au chargement (`renderStocks()`), pas des données de démonstration statiques — confirme que ces valeurs doivent être **réellement calculées en Dart** depuis `StockProvider`/`IntrantsProvider` (Doc C1), pas simplement copiées comme constantes de seed.

### Filtre
Catégorie : Toutes / Intrants Provende / Produits Finis.

---

## Correction au Document `INDEX_MAITRE.md`

La réserve "contenu inféré, non audité" précédemment posée sur ce document est levée — le contenu ci-dessus est vérifié contre le fichier HTML réel.

---

## Constatations d'implémentation (Flutter Desktop) — Strict Avoid §7

L'écran est livré : route `/rapports`, 6 onglets, `rapports_exports_screen.dart`. Il constitue un **contexte à part entière** (`lib/rapports/`), sans aucune table à lui : c'est un **modèle de lecture transverse**, en lecture seule, qui agrège Comptabilité, Commercial, Approvisionnement et Élevage. C'est le seul contexte du projet autorisé à lire au travers des autres, parce qu'un rapport de gestion est par nature transversal.

### 1. Toutes les valeurs de référence de ce document sont des constantes de maquette

Les « valeurs de référence réelles » relevées ci-dessus — 142 000 F de recettes, 312 000 F de trésorerie, 184 sujets, 84 % d'éclosion — sont des littéraux JavaScript du prototype (`RECETTES_DEPENSES`, `TRESORERIE_MOUVEMENTS`, tableaux HTML en dur). Elles ont servi à **vérifier la cohérence des formules**, jamais à peupler quoi que ce soit. Sur une base vierge, les 6 onglets affichent des états vides avec un message explicite — un test dédié le vérifie onglet par onglet.

### 2. Le Résultat Net de l'onglet 1 est le même que celui de la Comptabilité

BR-CPT-005 exigeait que le Bilan, le Compte de Résultat et le TAFIRE affichent le même résultat. La règle vaut aussi **entre modules** : `Total Recettes − Total Dépenses` de cet écran se calcule sur les mêmes classes 7 et 6 des mêmes écritures que `CalculerResultatNet`. Un test compare les deux ViewModels et exige l'égalité stricte.

Corollaire appliqué : **seules les classes 6 et 7 comptent**. Les contreparties de trésorerie (531, 512) et de tiers (411, 401) ne sont ni une recette ni une dépense ; les additionner doublerait tous les totaux — l'erreur la plus facile à commettre sur un état de ce type.

### 3. ⚠️ Aucune date d'échéance n'existe dans le modèle de données

Les onglets 3 et 4 comportent une colonne « Échéance » et une colonne « Retard ». Ni `VENTES` ni `ACHATS` ne portent de délai de paiement, et aucun écran de saisie n'en propose.

Le prototype le confirme involontairement : sa seule créance affiche `dateVente` et `echeance` **identiques** (27/07/2026 dans les deux colonnes) — la colonne ne porte donc aucune information indépendante. Sa seule dette va plus loin : datée du **06/08/2026** avec une échéance au **05/08/2026**, elle serait exigible la veille de son propre engagement. Cette valeur n'a pas été reproduite.

**Décision** : l'échéance vaut la date de l'opération, le retard se compte à partir d'elle, et l'écran énonce la limite sous chacun des deux tableaux. Ajouter un délai de paiement supposerait une colonne `echeance` sur `VENTES` et `ACHATS` **et** un champ de saisie au POS et aux Achats. **Reste ouvert**, à arbitrer avec la Gérante.

### 4. Le solde progressif de trésorerie se tient par compte

Le prototype tient deux compteurs séparés (`soldeCaisse`, `soldeMomo`) et affiche celui du compte de la ligne. Ce comportement est reproduit : une ligne Mobile Money n'affiche jamais un cumul mêlant la Caisse. Le filtre par compte est un filtre **d'affichage** — masquer la Caisse ne change pas le solde du Mobile Money. Testé dans les deux sens.

### 5. Ce qui a été rendu réel, là où le prototype affichait du texte figé

| Colonne | Prototype | Implémentation |
|---|---|---|
| Centre de Profit | Chaîne écrite dans le tableau JS | Déduit du n° de compte (701/601/622 → Aviculture, 707/602 → Commerce Annexe, reste → Charge Générale) |
| Traitement Administré | « Vaccin Newcastle (HB1) » en dur | Dernier soin de statut **Réalisé** sur la période, lu sur `SOINS_CALENDRIER` |
| Signes de Maladie | « 1 sujet en observation » en dur | Motifs réellement saisis à l'`INFIRMERIE` sur la période, avec leur nombre |
| Provende Servie | « ~7 300 » en dur | `CalculFicheJournaliere` appliqué aux effectifs du jour, **avec les barèmes de Paramètres Élevage** |
| Éclosion Attendue | `+21 jours` implicite | Durée par espèce — 21 j goliath, 27 j pintade (correction déjà actée en Doc F3) |
| Montant Vente par filière | Montant en dur | Somme des lignes de vente de l'espèce, ventes annulées exclues |

### 6. ⚠️ Le catalogue n'a pas de coût de revient — la colonne « CMUP » de l'onglet 6

`INTRANTS` porte un vrai PMP, calculé par le module Approvisionnement. `PRODUITS_VENDABLES` ne porte que `price`, un prix de **vente** indicatif : le modèle n'a aucun coût de revient pour un poulet élevé sur place, et il faudrait pour cela imputer provende, soins et amortissements à chaque sujet.

La colonne valorise donc les produits finis à leur prix de vente. C'est une **valeur de marché, pas un coût**, et l'écran le dit sous le tableau. Le prototype affiche les mêmes montants sans le préciser.

### 7. Nuances de calcul reprises fidèlement

- Les KPI de l'onglet 6 se calculent sur **tout** le stock, pas sur les lignes filtrées : le prototype incrémente `valeurTotale` avant d'appliquer son filtre. Les KPI décrivent le stock, la table en montre une partie.
- Le « Solde Cumulé » de l'onglet 1 se calcule au contraire sur les lignes **affichées** : filtrer par centre de profit produit le cumul de ce centre, ce que le prototype fait aussi.
- « Clients Débiteurs » compte des **clients**, pas des factures : un client à 3 impayés reste un seul débiteur. Testé.
- Un taux d'éclosion vaut `null` tant qu'aucun cycle n'a éclos, jamais 0 % — qui se lirait comme un échec total (règle déjà posée au tableau de bord).

### 8. Période par défaut

Le prototype fige « 01/08/2026 au 08/08/2026 », ce qui n'a de sens qu'à sa date de capture. La période par défaut est le **mois civil en cours**. Une période saisie à l'envers est remise d'aplomb plutôt que de renvoyer six onglets vides sans explication.

### 9. Non implémenté, signalé

- **Boutons « Exporter PDF »** des 6 onglets : Doc E9 (Impression & PDF) n'est pas implémenté. Le §« Structure Commune » ci-dessus décrit précisément le générateur unique à écrire — c'est le seul point de ce document qui reste à faire.
- **« Lettre de Relance PDF »** de l'onglet 3, pour la même raison. La relance client fonctionnelle existe déjà sur l'écran Clients & Créances (Doc F4).
- Les boutons de navigation par ligne (« Saisir Encaissement » → `/clients`, « Fiche Fournisseur » → `/fournisseurs`) ne sont pas repris : les deux écrans sont accessibles depuis la barre latérale, et un bouton de simple navigation dans un tableau de synthèse ajoute du bruit sans rien apporter.

### 10. État de vérification

| Contrôle | Résultat |
|---|---|
| `flutter analyze` | **0 problème** |
| `flutter test` | **333 tests, 333 réussis** (32 nouveaux sur ce module) |
| `flutter build windows --debug` | compilé, application relancée |
| Schéma | **inchangé (v12)** — ce module ne crée aucune table |
| Lien mort sur `/rapports` | **supprimé** |

## Finalisation — colonne Actions des créances

`rapports-exports.html` l.640-641 place deux icônes sur chaque ligne de créance : la **lettre de relance PDF** et **Saisir l'encaissement**. Aucune des deux n'était portée.

⚠️ **La lettre de relance était pourtant déjà écrite** — reprise mot pour mot dans `DocumentsCommercial.lettreRelance` lors du portage de Doc E9 — mais **branchée nulle part**. Un document complet sans porte d'entrée : personne ne pouvait l'imprimer.

Le second bouton reste une **navigation** vers Clients & Créances, pas une action. L'encaissement s'y saisit, avec le suivi du solde et l'écriture comptable. Le dupliquer ici créerait un second chemin d'encaissement, donc un risque de double règlement sur la même facture.

Un `IconeExportPdf` a été ajouté au socle : même en-tête officielle et même générateur unique que `BoutonExportPdf`, au format d'une cellule de tableau.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **485 tests au vert** · build **release** compilé et lancé.

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


## Écran Inventaire (ajout hors prototype)

Aucune page HTML ne décrit cet écran : il est demandé par la Gérante, et sa
logique est celle du comptable.

### Ce qu'il est, et ce qu'il n'est pas

Ce n'est pas un second Rapport de Stocks. Le rapport donne une photographie
d'aujourd'hui ; l'inventaire répond à **que détenait l'exploitation à une date,
et d'où vient l'écart ?** D'où les quatre colonnes — stock initial, entrées,
sorties, stock final — et l'égalité qui doit les relier. Les lignes dont les
mouvements n'expliquent pas le stock sont signalées en tête : un inventaire qui
ne se justifie pas ne se signe pas.

### ⚠️ Le stock n'est pas stocké par date

`INTRANTS.stock` et `PRODUITS_VENDABLES.stock` donnent l'état **d'aujourd'hui**.
Un inventaire daté se reconstitue donc à rebours :

> stock à la date T = stock actuel − mouvements postérieurs à T

Prendre `stock` tel quel pour une date passée produirait un inventaire
d'aujourd'hui portant la date d'hier — une erreur qu'aucun contrôle ne
rattrape, parce que le document a l'air juste.

### Trois natures de stock, trois traitements

| Nature | Valorisation | Pourquoi |
|---|---|---|
| Intrants | **PMP** | un coût d'achat réel, recalculé à chaque réception |
| Produits finis | **coût de revient** | jamais le prix de vente (Doc D1 v18) |
| Animaux sur pied, œufs en incubation | **comptés, non valorisés** | leur coût dépend de la provende consommée depuis la mise en bande, que le modèle ne cumule pas par lot |

Un produit sans coût de revient n'entre dans aucun total, et le KPI annonce
combien d'articles il exclut : un total qui tait ses exclusions se lit comme
complet.

### Périodes et impression

Journalier (défaut), hebdomadaire (depuis le lundi), mensuel (depuis le 1ᵉʳ) ou
plage libre. La dernière borne choisie fait foi et entraîne l'autre : choisir
« du 20 » alors que la fin est au 12 veut dire « je commence le 20 », pas
« je finis le 20 ». Export PDF en paysage, avec la base de valorisation et les
réserves en toutes lettres.

### Menu et droits

Rangé dans **Ventes & Clients**, plus un raccourci d'accès rapide. Ce groupe
est ouvert à l'Agent de Vente : la route lui est donc accordée, sans quoi
l'entrée s'afficherait dans sa barre latérale et le renverrait sur un refus.

**✓ Arbitré par la Gérante — l'écran reste visible pour les deux rôles.** La
question lui a été posée parce que l'Inventaire expose les **coûts de revient**
et la **valorisation totale du stock** : les montrer au point de vente est une
décision de gestion, pas un choix technique. La réponse est de les montrer. La
décision est consignée dans `PermissionService` pour qu'elle ne soit pas
« corrigée » par prudence lors d'une relecture ultérieure.

Restreindre l'accès supposerait par ailleurs des droits **par entrée de menu**,
là où le modèle n'en porte que par groupe : ce serait un changement de
structure, pas un réglage.

**Vérification** : 13 tests, dont la reconstitution à rebours, la borne haute
inclusive et le refus de valoriser au prix de vente.
