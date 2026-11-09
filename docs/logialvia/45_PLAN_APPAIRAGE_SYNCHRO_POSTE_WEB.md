# 45 — Plan d'exécution : web Laravel, appairage et synchronisation du poste

> **Statut au 08/11/2026.** Ce fichier est l'état réel du chantier, pas une spécification : la spécification
> détaillée est `43_APPAIRAGE_SYNCHRO_MODALE_ALERTES.md` (et le blueprint d'AgriERP). Il enregistre ce qui est
> fait, ce qui est décidé, ce qui bloque, et l'ordre de travail.

## 1. État du poste Flutter

**Terminé** : les 8 filières (dont escargots et bovins), ration en % du poids vif (bovins, poissons-chats), dose du
calendrier de prophylaxie, bouton Valider des repères, numérotation BAC et PARC, catalogue rattaché aux filières,
visites guidées, manuel. Schéma v30, 1087 tests.

**Pas terminé** : l'**appairage** et la **synchronisation** (envoi, réception, descente des référentiels). Le poste
n'en contient aucun code : seuls subsistent un message du Splash et un badge décoratif de la barre du haut. Le
poste ne peut pas être achevé avant que le serveur existe, puisqu'il n'a personne à qui parler.

## 2. Décisions du client (08/11/2026)

| Id | Décision | Conséquence |
|---|---|---|
| **DV-19** | Le poste migre **entièrement en UUID** (clés générées au poste). | Migration du schéma poste (v31) : chaque table reçoit un UUID, les clés étrangères sont réécrites. Voir §4. |
| **DV-20** | Le poste **conserve ses comptes locaux**. L'appairage ne sert qu'à la synchronisation. | Les étapes A5 (PIN local) et A6 (remplacer `ConnecterUtilisateurUseCase`) de `43_` §1.2 **ne sont pas appliquées**. Deux référentiels de comptes à tenir alignés (§5). |
| **DV-21** | **Q-SYNC-1 : option B.** Le préfixe de poste reste le numéro officiel des ventes, achats et devis (`V-P2-2026-001`), sans renumérotation par le serveur. | Code de poste attribué à l'appairage ; format et règles : `46_` §3. Les anciennes références restent valides. |

Décidé aussi : le web Laravel vit dans `logialvia_laravel/` de ce dépôt ; **le code Dart est la base**, le Laravel
lui est conforme (jetons de design, libellés, règles de calcul) ; si `prototype_html` est fourni plus tard, il prime
(DV-18).

## 3. Blocage actuel (diagnostic corrigé le 09/11/2026)

`composer create-project` ne peut pas télécharger les archives de ses dépendances. Les appels à
`api.github.com` et `codeload.github.com` répondent **403**, avec ce message : « *GitHub access to this repository is
not enabled for this session* ». **Ce n'est pas une règle de liste d'hôtes** : une passerelle de la session ne sert
que les dépôts rattachés à la session, et Composer en réclame des centaines (`laravel/framework`, `symfony/*`…).

> Erreur de diagnostic à ne pas répéter : le 08/11 des hôtes ont été ajoutés à un environnement personnel
> (aujourd'hui nommé « GitHub »). **Cela ne change rien** au 403 ; cet environnement est inutile et peut être
> supprimé dans les réglages.

**Voie retenue** : installer par **clonage git** (`composer … --prefer-source`), que le proxy autorise pour les dépôts
publics. C'est lourd (plusieurs Go de dépôts pour un squelette, les historiques complets étant clonés) : un
garde-fou arrête l'installation si l'espace libre passe sous 6 Go. `vendor/` n'est jamais versionné.

**Résultat (09/11/2026)** : l'installation par clonage a réussi (environ 7 Go le temps du clonage, ramenés à 0,9 Go
en supprimant les `.git` de `vendor/` et le cache Composer). Il faut le refaire après chaque `composer require`.

**Si l'installation échoue** : installer sur le poste du client ou une machine avec accès normal à Packagist, puis
pousser le dossier sans `vendor/`. Les travaux qui ne dépendent pas du réseau (migration UUID du poste, contrat de
synchronisation) avancent en attendant.

## 6b. Ce que W2 a livré, et ses limites

**Serveur** (`logialvia_laravel/`, 89 tests dont chaque garde-fou vérifié par mutation) :

- `POST /api/auth/login {identifiant, password, device_name}` : `device_name` = UUID du poste (refusé sinon) ; un seul
  jeton par poste (se reconnecter supprime l'ancien) ; 90 jours ; limiteur 5/min par identifiant et adresse ; compte
  désactivé refusé avec son motif ; identifiant inconnu et mot de passe faux donnent le même message.
- **Code de poste** `P1`, `P2`… attribué à l'appairage, stable (DV-21), table `postes`.
- `GET /api/auth/me`, `POST /api/auth/logout`, `POST /api/auth/mot-de-passe` (seule action permise avec un mot de
  passe temporaire ; elle coupe les jetons des autres postes).
- `POST /api/parametres/postes/revoquer` (droit `manage-users`) : tous les jetons du poste, tous comptes ; le poste
  reçoit 401 au contact suivant. Journal d'audit (`api.login`, `login.failed`, `sync.appairage_revoque`…).
- **Le jeton dit qui parle** : le `device_id` du push doit être le nom du jeton courant, sinon 403, rien écrit, rien
  journalisé. `GET /api/sync/pull` et `POST /api/sync/push` répondaient 501 à l'issue de W2 ; le moteur est livré par W3 (`46_` §6).

**Web** : connexion (mêmes règles et messages que l'API), changement de mot de passe obligatoire, et la page
**Postes & Appairage** (`/parametres/postes`, droit `manage-users`, revérifié dans chaque méthode qui écrit) :
liste (code, poste, utilisateur, appairé le en heure du Bénin, dernier contact en français, état), révocation par
modale. Tableau au-dessus de 640 px, cartes en dessous. Vérifié en navigateur aux trois tailles.

**Limites connues** : la coque web (barre latérale, modules) est **provisoire**, elle sera convertie du Dart avec le
premier module ; la page est une route propre au serveur, l'onglet « Postes & Appairage » de Paramètres Généraux
viendra avec cet écran ; pas encore d'écran de gestion des utilisateurs (création, désactivation, mot de passe
temporaire).

## 4. Constats techniques sur le poste (à connaître avant la migration UUID)

1. **22 fichiers de tables** déclarent des identifiants entiers auto-incrémentés (ventes lignes, fiches, soins,
   bandes, cycles de couveuse, clients, produits, fournisseurs, écritures, journaux…). Ces entiers circulent dans
   les entités, les dépôts, les ViewModels, les écrans et les tests : la migration touche le code de tout le poste,
   pas seulement le schéma. À faire **table par table**, chaque palier avec ses tests et sa migration vérifiée sur
   une base de départ.
2. **Les numéros de pièces sont fabriqués au poste** : ventes `V-AAAA-NNN`, achats, devis, factures `FV-`/`FA-`,
   pièces comptables (`prochainNumeroPiece`). Avec deux postes, **deux ventes recevraient la même référence**.
   Le blueprint exige que les compteurs soient **attribués par le serveur** (jamais inventés au poste).
   **Q-SYNC-1 tranchée (DV-21, option B)** : le préfixe de poste reste le numéro officiel, voir `46_` §3.
3. **Les écritures comptables et les clôtures** sont calculées au poste : le blueprint veut que le poste envoie une
   **demande** que le serveur rejoue par son point de passage unique. Cela suppose d'abord que le web ait le même
   moteur comptable que le poste.
4. La route d'authentification locale (`ConnecterUtilisateurUseCase`) reste inchangée (DV-20).

## 4b. Écarts connus entre le poste et les décisions validées (à corriger au poste)

Le serveur suit les **décisions validées** ; le poste doit s'y aligner. Ces écarts sont **déclarés** dans le test de
conformité des droits (`tests/Feature/ConformiteDroitsDartTest.php`), qui échoue à tout autre écart :

| Écart | Décision | Poste actuel | À faire au poste |
|---|---|---|---|
| Le caissier n'a plus accès à `/inventaire` | DV-06 | `permission_service.dart` l'autorise (« arbitrage de la Gérante », annulé) | retirer `/inventaire` du caissier et de sa barre latérale |
| Le caissier consulte et réimprime les factures, sans annuler ni créer d'avoir | DV-06 | accès complet à `/factures-mecef` | limiter les gestes de l'écran au rôle |
| 4 rôles dont `comptable` | DV-07 | 3 rôles (`role_utilisateur.dart`) | ajouter le rôle `comptable` et ses routes |

## 5. Risque lié à DV-20 : deux référentiels de comptes

Le poste garde ses comptes (identifiant, mot de passe haché, rôle) ; le web aura les siens. L'appairage ouvre une
session serveur avec un compte **web** (`POST /api/auth/login {identifiant, password, device_name}`). Pour que la
synchronisation respecte les droits table par table, il faut une règle d'alignement : proposition **provisoire** —
l'appairage se fait avec un compte web de même identifiant que le compte local de l'administrateur, et les rôles
(`admin`, `comptable`, `caissier`, `animalier`) portent les mêmes noms des deux côtés. Les comptes locaux ne
descendent pas du serveur et ne sont pas poussés vers lui (hors périmètre de la synchronisation).

## 6. Ordre de travail

| # | Étape | Dépend de | État |
|---|---|---|---|
| W0 | Squelette Laravel 12 + jetons de design copiés du Dart + test de conformité Tailwind↔Dart | installation par clonage git (§3) | **fait** (09/11/2026) : Laravel 12.71, Livewire 3.8, Sanctum 4.3, Spatie Permission 7.4, DomPDF 3.1, Tailwind 3.4 ; test de conformité vérifié par mutation |
| W1 | Modèle UUID, rôles, modules actifs, paramètres | W0 | **fait** (09/11/2026) : utilisateurs UUID + suppression logique, jetons Sanctum et rôles Spatie en UUID, 4 rôles et 22 droits, 5 modules désactivés, paramètres (ligne unique), premier administrateur par variable d'environnement ; tests de conformité des droits et des valeurs par défaut au Dart (31 tests, vérifiés par mutation) |
| W2 | API d'appairage (login par poste, jeton, révocation) + écran web « Postes & Appairage » | W1 | **fait** (09/11/2026) : voir §6b |
| W3 | Contrat et moteur `pull`/`push` serveur, essai multipostes | W2 | **fait** (09/11/2026) pour 3 tables (référentiels + clients), 129 tests, mutations vérifiées ; voir `46_` §6. Reste W3b (demandes, acquittement, remise à zéro) |
| P0 | **Contrat de synchronisation** écrit (tables, ordre, règles par donnée) | — | à faire, sans réseau |
| P1 | Poste : migration UUID par paliers (DV-19) et références à préfixe de poste (DV-21) | — | à faire, sans réseau |
| P2 | Poste : appairage (identifiant de poste, adresse, jeton au coffre, onglet Appairage) | W2 (ou faux serveur) | en attente |
| P3 | Poste : moteur de synchronisation (pending, envoi, réception, descente) + bouton et modale | W3 (ou faux serveur) | en attente |
| W4+ | Écrans web par module, conformes au Dart | W1 | en attente |

Règle : chaque étape se termine par l'analyse, la suite de tests complète et un commit ; rien n'est déclaré fait
sans avoir tourné.
