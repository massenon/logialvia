# 46b — Synchronisation de l'élevage : couveuse et mirages (tranche P7b)

> **Statut au 09/11/2026.** Tranche verticale « poste → serveur → web » des deux tables de la couveuse :
> `cycle_couveuse` (les lots d'incubation et leurs mirages) et `machines_incubateur` (les incubateurs).
> Complète `46_CONTRAT_SYNCHRONISATION.md` (§2.2, §2.3) ; recette suivie : `45_` §8. Le Dart est la source, le
> Laravel s'y conforme. **Schéma du poste : 37 → 39** (le 38 est réservé à une autre tranche).
> Les points qui engagent un choix métier sont réunis dans **« Décisions à valider par le client »** (§3).

## 1. Ce qui a été livré

| Couche | Livrable |
|---|---|
| **Poste** | Schéma v39 : les deux tables passent en UUID (DV-19) avec `sync_status`, `sync_motif`, `updated_at` ; migration idempotente `_couveuseEnUuid` ; `TableCyclesCouveusePoste` et `TableMachinesIncubateurPoste` ; codes de lot préfixés par le poste ; câblage dans `main.dart` ; faux serveur étendu. |
| **Serveur** | Migration `2026_11_09_141000_create_machines_incubateur_cycle_couveuse_tables.php`, modèles `CycleCouveuse` et `MachineIncubateur`, `CyclesCouveuseTable` et `MachinesIncubateurTable` (déclarées dans `sync.tables`, incubateurs AVANT lots), helpers `ligneMachine` / `ligneCycle` dans `PostesDeTest`. |
| **Web** | `/elevage/couveuse` (composant `Couveuse`) et `/elevage/mirages` (composant `StatistiquesMirages`), calculs portés du Dart dans `App\Support\SuiviIncubation`. |

## 2. Règles de synchronisation choisies

### 2.1 Nature des deux tables

| Table | Nature | Clé | Règle |
|---|---|---|---|
| `cycle_couveuse` | **fait**, dernier écrivain gagne | UUID du lot | Les mirages ne sont pas une table : ce sont deux colonnes du lot (`oeufs_blancs_j7` au J+7, `oeufs_gates_j14` au J+14), `null` = « pas encore miré » (jamais confondu avec « mirage fait, zéro œuf clair »). **Saisir un mirage est une modification du lot**, avec son nouvel instant de saisie. |
| `machines_incubateur` | **fait**, dernier écrivain gagne (voir D1) | UUID **dérivé du code** (voir D2) | Création au poste ou au web ; aucune modification ni suppression n'existe au poste. |

Colonnes de synchronisation communes (`46_` §1) : `id`, `sync_status` (`pending` · `synced` · `conflict`),
`sync_motif`, `updated_at` (instant de **saisie**, UTC, microsecondes). `device_id` n'est pas stocké au poste (le
serveur le déduit du jeton). Au serveur : `serveur_modifie_le` (curseur de tirage) et `supprime_le` (pierre tombale).

### 2.2 Format des échanges

`tables.machines_incubateur = [ {id, code, libelle, capacite_oeufs, active, updated_at} ]` ;
`tables.cycle_couveuse = [ {id, code_incubation, espece, date_incubation, oeufs_couves, poussins_nes, oeufs_perdus,
statut, machine_id, oeufs_blancs_j7, oeufs_gates_j14, lot_parent_id, supprime_le, updated_at} ]`.
`date_incubation` est une **date civile** `AAAA-MM-JJ`, sans fuseau (un lot chargé à minuit local ne recule jamais
d'un jour). Ordre d'un envoi : **incubateurs avant lots**, dans cet ordre dans `sync.tables`.
La colonne `bande_reproducteurs` (jamais saisie par aucun écran) ne voyage pas.

### 2.3 Absorbeur strict (poste) et validation (serveur)

Les deux côtés appliquent **les mêmes règles** ; une ligne incohérente est refusée avec son motif (serveur) ou
refusée et comptée (poste), jamais lissée :

- identifiant UUID ; code non vide (40 caractères au plus) ; espèce `goliath` ou `pintade` ; statut `En Incubation`,
  `Éclosion Effectuée` ou `Remplacé` ; date de chargement valide ; entiers **stricts** (un texte « 200 » ou un
  décimal est refusé) ;
- œufs chargés ≥ 1 ; quantités ≥ 0 ; **mirages ≤ œufs chargés** ; **éclos + perdus ≤ œufs retenus** après mirages
  (mêmes bornes que l'écran du poste) ; un lot ne se remplace pas lui-même ;
- l'**incubateur doit être connu** (il arrive avant les lots) ; le **lot d'origine, lui, peut arriver après** son
  remplaçant (ordre libre des lignes d'une page : aucune clé étrangère) ;
- le **code d'un lot ne change jamais** (c'est son numéro officiel, porté par le journal d'élevage et les rapports) ;
- un code déjà porté par un **autre** lot est signalé, jamais écrasé : refus au serveur
  (« Ce code est déjà utilisé par un autre lot. »), ligne refusée et comptée au poste ; un autre UUID qui porte le
  code d'un incubateur existant est refusé (« Un incubateur porte déjà le code INC-01. », casse ignorée).

Unicité du code de lot (DV-21 étendu, voir D3) : `C-P2-2026-001` est **unique pour tous** ; `C-2026-001` (poste jamais
appairé) est **unique par poste** ; les lots supprimés ne retiennent plus leur code.

### 2.4 Dernier écrivain gagne, à l'instant de saisie

Même règle que `46_` §6 et §8, des deux côtés : le serveur n'applique une ligne que si son `updated_at` est
**strictement** plus récent ; un rejeu est accepté sans rien changer (et ne touche pas l'instant de réception) ; le
poste ne remplace une saisie locale non envoyée que par une version **strictement** plus récente du serveur, et le dit.
L'accusé ne marque `synced` que si la ligne n'a pas bougé depuis l'envoi (une saisie faite pendant que le réseau
répondait repart au prochain cycle).

### 2.5 Suppression d'un lot : la pierre tombale

Au poste, supprimer un lot le range en **corbeille** (la ligne quitte la table). Pour que la suppression se propage :

- avant de ranger le lot, le dépôt **date** sa suppression (`updated_at` = maintenant, `sync_status` = `pending`) : cet
  instant est porté par l'instantané de la corbeille ; ses sous-lots, qui deviennent des lots racines, sont eux aussi
  modifiés (donc renvoyés) ;
- `TableCyclesCouveusePoste.aEnvoyer` envoie, en plus des lots, **une ligne complète avec `supprime_le`** pour chaque
  instantané de corbeille en attente ; l'accusé réécrit l'instantané (`synced`) ;
- le serveur ne supprime jamais physiquement : il pose `supprime_le` et redistribue ; une pierre tombale ne demande ni
  incubateur connu ni code libre (le lot n'existe plus) ;
- **un lot supprimé n'est jamais ressuscité par l'écho du serveur** : le tirage rend au poste son propre lot avant que
  la pierre tombale soit partie ; l'absorbeur l'ignore tant que la corbeille porte une suppression au moins aussi
  récente (défaut trouvé en écrivant les tests, voir §5) ;
- une version **strictement plus récente** (un autre poste a modifié le lot après la suppression) le fait revenir ; la
  pierre tombale devient caduque ;
- **restaurer** un lot depuis la corbeille lève la pierre tombale : il repart, daté de maintenant, et revient partout.

### 2.6 Règle d'or : absorber le fait d'un autre poste n'a AUCUN effet de bord

Un lot ou un incubateur reçu est de l'historique. Aucun poussin n'entre dans une fiche d'élevage (**`fiche_journee`
n'est jamais touchée**), aucun stock, aucune écriture comptable, aucun événement de domaine, aucune entrée de corbeille.
Testé : aucune autre table ne bouge, aucun flux de modification n'est émis, et le lot reçu ne repart pas.

### 2.7 Remise à zéro

Le serveur efface lots et incubateurs (faits). Le poste purge **les lots avant leurs incubateurs** (ordre inverse des
dépendances, déjà garanti par le moteur) et compte les saisies non envoyées perdues ; **la corbeille et les fiches
d'élevage ne sont pas touchées**. Aucune clé étrangère au serveur, donc la remise à zéro n'est pas bloquée par l'ordre
de `sync.tables`.

### 2.8 Droits (matrice de `config/logialvia.php`)

Lecture : `view-elevage`. Écriture (y compris la pierre tombale) : `manage-elevage`. Administrateur et agent d'élevage
lisent et écrivent ; **caissier et comptable ne reçoivent pas la couveuse** et leurs envois sont refusés avec le motif
« Droit insuffisant pour écrire dans « cycle_couveuse ». ».

## 3. Décisions à valider par le client

Chaque choix ci-dessous a été fait par prudence, sans bloquer. **Aucun n'est irréversible**, mais plusieurs changent ce
que voit la Gérante.

| Id | Décision prise | Pourquoi / option écartée | Ce qu'il faut confirmer |
|---|---|---|---|
| **D1** | Les **incubateurs sont des faits** (dernier écrivain gagne), pas un référentiel « le serveur gagne » avec demandes comme le range `46_` §2.2. | Seul le poste (et maintenant le web) sait en déclarer ; le serveur n'a aucune règle propre à leur appliquer. Passer par `POST /sync/demandes` aurait touché le code partagé des demandes de référentiel et imposé un nouveau type de demande. | Que le web et chaque poste puissent déclarer un incubateur directement. |
| **D2** | **Même code = même incubateur.** L'UUID d'un incubateur est dérivé de son code (`machine:inc-01`, insensible à la casse), identique au poste et au web. Deux postes qui déclarent « INC-01 » ne créent pas deux machines ; **deux UUID distincts portant le même code sont refusés, jamais fusionnés** (le code `inc-01` et `INC-01` aux casses différentes se départagent à la migration). | Sans cela, deux postes qui créent « INC-01 » chacun de leur côté se bloqueraient mutuellement (le poste n'a aucun écran pour renommer ni supprimer un incubateur). | Que le code identifie l'incubateur physique (deux couveuses ne doivent jamais porter le même code). |
| **D3** | **Les codes de lot portent le code du poste** : `C-P2-2026-001`, comme les ventes et achats (DV-21 étendu aux lots) ; un poste jamais appairé garde `C-2026-001`. Les codes existants restent valides tels quels. Le **web numérote `C-WEB-2026-001`** (il n'a pas de code de poste ; ce préfixe ne peut jamais coïncider avec celui d'un poste). | Deux postes auraient sinon tous deux produit `C-2026-001`. Le code d'un lot est son numéro officiel : il ne change jamais. | Le format `C-WEB-…` pour les lots créés depuis le web ; et que deux postes **non appairés** qui ont chacun un `C-2026-001` ne peuvent pas se les échanger (le second est refusé et compté, voir §4). |
| **D4** | **La suppression d'un lot se propage** (pierre tombale) et demande `manage-elevage` (pas `archive-elevage` : l'écran du poste n'a pas de droit d'archivage distinct pour les lots). | Sans propagation, un lot supprimé au poste serait ressuscité par un tirage complet (« Renvoyer vers ce poste »). | Que supprimer un lot au poste le fasse disparaître du web et des autres postes. |
| **D5** | **Dernier écrivain gagne sur la ligne entière du lot**, pas champ à champ. Si deux postes saisissent, hors ligne l'un de l'autre, le mirage 1 sur l'un et le mirage 2 sur l'autre, **le plus récent écrase l'autre** : le mirage perdu réapparaît « À saisir » et se re-saisit. | Une fusion champ à champ aurait demandé un instant par colonne (schéma plus lourd) ; en usage normal le poste tire avant d'envoyer et voit donc le mirage de l'autre. | Si ce risque (rare : deux saisies hors ligne du même lot) est acceptable, ou s'il faut un instant par mirage. |
| **D6** | **Un lot éclos ou remplacé n'est ni modifiable ni supprimable** : règle de l'écran (poste et web), **pas du serveur**. Le serveur accepte toute ligne valide, y compris une correction d'un lot éclos venue d'un poste ancien. | Le Dart tient cette règle dans le view-model, pas dans la base ; la répliquer au serveur aurait refusé des lots déjà éclos et valides. | Si le serveur doit aussi interdire la modification d'un lot éclos. |
| **D7** | **Le web saisit** lots, mirages, éclosions (avec remplacement), suppressions et incubateurs, par `absorber` (même validation que pour un poste). | La recette (`45_` §8) fait écrire le web par le chemin du poste ; la Gérante peut ainsi saisir un mirage depuis son téléphone. | Que la couveuse soit saisissable au web, pas seulement consultable. |
| **D8** | **Les naissances ne sont écrites nulle part par la couveuse.** Dans le poste actuel, enregistrer une éclosion ne touche pas `fiche_journee` ; la synchronisation non plus. Si l'éclosion doit un jour alimenter les naissances d'une fiche d'élevage, ce sera par les **faits de la fiche** (autre tranche), jamais en rejouant le lot. | Consigne de la tranche + règle d'or (§2.6). | Comment les poussins nés entrent dans les effectifs (saisie manuelle de la fiche aujourd'hui). |
| **D9** | **Un lot dont l'instant de saisie est inconnu** (lots d'avant la migration) est daté **de sa date de chargement**, pas de l'instant de la migration ; un incubateur d'avant la migration est daté de la migration. | L'instant de la migration ferait gagner un vieux lot contre une correction faite ailleurs ; un incubateur n'est pas modifiable au poste, il ne peut contredire personne. | — (technique) |
| **D10** | **Le web date sa saisie au plus tôt une microseconde après la dernière saisie connue du lot.** | Un poste dont l'horloge avance aurait sinon fait ignorer la saisie du web, sans le dire (dernier écrivain gagne exige un instant strictement postérieur). | — (technique) |
| **D11** | **« Non précisé » ne retire pas l'incubateur d'un lot en modification** (comportement du poste, reproduit au web). | Le Dart fait `machineId ?? cycle.machineId` : choisir « Non précisé » en modifiant conserve l'ancien incubateur. | Si l'on veut pouvoir retirer l'incubateur d'un lot (corriger le Dart et le web ensemble). |

## 4. Écarts avec le Dart et limites

### Écarts déclarés du web (`/elevage/couveuse`, `/elevage/mirages`)

- **Pas d'export PDF** (« Exporter ») : au poste.
- **Pas de fenêtre « lignée des remplacements »** (TER d'une lignée) : le lot d'origine reste visible (« ↳ remplace
  C-… »).
- **Numérotation propre au web** (`C-WEB-AAAA-NNN`, D3).
- **Date « Situation au »** : champ de date sur le Cycle Couveuse (âge, alertes, TER à cette date) ; sur les Statistiques
  des Mirages, les mirages manquants se jugent à **aujourd'hui** (le poste y applique la date de l'écran Cycle
  Couveuse, qui n'est pas partagée entre deux pages web).
- **Pas de cibles de visite guidée** ni de toasts : le message de retour s'affiche en bandeau.
- **Pas d'icônes Material Symbols** (police non embarquée).
- Les **règles de l'écran** (lot clos, mirage au-delà des œufs, messages d'erreur) reprennent mot pour mot celles du
  view-model du poste ; pour les autres refus, c'est le message du serveur qui s'affiche.

### Limites connues

1. **Corbeille vidée avant l'envoi** : la pierre tombale d'un lot supprimé puis purgé définitivement de la corbeille
   avant d'avoir été envoyée est perdue (le lot reste au serveur). Testé et documenté ; atténué par le fait que la
   synchronisation part après chaque geste (3 s), et à la fermeture.
2. **Deux postes non appairés** (codes `C-2026-001`) : le lot de l'un, reçu par l'autre, est **refusé et compté** si
   un lot local porte déjà ce code (contrainte `UNIQUE(code_incubation)` du poste) ; il reste au serveur et au web.
   Appairer les postes (code de poste) supprime la collision pour les lots à venir.
3. **Restaurer un lot dont le code a été réutilisé** échoue comme avant (message « existe déjà » de la corbeille).
4. **Aucun écran n'existe pour modifier ou supprimer un incubateur** (poste et web) : la table n'envoie donc que des
   créations ; le serveur sait pourtant recevoir une modification (dernier écrivain gagne).
5. **La remise à zéro du serveur** vide ses tables dans l'ordre de `sync.tables` : les deux tables de la couveuse n'ont
   volontairement pas de clé étrangère. (Observation hors tranche : `fournisseurs` précède `achats` dans cet ordre
   alors que `achats` y a une clé étrangère ; à vérifier sur MySQL, SQLite ne l'impose pas en test.)
6. **Pas de suppression propagée d'un incubateur**, pas de suppression d'un lot éclos (règles de l'écran).

## 5. Défauts trouvés en chemin

- **Résurrection d'un lot supprimé** : l'écho du tirage (son propre lot, modifié après le curseur) revenait avant que la
  pierre tombale soit partie et recréait le lot supprimé. Corrigé dans l'absorbeur (§2.5), deux tests dédiés.
- **Blade** : mélanger `@php(...)` en ligne et `@php … @endphp` dans une même vue fait avaler tout le contenu situé
  entre le premier `@php(` et le premier `@endphp` ; les calculs en ligne sont donc écrits en `<?php … ?>`.
- **Variable de vue homonyme d'une propriété publique Livewire** : la propriété (texte) masque la variable (date) ; la
  date de référence est passée à la vue sous le nom `jourRef`.

## 6. Vérifications

Chiffres au 09/11/2026 (suites entières vertes) : **poste** `flutter analyze` « No issues found! », 1458 tests
(+13 d'intégration ignorés) dont 8 de migration et 60 de synchronisation de la couveuse ; **serveur** 586 tests
(`php artisan test`), dont 53 pour cette synchronisation, 51 + 12 pour les deux écrans et 14 pour les calculs ;
`npm run build` réussi.

- **Poste** : migration sur une vraie base v37 (identifiants non consécutifs, jointures incubateur/lot d'origine,
  corbeille réécrite et restaurable, casse des codes, instants de saisie, rejouable) ; synchronisation (envoi, rejeu,
  accusé, saisie pendant l'envoi, numérotation, deux postes, règle du plus récent, absorbeur strict cas par cas,
  refus du serveur, suppression, hors ligne, remise à zéro, aucun effet de bord) ; **mutations** : chaque garde cassée
  fait rougir au moins un test (35 mutations : 24 sur les tables, le dépôt et l'archivage ; 11 sur la migration, dont
  la version du schéma — deux survivantes au premier passage ont donné un test de plus chacune).
- **Serveur** : push, pull, rejeu idempotent, refus avec motif français, droits par rôle, deux postes, remise à zéro,
  409 sur marque inconnue ; **25 mutations** vérifiées, toutes tuées.
- **Web** : accès par rôle, contenu (KPI, parc, tableau, alertes, filtres, cartes), chaque règle de validation avec son
  message, écriture en base (device web, curseur de tirage avancé), droits de chaque méthode, lecture seule des
  statistiques ; calculs portés du Dart testés contre les valeurs des tests du poste ; **41 mutations** vérifiées (deux survivantes au
  premier passage : la confirmation de suppression forcée sur un lot éclos, et la re-déclaration d'un incubateur
  existant, qui serait sinon une modification silencieuse ; un test de plus chacune). Seule garde non couverte par
  mutation : la transaction de l'éclosion avec remplacement (défensive : le second refus est inatteignable depuis
  l'écran, car les entrées du sous-lot sont validées avant l'écriture).
