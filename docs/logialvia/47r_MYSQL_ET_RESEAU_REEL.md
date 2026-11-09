# 47r — MySQL de production et réseau réel : ce qui est prouvé, ce qui ne l'est pas

> Suite de `47h_PREUVE_VRAI_SERVEUR.md` (section « Non prouvé »). Tout y avait été éprouvé sur
> SQLite et sur le réseau local ; ici, sur de **vrais** MySQL / MariaDB, un **vrai** Apache et un
> mandataire qui reproduit les pièges d'un hébergement mutualisé.

## 1. Verdict

| Limite de `47h_` | État | Preuve |
|---|---|---|
| MySQL / MariaDB de production | **Prouvé** sur MySQL 8.0.46 et MariaDB 10.11.14 (serveurs réels installés dans le bac à sable) | suite PHP complète, essai réel 55/55, sonde de concurrence |
| Réseau réel (TLS, 413, coupures, lenteurs, 5xx, redirections, HTML, `Authorization`) | **Prouvé** : 20 essais contre le vrai serveur derrière un mandataire, 33 essais contre le faux serveur, trois essais sur un vrai **Apache** (mod_php, `LimitRequestBody`, PHP en CGI) | `reseau_reel_test.dart`, `reseau_defaillant_test.dart` |
| Hébergeur mutualisé réel | **Non prouvé** (aucun accès) : voir §6 | — |

## 2. MySQL / MariaDB

### 2.1 Ce qui a été installé et lancé

`apt-get install mariadb-server` puis `mysql-server-8.0` (via le mandataire de paquets) : un
serveur réel, pas un simulateur. Le moteur SQLite reste celui des tests locaux ; la base MySQL
est recréée à chaque essai (`LV_BASE=mysql|mariadb`), **jamais** celle de l'exploitation.

Session MySQL observée sous Laravel (`strict: true`) :
`ONLY_FULL_GROUP_BY, STRICT_TRANS_TABLES, NO_ZERO_IN_DATE, NO_ZERO_DATE, ERROR_FOR_DIVISION_BY_ZERO,
NO_ENGINE_SUBSTITUTION`, collation de connexion `utf8mb4_unicode_ci`, fuseau de session `+00:00`.
Le serveur MySQL de l'essai était réglé sur `Europe/Paris` (le pire cas, voir §2.2 n° 5).

### 2.2 Différences de comportement trouvées et corrigées

La première exécution de la suite sur MariaDB a donné **96 échecs**. Causes :

| # | Différence | Symptôme | Correction |
|---|---|---|---|
| 1 | `datetime(6)` refuse l'ISO `…T…Z` (SQLite le gardait comme du texte) | `curseur_tirage` : `Incorrect datetime value` → **tout tirage complet répondait 500** (≈ 90 des 96 échecs) | `DemandesSynchronisationService::memoriserCurseur` écrit une date SQL UTC à la microseconde |
| 2 | `LIKE … ESCAPE '\'` : le antislash échappe le guillemet en MySQL, le litteral ne se ferme pas | recherche des ventes, devis, factures, impression : erreur de syntaxe | `App\Support\RechercheLike` (échappement `!`, jokers `%` `_` littéraux) |
| 3 | Ordre des lignes : SQLite rend l'ordre d'insertion, InnoDB l'ordre de la **clé primaire** (UUID aléatoire) | lignes d'une commande / vente / facture mélangées (visible à l'écran, au ticket, à la facture) | colonne `ordre` (migration `2026_11_09_164000_ajouter_ordre_aux_lignes`), relations `orderBy('ordre')`, rang posé par les absorbeurs |
| 4 | **JSON natif de MySQL 8** : clefs réordonnées, espaces refaits (MariaDB et SQLite : texte intact) | 5 échecs sur MySQL 8 seulement ; surtout : les **variantes d'une fiche journalière** étaient comparées par `===` sur des tableaux → un rejeu devenait une nouvelle variante (doublon) | migration `2026_11_09_164000_json_en_texte_pour_mysql` : `audit_logs.detail`, `demandes_referentiel.donnees`, `fiche_journee.variantes` passent en `LONGTEXT` (le cast `array` ne change pas) |
| 5 | Colonnes `TIMESTAMP` converties selon le fuseau de la **session** | un serveur en `Europe/Paris` refuse « 2026-03-29 02:30 » (`Incorrect datetime value`, constaté) | connexions `mysql` / `mariadb` : `'timezone' => '+00:00'` (`DB_TIMEZONE`) |
| 6 | **Interblocages** (erreur 1213) : plusieurs postes qui envoient les mêmes lignes en sens inverse ; `DB::transaction($f, 3)` rejoue aussitôt, les deux transactions se re-heurtent | sonde : 4 postes × 150 lignes en sens opposés, **23 réponses 500 sur 48** | `App\Support\TransactionRejouee` : 8 essais avec attente aléatoire croissante, puis **503 + `Retry-After: 1`** (`ServeurOccupe`) que le poste rejoue ; **0 échec sur 3 × 48** après correction |
| 7 | **Doublon de concurrence** (erreur 1062) : le poste rejoue après un délai alors que le premier envoi tourne encore ; les deux ne trouvent rien, les deux insèrent | 500 sur la clé primaire | rejoué (5 fois) : la seconde trouve la ligne et applique « dernier écrivain gagne » ; une vraie violation remonte telle quelle |

Les corrections 6 et 7 se couvrent dans `TransactionRejoueeTest` (simulation d'erreurs SQL : SQLite
ne les produit jamais) ; la sonde réelle est décrite au §2.5.

### 2.3 Audit statique (requêtes brutes et migrations)

Tout `DB::raw`, `whereRaw`, `selectRaw`, `orderByRaw`, `DB::statement` du serveur a été relu :

- **Portables, inchangés** : `COALESCE`, `SUM(CASE …)`, `COUNT`, `GROUP BY` complet
  (`ONLY_FULL_GROUP_BY` est actif et la suite passe), `lower(code) = ?`, `select 1 … not exists`.
- Aucun `strftime`, `julianday`, `substr` sur dates, `||`, `ifnull`, `group_concat`, `insert or`,
  `random()`, `glob`, `COLLATE NOCASE`, `pragma`, `rowid` dans `app/`, `routes/`, `database/`.
- Index : les clés composées `(portee_reference varchar(36), reference varchar(40))`,
  `(espece, code)`, `(annee, mois)` sont très en dessous des 3 072 octets d'InnoDB `DYNAMIC`.
  Les clés `varchar(255)` de Laravel (`users.email`, `permissions (name, guard_name)`) exigent
  `DYNAMIC` (**MySQL ≥ 5.7.7, MariaDB ≥ 10.2**) ; sur une version plus ancienne, voir §5.3.
- `uuid` = `char(36)` ; `double` (montants et quantités) : mêmes valeurs aller-retour sur les trois
  moteurs ; strict : aucun `NO_ZERO_DATE` rencontré.
- `datetime(6)` : toutes les colonnes de curseur et de « dernier écrivain gagne » des faits sont
  `datetime(6)`. Les sept référentiels dont le curseur est `updated_at` (`timestamps()`, précision
  de la seconde) écrivent des secondes entières sur SQLite comme sur MySQL ; le recouvrement
  (`SYNC_RECOUVREMENT_SECONDES = 2`) couvre l'arrondi.
- **Collation** : `utf8mb4_unicode_ci` est insensible à la casse **et aux accents** (`é = e`). Les
  références (`V-P1-2026-001`), codes (`INT-001`), UUID sont en forme canonique côté poste ;
  l'unicité devient insensible à la casse sur MySQL (plus stricte que SQLite, jamais plus lâche).
  La recherche « contient » trouve `LAINE` pour `laine`, sur les trois moteurs.

### 2.4 Résultats

| Essai | Moteur | Résultat |
|---|---|---|
| Suite PHP complète | MariaDB 10.11.14 | **1635 / 1635** (avant les corrections 4, 6 et 7, qui n'ont pas changé le comportement MariaDB) |
| Suite PHP complète | MySQL 8.0.46 (serveur en `Europe/Paris`) | 1636 / 1641 au 1ᵉʳ passage (correction 4), puis **1647 / 1647** |
| Essai réel poste ↔ serveur (55 essais, écrans web par `tinker` compris) | MariaDB 10.11.14 | **55 / 55** |
| Essai réel poste ↔ serveur | MySQL 8.0.46 | **55 / 55** |
| Essai réseau réel (mandataire, 20 essais) | MySQL 8.0.46 et SQLite | **20 / 20** sur chacun |
| Suite PHP + essai réel 55/55 | SQLite (référence) | verts après toutes les corrections |
| Sonde de concurrence (4 postes, mêmes 150 lignes en sens opposés, 12 tours, Apache + mod_php) | MySQL 8.0.46 | 23 × 500 avant, **0** après (3 passes) |

### 2.5 Rejouer

```bash
# Suite PHP sur MySQL / MariaDB (phpunit.xml pose sqlite sans `force` : l'environnement l'emporte)
cd logialvia_laravel
DB_CONNECTION=mysql DB_HOST=127.0.0.1 DB_DATABASE=lv_test DB_USERNAME=… DB_PASSWORD=… php artisan test

# Essai réel poste ↔ serveur sur MySQL (base `lv_essai` recréée)
LV_BASE=mysql LV_MYSQL_USER=… LV_MYSQL_PASSWORD=… bash logialvia_app/outils/essai_vrai_serveur.sh
```

Le job `.github/workflows/mysql.yml` (service `mysql:8` et `mariadb:10.11`) rejoue la suite PHP,
l'essai réel et l'essai réseau à chaque modification du serveur, du moteur de synchronisation ou de
`outils/`. **Il n'a pas pu être exécuté ici** (pas de GitHub Actions dans le bac à sable) : c'est
la transposition de commandes qui, elles, ont été exécutées ; son premier passage sur GitHub est à
surveiller.

## 3. Réseau réel

### 3.1 Le mandataire de test

`logialvia_app/outils/mandataire_reseau.py` (bibliothèque standard + `openssl`) est un mandataire
inverse devant le vrai serveur ; ses règles se changent à chaud (`PUT /regles`) et il tient un
journal des requêtes vues. Il reproduit : TLS (autorité maison, certificats **valide**,
**auto-signé**, **expiré**, **mauvais nom**), `LimitRequestBody` (413 HTML), coupure après N octets
du corps, **coupure après le traitement mais avant la réponse**, coupure en pleine réponse, retard
avant/après le traitement, statuts arbitraires (502/503/504/429 + `Retry-After`), redirection
301/302, page HTML d'hébergeur, `Authorization` (et `X-Authorization`) retiré.

```bash
ESSAI_RESEAU=1 bash logialvia_app/outils/essai_vrai_serveur.sh          # base jetable SQLite
ESSAI_RESEAU=1 LV_BASE=mysql LV_MYSQL_USER=… bash logialvia_app/outils/essai_vrai_serveur.sh
```

Le script lance le serveur, les mandataires (clair + 4 TLS) et un second serveur à
`post_max_size=3K` (vrai 413 de PHP), puis `test/integration/reseau_reel_test.dart`.
**La vérification TLS du poste n'est jamais désactivée** : le test fournit à un client une
autorité maison (comme le ferait son installation dans Windows) et prouve que tout autre certificat
est refusé.

### 3.2 Défauts trouvés (tous corrigés, chacun avec essai faux serveur ET essai réel)

La couche HTTP du poste est désormais unique : `lib/core/sync/transport_http.dart`, partagée par le
moteur et l'appairage. Avant, chaque `Exception` réseau devenait « Serveur injoignable ».

| Défaut | Avant | Maintenant |
|---|---|---|
| **TLS** (auto-signé, autorité inconnue, expiré, mauvais nom, serveur sans HTTPS) | « Serveur injoignable : hors ligne » | refus net, message précis en français, **jamais** de rejeu, jeton conservé ; « pas reconnu / expiré / ne correspond pas à l'adresse « … » / ne répond pas en HTTPS » |
| **413** (`LimitRequestBody`, `post_max_size`) | « Le serveur a refusé la demande (HTTP 413) », lot perdu à chaque cycle | lots plafonnés en **octets** (256 Kio) puis **dichotomie** à chaque 413 (rien n'a été traité, donc ni perte ni doublon) ; plafond appris, jamais redemandé ; une ligne seule trop grosse est refusée avec son motif (`conflict`) sans bloquer les autres |
| **Coupure en plein lot** (réponse perdue après traitement) | « hors ligne » au 1ᵉʳ cycle | rejeu immédiat (3 essais, 0,5 s puis 2 s) ; l'envoi est idempotent par UUID : aucun doublon, aucune ligne perdue, curseur avancé seulement après la dernière page |
| **Réponse lente** | confondue avec « hors ligne » | message distinct (« met trop de temps »), reprise au cycle suivant ; si le serveur avait traité, le rejeu ne crée rien |
| **502 / 503 / 504 / 429** | refus générique | rejeu en respectant `Retry-After` (plafonné à 15 s, sinon pas d'attente) ; au bout : état « hors ligne » neutre + message (« momentanément indisponible », message du serveur pour 429) |
| **Redirection 301/302 http → https** | un POST redirigé n'était pas suivi (`dart:io`) : échec | suivie (POST compris) **uniquement** vers `https` du **même hôte** ; l'adresse corrigée est mémorisée ; toute autre redirection est refusée (le jeton ne part jamais ailleurs) |
| **Page HTML d'hébergeur** (200, 404, 401, 5xx) | « Réponse du serveur inattendue » ou texte HTML | message clair (« page web au lieu de données… vérifiez l'adresse ») |
| **401 qui n'est pas celui de l'application** (protection du dossier, `Authorization` retiré) | le poste **oubliait son jeton valide** : appairage perdu, et la reconnexion ne servait à rien | seul un 401 JSON de l'application fait oublier le jeton ; `jeton_absent` / `jeton_invalide` distingués par le serveur |
| **`Authorization` retiré** par Apache CGI/FastCGI | 401 permanent, sans explication | le poste envoie le même jeton aussi dans `X-Authorization` ; `RestaurerEnTeteAutorisation` (serveur) le rend ; 401 `jeton_absent` explicite si rien n'arrive |

### 3.3 Essais

- **`test/core/sync/reseau_defaillant_test.dart`** (faux serveur, 33 essais, sans attente réelle) :
  413 (dichotomie, plafond appris, ligne trop grosse, plafond en octets), coupures (réponse perdue,
  persistante, tirage coupé à la page 2, réseau qui revient en plein cycle), lenteurs (tirage, envoi
  traité puis rejoué), 502/503/504/429, HTML, 401 (HTML / `jeton_absent` / JSON), double en-tête,
  redirections (suivie, autre site refusée), TLS (4 certificats, mauvais port), appairage.
- **`test/integration/reseau_reel_test.dart`** (vrai serveur + mandataire, 20 essais) : TLS (auto-signé,
  expiré, mauvais nom, autorité maison refusée par défaut puis acceptée et synchro de bout en bout),
  413 par le mandataire **et par le vrai `post_max_size` de PHP** (60 puis 40 clients : chacun une
  fois, vérifié par un second poste), coupure avant la réponse, coupure en plein corps, coupure
  persistante puis retour du réseau, réponse du tirage tronquée, réponse en 2 s avec un délai de
  700 ms, 502/503/504 passagers, 503 persistant, 429 + `Retry-After: 120`, HTML, `Authorization`
  retiré, `Authorization` + `X-Authorization` retirés, redirection 301 http → https.
- **Vrai Apache 2.4.58** (hors mandataire), sur MySQL 8 :
  - mod_php + `.htaccess` de Laravel : jeton accepté ;
  - **`LimitRequestBody 3000`** : le vrai 413 HTML d'Apache fait découper les envois du poste, 40 clients
    arrivent chacun une fois ;
  - **PHP en CGI sans les règles `Authorization`** (cas du `.htaccess` ignoré) : `Authorization`
    n'arrive jamais à PHP → 401 `jeton_absent` ; avec `X-Authorization` : 200, et le poste synchronise
    (40 clients) de bout en bout.

## 4. Les interblocages en un coup d'œil

`TransactionRejouee::executer()` remplace `DB::transaction($f, 3)` pour l'envoi (`/api/sync/push`),
les demandes de référentiel et la lecture des demandes de synchronisation. Interblocage
(SQLSTATE 40001 / erreurs 1213, 1205) : jusqu'à 8 essais avec attente aléatoire de 10–40 ms × n, puis
`ServeurOccupe` → **503 `serveur_occupe` + `Retry-After: 1`**. Doublon de clé (1062) : jusqu'à 6 essais
puis l'erreur d'origine. Toute autre erreur SQL n'est jamais rejouée.

## 5. Configuration d'hébergement recommandée

### 5.1 `public/.htaccess` (déjà dans le dépôt)

```apache
RewriteEngine On

# Authorization : trois filets, du plus classique au dernier recours.
RewriteCond %{HTTP:Authorization} .
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
<IfModule mod_setenvif.c>
    SetEnvIfNoCase ^Authorization$ "(.+)" HTTP_AUTHORIZATION=$1
</IfModule>
# 3ᵉ filet, sans rien à régler : le poste envoie aussi le jeton dans X-Authorization.
```

À ajouter à la racine du domaine si l'hébergeur n'impose pas déjà HTTPS (jamais d'HTTP clair en
production : le jeton du poste y voyagerait) :

```apache
RewriteCond %{HTTPS} !=on
RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
```

Le poste suit cette redirection (même hôte) et mémorise l'adresse `https://`.

Limites Apache : ne **pas** poser de `LimitRequestBody` en dessous de 1 Mio ; s'il existe (même bas),
le poste s'adapte (dichotomie), au prix de plus de requêtes. Un `<Directory>` avec
`AllowOverride None` et des règles écrites à la main doit reprendre les lignes `Authorization` ci-dessus.

### 5.2 `php.ini` (ou `.user.ini`)

```ini
post_max_size = 8M          ; le poste n'envoie jamais plus de 256 Kio par requête (il découpe)
upload_max_filesize = 8M
memory_limit = 256M
max_execution_time = 60     ; un tirage complet paginé reste bien en dessous
max_input_vars = 1000       ; sans effet : l'API reçoit du JSON, pas de formulaire
display_errors = Off        ; jamais de page d'erreur PHP en clair
```

`max_input_vars` ne concerne que `$_POST` en `x-www-form-urlencoded` : le corps JSON est lu par
`json_decode`. `post_max_size` dépassé donne un 413 que le poste sait absorber.

### 5.3 MySQL / MariaDB

- **MySQL ≥ 5.7.7 ou MariaDB ≥ 10.2** (format de ligne `DYNAMIC`, index jusqu'à 3 072 octets). Plus
  ancien : `innodb_large_prefix=ON`, `innodb_file_format=Barracuda`, `ROW_FORMAT=DYNAMIC`, ou
  `Schema::defaultStringLength(191)` (réduit les `string()` sans longueur : à vérifier avant).
- `character_set_server = utf8mb4`, collation `utf8mb4_unicode_ci` (celle de la connexion Laravel).
- Mode strict (Laravel l'impose à la connexion : `ONLY_FULL_GROUP_BY` inclus).
- `.env` : `DB_CONNECTION=mysql` (ou `mariadb`), `DB_TIMEZONE=+00:00` (valeur par défaut),
  `APP_TIMEZONE=UTC`. L'utilisateur applicatif n'a besoin ni de `SUPER` ni de `FILE`.
- `max_allowed_packet ≥ 16M`, `innodb_lock_wait_timeout = 50` (défaut) : la couche de rejeu absorbe les
  interblocages, pas les attentes de verrou de plusieurs minutes.
- Sauvegarde : `mysqldump --single-transaction` ; les colonnes JSON étant du texte, aucun traitement
  spécial.

### 5.4 HTTPS

- Certificat **public** (Let's Encrypt, AutoSSL de l'hébergeur) : rien à faire sur les postes.
- Autorité de l'entreprise : l'installer dans Windows (« Autorités de certification racines de
  confiance ») ; le poste utilise le magasin du système. Un certificat auto-signé isolé, expiré ou au
  mauvais nom est **refusé** avec un message qui dit pourquoi.
- Certificat renouvelé automatiquement : surveiller l'expiration (le poste affiche « certificat expiré »
  mais ne synchronise plus tant que ce n'est pas réglé, par conception).

### 5.5 Limites utiles

| Paramètre | Valeur | Où |
|---|---|---|
| Lignes par envoi | 100 (`tailleLot`) | poste |
| Poids d'un envoi | 256 Kio (`octetsMaxEnvoi`), divisé par 2 à chaque 413 | poste |
| Rejeux réseau | 3 essais, 0,5 s puis 2 s ; `Retry-After` jusqu'à 15 s | poste |
| Délai d'une requête | 30 s (synchro), 15 s (appairage) | poste |
| Lignes par page de tirage | `logialvia.sync.lignes_par_page` | serveur |
| Interblocage | 8 essais, 10–40 ms × n puis 503 | serveur |

## 6. Ce qui n'est PAS prouvé

- **Un hébergeur mutualisé réel** : ni sa version de MySQL, ni son WAF (mod_security, Imunify), ni ses
  limites de processus ou de connexions simultanées, ni son quota d'écritures. Les pièges connus sont
  reproduits (413, `Authorization`, 502/503, HTML, redirection), pas l'hébergeur lui-même.
- **MySQL 5.7 et MariaDB 10.3–10.4**, `ROW_FORMAT=COMPACT` : non essayés (seuls 8.0.46 et 10.11.14 l'ont été).
- **Performances et charge** : la sonde de concurrence compte 4 postes ; pas de test de montée en charge
  (dizaines de postes, bases de plusieurs centaines de milliers de lignes).
- **Le job GitHub Actions `mysql.yml`** (non exécuté ici, voir §2.5).
- **Les clients `e-MECeF`** (`transmission_mecef.dart`, API de la DGI) : leur propre client HTTP n'a pas
  été durci par cette étape (hors synchronisation poste ↔ serveur).
- **TLS 1.0/1.1, certificats à chaîne intermédiaire incomplète** : le refus est celui de `dart:io`
  (« autorité inconnue ») ; le message est correct mais le cas n'a pas d'essai dédié.
- **L'accent et la casse dans les références** sous collation `utf8mb4_unicode_ci` : plus stricte que
  SQLite, sans cas métier connu qui en pâtisse ; non éprouvée sur des données réelles.

## 7. Fichiers

| Fichier | Rôle |
|---|---|
| `logialvia_laravel/app/Support/RechercheLike.php` | recherche « contient » portable |
| `logialvia_laravel/app/Support/TransactionRejouee.php`, `ServeurOccupe.php` | interblocages et doublons |
| `logialvia_laravel/app/Http/Middleware/RestaurerEnTeteAutorisation.php` | `X-Authorization` → `Authorization` |
| `logialvia_laravel/database/migrations/2026_11_09_164000_*` | `ordre` des lignes ; JSON → `LONGTEXT` (MySQL) |
| `logialvia_laravel/tests/Feature/Sync/{PortabiliteMysql,TransactionRejouee,AuthorizationHebergeur}Test.php` | essais PHP |
| `logialvia_app/lib/core/sync/transport_http.dart` | couche HTTP du poste |
| `logialvia_app/outils/mandataire_reseau.py` | mandataire de test |
| `logialvia_app/outils/essai_vrai_serveur.sh` | `LV_BASE=mysql|mariadb`, `ESSAI_RESEAU=1` |
| `logialvia_app/test/core/sync/reseau_defaillant_test.dart` | 33 essais, faux serveur |
| `logialvia_app/test/integration/reseau_reel_test.dart` | 20 essais, vrai serveur + mandataire |
| `.github/workflows/mysql.yml` | CI MySQL 8 / MariaDB 10.11 |
