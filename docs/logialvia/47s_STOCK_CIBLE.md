# 47s — Stock ciblé : une opération web atteint le stock d'un poste

> **Statut au 09/11/2026.** Lève la limite signalée par `47a_` (D6) et `47b_` (D1) : « une opération web n'atteint aucun stock ».
> Schéma du poste **49**. Code : poste `core/sync/effets_stock_poste.dart`, `core/sync/table_effets_stock_poste.dart`,
> `approvisionnement/domain/services/calcul_pmp.dart`, absorbeurs `table_{achats,ventes,mouvements_intrant,mouvements_produit}_poste.dart` ;
> serveur `app/Services/PosteDeStock.php`, `app/Sync/Tables/{AchatsTable,VentesTable,MouvementsIntrantTable,MouvementsProduitTable,EffetsStockTable}.php`,
> `app/Services/Commerce/CorrectionsStockWeb.php`, migration `2026_11_09_161000_create_stock_cible.php` ; écrans `Achats`, `Ventes`, `Catalogue`, `GestionStocks`.

## 1. La règle

**La décision du client est conservée** : le stock et le PMP sont **propres à chaque poste** ; le journal des mouvements est un historique
partagé (`46_` §14-§15) ; absorber le fait d'un autre poste n'a **aucun effet local**. Le web n'a toujours **aucun stock**.

**Exception documentée à la règle d'or.** Une opération web qui a un effet de stock **désigne un poste de stock**. Le fait porte `poste_cible`
(identifiant du poste, son `device_id`) en plus de son `device_id` d'origine (« web »). **Seul le poste désigné**, en absorbant ce fait,
**applique l'effet de stock et de PMP à SON stock, une seule fois**. Tous les autres postes l'absorbent comme historique, exactement comme avant.

Tout le reste de la règle d'or tient : un fait **sans** poste cible, ou qui en désigne un autre, n'a aucun effet chez moi.

## 2. Ce que le poste désigné applique

| Fait web | Effet au poste désigné | Nature (journal `effets_appliques`) |
|---|---|---|
| **Réception d'achat** (statut → « Livré », ou commande livrée à la saisie) | pour chaque ligne : `stock += qté` (entier, comme `_receptionnerLignes`) et `PMP' = (stock × PMP + qté × prix) ÷ (stock + qté)` arrondi à l'entier ; stock résultant ≤ 0 : PMP inchangé. **Même fonction `CalculPmp.apresReception`** que la réception saisie au poste (test : même résultat). | `reception` |
| **Annulation d'une commande livrée** (statut → « Annulé ») | pour chaque ligne : `stock = max(0, stock − qté)` et PMP rendu par l'**inverse** `PMP' = (stock × PMP − qté × prix) ÷ (stock − qté)` (`CalculPmp.apresRetrait`) si le stock couvre la quantité et en laisse ; sinon PMP inchangé. Jamais de PMP négatif. Seulement si la réception a été appliquée **ici**. | `annulation_reception` |
| **Vente** (statut « Payée » ou « Avance ») | pour chaque ligne : `stock = max(0, stock − qté)` — le **plancher à 0** de `_decrementerStock` du poste | `vente` |
| **Annulation de vente** | pour chaque ligne : `stock += qté` — comme `_incrementerStock` (sans plafond). Seulement si la vente a été décrémentée **ici**. | `annulation_vente` |
| **Correction de stock produit** (journal `mouvements_produit`) | `stock = max(0, stock + variation signée)` | `correction` |

- **Une seule fois** : chaque effet a un identifiant déterministe (UUID v5 de `effet:<nature>:<fait>`), la table locale `effets_appliques` a une
  clé unique (`fait_id`, `nature`) et l'absorbeur la consulte avant d'écrire. Rejeu, version identique, règlement ultérieur d'une commande,
  tirage complet, « Renvoyer vers ce poste » : aucun second effet. L'effet et sa trace s'écrivent dans la **même transaction** que l'absorption.
- **`fiche_ventes_jour` : règle de `46a_` inchangée.** Le web tient son propre compteur (une ligne par poste, `qte` remplacée) ; le poste désigné
  **ne touche pas** son compteur du jour en absorbant une vente web (sinon elle serait comptée deux fois). Seul le **stock** bouge.
- **Les lignes du journal partagé** (`mouvements_intrant`, `Entrée` / `Sortie` écrites par le web à la réception / annulation) portent `poste_cible`
  **à titre informatif seulement** : l'effet est porté par l'**achat** (il connaît le prix, donc le PMP). Le journal ne l'applique jamais — sinon double effet.
  Le poste voit ces lignes marquées « appliqué depuis le web à ce poste » lorsque l'effet a réellement eu lieu.
- **Aucune écriture dans le journal partagé par le poste désigné** : la trace de l'effet est une table à part (`effets_appliques`), pas un mouvement,
  pour ne pas dupliquer au serveur les mouvements que le web a déjà inscrits.

## 3. Le poste désigné, côté web

Un écran qui écrit un fait à effet de stock propose un champ **« Poste de stock »** :

| Opération | Écran | Quand | Liste proposée |
|---|---|---|---|
| Réception d'achat | Achats : nouvelle commande (obligatoire si « livrée immédiatement » quand le client l'exige), modale « Réceptionner » | à la commande, ou **une seule fois** à la réception | postes appairés, non révoqués, déjà synchronisés, dont le compte lit les achats |
| Vente / caisse web | Ventes : panier | à l'encaissement | idem, compte qui lit les ventes |
| Correction de stock | Catalogue : « Corriger le stock » | à la correction (poste **obligatoire** : sans poste, rien ne serait corrigé) | idem, `view-ventes` ou `view-stocks` |

- **Défaut mémorisé par compte et par type d'opération** (`postes_stock_defauts`) ; s'il n'est plus désignable il est ignoré ; sans mémoire, s'il
  n'y a **qu'un** poste désignable, c'est lui. À la réception d'une commande **passée sur un poste**, le poste proposé est d'abord celui qui l'a passée
  (c'est exactement l'alternative D1 de `47b_`).
- **Sans poste choisi** (« Aucun ») : le fait n'est que du journal partagé, comme avant, et l'écran le dit. **Décision à valider (D1)** : un réglage
  serveur `STOCK_CIBLE_OBLIGATOIRE=true` exige un poste pour toute vente, réception et correction (désactivé par défaut pour ne pas bloquer un
  web utilisé sans poste appairé).
- **Historiques** : colonne « Poste de stock » dans Achats et dans l'historique des ventes (et ligne dans Catalogue pour les corrections) avec
  l'état : *En attente du poste P2* · *Appliqué au poste P2* · *Appliqué avec avertissement* · *Non appliqué par le poste P2* · *Poste révoqué : jamais
  appliqué* · *Poste P2 (appliqué à la réception)* · *aucun effet* (annulé avant d'avoir touché un stock). Le journal des stocks affiche « Web → P2 ».
  L'état se déduit de la **trace** que le poste remonte (`effets_stock`, §5) : le web n'invente rien.
- **Bandeau** d'explication sur chaque écran ; la mention « aucun stock » a disparu des écrans Achats, Ventes et Catalogue (Gestion des stocks
  continue de dire que stock, PMP et valeur ne se lisent qu'au poste : c'est vrai).

## 4. Validation et droits (serveur)

- `poste_cible` : `uuid` facultatif. **Seul le web désigne** : un poste qui pousse un fait avec `poste_cible` est refusé (« Seul le web peut désigner
  un poste de stock. ») — un poste ne délègue pas son stock à un autre.
- Le poste désigné doit être **désignable** (`PosteDeStock::verifier`), à la création du fait ou quand il se pose (une fois) :
  - inconnu ou **révoqué** : « Poste de stock inconnu ou révoqué : choisissez un poste appairé et actif. » ;
  - **jamais synchronisé** (`curseur_tirage` vide : n'a jamais fini un tirage, donc n'a ni référentiels ni stock « à lui », et la remise à zéro le remet
    dans cet état) : « Ce poste ne s'est encore jamais synchronisé… » ;
  - dont le compte connu ne peut pas **lire** les faits de l'opération : « Le compte connecté au poste P2 n'a pas le droit de lire ces opérations :
    elles ne lui parviendraient jamais. » (sinon le fait ne lui serait jamais servi et l'effet attendrait pour toujours).
  Le refus s'affiche à la saisie (message clair) et **rien n'est écrit** (une transaction par opération). Justification du refus plutôt qu'une file
  d'attente : une opération qui ne pourra **jamais** s'appliquer ferait croire que le stock a bougé.
- **Droits d'écriture** inchangés : `manage-achats` (réception), `manage-ventes` (vente), `manage-stocks` ou `manage-ventes` (correction), vérifiés
  dans **chaque** méthode Livewire et dans le service. `effets_stock` : lecture `view-stocks`/`view-achats`/`view-ventes`, **écriture ouverte à tout
  compte** (un poste dont le compte ne fait que lire les ventes applique tout de même son effet et doit pouvoir le dire).
- **Immutabilité (cas 6)** : `poste_cible` se pose **à la création** (vente, correction) ou **une seule fois tant que la commande est « Commandé »**
  (achat). Ensuite : un autre poste est refusé (« …ne peut plus être changé : le fait lui est lié. »), une désignation tardive d'une commande déjà
  livrée ou d'une vente saisie sans poste est refusée, et l'**absence** de `poste_cible` dans un envoi (ancien poste, aller-retour) ne l'efface pas.
  L'annulation suit le même poste (la sortie part au poste lié).
- Au poste, l'effet suit le **lien d'origine** (`poste_cible` de la ligne locale), jamais le poste du message.

## 5. La trace : `effets_stock` (table locale `effets_appliques`)

Fait **immuable** remonté par le poste désigné : `{id, fait_type (achat|vente|mouvement_produit), fait_id, nature, reference, libelle, etat
(applique|avertissement|ignore), avertissement, applique_le}`. Le serveur recalcule l'identifiant (un poste ne peut pas forger l'effet d'un autre),
l'enregistre sans rien appliquer et le redistribue : **chez les autres postes c'est de l'historique** (`origine` non nulle, aucun stock touché). Un
effet portant l'identifiant **de ce poste** qui revient d'un tirage complet (base restaurée) redevient le sien : il prouve que l'effet a déjà eu lieu.
Ordre de synchronisation : **après** les faits (achats, ventes, journaux). La remise à zéro du serveur le purge (comme les autres faits).

## 6. Cas limites

| # | Cas | Comportement |
|---|---|---|
| 4a | Poste désigné **hors ligne** | L'effet attend sa prochaine synchronisation ; le web affiche « En attente du poste P2 ». Rien ne se perd (le fait reste au serveur, le curseur du poste n'avance pas sans lui). |
| 4b | Poste révoqué/supprimé/jamais synchronisé **à la saisie** | Opération refusée, message clair, aucune écriture. |
| 4c | Poste révoqué **après** la saisie | L'effet ne viendra jamais : le web affiche « Poste révoqué : jamais appliqué » ; l'annulation reste possible, avec un avertissement (« …ne peut pas recevoir la sortie de stock »). Il n'y a pas de transfert automatique vers un autre poste (décision D4). |
| 5 | **Stock insuffisant** (vente, annulation de réception, correction négative) | Plancher à 0 **et** avertissement tracé : « Stock insuffisant au poste P2 : « Goliath mature » — 5 demandés, 2 disponibles ; stock ramené à 0 ». Visible au **poste** (panneau « Opérations du web appliquées à ce poste », en rouge) et au **web** (badge « Appliqué avec avertissement » et le texte). Pas de stock négatif silencieux. |
| 6 | Changer le poste cible après coup | Interdit (§4). |
| — | Commande déjà **livrée au poste** (réception locale) avant que le web la désigne | L'effet n'est **pas** appliqué (double entrée) ; la trace « Non appliqué : la commande … était déjà livrée… » remonte (état `ignore`). |
| — | Vente **annulée aussi sur le poste** (restitution locale) avant l'annulation web | Pas de seconde restitution ; trace `ignore`. |
| — | Fait qui arrive **déjà annulé** (jamais vu vendu / livré par ce poste) | Aucun effet, aucune trace : rien n'a jamais touché son stock. |
| — | Commande modifiée puis livrée avant que le poste ne tire | Les lignes appliquées sont celles du message (lignes figées dès « Livré »). |
| — | Intrant / produit inconnu au poste désigné | Ligne non appliquée, avertissement tracé (état `avertissement`) ; le reste de l'opération s'applique. |
| — | Saisie locale en conflit (LWW) | L'effet suit **l'état que le poste adopte** : une version refusée parce que la saisie locale est plus récente n'applique rien (le dernier écrivain gagne, comme pour le reste). |
| — | Vente web d'un produit encore inconnu du poste | Refusée à la réception comme aujourd'hui (les produits arrivent avant) : l'effet est alors perdu pour ce poste — limite héritée de `46_` §12. |
| — | Annuler au web une vente / commande **d'un poste** (sans poste cible) | Comme avant : aucun effet de stock (le web ne sait pas quel stock a bougé ; `47a_` D6). Pour une **commande** encore « Commandé », le web peut en revanche la réceptionner pour le poste qui l'a passée (§3). |

## 7. Formules (récapitulatif chiffré)

Départ : INT-001 stock 100, PMP 200.
- Réception 50 × 320 → stock 150, PMP `(100×200 + 50×320) ÷ 150 = 240`.
- Annulation de cette réception → stock 100, PMP `(150×240 − 50×320) ÷ 100 = 200`.
- Annulation alors que le magasin n'a plus que 20 : stock 0, PMP **240 inchangé**, avertissement « 50 à retirer, 20 disponibles ».
- Vente de 3 : produit à 10 → 7 ; à 2 → 0 + avertissement ; annulation → +3.

## 8. Migration

- **Poste, schéma 49** (`if (from < 49)`, additif et idempotent) : `poste_cible` (texte, nullable) sur `achats`, `ventes`, `mouvements_intrant`,
  `mouvements_produit` ; table `effets_appliques`. Aucune ligne existante n'est touchée : **sans poste cible, aucun effet rétroactif**. Les anciennes
  reconstructions de tables (v34, v35, v36) créent désormais la colonne (elles copient le schéma courant). Testée sur une vraie base v47 et v48,
  rejouée, avec perte nulle (`migration_v49_stock_cible_test.dart`). La version 48 appartient à un autre chantier.
- **Serveur** : `2026_11_09_161000_create_stock_cible.php` (`poste_cible` ×4, `effets_stock`, `postes_stock_defauts`), idempotente.
- **Compatibilité** : un poste non migré ignore `poste_cible` (champ inconnu) et ne renvoie jamais la trace ; le web affiche alors « En attente »
  indéfiniment pour ce poste — mettre à jour le poste. Le serveur accepte les envois d'un ancien poste (le champ est facultatif).

## 9. Décisions à valider par le client

| # | Décision prise | Alternative |
|---|---|---|
| **D1** | Le poste de stock est **facultatif** par défaut (« Aucun » = journal seul, comme avant) ; `STOCK_CIBLE_OBLIGATOIRE=true` l'impose. La correction exige toujours un poste. | Poste toujours obligatoire. |
| **D2** | Vente web sur un stock insuffisant : **appliquée avec plancher à 0 + avertissement** (jamais refusée au poste : la vente est déjà faite et encaissée). | Bloquer la vente au web (impossible : le web ne voit aucun stock). |
| **D3** | Annulation d'une réception : le PMP est rendu par l'**inverse** de la formule (la marchandise repart au prix d'entrée) ; plancher / stock vidé : PMP inchangé. | PMP jamais modifié par une sortie (standard du poste pour ses propres sorties). |
| **D4** | Poste désigné **révoqué** après coup : l'effet ne s'applique jamais, le web le dit ; pas de transfert vers un autre poste. | « Réaffecter » une opération en attente à un autre poste (contredit l'immutabilité). |
| **D5** | Annulation d'une vente **saisie sur un poste** depuis le web : aucun effet de stock (inchangé). | Faire restituer par le poste d'origine. |
| **D6** | `fiche_ventes_jour` : le poste désigné ne touche pas son compteur (le web tient le sien). | Compter la vente web dans le compteur du poste désigné. |
| **D7** | La trace d'effet est visible de **tous** les postes (historique) ; elle ne contient ni stock ni PMP, seulement le libellé de ce qui a été fait. | Ne la réserver qu'au web et au poste concerné. |
| **D8** | Réception : la désignation tardive d'un poste sur une commande passée ailleurs n'est possible que tant qu'elle est « Commandé ». | Autoriser la désignation après livraison (risque de double entrée). |

## 10. Limites

- **Le web ne montre toujours aucun stock** : il n'en a pas. Il montre l'**état de l'opération**, pas le niveau de stock du poste.
- L'effet est **différé** : il a lieu à la prochaine synchronisation du poste désigné (30 s en ligne, plus tard hors ligne).
- Une vente web qui cite un produit **inconnu du poste désigné** est refusée localement (limite de `46_` §12) : l'effet est perdu pour ce poste.
- Les **ajustements d'inventaire** et la **fabrication de provende** restent exclus du web (ils modifient le stock d'intrants sans prix) ; seule la
  correction de **produit vendable** est ciblée.
- Poste désigné **réinstallé** (nouvel identifiant) : c'est un autre poste ; les opérations en attente pour l'ancien ne s'appliqueront jamais.
- Deux postes ne peuvent pas se partager une opération : un fait = un poste.

## 11. Tests

- **Poste** : `test/core/sync/stock_cible_poste_test.dart` (38 : formule, réception, annulation, plancher, double effet, lien immuable, vente, correction,
  garde-fous du service, aller-retour du poste cible, affichage, trace), `stock_cible_deux_postes_test.dart` (4 : A hors ligne, B inchangé, tirage complet, trace chez B), `test/core/migration_v49_stock_cible_test.dart`
  (7 : v47 et v48, perte nulle, idempotence, unicité).
- **Serveur** : `tests/Feature/Sync/StockCibleTest.php` (14 : validation, droits, immutabilité, redistribution, trace, remise à zéro),
  `tests/Feature/Web/StockCibleWebTest.php` (23 : postes désignables, chaque refus, réception, annulation, états, défaut mémorisé, obligatoire, vente, correction, droits).
- **Essais réels** (`serveur_reel_test.dart`, groupe « stock ciblé ») : 6 essais contre le **vrai** serveur Laravel (vente ciblée puis annulation, stock
  insuffisant, réception + PMP puis annulation, correction, refus du poste révoqué / jamais synchronisé / inconnu / d'un poste qui prétend désigner) :
  `bash logialvia_app/outils/essai_vrai_serveur.sh` donne 61/61 (les 55 d'avant restent verts).
- **Mutations** (62, script d'exécution jetable) : 54 tuées du premier coup ; les 8 survivantes étaient 2 gardes redondantes (le contrôle de
  `PosteDeStock` fait aussi partie de l'absorbeur ; `quantite > stock` implique `reste <= 0`, simplifié) et 6 cas non couverts, tous ajoutés
  (idempotence propre du service, entrée unique d'une commande réceptionnée localement avant la livraison web, aller-retour du poste cible) et tués
  ensuite. Reste 1 mutante équivalente : retirer le contrôle précoce du poste dans `VentesWeb::encaisser`, l'absorbeur renvoyant le même motif.
