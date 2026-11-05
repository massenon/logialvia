# F8 — Module : Paramètres & Administration

**Ce document remplace la version précédente**, fondée sur une inférence non vérifiée. Contenu extrait de la lecture réelle de `parametres-generaux.html`.

Écran : `parametres-generaux.html` → `parametres_generaux_screen.dart`. **4 onglets internes** (`switchPgTab`) : Modules Actifs, Données de l'Entreprise, Gestion Utilisateurs, Modes de Paiement.

---

## Onglet 1 — Modules Actifs

**⚠️ Correction critique à Doc I2** : le contenu réel contredit ce que j'avais documenté. Voir section "Corrections Nécessaires" en fin de ce document.

### Texte d'introduction réel (à reproduire fidèlement)
> "Goliaths et Pintades sont l'activité principale confirmée d'ALLMANY et restent toujours actifs. Les filières ci-dessous sont désactivées par défaut — activez-les uniquement si l'activité démarre réellement."

### Structure réelle — 5 lignes à bascule (`toggle-switch`)
| Filière | État | Modifiable |
|---|---|---|
| Goliaths | Toujours actif | ❌ Non — `checked disabled` dans le HTML, aucune interaction possible |
| Pintades | Toujours actif | ❌ Non — idem |
| Poissons-Chats (Pisciculture) | **Désactivé par défaut** | ✅ Oui — "fiche construite, paramètres non confirmés" |
| Poulets / Pondeuses ("aviculture_classique") | **Désactivé par défaut** | ✅ Oui — "Filière dupliquée — désactivée par défaut" |
| Lapins (Cuniculture) | **Désactivé par défaut** | ✅ Oui — "Copie fidèle — désactivée par défaut" |

### Comportement à l'Activation (texte réel, à reproduire)
> "Activer un module affiche immédiatement sa fiche et son raccourci dans le menu latéral et le panneau d'accès rapide."

Confirme le comportement déjà décrit en Doc I2 §3 (effet immédiat sur la navigation) — cette partie reste correcte, seule la liste des filières et leur état par défaut doivent être corrigés.

---

## Onglet 2 — Données de l'Entreprise

### Section « Informations Générales »
| Champ | Valeur réelle observée | Validation |
|---|---|---|
| Raison Sociale * | "ALLMANY ET COMPAGNIE" | Requis |
| Nom du Promoteur | "SIDI ALI Raïmatou" | — |
| Adresse du Siège d'Exploitation | "Natitingou, Bénin" | — |
| Téléphone Principal | "+229 97 00 00 00" | — |
| Email de Contact | — | Format email |

### Section « Informations Légales & Fiscales » — règle métier réelle importante
| Champ | Validation | Règle métier découverte |
|---|---|---|
| Identifiant Fiscal Unique (IFU) * | Requis, **chiffres uniquement** | — |
| Registre du Commerce (RCCM) | Optionnel | — |

**Règle métier non documentée ailleurs dans cette série, à ajouter à Doc B6** : *"Une fois l'IFU et le RCCM renseignés, le module MeCeF (Comptabilité) devient activable."* — MeCeF (Machine Électronique Certifiée Fiscalement) est le dispositif fiscal réglementaire béninois déjà connu du cadre PAEB (cohérent avec les références MECeF/e-MECeF déjà établies sur le projet jumeau AgriERP). **Nouvelle règle métier à cataloguer** :

> **BR-ADM-004** (nouvelle) : Le module de conformité fiscale MeCeF ne peut être activé tant que l'IFU et le RCCM de l'entreprise ne sont pas renseignés dans les Paramètres Généraux.

### Section « Configuration Email (SMTP) »
Serveur SMTP, Port, Sécurité (TLS/SSL/Aucun) — fonctionnalité pour l'envoi de documents (factures, relances) par email, non détaillée davantage dans le HTML observé.

### Section « Logo / Favicon »
Deux zones de dépôt de fichier (glisser-déposer), utilisées dans l'en-tête des factures/rapports (Doc E9) une fois configurées.

### Bouton
"Enregistrer les Modifications" — bas de page, pleine largeur en mobile.

---

## Onglet 3 — Gestion Utilisateurs

### Structure
Bouton "Ajouter un Utilisateur" (haut-droite) → modale : Nom Complet, Rôle (dropdown, 2 options : "Agent de Vente" / "Agent d'Élevage").

### ✅ Divergence Résolue (Doc K4 §8, Doc I1 corrigé)

La divergence précédemment signalée ici est résolue : "Agent de Vente" et "Agent d'Élevage" sont bien les **libellés d'affichage** des rôles techniques `caissier` et `animalier` — confirmé par la lecture directe de `sidebar.js` réel, dont le commentaire d'en-tête affirme explicitement **3 rôles RBAC, pas 4, aucun rôle `comptable`**. Le rôle `admin` n'apparaît pas dans cette modale car il est attribué uniquement via le compte initial (Doc K4 §8, seeder d'administration), pas par ce formulaire de création d'utilisateur secondaire. Doc I1 a été corrigé en conséquence (3 rôles au lieu de 4).

---

## Onglet 4 — Modes de Paiement

### Structure réelle
2 lignes à bascule, **toutes deux toujours actives, non désactivables** (`checked disabled`) :
- Espèces
- Mobile Money

### Texte réel (règle métier à reproduire fidèlement)
> "Conformément au CDCT, seuls 2 modes de règlement sont retenus — pas de virement bancaire ni de multi-comptes."

### ✅ Divergence Réelle — **tranchée** (voir « Divergence de l'Onglet 4 » en fin de document)

Doc D1 (dictionnaire de données, table `VENTES.mode`) et Doc H1 (onglet POS) documentent **3 valeurs possibles** pour le mode de règlement d'une vente : `'Espèces'`, `'Mobile Money'`, `'Avance (Solde Restant Dû)'`. Cet écran Paramètres n'en présente que 2 comme "modes de paiement" configurables.

**Lecture la plus probable, non vérifiée davantage** : "Avance" n'est pas un 3ᵉ mode de règlement au même titre que les 2 premiers, mais une **condition de paiement** appliquée sur une transaction en Espèces ou Mobile Money (vente à crédit partiel) — cohérent avec BR-VTE le mode reste techniquement l'un des 2 seuls moyens, "Avance" qualifie le statut de la transaction (`VENTES.status`), pas le canal de paiement lui-même. **Cette lecture n'est pas contredite par le code déjà réellement construit dans `ventes.html`** (le champ `mode` stocke littéralement la chaîne complète "Avance (Solde Restant Dû)", ce qui est techniquement incohérent avec la distinction mode/statut proposée ici) — **point à clarifier avant implémentation Dart**, actuellement une incohérence réelle entre 2 parties du système existant, pas seulement entre le HTML et ma documentation.

---

---

## État d'implémentation — les 4 onglets sont livrés

| Onglet | État |
|---|---|
| 1 — Modules Actifs | ✅ 5 lignes, Goliaths/Pintades verrouillés, effet immédiat sur la navigation |
| 2 — Données de l'Entreprise | ✅ 3 sections + BR-ADM-004 · dépôt Logo/Favicon reporté (voir ci-dessous) |
| 3 — Gestion Utilisateurs | ✅ liste + création + suppression |
| 4 — Modes de Paiement | ✅ **2 tables** — Modes de Règlement et Conditions de Paiement (divergence tranchée) |

### ⚠️ Cet onglet 1 débloquait un cul-de-sac fonctionnel

Avant son implémentation, les 3 filières désactivables étaient **inaccessibles par conception** : masquées de la barre latérale (Doc I2 §3) et redirigées par le `redirect` du routeur. Aucun chemin ne permettait de les activer. Les fiches Lapins, Poissons-Chats et Poulets/Pondeuses existaient en code sans être atteignables.

### ⚠️ Ajout nécessaire à la modale « Ajouter un Utilisateur »

La modale du prototype ne comporte que **2 champs** : Nom Complet et Rôle. Un compte créé ainsi n'a **ni identifiant de connexion ni mot de passe** — il serait donc impossible de s'y connecter, et l'onglet ne serait qu'une liste décorative (Master Prompt §2.3).

Deux champs ont été ajoutés : **identifiant de connexion** et **mot de passe** (8 caractères minimum, avec confirmation). Un test vérifie qu'un compte créé depuis cet écran peut réellement ouvrir une session — c'est le seul critère qui prouve que l'écran n'est pas décoratif.

### Garde-fou ajouté

**Le dernier compte administrateur ne peut pas être supprimé.** Absent du prototype, mais sans lui l'application deviendrait définitivement inadministrable — le rôle `admin` n'étant attribuable ni par cet écran ni par aucun autre (seul le seeder initial le pose, Doc K4 §8).

### Écart assumé — dépôt Logo / Favicon

Les 2 zones de glisser-déposer ne sont pas reproduites. Elles supposent un sélecteur de fichier **et** la chaîne de validation stricte de Doc I3 §2 (type réel vérifié par signature de fichier, taille maximale, nom regénéré en UUID). Les afficher sans cette chaîne donnerait une zone de dépôt inerte. `TODO(dette)` posé : à implémenter avec Doc E9, seul consommateur réel du logo.

### Persistance — table créée

`PARAMETRES_ENTREPRISE` **n'existait pas dans Doc D1**. Créée en schéma v7 (voir Doc D1). Sans elle, l'onglet 2 aurait été un formulaire sans persistance.

---

## Corrections Nécessaires — Récapitulatif pour Doc I2

Le tableau §2 de `I2_Gestion_Modules_Actifs.md` doit être corrigé :
- Goliaths, Pintades : passer de "✅ Désactivable" à **"❌ Non désactivable — activité principale confirmée"**
- Ajouter la précision : les 3 filières réellement désactivables (Poissons-Chats, Poulets/Pondeuses, Lapins) sont **désactivées par défaut**, pas activées par défaut comme le document actuel le suggère implicitement
- Identifiants techniques réels des modules à utiliser dans le code : `pisciculture`, `aviculture_classique`, `cuniculture` (pas les noms d'espèce bruts que j'avais utilisés)

## Divergence de l'Onglet 4 — tranchée par la Gérante

**Point 3 de l'index maître, ouvert depuis Doc F8 §Onglet 4 — désormais clos.**

La lecture proposée au §85 était la bonne : **« Avance (Solde Restant Dû) » est une condition de paiement, pas un mode de règlement.** L'écran Paramètres avait raison avec ses 2 modes ; c'est `VENTES.mode` qui était surchargé.

### Pourquoi ce n'était pas qu'une question de vocabulaire

Les deux valeurs légitimes de `mode` répondent à *avec quoi le client a payé*. La troisième répondait à *combien il a payé*. Les loger dans la même colonne coûtait une information réelle : **une avance versée en Mobile Money ne pouvait pas être distinguée d'une avance en espèces**, alors que le rapprochement de caisse en dépend directement.

### Ce qui change

| | Avant | Après |
|---|---|---|
| `VENTES.mode` | 3 valeurs, dont une condition | 2 instruments — Espèces, Mobile Money |
| Condition de paiement | confondue avec le mode | lue sur `VENTES.status`, où elle était **déjà** stockée |
| Point de vente | 1 sélecteur | **2 sélecteurs** — Mode de règlement, Condition de paiement |
| Onglet 4 | 1 table + encart « incohérence non tranchée » | **2 tables** — Modes de Règlement, Conditions de Paiement |
| Détail d'une vente | « Mode de règlement » | + ligne « Condition de paiement » |

**Aucune colonne n'est ajoutée.** La condition se déduit intégralement de `status` : « Avance » ⇒ vente à crédit, « Payée » ⇒ comptant. L'information était donc stockée deux fois — c'est précisément ce qui rendait la surcharge de `mode` inutile en plus d'être fausse. `ConditionPaiement.depuisStatut()` est la seule lecture.

### Migration v15 — les ventes antérieures

Les ventes qui portaient la condition dans `mode` n'ont **jamais enregistré leur instrument réel** : il est inconnu. La migration écrit `'Non précisé'`, pas `'Espèces'` — inventer une donnée absente serait pire que l'admettre. `status` reste intact : ces ventes demeurent des créances, leur reste dû est inchangé. `'Non précisé'` n'est pas proposé à la saisie : c'est une trace du passé, pas un choix offert à la caissière.

### Garde-fou ajouté au point de vente

Une condition « Avance » dont le montant reçu solde la vente est refusée, avec le message « Le montant reçu solde la vente : choisissez "Comptant" ». Sans ce contrôle, la vente serait enregistrée en avance avec un reste dû nul et apparaîtrait en créance dans Clients sans rien à recouvrer. Basculer d'« Avance » vers « Comptant » remet aussi le montant reçu à zéro, faute de quoi un reliquat bloquerait la validation sans dire pourquoi.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **433 tests au vert** dont 8 sur la séparation mode/condition et 5 sur la migration v15 · build compilé, application relancée · schéma **v15**.

## Échéances de paiement — le défaut qui produisait des lettres de relance injustifiées

**Tranché avec la Gérante : délai par défaut paramétrable + saisie au cas par cas.**

### Ce qui n'allait pas

`CreanceClient.echeance` retournait `dateVente`. Donc :

```
joursDeRetard = aujourd'hui − date de vente
enRetard      = joursDeRetard > 0
```

**Toute vente à crédit faite hier ou avant était affichée « En Retard »**, avec un compteur de jours qui mesurait en réalité son ancienneté. Tant que la colonne n'était qu'un affichage, le défaut restait cosmétique et il était documenté comme tel.

Il a changé de nature le jour où la **colonne Actions des créances** a été branchée : la lettre de relance s'imprime depuis ce tableau. La Gérante pouvait donc envoyer une mise en demeure — un document signé, adressé à un vrai client — pour une créance de la veille, mentionnant un retard qui n'existait pas.

Même défaut sur les dettes fournisseurs (`echeance => dateAchat`). Le prototype allait plus loin : sa seule dette est datée du `06/08/2026` avec une échéance au `05/08/2026`, **exigible la veille de son propre engagement**.

### Ce qui a été fait

| Où | Quoi |
|---|---|
| `VENTES.echeance`, `ACHATS.echeance` | DATETIME nullable (v17) |
| `PARAMETRES_ENTREPRISE.delaiPaiementJours` | INTEGER nullable (v17) |
| Paramètres Généraux | nouvelle carte « **Conditions de Vente** » |
| Point de vente | champ « **Payable le** », visible uniquement en Avance |
| Rapports | l'échéance vient de la base ; nouveau statut « **Sans échéance** » |
| Lettre de relance | change de ton et de titre quand aucune échéance n'existe |

### Aucun délai n'est inventé

Le nombre de jours réellement pratiqué chez ALLMANY n'a pas été communiqué. Le réglage est donc **laissé vide**, et tant qu'il l'est :

- passer une vente en « Avance » ne propose **aucune** date ;
- la créance est enregistrée « **Sans échéance** » ;
- elle apparaît bien dans les créances, avec son solde dû, mais **n'est jamais déclarée en retard** ;
- le PDF s'intitule « **Rappel de Solde** » et non « Lettre de Relance », et écrit « présente un solde restant à régler » au lieu de « reste impayée à ce jour ».

Un encart le dit sur les deux écrans concernés, et indique où fixer le délai.

### « Sans échéance » n'est pas « À échoir »

Les deux se distinguent : la première dit qu'**aucune date n'a été fixée**, la seconde qu'une date existe et n'est pas encore atteinte. Les confondre reviendrait à affirmer un délai que personne n'a convenu — exactement l'erreur d'origine, à l'envers.

Un délai saisi à 0 ou négatif compte comme non fixé : mieux vaut ne rien affirmer qu'affirmer faux.

### Le comportement est verrouillé par les tests

Douze tests sur le flux POS → créance, plus quatre réécrits dans les rapports — dont deux qui verrouillaient l'ancien comportement fautif et affirmaient que « l'échéance vaut la date de vente ». Ils affirment maintenant l'inverse, avec la raison inscrite dans le `reason`.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **520 tests au vert** · build **release** compilé, packagé et lancé · migration **v16 → v17**, lignes existantes laissées à NULL.

## Corbeille, réinitialisation et toast — trois demandes de la Gérante

### 1. « Supprimer » n'efface plus rien (v22)

Les **8 suppressions** ouvertes à l'utilisateur passent désormais par une corbeille : produits du catalogue, intrants, barèmes de rationnement, échéances de prophylaxie, lots d'incubation, utilisateurs, écritures comptables, messages à l'éditeur.

#### Pourquoi une corbeille plutôt qu'un drapeau `archive` par table

Marquer chaque table d'un booléen aurait imposé de filtrer **toutes** les requêtes de l'application. Une seule oubliée, et un intrant supprimé réapparaît dans une fabrication de provende. La table `CORBEILLE` sort la ligne de sa table et en garde une **copie JSON complète** : aucune requête existante ne change, et la restauration réécrit la ligne à l'identique — y compris les colonnes ajoutées par une migration ultérieure.

Le nom de table vient d'une **liste blanche stricte** (`TypeArchivable`) : il part dans une requête SQL à la restauration, il ne doit jamais venir d'ailleurs.

#### Logique de sécurité — décidée, pas subie

| Opération | Qui |
|---|---|
| **Archiver** | qui a le droit de gérer l'écran — un Agent de Vente retire un produit, c'est son métier |
| **Restaurer** un produit, un intrant, un barème, une échéance, un lot, un message | tout le monde |
| **Restaurer** un utilisateur ou une écriture comptable | **administratrice seulement** |
| **Supprimer définitivement** / vider la corbeille | **administratrice seulement** |

Ressusciter un compte utilisateur ou une écriture comptable ne se fait pas depuis un poste de caisse. Et la purge est la **seule opération de toute l'application qui détruit vraiment quelque chose** — elle porte sa propre modale d'avertissement, qui renvoie vers l'onglet Sauvegardes comme alternative.

Deux refus supplémentaires, testés : restaurer sur une référence réoccupée entre-temps (écraser remplacerait des données à jour par des données périmées), et restaurer un élément déjà sorti de la corbeille.

### 2. Onglet « Données de Test » (v23)

Remet à zéro l'**activité**, jamais l'**exploitation**.

| Effacé | Préservé |
|---|---|
| ventes, lignes de vente, devis, clients, achats, lignes d'achat, mouvements d'intrant, écritures, notes annexes, clôtures, fiches journalières, fiches de ventes, lots d'incubation, machines, soins, infirmerie, corbeille | comptes, rôles, permissions, paramètres d'entreprise, plan comptable, exercices, modules actifs, préférences du poste, barèmes, calendriers de prophylaxie, catalogue, intrants, fournisseurs |

Après elle, l'application est prête à travailler ; elle n'a simplement rien fait encore. C'est exactement l'état voulu après une période d'essai.

⚠️ **Les journaux d'audit sont conservés délibérément.** Une opération qui efface l'activité *et* la trace de qui l'a effacée n'est pas une réinitialisation, c'est un effacement de preuves.

#### Double verrou

1. Le **mode « Données de Test »** doit être activé — un interrupteur posé dans **Modules Actifs**, pas dans l'onglet qu'il protège : un verrou sur la porte qu'il ferme ne ferme rien. **Faux par défaut**, y compris sur les bases existantes lors de la migration.
2. L'utilisatrice doit être **administratrice**.

Le second sans le premier ne suffirait pas : la Gérante *est* administratrice, et c'est justement son exploitation qu'il faut protéger.

#### La modale d'avertissement compte pour de vrai

Elle n'annonce pas « des données seront effacées » : elle affiche le **nombre réel de lignes**, table par table, calculé avant l'opération (`apercu()`, qui ne touche à rien). Elle liste ensuite ce qui sera conservé, et rappelle que la sauvegarde est le seul retour en arrière possible — la réinitialisation, elle, **ne passe pas par la corbeille**.

Tout est fait dans une transaction : une réinitialisation à moitié faite laisserait des écritures comptables sans les ventes qui les justifient. Les seeders sont rejoués ensuite pour garantir qu'un exercice comptable reste ouvert, sans quoi plus aucune écriture ne pourrait être saisie.

### 3. Toast en haut à droite

Un `SnackBar` Material est structurellement ancré en bas : ni `behavior`, ni `margin`, ni `width` ne le remontent. Le toast est donc reconstruit sur un `Overlay`, à la même signature — les ~60 appels existants sont inchangés.

Le bas droit était de toute façon occupé par les deux boutons flottants (Accès Rapide, Visite Guidée) et la barre d'actions des modales. Les toasts **s'empilent** au lieu de se remplacer — deux enregistrements enchaînés doivent tous deux être lus —, portent une croix de fermeture pour les messages longs, et sont plafonnés à 4 : un empilement sans fin masquerait l'écran au lieu de l'informer.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **656 tests au vert** dont 32 dédiés (16 corbeille, 16 réinitialisation) · build **release** compilé, packagé et lancé · migrations **v21 → v22 → v23**.

### La corbeille nomme désormais son auteur

La colonne « Archivé par » restait vide : les dépôts acceptaient l'auteur, mais rien ne le leur transmettait — un paramètre qui n'est jamais rempli est aussi décoratif qu'un bouton qui n'écrit rien.

La chaîne est branchée de bout en bout, sur les **8 suppressions** : écran → ViewModel → dépôt → corbeille. `auteurCourant(context)` lit la session une fois pour toutes, plutôt que de répéter six fois la même lecture de `AuthViewModel` — une seule oubliée laisserait une colonne vide sans que rien ne le signale.

`AuteurArchivage` est un objet et non deux `String?` côte à côte : deux paramètres nullables voisins finissent toujours par être inversés quelque part, et la corbeille attribuerait alors la suppression à la mauvaise personne.

**`null` reste légitime** — un archivage déclenché hors session (test, migration) n'a pas d'auteur, et inventer « admin » attribuerait l'acte à quelqu'un. Un test le verrouille.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **659 tests au vert** · build **release** compilé, packagé et lancé.


## Restauration d'une sauvegarde

### Le défaut que cette fonction comble

L'onglet Sauvegardes savait **générer**, **exporter**, **lister** et
**supprimer**. Il ne savait pas **restaurer**. L'application invitait donc la
Gérante à faire des sauvegardes et ne lui permettait jamais de s'en servir — un
bouton qui promet une sécurité qu'il ne donne pas, au seul endroit où la
promesse compte vraiment.

### ⚠️ Pourquoi la restauration est différée au redémarrage

La base est ouverte en permanence par l'application. Remplacer le fichier sous
une connexion vivante produit au mieux une erreur, au pire une base à moitié
écrite — sur la comptabilité d'une exploitation.

Le fichier choisi est donc **mis en attente** dans le dossier applicatif, et
c'est le démarrage suivant qui l'applique, **avant** que `AppDatabase()` n'ouvre
quoi que ce soit. Tant que l'utilisatrice n'a pas redémarré, rien n'est modifié
et elle peut annuler.

### Les quatre contrôles, avant que le moindre octet ne bouge

Une restauration qui échoue en cours de route laisserait l'exploitation sans
base du tout. Tout est donc vérifié d'abord :

| Contrôle | Ce qu'il écarte |
|---|---|
| Signature SQLite (16 premiers octets) | un document renommé en `.sqlite` |
| `PRAGMA integrity_check` | une sauvegarde corrompue — qu'on découvre d'ordinaire le jour où on en a besoin |
| Tables `utilisateurs`, `roles`, `parametres_entreprise` | la base d'un autre logiciel, qui s'ouvrirait très bien |
| `user_version` ≤ version du logiciel | une base produite par une version plus récente : on migre en avant, jamais en arrière |

Une base **plus ancienne** est en revanche acceptée : elle sera migrée à
l'ouverture, c'est le cas normal d'une vieille sauvegarde.

Le fichier est ouvert en **lecture seule** pour ces contrôles.
`AppDatabase.pourFichier` appliquerait ses migrations et modifierait donc la
sauvegarde qu'on est en train de vérifier.

### Ce que la restauration garantit

- **La base précédente est conservée** dans le dossier des sauvegardes, sous
  `logialvia-avant-restauration-<horodatage>.sqlite`. Une restauration n'est
  jamais un aller sans retour.
- **La demande est consommée** : sans cela, chaque démarrage écraserait le
  travail de la veille par la même sauvegarde.
- **Les journaux `-wal` et `-shm` sont supprimés** : ils décrivent l'ancienne
  base, et les laisser ferait relire des pages sans rapport avec le fichier
  restauré.
- **Un fichier devenu illisible entre-temps est écarté**, pas appliqué : il est
  recontrôlé au démarrage, la base en service n'est pas touchée.
- **Le Splash annonce la restauration** au redémarrage. Sans cela, la Gérante
  ne verrait qu'un écran de connexion ordinaire et ne saurait pas si son
  opération a réussi.

Seule une **base complète** se restaure : remettre en place l'export d'une seule
table laisserait les autres dans l'état d'aujourd'hui, et la base serait
incohérente.

**Vérification** : 16 tests, dont un qui a révélé une fuite réelle — le
descripteur de fichier ouvert pour lire la signature n'était pas refermé, ce qui
verrouillait la sauvegarde sous Windows après un simple contrôle.
