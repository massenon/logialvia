# 47y — Postes & Appairage : les quatre écrans, ce qui est fait et ce qui reste

Référence demandée par le client (fonctionnement décrit pour un projet voisin, **adapté aux noms réels de LogiALVIA** : pas de `agrierp.token`, pas de `device_name` dans les routes — voir `BLUEPRINT_SYNCHRONISATION_POSTES.md` §3).

## Identité d'un poste
Un poste = un **jeton Sanctum** + un **identifiant de poste** (UUID v4 choisi par le poste, `identifiant_poste.dart`) et un **code** `P<n>` attribué par le serveur. Le jeton est dans le coffre du système (`flutter_secure_storage`), jamais en base. Un seul jeton actif par poste ; durée 90 jours. Le serveur lit l'identité du poste dans le **nom du jeton** (`SyncController::poste` : `currentAccessToken()->name`) et non dans un paramètre de la requête : un poste ne peut pas se faire passer pour un autre. Contrairement au projet voisin, il n'y a pas de `device_id` à recouper.

## Écran 1 — Web : Postes & Appairage (`/parametres/postes`, droit `manage-users`) — FAIT
| Action | Effet |
|---|---|
| **Actualiser** | recharge la liste et l'état de chaque poste |
| **Demander** (un poste) / **Synchroniser tous les postes** | dépose une demande de synchronisation (valable 60 min) ; le poste, qui interroge le serveur toutes les 30 s, synchronise sous 30 s (`DemandesSynchronisationService::demander`) |
| **Renvoyer** (un poste) / **Renvoyer vers tous les postes** | confirmation, puis le poste repart d'un **tirage complet** à son prochain contact (`renvoyer`) |
| **Révoquer l'appairage** | confirmation, puis suppression de tous les jetons du poste, journal d'audit ; le poste reçoit 401 et se suspend |

Badges d'état par poste : *Appairé / Révoqué / Sans jeton*, plus **Synchro demandée** et **Renvoi complet en attente** tant que le poste n'a pas servi la demande. Colonnes : code, poste, dernier utilisateur, droits, appairé le, dernier contact. Garde : `tests/Feature/Web/PostesAppairageTest.php` (27 essais).

Routes d'API correspondantes (déjà existantes) : `POST /api/parametres/postes/synchroniser`, `…/renvoyer`, `…/revoquer`.

## Écran 2 — Web : modale de synchronisation (icône de la barre du haut) — EXISTANT, SANS ACTIONS
Liste des postes avec leur état (en ligne, joint récemment, sans contact, révoqué) et lien vers « Postes & Appairage ». Les actions Demander/Renvoyer sont **sur l'écran Postes & Appairage**, pas dans la modale.

## Écran 3 — Poste : Appairage (Paramètres Généraux > Appairage) — FAIT, SAUF « Environnement »
Cartes : *Ce poste* (code, identifiant, serveur, compte, date d'appairage) ; *Droits et horloge* (+ « Réessayer ») ; **Synchro automatique** (nouveau : intervalle de la routine 1, 2, 5, 10, 15 ou 30 minutes, 5 par défaut, mémorisé et appliqué tout de suite) ; *Connexion au serveur* (Synchroniser maintenant, **Tester la connexion** = `GET /api/auth/me`, Déconnecter ce poste, qui ramène à l'appairage) ; formulaire d'appairage (adresse, identifiant, mot de passe) quand le poste n'est pas appairé.
**Pas de carte « Environnement »** : il n'y a pas d'adresse ni d'environnement compilés dans le poste (`47w_`).

## Écran 4 — Poste : Synchronisation — PARTIEL
Existe : modale d'état de la barre du haut (dernier cycle, horloge, « Synchroniser maintenant »), compteur « en attente de droit » dans l'onglet Appairage.
**N'existe pas (à construire, voir ci-dessous)** : le tableau des **10 dernières tentatives** (date, reçus, envoyés, refusés, statut) avec « Exporter le journal » ; la liste des **refusés par le serveur** avec motif, « Remettre en file » et filtres par table ; le **contrôle de cohérence** table par table.

### Pourquoi ce n'est pas fait dans ce lot
Le poste ne **garde aucune trace** de ses tentatives : le rapport du dernier cycle est en mémoire (`PlanificateurSynchronisation.dernierRapport`) et les refus ne sont pas listés par ligne. Construire ces trois blocs exige une **nouvelle table de journal** (schéma poste 51 → 52, migration idempotente testée, `build_runner`), l'enregistrement de chaque cycle par le moteur, la mise en file des refusés (`conflict` → `pending`), et un contrôle de cohérence (comparer, table par table, les effectifs poste/serveur, ce qui demande un point d'API de comptage). C'est un lot à part : **à valider avant** (voir la question posée au client).
