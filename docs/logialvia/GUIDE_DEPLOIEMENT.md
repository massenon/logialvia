# GUIDE_DEPLOIEMENT — Déployer le web LogiALVIA (Laravel) sur un hébergement mutualisé cPanel

**Statut : procédure rédigée à partir du code et des docs du dépôt, NON exécutée sur un hébergeur réel.**
`47r_MYSQL_ET_RESEAU_REEL.md` §6 le dit déjà : aucun accès à un hébergeur mutualisé n'a eu lieu ; les pièges connus (en-tête
`Authorization`, 413, redirection HTTPS, MySQL/MariaDB) ont été reproduits, pas l'hébergeur lui-même. Les libellés des écrans
cPanel (« MultiPHP », « Bases de données MySQL », etc.) varient selon l'hébergeur et ne sont pas vérifiés ici.

Environnement déclaré par le client (`47r_` fin de document) : production = cPanel mutualisé, **versions de PHP et de
MySQL/MariaDB non communiquées** ; test = Laragon (PHP 8.3.30, Apache 2.4.54, MySQL 8.0.30), non essayé sous Windows.

Documents liés : `02_ARCHITECTURE_WEB_ET_STACK.md` §9, `47r_MYSQL_ET_RESEAU_REEL.md` §5, `47x_PWA_ET_PERFORMANCE.md`,
`LISTE_DES_CRON_JOBS_CPANEL.md`, `CODE_DE_SECOURS_ADMINISTRATEUR.md`, `ESSAIS_EN_PRODUCTION_ET_REINITIALISATION.md`.

---

## 1. Prérequis

| Élément | Exigence | Source |
|---|---|---|
| PHP | `^8.2` exigé ; **8.3** visé et utilisé par la CI (`php-version: '8.3'`) | `logialvia_laravel/composer.json`, `.github/workflows/ci.yml` |
| Extensions PHP | `dom` et `mbstring` (exigées par `dompdf`), `zip` (classe `ZipArchive`, export XLSX), pilote `pdo_mysql` pour MySQL/MariaDB (extension standard de Laravel, non listée dans `composer.json`) | `composer.lock` (dompdf), `app/Support/ExportXlsx.php:7` |
| Base de données | MySQL **≥ 5.7.7** ou MariaDB **≥ 10.2** (format de ligne `DYNAMIC`). Essayés : MySQL 8.0.46 et MariaDB 10.11.14. **Non essayés** : MySQL 5.7, MariaDB 10.3/10.4 | `47r_` §2.4, §5.3, §6 |
| Collation | `utf8mb4` / `utf8mb4_unicode_ci` | `47r_` §5.3 |
| Accès shell | Terminal cPanel ou SSH : **à confirmer avec l'hébergeur** (question ouverte de `02_` §9 et §11). Sans shell, voir §3.3 et §5.4 | `02_` §9 |
| Node | **Non requis sur le serveur** : `npm run build` se fait en local (voir §4) | `02_` §9 |
| HTTPS | Obligatoire en pratique : le jeton des postes y circule (voir §8) | `47r_` §5.1 |

Fonctions du code qui dépendent de l'hébergement : aucune file à traiter, aucun planning (voir `LISTE_DES_CRON_JOBS_CPANEL.md`) ;
aucun envoi d'e-mail (aucun appel `Mail::` dans `app/`) ; aucun téléversement de fichier côté web (aucun `Storage::`,
`->store(` ni `storeAs` dans `app/`), donc **`php artisan storage:link` n'est pas requis par le code**.

## 2. Disposition des fichiers sur le serveur

Le dépôt ne contient **pas** de `.htaccess` à la racine de `logialvia_laravel/` (vérifié : seul `public/.htaccess` existe) ;
le « filet de sécurité » de racine évoqué par `02_` §9 n'existe donc pas. Il faut que **la racine web du domaine soit `public/`**.

Deux dispositions possibles (procédures cPanel/Laravel usuelles, non éprouvées ici) :

**A. Racine du (sous-)domaine réglée sur `public/`** (préférable). Déposer le projet complet, par exemple
`/home/UTILISATEUR/logialvia/`, puis, dans cPanel, régler la « racine du document » du sous-domaine sur
`/home/UTILISATEUR/logialvia/public`. Rien d'autre à modifier : `public/index.php` charge `../vendor/autoload.php` et
`../bootstrap/app.php` (`public/index.php:14,18`).

**B. Racine imposée (`public_html`)**. Garder l'application hors de `public_html` (`/home/UTILISATEUR/logialvia/`), copier le
**contenu** de `public/` (y compris `.htaccess`, `build/`, `fonts/`, `icons/`, `manifest.webmanifest`, `favicon.ico`,
`robots.txt`) dans `public_html/`, puis corriger les trois chemins de `public_html/index.php` pour qu'ils pointent vers
`/home/UTILISATEUR/logialvia/` (lignes 9, 14 et 18 de l'original : `storage/framework/maintenance.php`,
`vendor/autoload.php`, `bootstrap/app.php`). À refaire à chaque mise à jour de `public/` (voir §10).

Dans tous les cas : ne jamais laisser `.env`, `vendor/`, `storage/` ni `database/` accessibles par le web.

## 3. Envoi des fichiers et dépendances PHP

### 3.1 Ce qu'il faut envoyer

Depuis un clone propre (`git clone` ou archive du dépôt) de `logialvia_laravel/` : tout **sauf** `.env` (à créer sur le serveur,
§5), `node_modules/` et `e2e/performance/node_modules/` (inutiles), `.phpunit.result.cache`. `public/build/` n'est **pas
versionné** (`.gitignore` : `/public/build`) : il faut l'envoyer après l'avoir construit (§4).

### 3.2 Composer sur le serveur (avec shell)

```bash
cd /home/UTILISATEUR/logialvia
composer install --no-dev --optimize-autoloader --no-interaction
```

Le `post-autoload-dump` de `composer.json` lance `artisan package:discover` : le fichier `.env` n'est pas nécessaire pour cela
mais l'application doit pouvoir démarrer (PHP 8.3 actif en CLI : sur cPanel, le `php` du shell n'est pas toujours celui du site ;
vérifier avec `php -v`).

### 3.3 Composer en local, `vendor/` envoyé (sans shell)

```bash
cd logialvia_laravel
composer install --no-dev --optimize-autoloader --no-interaction
```

Puis envoyer `vendor/` avec le reste. À faire avec la **même version mineure de PHP** que l'hébergeur (PHP 8.3 ici). Piège
documenté dans `CLAUDE.md` : dans l'environnement cloud de Claude Code, les archives GitHub de Composer sont refusées (403) ; il
faut `--prefer-source`, puis supprimer les `.git` de `vendor/` et le cache Composer, sinon le disque sature (voir
`INSTALLATION_LOCALE.md` §6). Ne pas envoyer de `.git` dans `vendor/` en production.

## 4. Construire les assets en local, envoyer `public/build`

Le serveur n'a pas Node (`02_` §9). En local :

```bash
cd logialvia_laravel
npm ci
npm run build
```

`npm run build` = `vite build` (`package.json`). Il produit `public/build/` (`manifest.json` + `assets/`). Envoyer **tout** le
dossier `public/build/` : le service worker généré (`/sw.js`) lit `public/build/manifest.json` pour sa liste de précache
(`app/Http/Controllers/ServiceWorkerController.php:26`, `47x_`). Un `public/build/` absent ou périmé donne une application sans
styles ni scripts. Les fichiers de `build/` portent une empreinte dans leur nom : un nouvel envoi remplace l'ensemble
(supprimer les anciens fichiers de `build/assets/` qui ne sont plus dans le nouveau `manifest.json`).

`PerformanceAssetsTest` borne le build : JS ≤ 300 Ko, CSS ≤ 100 Ko (`CLAUDE.md`, `47x_`).

## 5. Fichier `.env` de production

Partir de `logialvia_laravel/.env.example` : copier en `.env` **sur le serveur** (le fichier est ignoré par git :
`.gitignore` ligne `.env`), puis régler les valeurs ci-dessous. Aucune valeur sensible n'est jamais versionnée.

```bash
cp .env.example .env
php artisan key:generate --force
```

| Variable | Valeur de production | Vérification dans le dépôt |
|---|---|---|
| `APP_ENV` | `production` | `.env.example:2` (par défaut `local`) |
| `APP_DEBUG` | `false` | `.env.example:4` (par défaut `true` : **à changer**) ; `47r_` §5.2 `display_errors = Off` |
| `APP_URL` | `https://votre-domaine` | `config/filesystems.php:44` s'en sert pour le disque `public` ; lu par `config/app.php` |
| `APP_KEY` | générée par `key:generate` | `config/app.php:100` |
| `APP_LOCALE`, `APP_FALLBACK_LOCALE`, `APP_FAKER_LOCALE` | `fr`, `fr`, `fr_FR` (déjà dans `.env.example`) | `.env.example` |
| `LOG_LEVEL` | `warning` (au lieu de `debug`) ; `LOG_STACK=single` | `.env.example` ; `02_` §9 |
| `DB_CONNECTION` | `mysql` (ou `mariadb`) | `config/database.php` définit les connexions `mysql` et `mariadb` |
| `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` | ceux de la base créée dans cPanel (en commentaire dans `.env.example`, à décommenter) | `.env.example:24-28` |
| `DB_TIMEZONE` | laisser `+00:00` (valeur par défaut) | `config/database.php:64,88` ; `47r_` §2.2 n° 5 : un fuseau de session non UTC a fait échouer des écritures |
| `SESSION_DRIVER` | `database` (déjà la valeur de `.env.example`) | `.env.example:30` ; table `sessions` créée par la migration `0001_01_01_000000_create_users_table.php` |
| `SESSION_SECURE_COOKIE` | `true` une fois HTTPS actif | `config/session.php:172` (lit `env('SESSION_SECURE_COOKIE')`) ; absente de `.env.example`, à **ajouter** |
| `SESSION_LIFETIME` | `120` (minutes, défaut) | `.env.example:31` |
| `QUEUE_CONNECTION` | `database` (déjà la valeur par défaut ; aucune file à traiter, voir `LISTE_DES_CRON_JOBS_CPANEL.md`) | `.env.example:38` |
| `CACHE_STORE` | `database` (défaut) ; table `cache` créée par la migration `…000001_create_cache_table.php` | `.env.example:40` |
| `MAIL_MAILER`, `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `MAIL_FROM_*` | `smtp` + le SMTP du domaine (voir `.env.production.example`). Avec `log` ou `array`, **aucun e-mail ne part** | `app/Livewire/Contact.php` (seul envoi : « Contactez l'Éditeur ») |
| `SUPPORT_MAIL` | adresse du support de l'éditeur : chaque message écrit au web lui est envoyé. Vide ou transport `log` : aucun envoi, le message reste enregistré | `config/logialvia.php` (`support_mail`), `app/Mail/MessageEditeurMail.php` |
| `ADMIN_INITIAL_USERNAME` | `admin` (défaut) | `.env.example:69` ; `config/logialvia.php` |
| `ADMIN_INITIAL_PASSWORD` | un mot de passe fort, **retiré du `.env` après le premier `db:seed`** (voir §6) | `.env.example:70` ; `database/seeders/AdminSeeder.php` |
| `REMISE_A_ZERO_ACTIVEE` | **absente ou `false`** en exploitation | `config/logialvia.php:136-139` (défaut `false`) ; voir `ESSAIS_EN_PRODUCTION_ET_REINITIALISATION.md` |
| `STOCK_CIBLE_OBLIGATOIRE` | `false` (défaut) sauf décision du client | `config/logialvia.php` (`stock_cible`) |
| `SANCTUM_EXPIRATION_JOURS` | `90` (défaut) : durée de vie du jeton d'un poste | `config/logialvia.php` (`jeton_duree_jours`) |
| `SYNC_LIGNES_PAR_PAGE`, `SYNC_RECOUVREMENT_SECONDES` | défauts `200` et `2` ; ne pas toucher sans raison | `config/logialvia.php:184+` ; `47r_` §5.5 |

À savoir :

- **`APP_TIMEZONE` n'est pas lue** : `config/app.php:68` fixe `'timezone' => 'UTC'` en dur (le `47r_` §5.3 la cite, mais le code
  ne la consulte pas). Les dates métier sont converties à l'affichage en `Africa/Porto-Novo` (`config/logialvia.php`, clé `fuseau`).
- Redis, Memcached, AWS et SMTP figurent dans `.env.example` comme valeurs de squelette Laravel ; rien dans LogiALVIA ne
  les exige (sessions, cache et file sont sur `database`).
- Aucun appel à `env()` hors des fichiers `config/` et des seeders (vérifié par `grep` sur `app/`, `routes/`, `resources/`,
  `bootstrap/`) : `php artisan config:cache` est donc sans risque pour le code.

## 6. Migrations et mot de passe de l'administrateur initial

Créer la base dans cPanel (utilisateur applicatif sans droits d'administration : `47r_` §5.3), renseigner `.env`, puis :

```bash
cd /home/UTILISATEUR/logialvia
php artisan migrate --force
php artisan db:seed --force
```

- `migrate` crée les 35 migrations présentes (dont `sessions`, `cache`, `jobs`).
- `db:seed` appelle, dans l'ordre : `RolesAndPermissionsSeeder`, `ModulesActifsSeeder`, `ParametresEntrepriseSeeder`,
  `GroupesTaxeSeeder`, `PlanComptableSeeder`, `AdminSeeder` (`database/seeders/DatabaseSeeder.php`). Ils sont écrits pour
  être rejouables (`findOrCreate` / `firstOrCreate`).
- **`AdminSeeder` ne crée l'administrateur que si `ADMIN_INITIAL_PASSWORD` est définie et conforme** (8 caractères minimum,
  1 majuscule, 1 chiffre : `app/Support/RegleMotDePasse.php`). Sinon il affiche un avertissement et **ne crée aucun compte**
  (`AdminSeeder.php:23-27`). Le compte est créé avec `must_change_password = true` : **le changement est exigé à la première
  connexion** (middleware `mdp.web`, `app/Http/Middleware/ChangementMotDePasseObligatoireWeb.php`).
- Le seeder est un `firstOrCreate` sur l'identifiant : **changer `ADMIN_INITIAL_PASSWORD` plus tard n'a aucun effet** sur un compte
  existant. Voir `CODE_DE_SECOURS_ADMINISTRATEUR.md`.
- **Après le premier `db:seed` réussi, retirer `ADMIN_INITIAL_PASSWORD` du `.env`** (le mot de passe n'a plus d'usage et ne doit
  pas rester en clair sur le serveur).

N'exécutez **jamais** `php artisan migrate:fresh` sur la base d'exploitation : il supprime toutes les tables. Les scripts du dépôt
(`essai_vrai_serveur.sh`, `e2e/lancer.sh`) l'emploient sur une base jetable. Le dépôt ne pose aucun garde-fou propre
(`grep prohibitDestructiveCommands` : aucun résultat) ; Laravel demande seulement une confirmation en `APP_ENV=production`,
que `--force` contourne. Voir `ESSAIS_EN_PRODUCTION_ET_REINITIALISATION.md`.

## 7. Permissions, caches, `php.ini`

### 7.1 Permissions

Laravel doit pouvoir écrire dans `storage/` (et sous-dossiers `framework/cache`, `framework/sessions`, `framework/views`, `logs`)
et `bootstrap/cache/`. Réglage usuel sous cPanel (non essayé ici) :

```bash
cd /home/UTILISATEUR/logialvia
find storage bootstrap/cache -type d -exec chmod 775 {} \;
find storage bootstrap/cache -type f -exec chmod 664 {} \;
chmod 640 .env
```

### 7.2 Caches au déploiement

```bash
php artisan config:cache
php artisan route:cache
php artisan view:cache
```

Essai fait pour ce guide : `config:cache` et `route:cache` réussissent sur ce dépôt (cache écrit hors du dépôt via
`APP_CONFIG_CACHE` / `APP_ROUTES_CACHE`, puis supprimé). `view:cache` n'a pas été exécuté. Après toute modification de `.env`,
refaire `php artisan config:cache`. Pour revenir en arrière : `php artisan optimize:clear`.

### 7.3 `php.ini` / `.user.ini`

Valeurs recommandées par `47r_` §5.2 (à poser dans l'éditeur PHP de cPanel ou dans un `.user.ini`) :

```ini
post_max_size = 8M
upload_max_filesize = 8M
memory_limit = 256M
max_execution_time = 60
display_errors = Off
```

Le poste n'envoie jamais plus de 256 Kio par requête (il découpe) ; un `post_max_size` bas n'est pas bloquant, le poste s'adapte
(413 absorbé, `47r_` §3.2). Ne **pas** poser de `LimitRequestBody` sous 1 Mio. `max_input_vars` est sans effet (l'API reçoit du JSON).
La sauvegarde logique téléchargeable (`SauvegardesWeb`) est écrite en flux, une table et une ligne à la fois
(`app/Services/SauvegardeLogiqueService.php`), ce qui limite la mémoire nécessaire.

## 8. `.htaccess` et HTTPS

`public/.htaccess` est dans le dépôt et gère : compression Brotli/gzip, types MIME (`.webmanifest`, `.woff2`), cache immuable de
`/build` (un an) et cache 30 jours des polices/icônes, réécriture vers `index.php`, et trois filets pour l'en-tête
`Authorization` (`RewriteRule … HTTP_AUTHORIZATION`, `SetEnvIfNoCase`, et, en dernier recours, `X-Authorization` que le poste
envoie aussi et que `RestaurerEnTeteAutorisation` relit). Voir `47r_` §5.1 et §3.2. Si l'hébergeur ignore `.htaccess` (PHP en CGI
sans `AllowOverride`), le poste continue de fonctionner grâce à `X-Authorization` (essai réel `47r_` §3.3).

**Redirection HTTP → HTTPS** : si l'hébergeur ne l'impose pas, ajouter dans le `.htaccess` de la racine du domaine
(`47r_` §5.1) :

```apache
RewriteCond %{HTTPS} !=on
RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
```

Le poste suit cette redirection (même hôte uniquement) et mémorise l'adresse `https://`. Jamais d'HTTP clair en production.

Certificat : un certificat **public** (AutoSSL de l'hébergeur ou Let's Encrypt) ne demande rien sur les postes. Un certificat
auto-signé, expiré ou au mauvais nom est **refusé** par le poste, avec un message en français (`47r_` §5.4). Surveiller
l'expiration : le poste ne synchronise plus tant qu'un certificat expiré n'est pas remplacé, par conception.

## 9. Vérification après déploiement

```bash
curl -sI https://votre-domaine/up        # 200 : sonde de santé de Laravel (bootstrap/app.php:22, `health: '/up'`)
curl -sI https://votre-domaine/login     # 200 : page de connexion
curl -sI http://votre-domaine/login      # 301 vers https:// si la redirection est en place
```

Ensuite, dans le navigateur :

1. `/login` : se connecter avec `admin` et le mot de passe initial ; l'application impose alors `/mot-de-passe` (changement
   obligatoire) avant toute autre page (`routes/web.php`, groupe `mdp.web`).
2. Aucun message d'erreur PHP en clair ; `APP_DEBUG=false`.
3. Menu **Paramètres généraux > Gestion Utilisateurs** : créer les comptes réels (`app/Livewire/GestionUtilisateurs.php`).
4. Menu **Paramètres généraux > Appairage** (côté poste) et **/parametres/postes** (côté web) : appairer un poste avec l'adresse
   `https://votre-domaine` (voir `INSTALLATION_LOCALE.md` §4). Un 401 `jeton_absent` signifie que l'hébergeur retire
   `Authorization` et que `X-Authorization` n'arrive pas non plus : revoir le `.htaccess` (`47r_` §3.2).
5. Contrôles de `47r_` (fin de document) : en-tête `Authorization` transmis, `utf8mb4`, `DB_TIMEZONE=+00:00`,
   `post_max_size` ≥ 8M, HTTPS, racine web = `public/`.

### 9.1 PWA et performance

Le web est installable (manifeste, `/sw.js` généré, page `/hors-ligne`) ; le travail hors ligne reste celui du poste Windows
(`47x_`). Objectif : LCP < 2 s, score Lighthouse ≥ 90, CLS ≤ 0,1, TBT ≤ 200 ms. Mesure du serveur en ligne (Node 20+ et
Chrome/Chromium requis en local, sans mandataire) :

```bash
bash logialvia_laravel/outils/mesure_performance.sh https://votre-domaine
LV_MDP='…' bash logialvia_laravel/outils/mesure_performance.sh https://votre-domaine admin1
```

Le script écrit ses rapports dans `logialvia_laravel/e2e/rapports-performance/` et sort en code 1 si un seuil est dépassé. Si
l'hébergeur n'active ni Brotli ni gzip sur les fichiers statiques, le mobile peut dépasser 2 s (`47x_` « Résultats constatés ») ;
le filet `CompresserReponse` compresse alors les réponses PHP (pas les fichiers statiques servis directement par Apache).
Limites reconnues : mesures faites en HTTP local, coût TLS non simulé.

## 10. Mise à jour

1. En local : récupérer la nouvelle version, `npm ci && npm run build`, `composer install --no-dev --optimize-autoloader`
   si `composer.lock` a changé.
2. **Sauvegarder la base** (§11.1) avant tout envoi.
3. Mettre le site en maintenance (commande standard de Laravel ; le mode maintenance utilise le pilote `file`,
   `APP_MAINTENANCE_DRIVER=file` dans `.env.example`) :

```bash
php artisan down
```

4. Envoyer les fichiers modifiés (sans écraser `.env` ni `storage/`), puis le **nouveau `public/build/`** complet
   (disposition B : recopier aussi le contenu de `public/` dans `public_html/`).
5. Appliquer les migrations et rafraîchir les caches :

```bash
php artisan migrate --force
php artisan config:cache
php artisan route:cache
php artisan view:cache
php artisan up
```

6. Refaire les vérifications du §9 (`/up`, `/login`).

Les postes continuent de fonctionner pendant la maintenance (hors ligne = état normal) et rejouent leurs envois ensuite : l'envoi
est idempotent par UUID (`47r_` §3.2). Une migration qui change le schéma partagé exige la version correspondante du poste
(`02_` : le schéma de `app_database.dart` doit rester aligné).

## 11. Sauvegarde et retour arrière

### 11.1 Sauvegarde avant mise à jour

- **Base du serveur** : à la charge de l'hébergement (`47u_ADMINISTRATION_PARITE.md` §5). Commande conseillée par `47r_` §5.3 :

```bash
mysqldump --single-transaction -u UTILISATEUR_BASE -p NOM_BASE > logialvia-AAAAMMJJ.sql
```

  (ou l'outil de sauvegarde de cPanel). Les colonnes JSON sont du texte : aucun traitement spécial.
- **Sauvegarde logique JSON** : menu **Paramètres généraux > Sauvegardes** (`app/Livewire/SauvegardesWeb.php`), réservée à
  l'administrateur ; elle ne contient ni mot de passe, ni jeton, ni session. **Le web ne sait pas la restaurer**
  (`SauvegardeLogiqueService`, `47u_` D6) : ce n'est qu'une photo des données, pas un point de retour arrière.
- Les postes gardent leur propre base SQLite et leurs sauvegardes (`ESSAIS_EN_PRODUCTION_ET_REINITIALISATION.md` §5).

### 11.2 Retour arrière

Il n'existe **aucune commande de retour arrière** propre à LogiALVIA. Procédure réelle :

1. `php artisan down`.
2. Restaurer le dump SQL pris avant la mise à jour (phpMyAdmin ou `mysql … < logialvia-AAAAMMJJ.sql`) : les migrations ne
   sont pas supposées se défaire une à une (ne pas utiliser `migrate:rollback` en exploitation, non éprouvé).
3. Remettre les fichiers de la version précédente (code et `public/build/` correspondant).
4. `php artisan optimize:clear`, puis `php artisan config:cache` si utilisé, `php artisan up`.
5. Vérifier `/up` et `/login`. Les postes repartiront d'un tirage cohérent à leur prochain cycle (les faits reçus entre-temps
   par le serveur et absents de la sauvegarde seront renvoyés par les postes, qui conservent leurs données).

## 12. Liste de contrôle

- [ ] PHP 8.3 actif (site **et** CLI), extensions `dom`, `mbstring`, `zip`, `pdo_mysql`
- [ ] Base `utf8mb4_unicode_ci`, MySQL ≥ 5.7.7 / MariaDB ≥ 10.2, utilisateur sans droit d'administration
- [ ] Racine web = `public/` (ou contenu de `public/` copié et `index.php` corrigé)
- [ ] `.env` : `APP_ENV=production`, `APP_DEBUG=false`, `APP_URL=https://…`, `APP_KEY`, base, `SESSION_SECURE_COOKIE=true`
- [ ] `ADMIN_INITIAL_PASSWORD` posé pour `db:seed`, puis retiré
- [ ] `REMISE_A_ZERO_ACTIVEE` absente ou `false`
- [ ] `php artisan migrate --force` et `db:seed --force` exécutés ; jamais `migrate:fresh`
- [ ] `public/build/` envoyé en entier (construit en local)
- [ ] `storage/` et `bootstrap/cache/` accessibles en écriture ; `.env` non lisible par le web
- [ ] HTTPS actif, redirection HTTP → HTTPS, certificat public valide
- [ ] `/up` et `/login` répondent 200 ; changement de mot de passe imposé à la première connexion
- [ ] `post_max_size` ≥ 8M, `display_errors = Off`
- [ ] Un poste appairé et synchronisé (adresse en `https://`)
- [ ] `mesure_performance.sh` : LCP < 2 s
- [ ] Sauvegarde de la base prise et testée **avant** la mise en service
- [ ] Mot de passe administrateur noté sur fiche papier au coffre (voir `CODE_DE_SECOURS_ADMINISTRATEUR.md`)
