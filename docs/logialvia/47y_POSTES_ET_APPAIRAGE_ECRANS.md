# 47y — Postes & Appairage : les quatre écrans, ce qui est fait et ce qui reste

Référence demandée par le client (fonctionnement décrit pour un projet voisin, **adapté aux noms réels de LogiALVIA** : pas de `agrierp.token`, pas de `device_name` dans les routes — voir `BLUEPRINT_SYNCHRONISATION_POSTES.md` §3).

## Identité d'un poste
Un poste = un **jeton Sanctum** + un **identifiant de poste** (UUID v4 choisi par le poste, `identifiant_poste.dart`) et un **code** `P<n>` attribué par le serveur. Le jeton est dans le coffre du système (`flutter_secure_storage`), jamais en base. Un seul jeton actif par poste ; durée 90 jours. Le serveur lit l'identité du poste dans le **nom du jeton** (`currentAccessToken()->name`), jamais dans la requête : un poste ne peut pas se faire passer pour un autre. **En plus**, le poste envoie son identifiant (`device_id`) et le serveur le recoupe avec le nom du jeton (`PosteDuJeton`, code `poste_different_du_jeton`, 403, rien n'est écrit ni journalisé) : **obligatoire** pour les écritures (`/sync/push`, `/sync/demandes`, `/sync/factures/reserver`), **recoupé s'il est présent** pour les lectures (`/sync/pull`, `/sync/demande`, acquittement) afin que les postes déjà installés, qui ne l'envoyaient pas, continuent de fonctionner.

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
**Carte « Environnement »** : environnement de la construction (`build_windows.bat --env dev|recette|production`, transmis par `--dart-define=LOGIALVIA_ENV`) et adresse proposée à l'appairage : **production = `https://logialvia.digitonpro.com`** ; recette et développement : aucune adresse proposée. L'adresse reste modifiable (`Environnement`, `environnement.dart`).

## Écran 4 — Poste : Synchronisation (Paramètres Généraux > Synchronisation) — FAIT (cohérence : contrôle local)
Quatre blocs :
| Bloc | Contenu |
|---|---|
| **État du poste** | grand compteur **EN ATTENTE** (saisies pas encore envoyées, toutes tables ; doré si > 0, vert « à jour » sinon), dernière réception, dernier envoi, bouton **Synchroniser** |
| **Historique des 10 dernières tentatives** | date, déclencheur (à l'ouverture, automatique, après une saisie, manuel, demande du serveur, à la fermeture, après l'appairage), reçus, envoyés, refusés, statut (pastille ; le message du rapport en infobulle) ; bouton **Exporter le journal** (CSV `;`, UTF-8 avec BOM, dans `Documents\LogiALVIA\Journal`) |
| **Refusés par le serveur** | lignes `conflict` de toutes les tables : table, désignation (référence, nom… sinon identifiant), **motif** ; filtres par table ; **Remettre en file** (une ligne), **Tout remettre en file** / « Remettre la table en file » ; la remise en file lance aussitôt une synchronisation |
| **Cohérence** | bouton **Vérifier la cohérence** : recompte, table par table, les lignes du poste par état (en attente, synchronisées, refusées) ; « Conforme » ou « N écart(s) » |

**Le journal** est une table locale neuve (`journal_synchronisation`, **schéma poste 51 → 52**, migration idempotente testée) : jamais synchronisée, 200 cycles gardés, deux « hors ligne » de suite ne font qu'une ligne, un poste non appairé ne journalise rien. Code : `core/sync/depot_journal_synchronisation.dart`, `depot_etat_synchronisation.dart`, `administration/presentation/viewmodels/synchronisation_view_model.dart`, `widgets/onglet_synchronisation.dart`.

### Limite assumée : la cohérence est LOCALE
« Vérifier la cohérence » **ne compare pas le contenu du poste avec celui du serveur**. Une comparaison exacte table par table suppose, pour chaque table synchronisée, de savoir comment le serveur compte ses lignes (pierres tombales, lignes servies à d'autres postes, tables propres au poste comme le stock). Aucun point d'API de comptage n'existe ; en inventer un qui donnerait de faux écarts serait pire que de ne pas l'avoir. À construire si le client le demande : un point d'API de comptage + un test d'accord sur le vrai serveur (`essai_vrai_serveur.sh`).
