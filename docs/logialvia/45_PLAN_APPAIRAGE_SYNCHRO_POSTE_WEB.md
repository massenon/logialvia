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

## 6c. Ce que l'appairage du poste a livré (P1b), et ses limites

**Poste Flutter** (`lib/core/sync/`, onglet « Appairage » de Paramètres Généraux, 33 tests, 8 mutations vérifiées) :

- **Identifiant du poste** : UUID v4 tiré une seule fois, gardé dans `preferences_poste` (`poste.identifiant`), jamais régénéré. Aucune migration de schéma (v30 inchangée).
- **Adresse du serveur** normalisée (schéma ajouté : `http` en réseau local, `https` ailleurs ; `/` finaux retirés ; vide ou autre schéma refusé).
- **Jeton au coffre du système** (`flutter_secure_storage`), jamais en base ; le **mot de passe n'est ni gardé ni journalisé** et le champ est vidé dès l'envoi. Seul le code de poste (`P2`), le compte web et la date sont mémorisés.
- **Appairer** = `POST /api/auth/login` avec `device_name` = UUID du poste ; **Tester la connexion** = `GET /api/auth/me` ; **Déconnecter** (avec confirmation) efface toujours le jeton local, et dit si le serveur n'a pas pu être prévenu.
- **401 = révocation** : le poste oublie le jeton et redemande une connexion, sans toucher à ses saisies. **Hors ligne n'est jamais une révocation** : le poste reste appairé.
- Les comptes locaux sont inchangés (DV-20) ; l'onglet dit que « appairé » n'est pas « synchronisé » (P2).

**Limites connues** : testé contre un **faux serveur** qui rejoue les réponses de `AuthController` ; l'essai contre le vrai serveur Laravel reste à faire (dernière étape). Restaurer une sauvegarde sur une **autre machine** copie l'identifiant du poste : il faudra proposer de le régénérer (`TODO(dette)`). Le manuel utilisateur ne décrit pas encore l'onglet.

## 6d. Palier 1 de la migration UUID et premier moteur de synchronisation du poste

**Fait (09/11/2026)** — table `clients`, de bout en bout :

- **Schéma v31** : `clients.id` passe en UUID (texte) ; colonnes `sync_status` (`pending`/`synced`/`conflict`), `sync_motif`, `updated_at` (instant de **saisie**, texte ISO 8601 UTC à la microseconde : Drift stocke les dates à la seconde, trop grossier pour « dernier écrivain gagne »). `device_id` n'est pas stocké : le serveur le déduit du jeton. Migration testée sur une **vraie base v30** (UUID distincts, données conservées, clients existants `pending`, rejouable sans changer un UUID). Aucune autre table ne référence `clients.id` (les ventes retiennent le nom du client) : la reconstruction est sans cascade.
- **Moteur** (`lib/core/sync/moteur_synchronisation.dart`) : pull puis push, curseur du serveur avancé à la dernière page seulement, tirage paginé à borne `until`, lots d'envoi de 100, accusé qui ne marque `synced` que si la ligne n'a pas bougé depuis l'envoi, refus → `conflict` avec le motif du serveur, 401 → jeton oublié (saisies conservées), hors ligne ≠ erreur, remise à zéro du serveur → purge et décompte des saisies non envoyées perdues, une seule synchronisation à la fois. Brancher une table = écrire une `TablePoste`.
- **Règle d'absorption** : une ligne locale non envoyée n'est écrasée que si la version du serveur est **strictement plus récente** (même règle que le serveur). *Défaut trouvé et corrigé en écrivant les tests* : avec « jamais écrasée », un poste gardait une saisie que le serveur avait ignorée comme trop ancienne, la croyait synchronisée, et ne convergeait jamais.
- **Écran** : bouton « Synchroniser maintenant » dans l'onglet Appairage, avec rapport chiffré ; le bandeau dit que seuls les clients sont synchronisés.
- **Tests** : 52 sur le moteur, contre un faux serveur qui rejoue la **logique** du serveur (arbitrage, curseur, pagination, marque), 13 mutations vérifiées ; **5 essais contre le vrai serveur Laravel** (appairage, deux postes, saisie ancienne en retard, refus avec le vrai motif, révocation) — `test/integration/serveur_reel_test.dart`.

**Limites levées au palier 2 (§6e)** : référentiels et synchronisation automatique. **Limites restantes** : la suppression d'un client n'existe pas au poste ; les ventes retiennent le NOM du client (un homonyme est indiscernable : à traiter au palier des ventes) ; 21 fichiers de tables restent en entiers.

## 6e. Palier 2 : référentiels et synchronisation automatique

**Référentiels** (`modules_actifs`, `parametres_entreprise`) : le serveur gagne, le poste ne les envoie jamais, une remise à zéro les préserve. Trois garde-fous, chacun né d'un risque concret :

- **Valeur de semis ≠ décision.** Une ligne que personne n'a jamais modifiée côté serveur (`updated_at == created_at`) n'est pas absorbée : le web est installé vide, le poste tient les vraies données (IFU, RCCM, modules choisis par la Gérante) et aucun chemin de retour n'existe encore (`POST /sync/demandes`). Une ligne absente du poste est toujours créée.
- **Un `null` du serveur n'efface jamais** une valeur locale.
- **Jamais absorbés** : `chemin_logo` / `chemin_favicon` (chemins de CETTE machine), `mode_donnees_test` (le verrou de sécurité de la remise à zéro : un serveur ne doit pas pouvoir le lever), l'identifiant. Un module inconnu du poste, un booléen incohérent, un préfixe vide ou trop long : refusés, jamais devinés.

**Synchronisation automatique** (`PlanificateurSynchronisation`, démarré par `main.dart`) : à l'ouverture ; toutes les 30 s `GET /sync/demande` (« synchronise maintenant » servi une fois, « renvoyer vers ce poste » = tirage **complet** puis acquittement, *uniquement si le tirage a réussi*) ; **après un geste** (saisie locale, temporisée 3 s : une rafale = un envoi ; garde « rien à envoyer » : l'accusé ne relance rien) ; routine toutes les 5 min ; bouton. **Aucun minuteur tant que le poste n'est pas appairé** ; un 401 le **suspend** (plus un seul appel) jusqu'à un nouvel appairage ; hors ligne = on réessaie sans bruit. La barre du haut reçoit un indicateur **réel** (en cours, à jour à HH:MM, hors ligne, à vérifier, non appairé) à la place du badge « 3 en attente » du prototype, écrit en dur ; la barre latérale n'a pas besoin du bouton retiré (Appairage + barre du haut).

*Défaut trouvé par les tests* : l'effacement du curseur avant un tirage complet ne s'était pas appliqué, donc « Renvoyer vers ce poste » ne renvoyait rien.

**Tests** : 88 sur le moteur, les référentiels, le planificateur et l'indicateur (faux serveur à logique réelle) ; **7 essais contre le vrai serveur Laravel** dont les référentiels (décidé appliqué, semis ignoré) et la demande/renvoi/acquittement. Mutations vérifiées sur les gardes ; deux sont *équivalentes* et le restent : ne pas désarmer les minuteurs à la suspension (le garde `_suspendu` les rend inertes) et démarrer un poste non appairé (le moteur répond « non appairé » sans appeler le serveur).

**Limites** : pas de synchronisation à la fermeture (`windowManager.destroy()` ne se retarde pas sur un réseau incertain) ; le poste ne peut toujours pas modifier un référentiel vers le serveur (`POST /sync/demandes`, W4+) ; les modifications faites au web sur les modules ne sont reçues qu'après `updated_at > created_at`, ce que seul un enregistrement par l'écran web garantit.

## 6f. Les trois limites du palier 2, levées

**1. Le poste propose ses modifications de référentiel** (`POST /api/sync/demandes`).
- *Serveur* : le poste **propose**, le serveur **décide**. Droit vérifié par type (`manage-modules`, `manage-parametres`) ; **idempotent par l'UUID de la demande** (journal `demandes_referentiel` : une demande rejouée rend la même issue sans rien réappliquer) ; une demande plus **ancienne** que la dernière décision du serveur est refusée (« une modification plus récente existe… ») ; une demande acceptée **décide** la ligne (`updated_at` avance, même si la valeur est identique à celle du semis) et redescend vers tous les postes ; champs interdits (`chemin_logo`, `mode_donnees_test`, `marque_remise_a_zero`, `id`) refusés en bloc ; une valeur vide n'efface jamais celle du serveur. 17 tests, 8 mutations (la 8e a révélé le cas « valeur identique », désormais testé).
- *Poste* (schéma **v32**, table `demandes_referentiel`) : chaque modification locale d'un module, des paramètres ou des formats de numérotation dépose une demande (une seule en attente par clé : la dernière saisie remplace la précédente). Le moteur les envoie après les faits ; accusé seulement si la demande n'a pas été remplacée ; refus → `conflict` avec le motif du serveur, jamais renvoyé en boucle.
- **Règle du plus récent, des deux côtés** : à l'absorption, une demande locale en attente n'est supplantée que par une décision du serveur **postérieure** à la saisie du poste (sinon le tirage, qui passe *avant* l'envoi, aurait défait un choix fait hors ligne). Elle tombe alors, et le rapport le dit.

**2. Adoption initiale.** Quand le serveur n'a jamais décidé (valeur de semis) et diffère du poste, le poste lui **propose** ses valeurs une fois : le web installé vide apprend l'IFU, le RCCM et les modules choisis par la Gérante. Une fois la ligne décidée, la règle du semis cesse de jouer : un changement fait au web redescend normalement.

**3. Synchronisation à la fermeture** : `synchroniserALaFermeture`, bornée à **4 s** (une fenêtre qui ne se ferme pas parce que le réseau est coupé serait pire qu'une saisie qui attend l'ouverture suivante ; elle reste `pending`, l'envoi étant idempotent). Elle n'envoie que s'il y a quelque chose, jamais pour un poste suspendu ou non appairé, et `main.dart` ferme la fenêtre **quoi qu'il arrive** (`finally`).

**Tests** : 108 sur la synchronisation du poste, 161 côté serveur, **9 essais contre le vrai serveur Laravel** (dont : demande d'un administrateur acceptée puis reçue par un second poste ; demande d'un caissier refusée avec le vrai motif). Mutations : 12 sur le poste ; deux restent *équivalentes* par construction — l'accusé d'une demande n'a pas besoin de comparer la date (une demande remplacée change d'identifiant) et la fermeture d'un poste suspendu (`_lancer` refuse déjà).

**Reste** : le branchement `onWindowClose` de `main.dart` n'est pas testable sans fenêtre (le comportement qu'il appelle l'est) ; `POST /sync/demandes` ne couvre que `module_actif` et `parametres_entreprise` (les autres référentiels — barèmes, calendrier de prophylaxie, plan comptable… — attendent leur palier).

## 6g. Palier 3 (poste) : produits, lignes de vente et ventes en UUID

**Fait (09/11/2026), schémas v33 et v34, côté poste uniquement** — la synchronisation des ventes avec le serveur est le palier suivant (§6h).

- **v33 — `produits_vendables` et `lignes_vente` en UUID.** `lignes_vente.produit_id` suit. La migration passe par une table de correspondance ancien entier → nouvel UUID : **chaque ligne de vente garde son produit** (vérifié par jointure sur une vraie base v32, ids volontairement non consécutifs), les produits déjà **archivés en corbeille** voient leur instantané réécrit (sinon ils reviendraient sans UUID), aucune ligne orpheline (`PRAGMA foreign_key_check`), rejouable sans changer un UUID.
- **v34 — `ventes`** reçoit son `id` (UUID, unique), `client_id`, `sync_status`, `sync_motif`, `updated_at`. **La clé primaire reste `ref`** : lignes, écritures comptables et factures s'y rattachent par texte, et la reconstruire aurait touché tout le comptable. `ref` est le **numéro officiel** remis au client (DV-21) ; `id` est l'identité synchronisée. Une vente existante est `pending` et son instant de saisie est **sa date de vente** (pas l'instant de la migration : il ferait gagner une vieille vente contre une correction faite ailleurs). Vérifié : **les lignes ne sont pas emportées par `ON DELETE CASCADE`** quand la table est reconstruite.
- **Références à préfixe de poste (DV-21)** : `V-P2-2026-001` pour un poste appairé, `V-2026-001` pour un poste jamais appairé ; séquence continue **par poste et par année** ; aucune renumérotation rétroactive. Le **code attribué survit à la déconnexion** (sinon un poste déconnecté mélangerait ses références avec celles d'avant l'appairage). `P1` et `P12` ne se mélangent pas (le préfixe se termine par un tiret).
- **`client_id` — la limite des homonymes, levée autant que possible.** Le POS saisit un nom libre : la vente est rattachée au client **si un seul client porte ce nom** (casse et espaces ignorés) ; **deux homonymes ou un nom libre (« Client Comptant ») : `client_id` reste vide**, on ne devine pas qui a acheté, le nom saisi est conservé tel quel. La migration fait de même pour les ventes existantes. *Reste* : un vrai sélecteur de client au POS (le champ est du texte libre) lèverait l'ambiguïté à la source.
- Toute modification locale d'une vente (annulation, règlement d'une avance) la **remet à envoyer** avec un nouvel instant de saisie.
- **Tests** : migrations v33 (8) et v34 (7) sur de vraies bases antérieures, références et liaison client (15) ; 14 mutations vérifiées (v33 : 5, ventes et v34 : 9).

## 6h. Palier 3c : produits et ventes synchronisés (serveur et moteur) — fait

**Serveur** (`logialvia_laravel/`, 196 tests, 14 mutations) :
- Tables `produits_vendables` (référentiel, **sans stock**), `ventes` et `lignes_vente`.
- **Une vente et ses lignes forment un lot** : validées ensemble, écrites ensemble, **refusées ensemble** (un produit inconnu rejette toute la vente, aucune ligne orpheline), servies ensemble au tirage (`lignes` imbriquées). Les lignes sont **immuables** après création ; l'entête suit « dernier écrivain gagne » ; la référence ne change jamais.
- **Règle d'unicité de la référence (validée par le client)** : unique pour tous quand elle porte un code de poste (`V-P2-2026-001`), **unique par poste** sans code (`V-2026-001`, ventes d'avant l'appairage : deux postes peuvent l'avoir). Un doublon est refusé avec son motif.
- Droits : lecture `view-ventes`, écriture `manage-ventes` ; ni stock ni écriture comptable côté serveur (le fait est enregistré, rien d'autre). `clients.solde_creance` est **dérivé** par le serveur (restes dus des avances non annulées), jamais accepté d'un poste.
- **Produits par demande** (`type: produit_vendable`) : stock refusé, contenu identique accepté sans conflit (deux postes semés du même catalogue), demande plus ancienne refusée, droit `manage-ventes`. Un envoi direct reste ignoré.
- Le moteur a été **généralisé** : `TableSync::absorber()` (par défaut : ligne plate en dernier écrivain gagne ; `VentesTable` le surcharge).

**Poste** (schémas v33-v34 inchangés ; 142 tests de synchronisation) :
- **UUID déterministes pour les produits** (SHA-1, `sku|désignation`) : deux postes installés du même programme donnent le **même** identifiant à « Goliath mature » (sinon doublon au serveur). Appliqué au catalogue semé **et à la migration v33** ; un doublon exact sur un même poste se départage par son ancien entier.
- **Adoption du catalogue** (une fois) : le poste propose tout son catalogue au serveur, car ses ventes référencent ses produits.
- **Ordre du moteur : tirage → demandes → faits.** Les produits partent AVANT les ventes ; sans cela, toute vente d'un produit créé au poste serait refusée.
- `TableProduitsPoste` : le serveur gagne, **jamais le stock** (un produit d'un autre poste arrive avec un stock de 0 ; un produit connu garde le sien), règle du plus récent contre une demande locale en attente, lignes incohérentes refusées.
- `TableVentesPoste` : envoi d'une vente avec ses lignes ; **absorption d'une vente d'un autre poste sans décrément de stock, sans écriture comptable, sans compteur de fiche, sans événement** (ces effets appartiennent au poste qui a vendu) ; absorbeur strict ; règle du plus récent ; lignes immuables ; accusé seulement si la vente n'a pas bougé depuis l'envoi.
- **Sélecteur de client au POS** : saisie avec suggestions (nom **et téléphone**, ce qui distingue deux homonymes) ; choisir dans la liste mémorise l'identifiant, retoucher le texte l'oublie ; un nom ambigu tapé à la main affiche un message ; un nom libre reste possible. La limite des homonymes du §6g est levée **à la source**.
- **Tests** : 35 sur produits et ventes, 16 sur le sélecteur ; mutations : 15 + 8, dont 3 survivantes d'abord (tests trop faibles, renforcés) et 1 équivalente (supprimer les ventes emporte déjà leurs lignes par cascade). **11 essais contre le vrai serveur Laravel**, dont deux postes qui vendent et reçoivent la vente de l'autre avec un stock inchangé, et une avance dont le solde est calculé par le serveur.

**Limites** : la comptabilité et le stock du poste ne sont pas synchronisés (autres paliers) — une remise à zéro du serveur vide donc les ventes du poste mais **pas** ses écritures ni ses compteurs ; une ancienne référence sans code déjà prise par une autre vente **de ce poste** ne peut pas coexister localement (la clé primaire est `ref`) : la vente reçue est refusée et comptée, pas écrasée ; la suppression d'un produit (archivage) n'est pas propagée ; **18 fichiers de tables** restent en entiers.

## 6i. Palier 4 : fournisseurs et achats (poste v35, serveur, moteur) — fait

**Même schéma que les ventes** (§6g-§6h), sans les produits à adopter.

- **Poste, schéma v35** : `fournisseurs`, `achats` et `lignes_achat` en UUID ; `achats.fournisseur_id` suit (table de correspondance ancien entier → UUID, supprimée en fin de migration) ; `achats` reçoit `id`, `sync_status`, `sync_motif`, `updated_at` ; **la clé primaire reste `ref`**, le numéro officiel, jamais renuméroté (DV-21). Un achat d'hier est « à envoyer » et son instant de saisie est **sa date d'achat**. Les fournisseurs reçoivent un UUID **aléatoire** (saisis par l'utilisatrice, jamais semés identiquement). Vérifié sur une **vraie base v34** : chaque achat garde son fournisseur (jointure), aucune ligne emportée par `ON DELETE CASCADE`, intégrité référentielle intacte, rejouable sans changer un UUID.
- **Références** : `ACH-P2-2026-001` (poste appairé) ou `ACH-2026-001` (jamais appairé), séquence par poste et par année, code conservé après déconnexion. **Correction du contrat** : le `46_` §3 annonçait `A-P2-…` ; le préfixe réel des achats du poste est **`ACH`**, conservé.
- **Serveur** : `fournisseurs` (fait plat, dernier écrivain gagne), `achats` + `lignes_achat` (lot : acceptés ou refusés ensemble, servis ensemble, lignes immuables, référence jamais changée), **même règle d'unicité** que les ventes (globale avec code de poste, par poste sans code). Lecture `view-achats`, écriture `manage-achats` : seul l'administrateur écrit, le comptable consulte, le caissier et l'animalier n'y ont pas accès (conforme à `config/logialvia.php`). 216 tests, 8 mutations.
- **Moteur du poste** : `TableFournisseursPoste`, `TableAchatsPoste`. **Absorber l'achat d'un autre poste ne produit aucun effet** : ni entrée de stock, ni recalcul du PMP, ni mouvement journalisé, ni écriture comptable (la réception appartient au poste qui a reçu la marchandise). Un achat dont le fournisseur ou un intrant est inconnu du poste est **refusé et compté**, jamais écrasé ; une pierre tombale ne supprime jamais un fournisseur. Réceptionner ou régler un achat le remet à envoyer.
- **Purge à la remise à zéro dans l'ordre INVERSE des dépendances** (les achats avant leur fournisseur) : sinon la clé étrangère refuse la suppression. Corrigé dans le moteur pour toutes les tables.
- **Tests** : 26 (poste), 20 (serveur), migration v35 (7) ; **13 essais contre le vrai serveur**, dont deux postes qui achètent (achat livré compris) et un caissier refusé avec le vrai motif.

**Défauts trouvés en chemin (tous dans mon infrastructure de test, pas dans le moteur)** : le faux serveur avait une **horloge figée à 10 h UTC** et comparait des dates **en texte** (`…625Z` après `…625655Z`) : des tests passaient ou échouaient selon l'heure de la journée et la microseconde. L'horloge ne peut plus être en retard sur une ligne détenue, les instants émis lui sont postérieurs, les comparaisons portent sur des instants analysés ; 6 exécutions consécutives stables.

**Limites** : les **intrants** (leur stock, leur PMP) et les **mouvements** ne sont pas synchronisés : deux postes qui achètent le même intrant ont chacun leur stock, l'achat de l'un n'alimente pas celui de l'autre (c'est le sujet « stock partagé », non traité) ; un intrant créé sur un poste est inconnu des autres, qui refusent alors les achats qui le portent ; la remise à zéro du serveur vide achats et fournisseurs du poste mais **pas** son stock, ses mouvements ni ses écritures ; le **règlement d'une dette fournisseur** ne crée aucune écriture chez les autres postes ; **16 fichiers de tables** restent en entiers.

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
| W3 | Contrat et moteur `pull`/`push` serveur, essai multipostes | W2 | **fait** (09/11/2026) pour 3 tables (référentiels + clients), 129 tests, mutations vérifiées ; voir `46_` §6. W3b livré aussi (demandes, resynchronisation, remise à zéro ; 144 tests) ; reste `POST /sync/demandes` et les 35 autres tables, voir `46_` §7 |
| P0 | **Contrat de synchronisation** écrit (tables, ordre, règles par donnée) | — | à faire, sans réseau |
| P1a | Poste : migration UUID par paliers (DV-19) et références à préfixe de poste (DV-21) | — | **paliers 1, 3 et 4 faits** : `clients` (v31), produits, lignes de vente, ventes (v33-v34), fournisseurs, achats, lignes d'achat (v35), références à préfixe de poste ; voir §6d-§6i. Restent 16 fichiers de tables |
| P1b | Poste : appairage (identifiant de poste, adresse, jeton au coffre, onglet Appairage) | W2 (ou faux serveur) | **fait** (09/11/2026) : voir §6c |
| P2 | Poste : moteur de synchronisation (pending, envoi, réception, descente) + bouton et modale | W3 (ou faux serveur) | **moteur fait** pour modules, paramètres, produits, clients, ventes (§6d-§6h) ; reste les autres tables |
| W4+ | Écrans web par module, conformes au Dart | W1 | **en cours** : W4a coque, W4b Catalogue (§7) ; reste les autres écrans |

Règle : chaque étape se termine par l'analyse, la suite de tests complète et un commit ; rien n'est déclaré fait
sans avoir tourné.

### 6j. P5 — Intrants et journal (09/11/2026)
Poste : migration v36 (`mouvements_intrant.id` en UUID, `origine`, `sync_status`), `TableIntrantsPoste`,
`TableMouvementsIntrantPoste`, demandes d'intrants, libellé « autre poste » dans Gestion des stocks. Serveur :
tables `intrants` / `mouvements_intrant`, droits lecture/écriture par table. Voir `46_` §14.
Essais : `journal_sync_poste_test.dart` (25), `migration_v36_mouvements_test.dart`, `IntrantsEtJournalTest.php`.
Non fait : essai contre le vrai serveur Laravel pour ces deux tables.

### 6k. P6 — Stock des produits vendables (09/11/2026)
Poste : migration v37 (`mouvements_produit`), journal des corrections de stock du catalogue,
`TableMouvementsProduitPoste`. Serveur : table `mouvements_produit` et `MouvementsProduitTable`. Voir `46_` §15.
Essais : `journal_produits_sync_poste_test.dart` (19), `migration_v37_mouvements_produit_test.dart`,
`JournalProduitsTest.php` (11). Non fait : essai contre le vrai serveur Laravel pour cette table.

Limites levées après P6 : motif de correction saisi au formulaire ; suppression de produit propagée par pierre tombale
(`archive_le`, voir `46_` §15). Essais : `suppression_produit_sync_poste_test.dart` (8), `ProduitsDemandesTest.php` (+6).

## 7. W4+ — Écrans web (09/11/2026)

**W4a — La coque.** Barre laterale `config/navigation.php`, **transcrite du Dart** (`navigation_model.dart`) et comparee a lui par
`ConformiteNavigationDartTest` (groupes, ordre, libelles, icones, routes, modules). Une entree est visible quand le compte a le droit
de sa route (matrice `config/logialvia.php`) ET que son module est actif (filieres optionnelles inactives par defaut ; `mecef` suit le
reglage de l'entreprise). Chaque route du poste a son adresse web : tant que l'ecran n'est pas converti, la page « bientot » la
tient, droit et module deja verifies (403 / 404). `/` mene a `/dashboard`. Liste des ecrans convertis : `routes_web_implementees`.

**W4b — Catalogue & Seuils** (`/catalogue`, droit `view-stocks` ; ecriture `manage-ventes`). Liste, recherche, filtre de categorie,
ajout / modification / suppression par modales. Toute ecriture passe par `DemandesReferentiel::traiter` : memes regles que pour un
poste (validation, droit, dernier ecrivain gagne, audit, historique, poste « web » = UUID nul). La suppression pose la pierre tombale
(`46_` §15) que les postes archivent a leur tour. **Ecarts assumes avec le Dart** : pas de colonne « Stock », de « valeur du catalogue »
ni de tableau des seuils critiques (le stock est propre a chaque poste) ; pas d'icones Material Symbols (police non embarquee) ;
l'icone d'un produit cree au web est `category`.

**Reste a convertir** (page « bientot ») : tableau de bord, filieres d'elevage, ventes, clients, inventaire, factures MeCeF, achats,
fournisseurs, depenses, gestion des stocks, comptabilite (6 ecrans), rapports, parametres, profil, aide, contact.
