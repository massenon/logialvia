# 46d — Synchronisation de la comptabilité SYSCOHADA et des dépenses (tranche P8)

> **Statut au 09/11/2026.** Poste (schéma **v41**), serveur et web sont livrés et testés. Ce document dit les règles
> **choisies**, les chiffres vérifiés, les **décisions à valider par le client** (§7) et les limites (§8). Il complète
> `46_CONTRAT_SYNCHRONISATION.md` (§2.5 : « la comptabilité est une demande ») sans le modifier : le contrat prévoyait que
> ces tables resteraient hors synchronisation tant que le web n'aurait pas **le même moteur comptable que le poste**. Il
> l'a maintenant : port fidèle de `moteur_comptable.dart`, vérifié sur un jeu d'écritures construit à la main (§5).
>
> **Écart avec le contrat (à reporter dans `46_` §2.5 par le coordinateur).** Le contrat disait que le poste enverrait
> « le fait générateur » (vente encaissée, dépense saisie) et que le serveur numéroterait la pièce. La règle actée pour
> cette tranche est **l'inverse, et plus sûre** : le poste envoie **ses propres écritures**, comme des faits immuables ;
> le serveur les **vérifie** (équilibre, verrous, plan, droits) mais **n'en engendre aucune** ; les numéros portent le
> préfixe de poste (DV-21) et ne sont **jamais renumérotés**.

## 1. Les cinq tables du poste et ce qu'elles deviennent

| Table Dart | Clé | Nature | Table(s) de synchronisation | Serveur |
|---|---|---|---|---|
| `plan_comptable` | **numéro de compte** (clé naturelle) | **référentiel** : le serveur gagne, le poste **propose** | `plan_comptable` | `plan_comptable` |
| `exercice_comptable` | **année** (clé naturelle) | référentiel **reçu seulement** | `exercice_comptable` (tirage) + `clotures_exercice` (fait lourd, envoi) | `exercices_comptables`, `clotures_exercice` |
| `ecriture_comptable` | UUID par ligne ; `piece_id` par pièce | **faits immuables**, une pièce à la fois | `ecriture_comptable` | `pieces_comptables` + `ecritures_comptables` |
| `notes_annexes` | UUID **déterministe** de (exercice, numéro) | fait, dernier écrivain gagne | `notes_annexes` | `notes_annexes` |
| `clotures_periodiques` | (année, mois) ; UUID dérivé | fait, dernier écrivain gagne | `clotures_periodiques` | `clotures_periodiques` |

Pourquoi `plan_comptable` et `exercice_comptable` **ne passent pas en UUID** : leur clé est **naturelle et partagée**
(le même numéro de compte, la même année, sur tous les postes) et plusieurs tables les référencent. Les convertir
obligerait à réécrire des clés étrangères pour rien, et deux postes semés du même programme leur donneraient des UUID
différents. Le plan est **semé à l'identique** partout (19 comptes, `PlanComptableSeeder` Dart et PHP,
`ConformiteComptabiliteDartTest` les compare **compte pour compte**).

### 1.1 Migration du poste (v40 → v41, DV-19)

`_comptabiliteEnUuid` : idempotente (chaque table est testée sur son état réel, pas sur le numéro de version), sans
perte de ligne, rejouable sans changer un UUID. Vérifiée sur une **vraie base v40** (`migration_v41_comptabilite_test.dart`, 10 tests).

- `ecriture_comptable` : `id` en UUID aléatoire ; **`piece_id`** regroupe les lignes d'une même pièce (exercice + numéro).
  Une ligne **sans numéro de pièce** forme sa propre pièce (on ne devine rien). Les écritures d'hier sont **locales**
  (`origine` vide), **à envoyer**, et leur instant de saisie est **leur date** (pas l'instant de la migration, qui les
  ferait gagner contre une correction faite ailleurs). Le verrou des exercices clos est conservé.
- `notes_annexes` : `id` = UUID v5 de `note:<exercice>-<numéro>` (le même sur tous les postes).
- `exercice_comptable` : un exercice **clos** devient « à envoyer » (le serveur vérifiera la clôture), un exercice ouvert non.
- `clotures_periodiques` : les clôtures d'hier partent.
- Cas limite traité : le numéro de pièce n'est **pas unique** (`REG-V-…` revient à chaque règlement partiel d'une même
  vente) ; la migration regroupe par (exercice, numéro), la pièce regroupée reste équilibrée. Une pièce **déséquilibrée**
  d'avant (donnée corrompue) sera refusée par le serveur avec son motif, jamais « réparée » en silence.

## 2. Règles choisies

### 2.1 Une pièce est un fait immuable

- L'unité de synchronisation est la **pièce** (partie double), pas la ligne : ses lignes voyagent dans un même corps
  (`lignes: [...]`), le serveur l'accepte ou la refuse **toute entière** (même schéma que ventes et achats).
- Une pièce **acceptée ne change jamais**. Rejouée, même avec un contenu différent, elle est acceptée sans rien changer
  (idempotence par UUID).
- **Se corriger, c'est contrepasser** : pièce inverse `ANN-<numéro>`, journal `OD`, **à la date du jour**, mêmes comptes
  et mêmes centres analytiques, sens inversé, champ `contrepasse_de`. Le serveur vérifie qu'elle **reprend la pièce
  annulée ligne pour ligne**, qu'une pièce ne s'annule **qu'une fois** et qu'**une annulation ne s'annule pas**.
- **Au poste** : une pièce **non encore transmise** (`pending`) ou **refusée** (`conflict`) se modifie et se supprime
  comme avant (rien n'est parti, ou le serveur ne l'a jamais acceptée) ; une pièce **transmise** (`synced`) ne se modifie
  plus (message explicite) et « Supprimer » devient **« Annuler »** : l'écriture inverse est passée, le journal garde les
  deux traces, la dépense annulée sort de la liste. Une pièce **venue d'un autre poste** ne se modifie ni ne se supprime ici.
- **Au web** : même règle — pas de modification, « Annuler la pièce » / « Annuler la dépense ».

### 2.2 Origine et absence d'effet comptable à la réception

- Chaque ligne reçue d'un autre poste porte son **`origine`** (identifiant du poste qui l'a saisie) ; une ligne locale a
  `origine` vide. Le Journal du poste l'indique (icône « autre poste »), le web affiche le **code du poste** (`P2`, ou
  « Web »).
- **Absorber la vente ou l'achat d'un autre poste n'a AUCUN effet comptable local** (règle actée) : l'écriture de ce
  poste-là arrive **comme son propre fait**. Le grand livre et la balance de chaque poste sont donc la **somme de tous les
  faits**, sans double comptage ni trou. Testé : A et B vendent hors ligne, se synchronisent dans le désordre, mêmes
  totaux, mêmes lignes, même résultat net des deux côtés.
- Le **serveur** n'engendre pas non plus d'écriture à partir d'une vente reçue (testé).

### 2.3 Numérotation (DV-21)

`<journal>-<code du poste>-<année>-<séquence à 4 chiffres>` : `OD-P2-2026-0003`, `DEP-P2-2026-0001`. La séquence est
**continue par poste et par année**, **jamais renumérotée** (une pièce modifiée garde son numéro : il figure sur le reçu
papier). Un poste jamais appairé garde l'ancien format `OD-2026-0003`. Le **web** est un poste de code `WEB`
(`OD-WEB-2026-0001`). Les numéros des pièces automatiques sont ceux des ventes et achats (`V-P2-2026-001`, `ACH-…`),
déjà préfixés. Le numéro n'est **pas** une clé : l'identité d'une pièce est son `piece_id`.

### 2.4 Plan comptable : le serveur gagne, le poste propose

- Créer, renommer ou archiver un compte au poste dépose une **demande** `compte_comptable`
  (`{numero_compte, libelle, classe, archive}`) ; le serveur décide (droit `manage-comptabilite`, validation, dernier
  écrivain gagne à l'instant de **saisie**, audit) et redistribue.
- **Valeur de semis ≠ décision** : un compte jamais décidé (`updated_at == created_at`) n'écrase pas le poste.
- Une saisie locale plus récente que la décision du serveur est **conservée** et part ; une décision plus récente
  **supplante** la saisie non envoyée (comptée).
- **Adoption initiale** (une fois) : les comptes ajoutés ou renommés au poste hors du socle sont proposés, pour être
  connus du serveur **avant** que les écritures qui les portent n'arrivent. Le socle n'est jamais reproposé.
- Le **numéro** ne change jamais ; la **classe est le premier chiffre du numéro** (donc un compte mouvementé ne peut pas
  changer de classe). Jamais de suppression : archivage seulement.

### 2.5 Exercices

- Le serveur **ouvre** un exercice quand une écriture y arrive (bornes **2000 → année en cours + 1**, sinon refus).
- Le poste reçoit les exercices **avant** les écritures (ordre des tables) : une pièce dont l'exercice ou un compte reste
  inconnu est **refusée et comptée** à la réception, jamais devinée.
- **Aucune déclôture** (BR-CPT-001). Un serveur qui dit « ouvert » ne rouvre jamais un exercice que le poste a clos.
  Seule la **remise à zéro** du serveur rouvre les exercices (leurs écritures sont purgées avec).

### 2.6 Clôture mensuelle (BR-CPT-006)

Fait « dernier écrivain gagne », strictement, par (année, mois). **Clore** : `manage-comptabilite`, sur une balance
équilibrée, jamais dans un exercice clos. **Déclôturer** : `close-fiscal-year` (l'administratrice seule), tracée à l'audit.
Un mois clos refuse **toute nouvelle écriture à sa date**, y compris les écritures automatiques d'une vente antidatée.

### 2.7 Clôture annuelle : un fait lourd

**Qui.** `close-fiscal-year` : l'**administratrice seule** (DV-15). Le comptable consulte, comptabilise, clôt les mois,
mais ne clôt pas l'exercice. Au poste : rôle `admin`, dans le ViewModel (pas seulement dans l'écran).

**Quand.** Une clôture est **envoyée en dernier** (`clotures_exercice` après `ecriture_comptable` dans l'ordre du moteur
et dans `sync.tables`, **quel que soit l'ordre du lot reçu** — testé) : le serveur verrouille un exercice dont il doit
**connaître toutes les pièces**. En plus :
- un poste **déjà appairé** refuse de clôturer tant qu'une pièce de l'exercice n'a pas été acceptée (`pending`) ou a été
  refusée (`conflict`) : « Synchronisez ce poste avant de clôturer… » (un poste **jamais appairé** clôture seul) ;
- le serveur vérifie l'**équilibre** (BR-CPT-004) de **toutes** les lignes de l'exercice ;
- le serveur est la vérité : s'il refuse (droit, équilibre), la clôture **n'a pas eu lieu** ; le poste **rouvre
  l'exercice** localement (écritures déverrouillées), garde le **motif**, l'affiche sur l'écran de clôture, et permet de
  recommencer. Ce n'est pas une déclôture : le serveur, qui fait foi, n'avait jamais clos.

**Effet.** Exercice clos (définitif), exercice suivant ouvert, écritures verrouillées (dérivé de l'exercice), trace du
fait (qui, depuis quel poste, quand) et audit. Rejouée, ou déjà close : acceptée sans rien changer.

### 2.8 Écriture saisie hors ligne pour une période clôturée entre-temps

Le poste B, hors ligne, écrit en mars ; l'administratrice clôt mars (ou l'exercice) ailleurs ; B se reconnecte : il reçoit
la clôture, puis envoie sa pièce. Le serveur la **refuse avec son motif** (« Le mois 3/2026 est clôturé… »,
« L'exercice 2026 est clôturé… »). Elle **reste dans les livres de B**, marquée **« Refusée par le serveur »** (icône et
infobulle du Journal), jamais supprimée en silence ; elle est **modifiable ou supprimable** (le serveur ne l'a jamais
acceptée) et empêche B de clôturer l'exercice. Le serveur ne la reroute **jamais** vers une autre période : le rattachement
d'une dépense à un mois est un choix de la Gérante (voir D3).

### 2.9 Notes annexes

Dernier écrivain gagne par (exercice, numéro) à l'instant de saisie, strictement ; rien n'est fusionné. Identifiant
déterministe : deux postes qui rédigent la note 1 de 2026 ne créent pas de doublon. Au web, seules les notes **1 et 5**
(rédactionnelles) s'éditent ; **2, 3 et 4 sont calculées** depuis la balance, comme au poste.

### 2.10 Droits

| Table | Lecture | Écriture |
|---|---|---|
| `plan_comptable`, `exercice_comptable` | `view-comptabilite` | demande `manage-comptabilite` ; exercices : jamais envoyés |
| `ecriture_comptable` | `view-comptabilite` | pièce **manuelle** : `manage-comptabilite` ; pièce **automatique** (`vente_ref` / `achat_ref`) : aussi `manage-ventes` / `manage-achats` |
| `notes_annexes` | `view-comptabilite` | `manage-comptabilite` |
| `clotures_periodiques` | `view-comptabilite` | clore : `manage-comptabilite` ; déclôturer : `close-fiscal-year` |
| `clotures_exercice` | jamais servie | `close-fiscal-year` |

Le poste de caisse (compte web `caissier`) peut donc envoyer ses écritures de vente, pas lire le grand livre ni saisir une
écriture manuelle. Lien aux écrans : `/comptabilite*` exige `view-comptabilite` (admin, comptable) ; `/depenses` exige
`view-achats` (matrice existante, inchangée) ; **écrire** exige `manage-comptabilite`, vérifié **dans chaque méthode**
Livewire (un composant neuf par appel interdit, testé).

### 2.11 Dates et fuseau

L'exercice et le mois d'une écriture s'entendent dans le **fuseau de l'exploitation** (`Africa/Porto-Novo`) : une
écriture du 1ᵉʳ janvier 00h30 à Natitingou appartient à janvier, même si son instant UTC est encore en décembre. Le
serveur recalcule l'exercice depuis la date et **refuse** une pièce dont l'exercice déclaré diffère (testé à la frontière
du 31/12 23h30 UTC).

### 2.12 Remise à zéro du serveur

Efface pièces, lignes, notes, clôtures mensuelles et faits de clôture ; **préserve le plan** ; **rouvre les exercices**
(leur clôture est de l'activité, les écritures qu'elle verrouillait viennent d'être effacées). Le poste, quand il apprend
la nouvelle marque, purge de même, rouvre ses exercices et **compte** les saisies non envoyées perdues (écritures, notes,
clôtures, clôture d'exercice non acceptée).

## 3. Format des échanges (précisions à `46_` §4)

- **Pull** `plan_comptable` : `{numero_compte, libelle, classe, archive, saisi_le, created_at, updated_at}` ;
  `exercice_comptable` : `{annee, is_cloture, date_cloture, updated_at}` (sans `cloture_par`) ;
  `ecriture_comptable` : `{id (piece_id), device_id, numero_piece, date_ecriture, exercice_annee, journal_code, vente_ref,
  achat_ref, contrepasse_de, updated_at, serveur_modifie_le, lignes: [{id, piece_id, numero_compte, debit, credit,
  libelle, axe_analytique}]}` (une pièce n'est jamais servie sans ses lignes) ; `notes_annexes` et `clotures_periodiques`
  à plat.
- **Push** `ecriture_comptable` : le même corps sans `device_id` ni `serveur_modifie_le` ; `clotures_exercice` :
  `{id, annee, date_cloture, updated_at}` ; `clotures_periodiques` : `{id, annee, mois, is_cloture, date_cloture,
  decloture_par, updated_at}`.
- **Demande** `POST /api/sync/demandes`, type `compte_comptable`.
- **Ordre** (moteur du poste **et** `sync.tables`) : `plan_comptable`, `exercice_comptable`, `ecriture_comptable`,
  `notes_annexes`, `clotures_periodiques`, `clotures_exercice`. Purge à la remise à zéro dans l'ordre inverse.
- **Identifiants déterministes** (UUID v5 de `logialvia:<clé>`, identiques en Dart et en PHP — testé contre les valeurs
  calculées par le Dart) : `note:<année>-<n>`, `cloture-periodique:<année>-<mois>`, `cloture-exercice:<année>`.

## 4. Écrans web

`/comptabilite` (hub), `/comptabilite/journal`, `/grand-livre`, `/balance`, `/plan`, `/analytique`, `/etats-financiers`,
`/bilan`, `/cloture`, et `/depenses` — un fichier `routes/ecrans/*.php` par écran. Lectures calculées par le serveur
(`MoteurComptable`, port fidèle du Dart) sur **toutes** les pièces reçues. Écritures : `EcrituresTable`,
`NotesAnnexesTable`, `CloturesPeriodiquesTable`, `ClotureExerciceTable` (`pourUtilisateur()->absorber`, poste « web » =
UUID nul), plan par `DemandesReferentiel::traiter`.

**Comment une dépense devient une écriture** (lu dans le Dart) : une dépense **n'a pas de table**. C'est une **pièce de
deux lignes**, journal `CA`, numéro `DEP-<poste>-AAAA-NNNN` : la charge au **débit** d'un compte de **classe 6** (hors
601/602, alimentés par les achats), la contrepartie au **crédit** d'un compte de **trésorerie** (classe 5) ou, « à
crédit », d'un compte fournisseur (40x). Le centre analytique n'est porté que par la ligne de charge. La liste des
dépenses est **reconstruite** depuis les écritures (ligne au débit de classe 6, sans `vente_ref` ni `achat_ref`) ; une
charge soldée par 40x est « En attente ». Une dépense **annulée** (contrepassée) n'en est plus une.

## 5. Chiffres vérifiés contre le Dart (jeu commun, construit à la main)

Même jeu dans `logialvia_app/test/comptabilite/jeu_commun_chiffres_test.dart` (14 tests) et
`logialvia_laravel/tests/Concerns/JeuComptable.php` + `Web/ComptabiliteWebTest.php`. Les chiffres attendus sont **calculés
à la main**, puis vérifiés **des deux côtés** : si le web et le poste s'écartent, l'un des deux tests rougit.

Exercice N−1 : `531 D 100 000 / 101 C 100 000` (ouverture). Exercice N : apport `531 D / 101 C 500 000` ; vente comptant
`531 D / 701 C 120 000` (centre Goliaths) ; vente à crédit `531 D 30 000, 411 D 50 000 / 707 C 80 000` ; achat
`601 D 40 000 / 531 C 10 000, 401 C 30 000` ; dépense transport `624 D 15 000` (centre Pintades) `/ 531 C` ; dépense
assurance `616 D 12 000 / 401 C` ; encaissement `531 D / 411 C 20 000` ; bâtiment `231 D / 531 C 200 000`.

| Grandeur | Valeur | | Grandeur | Valeur |
|---|---|---|---|---|
| Débit = crédit (exercice N) | 987 000 | | Marge commerciale | 80 000 |
| Résultat net (produits 200 000 − charges 67 000) | 133 000 | | Consommations des tiers (601 + 61 + 62) | 67 000 |
| Trésorerie (classe 5, soldes débiteurs) | 445 000 | | Valeur ajoutée = EBE | 133 000 |
| Total actif = total passif (bilan) | 675 000 | | Flux d'exploitation / investissement / financement | 145 000 / −200 000 / 267 000 |
| Balance : soldes finaux D = C | 842 000 | | Trésorerie de clôture du TAFIRE | 312 000 |
| Balance : mouvements D = C ; ouverture D = C | 987 000 ; 100 000 | | Bilan de l'entreprise : actif ; passif ; écart | 475 000 ; 675 000 ; −200 000 |
| Grand livre 531 : ouverture ; débit ; crédit ; final | 100 000 ; 670 000 ; 225 000 ; 545 000 | | …depuis le 01/05 : ouverture ; final | 740 000 ; 545 000 |
| Analytique : Σ marges ; charges non affectées | 145 000 ; 12 000 | | Dépenses : fixes ; variables | 12 000 ; 15 000 |

Invariant vérifié : Σ marges + produits non affectés − charges non affectées = résultat net (145 000 − 12 000 = 133 000).

## 6. Tests et mutations

- **Poste** (Flutter, 1456 tests dont 66 nouveaux ; analyse « No issues found! ») : `migration_v41_comptabilite_test.dart`
  (10, vraie base v40), `comptabilite_sync_poste_test.dart` (42, faux serveur étendu `FauxServeurSync` qui rejoue
  équilibre, verrous, clôtures), `jeu_commun_chiffres_test.dart` (14). **~30 mutations** (équilibre, origine, plan connu,
  verrou d'absorption, contrepassation, immuabilité, numéros de poste, rôle de clôture, pré-condition de synchro, remise
  à la baisse d'une clôture refusée, ordre de réception…) : toutes **tuées** après renforcement de 4 tests trop faibles
  (semis du plan, verrou d'une pièce reçue dans un exercice clos, note hors 1-5, règle du plus récent d'une clôture
  mensuelle), **sauf 2 équivalentes** (le filtre `origine` à l'envoi est redondant avec le statut `synced` des lignes
  absorbées ; `lignes < 2` est redondant avec le contrôle d'équilibre).
- **Serveur** (PHP : 56 nouveaux tests, suite complète 602 tests / 4366 assertions) : `Sync/ComptabiliteTest` (41), `Sync/PlanComptableDemandesTest` (10),
  `ConformiteComptabiliteDartTest` (5, plan compte pour compte, UUID, tolérance, journaux, droits). **28 mutations** tuées
  (équilibre, partie double, verrous, fuseau, droits, contrepassation, idempotence, clôtures, remise à zéro…), une
  mutation équivalente retirée du code (`touch()` redondant).
- **Web** (PHP : 90 nouveaux tests) : `Web/ComptabiliteWebTest` (67), `Web/DepensesWebTest` (23) ; `CoqueNavigationTest` ne
  désigne plus un écran précis comme « non converti » (il prend la première route restante). **~36 mutations** tuées (ouverture, borne
  incluse, sens naturel, mois en cours, signe du capital, double comptage analytique, annulées, droits de chaque méthode
  Livewire, confirmation d'archivage, comptes proposés, exercice libre…), dont 2 survivantes d'abord, renforcées
  (« -120 000 » contenait « 120 000 »). Une équivalente (`!` de `createFromFormat`, l'heure est réécrite juste après).
- `npm run build` OK.

## 7. Décisions à valider par le client

Chacune a été tranchée par **l'option la plus prudente** ; aucune ne bloque.

| # | Décision prise | Alternative possible |
|---|---|---|
| **D1** | Une écriture **transmise** ne se modifie ni ne se supprime : on l'**annule** par l'écriture inverse (`ANN-…`), au poste comme au web. | Autoriser la modification d'une dépense tant qu'aucun mois n'est clos (le serveur devrait alors tenir une version par pièce). |
| **D2** | **La clôture annuelle est réservée à l'administratrice** ; elle exige un poste **synchronisé** (aucune pièce en attente ou refusée), une balance équilibrée vérifiée **par le serveur**, et le serveur a le dernier mot : refusée, l'exercice est **rouvert** au poste avec le motif. Un poste appairé **hors ligne ne peut donc pas clôturer**. | Permettre au comptable de clôturer ; permettre la clôture hors ligne puis la faire valider au retour. |
| **D3** | Une écriture saisie hors ligne dans une période **clôturée entre-temps** est **refusée avec son motif** et **reste visible, marquée, dans les livres du poste** (corrigeable ou supprimable) ; elle n'est **jamais** rattachée automatiquement à une autre période. | Reporter automatiquement la pièce au premier mois ouvert (au risque de fausser la date d'une dépense). |
| **D4** | **Clore un mois** : comptable ou administratrice ; **le rouvrir** : administratrice seule, avec audit (comme au poste). | Tout au comptable. |
| **D5** | Le serveur **ouvre automatiquement** un exercice quand une écriture y arrive (de 2000 à l'année en cours + 1). | Ouverture explicite par l'administratrice. |
| **D6** | Les écritures saisies **au web** portent le code de poste **`WEB`** (`OD-WEB-2026-0001`). | Un code `P0` partagé, ou un numéro attribué par le serveur. |
| **D7** | Le compte du **caissier** peut envoyer les écritures **automatiques** de ses ventes, pas d'écriture manuelle ; il ne lit pas le grand livre. | Refuser toute écriture à qui ne gère pas la comptabilité (il faudrait alors que le poste de caisse s'appaire avec un compte comptable). |
| **D8** | La **remise à zéro** efface les clôtures et **rouvre les exercices** ; elle préserve le plan. | Conserver les exercices clos. |
| **D9** | Plan comptable : le poste **propose**, le serveur **arbitre** (dernier écrivain gagne, à la saisie) ; jamais de suppression, archivage seulement ; adoption initiale **une fois** des comptes ajoutés au poste. | Plan verrouillé côté serveur, modifiable au web seulement. |
| **D10** | Notes annexes : le **plus récent** remplace l'autre (pas de fusion de texte). | Verrou d'édition, ou historique des versions. |
| **D11** | Le **bilan, le Compte de Résultat et le TAFIRE du poste ne cumulent pas l'ouverture** : ils lisent les écritures de l'exercice seul ; le TAFIRE soustrait pourtant l'ouverture (variations). Dès qu'un exercice antérieur existe, l'écran « Flux de Trésorerie » affiche « Incohérence de … » (133 000 FCFA sur le jeu commun). **Repris à l'identique au web** (le Dart est la source). | Générer les écritures de **report à nouveau** à la clôture (prévues par `J1_Bascule_Cloture_Exercice.md` §1.4, **non codées** au poste : l'étape 3 de l'assistant les annonce) — ce qui corrigerait le bilan, la balance et le TAFIRE. **À arbitrer avant la première clôture réelle.** |
| **D12** | Tolérance d'équilibre **0,01 FCFA** ; fuseau **Africa/Porto-Novo** pour l'exercice et le mois. | — |
| **D13** | Dépenses : pas de « Modifier » après transmission ; « Annuler la dépense ». Au poste, « Modifier » reste possible tant que la dépense n'est pas transmise. | Voir D1. |
| **D14** | Les écritures **d'avant la migration** ont pour instant de saisie **leur date** et partent toutes au premier envoi. | — |

## 8. Écarts et limites

- **Pas d'export PDF** au web (journal, grand livre, balance, plan, analytique, bilan, états). Les PDF restent au poste.
- **Pas de modification d'une pièce transmise** (D1) ; **pas de pièce justificative** (le poste n'en stocke pas non plus).
- **Report à nouveau non généré** (D11) : l'étape 3 « Génération des Écritures d'À-Nouveaux » de l'assistant de clôture
  est un texte hérité du prototype ; ni le poste ni le web ne passent ces écritures.
- **Bandeau « Ventilation par activité, et non par filière »** de l'analytique du poste **non repris** : il date d'avant
  l'axe analytique (v19) et contredit l'écran ; le web ventile par axe, puis par compte.
- Le **web n'affiche pas de piste d'audit** par pièce (qui a saisi quoi) au-delà du poste d'origine.
- **Les écrans du poste ne se rafraîchissent pas seuls** après une synchronisation (le ViewModel de comptabilité se
  recharge à l'ouverture de l'écran) : limite préexistante, non traitée ici.
- **`/rapports` (hors périmètre)** lit `ecriture_comptable` et ordonne par `id` à date égale ; l'`id` est devenu un UUID :
  l'ordre des mouvements d'un même jour est stable mais arbitraire. Aucun test n'en dépend.
- **Essai contre le vrai serveur Laravel** (`test/integration/serveur_reel_test.dart`) : **non fait** pour ces tables ;
  le faux serveur rejoue les règles du vrai (équilibre, verrous, clôture, contrepassation), les deux jeux de tests
  visent les mêmes cas.
- Une pièce **sans numéro** d'avant la migration devient sa propre pièce : elle est refusée par le serveur si elle est
  déséquilibrée seule (cas d'une donnée déjà corrompue).
