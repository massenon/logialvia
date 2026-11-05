# F1 — Module : Authentification & Démarrage

Écrans concernés : `index.html`→Splash, `welcome.html`→Welcome, `login.html`→Login (Doc F0/03 pour la correspondance complète).

**⚠️ Document corrigé après implémentation réelle et relecture ligne par ligne des 3 fichiers HTML source.** La première version de ce document décrivait plusieurs comportements qui ne correspondaient pas au prototype (spinner au lieu d'une barre de progression, redirection vers `/dashboard`, auto-login) et omettait 3 fonctionnalités réellement présentes dans `login.html`. Les corrections sont signalées section par section.

---

## Écran 1 — Splash (`index.html` → `splash_screen.dart`)

**Objectif** : écran de démarrage, vérifie l'état de l'application (base de données accessible, migrations à jour, compte administrateur présent) avant de rediriger.

### Sections (ordre strict, fidèle au prototype — ⚠️ corrigé)
1. Emblème centré : cercle de 80 px, fond blanc 10 %, bordure blanche 2 px, icône `egg` 44 px
2. Mot-symbole "Logi**ALVIA**" (24 px, extrabold, "ALVIA" en `brand-gold`)
3. Accroche "GESTION ET SUIVI AVICOLE INTÉGRÉ" (11 px, `brand-gold-light`, `tracking-[0.15em]`)
4. Sous-titre "Couveuse • Élevage • Stocks • Ventes • Relances Clients"
5. "ALLMANY ET COMPAGNIE" (14 px, bold, blanc)
6. "Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB)" (12 px, `brand-gold-light`)
7. **Barre de progression** pleine largeur (6 px, fond blanc 15 %, remplissage `brand-gold-light` animé de 0 % à 100 % en 3 s, linéaire)
8. **Message d'état rotatif** — 5 messages qui défilent toutes les 600 ms
9. Mention basse "v1.0.0 — © 2026 FAGUEZ SARL"

**Correction n°1 — il n'y a pas de spinner.** La première version parlait d'un « indicateur de chargement (spinner) » et d'un texte « Initialisation… ». Le prototype (`index.html` l.40-45) utilise une **barre de progression** et **5 messages qui tournent**, repris ici mot pour mot :
```
"Vérification de la base de données locale…"
"Initialisation du moteur de synchronisation…"
"Chargement des cycles de couveuse en cours…"
"Sécurisation de l'espace de stockage…"
"Chargement du catalogue de stocks et de vaccins…"
```

### Comportement — ⚠️ corrigé

**Correction n°2 — la destination n'est pas `/dashboard`, et il n'y a pas d'auto-login.** Le prototype (`index.html` l.67-77) ne consulte aucune session : il regarde uniquement si c'est le **tout premier lancement**.

```
premier lancement  -> /welcome
lancements suivants -> /login
```

Aucun mécanisme d'auto-login n'existe dans le prototype, et aucune table de session n'existe en Doc D1 — l'utilisateur passe **toujours** par l'écran de connexion.

```dart
Future<void> initialiser() async {
  // 1. Ouvre reellement la base et applique les migrations en attente
  //    (LazyDatabase etant paresseuse, la premiere requete declenche les deux)
  await _database.customSelect('SELECT 1').get();

  // 2. Peuple roles + compte administrateur si la base est vierge (Doc K4 §8)
  final aSemeAdmin = await _seeder.executer();

  // 3. ECART_DELIBERE : le prototype detecte le premier lancement via
  //    localStorage.logialvia_visited. Sans equivalent en Flutter Desktop, le
  //    signal "le seeder vient de creer le compte" porte exactement la meme
  //    information, sans stockage supplementaire.
  _routeCible = aSemeAdmin ? '/welcome' : '/login';

  // 4. Duree minimale d'affichage : 3 s (setTimeout du prototype), completee
  //    si le travail reel a ete plus rapide.
}
```

**Ajout — état d'erreur d'initialisation.** Le prototype n'a pas d'équivalent (aucune base à ouvrir côté web). Si la base est inaccessible, le Splash doit afficher un message explicite et un bouton **Réessayer** : sans cela, l'écran resterait figé sans explication. Le message reste générique côté utilisateur, le détail technique n'étant journalisé que sous `kDebugMode` (Doc I3 §3).

**KPIs** : aucun sur cet écran (pas applicable).

---

## Écran 2 — Welcome (`welcome.html` → `welcome_screen.dart`)

**Objectif** : écran d'accueil de présentation avant connexion, avec bouton d'entrée vers Login.

### Sections
1. Illustration/emblème de la ferme
2. Titre + accroche
3. Bouton primaire "Se Connecter" → `/login`

**Boutons** : 1 seul bouton primaire, position centrée basse — fidèle au prototype, pas de repositionnement.

---

## Écran 3 — Login (`login.html` → `login_screen.dart`)

**Objectif** : authentification, sélection implicite du rôle (déterminé par le compte, pas par un sélecteur manuel en production — le sélecteur RBAC visible sur les autres écrans du prototype est un outil de **test/démonstration**, pas une fonctionnalité de production, voir Doc I1).

### Sections (ordre strict — ⚠️ complété après lecture réelle de `login.html`)

Carte blanche centrée (largeur max 460 px, `rounded-2xl`, `shadow-2xl`, padding 32 px) sur fond dégradé navy 165° + texture de grain :

1. **Barre langue/version** alignée à droite : pilule bordée « 🌐 Français », puis « v1.0.0 »
2. **En-tête de marque** : icône `egg` 38 px navy + "Logi**ALVIA**" (22 px, `font-black`) + "ALLMANY ET COMPAGNIE" (9 px), puis, séparé par un filet, "GESTION ET SUIVI AVICOLE INTÉGRÉ"
3. **Bandeau de 7 icônes** encadré haut et bas : `egg`, `inventory_2`, `point_of_sale`, `receipt`, `vaccines`, `campaign`, `account_balance`
4. **Accroche** : "Bienvenue !" (20 px, bold, navy) + "Connectez-vous à votre espace LogiALVIA."
5. **Bannière de verrouillage** (masquée par défaut)
6. Champ **NOM D'UTILISATEUR OU EMAIL** (icône `person` à gauche)
7. Champ **MOT DE PASSE** (icône `lock` à gauche, bouton œil afficher/masquer à droite)
8. Ligne : case **« Se souvenir de moi »** — lien **« Mot de passe oublié ? »**
9. Bouton primaire pleine largeur « 🔓 SE CONNECTER » (44 px)
10. Pied de carte : "© 2026 LogiALVIA — Projet d'Appui à l'Entrepreneuriat au Bénin (PAEB) — FAGUEZ SARL"

**Correction n°3 — 3 éléments réels étaient absents de ce document** : le bandeau de 7 icônes (§3), la case « Se souvenir de moi » (§8) et le verrouillage après échecs répétés (§5, détaillé ci-dessous). La mention « Mot de passe oublié — à confirmer, non détaillé dans le prototype » était fausse : `login.html` l.116-126 contient une modale complète.

### Formulaire & Validations (Doc E6)
| Champ | Règle | Message d'erreur (verbatim du prototype) |
|---|---|---|
| Nom d'utilisateur ou email | Requis, non vide après `trim()` | "L'adresse e-mail est obligatoire." |
| Mot de passe | Requis, non vide après `trim()` | "Le mot de passe est obligatoire." |

Champ invalide : bordure `error-deep` **et** fond `error-container` (classe `.is-invalid`), message rouge 11 px sous le champ. Un toast « Veuillez renseigner tous les champs requis. » accompagne l'erreur — il ne la remplace pas.

### Boutons
| Bouton | Action |
|---|---|
| Se Connecter (primaire) | Valide le formulaire → vérifie les identifiants contre `UTILISATEURS` (Doc D1) → si succès : toast « Connexion réussie — Bienvenue ! », **700 ms d'attente**, puis `/dashboard` avec le rôle chargé en session → si échec : erreur sous le formulaire + toast, jamais un toast seul |
| Œil (afficher/masquer) | Bascule `visibility` ⇄ `visibility_off` |
| Mot de passe oublié ? | Ouvre la modale (voir ci-dessous) |

### Cas d'Erreur
- Identifiant inconnu **ou** mot de passe incorrect : message strictement identique dans les deux cas, ne jamais préciser lequel est erroné. Libellé du prototype : **« Adresse e-mail ou mot de passe incorrect. Veuillez réessayer. (n/5) »**, où `n` est le nombre d'échecs consécutifs.
- Chaque échec est consigné dans `SECURITY_LOGS` (`typeEvenement = 'echec_connexion'`, Doc I3 §6). Le mot de passe saisi n'apparaît jamais dans le journal.
- Une connexion réussie est consignée dans `AUDIT_LOGS` (`action = 'connexion'`), la déconnexion également.

### Verrouillage après 5 échecs — ⚠️ absent de la version précédente

Comportement réel (`login.html` l.159-214), à reproduire tel quel :
- Compteur d'échecs consécutifs ; au **5ᵉ** échec, le compte est verrouillé **900 secondes (15 min)**
- Le bouton « Se connecter » passe en désactivé, et la bannière `#lock-banner` apparaît : *« Trop de tentatives de connexion. Accès bloqué pendant **15min**. »*, le compteur passant ensuite au format `Mmin Ss` à chaque seconde
- **Aucun toast n'est affiché au 5ᵉ échec** — seule la bannière apparaît. Ce détail est facile à manquer et fait partie du comportement fidèle.
- À l'expiration : bannière masquée, bouton réactivé, compteur remis à zéro

**Limite connue** : le verrou n'est pas persisté (ni côté web, ni côté Flutter) — fermer puis rouvrir l'application le remet à zéro. C'est le comportement du prototype, pas un oubli. Un verrouillage réellement persistant relèverait d'un durcissement à décider explicitement (Doc I3 §6 évoque cette piste sans la trancher).

### Modale « Mot de passe oublié » — ⚠️ écart délibéré assumé

Le prototype affiche un champ e-mail et un bouton « Envoyer le lien de réinitialisation » dont le **seul effet réel est un toast de succès** (`login.html` l.145) : aucun envoi n'a lieu. C'est précisément le pattern interdit par le Master Prompt §2.3, qui cite nommément le cas `validateSale()`. Il est de plus structurellement impossible à honorer : LogiALVIA Desktop fonctionne hors-ligne, sans appel réseau ni configuration SMTP (Doc B1 §7, Doc I3 §3).

**Décision** : la modale conserve son titre, sa taille et sa place dans le parcours, mais indique la seule procédure réellement disponible — réinitialisation par l'administratrice depuis la gestion des utilisateurs — au lieu de simuler un envoi. Un `TODO(dette)` est posé dans le code pour restaurer le champ et le bouton d'envoi du prototype le jour où la configuration e-mail de Doc F8 existera.

### Point non tranché — « Se souvenir de moi »

La case est présente et fonctionnelle à l'écran, mais **ne persiste rien** : aucun mécanisme de session persistante n'existe (pas de `shared_preferences`, aucune table de session en Doc D1). Deux issues possibles, à décider : ajouter un stockage de session, ou retirer la case. En l'état, elle est un vestige visuel du prototype — signalé plutôt que silencieusement laissé à moitié fonctionnel.

---

## Point Ouvert — ✅ TRANCHÉ : Mécanisme d'Authentification

Le prototype HTML de référence ne contient pas de logique de hachage de mot de passe observable (application côté client uniquement). La recommandation initiale — SHA-256 avec sel, via le package `crypto` — **a été validée explicitement avant implémentation** et est désormais en place :

- Colonnes `motDePasseHash` et `sel` ajoutées à `UTILISATEURS` (Doc D1, corrigé)
- Sel aléatoire de 16 octets (`Random.secure()`), encodé base64, **propre à chaque compte** — deux comptes partageant le même mot de passe ont donc des hash différents
- Hash = `SHA-256(sel + motDePasse)`, stocké en hexadécimal (64 caractères)
- Comparaison **en temps constant** : une comparaison `==` classique s'arrête au premier caractère différent et fuiterait de l'information par son temps d'exécution
- Le mot de passe en clair n'est jamais persisté ni journalisé

**Réserve honnête** : SHA-256 salé est adapté au contexte (poste local, hors-ligne, base protégée par les droits du dossier applicatif) mais reste un hachage **rapide** — il n'oppose pas la résistance au bruteforce hors-ligne d'un `bcrypt`/`argon2`. Si le fichier `.db` devait un jour circuler hors du poste, c'est le chiffrement de la base au repos (`sqlcipher_flutter_libs`, déjà signalé en Doc I3 §4 comme non tranché) qui apporterait la vraie protection, davantage que le changement d'algorithme de hachage.

---

## Compte Administrateur Initial (Seeder) — Doc K4 §8

Au premier lancement la base est vide : aucun compte ne permet de se connecter. Le seeder crée, **de façon idempotente**, les 3 rôles réels (Doc I1 §1) puis le compte administrateur.

| Élément | Valeur |
|---|---|
| Identifiant | `admin` (valeur littérale de Doc K4 §8) |
| Nom | `Administratrice Principale` |
| Rôle | `admin` |
| Mot de passe initial | `ALLMANY2026` — arbitré par la Gérante le 25/08/2026. Le `placeholder` du champ **lit désormais cette constante** (`AdminSeeder.motDePasseInitialAdmin`) au lieu de la recopier : une indication qui suggère un mot de passe refusé est pire que pas d'indication du tout. Valeur précédente : `LogiALVIA@2026`, reprise du `placeholder` de `login.html` l.95 |

**Garanties vérifiées par test automatisé** : un 2ᵉ appel ne recrée rien ; les libellés de rôle existants ne sont pas écrasés (`insertOrIgnore`) ; un compte déjà renommé et dont le mot de passe a été changé par l'utilisatrice réelle n'est jamais réinitialisé.

**ECART_DELIBERE — placeholder du champ identifiant** : `login.html` affiche `gerante@allmany.bj`, un compte de démonstration codé en dur dans le JavaScript du prototype et qui n'existe pas en base. Conserver ce placeholder induisait concrètement en erreur sur l'identifiant à saisir. Le champ affiche donc `admin`, l'identifiant du compte réellement créé.

**`TODO(dette)` ouvert** : le mot de passe initial est en dur dans `AdminSeeder`. Il devra devenir modifiable — et son changement forcé à la première connexion — dès que l'écran Mon Profil (Doc F9) existera.
- **Ceci est une recommandation de sécurité standard (NFRS-SEC), pas une donnée extraite du prototype** — à valider explicitement avant implémentation, car le prototype ne spécifie pas ce niveau de détail

## « Se souvenir de moi » — la dernière case décorative

La case existait depuis le portage initial et **ne pilotait qu'elle-même** : `_seSouvenirDeMoi` était lu par la case, écrit par la case, et rien d'autre ne le regardait. C'était le dernier manquement debout à la règle cardinale du projet — *zéro fonctionnalité décorative* (Cahier des Charges §2.3), celle-là même dont `validateSale()` est l'exemple à ne jamais reproduire.

Le prototype ne fait pas mieux : `login.html` l.101 déclare la case sans lui attacher le moindre gestionnaire.

### ⚠️ On mémorise l'identifiant, jamais la session

« Se souvenir de moi » **ne rouvre pas la session**. Le mot de passe reste exigé à chaque lancement ; la case pré-remplit le champ identifiant et envoie le curseur au mot de passe.

C'est ce que le libellé promet — *se souvenir de moi*, pas *reste connectée* — et le choix n'est pas de la prudence de principe. LogiALVIA tourne sur **un poste partagé** entre trois rôles, dont un point de vente qui manipule des espèces. Une session rouverte automatiquement donnerait à quiconque ouvre l'ordinateur les droits du dernier connecté, et viderait de leur sens le verrouillage après 5 tentatives, la journalisation `AUDIT_LOGS` et le RBAC entier.

Le gain réel — ne pas retaper son identifiant chaque matin — est conservé sans rien céder de tout cela. Deux tests le verrouillent : aucune préférence ne contient le mot de passe, et une application relancée n'a **pas** de session ouverte.

### Trois règles de comportement, testées

- L'écriture n'a lieu qu'après une connexion **réussie** — mémoriser un identifiant refusé le proposerait ensuite en boucle.
- **Décocher efface** l'identifiant déjà mémorisé : laisser l'ancien en base contredirait le geste de la Gérante.
- Au retour sur l'écran, la case **reflète l'état réel**. Une case décochée alors que l'identifiant revient serait un mensonge de plus.

### Barre latérale — le second réglage perdu

`common.js` l.27-42 restaure `logialvia_sidebar_hidden` au chargement de chaque page. Côté Flutter, la barre repartait dépliée à chaque lancement : le réglage était à refaire tous les matins, alors que c'est justement sur les petits écrans qu'on la replie pour gagner de la place.

### `PREFERENCES_POSTE` — v20

Table clé/valeur minuscule, **séparée de `PARAMETRES_ENTREPRISE`** : celle-ci décrit ALLMANY et suivrait la base si elle était copiée sur un autre ordinateur, alors qu'un identifiant mémorisé ou une barre repliée n'ont de sens que sur la machine où on les a réglés.

Pas de `shared_preferences` : la base est déjà locale au poste (`getApplicationSupportDirectory`), une dépendance de plus n'apporterait qu'une seconde source de vérité.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **547 tests au vert** dont 13 dédiés · build **release** compilé, packagé et lancé · migration **v19 → v20**.
