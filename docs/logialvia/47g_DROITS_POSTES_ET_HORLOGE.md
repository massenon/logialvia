# 47g — Droits des postes et horloge : le moteur de synchronisation les respecte

> **Pourquoi.** L'essai réel (`47h_` D6) avait montré qu'un poste appairé à un compte sans droits (`caissier1`, `comptable1`,
> `animalier1`) proposait tout son semis : environ 74 demandes refusées pour « Droit insuffisant », laissées en `conflict`, jamais
> reproposées quand un administrateur se reconnectait. Et la limite signalée en `47h_` §5 : un poste dont l'horloge avance de plusieurs
> jours (ou années) écrit des `updated_at` / `saisi_le` dans le futur, **gagne toutes les comparaisons « dernier écrivain gagne »** et gèle
> les lignes contre les autres postes ; le serveur n'avait aucune garde.
>
> **Résultat.** Le poste connaît les droits de son compte, ne propose et ne pousse que ce qu'il peut écrire, ne tient jamais un refus de droit
> pour définitif ; le serveur refuse avec des **codes stables** ; un instant de saisie en avance de plus de 5 minutes est refusé, le poste
> mesure l'écart de son horloge à chaque synchronisation et suspend l'envoi tant qu'elle n'est pas corrigée. Rien n'est perdu.

## 1. Droits

### 1.1 Ce que le serveur annonce

`DroitsPoste::pour($utilisateur)` (`app/Sync/DroitsPoste.php`) — jamais de secret :

```json
{ "compte": "caissier1", "nom": "Caissier", "roles": ["caissier"],
  "permissions": ["view-ventes", "manage-ventes", "..."],
  "tables_ecrites": ["clients", "ventes", "devis", "..."],
  "tables_lues": ["..."],
  "demandes": ["produit_vendable"] }
```

Il est porté par : la réponse de **connexion** (`POST /api/auth/login`), `GET /api/auth/me` (« Tester la connexion ») et **chaque tirage**
(`GET /api/sync/pull`, page 1). Un droit accordé au serveur, un changement de compte ou une reconnexion arrivent donc au poste à sa
synchronisation suivante, sans manipulation.

Les listes ne sont pas recopiées : `tables_ecrites` vient de `TableSync::peutEcrire()` (donc des `droitEcriture()` et des surcharges de chaque table), limité aux tables de
**faits** ; `demandes` vient de `DemandesReferentiel::DROITS_PAR_TYPE`, la table unique qu'applique aussi le refus. Le test
`DroitsEtHorlogeTest` rejoue, pour chaque rôle et chaque table / type, que « annoncé » = « accepté par le serveur ».

| Rôle | Types de demandes proposables | Tables de faits écrites (hors messages à l'éditeur, ouverts à tout compte) |
|---|---|---|
| `admin` | les 8 (module, paramètres, produit, intrant, barème, taux, échéance, compte) | toutes (selon `peutEcrire` de chacune) |
| `caissier` | `produit_vendable` | clients, ventes, devis, compteurs de ventes du jour, mouvements de produit, écritures de vente |
| `comptable` | `compte_comptable` | factures, écritures, notes annexes, clôtures de mois |
| `animalier` | `bareme_ration`, `taux_ration_poids`, `echeance_prophylaxie` | fiches du jour, bandes, couveuse, soins, infirmerie |

### 1.2 Ce que fait le poste

- **Mémoire.** Les droits sont mémorisés avec l'appairage (`preferences_poste`, clé `sync.droits`, JSON sans secret) et rafraîchis à chaque tirage ; un
  nouvel appairage (autre compte) remplace ceux de l'ancien compte ; se déconnecter les oublie.
- **Il ne propose et ne pousse que ce que son compte peut écrire** : une table absente de `tables_ecrites` n'est pas poussée, un type absent de `demandes`
  n'est pas proposé. Les droits **inconnus** (ancien serveur, jamais appris) = le poste propose tout et le serveur tranche (comportement d'avant).
- **« En attente de droit »** est un état, pas un statut de base : la ligne ou la demande reste `pending`. Le poste la compte (`compterEnAttenteDeDroit`) et
  l'affiche ; `aDesSaisiesAEnvoyer()` ne la compte pas (le planificateur ne relance pas une synchronisation pour rien).
- **Un refus pour droit n'est jamais définitif.** Le serveur répond `code: "droit_insuffisant"` ; le poste le reconnaît **par le code** (plus aucune comparaison de texte)
  et laisse la ligne/demande `pending` (compteur `refuseesPourDroit`). Elle repart dès qu'une synchronisation passe avec le droit.
  Côté serveur, ce refus **n'est pas mémorisé** : la même demande (même UUID) rejouée par une session qui a le droit est jugée de nouveau
  (sinon l'idempotence par UUID lui aurait rendu éternellement son ancien refus). Une migration serveur (`2026_11_09_162000_*`) oublie les refus de ce genre déjà mémorisés.
- **Anciennes données.** Migration poste **v50** : les lignes restées `conflict` avec un motif « Droit insuffisant… » repassent `pending` (toutes les tables à colonnes de
  synchronisation) — seul endroit où un texte est comparé. Les 74 demandes de l'essai D6 repartent donc à la première synchronisation d'un compte qui a le droit.
- **Visible.**
  - Onglet « Appairage » du poste : carte « Droits et horloge » (compte, rôle, nombre de tables / types proposables, **saisies et demandes en attente de droit**,
    écart d'horloge, avertissement) et bouton **Réessayer** (synchronise tout de suite : le tirage rafraîchit les droits, ce qui attendait part).
  - Web, « Postes & Appairage » : colonne **Droits** par poste (compte, rôle, ce que le compte peut envoyer ; « compte supprimé » ; « lecture seule »).
    Le serveur ne sait pas combien de saisies attendent *sur le poste* : ce compteur n'existe que sur le poste.

## 2. Horloge

### 2.1 Règle du serveur

`GardeHorloge` (`app/Sync/GardeHorloge.php`), constante **`TOLERANCE_SECONDES = 300`** (5 minutes) : un instant de saisie qui dépasse l'horloge du serveur de plus de la
tolérance est refusé, code **`horloge_en_avance`**, motif français : « L'horloge de ce poste avance de 2 jours : corrigez la date et l'heure du poste. » (durée
arrondie à la minute : « 2 ans », « 2 jours », « 1 h 05 », « 7 min »). Égalité à la tolérance exacte : acceptée.

Instants contrôlés (ceux que le **poste écrit comme instant de saisie**, pas les dates métier : une échéance ou une date de vente peut être dans le futur) :
`updated_at`, `horodatage`, `saisi_le`, `supprime_le`, `archive_le`.

Où : `MoteurSynchronisation::absorberTable` contrôle **toute** ligne poussée avant l'absorbeur propre de sa table (ventes, factures, devis, écritures/pièces, fiches du jour,
couveuse, mouvements, notes, clôtures… sans exception) ; `TableSync::absorber` (absorbeur générique) contrôle aussi, pour les appels directs ;
`DemandesReferentiel` contrôle `saisi_le` de chaque demande. Les écrans du **web** (poste nul `0000…`) y échappent : ils datent leur écriture *après* la ligne qu'ils
remplacent (`max(maintenant, existante + 1 µs)`) et doivent pouvoir remplacer une ligne déjà gelée avant la garde. Un refus d'horloge n'est jamais mémorisé non plus.

`server_now` : l'heure du serveur **à l'instant de la réponse** (connexion, `me`, tirage). `server_time` existait déjà mais il est figé par `until` pendant la pagination
(curseur) : il ne sert pas à mesurer. Le poste lit donc `server_now`.

### 2.2 Ce que fait le poste

- **Il calcule son décalage à chaque synchronisation** : `milieu(demande, réponse) − server_now` (positif : poste en avance), mémorisé (`sync.decalage_horloge_ms`),
  mesuré aussi à la connexion et au test de connexion.
- **Jugement** (`analyserHorloge`) :

  | Écart (poste − serveur) | État | Conséquence |
  |---|---|---|
  | ≤ 2 min en avance, ≤ 5 min en retard | juste | rien |
  | > 2 min et ≤ 5 min en avance | avertissement | message dans la modale de synchronisation et l'onglet Appairage ; l'envoi se fait |
  | **> 5 min en avance** | **bloquant** | **l'envoi est suspendu** (le tirage a lieu) ; saisies et demandes restent en attente, rien n'est perdu ; message clair |
  | > 5 min en retard | retard | avertissement (« vos saisies risquent de perdre contre celles des autres postes ») ; **pas de blocage** |

- **Modale de synchronisation** : l'indicateur de la barre du haut prend l'icône « horloge » et, au clic « synchroniser maintenant », une modale dit l'avertissement.
- **Reprise après correction.** Une saisie faite pendant l'avance est datée du futur *dans la base du poste* ; une fois l'horloge corrigée, le poste **borne** les
  instants de saisie qu'il envoie à l'heure du serveur (estimée par l'écart mesuré à ce cycle), sans toucher à la ligne locale : l'accusé compare toujours l'instant d'origine, le
  tirage suivant rapporte la version du serveur. Sans cette borne, ces lignes seraient refusées pour toujours. Le serveur ne détient ainsi jamais un instant du futur.
- **Si le poste ne peut rien mesurer** (serveur ancien sans `server_now`) : il envoie, le refus `horloge_en_avance` (code) laisse la ligne en attente (`refuseesHorloge`).
- **Injection d'horloge** : `horlogePoste` (`lib/core/sync/identifiant_poste.dart`) est le seul point d'injection du temps (par défaut `DateTime.now`) ; `instantSaisie()` et la mesure
  y passent. Les tests et l'essai réel y simulent le décalage.

## 3. Codes de refus (stables)

| Code | Où | Sens | Le poste |
|---|---|---|---|
| `droit_insuffisant` | `rejected[]` de `POST /api/sync/push` (table entière, ou ligne : écriture d'achat par un caissier, clôture de mois, clôture d'exercice) et `/api/sync/demandes` ; `403` de `factures/reserver` | le compte n'a pas le droit d'écrire cette table / cette ligne / ce type | ligne ou demande **reste en attente**, repart quand le droit existe |
| `horloge_en_avance` | idem | un instant de saisie dépasse l'horloge du serveur de plus de 5 min | ligne ou demande **reste en attente** ; l'envoi se suspend si le poste l'a mesuré |
| *(aucun code)* | idem | refus définitif (donnée invalide, plus récent sur le serveur, stock…) | `conflict` + motif, comme avant |
| `remise_a_zero_inconnue` | `409` du push | le poste ne connaît pas la dernière remise à zéro | inchangé |

## 4. Preuves

- **PHP** (`DroitsEtHorlogeTest`, 19 essais ; `PostesAppairageTest` colonne Droits) : droits annoncés par rôle ; matrice « annoncé = accepté » sur toutes les tables et tous les types ; tirage et
  `me` à jour sans reconnexion ; refus avec code, non mémorisé, rejouable ; +1 h, +2 jours, +2 ans, +6 min refusés, −1 h / −2 jours / 0 / +300 s acceptés, +301 s refusé ;
  aucune ligne gelée ; garde sur ventes, factures, devis, écritures, fiches, mouvements ; écran web exempt.
  Plusieurs essais existants datés du futur (`2999`, `2030`, `2026-11-15`) ont été rendus **relatifs** à maintenant : ils éprouvaient la règle que la garde interdit désormais.
- **Dart, faux serveur** (`droits_et_horloge_poste_test.dart`, 30 essais ; `onglet_appairage_test`, `indicateur_synchro_test`, `migration_v50_droits_test`) : le faux serveur rejoue les deux règles
  (`droits`, `annoncerDroits`, `decalageServeur`, `annoncerHeure`). Poste +1 h, +2 jours, +2 ans, −1 h, +3 min, +6 min, seuils exacts, reprise après correction (aucune ligne gelée,
  l'autre poste gagne ensuite), sans heure du serveur, changement de compte, droits périmés.
- **Mutations** (essais rouges quand on casse) : gating des tables, gating des demandes, code `droit_insuffisant`, code `horloge_en_avance`, suspension d'horloge, borne des instants, seuil `>` / `>=`
  de la tolérance (poste et serveur), mémorisation des droits, garde du moteur. Sur le **vrai serveur** : retirer la garde du moteur *et* celle de l'absorbeur générique fait échouer 21 essais réels
  (retirer l'une seule n'en fait échouer aucun : les deux se couvrent pour les tables à absorbeur générique, comme `clients`).
- **Essai réel** (`bash logialvia_app/outils/essai_vrai_serveur.sh` : **68/68**, dont les 55 d'avant et 13 ajoutés) :
  - chaque compte réel (admin, caissier1, comptable1, animalier1) synchronise exactement ce qu'il peut, **aucune demande en `conflict` à tort**, compteur « en attente de droit » exact ;
  - caissier → administrateur sur le même poste : les demandes en attente de droit partent et atteignent un autre poste ;
  - droit accordé au serveur (rôle ajouté par `artisan tinker`) sans reconnexion : la demande repart ;
  - refus brut avec le code `droit_insuffisant` ; refus brut `horloge_en_avance` (+1 h, +2 jours, +2 ans), +4 min et −1 h acceptés ;
  - poste simulé +1 h / +2 jours / +2 ans : envoi suspendu, rien sur le serveur, reprise après correction, instant du serveur jamais dans le futur, l'autre poste corrige et gagne ; retard −1 h sans blocage ;
    +4 min avertie et envoyée, +6 min suspendue ; décalage recalculé à chaque synchronisation.
  - Trois essais d'avant (modules du caissier, achats du caissier, ventes du comptable) attendaient un `conflict` : ils décrivent maintenant « en attente de droit ».

## 5. Décisions à valider par le client

1. **Tolérance de 5 minutes** (constante `GardeHorloge::TOLERANCE_SECONDES` et `toleranceHorloge`) et **seuil d'avertissement de 2 minutes**. Plus serré = plus de postes suspendus à tort (horloges mal réglées, pas de NTP) ; plus large = fenêtre
   où une saisie en avance gagne contre les autres.
2. **Suspendre l'envoi, pas la saisie.** Un poste en avance de plus de 5 min continue de travailler hors ligne ; ses saisies attendent la correction de l'horloge. Alternative écartée : refuser de saisir.
3. **Borner les instants au lieu de les refuser après correction.** Les saisies faites pendant l'avance sont envoyées datées de l'heure du serveur (leur ordre relatif est perdu, tous les instants au plus égaux à « maintenant »). Alternative : les refuser et demander
   de les ressaisir (perte de travail).
4. **Un compte sans droits n'adopte rien... mais le dit.** Le semis reste en attente (74 demandes pour un caissier) et l'écran le montre ; il part avec le premier compte qui peut. Alternative : ne rien mettre en file avant d'avoir les droits.
5. **Qui peut réparer l'horloge** : seule la gérante, sur le poste (le serveur ne peut pas la corriger). Faut-il un message plus fort (bandeau persistant) pour les postes sans synchronisation depuis longtemps ?
6. **Retard d'horloge** : simple avertissement. Un poste en retard d'une heure perd ses « dernier écrivain gagne » contre les autres postes (la ligne qu'il corrige n'est pas appliquée) : voulu, mais à valider.
7. **Écrans du web exemptés de la garde.** Ils écrivent à l'heure du serveur ; la garde ne vise que les postes.

## 6. Limites

- **Mesure imprécise** : l'écart est mesuré au milieu de l'échange ; un réseau très lent (plusieurs secondes d'aller-retour) fausse la mesure d'autant. L'affichage est arrondi à la minute. À ±5 min près de la tolérance, un poste peut être jugé
  juste par le poste et refusé par le serveur (ou l'inverse) : le refus par code garde alors la ligne en attente.
- **Dernière mesure ancienne** : `aDesSaisiesAEnvoyer()` s'appuie sur la dernière mesure : après correction de l'horloge, l'envoi déclenché par un geste attend la synchronisation de routine (5 min) ou le bouton
  « Réessayer » / « Synchroniser maintenant ». La suspension n'utilise, elle, que la mesure du cycle en cours.
- **Instants imbriqués** : la garde et la borne ne contrôlent que les instants de saisie **au premier niveau** de la ligne (`updated_at`, `horodatage`, `saisi_le`, `supprime_le`, `archive_le`) ; pas ceux d'éventuelles lignes enfants (les lignes de vente, de facture, de
  pièce n'en portent pas).
- **Saisies refusées pour droit avant v50 dans les tables de faits** : réarmées par la migration ; au-delà, un conflit définitif reste un conflit.
- **Droits annoncés au niveau de la table** : `EcrituresTable::peutEcrire` accepte `manage-comptabilite`, `manage-ventes` ou `manage-achats` ; un comptable et un caissier peuvent donc *proposer* des écritures ; les contrôles fins par journal
  (pièce d'une autre origine) restent au serveur et sont de vrais refus (`conflict`).
- **Poste hors de l'essai** : l'écran réel (Flutter) n'est pas rejoué contre le vrai serveur (voir `47h_` §5) ; la modale et l'onglet sont éprouvés en widgets contre le faux serveur.
- **MySQL, réseau réel, volumétrie** : inchangés (`47h_` §5).
- **`app_database.dart`** : version de schéma portée à **50** (réservée) ; les versions 48 et 49 sont celles des autres chantiers.
