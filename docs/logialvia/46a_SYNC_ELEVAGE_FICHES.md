# 46a — Synchronisation de l'élevage : fiches journalières, compteurs de ventes du jour et bandes (tranche P7a)

> **Statut au 09/11/2026.** Complète `46_CONTRAT_SYNCHRONISATION.md` (§2.3) et `45_PLAN_APPAIRAGE_SYNCHRO_POSTE_WEB.md` (§6c à §8).
> Trois tables du poste (schéma **v37 → v38**), trois tables du serveur, huit écrans web. Les autres écrans d'élevage
> (couveuse, mirages, soins, paramètres élevage) sont d'autres tranches (`P7b`, `P7c`) et n'y sont pas traités.
> Le Dart est la source ; le Laravel s'y conforme. **Toute décision métier que cette tranche a dû prendre est listée au §6** :
> aucune n'a été validée par le client.

## 1. Vue d'ensemble

| Table | Nature | Identité (UUID) | Arbitrage | Droits serveur (lecture / écriture) |
|---|---|---|---|---|
| `fiche_journee` | fait mutable | **déterministe** de (filière, date) | dernier écrivain gagne, **ligne entière** | `view-elevage` / `manage-elevage` |
| `fiche_ventes_jour` | fait mutable, **une ligne par poste** | **déterministe** de (filière, date, poste) | dernier écrivain gagne, par ligne (un seul écrivain par ligne) | `view-elevage` ou `view-ventes` / `manage-ventes` ou `manage-elevage` |
| `bandes` | fait mutable | aléatoire (v4), saisie de l'utilisatrice | dernier écrivain gagne, `UNIQUE(filière, code)` | `view-elevage` / `manage-elevage` |

Ordre d'un cycle (liste `sync.tables`, après `mouvements_produit`) : `fiche_journee`, `fiche_ventes_jour`, `bandes`. Aucune de ces tables ne
dépend d'une autre ; la remise à zéro les purge dans l'ordre inverse comme toutes les autres. Aucun poste n'envoie jamais un effectif « réel »
de bande, ni un stock : voir §3.3.

## 2. Règles communes (rappel des règles d'or)

- **Absorber le fait d'un autre poste n'a AUCUN effet de bord local** : ni recalcul de la cascade des jours suivants, ni compteur de ventes, ni
  stock, ni événement. L'effet arrive par ses propres lignes.
- **Absorbeur strict** : une ligne incohérente est **refusée et comptée**, jamais lissée ni corrigée. Refus du serveur : la ligne devient
  `conflict` avec son motif français ; elle n'est pas renvoyée en boucle.
- **Instant de saisie** (`updated_at`, UTC, microsecondes) : seul l'instant où la saisie a eu lieu départage deux écritures, jamais l'instant d'envoi.
  Une saisie locale non envoyée n'est remplacée que par une version **strictement** plus récente du serveur.
- Les dates d'une fiche, d'un compteur et d'une bande sont des **dates civiles** `AAAA-MM-JJ`, sans fuseau (minuit local à Porto-Novo et à Paris désignent
  le même jour pour l'éleveur).
- Le curseur de tirage est `serveur_modifie_le` (instant de réception), comme pour toutes les tables de faits.

## 3. Règles par table

### 3.1 `fiche_journee` : convergence de deux postes

**Problème.** Une fiche est unique par (filière, date) (`UNIQUE(espece, date)`). Deux postes peuvent saisir le même jour, hors ligne.

**Règle choisie.** L'UUID de la fiche est **calculé** de (filière, date) (`uuidDeterministe('fiche_journee:<filière>|<AAAA-MM-JJ>')`, SHA-1 version 5,
même calcul en PHP : `App\Support\UuidDeterministe`). Deux postes écrivent donc la **même** ligne. La plus récente à l'instant de saisie l'emporte,
**en bloc** : la ligne entière du perdant disparaît, y compris ses champs facultatifs (pesée, observation…) ; jamais de mélange champ par champ.
Raison : `effectif` et les sous-effectifs sont **calculés** à partir de la veille ; mélanger deux saisies produirait un effectif qu'aucun des deux postes n'a calculé.

- Le serveur **recalcule l'UUID** et refuse une ligne dont l'identifiant n'est pas celui de sa clé (« L'identifiant de la fiche ne correspond pas à sa
  filière et à sa date. ») : c'est ce qui garantit la convergence.
- Le poste fait de même à l'absorption, et refuse une ligne qui porterait déjà (filière, date) sous un autre UUID (jamais écrasée).
- Valeurs validées : filière connue (8), date réelle `AAAA-MM-JJ` exacte, 13 entiers ≥ 0 obligatoires, 10 entiers facultatifs (`null` ou ≥ 0), deux booléens stricts.
  Serveur : entiers `integer:strict` (le texte « 5 » est refusé), booléens `boolean:strict`.
- **Ligne entière** côté serveur : une colonne facultative absente du lot est écrite à `null`, jamais conservée.
- **Pas de cascade à l'absorption.** La ligne arrive avec ses valeurs calculées ; les jours suivants arrivent par leurs propres lignes (le poste qui a saisi
  les a recalculés et envoyés). Voir les limites (§8).
- Le poste remet une fiche à envoyer **à chaque écriture** (saisie, cascade, report d'un décès d'infirmerie) avec un nouvel instant de saisie.

### 3.2 `fiche_ventes_jour` : un compteur cumulatif sans double comptage

**Problème.** Le compteur est alimenté par la caisse (`+qte` à la vente, `−qte` à l'annulation). Comme absorber une vente d'un autre poste n'a aucun effet local,
ce compteur doit voyager par ses propres faits. Une ligne unique par (filière, date) serait écrasée d'un poste à l'autre (ventes perdues) ou comptée deux fois.

**Règle choisie : une ligne par poste, sommée à la lecture.**

- Chaque poste ne tient et n'envoie que **son** compteur : `origine` vide en base locale ; UUID déterministe de (filière, date, **identifiant du poste**).
- Les compteurs des autres postes arrivent avec leur `origine` (le `device_id` servi par le serveur) et ne sont **jamais renvoyés**.
- `venteDuJour` (fiche d'un poste) et « Ventes (POS) » (fiche du web) = **somme** de toutes les lignes (filière, date).
- Le serveur recalcule l'UUID avec le `device_id` **du jeton qui envoie** : un poste ne peut pas écrire le compteur d'un autre, ni créer deux lignes pour lui-même
  (`UNIQUE(device_id, filière, date)`).
- **Mon propre compteur qui revient d'un tirage complet sur une base vide** (restauration, « renvoyer vers ce poste ») reprend `origine` vide : sinon il serait pris
  pour celui d'un autre poste et mes ventes suivantes ouvriraient une seconde ligne, comptée deux fois.
- `qte` : entier ≥ 0, **remplacé** (jamais additionné) à chaque envoi : un rejeu ou une ligne plus ancienne arrivée en retard ne double rien.
- Le web **n'écrit jamais** ce compteur (il ne vend pas) et l'affiche en lecture seule.

### 3.3 `bandes` : déclaration seulement

- Voyage : filière, code, date de mise en place, effectif mis en place (`effectif_initial`, **indicatif**), date de clôture, observations.
- **Ne voyage jamais, et n'est stocké nulle part** : un effectif « réel » de bande. La fiche journalière est tenue par filière, pas par bande ; l'effectif réel se recalcule des fiches.
  Ni le poste ni le serveur n'ont de colonne pour le porter (test de schéma des deux côtés) ; un champ `effectif` poussé par un poste n'est pas enregistré.
- **Code unique par filière.** Deux postes qui déclarent chacun « B2 » hors ligne créent deux bandes de UUID différents. La seconde reçue est **refusée**
  (« Ce code de bande est déjà utilisé pour cette filière. ») et, côté poste, la bande de l'autre poste est refusée à l'absorption et comptée : **rien n'est fusionné
  ni écrasé** (deux dates de mise en place ne se moyennent pas). La bande refusée reste au poste, en `conflict`. Voir la décision D4.
- Clôture antérieure à la mise en place : refusée (même règle que le formulaire du poste). Espaces autour du code : retirés.
- `soins_calendrier.bande_id` suit : la migration réécrit chaque lien vers le nouvel UUID de sa bande (hors périmètre de synchronisation, lot `P7c`).

## 4. Poste (schéma v38)

- **Migration `from < 38`**, idempotente (garde par type de colonne `id`, comme v31 à v36), sans perte de ligne, rejouable sans changer un UUID :
  - `fiche_journee` : `id` UUID v5 de (filière, date), `sync_status` (`pending`), `sync_motif`, `updated_at` = **le jour décrit par la fiche** (jamais l'instant de la migration, qui
    la ferait gagner contre une correction faite ailleurs) ; l'unicité (filière, date) est conservée. Deux bases migrées séparément donnent le **même** UUID au même (filière, date).
  - `fiche_ventes_jour` : `id` UUID v5 de (filière, date, identifiant du poste — créé par la migration s'il n'existe pas encore), `origine` vide, colonnes de synchro. L'unicité (filière, date)
    est remplacée par l'identité calculée (une ligne par poste).
  - `bandes` : `id` UUID v4, colonnes de synchro, `updated_at` = date de clôture, sinon de mise en place ; table de correspondance ancien entier → UUID le temps de la migration.
  - `soins_calendrier.bande_id` : colonne passée en texte, chaque soin garde sa bande ; un soin libre reste libre ; une bande inconnue donne `null` (le lien était déjà orphelin).
- Classes : `TableFichesJourneePoste`, `TableVentesJourPoste`, `TableBandesPoste` (`lib/elevage/data/sync/`), câblées dans `lib/main.dart`. Identifiants : `identifiants_elevage.dart`.
- Dépôts : `FicheElevageRepositoryDrift.enregistrerJour` (UUID déterministe, `pending`, instant de saisie), `BandesRepositoryDrift` (UUID v4, `pending`), `VentesRepositoryDrift._ajusterFicheVentesJour`
  (ne touche **que** mon compteur : `origine` vide).
- Types : `Bande.id` et `Soin.bandeId` passent d'`int` à `String`.

## 5. Serveur et web

- **Serveur** : migration `2026_11_09_140000_create_elevage_fiches_bandes_tables.php`, modèles `FicheJournee`, `FicheVentesJour`, `Bande`, tables `FichesJourneeTable`, `VentesJourTable`, `BandesTable`,
  helper `App\Support\UuidDeterministe` (même calcul que le poste, vecteurs communs testés), `App\Support\FilieresElevage` (configuration des 8 filières, **comparée au Dart** par `ConformiteFilieresDartTest`).
- **Web** : un seul composant `FicheEspece` pour les 7 routes `/elevage/<filière>` (`/elevage/poulets-pondeuses` porte les onglets Poulets et Pondeuses), `DashboardElevage` pour `/elevage/dashboard`.
  Écritures par `TableSync::absorber` (device `Catalogue::POSTE_WEB`) via `App\Services\FichesElevage` (port du dépôt, du cas d'usage `EnregistrerJournee` et de la cascade) et `App\Support\CalculFicheJournaliere`.
  La saisie du web est datée du plus tardif de (maintenant, instant de la ligne connue + 1 µs) : elle l'emporte même si l'horloge d'un poste avait de l'avance (décision D7).

### Écarts avec le Dart (déclarés dans les écrans)

| Écart | Raison |
|---|---|
| Pas de tableau de rationnement (provende) ni de pesée → provende | barèmes de ration non synchronisés (`P7c`) ; la pesée est enregistrée et le poids moyen affiché |
| Pas de prophylaxie du jour, de calendrier de prophylaxie ni de planification d'échéance | calendrier et soins non synchronisés (`P7c`) |
| Dashboard : cartes « Couveuse », « Rappels vétérinaires », « Alertes sanitaires » grisées « Disponible sur le poste » ; panneau GMQ avec le message du Dart | couveuse (`P7b`), soins (`P7c`) et stock d'intrants propres à d'autres tranches ou au poste ; jamais un zéro inventé |
| Pas d'export PDF, pas d'icônes Material Symbols, pas de rappel de prophylaxie à l'ouverture | police d'icônes non embarquée au web ; documents au poste |
| Code de bande proposé avec le préfixe par défaut `B` | le préfixe se règle aux Paramètres Élevage (`P7c`) |
| Messages de refus d'une bande : ceux du serveur (accentués), plus précis que ceux du Dart | le web écrit par la même table que les postes |
| Effectifs saisis en direct : recalculés à chaque frappe (aller-retour serveur, 400 ms) au lieu d'un calcul local | Livewire |

## 6. Décisions à valider par le client

Chaque point ci-dessous est un **choix métier fait faute de réponse**. Dans le doute, l'option la plus prudente a été retenue. Aucun n'a été validé.

| Id | Décision prise | Alternative écartée | Pourquoi / risque |
|---|---|---|---|
| **D1** | Deux postes saisissent le même jour : la saisie **la plus récente gagne en bloc** (ligne entière). | Fusion champ par champ ; premier arrivé gagne. | Les effectifs sont calculés : une fusion produirait un effectif faux. Risque : la saisie du poste le plus ancien est perdue (mais restée visible tant que ce poste n'a pas synchronisé). |
| **D2** | **Pas de recalcul automatique** des jours voisins à l'arrivée d'une fiche d'un autre poste. | Rejouer la cascade à la réception. | Règle d'or (aucun effet de bord) ; chaque poste envoie ses propres recalculs. Risque : si deux postes saisissent des jours **voisins** hors ligne, l'effectif d'un jour peut ne pas découler de celui de la veille jusqu'à la prochaine saisie qui déclenche la cascade. Faut-il un bouton « Recalculer la chaîne » ? |
| **D3** | Le compteur de ventes du jour est **une ligne par poste, sommée à la lecture** ; la fiche affiche (et enregistre dans `vente`) la somme de **tous** les postes au moment de la saisie. | Ligne unique à dernier écrivain gagne ; compteur central. | Évite les ventes perdues et le double comptage. Risque : `fiche_journee.vente` est un instantané ; si un poste synchronise ses ventes **après** la saisie de la fiche, le compteur change mais la fiche n'est recalculée qu'à la prochaine saisie du jour. |
| **D4** | Deux bandes de **même code** (filière) créées hors ligne : la seconde est **refusée** (conflit visible), jamais fusionnée. | Clé déterministe (code) qui fusionne ; suffixe automatique du code de poste. | Fusionner perdrait une date de mise en place (donc fausserait la prophylaxie). Risque : le poste refusé n'a pas d'écran pour **recoder** une bande ; il faudra en prévoir un, ou valider le suffixe automatique `B2-P2`. |
| **D5** | `effectif_initial` voyage comme **déclaration indicative** ; l'effectif réel d'une bande n'est ni stocké ni synchronisé. | Calculer et stocker un effectif par bande. | La fiche est tenue par filière, répartir entre bandes concomitantes supposerait des données que personne n'a saisies. |
| **D6** | Droits : fiches et bandes **lecture `view-elevage` / écriture `manage-elevage`** (animalier, administrateur). Compteur de ventes : lecture `view-elevage` **ou** `view-ventes`, écriture `manage-ventes` **ou** `manage-elevage`. | Écriture réservée à `manage-elevage`. | Le **caissier** alimente le compteur par la caisse : sans `manage-ventes`, son poste verrait tous ses compteurs refusés. Le comptable (`view-ventes`) lit le compteur sans l'écrire. |
| **D7** | Une saisie du web est datée du plus tardif de (maintenant, ligne connue + 1 µs). | Horloge du serveur seule. | Sans cela, l'utilisatrice du web verrait sa saisie **ignorée sans bruit** si l'horloge d'un poste avait de l'avance (« dernier écrivain gagne »). Risque : elle l'emporte sur une saisie de poste plus récente en réalité mais datée plus tôt. |
| **D8** | Au web : la clôture d'une bande est datée **d'aujourd'hui** (fuseau de l'entreprise), comme au poste ; le code proposé a le préfixe par défaut `B`. | Date choisie dans la modale. | Fidélité au Dart. |
| **D9** | Les fiches existantes d'un poste migré sont datées **du jour qu'elles décrivent** ; à instant égal entre deux postes migrés, la **première arrivée au serveur** est conservée. | Dater de la migration. | Dater de la migration aurait fait gagner une vieille fiche contre une correction faite ailleurs. |
| **D10** | La **remise à zéro** du serveur vide fiches, compteurs et bandes des postes, y compris leurs lignes non envoyées (comptées et signalées). | Préserver les fiches (« données d'élevage »). | Cohérence avec les ventes (une remise à zéro efface l'activité). Les fiches sont de l'historique d'exploitation : à confirmer qu'elles doivent bien partir. |
| **D11** | Le web **ne supprime jamais** une fiche ni une bande ; il ne peut pas non plus corriger un compteur de ventes. | Ajouter ces gestes. | Le poste non plus ne supprime pas de fiche ; le compteur appartient à la caisse du poste qui a vendu. |
| **D12** | Au dashboard web, **Revenus Élevage** = ventes non annulées du mois **hors catégorie « Commerce Annexe »**, du 1er du mois (fuseau de l'entreprise) à maintenant. | Fin de mois incluse. | Même définition que le Dart. |
| **D13** | `soins_calendrier.bande_id` passe en UUID texte ; un soin dont la bande n'existait pas garde `null`. | Supprimer le soin. | Jamais de perte de ligne. |

## 7. Tests

- **Poste** : `test/core/migration_v38_elevage_test.dart` (11 : vraie base v37, aucune ligne perdue, UUID, instants, convergence de deux bases, soins, intégrité, rejeu),
  `test/elevage/fiches_sync_poste_test.dart` (32 : envoi, absorption stricte, convergence de deux postes dans le désordre, saisie locale plus récente/plus ancienne, refus avec motif,
  hors ligne, saisie pendant l'envoi, remise à zéro, compteurs sans double comptage, collision de code de bande). Faux serveur étendu : il **rejoue** les règles du vrai.
  **26 mutations**, toutes tuées (identité non contrôlée, instant non comparé, origine mal reprise, compteur d'un autre renvoyé, purge, clôture avant mise en place, migration datée de « maintenant », soins sans bande…).
- **Serveur** : `tests/Feature/Sync/ElevageFichesTest.php` (51 cas : push, pull, rejeu idempotent, ligne entière, refus avec motif français, droits par rôle, deux postes dans les deux ordres, remise à zéro, marque inconnue 409). **17 mutations** tuées (identité non contrôlée, ligne non entière, droits, strictness des entiers/booléens/dates, clôture avant mise en place, code non rogné, table non déclarée, version de l'UUID…).
- **Web** : `tests/Feature/Web/FicheEspeceWebTest.php` (62 cas : accès par rôle et par module, 7 routes, onglets, KPI, tableau mensuel et hebdomadaire, ventes POS sommées, totaux en direct, saisie et cascade, pondeuses, validations, horloge en avance d'un poste, bandes, droits de **chaque** méthode, module désactivé après ouverture, filière verrouillée),
  `DashboardElevageWebTest.php` (11), `tests/Feature/ConformiteFilieresDartTest.php` (5, relit le Dart), `tests/Unit/CalculFicheJournaliereTest.php` (16, mêmes cas que le test Dart). **31 mutations** tuées. `npm run build` OK.
- Suites complètes au moment de la tranche : `flutter analyze` « No issues found! », `flutter test` 1433 tests verts (+13 d'intégration ignorés), `php artisan test` 602 tests verts.

## 8. Limites

- **Cascade entre postes** : voir D2. Un effectif n'est garanti cohérent avec la veille que par le poste qui a saisi.
- `fiche_journee.vente` est un instantané du compteur au moment de la saisie (D3).
- Une bande refusée pour code en doublon reste en `conflict` au poste sans moyen de la recoder (D4).
- La suppression d'une fiche ou d'une bande n'existe ni au poste ni au web : pas de pierre tombale.
- Pas d'essai contre le **vrai** serveur Laravel pour ces trois tables (`test/integration/serveur_reel_test.dart` n'a pas été étendu) ; le faux serveur rejoue les règles mais n'est pas le serveur.
- Le web ne montre pas la provende, la prophylaxie, la couveuse ni les soins (§5).
- `soins_calendrier.echeance_prophylaxie_id` (référentiel du calendrier) n'est pas touché : il relève de `P7c`.

## 9. Fichiers partagés touchés (points de fusion)

Uniquement des lignes ou blocs **nouveaux** : `app_database.dart` (`versionSchema = 38`, bloc `if (from < 38)`, méthodes `_elevageEnUuid` et suivantes, deux `import`), `main.dart` (3 lignes dans `tables`, 3 `import`),
`test/core/sync/faux_serveur_sync.dart` (3 tables, 3 méthodes), `config/logialvia.php` (3 classes dans `sync.tables`), `tests/Concerns/PostesDeTest.php` (3 helpers).
Conséquences sur d'autres tranches : `Soin.bandeId` et `soins_calendrier.bande_id` passent en `String` (UUID) ; `Bande.id` en `String` ; la migration v38 réécrit `soins_calendrier` (`bande_id` seul). La tranche `P7c`, si elle reconstruit
`soins_calendrier`, doit reprendre `bande_id` **en texte**.

