# INSTALLATION_LOCALE — Cloner et lancer LogiALVIA en local (web Laravel + poste Windows)

Ce document décrit comment faire tourner le dépôt sur un poste de développement ou de recette. Pour la mise en ligne, voir
`GUIDE_DEPLOIEMENT.md` ; pour construire l'installateur Windows, voir `47w_INSTALLATEUR_WINDOWS.md`.

**Statut des commandes** : celles du web (`composer`, `php artisan`, `npm`) et des scripts `essai_vrai_serveur.sh` /
`e2e/lancer.sh` sont celles du dépôt ; elles ont été relevées dans `composer.json`, `package.json`, `CLAUDE.md` et les scripts,
pas exécutées pour ce document (sauf mention). Les variantes PowerShell sont la transposition directe de ces commandes sous
Windows et **n'ont pas été essayées** (le dépôt a été développé sous Linux, `47w_`).

Le dépôt (`CLAUDE.md`) :

| Chemin | Contenu |
|---|---|
| `logialvia_app/` | Poste Flutter (cible principale : Windows desktop) |
| `logialvia_laravel/` | Web Laravel 12 + Livewire 3 |
| `docs/`, `docs/logialvia/` | Documentation |

## 1. Prérequis

| Outil | Version | Source |
|---|---|---|
| Git | récent | — |
| PHP | `^8.2` exigé, **8.3** utilisé par la CI ; extensions `dom`, `mbstring`, `zip`, `pdo_sqlite` (SQLite par défaut) | `composer.json`, `.github/workflows/ci.yml`, `.env.example` (`DB_CONNECTION=sqlite`) |
| Composer | 2.x | `composer.json` |
| Node + npm | Node 20+ (la CI utilise 22) | `.github/workflows/ci.yml`, `02_` |
| Flutter | `>= 3.41` (Dart `^3.12.2`), vérifié avec Flutter 3.47.9 | `CLAUDE.md`, `logialvia_app/pubspec.yaml` |
| Poste Windows | Visual Studio 2022 avec la charge « Développement Desktop en C++ » | `logialvia_app/README.md` |
| Python 3 + `openpyxl` | seulement pour le scénario d'export XLSX des essais navigateur | `logialvia_laravel/e2e/transversaux.mjs`, `verifier_xlsx.py` |

## 2. Cloner

```bash
git clone <URL-du-dépôt> logialvia
cd logialvia
```

Sous Windows PowerShell, dans `C:\Projects` (exemple de dossier ; tout dossier convient, mais voir §6 pour l'antivirus) :

```powershell
cd C:\Projects
git clone <URL-du-dépôt> logialvia
cd C:\Projects\logialvia
```

## 3. Web (Laravel)

### 3.1 Installation

```bash
cd logialvia_laravel
composer install
npm ci
cp .env.example .env
php artisan key:generate
```

Sous PowerShell :

```powershell
cd C:\Projects\logialvia\logialvia_laravel
composer install
npm ci
Copy-Item .env.example .env
php artisan key:generate
```

`composer.json` fournit aussi un raccourci `composer setup` (`composer install`, copie de `.env`, `key:generate`,
`migrate --force`, `npm install`, `npm run build`). Il ne lance **pas** `db:seed` : l'administrateur n'est alors pas créé.

Piège de l'environnement **cloud de Claude Code** (`CLAUDE.md`) : les archives GitHub de Composer y sont refusées (403). Installer
avec `composer install --prefer-source` (clonage git) puis supprimer les `.git` de `vendor/` et le cache Composer ; voir §6.

### 3.2 Base SQLite et administrateur

`.env.example` est réglé sur `DB_CONNECTION=sqlite` ; `config/database.php` prend alors `database/database.sqlite` si
`DB_DATABASE` n'est pas défini. Le fichier doit exister. Fixer `ADMIN_INITIAL_PASSWORD` **avant** `db:seed`
(`.env.example:69-70` ; `AdminSeeder` ne crée aucun compte sans lui, 8 caractères minimum, 1 majuscule, 1 chiffre).

Dans `.env`, renseigner par exemple :

```ini
ADMIN_INITIAL_USERNAME=admin
ADMIN_INITIAL_PASSWORD=ChoisirUnMotDePasse1
```

```bash
touch database/database.sqlite
php artisan migrate --seed
```

Sous PowerShell :

```powershell
New-Item -ItemType File -Path database\database.sqlite -Force
php artisan migrate --seed
```

(`--seed` appelle `DatabaseSeeder` : rôles, modules, paramètres, taxes, plan comptable SYSCOHADA, puis l'administrateur.) À la
première connexion web, le mot de passe initial doit être changé (`must_change_password`).

### 3.3 Assets, serveur, mode développement

```bash
npm run build          # construit public/build (vite build)
php artisan serve      # http://127.0.0.1:8000
```

Mode développement complet (une seule commande, définie dans `composer.json`, script `dev`) : `php artisan serve`,
`php artisan queue:listen --tries=1 --timeout=0`, `php artisan pail --timeout=0` et `npm run dev`, orchestrés par `concurrently` :

```bash
composer dev
```

Remarque : aucune file n'est utilisée par le code (voir `LISTE_DES_CRON_JOBS_CPANEL.md`) ; `queue:listen` tourne à vide dans
`composer dev`. `php artisan serve` ne lit pas `.htaccess` (`02_` §9) : les règles `Authorization` et la compression ne
s'appliquent pas en local.

Vérifier : `http://127.0.0.1:8000/up` (200) et `http://127.0.0.1:8000/login`.

### 3.4 Variante MySQL / MariaDB locale

Dans `.env` : `DB_CONNECTION=mysql` (ou `mariadb`), décommenter `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`,
`DB_PASSWORD`. Créer la base en `utf8mb4_unicode_ci`. Même `php artisan migrate --seed`. Détails et pièges : `47r_` §2 et §5.3.

## 4. Poste Windows (Flutter) et appairage au web

```bash
cd logialvia_app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
```

Sous PowerShell :

```powershell
cd C:\Projects\logialvia\logialvia_app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
```

- `build_runner` est **obligatoire après toute modification d'une table Drift** (`CLAUDE.md`) ; `app_database.g.dart` est versionné
  (`versionSchema = 51`, `app_database.dart:111`). Le premier passage a duré environ 6 minutes sur le poste du client
  (812 fichiers générés), ensuite 10 à 90 s (`47w_`).
- Données du poste en production : `%APPDATA%\ALLMANY ET COMPAGNIE\LogiALVIA` ; sauvegardes : `Documents\LogiALVIA\Sauvegardes`
  (`47w_`, `main.dart:101-128`).
- **Compte du poste** : le poste a ses propres comptes locaux (DV-20), distincts de ceux du web. Le compte initial est `admin`
  avec le mot de passe de la constante `AdminSeeder.motDePasseInitialAdmin` (`logialvia_app/lib/administration/data/seed/admin_seeder.dart`).
  Rien n'impose de le changer au poste (la colonne « mot de passe à changer » n'existe pas côté poste, voir le commentaire de ce
  fichier) : **le changer dès la première connexion** via « Mon Profil ». Voir `CODE_DE_SECOURS_ADMINISTRATEUR.md`.

### 4.1 Appairer le poste au web

Écran réel : **Paramètres Généraux > onglet « Appairage »** (`parametres_generaux_screen.dart`, route `/parametres/generaux` ;
carte « Appairer ce poste » dans `administration/presentation/screens/widgets/onglet_appairage.dart`). Champs :

| Champ | Contenu |
|---|---|
| Adresse du serveur | par exemple `http://127.0.0.1:8000` en local, `https://votre-domaine` en production |
| Identifiant du compte web | un compte du **web** (par exemple `admin`) |
| Mot de passe | celui du compte web ; **n'est jamais conservé** sur le poste : seul un jeton révocable l'est (`secure storage`) |

Bouton « Appairer ». Règles de l'adresse (`core/sync/adresse_serveur.dart`) : le schéma manquant est ajouté, `http://` pour un
réseau local (`localhost`, `127.*`, `10.*`, `192.168.*`, `172.16-31.*`, nom sans point), `https://` sinon ; les `/` finaux sont retirés.
Après appairage, l'onglet affiche le code du poste, l'identifiant, le compte web, les droits et l'écart d'horloge, et propose
« Synchroniser maintenant », « Tester la connexion » et « Déconnecter ce poste ».

Le compte web utilisé doit avoir changé son mot de passe temporaire (les routes de synchronisation sont derrière le
middleware `mdp.change`, `routes/api.php`) et disposer des droits voulus : un compte sans droits (par exemple `caissier1`)
voit une grande partie de ses propositions refusées (`47h_` D6). Côté web, la liste des postes et leur révocation sont à
**/parametres/postes** (`app/Livewire/PostesAppairage.php`, droit `manage-users`).

Il n'y a **pas d'adresse de serveur compilée** dans le poste : elle est saisie à l'appairage (`47w_`).

## 5. Tests

| Cible | Commande | Remarque |
|---|---|---|
| Web (PHP) | `cd logialvia_laravel && php artisan test` | comprend `ConformiteDartTest` : Tailwind doit rester égal au code Dart (`CLAUDE.md`). La CI fait `cp .env.example .env && php artisan key:generate` avant. `phpunit.xml` impose SQLite en mémoire |
| Web sur MySQL/MariaDB | `DB_CONNECTION=mysql DB_HOST=127.0.0.1 DB_DATABASE=lv_test DB_USERNAME=… DB_PASSWORD=… php artisan test` | `47r_` §2.5 |
| Poste (Dart) | `cd logialvia_app && flutter analyze` puis `flutter test` | `analyze` doit rester à « No issues found! » ; ~2000 tests (+90 d'intégration ignorés sans serveur), ~2 min (`CLAUDE.md`) ; `flutter analyze` 3 à 4 min sur le poste du client (`47w_`) |
| Un dossier / un fichier | `flutter test test/elevage/` | `CLAUDE.md` |
| Poste ↔ vrai serveur | `bash logialvia_app/outils/essai_vrai_serveur.sh` | base **jetable** ; voir ci-dessous |
| Écrans web, navigateur | `bash logialvia_laravel/e2e/lancer.sh` | base **jetable** ; 52 scénarios (`47n_`) |
| Performance web | `LV_SCRIPT=e2e/performance.mjs bash logialvia_laravel/e2e/lancer.sh` | garde LCP < 2 s (`47x_`) |

Règle : **ne jamais** lancer `flutter test test/manuel/captures_test.dart` avec `GENERER_MANUEL=1` sans vouloir régénérer le manuel
(il écrit dans `docs/manuel/`, `CLAUDE.md`).

### 5.1 `essai_vrai_serveur.sh`

Crée une base SQLite neuve (`/tmp/lv/essai.sqlite`, dossier réglable par `LV_DOSSIER`), exécute `migrate:fresh --seed`, crée les
comptes `admin1…admin150`, `caissier1`, `comptable1`, `animalier1` (mot de passe d'essai `EssaiPoste-2026!`), active la remise à zéro
(`REMISE_A_ZERO_ACTIVEE=true`), lance `php artisan serve --port=8765` puis `flutter test test/integration/serveur_reel_test.dart`.
Variables : `FLUTTER`, `TZ`, `LV_DOSSIER`, `LV_BASE=sqlite|mysql|mariadb`, `LV_MYSQL_*`, `ESSAI_RESEAU=1` (essai réseau, `47r_` §3).
Sans `LOGIALVIA_SERVEUR`, l'essai d'intégration est ignoré (`CLAUDE.md`). Le script utilise `bash`, `curl`, `pkill`, `/tmp` : il
s'exécute sous Linux ; **sous Windows, non essayé** (Git Bash ou WSL à tester).

### 5.2 `e2e/lancer.sh`

Base SQLite jetable (`/tmp/lv-e2e/e2e.sqlite`), `npm run build` (sauf `SANS_BUILD=1`), `migrate:fresh --seed`, jeu de données
(`e2e/donnees.php`), serveur sur le port 8799, puis `node e2e/executer.mjs` (Playwright, Chromium). Comptes : `admin1`,
`comptable1`, `caissier1`, `animalier1`, `temporaire1`, mot de passe `EssaiPoste-2026!` (`47n_` §1).

Prérequis qui ne sont pas dans le dépôt : `e2e/` n'a pas de `package.json` ; `playwright` est résolu par `NODE_PATH` (le script
ajoute `/opt/node-tools/node_modules`, chemin de l'environnement cloud) et Chromium est cherché via Playwright puis
`/opt/pw-browsers/chromium` (`e2e/lib.mjs:75-76`). Sur un autre poste, il faut installer `playwright` et Chromium soi-même et
exporter `NODE_PATH`. Le scénario d'export XLSX appelle `python3 -I e2e/verifier_xlsx.py` (module `openpyxl` nécessaire).
Durée : environ 6 minutes (`47n_`).

## 6. Pièges

- **Archives Composer refusées (403) dans le cloud Claude Code** : `composer … --prefer-source`, puis
  `find vendor -maxdepth 3 -name .git -prune -exec rm -rf {} +` et suppression du cache Composer, sinon l'espace disque est saturé
  en quelques Go (`CLAUDE.md`).
- **Disque** : `vendor/` cloné en source, `node_modules/`, `build/` Flutter et les builds Windows sont volumineux ; prévoir de la marge
  (aucun chiffre mesuré dans le dépôt).
- **Antivirus Windows** : le `47w_` conseille d'exclure `C:\Projects`, le dossier Flutter et `%LOCALAPPDATA%\Pub\Cache` de
  l'analyse de Windows Defender et de construire sur SSD (durées de `build_runner` et `flutter analyze`).
- **`.env` jamais versionné** (`.gitignore`) ; `APP_KEY` à générer sur chaque installation.
- **`migrate:fresh`** : seulement sur une base jetable (scripts d'essai). Jamais sur la base d'exploitation
  (`ESSAIS_EN_PRODUCTION_ET_REINITIALISATION.md`).
- **Tailwind / Dart** : modifier une couleur, un espacement ou une taille de texte d'un seul côté (Dart ou `tailwind.config.js`) fait
  échouer `ConformiteDartTest` (`CLAUDE.md`).
- **Table Drift modifiée** : relancer `build_runner`, sinon le poste ne compile pas ou lit un schéma périmé.
