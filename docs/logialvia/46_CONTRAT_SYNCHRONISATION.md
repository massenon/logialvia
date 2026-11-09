# 46 — Contrat de synchronisation poste ↔ web (étape P0)

> **Statut : brouillon à valider.** Il classe les **38 tables** du poste (schéma v30) et fixe le format des échanges.
> Règles de fond : `docs/BLUEPRINT_SYNCHRONISATION_MULTIPOSTES.md` d'AgriERP et `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md`.
> Décisions : DV-19 (poste entièrement en UUID), DV-20 (comptes locaux conservés) — voir `45_`.
> **Rien ici n'est implémenté.** Les points marqués **[À TRANCHER]** bloquent l'implémentation de la table concernée.

## 1. Principe

Le **serveur est la vérité**. Le poste travaille hors ligne sur sa base locale, **reçoit** (`pull`) puis **envoie**
(`push`), toujours dans cet ordre. Le poste écrit un **fait** ou une **demande** ; le serveur le rejoue par le même
code que l'écran web, et seul le serveur calcule stock, comptabilité et numéros officiels.

Colonnes de synchronisation communes à toute table synchronisée : `id` (UUID, généré au poste), `device_id` (UUID du
poste qui a saisi), `sync_status` (`pending` · `synced` · `conflict`), `sync_motif` (refus, en français),
`updated_at` (instant de **saisie**, UTC, jamais d'envoi).

## 2. Classement des 38 tables

### 2.1 Jamais synchronisées (restent au poste) — 8 tables

`utilisateurs`, `roles`, `permissions_role` (DV-20 : comptes locaux), `preferences_poste`, `corbeille`,
`messages_editeur`, `audit_logs`, `security_logs`.

> `audit_logs` et `security_logs` restent locaux dans cette première version : le journal du serveur trace les
> envois reçus. Les remonter est une évolution possible.

### 2.2 Référentiels : le serveur gagne, le poste reçoit — 10 tables

`produits_vendables`, `groupes_taxe`, `baremes_ration`, `taux_ration_poids`, `calendrier_prophylaxie`,
`machines_incubateur`, `modules_actifs`, `parametres_entreprise`, `plan_comptable`, `exercice_comptable`.

Le poste ne les envoie pas ; une modification faite au poste (Paramètres Élevage, Catalogue…) part comme **demande**
rejouée par le serveur (`POST /api/sync/demandes`) et redescend au tirage suivant. Un envoi direct est **ignoré et
journalisé**. **[À TRANCHER]** `produits_vendables.stock` est une donnée **dérivée** (ventes, achats) : elle ne doit
pas être écrasée par le référentiel ; proposition : le stock des produits descend avec les mouvements, pas avec la
ligne du produit.

### 2.3 Faits saisis au poste, rejoués tels quels — 13 tables

| Table | Règle |
|---|---|
| `clients`, `fournisseurs` | fait indépendant ; doublon de nom signalé, jamais fusionné en silence |
| `ventes` + `lignes_vente` | **jamais fusionnées** : chaque vente hors ligne est un fait indépendant ; le lot ne se coupe jamais entre une vente et ses lignes |
| `devis` | idem |
| `achats` + `lignes_achat` | idem |
| `fiche_journee` | **dernier écrivain gagne**, upsert sur (`espece`, `date`) sous verrou ; deux postes qui créent le même jour au même instant sont fusionnés |
| `fiche_ventes_jour` | **dérivée** : le serveur l'augmente à partir des ventes reçues, le poste ne l'envoie pas |
| `bandes`, `soins_calendrier`, `infirmerie`, `cycle_couveuse` | dernier écrivain gagne, par UUID |

### 2.4 Mouvements : le serveur les rejoue — 2 tables

`mouvements_intrant` et `intrants`. Pour `mouvements_intrant`, le poste envoie un **mouvement** (entrée, sortie, comptage), jamais un stock. Le serveur le
rejoue par son **point de passage unique** (`AdjustStockAction`) ; le stock de l'intrant redescend avec le tirage.
`intrants` est donc **dérivée** côté stock (référentiel pour code, nom, seuil, unité).

### 2.5 Comptabilité : le poste envoie une demande — 5 tables

`ecriture_comptable`, `notes_annexes`, `clotures_periodiques`, `factures`, `lignes_facture`.

Le poste n'écrit pas dans le grand livre du serveur : il envoie le **fait générateur** (vente encaissée, dépense
saisie, demande de clôture). Le serveur passe l'écriture par son point de passage unique
(`AccountingEntryService::record()`), la numérote et la redescend. Les factures normalisées (e-MECeF) sont
transmises par le serveur (`41_MECEF_EMECEF.md`). **[À TRANCHER]** Tant que le web n'a pas le **même moteur
comptable** que le poste, ces 5 tables restent **hors synchronisation** (le poste garde sa comptabilité locale).

> **Total : 8 + 10 + 13 + 2 + 5 = 38 tables**, soit toutes celles de `AppDatabase` (vérifié le 09/11/2026 contre
> la liste réelle). Le test de couverture de l'implémentation vérifiera que **chaque table figure dans exactement
> une catégorie** : une table oubliée, ou ajoutée plus tard sans être classée, fait échouer le test.

## 3. Numéros et références — Q-SYNC-1 **TRANCHÉE : option B (DV-21, 09/11/2026)**

Ventes (`V-AAAA-NNN`), achats, devis et pièces étaient numérotés au poste : deux postes produiraient la même
référence. **Décision du client : le préfixe de poste reste le numéro officiel** (`V-P2-2026-001`), sans
renumérotation par le serveur : une pièce déjà remise au client ne change jamais de numéro.

- Format : `<lettre de la pièce>-<code du poste>-<année>-<séquence à 3 chiffres ou plus>`, ex. `V-P2-2026-001`,
  `A-P2-2026-014` (achat), `D-P2-2026-003` (devis). La séquence est **continue par poste et par année**.
- **Code du poste** : attribué à l'appairage, **unique au serveur**, stable (ne change pas à la réinstallation d'un
  poste : un nouveau poste reçoit un nouveau code). Un poste jamais appairé garde le code `P0` (poste seul).
- Les références **existantes** (`V-2026-001`) restent valides telles quelles ; seules les nouvelles pièces portent le
  code du poste. Aucune réécriture rétroactive.
- Unicité garantie au serveur par `UNIQUE(reference)` ; un doublon au push est refusé avec son motif (`conflict`).
- **Hors du champ de B** : la numérotation **fiscale** des factures normalisées (`FV-`/`FA-`) reste celle de
  la machine e-MECeF/du serveur ; les **pièces comptables** sont numérotées par le serveur (la comptabilité reste
  une demande, §2.5).

## 4. Format des échanges

Authentification : jeton Sanctum par poste (`43_` §1). Tous les corps sont en JSON, UTF-8.

### 4.1 `GET /api/sync/pull?since=<curseur>&page=<n>`

Réponse : `{ "server_time": "…", "page": n, "last_page": m, "reset_mark": "…", "tables": { "<table>": [ {ligne}, … ] } }`.
`since` est le `server_time` de la **dernière page du tirage précédent** (jamais l'horloge du poste) ; sans
`since`, tirage complet. Seules les tables que le compte a le droit de lire sont servies. Une ligne n'est jamais
servie sans sa pièce (une vente avec ses lignes dans la même page).

### 4.2 `POST /api/sync/push`

Corps : `{ "device_id": "<uuid du poste>", "reset_mark": "…", "tables": { "<table>": [ {ligne}, … ] } }`, tables
**dans l'ordre des dépendances** (clients, produits, ventes, lignes…). Règles : `device_id` = nom du jeton courant,
sinon **403** ; marque de remise à zéro inconnue, **409** ; tout le lot en **une transaction** (rejouée 3 fois sur
interblocage) ; **idempotent par UUID**.

Réponse, table par table : `{ "<table>": { "accepted": ["<uuid>", …], "rejected": [ {"id": "<uuid>", "motif": "…"} ] } }`.
Le poste ne marque `synced` qu'**après** l'accusé ; un refus devient `conflict` avec son motif, jamais d'échec
silencieux ; hors ligne n'est pas une erreur.

### 4.3 Autres appels

`POST /api/auth/login`, `GET /api/auth/me` (appairage, `43_`) · `GET /api/sync/demande` (le poste interroge toutes les
30 s : « synchronise maintenant ») · `POST /api/sync/resynchronisation/acquittement` · `POST /api/sync/demandes`
(modification d'un référentiel faite au poste).

## 5. Critères d'acceptation du contrat

- [ ] Chaque table de `AppDatabase` est dans **exactement une** catégorie du §2 (test automatique).
- [x] Q-SYNC-1 tranchée (option B, DV-21) : la migration des tables de ventes, achats et devis peut démarrer.
- [ ] Le serveur et le poste passent le **même jeu de cas** : essai à deux postes qui vendent hors ligne, se
      reconnectent dans le désordre, et obtiennent la même base ; renvoi d'un lot déjà reçu sans effet ; vente d'un
      poste révoqué refusée ; remise à zéro d'un côté, purge de l'autre.
- [ ] Aucune règle métier n'est recopiée dans le client : le poste envoie des faits, le serveur décide.
