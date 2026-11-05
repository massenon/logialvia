# F2 — Module : Pilotage (Dashboards)

Écrans concernés : `dashboard.html` → `dashboard_screen.dart`, `elevage-dashboard.html` → `elevage_dashboard_screen.dart`.

**⚠️ Document reconstruit après implémentation réelle et lecture ligne par ligne des 2 fichiers HTML source.** La version précédente décrivait 4 KPI et 4 sections pour le Dashboard Principal ; le HTML réel en compte **8 KPI et 7 sections**. Les écarts sont signalés section par section.

---

## Écran 1 — Dashboard Principal (`dashboard.html`)

### Structure réelle (ordre strict — ⚠️ corrigé, 7 sections)

```
1. En-tete de bienvenue + 2 actions rapides
2. Filtre de periode + selecteur d'etat/rapport
3. Bandeau de 8 KPI (grid-cols-2 xl:grid-cols-4)
4. Courbe CA vs Depenses (lg:col-span-8) + Alertes Critiques (lg:col-span-4)
5. Cartes de recensement : Goliaths, Pintades, Couveuse (md:grid-cols-3)
6. Statistiques de Ventes + Transactions Recentes (lg:grid-cols-2)
7. Activites du Jour + Meilleures Ventes du Mois (lg:grid-cols-2)
```

**Correction n°1 — la grille KPI est `xl:grid-cols-4`, pas `md:grid-cols-4`.** Doc E7 §2 annonçait un basculement à 768 px ; `dashboard.html` l.134 utilise `grid-cols-2 xl:grid-cols-4`, soit un basculement à **1280 px**. C'est le HTML qui fait foi. Avec 8 KPI, la disposition attendue sur desktop est donc **2 rangées de 4 colonnes**.

**Piège de traduction Tailwind → Flutter, rencontré et corrigé.** Un breakpoint Tailwind se déclenche sur une *media query* — la largeur de la **fenêtre** — pas sur la largeur du conteneur qui porte la classe. Une première implémentation lisait les contraintes d'un `LayoutBuilder`, qui valent ~1100 px sur une fenêtre de 1440 (288 px de barre latérale + marges) : la grille retombait à 2 colonnes et 4 rangées, là où le web en affiche 4 et 2.

> **Règle à appliquer à toute conversion de breakpoint** (`sm` 640 / `md` 768 / `lg` 1024 / `xl` 1280) : comparer `MediaQuery.sizeOf(context).width`, jamais `constraints.maxWidth`. Les contraintes du conteneur ne servent qu'à **dimensionner** les éléments une fois le nombre de colonnes décidé. Ce point est à répercuter dans Doc E8 (Responsive) et vaut pour les 26 écrans restants.

### 1. En-tête
- `Bienvenue, <nom de l'utilisatrice connectée> 👋` (20 px, bold, navy)
- `Rapport généré le JJ/MM/AAAA à HH:MM · ALLMANY ET COMPAGNIE`
- Bouton primaire pilule « Enregistrer une Vente » → `/ventes`
- Bouton secondaire pilule « Dashboard Élevage » → `/elevage/dashboard`

### 2. Filtre de période + export

Deux champs date (`du` … `au`) qui filtrent réellement les données de l'écran, puis un `<select>` de 6 états et un bouton PDF.

**ECART_DELIBERE sur le sélecteur d'états** : `exportReport()` (dashboard.html l.385-400) ne produit **aucun PDF** — il affiche un toast puis redirige vers l'écran correspondant. Les 6 cibles sont des écrans non encore implémentés. Le bloc est donc réduit au filtre de période, pleinement fonctionnel. `TODO(dette)` posé dans le code.

### 3. Les 8 KPI (⚠️ corrigé — 4 étaient documentés, 8 existent)

| # | KPI | Accent (bordure gauche) | Icône | Source réelle | État aujourd'hui |
|---|---|---|---|---|---|
| 1 | Chiffre d'Affaires | `brand-navy` | `trending_up` | `SUM(LIGNES_VENTE.qte × pu)` des ventes non annulées de la période, ventilé Avicole / Commerce Annexe via `PRODUITS_VENDABLES.cat` | ✅ calculé |
| 2 | Trésorerie | `info-blue` | `account_balance_wallet` | Solde du compte 531 (Doc F6) | ⛔ module Comptabilité absent |
| 3 | Dépenses | `brand-gold` | `shopping_cart` | Achats (Doc F5) + dépenses saisies (Doc F6) | ⛔ modules absents |
| 4 | Résultat Net | `success-deep` | `savings` | CA − Dépenses | ⛔ dépend du n°3 |
| 5 | Soldes Restant Dus | `error-deep` | `request_quote` | `SUM(total − paye)` des ventes en statut `Avance` | ✅ calculé |
| 6 | Stock Critique | `error-deep` | `warning` | `COUNT(INTRANTS WHERE stock ≤ threshold)` | ✅ calculé |
| 7 | Effectif Cheptel | `brand-navy` | `pets` | Somme des `effectif` du dernier jour saisi de chaque filière **active** | ✅ calculé |
| 8 | Cycles Couveuse en Cours | `brand-gold` | `egg` | `COUNT(CYCLE_COUVEUSE WHERE statut='En Incubation')` | ✅ calculé |

**Règle appliquée aux KPI non calculables** (n°2, 3, 4) : la carte reste **toujours affichée** (Doc E7 §1), mais sa valeur est `—` et sa ligne de détail dit explicitement *« Disponible avec le module Comptabilité »*. Sa bande d'accent passe en gris neutre. Afficher « 0 FCFA » se lirait comme un vrai zéro métier — c'est-à-dire une information fausse.

**Vérification par test automatisé — le KPI n°6 vaut réellement 1.** Le seed transcrit `DEFAULT_INTRANTS` de `logialvia-store.js` : le Maïs y a 18 kg pour un seuil de 25, et c'est le seul intrant sous son seuil. La carte affiche donc « 1 intrant — Maïs sous le seuil d'alerte », identique à `dashboard.html` l.162-163, **par requête SQL sur les données seedées et non par recopie du chiffre du HTML**.

### 4. Courbe + Alertes

- **Courbe « CA vs Dépenses — 6 derniers mois »** : CA en `brand-navy` plein, Dépenses en `error-deep` pointillé `5,4`. Le prototype trace un `<svg>` **statique** (points écrits en dur) ; l'implémentation Flutter utilise `fl_chart` sur les données réelles (Doc E7 §5).
- **Panneau « Alertes Critiques »** : intrants et produits sous seuil, éclosion imminente (J+21 à moins de 3 jours), soldes restant dus, soins en retard. Chaque alerte est cliquable vers l'écran concerné — jamais un lien mort (Doc E3 §5).

**Point de conception** : le prototype alimente séparément la cloche de notifications et ce panneau, avec deux listes écrites en dur qui peuvent diverger. L'implémentation les fait dériver d'une **source unique** (`AlertesViewModel`), conformément à Strict Avoid §12.

### 5. Cartes de recensement

Une carte par filière active + une carte Couveuse. Chaque carte est cliquable vers la fiche correspondante.

**Structure réelle des catégories d'élevage — ⚠️ corrige Doc F3.** `fiche-goliaths.html` (l.121-125, l.465-487) montre que les 3 catégories sont **Poussin / Goliathau (Immature) / Mature (Éligible Vente)**, et non « Jeune / Commercialisée / Adulte » comme l'écrit Doc F3 §Spécificités. La carte affiche donc :
- Effectif = `FICHE_JOURNEE.effectif`
- Matures = `effCat3Day`
- « Goliathaux » / « Pintadaux » = `effCat2Day`
- Mortalité = mortalité du mois ÷ effectif de début de mois × 100 (Doc F3 §1)

**Taux d'éclosion moyen quand aucune éclosion n'existe** : affiché `—`, jamais `0 %`. Une moyenne calculée sur zéro échantillon n'existe pas ; elle ne vaut pas zéro.

### 6. Statistiques de Ventes + Transactions Récentes

- Deux mini-statistiques (Revenu semaine / Dépenses semaine) puis un histogramme des 6 derniers jours.
- **Transactions Récentes : 3 onglets** — Vente, Achat, Dépenses. Seul l'onglet Vente a une source de données ; les deux autres affichent un état explicite (« Le module Achats & Commandes n'est pas encore disponible »), jamais des lignes inventées.

### 7. Activités du Jour + Meilleures Ventes du Mois

**Décision tranchée sur le fil d'activité** — Doc E7 §6 et l'ancienne version de ce document signalaient qu'une table `JournalActivite` manquait au modèle D1 et marquaient le point « à trancher avant implémentation ».

**Tranché : le fil d'activité s'appuie sur `AUDIT_LOGS`** (Doc D1, Doc I3 §6), qui porte déjà horodatage, utilisateur, action et entité concernée. Créer une seconde table dédiée à l'affichage imposerait une double écriture à chaque action et deux sources de vérité à garder cohérentes (Strict Avoid §12). La liste des actions journalisées de Doc D1 devra s'élargir au fil des modules.

Le tableau « Meilleures Ventes du Mois » agrège `LIGNES_VENTE` par produit, trié par CA décroissant, colonnes Produit / Qté / CA / Activité, avec zébrage.

---

## Écran 2 — Dashboard Élevage (`elevage-dashboard.html`)

### Structure réelle (⚠️ corrigée — 3 sections documentées, 4 réelles)

```
1. En-tete + bouton Exporter PDF
2. Cartes par filiere (md:grid-cols-3), avec cartes d'apercu pour les
   filieres non activees
3. Graphique GMQ + Rappels Veterinaires a Venir (lg:grid-cols-2)
4. Alertes Sanitaires du Jour + Bilan Economique Elevage (lg:grid-cols-2)
```

**Correction n°2 — le mécanisme des filières inactives était absent du document.** Pour chacune des 3 filières activables, `elevage-dashboard.html` contient **deux** cartes :
- la carte réelle (`data-module-full-card`), masquée tant que le module est inactif ;
- une **carte d'aperçu** (`data-module-preview`) — fond `surface-zebra`, bordure en tirets, cadenas, texte *« Filière X disponible — non activée pour le moment. »* et lien *« Activer depuis Paramètres → »*.

L'une remplace exactement l'autre selon `MODULES_ACTIFS` (Doc I2). Les 3 filières étant désactivées par défaut, ce sont les cartes d'aperçu qui s'affichent au premier lancement.

### Graphique GMQ — ⚠️ donnée non modélisable en l'état

Le prototype trace un GMQ (Gain Moyen Quotidien) par espèce sur 4 semaines. Or :
- Doc F3 §2 liste bien un champ « Poids Général » dans le formulaire de saisie journalière ;
- **mais Doc D1 ne prévoit aucune colonne de poids dans `FICHE_JOURNEE`** — la donnée n'a nulle part où être stockée ;
- le graphique du prototype est un `<svg>` à points écrits en dur : il ne prouve pas que la donnée existe.

La section est conservée avec un état explicite décrivant l'écart, plutôt que remplie d'une courbe inventée. **Point à trancher avant l'implémentation de Doc F3.**

### Bilan Économique Élevage

`elevage-dashboard.html` l.264 donne la formule : *« Revenus = ventes Avicole du Dashboard principal. Coûts = intrants provende + vétérinaire de la période. »*
- Revenus Élevage : ✅ calculé (CA d'activité Avicole du mois)
- Coûts Élevage : ⛔ dépend du module Achats (Doc F5)
- Marge Nette : ⛔ non calculable tant que les coûts manquent — affichée `—`, jamais réduite au seul revenu

### Bouton « Exporter PDF »

ECART_DELIBERE : appelle `generateOfficialPDF()` côté web. La génération PDF relève de Doc E9 et de dépendances (`printing`, `pdf`) non encore ajoutées. Le bouton est retiré plutôt que rendu inerte. `TODO(dette)` posé.

---

## AppShell — coquille commune aux 28 écrans internes (Doc E3 §1)

Livré avec ce module car les 2 dashboards en sont les premiers consommateurs.

### Barre latérale — 8 groupes réels (transcription de `sidebar.js`)

| Groupe | `data-role-group` | Entrées |
|---|---|---|
| PILOTAGE | admin, animalier, caissier | Tableau de Bord |
| ÉLEVAGE & COUVEUSE | admin, animalier | Cycle Couveuse, Fiche Goliaths, Fiche Pintades, Fiche Poissons-Chats*, Fiche Lapins*, Fiche Poulets/Pondeuses*, Dashboard Élevage, Paramètres Élevage, Soins & Calendrier |
| VENTES & CLIENTS | admin, caissier | Ventes, Clients et Créances |
| ACHATS & FOURNISSEURS | admin | Achats & Commandes, Fournisseurs, Saisie Dépenses |
| STOCKS & CATALOGUE | admin | Gestion Stocks, Catalogue & Seuils |
| COMPTABILITÉ | admin | Comptabilité, Grand Livre, Balance Générale, États Financiers |
| PARAMÈTRES | admin | Paramètres Général |
| ÉDITIONS | admin | Rapports & États |

\* masquées tant que leur module n'est pas actif (Doc I2 §3).

**Divergence relevée avec Doc E3 §2** : la barre latérale réelle pointe vers `grand-livre.html`, `balance-generale.html` et `etats-financiers.html`, alors que l'arborescence de Doc E3 nommait `/comptabilite/journal`, `/plan`, `/analytique`, `/cloture`, `/bilan`. Les routes suivent la barre latérale réelle ; les écrans de Doc E3 absents du menu restent atteignables par navigation contextuelle, comme côté web.

### Barre du haut

Bouton de repli de la barre latérale, fil d'Ariane, recherche globale, cloche de notifications, menu profil.

**Éléments volontairement non reproduits, et pourquoi** :
- Badge « 3 en attente » avec icône `sync` animée : aucune synchronisation n'existe (hors-ligne par conception, Doc B1 §7) et le nombre est écrit en dur. Ce serait un indicateur mensonger.
- Les 2 boutons dont le `title` commence par *« Démonstration — forcer l'affichage… »* : outils de test du prototype.
- Sélecteur de rôle RBAC : outil d'audit, même statut (Doc I1 §1).

**La recherche globale, elle, est réelle et reproduite** : `common.js` §5-BIS implémente un vrai moteur (`GLOBAL_SEARCH_INDEX`, raccourci Ctrl+K, anti-rebond 150 ms). L'index Flutter est dérivé de la table de navigation, **filtré par rôle et par module actif**, pour qu'aucun résultat ne mène à un écran interdit ou désactivé.

### Routes non encore implémentées

Les 21 entrées de la barre latérale sont toutes enregistrées. Celles dont le module n'existe pas encore affichent un écran d'attente nommant le document de spécification correspondant — **jamais un lien mort** (Doc E3 §5), et sans aucune maquette ni donnée simulée.

---

## Cohérence Transversale — Effectifs Réels Établis

Pour toute donnée de démonstration/seed nécessaire à ces dashboards avant saisie réelle, respecter les valeurs déjà établies ailleurs dans le système (Doc D1 §seed, Doc B1) : Goliath mature = 31 sujets, Pintade mature = 28 sujets. Ne jamais introduire une valeur de démonstration divergente pour ces deux filières.

**Vérifié à l'implémentation** : ces 2 valeurs figurent bien dans `DEFAULT_STOCK` de `logialvia-store.js` (`stock: 31` et `stock: 28`) et sont couvertes par un test automatisé.

**En revanche, `DEFAULT_VENTES` n'existe pas.** Doc D1 §3 le mentionne dans son `_seedInitialData()`, mais vérification faite dans `logialvia-store.js` : `getVentes()` retourne `[]` par défaut, l'historique des ventes démarre vide dans le prototype. Aucune vente de démonstration n'est donc créée — elles seraient une invention (Strict Avoid §10).

### Popup « Prophylaxie du Jour » — ajoutée aux deux tableaux de bord

`assets/js/prophylaxie-popup.js` l.4 : « Portée : `dashboard.html` et `elevage-dashboard.html` **uniquement** ». La popup s'ouvre au chargement de ces deux écrans quand un traitement reste dû, et se referme quand il n'en reste plus.

Elle liste les soins de `SOINS_CALENDRIER` dus aujourd'hui **ou en retard**, et « Marquer fait » les passe réellement à « Effectué » en base — le prototype, lui, cochait la ligne dans `localStorage` en laissant le soin « Planifié » dans le registre. Deux vérités pour un même traitement.

Le report vaut pour la **session** : côté web `initProphylaxieReminder()` s'exécute au `DOMContentLoaded` de chaque page, donc revenir au tableau de bord rouvre la popup à l'identique. Dans une application à navigation instantanée, un rappel qu'on ne peut pas écarter cesse d'être un rappel.

Le ViewModel des soins n'est pas injecté dans le tableau de bord : la popup est le seul élément qui en dépende, et l'injecter globalement ferait relire `SOINS_CALENDRIER` à chaque navigation. Il est construit à l'ouverture, utilisé, puis libéré.

Détail complet et arbitrage du calendrier de prophylaxie : **Doc K2 §B.1**.
