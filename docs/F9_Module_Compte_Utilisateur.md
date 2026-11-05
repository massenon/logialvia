# F9 — Module : Compte Utilisateur

Écrans concernés : `mon-profil.html` → `mon_profil_screen.dart`, `aide-a-propos.html` → `aide_a_propos_screen.dart`, `contact-editeur.html` → `contact_editeur_screen.dart`.

---

## Écran 1 — Mon Profil (`mon-profil.html`)

### Structure
1. Informations du compte connecté : Nom, Identifiant, Rôle (lecture seule pour le rôle — un utilisateur ne change pas son propre rôle, réservé à l'Admin via F8)
2. Formulaire de modification du mot de passe (ancien mot de passe requis + nouveau + confirmation)
3. Bouton "Déconnexion"

### Validation (Doc E6)
| Champ | Règle |
|---|---|
| Ancien mot de passe | Doit correspondre au hash actuel |
| Nouveau mot de passe | Non vide, différent de l'ancien |
| Confirmation | Doit être identique au nouveau mot de passe |

---

## Écran 2 — Aide & À Propos (`aide-a-propos.html`)

### Structure
Contenu principalement statique : version de l'application, guide d'utilisation résumé, FAQ. Pas de logique métier significative — écran de consultation.

---

## Écran 3 — Contact Éditeur (`contact-editeur.html`)

### Structure
Formulaire de contact simple (Nom, Message) ou coordonnées statiques de l'éditeur/support technique — à confirmer contre le contenu réel du fichier (même réserve que F7/F8, non audité ligne par ligne dans cette série).

---

## Note — Module le Moins Critique du Système

Ce module a le risque fonctionnel le plus faible du projet (pas de calcul métier, pas de persistance complexe) — à traiter en fin de phase d'implémentation (Doc B2 §7, Phase 5) sans urgence particulière.

---

## Constatations d'implémentation (Flutter Desktop) — Strict Avoid §7

Les 3 écrans sont livrés : `/profil`, `/aide`, `/contact`, atteignables depuis le menu profil de l'en-tête, comme côté web.

### ⚠️ « Le module le moins critique du système » — la conclusion était fausse

La §Note ci-dessus affirme « pas de calcul métier, pas de persistance complexe ». L'audit du HTML montre l'inverse sur deux points :

1. **Mon Profil est le seul écran qui change un secret d'authentification.** C'est la seule opération du logiciel qui touche `UTILISATEURS.motDePasseHash` et `sel`, et elle exige de vérifier l'ancien mot de passe en temps constant avant d'écrire. C'est l'écran le plus sensible du projet, pas le moins.
2. **L'écran comporte un journal d'audit** que le document ne mentionnait pas, et un bloc « Métadonnées de Session ». À l'inverse, le « Bouton Déconnexion » annoncé au point 3 de la §Structure **n'existe pas sur cet écran** — la déconnexion vit dans le menu profil de l'en-tête, sur les 31 pages.

### ✅ Point ouvert résolu — le mot de passe administrateur n'est plus figé

`AdminSeeder` posait `LogiALVIA@2026` avec un `TODO(dette)` : *« mot de passe initial en dur jusqu'à l'écran Mon Profil (F9) »*. Cet écran existe désormais et la Gérante peut réellement changer son mot de passe. La dette est levée.

Détails de l'implémentation :
- L'ancien mot de passe est vérifié **avant** toute écriture, en temps constant.
- Un **sel neuf** est généré à chaque changement : réutiliser l'ancien permettrait de reconnaître qu'un mot de passe déjà employé revient.
- Le changement est tracé dans `AUDIT_LOGS` (BR-ADM-003) **sans jamais journaliser le mot de passe** (Doc I3 §3). Un test parcourt l'intégralité du journal et échoue si l'un des deux mots de passe y apparaît.
- Le message d'erreur distingue « ancien mot de passe incorrect » des autres échecs. C'est volontairement l'inverse de l'écran de connexion, où le message reste générique pour ne pas révéler l'existence d'un compte (Doc I3 §5) : ici l'utilisatrice est déjà authentifiée, un message vague ne protégerait rien et l'empêcherait de comprendre son erreur.

### ⚠️ Les règles de complexité annoncées n'étaient pas appliquées

Le champ affiche « Min. 8 caractères, 1 majuscule, 1 chiffre ». Le script du prototype ne vérifie **que la longueur ≥ 8** — les deux autres règles sont annoncées et jamais appliquées. Les trois le sont désormais : un texte d'aide qui ment est pire que pas de texte du tout. Testé règle par règle.

### Métadonnées de session — ce qui est réel, ce qui ne l'est pas

| Champ du prototype | Traitement |
|---|---|
| Dernière connexion | **Réel** — lu dans `AUDIT_LOGS`. C'est l'**avant-dernière** connexion : la plus récente est la session en cours, l'afficher n'apprendrait rien à l'utilisatrice |
| Adresse IP `192.168.1.24` | **Non repris.** L'application est monoposte et hors-ligne : il n'existe ni session distante ni adresse à journaliser. Remplacé par « Connexions enregistrées », qui est réel, et la raison est affichée à l'écran |
| Statut du compte | Conservé — « Actif » ; aucun mécanisme de désactivation de compte n'existe encore |

**Correctif de robustesse trouvé par les tests** : deux événements d'audit peuvent partager la même milliseconde (une connexion puis une déconnexion immédiate). Un tri sur le seul horodatage rendait alors l'ordre indéfini — donc la « session en cours » potentiellement fausse. Un second critère sur `id` a été ajouté aux trois requêtes concernées.

### Journal d'audit personnel

Les 4 lignes du prototype sont écrites en dur. Ici le journal est filtré sur l'utilisateur connecté, limité aux 20 dernières actions, et `AUDIT_LOGS.entiteConcernee` (une entité technique) est traduit en nom de module affichable (`Vente` → « Point de Vente », `Ecriture` → « Comptabilité »…). Une entité inconnue retombe sur son nom technique plutôt que sur une cellule vide (Doc E7 §1).

### Aide & À Propos — corrections au document

La §Structure disait « contenu principalement statique : version, guide d'utilisation résumé, FAQ ». L'écran réel comporte **3 sections** : une grille de **8 vignettes de modules**, une **FAQ repliable de 5 questions avec recherche**, et un pied de page éditeur. Il n'y a **pas de « guide d'utilisation résumé »**.

Deux points d'implémentation :
- Les vignettes du prototype sont des cartes inertes. Elles conduisent ici réellement au module correspondant — une carte cliquable qui ne fait rien serait décorative au même titre qu'un lien mort.
- La recherche du prototype porte sur un attribut `data-question` normalisé (sans accents), pas sur le libellé affiché : chercher « module » trouve la question « Comment activer ou désactiver une **filière** ? ». Ce comportement est reproduit, la recherche portant sur les mots-clés **et** sur le texte visible.

### ⚠️ Contactez l'Éditeur — le formulaire du prototype est l'anti-patron interdit

`submitContactForm()` affiche `showToast('Message envoyé à l'éditeur.')` **sans rien envoyer ni rien conserver**. C'est exactement le patron que le Master Prompt §2.3 désigne comme le bug à ne jamais reproduire, le même que `validateSale()`.

L'application est hors-ligne, aucun transport e-mail n'est configuré, et le mot de passe SMTP n'est volontairement pas stocké (Doc I3 §3). Deux issues honnêtes étaient possibles : retirer les formulaires, ou leur donner un effet réel.

**Retenu** : le message est **enregistré** dans la nouvelle table `MESSAGES_EDITEUR`, **copié dans le presse-papiers** sous une forme prête à envoyer (en-tête, version du logiciel, identité de l'expéditrice, corps, étapes de reproduction), et l'écran affiche le numéro de l'éditeur avec un bouton de copie. La liste des messages conservés apparaît sous le formulaire, chacun pouvant être recopié, marqué « Transmis » ou supprimé.

Rien n'est perdu, rien n'est promis à tort, et la Gérante a un pas suivant concret. La §Structure du document, qui hésitait entre « formulaire de contact simple (Nom, Message) » et « coordonnées statiques », est remplacée par : **2 onglets** — Question Générale (Objet + Message) et Signaler un Problème (Module concerné parmi 7 + Description + Étapes) — plus un bloc de coordonnées.

**Non repris** : la zone de dépôt « Capture d'Écran ». Le modèle de données ne comporte aucun champ de pièce jointe et l'application ne stocke aucun fichier — même traitement que le justificatif photo de la Saisie des Dépenses. La raison est affichée à l'écran.

### État de vérification

| Contrôle | Résultat |
|---|---|
| `flutter analyze` | **0 problème** |
| `flutter test` | **358 tests, 358 réussis** (25 nouveaux sur ce module) |
| `flutter build windows --debug` | compilé, application relancée |
| Migration **v12 → v13** sur base réelle | `MESSAGES_EDITEUR` créée, **aucune donnée perdue** (utilisateur, 12 barèmes, 11 échéances, 19 comptes, 6 intrants, 14 produits, 15 lignes d'audit intacts) |
| Liens morts restants dans l'application | **aucun** |
