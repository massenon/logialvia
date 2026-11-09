# 47n — Tests des écrans web DANS UN VRAI NAVIGATEUR (Playwright / Chromium)

> **Pourquoi.** Les composants Livewire étaient testés par `Livewire::test` (PHP), jamais depuis un navigateur : JavaScript
> (Livewire/Alpine, `wire:model.live`, modales, `wire:click`), téléchargements, impression et mise en page responsive
> échappaient aux tests. Cette étape ajoute une suite de bout en bout, **sans dépendance réseau** (Node + `playwright`
> préinstallé, Chromium local, base SQLite jetable) : `logialvia_laravel/e2e/`.
> Le Dart reste la source ; rien ici ne change une règle métier.

## 1. Relancer

```bash
bash logialvia_laravel/e2e/lancer.sh               # tout (≈ 6 min) : build, base jetable, serveur, 52 scénarios
bash logialvia_laravel/e2e/lancer.sh 8799 -- 'caisse|devis'   # un filtre (expression régulière sur le nom du scénario)
SANS_BUILD=1 bash logialvia_laravel/e2e/lancer.sh  # saute `npm run build`
```

`lancer.sh` : base SQLite **jetable** (`/tmp/lv-e2e/e2e.sqlite`, jamais celle de l'exploitation) → `migrate:fresh --seed` → jeu
de données (`e2e/donnees.php`, passe par les **services** du serveur : ventes, achats, fiches ⇒ écritures comptables cohérentes) →
`npm run build` → `php artisan serve` (4 workers, port 8799) → `node e2e/executer.mjs`. Code de sortie ≠ 0 au moindre échec.
Comptes d'essai (mot de passe `EssaiPoste-2026!`) : `admin1`, `comptable1`, `caissier1`, `animalier1`, `temporaire1` (mot de passe
temporaire). Jeu de données : 8 produits, 6 intrants, 5 clients, 3 fournisseurs, 3 achats (livré réglé, livré à crédit, commandé),
3 ventes (comptant, à crédit, client de passage), 12 jours de fiches goliaths et pintades, un poste appairé, tous les modules actifs.

| Fichier | Contenu |
|---|---|
| `lib.mjs` | cadre de scénarios, surveillance (console, `pageerror`, requêtes échouées, HTTP ≥ 400), connexion, lecture de la base |
| `fumee.mjs` | fumée de **toutes** les routes × 4 rôles (4 scénarios + barre latérale + visiteur + /login) |
| `parcours_*.mjs` | parcours CRUD au clic (commerce, documents, achats, élevage, compta, admin, postes) |
| `transversaux*.mjs` | impressions, exports XLSX, `print`, responsive, clavier, double clic, réseau, session, onglets, accessibilité |
| `verifier_xlsx.py` | ouvre un export avec `openpyxl` |
| `captures/` | une capture par écran/rôle/largeur (`deviceScaleFactor: 1`) ; **non versionnées** sauf `exemple_*.png` |

Règle d'écriture : les gestes sont des **clics et des saisies** (jamais un appel direct de méthode) ; la base n'est écrite directement
que pour **préparer** un état (chaîne incohérente, divergence), jamais pour le geste testé. Chaque scénario vérifie l'écran **et** la base.

## 2. Résultats par écran

| Écran | Fumée (4 rôles) | Parcours au clic | Vérifié en base |
|---|---|---|---|
| Connexion / mot de passe temporaire | oui | faux refusé, bon accepté, déconnexion ; temporaire → seul le changement est ouvert, règle de complexité, confirmation | `must_change_password` |
| Catalogue | oui | ajouter (validation), recherche en direct, modifier, supprimer (annuler puis confirmer) | produit, prix, archivage |
| Clients | oui | ajouter/modifier/supprimer ; recouvrement (trop élevé refusé, partiel) | `solde_creance`, `paye` |
| Caisse / Ventes | oui | panier (modale « vente à la pièce »), retrait, client suggéré, reçu insuffisant, monnaie, encaissement, historique, détail, annulation (motif) ; vente à crédit | vente, lignes, pièces, contre-passation `ANN-` |
| Devis | oui | créer, accepter, imprimer, dupliquer, supprimer | `devis` |
| Factures MeCeF | oui | émission depuis une vente, détail, impression, avoir total | `factures`, avoir = total |
| Achats | oui | commande, réception, règlement (nul refusé, plafonné, soldé), annulation (motif) | statut, `paye`, mouvement de stock, pièces |
| Fournisseurs | oui | ajouter/modifier/supprimer, bloc de cohérence 401 | `fournisseurs` |
| Dépenses | oui | saisie SYSCOHADA, validation, correction, annulation | pièce équilibrée, contre-passation |
| Fiches d'élevage | 8 routes | saisie du jour (impossible refusé), effectif recalculé, chaîne incohérente → recalcul, divergence → garder une version, bande (déclarer, recoder, clôturer) | `fiche_journee`, `bandes` |
| Couveuse | oui | incubateur, lot, mirage 1, éclosion (règle J+17 constatée) | `cycle_couveuse` |
| Soins / infirmerie | oui | soin planifié puis confirmé, entrée, décès avec perte portée sur la fiche | `soins_calendrier`, `infirmerie`, fiche |
| Comptabilité | 9 routes | écriture manuelle + annulation ; clôture mensuelle (écriture refusée en période close, déclôture) ; assistant de clôture annuelle + réouverture | pièces, `clotures_periodiques`, `exercices_comptables` |
| Utilisateurs / corbeille | oui | créer (mot de passe faible refusé), désactiver, réactiver, supprimer → corbeille → restaurer ; compte désactivé refusé à la connexion | `users`, rôle |
| Paramètres | oui | entreprise, module désactivé → 404 + lien retiré → réactivé | `parametres_entreprise`, `modules_actifs` |
| Profil / Contact | oui | mot de passe (ancien faux refusé) puis reconnexion ; question et problème technique | `messages_editeur` |
| Postes & Audit | oui | révocation (annuler puis confirmer), trace d'audit | `postes.revoque_le` |

**Fumée** : 39 routes par rôle (matrice `config/logialvia.php` + `/parametres/postes`, `/parametres/audit`, `/ventes/devis`) : 200 si le
droit existe, **403** net (sans trace) sinon ; titre `… — LogiALVIA` ; aucune erreur console, aucun `pageerror`, aucune requête en
erreur, aucune police/image 404 ; barre latérale = celle de l'administrateur filtrée par droits et modules ; visiteur → `/login`
(y compris pour les vues imprimables). **Impressions** : 12 vues `/impression/…`, `/achats/impression`, `/depenses/impression`, etc.
(200, sans menu, contenu présent ; 403 pour un rôle sans droit). **Exports XLSX** : 15 écrans, fichiers ouverts avec `openpyxl`
(feuille nommée, en-tête sans trou, nombres **typés** ; les identifiants — n° de compte, code, référence — restent du texte, voulu).
**Impression navigateur** : `emulateMedia('print')` + `page.pdf()` sur 13 écrans (barre latérale/en-tête/boutons masqués, aucun
tableau coupé, aucun défilement caché). **Responsive** : 39 routes × 390 / 768 / 1280 px sans défilement horizontal de page.

## 3. Défauts trouvés et corrigés

| # | Défaut (vu dans le navigateur) | Cause | Correctif | Non-régression |
|---|---|---|---|---|
| 1 | Caisse : « Encaisser la Vente » juste après la frappe du montant reçu → « Veuillez saisir le montant reçu » | `wire:model.live.debounce.300ms` ne met l'état à jour qu'**après** le délai ; le clic partait avec l'ancienne valeur (même risque sur les quantités d'achat, la fiche d'élevage, etc. : 36 champs `debounce`) | `resources/js/app.js` : à la perte du focus et à la validation d'un formulaire, la valeur est poussée dans l'état du composant (`set(prop, valeur, false)`), sans requête | e2e « caisse : vente à crédit » (saisie puis clic immédiat) ; `DefautsNavigateurTest` |
| 2 | Téléphone : le contenu commençait à 1 333 px, après les 40 liens du menu | barre latérale toujours dépliée sous `md` | `layouts/app.blade.php` : bouton « Menu » (`aria-controls`/`aria-expanded`) sous `md`, navigation repliée ; toujours visible dès `md` | e2e responsive (menu, contenu < 250 px) ; `DefautsNavigateurTest` |
| 3 | Achats : boutons Réceptionner / Régler / Annuler hors de la carte à 1 280 px | cellule d'actions `whitespace-nowrap` dans un tableau à défilement interne | `achats.blade.php` : actions en `flex-wrap` | e2e « achats » (clics sur ces boutons) ; e2e responsive bureau (aucun tableau tronqué) |
| 4 | Listes déroulantes : la flèche chevauchait le texte (« Tous les statuts▾ ») | `px-sm` écrase le `padding-right` du plugin forms | `app.css` : `select:not([multiple]) { padding-right: 2.25rem }` | capture relue ; `DefautsNavigateurTest` |
| 5 | Paramètres Généraux : l'onglet « Données de Test » coupé à 1 280 px | tablist `overflow-x-auto` de 8 onglets | `parametres-generaux.blade.php` : `flex-wrap` | e2e responsive bureau (tableau/conteneur tronqué) ; `DefautsNavigateurTest` |
| 6 | Soins : le texte disait que le décès « se déclare sur le poste… ce que le web ne fait pas », alors que le bouton « Décès » existe | texte périmé après l'ajout du décès au web | `soins-calendrier.blade.php` : texte réécrit | `DefautsNavigateurTest` |
| 7 | Modales : le clavier continuait de parcourir la page cachée derrière ; Échap sans effet ; focus perdu à la fermeture | aucune gestion de focus | `app.js` : focus à l'ouverture, Tab piégé, Échap = bouton `annuler*/fermer*/renoncer*`, focus restitué | e2e « clavier » et « accessibilité : 11 modales » |
| 8 | Réseau coupé pendant une action : rien ne se passe ; session expirée : `confirm()` anglais « This page has expired » | Livewire 3.1 : échec 503 silencieux ; 419 → `confirm()` natif | `app.js` : bandeau « Connexion au serveur perdue… » (disparaît au retour) ; 419 → message français puis `/login` | e2e « perte de connexion », « session expirée » |

Les défauts 7 et 8 ont été identifiés par lecture de `livewire.js` (3.1.2) et sondage du navigateur ; leurs correctifs sont prouvés par
les scénarios e2e, qui échoueraient sans eux (aucun gestionnaire n'existait).

## 4. Constats sans correctif (à décider)

- **Onglet périmé** : agir sur un élément déjà supprimé depuis un autre onglet (ex. « Supprimer » un client déjà en corbeille) n'ouvre
  rien et ne dit rien (aucune erreur 500). Un message « cet élément n'existe plus » serait plus clair (écrans clients/fournisseurs…).
- **Lignes cliquables non focalisables** : le détail d'une vente, d'une facture ou le choix d'un jour de fiche s'ouvre par un clic sur
  une cellule ou une ligne (`wire:click` sur `td`/`tr`) : inaccessible au clavier.
- **Tablette 768 px** : la barre latérale (256 px) reste dépliée ; le contenu n'a que 512 px (utilisable, serré).
- **Panier / modale** : un rafraîchissement perd le panier en cours (état du composant) — comportement attendu, vérifié sans erreur.
- **Règlement fournisseur** : un montant supérieur au reste dû est **plafonné** au reste (comportement du Dart) et non refusé.

## 5. Ce qui n'est pas couvert

- Navigateurs autres que Chromium (Firefox, Safari), vrai téléphone (tactile, clavier virtuel), lecteurs d'écran.
- Dépôt du logo, SMTP, transmission e-MECeF réelle (le serveur e-MECeF d'essai n'existe pas), sauvegarde logique téléchargée.
- Écrans à contenu non rempli par le jeu de données : bovins, poulets/pondeuses, poissons-chats, lapins, escargots (fumée, onglets et
  modale de bande seulement ; la saisie complète est faite sur goliaths/pintades) ; plan comptable (zone d'un autre chantier, lecture et
  export seulement) ; paramètres d'élevage (onglets cliqués, pas de saisie) ; rapports (onglets, filtres, export).
- Perte de connexion « en vol » (réponse coupée après l'écriture serveur) ; concurrence réelle de deux postes sur la même fiche
  (la divergence est préparée en base, pas produite par deux postes).
- Rendu `page.pdf()` jugé par taille et géométrie (pas de comparaison visuelle page à page).
