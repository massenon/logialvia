# 47u — Parité d'administration web ↔ poste (utilisateurs, audit, corbeille, messages, sauvegardes)

Le Dart est la source ; le web s'y conforme. Ce document fixe les règles livrées, les décisions à faire valider
par le client, les écarts avec le poste et les limites. Il complète `45_` §7 (ne le modifie pas).

## 1. Ce que le web fait désormais

| Écran / onglet | Route / droit | Ce que fait le web | Équivalent poste |
|---|---|---|---|
| Paramètres Généraux > **Gestion Utilisateurs** | `/parametres/generaux`, droit `manage-users` (vérifié dans chaque méthode **et** dans `UtilisateursService`) | Créer, modifier (nom, e-mail, rôle), désactiver / réactiver, réinitialiser le mot de passe, supprimer (archiver) ; recherche ; export XLSX | `_OngletUtilisateurs`, `modale_utilisateur.dart` |
| **Journal d'Audit** | `/parametres/audit`, droit `manage-users` | Lecture seule de `audit_logs` : filtres date (fin incluse, fuseau du Bénin), action, utilisateur ; pagination 25 ; export XLSX ; impression | Aucun écran au poste (il n'a que le journal personnel) |
| Paramètres Généraux > **Corbeille** | droit `view-parametres` pour voir ; droit d'écriture de l'élément pour restaurer ; administrateur pour les types réservés et la purge | Liste des pierres tombales du serveur, **restauration**, purge des comptes ; filtre type / recherche ; export XLSX | `onglet_corbeille.dart`, `service_archivage.dart` |
| **Contact** | `/contact`, tout compte connecté | Formulaire Question / Problème technique, registre des messages, texte à copier, « Transmis », suppression | `contact_editeur_screen.dart` |
| Paramètres Généraux > **Sauvegardes** | téléchargement : administrateur (`manage-parametres`) | Sauvegarde **logique** JSON des données du serveur, sans secret, auditée | `onglet_sauvegardes.dart` (copie de la base du poste) |
| **Mon Profil** | `/profil`, tout compte connecté | + dernière connexion, nombre de connexions, statut, journal d'audit personnel (20 dernières actions) ; nouveau mot de passe ≠ ancien | `mon_profil_screen.dart` |
| Vues imprimables | partout | CSS `@media print` global ; bouton « Imprimer / PDF » (`<x-bouton-imprimer />`) sur l'audit, la corbeille, les utilisateurs | exports PDF du poste |

Format d'export des tableaux au web : **XLSX** (`App\Support\ExportXlsx`), jamais CSV (consigne du client).

## 2. Règles et garde-fous (utilisateurs)

- **Comptes du serveur seulement** (`users`). Les comptes locaux d'un poste restent propres au poste (DV-20) ; seuls existent les comptes créés par l'administrateur ; **pas de compte « acheteur »**.
- **Mot de passe** : règle du Dart (`App\Support\RegleMotDePasse` : 8 caractères, 1 majuscule, 1 chiffre, mêmes messages) + confirmation. Un mot de passe posé par l'administrateur est **temporaire** : `must_change_password = true`, le changement est exigé à la connexion (le web n'ouvre alors que `/mot-de-passe`).
- **Garde-fous d'expert** : impossible de supprimer, désactiver ou rétrograder le **dernier administrateur actif** (un administrateur désactivé ne compte pas) ; impossible de désactiver, supprimer, changer le rôle ou réinitialiser le mot de passe de **son propre compte** (pour ce dernier : Mon Profil).
- **Désactivation / suppression / réinitialisation** : tous les **jetons de poste** du compte sont supprimés (le poste reçoit 401, suspend sa synchronisation). La désactivation est aussi appliquée **en cours de session web** (`CompteActifWeb`, persistant pour les appels Livewire d'une page déjà ouverte) : déconnexion avec le motif.
- **Suppression = archivage** (suppression logique). Restauration depuis la Corbeille ; purge définitive : administrateur seul. L'identifiant d'un compte supprimé reste réservé (contrainte d'unicité) : le message oriente vers la Corbeille.
- **Audit sans secret** : `utilisateur.cree / modifie / desactive / reactive / mdp_reinitialise / archive / restaure / purge`, `corbeille.restaure`, `sauvegarde.telechargee`, `message_editeur.cree / transmis / supprime`. Jamais de mot de passe dans le détail ; à l'affichage, toute clé qui ressemble à un mot de passe, un jeton ou un secret est masquée (`LibellesAudit`).

## 3. Corbeille web

Au serveur, « supprimé » est une **pierre tombale** : `supprime_le` (clients, fournisseurs, lots d'incubation, incubateurs, messages), `archive_le` (produits, barèmes, taux par classe de poids, échéances de prophylaxie) ou la suppression logique d'un compte. Liste blanche de types (`CorbeilleService::types()`).

- **Restauration** = une écriture qui lève la pierre tombale, par les **mêmes chemins qu'un poste** : `TableSync::absorber` (faits) ou `DemandesReferentiel::traiter` (référentiels). Mêmes validations (ex. un lot dont l'incubateur a disparu est refusé avec son motif), même droit d'écriture, dernier écrivain gagne ; l'écriture est datée de maintenant **après** la pierre tombale (même si l'horloge d'un poste était en avance) et redescend vers tous les postes. Poste d'origine « Web » = UUID nul.
- **Types réservés à l'administrateur** (comme `reserveALAdmin` au Dart) : comptes utilisateurs. Le Dart réserve aussi les écritures comptables : elles n'ont **pas** de pierre tombale au serveur (jamais supprimées), donc absentes de la corbeille web.
- **Purge définitive** : réservée à l'administrateur, **comptes seulement**. Les autres pierres tombales ne s'effacent jamais (voir D3).
- La corbeille **d'un poste** (instantanés locaux) reste sur le poste.

## 4. Messages à l'éditeur (poste v45)

- Poste : table `messages_editeur` en **UUID** (migration v45 idempotente : messages d'hier `pending` datés de leur rédaction ; instantanés de corbeille munis d'un UUID, déclarés `synced`) + `auteur_nom` + colonnes de synchronisation. `TableMessagesEditeurPoste` (fait, dernier écrivain gagne, **pierre tombale** par l'instantané de corbeille, comme les lots de couveuse), câblée dans `main.dart`, faux serveur et tests. Les versions 43 et 44 sont réservées à d'autres tranches (`if (from < 45)` seul).
- Serveur : migration `2026_11_09_151000_create_messages_editeur_table.php`, `MessagesEditeurTable` (lecture et écriture ouvertes à tout compte connecté, comme le poste où chacun voit le registre).
- **Aucun e-mail n'est envoyé** (ni poste, ni serveur : pas de transport, pas de secret SMTP). Le message est **enregistré** ; l'utilisateur copie le texte (même contenu que `texteAEnvoyer` du Dart) et le transmet lui-même, puis le marque « Transmis ». C'est dit à l'écran.
- Écart avec le Dart : la capture d'écran de la maquette n'existe nulle part.

## 5. Autres écarts comblés, et ceux qui restent

- **Sauvegardes** : le web télécharge une sauvegarde **logique** (JSON, toutes les tables métier, jamais `password`, `remember_token`, jetons, sessions, cache, files). Ce n'est pas une copie de la base et **le web ne la restaure pas** ; la copie / restauration / vérification de base reste au poste ; la sauvegarde de la base du serveur relève de l'hébergement.
- **Données de Test** : **poste seulement** (remise à zéro et jeu d'essai sous verrou). Le mode « Données de Test » est affiché, non modifiable au web.
- **Logo / favicon** : le **poste** les reçoit (Paramètres Généraux > Logo / Favicon : champ de saisie du chemin, `ServiceImagesEntreprise` : type réel vérifié par signature, 2 Mo / 512 Ko, copie dans le dossier du poste sous un nom régénéré, Doc I3 §2) ; ce sont des fichiers propres à la machine, **non synchronisés**. Le web ne les offre donc pas ; la section le dit. Utilisation par les documents imprimés : avec Doc E9.
- **Rôles** : le web attribue les **quatre** rôles (admin, comptable, agent de vente, agent d'élevage), comme le demande le client (DV-07). Le Dart, lui, n'attribue que agent de vente et agent d'élevage depuis son écran et réserve `admin` au compte initial (voir D1).
- Jeton e-MECeF et mot de passe SMTP : toujours jamais affichés ni saisis au web.

## 6. Décisions à valider par le client

| Id | Décision prise | Pourquoi / alternative |
|---|---|---|
| D1 | Le web peut attribuer le rôle **Administrateur** et **Comptable** (le Dart n'attribue que les deux rôles métier) | Sans cela l'administrateur ne pourrait ni passer la main ni créer le comptable ; garde-fou du dernier administrateur en contrepartie. Alternative : calquer le Dart (admin seeder seul). |
| D2 | Un compte créé ou réinitialisé au web a un mot de passe **temporaire** (changement obligatoire) | Le Dart ne l'exige pas à la création ; l'administrateur connaît le mot de passe qu'il a saisi. |
| D3 | Pas de purge des pierres tombales autres que les comptes | Elles empêchent un poste hors ligne de ressusciter l'élément ; effacer un client détacherait ses ventes (`nullOnDelete`). Alternative : purge après N mois, avec accord de tous les postes. |
| D4 | Le journal d'audit web est réservé à `manage-users` (administrateur) | Il porte identifiants, adresses IP et gestes de tous les comptes ; le Dart n'a pas d'équivalent. |
| D5 | Messages à l'éditeur visibles de tout compte connecté (comme au poste) et synchronisés | Un message peut contenir une description d'incident : à restreindre à l'auteur + administrateur si le client le préfère. |
| D6 | Sauvegarde logique téléchargeable par l'administrateur seul, non restaurable au web | Une restauration au web exposerait à l'écrasement de données synchronisées ; à discuter avec l'hébergeur. |
| D7 | Un administrateur désactivé ne compte pas comme « relais » pour protéger le dernier administrateur actif | Évite de se retrouver sans administrateur capable de se connecter. |

## 7. Limites connues

- Le journal personnel de Mon Profil ne montre que ce que le serveur journalise (pas de déconnexion, ni ventes/achats saisis sur les postes).
- La suppression d'un message au poste dont la corbeille est vidée avant l'envoi perd sa pierre tombale (limite héritée des lots de couveuse, `46b_`).
- Le texte « Transmis » est un état déclaratif : rien ne prouve l'envoi réel.
- Les boutons « Imprimer / PDF » ne sont posés que sur les écrans de cette tranche ; la feuille `@media print` est globale (Ctrl+P fonctionne sur tout écran), à compléter par écran si le client veut une mise en page dédiée.
- Les clés étrangères `ventes.client_id` restent en `nullOnDelete` : sans objet tant qu'aucune pierre tombale n'est purgée.

## 8. Tests

`tests/Feature/Web/` : `GestionUtilisateursWebTest`, `JournalAuditWebTest`, `CorbeilleWebTest`, `ContactWebTest`, `SauvegardesWebTest`, `ProfilWebTest`, `VuesImprimablesTest` ; `tests/Feature/Sync/MessagesEditeurTest`. Poste : `test/administration/messages_editeur_sync_poste_test.dart`, `test/core/migration_v45_messages_test.dart`. Chaque garde (dernier administrateur, propre compte, droit par méthode, secret, réservé administrateur, pierre tombale, filtre de date, pagination…) a été **muté** pour vérifier qu'un test rougit.
