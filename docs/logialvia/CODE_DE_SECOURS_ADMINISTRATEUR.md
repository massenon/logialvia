# CODE_DE_SECOURS_ADMINISTRATEUR — Que faire si l'administrateur perd son mot de passe

**Constat d'ensemble (vérifié dans le code) : LogiALVIA n'a ni code de secours imprimable, ni commande artisan de
réinitialisation, ni envoi de lien par e-mail.** Ce document décrit ce qui existe réellement, côté web et côté poste Windows, et la
procédure de remplacement. La section « Ce qui n'existe pas (encore) » (§5) le dit sans détour.

Les deux applications ont **chacune leurs propres comptes** (DV-20 : « les comptes locaux d'un poste restent propres au poste »,
`app/Services/UtilisateursService.php` et `app/Models/User.php`). Un mot de passe web perdu et un mot de passe poste perdu sont
deux problèmes distincts.

Liés : `GUIDE_DEPLOIEMENT.md` §6, `47u_ADMINISTRATION_PARITE.md`, `ESSAIS_EN_PRODUCTION_ET_REINITIALISATION.md`.

---

## 1. Ce qui existe : le web (`logialvia_laravel/`)

### 1.1 Compte initial

`AdminSeeder` (`database/seeders/AdminSeeder.php`), lancé par `php artisan db:seed` (via `DatabaseSeeder`) :

- crée le compte `ADMIN_INITIAL_USERNAME` (par défaut `admin`) avec `ADMIN_INITIAL_PASSWORD` **uniquement si** cette variable est
  définie et conforme (8 caractères, 1 majuscule, 1 chiffre : `app/Support/RegleMotDePasse.php`) ; sinon il avertit et ne crée rien
  (`AdminSeeder.php:21-27`) ;
- pose `must_change_password = true` : le changement est exigé à la première connexion (middleware `mdp.web`,
  `app/Http/Middleware/ChangementMotDePasseObligatoireWeb.php`, route `/mot-de-passe`) ;
- utilise `firstOrCreate` sur l'identifiant : **il n'écrase jamais un compte existant**. Essai réalisé pour ce document sur une
  base SQLite jetable : après un second `db:seed` avec une autre valeur de `ADMIN_INITIAL_PASSWORD`, le mot de passe du compte
  existant était inchangé. **Modifier `ADMIN_INITIAL_PASSWORD` puis relancer `db:seed` ne rétablit donc pas un mot de passe perdu.**

### 1.2 Changer son propre mot de passe (le connaître)

Web : « Mon Profil » (`/profil`, `app/Livewire/Profil.php`) et l'écran `/mot-de-passe`
(`app/Livewire/Auth/ChangerMotDePasse.php`). Il faut saisir **l'ancien** mot de passe ; le nouveau doit respecter la règle (8
caractères, 1 majuscule, 1 chiffre) et différer de l'ancien. Les jetons des postes du compte sont supprimés (les postes doivent se
réappairer). Action d'audit : `web.mot_de_passe_change`.

### 1.3 Réinitialisation par un autre administrateur (procédure normale)

Écran **Paramètres généraux > Gestion Utilisateurs** (`app/Livewire/GestionUtilisateurs.php`, bouton « Mot de passe » de chaque
compte, modale « Réinitialiser le mot de passe », `resources/views/livewire/gestion-utilisateurs.blade.php`). Service :
`UtilisateursService::reinitialiserMotDePasse` (`app/Services/UtilisateursService.php:234`).

| Règle | Détail |
|---|---|
| Droit | `manage-users` (le rôle `admin` seul, `config/logialvia.php` `role_permissions`) |
| Compte visé | jamais soi-même (« Pour changer votre propre mot de passe, passez par Mon Profil. ») |
| Mot de passe saisi | règle 8 car. / 1 majuscule / 1 chiffre, avec confirmation |
| Effet | mot de passe **temporaire** : `must_change_password = true` (le titulaire doit en choisir un autre à la connexion) ; **tous les jetons** du compte (postes appairés) sont supprimés |
| Audit | `utilisateur.mdp_reinitialise` (compte visé et nombre de jetons supprimés ; jamais le mot de passe) |

Garde-fous du compte administrateur (`UtilisateursService.php`) : le **dernier administrateur actif** ne peut être ni supprimé, ni
désactivé, ni rétrogradé ; nul ne peut se désactiver, se supprimer ou changer son propre rôle. Le web peut attribuer le rôle
Administrateur (décision D1 de `47u_`). Les comptes supprimés vont à la Corbeille (restauration par un administrateur) ;
l'identifiant d'un compte supprimé reste réservé (`47u_` §2).

La connexion web n'a **aucune limite d'essais** (décision du client du 2026-11-11, `app/Livewire/Auth/Connexion.php:46`, et
`routes/api.php` pour l'appairage) : aucun compte ne se verrouille après des échecs ; les échecs sont journalisés (`login.failed`).

### 1.4 Dépannage quand aucun administrateur ne peut se connecter (hors fonctionnalités de l'application)

Si le seul administrateur a perdu son mot de passe, **aucun écran ne peut le rétablir**. Le seul moyen est l'accès au serveur
(Terminal cPanel / SSH) avec l'outil standard de Laravel `tinker` (`laravel/tinker` est dans `composer.json`). Ce n'est pas une
fonction de LogiALVIA ; la commande ci-dessous a été **essayée sur une base SQLite jetable** (mot de passe posé, hachage par le cast
`hashed` du modèle `User`, `must_change_password` à 1) mais **pas sur un hébergeur réel**.

```bash
cd /home/UTILISATEUR/logialvia
php artisan tinker --execute='$u = App\Models\User::where("username", "admin")->firstOrFail(); $u->forceFill(["password" => "MotDePasseTemporaire1", "must_change_password" => true, "is_active" => true])->save(); $u->tokens()->delete(); echo "ok\n";'
```

Précautions :

- Choisir un mot de passe temporaire conforme (8 car., 1 majuscule, 1 chiffre) : la règle n'est **pas** vérifiée par cette
  commande ; une valeur non conforme resterait utilisable à la connexion mais violerait la politique.
- La commande reste dans l'historique du shell : l'effacer, et faire changer le mot de passe immédiatement (le compte est
  marqué `must_change_password`).
- Un compte **supprimé** (Corbeille) n'est pas trouvé par `User::where(...)` (suppression logique) : il faut d'abord le restaurer,
  ce qu'un administrateur fait depuis la Corbeille ; sans administrateur, ajouter `User::withTrashed()` et `restore()` n'a pas été
  essayé ici.
- Sans accès shell, l'alternative est de modifier la colonne `users.password` par phpMyAdmin avec un hachage bcrypt produit
  ailleurs : **non essayé, non recommandé**.
- Hors de cette procédure d'exception, ne pas lancer `php artisan migrate:fresh` ni `db:seed` en espérant « réparer » :
  le premier détruit les données, le second ne touche pas un compte existant.

## 2. Ce qui existe : le poste Windows (`logialvia_app/`)

### 2.1 Écran de connexion et modale « Mot de passe oublié »

Le lien « Mot de passe oublié ? » de `login_screen.dart:264` ouvre une **modale d'information** (`afficherModaleMotDePasseOublie`,
`administration/presentation/screens/auth/widgets/modale_mot_de_passe_oublie.dart`). Aucun e-mail n'est envoyé (le poste est
hors ligne par conception) : le fichier documente cet écart délibéré du prototype. Son texte renvoie à « l'administratrice, depuis
la gestion des utilisateurs ».

**Cette promesse n'est pas tenue côté poste** : l'onglet « Gestion Utilisateurs » du poste ne permet que d'**ajouter** et de
**supprimer** un compte (`parametres_generaux_view_model.dart` : `creerUtilisateur`, `supprimerUtilisateur`) ; il n'existe aucune
action « réinitialiser le mot de passe » d'un autre compte (aucune méthode de ce type dans `compte_repository_drift.dart` ni
`parametres_repository_drift.dart`). `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` (tableau, ligne E7) le consigne : « création et suppression
seulement ; pas de modification, archivage, réinitialisation par l'administrateur ». Le poste n'a pas non plus de
« mot de passe temporaire » (pas de colonne `doit_changer_mot_de_passe` dans le poste).

### 2.2 Changer son propre mot de passe

« Mon Profil » (`compte_view_model.dart`, `changerMotDePasse`) : ancien mot de passe obligatoire, nouveau conforme (8 car.,
1 majuscule, 1 chiffre), différent de l'ancien. Il faut donc être connecté.

### 2.3 Compte initial du poste

`AdminSeeder` Dart (`administration/data/seed/admin_seeder.dart`) crée, sur une base vierge seulement, le compte `admin` avec le mot
de passe de la constante `motDePasseInitialAdmin` (écrite dans le code source, donc connue de quiconque lit le dépôt). Le fichier
indique que le changement n'est **pas forcé** à la première connexion. Il ne recrée jamais un compte existant. À changer au
premier lancement (« Mon Profil »). Le poste ne limite pas non plus les essais (`auth_view_model.dart`, `verrouille` toujours
faux : décision du client du 2026-11-10).

### 2.4 Outil de secours du poste : `reinitialiser_mot_de_passe_admin.dart`

C'est **le seul moyen** de rendre l'accès à un poste dont le mot de passe administrateur est perdu. Fichier :
`logialvia_app/outils/reinitialiser_mot_de_passe_admin.dart`. Syntaxe :

```bash
dart run outils/reinitialiser_mot_de_passe_admin.dart <base> <mot-de-passe> [identifiant]
```

- `<base>` : le fichier SQLite du poste, `logialvia.db`, dans le dossier de données de l'application
  (`getApplicationSupportDirectory()`, `app_database.dart:1651` ; sous Windows `%APPDATA%\ALLMANY ET COMPAGNIE\LogiALVIA`, d'après
  `47w_INSTALLATEUR_WINDOWS.md`, **à vérifier sur le poste**). `[identifiant]` vaut `admin` par défaut.
- L'outil emploie le hachage de l'application (`HachageMotDePasse`), **régénère le sel**, n'écrit jamais le mot de passe en clair, et
  **relit** la base après écriture pour vérifier que le mot de passe rouvre bien la session (échec explicite sinon).
- Il faut un SDK Dart/Flutter et le dépôt sur la machine du poste (`dart run` depuis `logialvia_app/`) : **l'installateur Windows
  ne livre pas cet outil** (rien dans `build_windows.bat` ni l'installateur ne le copie ; vérifié par recherche du nom du fichier
  dans `logialvia_app/`). La procédure suppose donc l'intervention d'un technicien équipé.
- Le mot de passe est passé en argument : il reste dans l'historique du terminal ; l'effacer. L'outil ne contrôle pas la règle de
  complexité : choisir 8 caractères, 1 majuscule, 1 chiffre.
- Pré-requis impératif de l'en-tête de l'outil : **copier la base avant de le lancer** et fermer LogiALVIA.

Procédure (technicien), non rejouée ici sur un poste Windows :

1. Fermer LogiALVIA ; copier `logialvia.db` (copie de sécurité).
2. Depuis `logialvia_app/` : `dart run outils/reinitialiser_mot_de_passe_admin.dart "<chemin>\logialvia.db" "NouveauMotDePasse1"`.
3. Lire le message « mot de passe reposé … vérification de connexion réussie ».
4. Ouvrir LogiALVIA, se connecter, puis changer le mot de passe dans « Mon Profil ».

Alternative sans outil : **restaurer une sauvegarde** antérieure dont on connaît le mot de passe (onglet « Sauvegardes »,
restauration appliquée au prochain démarrage, la base actuelle étant conservée : `docs/F8_Module_Parametres_Administration.md`, section « Restauration d'une sauvegarde »). Elle
fait perdre les saisies postérieures à la sauvegarde.

## 3. Procédure recommandée (ce que l'exploitation doit mettre en place)

Parce qu'aucun code de secours n'existe, la prévention est la seule vraie protection :

1. **Au moins deux administrateurs web** : créer un second compte au rôle Administrateur (« Gestion Utilisateurs », rôle attribuable
   par le web, `47u_` D1) et le confier à une seconde personne de confiance. Alors § 1.3 suffit et §1.4 n'est jamais nécessaire.
2. **Fiche papier au coffre** pour chaque mot de passe administrateur (web et poste) : identifiant, mot de passe, date, nom du
   détenteur, sous enveloppe scellée ; à renouveler à chaque changement. C'est une recommandation d'exploitation, pas une fonction
   du logiciel.
3. **Changer les mots de passe initiaux** : celui du web est imposé à la première connexion ; celui du poste
   (`motDePasseInitialAdmin`) ne l'est pas : le changer dès l'installation.
4. **Noter la procédure d'accès serveur** (Terminal cPanel, chemin de l'application) avec la fiche : sans elle, §1.4 est inapplicable.
5. **Sauvegardes régulières** du poste (« Sauvegardes ») et de la base du serveur (`GUIDE_DEPLOIEMENT.md` §11) ; tester une
   restauration.
6. Après tout dépannage, vérifier dans le **journal d'audit web** (`/parametres/audit`, droit `manage-users`) les actions
   `utilisateur.mdp_reinitialise`, `login.failed`.

## 4. Récapitulatif

| Situation | Moyen réel | Source |
|---|---|---|
| Web, un autre administrateur existe | « Gestion Utilisateurs » > « Mot de passe » (temporaire, jetons supprimés) | `UtilisateursService.php:234` |
| Web, mot de passe connu | « Mon Profil » / `/mot-de-passe` | `ChangerMotDePasse.php` |
| Web, seul administrateur, mot de passe perdu | `php artisan tinker` sur le serveur (dépannage, hors application) | §1.4 |
| Poste, mot de passe connu | « Mon Profil » | `compte_view_model.dart` |
| Poste, mot de passe perdu | `outils/reinitialiser_mot_de_passe_admin.dart` sur `logialvia.db`, ou restauration d'une sauvegarde | §2.4 |
| Poste, autre compte perdu | **aucune réinitialisation** par l'administrateur : supprimer puis recréer le compte (seules opérations d'administration disponibles au poste) | §2.1 |

## 5. Ce qui n'existe pas (encore)

Vérifié par recherche dans `logialvia_app/lib`, `logialvia_laravel/app`, `database/` et `routes/` :

- **Aucun code de secours** (ni imprimable, ni stocké, ni à usage unique). `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` décrit un tel
  mécanisme (24 caractères, empreinte SHA-256, usage unique) comme exigence venue d'un autre projet ; il n'est **pas implémenté**
  dans LogiALVIA (aucune occurrence de `codeSecours` / `code_secours` dans le code). Le même guide désigne le script du poste
  comme « équivalent » (§2.4).
- **Aucune commande artisan** de réinitialisation de mot de passe ou de création d'administrateur : le répertoire `app/Console/`
  n'existe pas, aucune classe ne dérive de `Command`, `routes/console.php` ne contient que `inspire`. Le seul seeder est
  `AdminSeeder`, qui ne touche pas un compte existant.
- **Aucun « mot de passe oublié » par e-mail**, web ou poste : aucun envoi de courriel dans l'application (`MAIL_MAILER=log`
  dans `.env.example`, aucun appel `Mail::`), tables `password_reset_tokens` présente (squelette Laravel) mais sans écran.
- **Aucune réinitialisation d'un autre compte au poste** (§2.1), malgré le texte de la modale.
- **Aucune limite d'essais ni verrouillage de compte** (décisions du client), donc rien à « débloquer ».
- **L'outil du poste n'est pas distribué** avec l'installateur (§2.4).

Remplacement : §3 (deux administrateurs, fiche papier au coffre, procédure d'accès serveur) et §1.4 / §2.4 en dernier recours.
Un code de secours imprimable ou une commande `artisan` de réinitialisation seraient des développements à décider avec le client.
