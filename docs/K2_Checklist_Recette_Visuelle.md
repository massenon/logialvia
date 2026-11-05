# K2 — Checklist de Recette Visuelle (par écran)

À exécuter pour **chacun des 31 écrans** avant de le considérer terminé — cohérent avec l'exigence de fidélité pixel-perfect (Master Prompt).

---

## Checklist Structurelle (à cocher pour chaque écran)

- [ ] **Structure de page** identique à Doc F0/03 (correspondance fichier confirmée)
- [ ] **Ordre des sections** identique au HTML source, aucune section réordonnée
- [ ] **Espacements** utilisent exclusivement `AppSpacing` (Doc E1) — zéro valeur numérique en dur
- [ ] **Conteneurs** (cartes, modales) utilisent `AppRadius`/`AppShadows` (Doc E1) — pas de style ad hoc
- [ ] **Hiérarchie typographique** utilise exclusivement `AppTypography` (Doc E1)
- [ ] **Position des boutons** identique au prototype (primaire à droite, secondaire à gauche dans les modales, etc. — Doc G2 §5)
- [ ] **Emplacement des CTA** (call-to-action) inchangé
- [ ] **Animations** reproduites (transitions de modale, accordéon KPI) — Doc E2/E7
- [ ] **KPIs** affichent systématiquement un texte, jamais de carte vide (Doc E7 §1, Doc G2 §7)
- [ ] **DataTables** ont header/footer/filtre/actions/modale d'édition/message de suppression/offcanvas conformes à Doc E4
- [ ] **Bouton Imprimer PDF** présent où attendu, comportement conforme Doc E9
- [ ] **Comportement responsive** vérifié à au moins 3 largeurs : 1024px (`lg`), 1280px (`xl`), largeur de lancement 1440px
- [ ] **Navigation** vers/depuis cet écran fonctionne dans les deux sens (Doc E3)
- [ ] **Calculs** (si applicable) vérifiés contre au moins 3 cas de test tracés manuellement (Doc 05, Strict Avoid §2)

## Checklist Fonctionnelle

- [ ] Aucun bouton n'affiche un succès sans persistance réelle (Master Prompt §2, Strict Avoid §10)
- [ ] Toute suppression passe par la modale d'avertissement (Doc E5 §3)
- [ ] Toute validation de formulaire affiche l'erreur sous le champ concerné (Doc E6)
- [ ] Les données affichées viennent de la base réelle (Drift), jamais de valeurs mock statiques une fois le Repository branché
- [ ] Rôle RBAC vérifié : l'écran est inaccessible/limité selon la matrice (Doc I1) pour au moins 2 rôles différents testés manuellement

## Checklist Technique

- [ ] `flutter analyze` : zéro avertissement non justifié
- [ ] Tests unitaires présents pour toute logique de calcul (Doc 05) si l'écran en contient
- [ ] Aucune duplication détectée avec un autre écran (vérification manuelle si le pattern se répète sur plusieurs des 31 écrans, Strict Avoid §12)
- [ ] Accessibilité : `Semantics` présents sur modales/onglets/boutons icône-seule (Doc G2 §8)

## Checklist de Confrontation Visuelle Directe

- [ ] Capture d'écran Flutter côte à côte avec une capture du HTML source (ou le HTML ouvert dans un navigateur à la même largeur de fenêtre)
- [ ] Différences de couleur perceptibles : 0 (au pixel de tolérance d'anti-aliasing près)
- [ ] Différences de position d'élément perceptibles : 0

---

## Processus de Signature

Une fois toutes les cases cochées pour un écran, il passe du statut "En Développement" à "Recetté" dans le suivi de projet (mécanisme de suivi hors périmètre de cette documentation — à définir avec l'outil de gestion de projet utilisé par l'équipe). Un écran non recetté ne doit jamais être présenté comme terminé, cohérent avec le principe de non-généricité et d'honnêteté sur l'état d'avancement déjà appliqué tout au long de cette série de documents.

---

# Recette effectuée — confrontation écran par écran contre `prototype_html`

Passage systématique : pour chaque page du prototype, relevé des modales (`id="modal-*"`), des onglets internes (`*-tab-btn-*`), des cartes KPI (`border-l-4`) et des gestionnaires `onclick`, puis confrontation au code Dart. Ce qui suit est le résultat, pas une impression.

---

## A. Défauts corrigés pendant cette recette

### A.1 ⚠️ Le plus grave — le point de vente calculait le montant au lieu de le demander

**Écran** : Ventes → Enregistrer Vente (`ventes.html`).

L'implémentation ajoutait le produit au panier d'un clic, avec un compteur `− 1 +`, et calculait `quantité × prix du catalogue`. C'est un POS de supermarché.

Le prototype ne fait **jamais** cela. Chaque clic sur un produit ouvre `#modal-weight`, intitulée **« Vente à la Pièce »**, qui demande deux valeurs **indépendantes** :

| Champ | Contenu |
|---|---|
| **Quantité (`unité`)** | Le libellé porte l'unité réelle du produit — « Quantité (u) », « Quantité (sujet(s)) » (`weight-qty-label`) |
| **Montant Global de la Vente (FCFA)** | Le **total convenu** pour la ligne |

Et sa note ne laisse aucune place au doute :

> « Vente à la pièce : saisissez directement le montant total convenu — **jamais un prix unitaire multiplié automatiquement**. Le prix indicatif n'est qu'une fourchette de référence. »

C'est cohérent avec le reste du modèle : `PRODUITS_VENDABLES.priceMax` définit une **fourchette de négociation** (Doc D1). Sur un marché de Natitingou, le prix d'un goliath se discute.

**Conséquence de l'erreur** : sur 2 sujets négociés à 11 000 F, l'application facturait 12 000 F — un montant que personne n'avait convenu. Ce n'était pas un écart d'apparence mais de **comportement métier**.

**Corrigé** : `LignePanier` porte désormais `montantGlobal` (saisi) ; `prixUnitaire` en est **déduit** pour l'historique et l'écriture comptable, et n'entre dans aucun total. La modale reproduit le libellé, la note et le comportement d'édition (`editWeightLine()`). Un même produit peut occuper plusieurs lignes à des montants différents — le prototype empile (`cart.push`), deux clients ne négocient pas au même prix. **15 tests** verrouillent la règle, dont la comparaison explicite « 11 000 saisi ≠ 12 000 calculé ».

### A.2 ⚠️ La modale « Livraison » n'enregistrait rien — chez nous comme dans le prototype

**Écran** : Ventes → Enregistrer Vente, bouton `#livraison-toggle-btn`.

Elle était purement absente de l'implémentation. Vérification faite dans le prototype : elle y est présente, mais **`validateSale()` ne lit aucun de ses champs**. Ni le mode, ni les frais, ni l'adresse ne survivent au clic sur « Valider ». Même « Livraison facturée séparément » avec un montant saisi n'affecte pas le total encaissé. C'est l'anti-patron que le Master Prompt §2.3 désigne nommément.

**Implémenté pour de bon** — schéma **v14**, 4 colonnes sur `VENTES` :

| Élément | Comportement |
|---|---|
| Case « Livraison concernée (cages, sujets volumineux) » | Fidèle |
| 4 modes (gratuite / client / incluse / facturée) | Fidèles, libellés mot pour mot |
| Champ « Frais » visible **uniquement** en mode facturée | Fidèle (`onDeliveryModeChange()`) |
| Adresse, Contact du transporteur | Persistés |
| Pastille ✓ verte + bordure verte sur le bouton | Fidèle |
| **Les frais entrent dans le total** | **Ajout** — seule lecture cohérente de « facturée séparément » |

Le sous-total et le supplément n'apparaissent au panier que si un supplément existe. 6 tests.

### A.3 Menu flottant « Accès Rapide » — entièrement absent

`toggleSpeciesQuickNav()` (`common.js` l.59) et son panneau (`sidebar.js` l.104-128) n'étaient pas implémentés : ni le bouton rond navy en bas à droite, ni le voile, ni l'offcanvas de 288 px.

Ce n'est pas un ornement. Le commentaire du prototype explique pourquoi :

> « Menu flottant autonome. **Indépendant du toggle du sidebar** — reste accessible que le sidebar soit ouvert, replié (desktop) ou masqué (mobile). »

Replier la barre latérale pour gagner de la place sur une fiche de saisie **coupait donc toute navigation**.

**Implémenté** : bouton rond à `bottom: 88px`, décalé à `right: 80px` quand la barre est repliée (comme `toggleSidebarDesktop()`), voile `black/40`, panneau glissant de 300 ms, et les **12 raccourcis dans l'ordre exact** avec leurs couleurs (navy pour les fiches, bleu pour les soins, or pour les modules). La fiche Poissons-Chats disparaît si la filière est désactivée (`data-module="pisciculture"`, Doc I2 §3).

---

## B. Manques constatés et **non** implémentés — à arbitrer

Aucun de ces éléments n'est un lien mort : ils sont absents, pas inertes. Ils sont listés par ordre d'enjeu métier décroissant.

### B.1 ~~Fabrication de Provende~~ — `#modal-fabrication` — ✅ **IMPLÉMENTÉE** (voir Doc F5)

La plus importante. La modale saisit les 5 intrants (Maïs, Soja, Coquille d'huître, Poudre de poisson, Tourteau de palmiste), totalise en kg, et **bloque si un stock est insuffisant** (`computeFabricationTotal()`). Sa note invoque une exigence contractuelle :

> « Toute sortie d'intrant pour la fabrication de provende doit être justifiée par cette opération — **jamais une simple sortie de stock isolée** (Cahier des Charges Technique §6.2, §8.3). »

Or `confirmFabrication()` du prototype **affiche un toast et ne décrémente rien**, alors que ce toast annonce « stocks des 5 intrants décrémentés automatiquement ». La fonctionnalité est donc à écrire pour de bon : une opération atomique décrémentant les 5 intrants et écrivant 5 `MOUVEMENTS_INTRANT`. Le module Approvisionnement a déjà tout ce qu'il faut.

### B.2 Popup « Prophylaxie du Jour » — `#modal-prophylaxie` (Tableau de Bord et Dashboard Élevage)

`assets/js/prophylaxie-popup.js` : au chargement du tableau de bord, si le jour du mois est **1, 5, 8 ou 15**, une fenêtre rappelle le soin à administrer (Déparasitage, Anti-coccidien 1/4 et 4/4, Vaccin Newcastle). Le rappel est marqué comme vu pour la journée.

**Point de vigilance** : ce calendrier est basé sur le **jour du mois**, alors que `CALENDRIER_PROPHYLAXIE` (schéma v12, Doc F3) l'indexe sur le **jour du cycle**. Les deux ne se recouvrent pas. Il faudra trancher lequel fait foi avant d'implémenter — sinon deux calendriers contradictoires cohabiteront.

### B.3 « Planifier une Intervention » — `#modal-planifier-intervention` (Calendrier de Soins)

Formulaire à 3 champs : Lot/Bande, Intervention, Date prévue. Il fait doublon partiel avec « Nouveau Soin », déjà implémenté avec ses 9 champs. À confirmer : est-ce une saisie allégée voulue, ou un reliquat ?

### B.4 Sélection de la ligne Mobile Money — `#modal-account-select` (POS)

Choisir le compte Mobile Money encaisseur quand ce mode est sélectionné. `MOBILE_MONEY_ACCOUNTS` du prototype ne contient **qu'une seule ligne** (« +229 97 00 00 00 (Gérante) »), écrite en dur, et aucune table ne modélise les comptes de la ferme. Implémenter un choix entre une seule option serait décoratif ; le faire correctement suppose une table `COMPTES_MOBILE_MONEY` et un écran de gestion. **À arbitrer.**

### B.5 Visite guidée — `startTourGuide()`

Second bouton flottant, bleu, à `bottom: 144px`. **22 pages** définissent leur `window.TOUR_STEPS` : une bulle pointe successivement des éléments de l'écran avec un titre et une explication. C'est un vrai dispositif de prise en main pour une utilisatrice non informaticienne. Le contenu existe déjà, entièrement rédigé, dans le prototype.

### B.6 Notifications — filtre et pied de liste

Le menu déroulant existe et affiche des **alertes réelles** (contre des lignes en dur côté web). Manquent : l'en-tête « Notifications », les onglets **Toutes / Non lues**, l'horodatage relatif (« il y a 20 min ») et le lien « Voir toutes les notifications ». Le filtre « Non lues » exige un état lu/non-lu qui n'existe pas dans le modèle : l'ajouter, ou renoncer au filtre — le même arbitrage que pour le statut des dépenses.

---

## C. Éléments du prototype volontairement écartés — vérifié, pas oublié

| Élément | Raison |
|---|---|
| `toggleDarkMode()` | Défini dans `common.js` mais **appelé par aucune page** : code mort côté web. Aucun bouton n'existe pour le déclencher. |
| `switchTestRole()` — sélecteur « 🔑 Administratrice / 💵 Agent de Vente / 🐔 Agent d'Élevage » | Outil d'audit RBAC de la maquette. Le rôle réel vient de la session ; laisser un sélecteur permettrait de changer de rôle sans se réauthentifier (Doc I3). Déjà documenté. |
| `toggleKpiPanel()` — accordéon KPI | `md:hidden` : mobile uniquement. L'application est Desktop Windows. |
| Badge « 3 en attente » avec icône `sync` animée | Aucune synchronisation n'existe (application hors-ligne). Déjà documenté. |
| `openMobileSearch()` | Recherche mobile ; la recherche globale desktop est implémentée. |
| `show403Overlay()` | Défini, **jamais appelé**. Le refus d'accès passe par la redirection du routeur (Doc E3 §6). |
| Pages `m10-*.html` | Plan comptable d'un autre projet (hôtellerie-restauration) — déjà documenté en Doc F6 §10.1. |
| `bilan-entreprise.html`, `elevage-dashboard-1.html` | Absorbées : la première par États Financiers (Doc F6 §1), la seconde est un doublon de `elevage-dashboard.html`. |

---

## D. Écrans confrontés sans écart structurel

Modales, onglets et cartes KPI comptés et retrouvés un à un :

| Écran | Onglets | Modales | Verdict |
|---|---|---|---|
| Catalogue Produits | 2 | 3/3 | conforme |
| Cycle Couveuse | — | 4/4 | conforme |
| Fournisseurs | 2 | 2/2 | conforme |
| Journal Comptable | — | 1/1 | conforme (disposition du tableau : écart documenté F6 §10.6) |
| Plan Comptable | — | 2/2 | conforme |
| Paramètres Élevage | 4 | 5/5 | conforme |
| Paramètres Généraux | 4 | 1/1 | conforme |
| Clôture d'Exercice | — | 1/1 | conforme (+ grille mensuelle ajoutée, F6 §10.11) |
| Saisie des Dépenses | — | 1/1 | conforme (2 corrections documentées F6 §10.4-10.5) |
| États Financiers | 4 | — | conforme |
| Rapports & États | 6 | — | conforme |
| Contact Éditeur | 2 | — | conforme (formulaire rendu réel, F9) |
| Fiche Poulets/Pondeuses | 2 | — | conforme |
| Achats & Commandes | — | 1/1 | conforme |
| Relances Clients | — | 2/2 | conforme |
| Soins & Calendrier | 3 | 3/4 | **manque `#modal-planifier-intervention`** (B.3) |
| Gestion des Stocks | — | 2/2 | conforme — `#modal-fabrication` implémentée depuis (B.1) |
| Tableau de Bord | — | 0/1 | **manque `#modal-prophylaxie`** (B.2) |
| Ventes | 4 | 5/6 | **manque `#modal-account-select`** (B.4) — les 5 autres conformes après correction |

---

## E. Ce que cette recette n'a pas couvert

La confrontation porte sur la **structure et le comportement** : présence des écrans, des onglets, des modales, des champs, et exactitude des règles de calcul. Elle ne remplace pas la **comparaison pixel à pixel** de la §« Checklist de Confrontation Visuelle Directe » ci-dessus, qui suppose d'ouvrir chaque page HTML dans un navigateur à côté de l'application. Espacements, graisses et hauteurs de ligne n'ont pas été mesurés. ⚠️ Ce volet était **techniquement impossible** tant que les polices manquaient au dépôt : les graisses 600 et 800, posées 45 fois dans l'interface et 442 fois dans le prototype, étaient rendues par la voisine la plus proche faute de fichier les contenant. La fonte variable Roboto étant désormais livrée et vérifiée (INDEX point 12), le blocage est levé : reste le travail d'œil, écran par écran, navigateur à côté de l'application.

### Le volet pixel, outillé — `outils/audit_typographie.py` et `outils/apparier_typographie.py`

Le volet pixel supposait d'ouvrir chaque page dans un navigateur et de comparer
à l'œil. Un script le mesure désormais, page par page, et **une première
divergence systémique est corrigée** :

- `.text-xs` est surchargé à `0.85rem` par `common.css`, chargé par 35 des
  41 pages : `text-xs` vaut **13,6 px**, pas 12. Le portage n'appliquait cette
  valeur qu'aux trois écrans d'authentification.
- Les cellules de tableau (`text-xs`, 327 relevés sur 338) sont donc **plus
  grandes** que les en-têtes (`text-[12px]`, 202 sur 205). Le portage les avait
  égalisées à 12 px.

Corrigé au niveau des jetons et des styles de base des sept modules, puis
verrouillé par `test/core/echelle_typographique_test.dart` — qui fige aussi
l'échelle d'espacement et les 15 couleurs contre `tailwind-config.js`.

Second passage : l'héritage est résolu **d'un niveau** — 27 tables posent
`text-xs` sur la balise `<table>` elle-même. **433 des 444 cellules mesurables
sont à 13,6 px** (97,5 %), et les tableaux des fiches d'élevage comme le suivi
d'infirmerie ont été alignés en conséquence.

**ÉCART_DÉLIBÉRÉ** : `cycle-couveuse`, `cloture-exercice` et
`comptabilite-analytique` ne posent aucune taille, ni sur les cellules, ni sur
la table, ni sur les ancêtres : leurs cellules héritent des **16 px** de la
racine, plus grandes que le corps de texte courant. C'est un oubli du
prototype, pas une intention — ces tables sont alignées sur les autres, et
l'écart est commenté dans le code.

**Ce qui reste** : 376 cellules héritent d'un ancêtre plus haut, et les
éléments hors tableau (formulaires, pastilles, panneaux) n'ont pas été
mesurés — 103 emplois de 12 px subsistent côté Dart. Le script refuse de
résoudre plus loin : l'arbre HTML n'est pas balancé dans les lignes assemblées
en JavaScript, et une mesure fausse serait pire que pas de mesure. Ces pages
sont à lire une à une, l'outil à côté.

### Recette sur données réelles — `test/parcours/tous_les_ecrans_test.dart`

La recette structurelle avait été menée sur une base quasi vide. Un tableau
vide ne déborde jamais : elle ne pouvait pas voir ce qui se casse **avec de la
matière**.

`SeedDemonstration` écrit 30 jours d'activité par les vrais chemins métier, puis
les **33 écrans** sont montés un par un à la taille réelle de la fenêtre du
poste (1382 × 794). Une exception de rendu fait échouer le test.

Premier passage : **deux écrans levaient `RenderFlex overflowed`** — Paramètres
Généraux (400 px) et Paramètres Élevage (24 px). Cause commune et infidélité :
les barres d'onglets du prototype portent `overflow-x-auto`, le portage les
avait figées. Corrigé sur les trois écrans concernés.

### État de vérification de ce passage

| Contrôle | Résultat |
|---|---|
| `flutter analyze` | **0 problème** |
| `flutter test` | **385 tests, 385 réussis** (15 nouveaux sur le POS et la livraison) |
| `flutter build windows --debug` | compilé, application relancée |
| Migration **v13 → v14** sur base réelle | 4 colonnes de livraison ajoutées à `VENTES`, **aucune donnée perdue** |

## Suites de la recette — 4 demandes de la Gérante

| # | Demande | Écran | Où c'est documenté |
|---|---|---|---|
| 1 | Colonne **Actions** (Éditer, Supprimer) sur « Lot d'Incubation » | Cycle Couveuse | Doc F3, §ÉCART_DELIBERE |
| 2 | Suivi des dépenses, Balance Générale, **Bilan de l'Entreprise** | Comptabilité | Doc F6 §10.19 |
| 3 | Bilan de l'Entreprise dans l'**Accès Rapide** et la **barre latérale** | transversal | Doc F6 §10.19 |
| 4 | « **Avance** » reclassée en condition de paiement | Paramètres Généraux, POS | Doc F8, §Divergence tranchée |

**Points 2 — état réel avant travaux** : le **Suivi des Dépenses** (`/depenses`) et la **Balance Générale** (`/comptabilite/balance`) étaient déjà livrés et présents dans la barre latérale ; seul le **Bilan de l'Entreprise** manquait, ayant été supprimé à tort. C'est donc le seul écran créé.

### État de vérification après les 4 demandes

| Contrôle | Résultat |
|---|---|
| `flutter analyze` | **0 problème** |
| `flutter test` | **433 tests, 433 réussis** (22 nouveaux : 5 couveuse, 9 bilan, 8 mode/condition, 5 migration) |
| `flutter build windows --debug` | compilé, application relancée |
| Migration **v14 → v15** | `VENTES.mode` nettoyé de la condition de paiement, `status`/`total`/`paye` intacts |

## §B clos — les 4 éléments recensés sont implémentés

Le §B recensait 3 modales non portées plus la visite guidée. Les quatre le sont désormais. Aucune n'a été reproduite telle quelle : chacune reposait sur un mécanisme que le prototype n'exécute pas.

### 1. Popup « Prophylaxie du Jour » — le calendrier était interrogé avec la mauvaise clé

**Le conflit annoncé en 11-sexdecies est tranché : le jour du cycle est la bonne clé.**

`parametres-elevage.html` l.170 intitule sa colonne « **Jour du Cycle** » et range ses échéances par espèce. Deux consommateurs la lisent pourtant comme un jour du mois :

| Fichier | Clé réellement utilisée |
|---|---|
| `prophylaxie-popup.js` l.25 | `new Date().getDate()` |
| `fiche-goliaths.html` l.488 | `PROPHYLAXIE_MULTI_CALENDAR[d]`, `d` parcourant 1→31 d'août 2026 |

Les deux jeux portent **les mêmes nombres** (1, 5, 8, 15) : voilà pourquoi la contradiction n'avait jamais sauté aux yeux. Le contenu, lui, ne laisse aucun doute :

- « Anti-stress (**post-éclosion**) » au jour 3 — l'éclosion, pas le 3 du mois ;
- « Anti-coccidien (Jour 1/4) » au jour 5 et « (Jour 4/4) » au jour 8 — une cure de 4 jours consécutifs suppose une date de départ commune ;
- « Vaccin Newcastle (**Rappel**) » — un rappel se programme sur l'âge du sujet ;
- la `remanence` (7 j, 5 j) est un délai d'attente avant commercialisation, qui court depuis l'administration.

Lire ce calendrier avec le jour du mois ferait rejouer le déparasitage tous les 1ᵉʳ à des sujets d'âges quelconques. `CALENDRIER_PROPHYLAXIE` utilise déjà `jourCycle` : le modèle avait raison.

**Ce que la popup affiche donc.** Les soins réellement datés de `SOINS_CALENDRIER`, pas le calendrier de prophylaxie. La projection du calendrier vers des échéances datées suppose une **date de mise en bande** que le modèle ne stocke nulle part — point 11-sexdecies, inchangé. L'encart de la popup le dit à l'écran plutôt que de laisser croire à une injection automatique qui n'a pas lieu.

**Deux écarts délibérés.** Les **retards** sont inclus, badge rouge à l'appui : un traitement oublié hier est plus urgent que celui du jour, l'omettre reviendrait à l'enterrer. Et **aucun `localStorage`** : le prototype coche ses lignes sous `logialvia_prophylaxie_done_AAAA-MM-JJ` tout en laissant le soin « Planifié » dans le registre — deux vérités pour un même traitement. Ici « Marquer fait » appelle `confirmerAdministration()`, le soin passe à « Effectué » en base, et la popup ne se rouvre pas parce qu'il ne reste rien à faire.

`testerPopupProphylaxie()` — l'ouverture forcée en « MODE TEST » avec une ligne d'exemple — n'est pas portée : elle afficherait un traitement inexistant.

Le report est valable pour la session : `initProphylaxieReminder()` s'exécute au `DOMContentLoaded` de chaque page, donc revenir au tableau de bord rouvre la popup côté web. Dans une application à navigation instantanée, un rappel qu'on ne peut pas écarter cesse d'être un rappel.

### 2. « Planifier une Intervention » — ce n'était pas un doublon

Le §B la soupçonnait de faire doublon avec « Nouveau Soin ». Elle ne l'est pas : celle-là consigne un soin **administré ou à administrer** (produit, dose, rémanence, vétérinaire, symptômes, coût) ; celle-ci pose une **échéance** dans le planning, en trois champs.

⚠️ Côté web les deux n'écrivent pas au même endroit : `confirmNouveauSoin()` alimente le registre, `submitPlanifierIntervention()` écrit dans `GANTT_LOTS[].interventions`, une structure parallèle en mémoire — d'où deux plannings qui ne se voient pas. Ici les deux écrivent dans `SOINS_CALENDRIER`, que le Gantt lit déjà. Le statut est toujours « Planifié » : on ne planifie pas ce qui est fait.

### 3. Ligne Mobile Money — une obligation dont le résultat était jeté

`ventes.html` l.388 code en dur `MOBILE_MONEY_ACCOUNTS`, **une seule entrée**, puis ouvre une modale bloquante pour faire choisir parmi cette unique option — et `validateSale()` ne conserve pas le choix. Le numéro codé en dur est exactement le « Téléphone Principal » de `parametres-generaux.html` l.147 : ce n'est pas une donnée du point de vente, c'est une donnée d'entreprise déjà administrable.

La modale disparaît, remplacée par un bandeau qui affiche la ligne créditée. Elle est **persistée** sur la vente (`VENTES.ligneMobileMoney`, migration v16), dénormalisée comme `LIGNES_VENTE.nom` : si la Gérante change de ligne l'an prochain, les encaissements passés doivent continuer de nommer celle qui les a reçus, sans quoi le rapprochement du compte 512 devient faux rétroactivement. Testé.

Si aucun numéro n'est enregistré, l'encaissement Mobile Money est refusé — comme côté web — mais le message dit **où** le renseigner au lieu d'imposer un numéro que personne n'a saisi. Le jour où plusieurs lignes existeront, le bandeau redeviendra un sélecteur.

### 4. Visite guidée — 42 étapes sur 21 écrans

`common.js` §16 décrit un moteur générique : chaque page définit `window.TOUR_STEPS`, le bouton d'aide flottant appelle `startTourGuide()`, et — c'est la seule ligne du prototype qui énonce d'elle-même la règle « zéro fonctionnalité décorative » — *« si aucun scénario n'est défini pour la page courante, un message honnête est affiché plutôt que de simuler un tour vide »*.

Le moteur est porté intégralement : voile noir à 60 %, anneau doré de 4 px sur la cible, carte positionnée sous l'élément ou au-dessus s'il déborde, compteur « Étape n / N », « Précédent » masqué mais conservant sa place à la première étape, « Terminer » à la dernière.

`document.querySelector('#kpi-panel')` n'ayant pas d'équivalent dans un arbre de widgets, une étape désigne sa cible par un **nom** et l'écran l'attache via `CibleTour` — ou, plus simplement, via le paramètre `cibleTour` porté par `CarteSection`, `AppButton` et `BarreOnglets`. Conséquence identique au web : les étapes dont la cible n'est pas affichée sont **filtrées**, jamais bloquantes.

**Les 45 étapes du prototype donnent 42 étapes portées.** Deux corrections :

1. **Les 3 étapes « Administrer une Dose »** (pages soins) visent `#administrer-dose-form`, un identifiant qui n'existe dans **aucun** des 31 fichiers. `startTourGuide()` les filtre déjà silencieusement côté web. Leur texte promet un stock vétérinaire décrémenté, un reçu imprimable et un blocage sur rupture : trois comportements qu'aucun écran n'implémente. Les porter reviendrait à promettre une fonctionnalité inexistante.
2. **L'étape « Mode de Règlement »** de `ventes.html` présente « Espèces, Mobile Money, ou Avance » comme trois modes. Depuis l'arbitrage, ce sont deux choix distincts : la phrase est réécrite, car la recopier apprendrait à la Gérante quelque chose de faux sur son propre logiciel.

**Deux cibles restaient sans point d'accroche**, faute d'écran correspondant. `#btn-view-weekly` en a une depuis : la **Vue Hebdomadaire** est implémentée (Doc F3, §ajouté). Reste `#day-prophy-multilist` — la prophylaxie injectée dans la fiche journalière — bloquée par la date de mise en bande absente du modèle. C'est un manque de notre côté, pas un défaut du prototype ; il est recensé ici pour ne pas être oublié.

### État de vérification

| Contrôle | Résultat |
|---|---|
| `flutter analyze` | **0 problème** |
| `flutter test` | **467 tests, 467 réussis** (34 nouveaux : 12 prophylaxie, 10 ligne Mobile Money, 12 visite guidée) |
| `flutter build windows --debug` | compilé, application relancée |
| Migration **v15 → v16** | colonne `ligneMobileMoney` ajoutée à `VENTES`, ventes antérieures à NULL |
