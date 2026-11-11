# LISTE_DES_CRON_JOBS_CPANEL — Tâches planifiées et files : ce que LogiALVIA exige réellement

## Réponse courte

**Le code de LogiALVIA n'exige AUCUNE tâche cron et AUCUN `queue:work`.** Il n'y a aucune tâche planifiée et aucun job à traiter.
Un déploiement cPanel qui ne crée aucune entrée cron est complet.

Cette réponse vient de vérifications, pas d'une supposition (§1). Les tâches du §3 sont des **suggestions d'exploitation**,
étiquetées « facultatif / non requis par le code » ; aucune n'existe dans l'application.

Contexte : `02_ARCHITECTURE_WEB_ET_STACK.md` §9 prévoit « UN seul cron cPanel, `schedule:run` » avec des tâches dans
`routes/console.php` (sauvegarde quotidienne, alertes, etc., modèles tirés d'AgriERP). **Ce planning n'a pas été construit dans
LogiALVIA** ; ce même §9 précise d'ailleurs « Ne pas déclarer de `queue:work` sans job réel ». Lié : `GUIDE_DEPLOIEMENT.md`.

---

## 1. Ce qui a été vérifié

| Vérification | Résultat | Preuve |
|---|---|---|
| Tâches planifiées déclarées | **aucune** | `logialvia_laravel/routes/console.php` ne contient que la commande `inspire` ; `php artisan schedule:list` répond « No scheduled tasks have been defined. » |
| Commandes artisan propres à l'application | **aucune** | le dossier `app/Console/` n'existe pas ; aucune classe ne dérive de `Command` dans `app/` |
| Jobs en file | **aucun** | aucune occurrence de `ShouldQueue`, `Queueable`, `dispatch`, `Bus::`, `Mail::`, `Notification::` dans `app/`, `routes/`, `bootstrap/` (les seules occurrences de `queue(` sont `Cookie::queue` dans `app/Livewire/Auth/Connexion.php`, qui n'a rien à voir avec les files) |
| Pilote de file | `QUEUE_CONNECTION=database` par défaut | `.env.example:38`, `config/queue.php:16` ; la table `jobs` existe (migration `0001_01_01_000002_create_jobs_table.php`) mais **personne n'y écrit** |
| Sessions | `SESSION_DRIVER=database` | `.env.example:30` ; table `sessions` ; ramassage automatique par loterie de Laravel (`config/session.php:117`, `'lottery' => [2, 100]`) : aucun cron nécessaire |
| Cache | `CACHE_STORE=database` | `.env.example:40` ; un seul usage : `Cache::remember` de 30 secondes pour les alertes de la barre (`app/Services/TableauBordService.php:560`) |
| Interrogation périodique | `wire:poll.30s` sur l'indicateur de synchronisation | `resources/views/livewire/indicateur-synchro.blade.php:2` : c'est le navigateur qui interroge le serveur, pas un cron |
| Synchronisation des postes | à l'initiative des postes | le poste appelle `/api/sync/*` toutes les 30 s environ (`core/sync/planificateur_synchronisation.dart`, `47h_` « Planificateur ») : aucun travail de fond du serveur |
| Sauvegarde automatique du serveur | **aucune** | `SauvegardesWeb` ne propose qu'un téléchargement manuel (`app/Livewire/SauvegardesWeb.php`) ; `47u_ADMINISTRATION_PARITE.md` §5 : « la sauvegarde de la base du serveur relève de l'hébergement » |
| Planification de sauvegarde | au **poste** seulement | `SauvegardesWeb` : « planification et vérification se font sur le poste » (commentaire de la classe) |

## 2. Ce qui est requis

| Élément | Requis ? |
|---|---|
| Cron `php artisan schedule:run` | **Non** : aucun planning n'est défini (il ne ferait rien) |
| Processus `php artisan queue:work` / `queue:listen` | **Non** : aucun job n'est jamais mis en file |
| Cron de purge des sessions | **Non** : ramassage par loterie à chaque requête |
| Cron de mise à jour du cache | **Non** |
| Cron d'envoi d'e-mails ou d'alertes | **Non** : l'application n'envoie aucun e-mail |

Le seul « processus de fond » du produit tourne **sur chaque poste Windows** (planificateur de synchronisation), pas sur le serveur.

Note sur `composer dev` : le script `dev` de `composer.json` lance `queue:listen` pour le développement local ; il tourne à vide
(`INSTALLATION_LOCALE.md` §3.3). Ne pas le reproduire en production.

## 3. Tâches utiles — FACULTATIF, NON REQUIS PAR LE CODE

Rien ci-dessous n'est implémenté ni attendu par LogiALVIA. Ce sont des propositions d'exploitation, **non essayées sur un
hébergeur réel**. Dans cPanel : « Tâches Cron ». Le chemin du binaire PHP varie selon l'hébergeur : le vérifier dans le Terminal
avec `which php` ou `php -v` (la CLI doit être en PHP 8.3, comme le site). Dans les lignes ci-dessous, remplacer `UTILISATEUR`
et `/usr/local/bin/php` par les valeurs de l'hébergeur.

### 3.1 Sauvegarde quotidienne de la base (la plus utile)

À défaut de sauvegarde automatique fournie par l'hébergeur (à demander à l'hébergeur : non vérifiable ici). Commande conseillée
par `47r_MYSQL_ET_RESEAU_REEL.md` §5.3 : `mysqldump --single-transaction`. Pour que le mot de passe ne figure pas dans la ligne de
commande, le placer dans `~/.my.cnf` (section `[client]`, droits 600). Le dossier `sauvegardes/` doit exister **hors** de la racine web.

```cron
15 2 * * * mysqldump --single-transaction NOM_BASE | gzip > /home/UTILISATEUR/sauvegardes/logialvia-$(date +\%F).sql.gz
```

(le `%` doit être échappé en `\%` dans un crontab). Nettoyage des copies de plus de 30 jours, facultatif :

```cron
45 2 * * * find /home/UTILISATEUR/sauvegardes -name 'logialvia-*.sql.gz' -mtime +30 -delete
```

Vérifier de temps en temps qu'une copie se **restaure** réellement : une sauvegarde jamais testée n'est pas une sauvegarde.
Garder aussi des copies hors du serveur. La « sauvegarde logique » JSON de l'écran web (Paramètres généraux > Sauvegardes) reste
un téléchargement manuel de l'administrateur et ne se restaure pas au web.

### 3.2 Purge des jetons de poste expirés (facultatif)

Les jetons des postes ont une durée de vie (`SANCTUM_EXPIRATION_JOURS`, 90 jours par défaut : `config/logialvia.php`,
`app/Services/PostesService.php:41`). Un jeton expiré est déjà refusé par l'application (`app/Models/Poste.php:38` ne compte que les
jetons non expirés) ; la commande standard de Sanctum (`sanctum:prune-expired`, présente dans `php artisan list`) ne fait que
nettoyer la table `personal_access_tokens`. Elle n'est **pas nécessaire** au bon fonctionnement.

```cron
30 3 * * 0 cd /home/UTILISATEUR/logialvia && /usr/local/bin/php artisan sanctum:prune-expired --hours=24 >> /dev/null 2>&1
```

À savoir (indépendamment du cron) : aucun renouvellement automatique du jeton n'a été trouvé dans le code (`expires_at` n'est posé que
par l'appairage, `PostesService.php`). Un poste dont le jeton a expiré reçoit un 401 `jeton_invalide` et doit être **réappairé**
(Paramètres généraux > Appairage). À planifier côté exploitation : réappairer les postes avant 90 jours, ou allonger
`SANCTUM_EXPIRATION_JOURS`.

### 3.3 `php artisan schedule:run` : seulement s'il existe un planning

Aujourd'hui, **ne pas créer** cette ligne : elle serait sans effet. Si, plus tard, des tâches sont déclarées dans
`routes/console.php` (décision du client, développement à faire), l'unique cron serait alors, comme le prévoit `02_` §9 :

```cron
* * * * * cd /home/UTILISATEUR/logialvia && /usr/local/bin/php artisan schedule:run >> /dev/null 2>&1
```

Contrôle avant d'ajouter ce cron : `php artisan schedule:list` doit lister au moins une tâche (aujourd'hui : « No scheduled tasks have
been defined. »).

### 3.4 `queue:work` : seulement si un job est un jour ajouté

Aucun job n'existe. Si des jobs sont ajoutés (envoi massif d'e-mails, par exemple), `02_` §9 prévoit alors un cron
`queue:work --stop-when-empty`, avec l'accord du client. Ne pas le créer aujourd'hui.

### 3.5 Purge des sessions, du cache, du journal d'audit

- **Sessions et cache** : rien à planifier (§1). Aucune commande de purge dédiée n'existe dans le projet.
- **Journal d'audit** (`audit_logs`) : aucune purge automatique ni commande n'existe ; le journal est en lecture seule dans
  l'application (`/parametres/audit`). Sa croissance n'a pas été mesurée dans le dépôt.

## 4. Pour les postes Windows : rien à planifier sur le serveur

La synchronisation est pilotée par le poste (`47h_`, « Planificateur et écrans du poste ») ; l'état « hors ligne » est normal
(`47r_` §3.2). Aucune tâche du serveur n'est nécessaire pour qu'un poste rattrape son retard. Les sauvegardes du **poste** se
planifient sur le poste (onglet « Sauvegardes »), pas par cron.

## 5. Ce qui n'existe pas (encore)

- Aucune tâche planifiée (`schedule:list` vide) ; aucun `schedule:run` à brancher.
- Aucun job ni file à traiter ; aucun `queue:work` à superviser.
- Aucune sauvegarde automatique de la base du serveur, aucune purge d'audit, aucune alerte e-mail, aucun rappel de prophylaxie côté
  serveur (ces tâches figurent comme modèles AgriERP dans `02_` §9 ; elles ne sont pas reprises dans LogiALVIA).
- Aucune commande artisan propre à LogiALVIA (`app/Console/` absent).

Procédure réelle de remplacement : §3.1 (cron de `mysqldump`, ou sauvegardes de l'hébergeur) et une revue périodique manuelle
(jetons de poste à 90 jours, espace disque, certificat HTTPS ; voir `GUIDE_DEPLOIEMENT.md` §12).
