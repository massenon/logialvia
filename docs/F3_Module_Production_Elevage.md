# F3 — Module : Production Élevage (le plus critique du système)

Écrans concernés : les 5 fiches (`fiche-goliaths.html`, `fiche-pintades.html`, `fiche-lapins.html`, `fiche-poulets-pondeuses.html`, `fiche-poissons-chats.html`), `cycle-couveuse.html`, `soins-calendrier.html`, `parametres-elevage.html`.

**Logique de calcul détaillée** : voir Doc 05 (non répétée ici). Ce document couvre la **structure d'écran** — sections, KPIs, boutons, widgets — que Doc 05 ne couvrait pas.

---

## Patron Commun aux 5 Fiches d'Élevage

Structure identique sur les 5 écrans (seules les catégories et couleurs d'espèce varient) :

```
1. En-tete : nom de l'espece, selecteur de mois/annee
2. KPI de la fiche (4 cartes, Doc E7)
3. Rappel du cycle (bandeau informatif, etapes cle en pastilles)
4. Formulaire de saisie journaliere (jour actif)
5. Tableau mensuel des 31 jours (DataTable, Doc E4)
6. Calendrier mobile (vue alternative pour ecran etroit)
```

### 1. KPI de Fiche (4 cartes standard, toutes espèces)
| KPI | Calcul |
|---|---|
| Effectif Actuel | `effectif` du dernier jour saisi |
| Mortalité du Mois | Somme des morts (toutes catégories) du mois en cours |
| Taux de Mortalité | `(mortalité mois / effectif début mois) × 100` |
| Ventes du Mois | Somme `vente` du mois en cours |

### 2. Formulaire de Saisie Journalière
Champs (Doc E6 §3 pour validation) : Achat, Naissances, Ventes, Morts par catégorie (3 ou 4 champs selon espèce), Dons par catégorie, Effectif (lecture seule, calculé), Poids Général, Traitement (case à cocher + observation texte).

**Précisions relevées dans le HTML réel** :
- Le champ **Ventes est `readonly`** (`fiche-goliaths.html` l.159, libellé « Ventes (POS) ») : il est alimenté par le point de vente via `FICHE_VENTES_JOUR`, jamais saisi sur la fiche. Le reproduire comme un champ éditable romprait la synchronisation POS → fiche que Doc C1 §1 identifie comme le cœur du système.
- Les **compteurs Morts et Dons sont eux aussi `readonly`**, pilotés uniquement par deux boutons `−` / `+` (`dayCounterStep()`). C'est ce qui garantit structurellement qu'aucune valeur négative ou non numérique n'atteint le calcul.
- **`Poids Général` est bien persisté** (`day.poidsGeneralG`, l.709), tout comme `traitementObs` et `traitementValide` (l.710-711).

**⚠️ Résolution du point ouvert sur le poids** : Doc D1 ne prévoyait aucune colonne pour ces 3 champs — la saisie n'aurait eu nulle part où être stockée, et le GMQ du Dashboard Élevage (Doc F2) serait resté incalculable. Les colonnes `poidsGeneralG`, `traitementObs` et `traitementValide` ont été **ajoutées à `FICHE_JOURNEE`** (schéma v3), migration additive vérifiée sur une base réelle.

**Boutons du formulaire**
| Bouton | Position | Action |
|---|---|---|
| Enregistrer | Bas du formulaire, primaire | Valide → calcule (Doc 05) → persiste `FICHE_JOURNEE` → déclenche cascade (BR-ELV-006) si jours suivants déjà saisis |
| Sélecteur de date | Haut du formulaire | Change le jour actif, recharge le formulaire avec les valeurs de ce jour (ou vide si non saisi) |

### 3. Tableau Mensuel 31 Jours (DataTable, Doc E4)
Colonnes : Date, Achat, Né, Vente, Morts (total), Dons (total), Effectif. Clic sur une ligne → charge ce jour dans le formulaire de saisie (section 2), ne navigue pas vers un autre écran.

---

## Spécificités par Fiche

### ⚠️ Correction — les catégories portent des noms d'espèce, pas des rôles génériques

La version précédente écrivait « Jeune / Commercialisée / Adulte » pour Goliaths, Pintades et Poissons-Chats. Ce sont les **rôles** des catégories, pas leurs libellés. Doc 05 §3 donnait déjà les vrais noms, confirmés par le JS réel (`fiche-goliaths.html` l.615-642, variables `mortPoussin` / `mortGoliathau` / `mortMature`) :

| Fiche | Cat. 1 — reçoit achats + nés | Cat. 2 — **déduite des ventes** | Cat. 3 |
|---|---|---|---|
| Goliaths | Poussins | **Goliathau** | Mature |
| Pintades | Poussins | **Pintadau** | Mature |
| Lapins | Lapereau | **Chair** | Reproducteur |
| Poulets (onglet) | Poussin | **Poulette** | Adulte |
| Poissons-Chats | Alevin | **Juvénile** | Mature |

### ⚠️ Piège majeur — la vente n'est PAS déduite de la catégorie « Mature »

Le bandeau de cycle et le KPI affichent « **Mature** (≥ 4 mois, ≥ 2,8 kg) — **Éligible à la Vente** ». Il serait naturel d'en conclure que la vente décrémente la catégorie Mature. **C'est faux** : `fiche-goliaths.html` l.638 déduit la vente du **Goliathau**.

```js
var effGoliathau = Math.max(0, prevGoliathau - vente - mortGoliathau - donGoliathau);
var effMature    = Math.max(0, prevMature - mortMature - donMature);   // aucune vente
```

« Éligible à la Vente » qualifie donc la **maturité commerciale** de l'animal, pas la catégorie décrémentée par le mouvement de vente du jour. C'est exactement le type d'écart qu'une traduction rapide inverserait sans que rien ne le signale à l'écran. Couvert par un test dédié.

### Rationnement (3 catégories)
Barème relevé dans le tableau réel : **30 / 60 / 110 g/j**. Note affichée sous le tableau des Goliaths, reprise telle quelle : *« Barème générique réutilisé de la référence Aviculture — aucun barème Goliath spécifique confirmé à ce jour, à valider avec la Gérante. »*

### Fiche Poulets-Pondeuses (écran à 2 onglets internes)
- **Onglet Poulets** : 3 catégories (Poussin/Poulette/Adulte), structure identique au patron commun
- **Onglet Pondeuses** : 4 catégories (Doc 05 §4), **section supplémentaire "Suivi du Stock d'Œufs"** (SRH/TS/Sorties/Stock Final) non présente sur les autres fiches — voir spécification détaillée en Doc H (Spécifications par Onglet)

---

## Écran — Cycle Couveuse (`cycle-couveuse.html` → `cycle_couveuse_screen.dart`)

### ⚠️ Structure corrigée — audit de `cycle-couveuse.html`

**Les 4 KPI réels** (l.105-120) — la version précédente en listait quatre autres :

| KPI | Accent | Icône |
|---|---|---|
| Cycles en Cours | or | `egg` |
| Poussins Attendus | navy | `query_stats` |
| Taux Éclosion Moyen | vert | `check_circle` |
| Taux Perte Moyen | rouge | `trending_down` |

**Colonnes réelles du tableau** (l.151-158) : Code Cycle · Espèce · Œufs Chargés · Date Chargement · Éclosion Prévue · Taux Éclosion · Statut · Actions.
Il n'y a **ni colonne « Bande »** ni colonne « Poussins Nés » — ce que la version précédente affirmait.

**Barre de filtres** (l.135-142) : statut (Tous / En cours / Éclos) et espèce (Toutes / Goliath / Pintade).

**Deux modales** : « Déclarer un Nouveau Cycle » (l.219-261) et « Enregistrer l'Éclosion » (l.263-290), cette dernière calculant en direct les taux d'éclosion et de perte.

### ⚠️ RÈGLE MÉTIER CORRIGÉE — la durée d'incubation dépend de l'espèce

La version précédente énonçait : *« Éclosion attendue = Date Incubation + 21 jours »*, comme une règle unique. **C'est faux.** La modale de création propose deux espèces avec deux durées distinctes (l.232-233) :

```html
<option value="pintade" data-duree="27">Pintade (incubation ≈ 27 jours)</option>
<option value="goliath" data-duree="21">Goliath (incubation ≈ 21 jours)</option>
```

Appliquer 21 jours à une pintade avance son éclosion prévue de **6 jours** et déclenche l'alerte « éclosion imminente » du Tableau de Bord (Doc F2) presque une semaine trop tôt. Le calcul du dashboard, initialement écrit avec un `+21` uniforme, a été corrigé en conséquence. Verrouillé par deux tests.

La date d'éclosion reste **calculée à l'affichage, jamais saisie**.

### ⚠️ Écarts du modèle de données (`CYCLE_COUVEUSE`, Doc D1)

| Colonne D1 | Réalité du prototype |
|---|---|
| `bandeReproducteurs` NOT NULL | **Aucun champ ne la saisit** — rendue nullable, sinon aucune création de cycle n'aurait été possible |
| — | **`espece` manquante** — 1er champ de la modale, et elle détermine la durée d'incubation |
| — | **`oeufsPerdus` manquante** — « Nombre d'Œufs Non Éclos / Cassés » de la modale d'éclosion |

Corrigé en **schéma v4**, migration vérifiée sur base réelle sans perte.

### Invariant ajouté

`poussinsEclos + oeufsPerdus ≤ oeufsCharges` — on ne peut pas faire éclore plus d'œufs qu'on n'en a chargé. Absent du prototype (qui n'effectue aucune validation croisée), ajouté car une saisie incohérente fausserait durablement le taux d'éclosion moyen, donc la projection « Poussins Attendus ».

---

## Écran — Calendrier de Soins (`soins-calendrier.html` → `soins_calendrier_screen.dart`)

### ⚠️ Structure corrigée — l'écran est bien plus vaste que décrit

**Les 4 KPI réels** (l.95-107). **Aucun des quatre** ne correspond à ceux qu'énonçait la version précédente :

| KPI | Accent | Icône |
|---|---|---|
| Doses Administrées (Mois) | navy | `vaccines` |
| Planifiées à Venir | or | `event_upcoming` |
| En Quarantaine / Traitement | bleu | `medication` |
| Coût Vétérinaire (Mois) | vert | `payments` |

**3 onglets**, et non une simple vue calendrier :
1. **Registre des Soins** — tableau Date · Lot/Espèce · Type d'action · Produit · Dose · Statut · Actions (l.150-156), avec filtres par catégorie et par espèce
2. **Calendrier des Doses** — grille Lot/Bande × jours du mois, colonne de gauche figée, jour courant surligné (l.192-194)
3. **Suivi Infirmerie** — voir ci-dessous

Le code couleur par statut (Effectué/vert, Planifié/or, En retard/rouge, En cours/bleu) est bien celui décrit, et il est appliqué.

### ⚠️ Sous-module Infirmerie — absent de F3 **et** de D1

`soins-calendrier.html` contient un suivi d'infirmerie complet dont ni ce document ni le modèle de données ne faisaient mention :
- tableau Date d'Entrée · Lot/Sujet · Motif · Niveau d'Isolement · Statut · Actions (l.238-243)
- filtres statut (En cours / Réintégré / Décédé) et niveau d'isolement (l.220-226)
- modale « Nouvelle Entrée Infirmerie » (l.300-319) : sujet, motif, niveau d'isolement parmi *Simple surveillance / Infirmerie / Quarantaine stricte*
- modale « Déclarer le Décès ? » (l.321-332)

C'est aussi la **source du KPI « En Quarantaine / Traitement »** — sans cette table, ce KPI était incalculable. Table `INFIRMERIE` créée en schéma v5.

### ⚠️ La modale « Nouveau Soin » saisit 9 champs, D1 n'en modélisait que 5

Champs réels (l.264-291) : Lot/Bande\*, Date du Soin\*, Type d'Action\*, Produit Utilisé, Dose, **Délai d'Attente / Rémanence (jours)**, Vétérinaire/Animalier, Symptômes observés, **Coût (FCFA)**.

Les 6 colonnes manquantes (`produit`, `dose`, `remanenceJours`, `veterinaire`, `symptomes`, `coutFcfa`) ont été ajoutées à `SOINS_CALENDRIER` en v5. Sans `coutFcfa`, le KPI « Coût Vétérinaire (Mois) » n'avait aucune source.

Le **Type d'Action** est une liste fermée : Vaccination · Traitement curatif · Vermifuge · Vitamines.

### ⚠️ Promesse non tenue par le prototype — répercussion d'un décès

La modale de décès affiche : *« Cette action clôture l'entrée d'infirmerie et sera reflétée dans le décompte de mortalité de la fiche d'élevage correspondante »* (l.326). **Côté web, aucune répercussion n'a lieu** — le texte annonce un comportement qui n'existe pas.

Le reproduire tel quel afficherait un message mensonger (Master Prompt §2.3). De plus, l'imputer réellement supposerait de savoir **sur quelle catégorie** imputer la mort, information que l'infirmerie ne capture pas : son champ « Lot / Sujet » est du texte libre. Le message a donc été adapté à ce qui se produit réellement, et un champ « Filière concernée » facultatif a été ajouté pour que l'information existe au moins en base. `TODO(dette)` posé pour brancher un événement de domaine (Doc C1 §4) le jour où la catégorie sera connue.

### Ajout assumé — exploitation du délai d'attente

Le prototype **saisit** une rémanence mais ne s'en sert jamais. La laisser inerte en ferait une donnée morte, alors qu'elle porte une contrainte commerciale réelle : les produits d'un animal sous délai d'attente ne sont pas vendables. Une bannière liste donc les délais en cours avec leur date de fin. Ajout signalé comme tel, absent du prototype.

---

## Écran — Paramètres Élevage (`parametres-elevage.html` → `parametres_elevage_screen.dart`)

> ### ⚠️ Section entièrement corrigée — la description précédente ne correspondait à aucun élément de l'écran réel
>
> La version précédente annonçait : « Configuration des seuils d'alerte de mortalité, des rations normatives par catégorie et par espèce, et activation/désactivation des filières ».
>
> Audit de `parametres-elevage.html` : **il n'y a aucun seuil d'alerte de mortalité** et **aucune activation de filière** sur cet écran — l'activation des modules vit dans `parametres-generaux.html` (Doc F8 / Doc I2). Sur les 3 éléments annoncés, un seul existe (les rations), et l'écran en comporte 3 autres que le document ne mentionnait pas.

L'écran comporte **4 onglets internes** :

| # | Onglet | Contenu réel |
|---|---|---|
| 1 | **Rationnement** | 12 barèmes (espèce × stade physiologique × g/tête/jour), badge « Confirmé » vs « Générique », recherche + filtre espèce, ajout et modification |
| 2 | **Calendriers Prophylaxie** | 11 échéances réparties sur les 4 espèces (jour du cycle, traitement, produit, rémanence), sélecteur d'espèce en pastilles, CRUD complet |
| 3 | **Types de Provende** | 5 intrants en **lecture seule** — « le stock se gère exclusivement depuis Gestion Stocks / Fabrication de Provende » |
| 4 | **Numérotation Bandes & Sujets** | 4 préfixes (Enclos, Cage, Bande, Bassin) avec aperçu en temps réel et bouton d'enregistrement |

### Le point qui fait tout l'intérêt de cet écran

Le script du prototype le dit lui-même : « Ces baremes reels [sont] deja utilises dans les fiches — cette page en est la **CONFIGURATION**, pas une seconde source de donnees inventee separement. »

Cette phrase est tenue au sens propre dans l'implémentation. `CalculFicheJournaliere` reçoit un `rationsConfigurees` chargé depuis `BAREMES_RATION`, et `ConfigurationEspece` ne fournit plus que la **valeur de référence par défaut**. Relever la ration des Matures de 110 à 130 g/j dans les paramètres change immédiatement la provende calculée sur la fiche Goliaths. Sans ce report, l'onglet aurait affiché 130 pendant que la fiche aurait continué à compter 110 : deux vérités pour une même donnée, et un écran de paramétrage décoratif (Master Prompt §2.3).

Un test le verrouille explicitement, ainsi que le comportement inverse : **supprimer un barème fait retomber la fiche sur la ration de référence, pas sur zéro**.

### ⚠️ Tables absentes de Doc D1 — créées en schéma v12

Ni `BAREMES_RATION` ni `CALENDRIER_PROPHYLAXIE` ne figuraient au dictionnaire. Le prototype garde ses barèmes dans les tableaux JavaScript `RATIONS` et `PROPHYLAXIE_STORE` : **ajouter une échéance n'y survit pas à un rechargement de page**. Les 4 préfixes de numérotation vivaient, eux, dans `localStorage.logialvia_numerotation_config` ; ils sont désormais 4 colonnes de `PARAMETRES_ENTREPRISE`, qui est déjà la ligne unique des paramètres d'entreprise.

Le socle reprend **les 12 barèmes et les 11 échéances exacts du prototype**, drapeau `confirme` compris : seuls les 3 barèmes Lapins portent « Confirmé (Référence Cuniculture) », les 9 autres « Générique (Aviculture, à confirmer) ». Ce n'est pas cosmétique — c'est le signal, adressé à la Gérante, des valeurs qu'elle doit encore valider.

### Écarts assumés, signalés à l'écran

1. **Un stade libre ne pilote aucun calcul.** Le prototype laisse ajouter n'importe quel stade (« Ex. Adulte ») sans dire ce qu'il devient. La réponse honnête : rien, tant qu'il ne porte pas le libellé exact d'une catégorie de la fiche. Les stades concernés portent une icône d'information qui l'explique, et la modale d'ajout le rappelle avant la saisie.
2. **Onglet 3 branché sur les vraies données.** Le prototype code ses 5 lignes en dur dans le HTML. Elles sont lues depuis `INTRANTS` filtrés sur la catégorie « Intrants Provende », et le « Prix Indicatif » affiché est le **PMP réellement calculé** par le module Approvisionnement — pas une seconde valeur saisie à part, qui aurait dérivé.
3. **Un préfixe vide est refusé.** Le prototype retombe silencieusement sur sa valeur par défaut ; des identifiants « 1, 2, 3 » ne distingueraient plus une cage d'un bassin. Le refus est explicite.
4. **L'injection automatique du calendrier de prophylaxie dans les fiches journalières n'est pas faite** — et l'écran le dit. Elle suppose de connaître le jour de cycle de chaque bande, donc une date de mise en place que `FICHE_JOURNEE` ne stocke pas. Les soins réellement planifiés et réalisés se saisissent sur l'écran Calendrier de Soins. **Point ouvert** : ajouter une date de mise en bande, ou renoncer à l'injection automatique — à trancher avec la Gérante.
5. **Bouton « Exporter PDF » omis** sur les 4 onglets, tant que Doc E9 n'est pas implémenté — même traitement que sur les autres modules.

---

---

## Implémentation — un seul écran pour les 5 fiches

Strict Avoid §5 et §15 l'exigent : **un unique `FicheEspeceScreen` paramétré par une `ConfigurationEspece`**, jamais 5 implémentations parallèles. Une espèce se déclare entièrement par sa configuration :

```dart
static const ConfigurationEspece goliaths = ConfigurationEspece(
  identifiant: 'goliaths',
  categories: [
    CategorieEspece(libelle: 'Poussins', rationGrammesParJour: 30,
        recoitAchatEtNaissances: true),
    CategorieEspece(libelle: 'Goliathau', rationGrammesParJour: 60,
        deduiteDesVentes: true),
    CategorieEspece(libelle: 'Mature', rationGrammesParJour: 110),
  ],
  // ...
);
```

Les rôles « reçoit les achats » et « déduite des ventes » sont **portés par la configuration**, pas codés en dur dans le calcul — c'est ce qui rend le moteur commun aux 5 fiches et aux 4 catégories des Pondeuses sans branchement conditionnel par espèce. Ajouter une 6ᵉ filière est une entrée de configuration.

### État d'avancement du module

| Écran | État |
|---|---|
| Fiche Goliaths | ✅ implémentée |
| Fiche Pintades | ✅ implémentée |
| Fiche Lapins | ✅ implémentée (visible si module `cuniculture` actif) |
| Fiche Poissons-Chats | ✅ implémentée (visible si module `pisciculture` actif) |
| Fiche Poulets/Pondeuses (2 onglets) | ✅ implémentée — 4 catégories + suivi du stock d'œufs (Doc H2) |
| Cycle Couveuse | ✅ implémenté (4 KPI, filtres, tableau, 2 modales) |
| Calendrier de Soins | ✅ implémenté (4 KPI, 3 onglets, infirmerie, 3 modales) |
| Paramètres Élevage (4 onglets) | ✅ implémenté — barèmes, prophylaxie, provende, numérotation |

Le **moteur de calcul est complet pour les 6 configurations**, Pondeuses comprises (4 catégories, provende sommant les 4 lignes, SRH/TS/Stock Final). **Le module F3 est entièrement implémenté.**

---

## Point de Vigilance Transversal — Rappel des Bugs Déjà Corrigés

Avant de considérer ce module "terminé" côté Flutter, revérifier explicitement contre Doc 05 §1 (répartition en %, interdite) et §4 (SRH/TS, la règle exacte de calcul du stock d'ouverture). Ce sont les deux points où une régression silencieuse est la plus probable si la traduction Dart est faite rapidement sans repasser par les cas de test déjà tracés.

### ÉCART_DELIBERE — l'onglet « Intrants de Provende » devient administrable

**Demandé par la Gérante après la recette K2.**

`parametres-elevage.html` intitule ce tableau « Types de Provende » et le déclare en lecture seule : « Le stock de ces 5 intrants se gère exclusivement depuis Gestion Stocks / Fabrication de Provende — **lecture seule ici** ».

Trois changements sont apportés :

| Point | Avant | Après |
|---|---|---|
| Libellé de l'onglet et du tableau | « Types de Provende » | « **Intrants de Provende** » — ce sont des intrants nommés, pas des types abstraits |
| Bouton | aucun | **Ajouter**, avec sa modale |
| Colonnes | Type d'Intrant · Stock Actuel · Prix Indicatif | **Code** · Intrant · Stock Actuel · **Seuil d'Alerte** · Prix Indicatif · **Actions** |
| Actions par ligne | aucune | **Modifier** (modale) et **Supprimer** (modale d'avertissement) |

#### Ce qui reste vrai de la note d'origine

**La quantité en stock ne se saisit toujours pas.** Ni à la création — un nouvel intrant démarre à 0 — ni à la modification, où elle est conservée à l'identique.

Ce n'est pas un oubli : le stock ne bouge que par une **réception de commande**, une **fabrication de provende** ou un **ajustement d'inventaire**, chacun laissant sa trace dans `MOUVEMENTS_INTRANT`. Permettre de le retoucher depuis un écran de paramétrage contournerait exactement la traçabilité que le Cahier des Charges Technique §6.2 impose — celle-là même que la Fabrication de Provende vient de rendre effective. La modale le dit à l'écran et renvoie vers l'ajustement d'inventaire pour corriger un écart constaté.

#### Pas de seconde logique

L'onglet écrit dans `INTRANTS`, table du module **Approvisionnement**. C'est son `ApprovisionnementViewModel` qui est utilisé, pas une couche parallèle : il porte déjà les validations (désignation obligatoire, seuil et prix non négatifs), la génération du code `INT-00N`, et surtout le message de refus de suppression.

`PageParametresElevage` fournit donc les deux ViewModels. Après chaque écriture, celui des paramètres relit — les deux lisent la même table, ils ne doivent pas diverger.

#### La suppression peut échouer, et c'est voulu

Un intrant déjà commandé ou consommé est protégé par les clés étrangères de `LIGNES_ACHAT` et `MOUVEMENTS_INTRANT`. L'effacer rendrait illisible l'historique qui le référence.

La modale d'avertissement l'annonce **avant** le clic : elle indique que l'action est irréversible, que le stock actuel sera perdu sans mouvement de sortie pour le justifier, que la suppression sera refusée si l'intrant a déjà servi, et propose l'alternative — mettre le seuil d'alerte à 0 pour cesser d'en être averti. Un test vérifie qu'une fabrication de provende suffit à rendre le Maïs indélébile.

#### Effet de bord voulu

Un intrant créé ici apparaît immédiatement dans la modale de **Fabrication de Provende** et dans **Gestion Stocks** : la composition n'est pas figée à 5 ingrédients. Testé.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **401 tests au vert** dont 5 dédiés à ce CRUD · build compilé, application relancée · schéma **inchangé (v14)**.

### ÉCART_DELIBERE — colonne « Actions » du tableau « Lot d'Incubation »

**Demandé par la Gérante après la recette K2.**

`cycle-couveuse.html` ne propose qu'un seul geste par ligne — « Éclosion » sur les cycles en cours, rien sur les autres. Une erreur de saisie à la mise en couveuse était donc définitive : un lot déclaré à 100 œufs au lieu de 1 000 restait faux jusqu'à l'éclosion, et y entraînait un taux absurde.

La colonne porte désormais **Éclosion · Éditer · Supprimer**, chacune avec sa modale. L'édition rouvre le formulaire de création, prérempli ; changer d'espèce **recalcule la date d'éclosion prévue** (21 jours goliath, 27 jours pintade) au lieu de conserver l'échéance de l'espèce précédente.

#### Les deux gestes s'arrêtent à l'éclosion

Un cycle éclos n'est **ni modifiable ni supprimable**, et la ligne l'affiche : « N poussins » et un cadenas à la place des boutons, avec l'explication au survol.

Ce n'est pas une précaution de principe. À l'éclosion, deux choses ont déjà quitté l'écran :

- le **taux d'éclosion** est entré dans la moyenne de la couveuse. Ramener après coup 100 œufs chargés à 50 sur un lot ayant produit 85 poussins ferait passer ce taux de 85 % à 170 % ;
- les **poussins** sont entrés dans les effectifs de la filière. Les effacer laisserait des sujets sans origine.

Le refus est porté par le ViewModel, pas seulement par l'affichage : `modifierCycle()` et `supprimerCycle()` renvoient un `Echec` explicite si le cycle n'est plus en incubation. Deux tests le vérifient, y compris que le nombre d'œufs chargés n'a pas bougé après un refus.

#### La modale de suppression propose l'alternative

Elle annonce l'irréversibilité, nomme ce qui disparaît — les N œufs du lot, sa date de chargement, l'éclosion annoncée au tableau de bord — puis distingue les deux situations : *« Ne supprimez un lot que s'il a été déclaré par erreur. Un lot réellement mis en couveuse puis perdu doit être enregistré comme éclosion avec 0 poussin — la perte reste ainsi visible dans le taux d'éclosion moyen, ce qui est le but du suivi. »*

Supprimer un lot perdu ferait remonter le taux moyen en effaçant l'échec : l'écran deviendrait flatteur au lieu d'être utile.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **433 tests au vert** dont 5 dédiés à cette colonne · build compilé, application relancée · schéma **inchangé** — aucune colonne ajoutée, l'édition écrit dans `CYCLES_INCUBATION` existante.

### Popup « Prophylaxie du Jour » et « Planifier une Intervention »

Les deux dernières modales du module sont portées. Le détail — dont **l'arbitrage du conflit jour du mois / jour du cycle**, tranché en faveur du jour du cycle sur preuves tirées du contenu des traitements — est en **Doc K2 §B.1 et §B.2**.

Trois points à retenir ici :

1. `CALENDRIER_PROPHYLAXIE.jourCycle` était la bonne modélisation. Ce sont `prophylaxie-popup.js` et `fiche-goliaths.html` qui interrogent ce calendrier avec un jour du mois.
2. La popup travaille sur `SOINS_CALENDRIER`, pas sur le calendrier de prophylaxie : la projection du second vers des échéances datées suppose une **date de mise en bande** que le modèle ne stocke pas. L'écran l'écrit noir sur blanc.
3. « Planifier une Intervention » et « Nouveau Soin » écrivent toutes deux dans `SOINS_CALENDRIER`. Côté web elles alimentaient deux structures distinctes — le registre et `GANTT_LOTS[].interventions` — d'où deux plannings aveugles l'un à l'autre.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **467 tests au vert** dont 12 sur la popup · build compilé, application relancée · schéma **inchangé** par ces deux modales.

### Glossaire des filières — les libellés de la saisie journalière

**Défaut signalé par la Gérante : la fiche Poissons-Chats affichait « Nés (Couveuse) ».** Les poissons-chats n'ont pas de couveuse.

La cause n'était pas une faute de frappe : l'écran codait les trois libellés **en dur**, alors que les cinq fiches du prototype écrivent chacune les leurs. Le vocabulaire avicole était donc appliqué à toutes les filières.

| Fiche | Colonne 1 | Colonne 2 | Source |
|---|---|---|---|
| Goliaths | Achats | **Nés (Couveuse)** | `fiche-goliaths.html` l.154 |
| Pintades | Achats | **Nés (Couveuse)** | `fiche-pintades.html` |
| Lapins | Achats | **Nés (Mise bas)** | `fiche-lapins.html` |
| Poissons-Chats | Achats | **Nés** | ÉCART_DELIBERE, voir ci-dessous |
| Poulets | Achats | **Nés / Transferts** | `fiche-poulets-pondeuses.html` l.139 |
| Pondeuses | **Achats / Entrées** | **Nés / Transferts** | `fiche-poulets-pondeuses.html` l.368 |

Ces libellés vivent désormais dans `ConfigurationEspece` (`libelleAchats`, `libelleNaissances`), aux côtés des catégories et des étapes du cycle — c'est-à-dire là où le reste du vocabulaire de la filière est déjà décrit.

#### ÉCART_DELIBERE — Poissons-Chats

`fiche-poissons-chats.html` l.161 intitule la colonne « **Alevins (Naissance/Empoissonnement)** ». La Gérante demande « **Nés** » tout court, et elle a raison sur les deux points :

- « Alevin » est déjà le nom de la **première catégorie**, affichée quelques lignes plus bas dans la même carte ;
- l'**empoissonnement** — acheter des alevins pour peupler un bassin — se saisit dans la colonne **Achats**. Le libellé du prototype mélangeait donc les deux entrées que la ligne sépare précisément.

Huit tests verrouillent ce glossaire, dont un qui vérifie qu'aucune filière n'emprunte le vocabulaire d'une autre : « couveuse » ne peut apparaître que chez les Goliaths et les Pintades.

### Uniformisation des champs de la saisie journalière

**Défaut signalé : les champs « Achats » et « Nés » n'avaient pas le même dessin que « Ventes (POS) ».**

Deux causes, toutes deux réelles :

1. **La bordure.** Le champ des deux premières colonnes ne renseignait que `border` dans son `InputDecoration`. Or Flutter ne s'en sert que **faute d'état plus précis** : au repos, c'est `enabledBorder` qui s'applique, et il retombait sur celui du thème. Les deux premières colonnes n'avaient donc pas la bordure `outline-variant` de la troisième, alors que le prototype leur donne la **même classe CSS**.
2. **La hauteur.** La colonne « Ventes » portait une note sous le champ (« Alimenté par le point de vente ») que le prototype n'a pas : il met « (POS) » **dans le libellé**, en 9 px et sans gras. Cette ligne supplémentaire décalait la troisième colonne.

Le champ avait été réécrit **trois fois** — deux dans la fiche d'espèce, une dans le suivi du stock d'œufs — et les copies avaient divergé. Il n'en reste qu'une, `ChampSaisieNombre` dans le socle, déclarant ses quatre états de bordure. La lecture seule n'est plus un widget séparé : c'est le même champ avec `onChange: null`, exactement comme le prototype réutilise l'input en ajoutant `readonly`.

#### Hauteur des champs — `h-10` → `h-11`

Demandé par la Gérante : les champs Achats / Nés / Ventes (POS) étaient trop serrés.

Le prototype leur donne `h-10` (40 px), la taille de ses **barres de filtres**. Ses **champs de formulaire**, eux, sont en `h-11` (44 px) — `saisie-depenses.html`, modale Nouveau Soin, modale Cycle Couveuse. Sur un écran où l'animalier saisit au clavier tous les jours, c'est cette seconde hauteur qui convient. 44 px n'est donc pas un nombre inventé : c'est la mesure que le prototype emploie lui-même partout où l'on saisit.

`ChampSaisieNombre.hauteurStandard` porte la valeur, et un test la verrouille.

### Vue Hebdomadaire — le seul écran de fiche qui manquait encore

Recensée comme manque de notre côté lors du portage de la visite guidée : l'étape « Bascule Vue Hebdomadaire » du prototype visait `#btn-view-weekly`, sans cible en face. Elle en a une.

La section « Tableau Mensuel » devient « **Historique du Mois** », titre du prototype, avec la pilule **Grille Quotidienne / Vue Hebdomadaire** posée à droite (`switchDensityView()`). La bascule est un état d'affichage local : rien à persister.

| Colonne | Source |
|---|---|
| Semaine | `Semaine N (1-7 août)` — bornes et mois calculés |
| Cumul Achats · Cumul *Nés* · Cumul Morts · Cumul Ventes | somme des journées **enregistrées** de la semaine |
| Effectif Fin de Semaine | effectif du soir du **dernier jour saisi** |
| Taux Mortalité Semaine | morts ÷ effectif de début de semaine |
| Traitements & Prophylaxie | observations réellement saisies |

L'en-tête de la 3ᵉ colonne suit le glossaire de la filière : « Cumul Nés (Couveuse) », « Cumul Nés (Mise bas) », « Cumul Nés »…

#### Trois corrections par rapport à `renderWeeklyGrid()`

1. **Les découpes n'étaient pas calculées.** Le prototype code `[[1,7],[8,14],[15,21],[22,31]]` en dur et étiquette « 22-31 **août** », le mois étant lui-même figé. En février, la 4ᵉ ligne annoncerait trois jours inexistants. Les bornes sont dérivées de la longueur réelle du mois — testé sur 28, 29, 30 et 31 jours.
2. **La colonne Traitements n'est pas reprise du calendrier.** Le prototype la remplit avec `PROPHYLAXIE_MULTI_CALENDAR[jourDuMois]`, or ce calendrier est indexé sur le **jour du cycle** (voir Doc K2 §B.1). L'écran affiche donc les observations réellement notées sur les journées, pas une projection fausse.
3. **Une semaine sans saisie affiche des tirets, pas des zéros.** Sa ligne reste visible — elle fait partie du mois — mais un « 0 mort » sur une semaine jamais renseignée se lirait comme une semaine sans perte. Même règle pour le taux de mortalité quand l'effectif de départ est nul.

L'effectif de report du mois n'est stocké nulle part : il est reconstitué depuis la première journée saisie, en lui rendant ce qu'elle a retiré et en lui retirant ce qu'elle a ajouté.

Treize tests couvrent le calcul, dont un qui vérifie que **la somme des 4 semaines égale le total du mois**.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **506 tests au vert** · build **release** compilé, packagé et lancé.

## Couveuse multi-âges — incubation en continu (v21)

**Demandé par la Gérante** (`incubation.txt`). Le module suivait un lot isolé, de sa date de chargement à son éclosion. Il suit désormais un **couvoir en rotation** : plusieurs lots d'âges différents cohabitent, chacun avec son propre calendrier, dans une ou plusieurs machines.

### ⚠️ La pintade incube 28 jours, pas 27

Le prototype écrit `data-duree="27"` (`cycle-couveuse.html` l.232). La Gérante a corrigé. Sur un lot isolé, un jour d'écart passerait inaperçu ; sur un couvoir en continu, **l'erreur se répète à chaque rotation** et décale toutes les relèves. Trois tests qui verrouillaient les 27 jours ont été réécrits.

### Ce qui a été ajouté

| Champ | Où | Rôle |
|---|---|---|
| `machineId` | `CYCLE_COUVEUSE` | l'incubateur occupé |
| `oeufsBlancsJ7` | `CYCLE_COUVEUSE` | `B_i(7)` — œufs clairs, mirage 1 |
| `oeufsGatesJ14` | `CYCLE_COUVEUSE` | `M_i(14)` — œufs gâtés, mirage 2 |
| `lotParentId` | `CYCLE_COUVEUSE` | lot dont celui-ci reprend la place |
| — | **`MACHINES_INCUBATEUR`** | table créée : code, libellé, capacité |

Le statut gagne une troisième valeur, **« Remplacé »**, qui n'efface pas l'éclosion : poussins nés, pertes et TER restent lisibles. Le statut dit seulement que la place dans la machine est reprise.

#### Deux champs volontairement **non** stockés

Le cahier des charges liste « date de remplacement » et « quantité remplacée ». Ce sont, pour un sous-lot, **sa propre date d'insertion et sa propre quantité initiale** — exposées comme getters, jamais dupliquées en colonnes. Deux copies de la même information finissent toujours par diverger.

L'« historique des remplacements » est la **chaîne de ces liens** : `SuiviIncubation.lignee()` la reconstitue dans l'ordre chronologique, `racineDe()` remonte au lot d'origine depuis n'importe quel maillon.

### Taux d'Éclosion Réel

```
TER = E_i(21/28) / (E_i(0) − [B_i(7) + M_i(14)]) × 100
```

Le dénominateur — les œufs **encore en incubation après les deux mirages** — est ce qui distingue le TER du taux brut. Un lot de 200 œufs dont 40 sont clairs n'a jamais eu 200 chances d'éclore : le rapporter à 200 confondrait une mauvaise **fécondation** avec une mauvaise **incubation**. L'écran affiche les deux côte à côte, chacun avec sa base (« sur 85 œufs retenus » / « sur 100 œufs chargés ») ; un écart important entre les deux désigne les reproducteurs, pas la machine.

**Le TER est `null`, jamais 0**, tant que l'éclosion n'est pas saisie — et aussi quand le dénominateur est nul. Un lot entièrement vidé aux mirages n'a pas un taux de 0 % : il n'a plus d'œufs.

**Le TER moyen est pondéré par les œufs retenus**, pas moyenné sur les taux. Un lot de 300 œufs et un lot de 12 ne pèsent pas pareil : la moyenne arithmétique laisserait un petit lot raté effondrer un couvoir par ailleurs excellent.

`terMoyenA(lots, t)` répond au « TER à une date précise t » du cahier des charges — seuls les lots arrivés à terme au plus tard à `t` y entrent. Aucun calcul n'appelle `DateTime.now()` : la date de référence est injectée, ce qui rend les résultats vérifiables.

### Alertes aux dates critiques

Une échéance reste due **tant que la saisie manque** — un mirage oublié le 8 août est toujours signalé le 20, avec ses 12 jours de retard. C'est délibéré : un couvoir en continu se rate par les mirages oubliés, pas par les éclosions, que les poussins signalent d'eux-mêmes. L'œuf clair laissé une semaine de plus pourrit et contamine ses voisins.

Le bandeau est placé **avant** le tableau, et les retards les plus anciens remontent en premier — c'est l'ordre dans lequel il faut agir.

### Remplacement automatique

À l'éclosion, une case « Recharger la machine immédiatement » crée un **sous-lot** dans la même transaction : si sa création échoue, le lot d'origine ne reste pas marqué « Remplacé » avec une place restée vide. Le sous-lot hérite de la **machine**, jamais du **calendrier** — il repart de sa propre date d'insertion, et peut changer d'espèce.

Supprimer un lot ne supprime pas ses sous-lots : leurs œufs sont physiquement dans la machine, une cascade les ferait s'évaporer. Ils deviennent des lots racines.

### ⚠️ Point 6 du cahier des charges — l'API REST

> « Exposer une API REST (JSON) pour que Flutter consomme ces données. »

**Aucun serveur HTTP n'est embarqué**, et c'est délibéré. LogiALVIA est une application **desktop hors-ligne** : la base est un fichier SQLite local, il n'y a ni backend à interroger ni consommateur distant. Embarquer un serveur dans l'exécutable de la Gérante ouvrirait un port sur son poste sans que rien ne s'y connecte.

Ce qui est livré est le **contrat JSON exact** qu'une telle API renverrait — `SuiviIncubation.versJson()` et `CycleIncubation.versJson()` —, produit localement, consommé par l'écran, et couvert par des tests. Le jour où un backend existe, il reprend ce contrat sans qu'une ligne du domaine change.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **624 tests au vert** dont 58 dédiés à l'incubation · build **release** compilé, packagé et **lancé** · migration **v20 → v21** sur base existante.


## Décès d'infirmerie porté sur la fiche d'élevage (v24)

### La promesse que le prototype ne tenait pas

`soins-calendrier.html` l.326, modale « Déclarer le Décès ? » : le décès
« sera reflété dans le décompte de mortalité de la fiche d'élevage
correspondante ». **Aucune ligne du prototype ne le fait.** Le portage l'avait
signalé à l'écran plutôt que de reproduire un message mensonger (Master Prompt
§2.3), mais la conséquence métier restait entière : un animal isolé à
l'infirmerie puis mort **sortait de l'effectif sans jamais entrer dans le taux
de mortalité**. Sur une exploitation où ce taux est le premier indicateur
sanitaire, le chiffre était faux — et rien ne le disait.

### ⚠️ L'information qui manquait : la catégorie

Une fiche compte les morts **par catégorie d'effectif** (`mortCat1..4`), et une
entrée d'infirmerie ne dit pas de quelle catégorie relève le sujet — « Goliath
#G-014 » est un texte libre. La modale **pose la question** au lieu de la
deviner : un menu des catégories réelles de la filière, plus l'option
« **Déjà saisie sur la fiche — ne rien ajouter** », qui est une réponse à part
entière. Le bouton « Confirmer le Décès » reste **inactif** tant qu'aucune
réponse n'est donnée. Choisir à la place de l'animalier fausserait un effectif
que personne ne rectifierait ensuite.

Quand l'entrée n'est rattachée à **aucune filière** (le champ est facultatif),
la modale le dit et le décès est enregistré sans report — il n'existe pas de
fiche où l'écrire.

### Le report n'est pas un `UPDATE` de `mortCatN`

`effectif` et les sous-effectifs sont des **résultats calculés** (BR-ELV-007).
Incrémenter la mortalité sans les recalculer — et sans propager la **cascade**
aux jours suivants déjà saisis (Doc 05 §5) — laisserait l'effectif faux, sans
qu'aucun écran ne le signale : c'est exactement le bug cardinal du projet.

Le report repasse donc par `EnregistrerJourneeUseCase`, comme une saisie
ordinaire :

- le décès **s'ajoute** aux mouvements du jour, il ne les remplace pas ;
- la journée est **créée si elle n'existe pas** — un décès survenu un jour non
  encore saisi doit compter — et marquée saisie, sans quoi la cascade
  s'arrêterait sur elle ;
- la **vente du jour est relue depuis le POS** (`FICHE_VENTES_JOUR`) : sans
  cela, créer la journée remettrait à zéro des ventes déjà encaissées et
  regonflerait l'effectif d'autant.

L'animalier retrouve la perte **déjà renseignée** en ouvrant sa fiche : c'est
aussi ce qui empêche le double comptage.

### Ordre des écritures, et ce qu'un échec laisse derrière lui

`INFIRMERIE.categorieMortalite` (v24) distingue « décédé » de « décédé **et
compté** ». La clôture est écrite **avant** le report ; la marque n'est posée
qu'**après** lui. Un échec en cours de route laisse donc une entrée close et
**non reportée** — état honnête, affiché en clair dans le tableau de suivi
(« Mortalité portée sur la fiche » / « Mortalité non reportée ») — plutôt
qu'une perte comptée deux fois à la reprise.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **681 tests au
vert**, dont 14 dédiés à ce report (cascade, 4ᵉ catégorie des Pondeuses, vente
du POS préservée, catégorie hors bornes refusée, double clôture refusée) ·
migration **v23 → v24** sur base existante.


## Mise en bande et prophylaxie datée (v25)

### Le point ouvert le plus ancien du projet, clos

`parametres-elevage.html` annonce un calendrier « automatique injecté dans
Traitements & Prophylaxie des fiches journalières ». Deux choses manquaient
pour le tenir. La première — sur quel jour ce calendrier est indexé — a été
tranchée par le contenu lui-même : le **jour du cycle**, et non le jour du mois
(Doc INDEX 11-untricies-novies). La seconde manquait au modèle : **quand le
cycle commence**. Sans elle, « J5 » ne se convertit en aucune date.

`BANDES.dateMiseEnBande` est cette date. Elle se déclare sur la fiche
d'élevage, dans un bandeau « Bande en Cours » qui affiche le code de la bande,
sa date de mise en place et le **jour de cycle du jour affiché**.

### Ce que la fiche montre maintenant

La section « Traitements & Prophylaxie » de la saisie journalière —
`#day-prophy-multilist` du prototype, dernière cible de la visite guidée sans
point d'accroche de notre côté — liste les échéances qui tombent **ce jour de
cycle**, avec leur produit et leur délai d'attente calculé depuis la date
projetée.

⚠️ **Rien n'est projeté sans bande.** L'écran le dit et propose d'en déclarer
une, plutôt que de supposer que le cycle a commencé le 1ᵉʳ du mois.

### Planifier une échéance — pourquoi le type d'action est demandé

Chaque échéance peut devenir un soin planifié, visible dans le Calendrier de
Soins. Le **type d'action** est demandé à l'utilisateur : `TypeSoin` est une
liste fermée (Vaccination, Traitement curatif, Vermifuge, Vitamines) que le
calendrier de prophylaxie ne porte pas. Le déduire du libellé marcherait sur
« Vaccin Newcastle » et se tromperait sur « Contrôle Oxygénation / Ammoniac »,
qui n'est aucun des quatre.

`SOINS_CALENDRIER.bandeId` et `echeanceProphylaxieId` rendent l'opération
**idempotente** : une échéance déjà planifiée l'affiche et ne se reprogramme
pas. Une comparaison sur (espèce, date, traitement) n'aurait pas suffi — deux
bandes mises en place le même jour partagent ces trois valeurs.

### L'effectif de mise en place n'est pas l'effectif de la fiche

`effectifInitial` documente la mise en place ; il n'alimente **aucun calcul**.
L'effectif réel reste celui de `FICHE_JOURNEE`, recalculé jour après jour
depuis les saisies (BR-ELV-007). La fiche l'écrit sous le bandeau, pour qu'un
écart entre les deux chiffres ne passe pas pour une erreur de calcul.

### Bande rétroactive

Déclarer une bande dont la mise en place est passée est légitime — c'est même
le cas normal à la reprise. Le formulaire annonce alors le jour de cycle déjà
atteint : les échéances antérieures restent visibles à leur date, l'application
n'ayant aucun moyen de savoir si elles ont été faites.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **718 tests au
vert**, dont 23 dédiés à la mise en bande (projection, bande décalée, clôture,
idempotence, rendu de la fiche) · migration **v24 → v25** sur base réelle,
34 → 35 tables, aucune donnée perdue.


## Cycle Couveuse — l'écran restructuré pour l'incubation continue (v25)

Le suivi multi-âges existait dans le domaine depuis v21 : machines, mirages
J+7 / J+14, sous-lots de remplacement, TER pondéré, alertes. **L'écran n'en
exposait qu'une partie** — un référentiel qu'aucun écran n'alimente est un
référentiel vide.

Quatre manques comblés :

1. **Parc d'incubateurs** — une carte par machine : code, libellé, occupation
   réelle en **œufs retenus après mirages** (un œuf clair retiré au J+7 ne
   prend plus de place), taux de remplissage, nombre de lots en cours. Le
   bouton « Ajouter un Incubateur » manquait : `MACHINES_INCUBATEUR` existait
   depuis v21 sans qu'aucun écran ne puisse y écrire. **La capacité annoncée
   sert à signaler une surcharge, jamais à la bloquer** ; laissée vide, aucun
   taux n'est inventé.
2. **Date de référence** — « Situation au … ». Tout ce que l'écran affiche est
   daté : l'âge d'un lot, les échéances atteintes, le TER. Le prototype
   calculait implicitement à « aujourd'hui », ce qui interdisait de
   reconstituer l'état du couvoir un jour donné. ⚠️ Le TER **n'existe pas**
   avant le terme du lot : `null`, jamais 0 — un zéro se lirait comme un échec.
3. **Prochaines échéances (3 jours)** — séparées des alertes à dessein : ce qui
   est **dû** et ce qui **arrive** ne demandent pas la même chose, les mélanger
   ferait perdre l'urgence des premières.
4. **Historique des remplacements** — la chaîne des `lotParentId`, du lot
   racine au dernier sous-lot, avec le **TER de la lignée** : la productivité
   d'un emplacement sur la durée, que le TER d'un lot isolé ne dit pas. Le
   bouton n'apparaît que sur les lots qui appartiennent à une chaîne.

**Bug de rendu attrapé par les tests** : la colonne « Actions » débordait de
4,2 px (`RenderFlex overflowed`) depuis qu'une quatrième commande s'y ajoutait.
Corrigé en flex 3, avec des icônes à contraintes explicites.

**Vérification** : 14 tests montent l'écran pour de bon — couvoir vide et
peuplé, occupation avec et sans capacité, surcharge signalée, date de référence,
échéances à venir, ouverture de la lignée, TER daté.


## Couveuse — ce que la Gérante a demandé en plus (v25)

### La date d'éclosion s'affiche en fenêtre, pas au jour près

Une éclosion ne tombe pas au jour dit : la température, l'hygrométrie et l'âge
des reproducteurs l'avancent ou la retardent. Annoncer une date exacte ferait
passer une éclosion parfaitement normale à J−1 pour une avance anormale — et
pousserait à ouvrir la machine trop tôt.

La modale de création affiche désormais un **calendrier prévisionnel** complet :

| Échéance | Affichage |
|---|---|
| Mirage 1 (J+7) | date exacte — c'est un rendez-vous fixe |
| Mirage 2 (J+14) | date exacte |
| Éclosion (J+21 ou J+28) | **fenêtre** `date − 2 j ——— date + 2 j` |

La tolérance de deux jours (`CycleIncubation.toleranceEclosionJours`) vient de
la Gérante ; elle n'est pas déduite d'une moyenne.

### Incubateur sélectionnable à la création et à l'édition

`CYCLE_COUVEUSE.machineId` existait depuis v21, et le filtre par machine s'en
servait déjà — mais **aucun écran ne permettait de le renseigner**. Le champ est
maintenant dans la modale, création et édition. « Non précisé » reste possible :
imposer une machine bloquerait une saisie légitime.

### Les mirages se saisissent depuis la ligne du lot

La colonne « Mirages » porte deux **boutons** au lieu de deux cellules
cliquables, avec trois états distincts et lisibles :

- **vert** — mirage fait, avec le nombre d'œufs retirés ;
- **rouge « À saisir »** — échéance atteinte, mirage manquant ;
- **gris** — date prévue, pas encore due.

Le bouton **Éclosion** est passé en fond rouge plein : c'est l'action qui
clôture le lot et fait entrer les poussins dans les effectifs, dans une ligne
qui porte quatre commandes.

### Les sous-lots ont leurs propres mirages

Un sous-lot de remplacement entre en machine à une autre date : son J+7 et son
J+14 ne tombent donc pas avec ceux du lot qu'il remplace. La modale
« Historique des Remplacements » affiche pour chaque occupation ses deux
mirages et leurs dates — sans quoi on croirait la lignée soumise à un seul
calendrier.

## Écran Statistiques des Mirages (v25)

### Ce que le TER seul ne dit pas

Trois causes distinctes se cachent derrière un même taux décevant :

| Constat | Cause | Qui est en cause |
|---|---|---|
| Beaucoup de **clairs** au J+7 | œufs jamais fécondés | le troupeau reproducteur |
| Beaucoup de **gâtés** au J+14 | embryons démarrés puis arrêtés | la conduite de la machine |
| Peu d'**éclos** sur les retenus | éclosion ratée | la fin d'incubation |

Les additionner dans un « taux de perte » unique reviendrait à jeter
l'information au moment précis où elle devient utile.

### ⚠️ Les dénominateurs ne sont pas interchangeables

- **Infertilité** = clairs ÷ œufs chargés, sur les **seuls lots mirés**.
  Rapporter aux œufs de tous les lots, mirés ou non, ferait baisser le taux à
  mesure que des mirages manquent : la négligence ressemblerait à un bon
  résultat.
- **Mortalité embryonnaire** = gâtés ÷ œufs **encore présents au J+14**, donc
  après retrait des clairs. Les clairs ne sont pas morts, ils n'ont jamais
  vécu ; les compter au dénominateur diluerait le taux et masquerait un vrai
  défaut de conduite.
- **TER** = éclos ÷ œufs retenus après les deux mirages.
- **Perte totale** : calculée sur les **seuls lots clôturés**. Un lot encore en
  machine n'a rien perdu, il n'a pas fini.

Un bandeau signale les lots dont un mirage est échu et non saisi : tant qu'il
manque, tous les taux de l'écran sont faux.

**Vérification** : 15 tests sur le service, dont ceux qui verrouillent chaque
dénominateur.
