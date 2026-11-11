# ESSAIS_EN_PRODUCTION_ET_REINITIALISATION — Essayer sans polluer l'exploitation, et réinitialiser

Ce document dit **ce qui existe réellement** (code web, code poste, scripts) pour faire des essais et pour remettre des données à
zéro, et **quels garde-fous existent vraiment**. Principe directeur : **les essais ne se font jamais sur la base d'exploitation**.
Les deux moyens sûrs du dépôt sont des bases jetables (§1 et §2). La réinitialisation sur une base en service est possible
(§4), mais elle est irréversible hors sauvegarde.

Sources : `47h_PREUVE_VRAI_SERVEUR.md`, `47n_TESTS_NAVIGATEUR.md`, `47r_MYSQL_ET_RESEAU_REEL.md`, `47u_ADMINISTRATION_PARITE.md`,
`docs/F8_Module_Parametres_Administration.md`, et le code cité. Liés : `GUIDE_DEPLOIEMENT.md`, `INSTALLATION_LOCALE.md`,
`CODE_DE_SECOURS_ADMINISTRATEUR.md`.

---

## 1. Essais sur le serveur sans toucher à l'exploitation : base jetable

Aucun essai ne doit utiliser le `.env` de production. Les trois mécanismes du dépôt créent leur propre base.

| Moyen | Base utilisée | Ce qui est recréé | Commande |
|---|---|---|---|
| Tests PHP | SQLite **en mémoire** (`phpunit.xml` : `DB_CONNECTION=sqlite`, `DB_DATABASE=:memory:`) | rien de persistant ; 83 fichiers de test utilisent `RefreshDatabase` | `php artisan test` |
| `e2e/lancer.sh` | SQLite jetable `/tmp/lv-e2e/e2e.sqlite` (dossier réglable par `LV_DOSSIER`), recréée à chaque lancement | `migrate:fresh --seed` + jeu de données `e2e/donnees.php` | `bash logialvia_laravel/e2e/lancer.sh` |
| `essai_vrai_serveur.sh` | SQLite jetable `/tmp/lv/essai.sqlite` (ou MySQL/MariaDB `lv_essai`, **recréée**) | `migrate:fresh --seed`, comptes d'essai, serveur local port 8765 | `bash logialvia_app/outils/essai_vrai_serveur.sh` |

### 1.1 `e2e/lancer.sh` (écrans web, vrai navigateur)

Défini par `47n_` : 52 scénarios Playwright/Chromium, base SQLite jetable, `npm run build` (sauf `SANS_BUILD=1`), serveur sur le port
8799, jeu de données passant par les **services** du serveur (ventes, achats, fiches : écritures comptables cohérentes). Le script
fixe lui-même `DB_CONNECTION=sqlite`, `DB_DATABASE` (fichier jetable), `ADMIN_INITIAL_PASSWORD`, `SESSION_DRIVER=file`,
`CACHE_STORE=file`, `APP_URL` : il **ne lit pas** la base du `.env`. Il écrit dans `/tmp` et lance `php artisan serve`.

Comptes d'essai (mot de passe `EssaiPoste-2026!`) : `admin1`, `comptable1`, `caissier1`, `animalier1`, `temporaire1` (mot de passe
temporaire). Jeu de données : 8 produits, 6 intrants, 5 clients, 3 fournisseurs, 3 achats, 3 ventes, 12 jours de fiches goliaths et
pintades, un poste appairé, tous les modules actifs (`47n_` §1).

Garde-fou sur la garde de performance : `LV_SCRIPT=e2e/performance.mjs bash logialvia_laravel/e2e/lancer.sh` (même base jetable). La
mesure d'un serveur **en ligne** est en lecture seule et distincte : `bash logialvia_laravel/outils/mesure_performance.sh https://domaine`
(charge la page de connexion et, avec un identifiant, le tableau de bord ; avec un identifiant il se connecte, ce qui laisse une
trace `web.login` au journal d'audit ; aucune donnée métier n'est créée par le script).

### 1.2 `essai_vrai_serveur.sh` (poste ↔ vrai serveur)

Défini par `47h_` §1 : base jetable neuve (migrations + seeders), comptes `admin1…admin150`, `caissier1`, `comptable1`,
`animalier1` (mot de passe d'essai `EssaiPoste-2026!`), `REMISE_A_ZERO_ACTIVEE=true`, `php artisan serve --port=8765`, puis
`flutter test test/integration/serveur_reel_test.dart` (74 essais selon `CLAUDE.md`, ignorés sans `LOGIALVIA_SERVEUR`).
`ESSAI_RESEAU=1` ajoute le mandataire réseau (`47r_` §3). `LV_BASE=mysql|mariadb` exige `LV_MYSQL_USER` etc.

**Piège réel** : avec `LV_BASE=mysql`, le script exécute `DROP DATABASE IF EXISTS` puis `CREATE DATABASE` sur la base nommée par
`LV_MYSQL_BASE` (défaut `lv_essai`). **Rien ne vérifie que ce n'est pas la base d'exploitation** : ne jamais renseigner
`LV_MYSQL_BASE`, `LV_MYSQL_HOST` ou `LV_MYSQL_USER` avec les valeurs de la production. Même règle pour
`DB_CONNECTION=mysql php artisan test` (`47r_` §2.5) : n'exporter ces variables que vers une base d'essai.

### 1.3 Ne pas lancer ces scripts sur le serveur de production

Les scripts utilisent `migrate:fresh` et écrivent dans `/tmp` ; ils sont faits pour un poste de développement
(`INSTALLATION_LOCALE.md` §5). Le dépôt n'offre aucun mécanisme qui les empêche d'être lancés sur un serveur de production : seule
la discipline (et les variables d'environnement qu'ils posent eux-mêmes, qui remplacent celles du `.env`) protège la base. Aucune
instruction du `.env` de production ne doit être exportée dans le shell qui les lance.

### 1.4 Un second environnement d'essai à côté de la production (suggestion)

Le dépôt ne fournit ni procédure ni script de « recette » en ligne. Si le client veut essayer sur un serveur réel, la solution
cohérente avec le code est une **seconde installation indépendante** (autre sous-domaine, autre base, autre `.env`, `APP_KEY`
distincte), déployée selon `GUIDE_DEPLOIEMENT.md` — et **jamais** un poste appairé aux deux. Un poste n'a qu'une adresse de
serveur à la fois (champ « Adresse du serveur », onglet « Appairage »).

## 2. Comptes d'essai

- Les comptes `admin1`, `caissier1`, etc. n'existent **que** dans les bases jetables des scripts ci-dessus. Ne pas les créer en
  production : leur mot de passe est écrit dans le dépôt.
- En production, le seul compte semé est celui de `AdminSeeder` (`ADMIN_INITIAL_USERNAME`, mot de passe temporaire exigeant un
  changement, voir `CODE_DE_SECOURS_ADMINISTRATEUR.md` §1.1). Les autres comptes se créent depuis **Paramètres généraux > Gestion
  Utilisateurs** (`app/Livewire/GestionUtilisateurs.php`) ; un compte créé ou réinitialisé au web a un mot de passe temporaire.
- Pour essayer les droits, utiliser les quatre rôles réels (`admin`, `comptable`, `caissier` = Agent de Vente, `animalier` = Agent
  d'Élevage : `config/logialvia.php`) sur la base jetable, pas sur la production.
- Les données d'un compte supprimé vont à la Corbeille (suppression logique) ; l'identifiant reste réservé (`47u_` §2).

## 3. Ce qui protège réellement l'exploitation (garde-fous réels)

| Garde-fou | Où | Portée |
|---|---|---|
| `REMISE_A_ZERO_ACTIVEE=false` par défaut | `config/logialvia.php:136-139` | verrou 1 de la remise à zéro **du serveur** |
| Mot exact `REMETTRE A ZERO` | `config/logialvia.php` (`remise_a_zero.mot`), `app/Services/RemiseAZeroService.php` | verrou 2 ; un mot faux est refusé et **audité** (`sync.remise_a_zero_refusee`) |
| Droit `manage-parametres` | `routes/api.php` (`/parametres/remise-a-zero`) | rôle `admin` seul (`config/logialvia.php`, `role_permissions`) |
| Audit `sync.remise_a_zero` | `RemiseAZeroService.php` | trace de qui et du nombre de lignes supprimées |
| Mode « Données de Test » (poste) | Modules Actifs, `parametres_generaux_screen.dart` | **faux par défaut** ; sans lui, personne (administrateur compris) ne peut réinitialiser ni peupler le poste |
| Rôle administrateur (poste) | `corbeille_view_model.dart` (`reinitialiser`, `peuplerDemonstration`) | refus « Seule une administratrice peut réinitialiser les données » |
| Journaux d'audit **préservés** par les deux remises à zéro | `service_reinitialisation.dart`, `RemiseAZeroService.php` | l'effacement n'efface pas sa trace |
| Dernier administrateur protégé | `UtilisateursService.php` (web), `parametres_generaux_view_model.dart` (poste) | ne peut être supprimé (ni désactivé ni rétrogradé au web) |

Ce qui **n'est pas** protégé : `php artisan migrate:fresh` (aucun `prohibitDestructiveCommands` dans le dépôt ; Laravel demande
seulement une confirmation en `APP_ENV=production`, que `--force` contourne) ; `db:wipe`, `migrate:rollback` ; la suppression
directe par SQL. Ils ne sont jamais à utiliser sur la base d'exploitation.

## 4. Réinitialiser : ce qui existe, côté serveur et côté poste

**Point essentiel : le web n'a pas d'écran de réinitialisation.** L'onglet « Données de Test » des Paramètres généraux web est une
page d'information (`resources/views/livewire/parametres-generaux.blade.php`, bloc `data-onglet="au-poste"`) : « La remise à zéro
et la préparation de données d'essai se font uniquement sur le poste, sous son verrou « Données de Test »… rien ne s'y fait depuis
le web ». L'indicateur « Mode « Données de Test » » du web est en lecture seule. Le serveur n'a qu'une **API** de remise à zéro
(§4.2), que **le poste n'appelle pas** (aucune occurrence de `remise-a-zero` dans `logialvia_app/lib`).

### 4.1 Poste : onglet « Données de Test » (réinitialisation locale)

Chemin : **Paramètres Généraux > Modules Actifs** (interrupteur « Mode « Données de Test » ») puis onglet **« Données de Test »**
(`onglet_donnees_test.dart`, service `ServiceReinitialisation`).

- **Double verrou** : mode activé **et** compte administrateur. Message du verrou fermé : « Onglet verrouillé… fermé par défaut pour
  qu'une exploitation en service ne puisse pas être remise à zéro par accident ». Le texte de l'interrupteur demande de le refermer
  « dès la fin de la période d'essai ».
- **Aperçu réel** : la modale affiche le **nombre de lignes** par table avant d'effacer (`apercu()`, qui ne modifie rien) et rappelle :
  opération « irréversible », « elle ne passe pas par la corbeille », « Générez une sauvegarde avant, depuis l'onglet Sauvegardes ».
- **Effacé** (`ServiceReinitialisation.tablesOperationnelles`) : lignes de vente, ventes, devis, clients, lignes d'achat, achats,
  **fournisseurs**, mouvements d'intrant, mouvements de produit, écritures comptables, notes annexes, clôtures périodiques, fiches de
  ventes du jour, fiches journalières, cycles de couveuse, machines d'incubateur, bandes, soins, infirmerie, corbeille.
- **Conservé** : comptes, rôles, permissions, paramètres de l'entreprise, modules actifs, préférences du poste, barèmes, calendriers de
  prophylaxie, catalogue (produits), intrants, groupes de taxe, plan comptable et exercices, **journaux d'audit**.
  (`docs/F8_Module_Parametres_Administration.md` § « Onglet Données de Test » cite encore les fournisseurs comme conservés ; **le code
  les efface** : c'est lui qui fait foi.)
- **Transaction unique**, puis les seeders de référence sont rejoués pour garantir un exercice comptable ouvert.
- **Trace** : une entrée d'audit `reinitialisation` (qui, nombre de lignes, tables) est écrite **après** le vidage.
- **« Peupler un mois de démonstration »** (même onglet, même double verrou) : écrit 30 jours d'activité fictive (clients, ventes,
  stocks, fiches, couveuse, soins) **par les mêmes chemins que la saisie réelle** ; la modale précise qu'elles « s'ajoutent à ce qui
  existe déjà » et que « Réinitialiser les données » est le seul moyen de les retirer.

**Précautions réelles (déduites du code, non essayées sur poste appairé)** :

- `ServiceReinitialisation` n'utilise que la base locale (aucun appel réseau) : **la réinitialisation d'un poste appairé ne vide pas le
  serveur**. Le dépôt ne documente pas ce qui arrive aux données d'un poste réinitialisé puis resynchronisé avec un serveur qui les
  détient encore ; ne pas réinitialiser ni peupler de données fictives un poste **appairé à la production**. Pour essayer, utiliser un
  poste **non appairé** (le poste fonctionne seul, hors ligne : onglet « Appairage », `onglet_appairage.dart`).
- Si un poste appairé envoyait des données fictives, elles se mêleraient aux vraies côté serveur ; la seule voie de retrait
  prévue côté serveur est la remise à zéro du §4.2, qui efface **toute** l'activité.

### 4.2 Serveur : API `POST /api/parametres/remise-a-zero`

Seule remise à zéro du serveur (`app/Services/RemiseAZeroService.php`, `PostesController::remiseAZero`). Elle n'a pas d'écran.

Conditions, toutes requises :

1. `REMISE_A_ZERO_ACTIVEE=true` dans l'environnement du serveur (sinon : « La remise à zéro est désactivée sur ce serveur. » ; HTTP 403) ;
2. un jeton d'un compte avec le droit `manage-parametres` (rôle `admin`) et sans mot de passe temporaire en attente
   (middleware `mdp.change`, `routes/api.php`) ;
3. le corps JSON `{"confirmation": "REMETTRE A ZERO"}` exact (sinon refus audité, rien n'est effacé).

Effets, dans **une transaction** (`RemiseAZeroService`) :

- supprime les lignes de toutes les tables de **faits** de `config/logialvia.php` (`sync.tables`) dans l'ordre inverse des
  dépendances : achats, clients, fournisseurs, ventes, factures, devis, mouvements d'intrant et de produit, effets de stock, fiches
  journalières, ventes du jour, bandes, incubateurs et lots de couveuse, soins, infirmerie, écritures, notes annexes, clôtures
  périodiques, clôture d'exercice, messages à l'éditeur ;
- **conserve** : comptes, rôles, référentiels (modules, paramètres, produits, intrants, barèmes, taux, calendriers, taxes, plan
  comptable, exercices) et journal d'audit ;
- rouvre les exercices clos (`is_cloture=false`), car les écritures qu'ils verrouillaient viennent d'être effacées ;
- pose une **nouvelle marque** (`marque_remise_a_zero`) : un poste qui envoie l'ancienne marque reçoit un 409
  `remise_a_zero_inconnue` ; à son prochain tirage, il apprend la nouvelle marque, **purge ses propres tables d'activité**, compte ce
  qu'il perd (saisies non envoyées) et repart d'un tirage complet (`moteur_synchronisation.dart:553-570`) ; les curseurs de tirage des
  postes et les demandes de synchronisation sont remis à zéro ;
- écrit l'audit `sync.remise_a_zero` (compte des lignes supprimées par table).

Exemple (à n'utiliser que sur un serveur d'essai ; `AuthController::login` crée un « poste » d'appairage du `device_name` donné,
révocable ensuite depuis `/parametres/postes`) :

```bash
# 1. Obtenir un jeton (un UUID quelconque comme device_name) : la réponse contient "token"
curl -s -X POST https://serveur-d-essai/api/auth/login -H 'Accept: application/json' -H 'Content-Type: application/json' \
  -d '{"identifiant":"admin","password":"…","device_name":"00000000-0000-4000-8000-000000000001"}'

# 2. Remise à zéro (REMISE_A_ZERO_ACTIVEE=true requis côté serveur)
curl -s -X POST https://serveur-d-essai/api/parametres/remise-a-zero -H 'Accept: application/json' \
  -H 'Authorization: Bearer LE_JETON' -H 'Content-Type: application/json' -d '{"confirmation":"REMETTRE A ZERO"}'
```

En production, laisser `REMISE_A_ZERO_ACTIVEE` à `false` (ou absente). Pour essayer la remise à zéro, ne l'activer **que** sur
l'installation d'essai (§1.4). Ne jamais l'activer « un moment » sur la production : le seul retour en arrière est la restauration
d'une sauvegarde de base (§5).

### 4.3 Corbeille (retour en arrière partiel, avant suppression définitive)

- **Web** : onglet « Corbeille » (`app/Livewire/CorbeilleWeb.php`, `CorbeilleService`). Liste les éléments portant une pierre tombale
  (comptes, clients, fournisseurs, lots, incubateurs, produits, barèmes, taux, échéances), **restaure** (droit d'écriture de
  l'élément ; comptes réservés à l'administrateur) ; **purge définitive : comptes seulement, administrateur seul**. La restauration
  redescend vers tous les postes (`47u_` §3).
- **Poste** : onglet « Corbeille » (`onglet_corbeille.dart`, `service_archivage.dart`) ; « vider la corbeille » est réservé à
  l'administrateur (`purgerTout`).
- Les **écritures comptables** n'y sont pas : on les contre-passe (ex. préfixe `ANN-`, `47n_` §2). La réinitialisation, elle,
  **ne passe pas par la corbeille** et vide celle-ci.

## 5. Sauvegarde et restauration : le vrai filet de sécurité

### 5.1 Poste Windows

Onglet **« Sauvegardes »** (`onglet_sauvegardes.dart`, `ServiceSauvegarde`, `ServiceRestauration`) :

- « Générer une sauvegarde » : copie de la base complète dans `Documents\LogiALVIA\Sauvegardes` (hors du dossier de données, pour
  survivre à une désinstallation) ; « Exporter une table » en CSV ; liste des fichiers ; suppression d'un fichier.
- **Restaurer** : le fichier choisi est **mis en attente** et appliqué au **prochain démarrage**, avant l'ouverture de la base. Quatre
  contrôles avant tout remplacement (signature SQLite, `PRAGMA integrity_check`, signature LogiALVIA, version non plus récente que le
  logiciel). **La base précédente est conservée** dans le dossier des sauvegardes (`service_restauration.dart`, `47u_`/`F8` §
  « Restauration d'une sauvegarde »).
- À faire **avant** toute réinitialisation (la modale le rappelle).

### 5.2 Serveur

- **Base de données** : sauvegarde à la charge de l'hébergement (`47u_` §5) ; commande conseillée `mysqldump --single-transaction`
  (`47r_` §5.3) ; modèle de cron facultatif dans `LISTE_DES_CRON_JOBS_CPANEL.md` §3.1. **La restauration d'un dump** se fait hors
  application (phpMyAdmin ou client `mysql`).
- **Sauvegarde logique JSON** (Paramètres généraux web > Sauvegardes, administrateur seul, audit `sauvegarde.telechargee`) : une photo
  lisible des données, sans mot de passe ni jeton. **Le web ne sait pas la restaurer** (`SauvegardeLogiqueService`, `47u_` D6) : ce
  n'est pas un point de retour arrière.

## 6. Procédure recommandée

**Avant la mise en service**

1. Faire tous les essais sur : (a) postes de recette **non appairés** ou appairés à l'installation d'essai ; (b) l'installation
   d'essai (§1.4) ; (c) les scripts jetables sur un poste de développement.
2. Sur ces environnements seulement : activer « Mode Données de Test », « Peupler un mois de démonstration », essayer, puis
   « Réinitialiser les données ». Sur le serveur d'essai : `REMISE_A_ZERO_ACTIVEE=true` pour l'API §4.2.
3. Dernier passage de la liste de `GUIDE_DEPLOIEMENT.md` §12 : mode « Données de Test » **fermé** sur tous les postes, `REMISE_A_ZERO_ACTIVEE`
   absente ou `false`, comptes d'essai absents, `ADMIN_INITIAL_PASSWORD` retirée du `.env`.

**En exploitation**

1. Aucune réinitialisation sans **sauvegarde du poste et du serveur** datée de la veille au plus, **testée** à la restauration.
2. Si une réinitialisation est vraiment décidée (reprise après une période d'essai en production) : sauvegardes ; prévenir tous les
   postes ; activer le mode « Données de Test » sur **un** poste ; réinitialiser ; refermer le mode ; puis, si le serveur doit aussi
   être vidé, activer `REMISE_A_ZERO_ACTIVEE` le temps de l'appel §4.2 et **la remettre à `false`** aussitôt (modifier `.env` puis
   `php artisan config:cache` si le cache de configuration est utilisé : `GUIDE_DEPLOIEMENT.md` §7.2). Vérifier dans `/parametres/audit`
   l'entrée `sync.remise_a_zero`.
3. Jamais `migrate:fresh`, `db:wipe` ni suppression SQL manuelle sur la base d'exploitation.

## 7. Ce qui n'existe pas (encore)

Vérifié dans `logialvia_laravel/` et `logialvia_app/lib` :

- **Aucun écran web de réinitialisation** (l'onglet « Données de Test » web est informatif) ; aucune commande artisan de remise à zéro
  ou d'essai (`app/Console/` absent) ; aucun bouton web pour appeler l'API §4.2.
- **Le poste n'appelle pas** la remise à zéro du serveur ; il ne fait que **réagir** à la nouvelle marque.
- **Aucun environnement de recette** fourni (ni script de clonage de la production, ni base de démonstration en ligne) : voir §1.4.
- **Aucun garde-fou propre** contre `migrate:fresh` / `db:wipe` en production, ni contre l'usage de `LV_MYSQL_BASE` sur une vraie base.
- **Aucune restauration web** de la sauvegarde logique JSON ; aucune sauvegarde automatique du serveur ; aucun retour arrière de
  migration éprouvé (`GUIDE_DEPLOIEMENT.md` §11.2).
- **Aucun effacement sélectif** de données fictives n'est documenté : la modale désigne la réinitialisation complète de l'activité
  comme « le seul moyen » de les retirer.
- **Effet d'une réinitialisation locale sur un poste appairé** : non documenté et non essayé dans le dépôt (§4.1).
