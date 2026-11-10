# 47b — Achats, fournisseurs, dépenses, stocks : parité du web avec le poste

> **Statut au 09/11/2026.** Le web fait désormais tout ce que le poste fait en achats **sans dépendre du stock** : commande,
> réception, règlement, plus (ce que le Dart ne fait pas) modification et annulation. Ce document dit les règles lues dans le
> Dart, ce que le web ajoute, les erreurs d'expert trouvées, les décisions **à valider par le client** et les limites.
> Code : `app/Services/Achats/GestionAchats.php`, `app/Services/Comptabilite/EcrituresAutomatiquesAchats.php`,
> `app/Livewire/{Achats,Fournisseurs,Depenses,GestionStocks}.php`, `app/Http/Controllers/ImpressionsAchats.php`.

## 1. Ce que le web fait

| Écran | Droit | Actions |
|---|---|---|
| Achats & Commandes (`/achats`) | lecture `view-achats` ; écriture `manage-achats` (administrateur) | Nouvelle commande (panier d'intrants, quantité entière, prix unitaire, fournisseur, mode Espèces / Mobile Money / Crédit, montant réglé, échéance, « livrée immédiatement »), **modifier** tant que « Commandé », **réceptionner**, **régler**, **annuler** avec motif ; bon de commande, historique imprimable ; export XLSX |
| Fournisseurs (`/fournisseurs`) | idem | « Régler » une dette (bouton du poste), suppression **refusée** tant qu'une dette est ouverte (décision du client), relevé fournisseur imprimable, état « Fournisseurs & Dettes » imprimable, export XLSX, bloc de cohérence achats ↔ 401 |
| Saisie des Dépenses (`/depenses`) | lecture `view-achats` ; écriture `manage-comptabilite` | Création, annulation (existaient), **corriger** (annule la pièce et passe la corrigée, une seule transaction), état imprimable, export XLSX (`view-comptabilite`) |
| Gestion Stocks (`/stocks`) | `view-stocks` (administrateur) | Intrants (création, modification : existaient), journal imprimable, export XLSX du journal |

Toute écriture passe par `TableSync::absorber` (poste « web », `Catalogue::POSTE_WEB`), jamais par un `update` direct ; chaque opération
est **une transaction** (un refus du serveur — mois clôturé, équilibre — n'en laisse aucune trace). Le droit est vérifié dans **chaque**
méthode Livewire (composant neuf par appel, testé) et dans le service. Numérotation : `ACH-WEB-AAAA-NNN` (séquence déduite des achats
enregistrés, jamais renumérotée, jamais réutilisée même après annulation) ; pièces `REG-<réf>` (règlement) et `ANN-<n°>` (extourne).

## 2. Écritures d'achat — port fidèle du Dart (`GenererEcrituresAutomatiques`)

| Fait | Journal | Pièce | Lignes |
|---|---|---|---|
| Commande (livrée ou non) | `AC` | `<réf>` | **D** 601 (intrants provende), 602 (Marchandises), 622 (Vétérinaire) selon la **catégorie de l'intrant** ; **C** 531 (Espèces, Crédit, Non précisé) ou 512 (Mobile Money) = montant payé ; **C** 401 = total − payé |
| Règlement | `CA` | `REG-<réf>` | **D** 401 / **C** 531 ou 512, du montant **réellement versé** |
| Extourne (annulation, modification) | `OD` | `ANN-<n° de la pièce>` | pièce inverse ligne pour ligne, à la date du jour, `contrepasse_de`, vérifiée par le serveur |

- **La charge est constatée à la commande, pas à la réception** : le Dart écrit la pièce dans `enregistrerAchat` et `receptionnerAchat`
  n'écrit rien. Le web fait de même : réceptionner = journal seul.
- **Pas de TVA** : le Dart n'en génère pas sur les achats (le plan comptable du poste n'a pas de 4452). Le web non plus.
- Montants arrondis au centime (`round(…, 2)`) : un prix à deux décimales ne désunit jamais une pièce (tolérance du serveur : 0,01).
  Quantité **entière** (comme le champ du poste) ; prix unitaire décimal possible. Total d'une commande = Σ quantité × prix.
- **Jeu chiffré à la main** (testé) : 100 Maïs × 300 + 10 Vaccin × 500 + 4 Sel × 1 250 = 40 000, 15 000 payés en espèces →
  D 601 30 000, D 622 5 000, D 602 5 000 / C 531 15 000, C 401 25 000. Règlement de 10 000 en Mobile Money → D 401 / C 512 10 000, reste dû
  15 000 = solde 401. Règlement de 999 999 → borné à 15 000, 401 revient à 0. Annulation → tous les comptes de l'achat reviennent à 0.

**Cohérence achats ↔ comptabilité** : l'écran Fournisseurs rapproche les dettes des achats (total − payé, hors annulés) du solde créditeur du
compte 401 sur les **seules pièces d'achat**, montre l'écart et le solde 401 de toutes les pièces (qui compte aussi les dépenses « à crédit »
saisies à la main). Visible de qui a `view-comptabilite`.

## 3. Réception : « stock propre à chaque poste + journal partagé »

> **Levé par `47s_STOCK_CIBLE.md` (09/11/2026)** : la commande désigne un **poste de stock** ; ce poste applique l'entrée de stock et le PMP à SON stock à la
> réception (et la sortie inverse à l'annulation d'une commande livrée), une seule fois. D1 est donc résolue par l'alternative proposée (le poste qui a passé
> la commande est proposé par défaut). Le texte ci-dessous décrit la limite d'avant.

La réception au web inscrit **un mouvement `Entrée` par ligne** au journal partagé (`mouvements_intrant`, poste d'origine = Web, motif
« Réception commande <réf> ») et **ne met aucun stock ni PMP à jour**. C'est déclaré sur l'écran (bandeau, fenêtre de confirmation, message).
Conséquence à connaître (décision D1) : si la commande a été passée **sur un poste**, ce poste n'augmente pas son stock du fait d'une réception
faite au web (absorber un achat d'un autre poste ne produit aucun effet). Pas de prix proposé à la commande : le PMP est propre à chaque poste.

## 4. Erreurs d'expert trouvées et corrigées

| # | Où | Erreur | Correction |
|---|---|---|---|
| E1 | Poste `reglerAchat` | Un règlement supérieur au reste dû bornait la dette mais **l'écriture portait le montant saisi** : 401 devenait débiteur (999 999 sur 6 000 dus → 401 débiteur de 993 999), le solde fournisseur ≠ dettes. L'écran dit pourtant « borné au reste dû ». | L'écriture porte le montant **réellement versé** ; un règlement sur une commande annulée est refusé. Testé au poste et au web. |
| E2 | Poste + serveur | Le choix **« Crédit »** de la liste déroulante de la commande était **refusé en bloc par la synchronisation** (« mode inconnu ») : un achat à crédit du poste ne partait jamais. | « Crédit » ajouté aux modes acceptés (serveur `AchatsTable::MODES`, poste `TableAchatsPoste`). |
| E3 | Poste, absorption d'un achat | Les lignes étaient **immuables** : une commande modifiée ailleurs aurait gardé ses anciennes lignes avec un nouveau total. Et une ligne locale déjà synchronisée cédait même à une version **plus ancienne**. | Tant que l'achat local est « Commandé », la saisie la plus récente **remplace** ses lignes (intrant inconnu : refusée, rien perdu) ; livré ou annulé : lignes figées. Une version strictement plus ancienne ne remplace plus rien. Même règle au serveur. |
| E4 | PDF « Achats & Commandes » du poste | Les totaux et le reste dû **comptaient les commandes annulées**. | Les annulées sont listées mais exclues des totaux (poste, web). |
| E5 | Poste, écran Achats | `achats.echeance` existe (rapports, dettes) mais **aucun écran ne la renseigne** : toutes les dettes sont « sans délai ». | Le web la saisit (jamais antérieure à la commande) et l'affiche (dettes, relevé, « échue »). |
| E6 | Références | Le serveur et le poste n'acceptaient que `ACH-Pn-…` / `ACH-…` : une référence web aurait été refusée. | `ACH-WEB-AAAA-NNN` acceptée (globalement unique, comme un code de poste). |

## 5. Ce que le web ajoute au Dart (à valider)

- **Modifier une commande « Commandé »** : fournisseur, lignes, mode, échéance. Le montant déjà réglé est conservé (il ne se corrige que par un
  règlement) et ne peut dépasser le nouveau total. Les pièces vivantes sont **extournées** et une pièce neuve est écrite, **à la date du jour**
  (une correction se passe dans la période ouverte).
- **Annuler avec motif obligatoire** : extourne de toutes les pièces vivantes (achat + règlements), statut « Annulé », audit. Si la commande était
  livrée : un mouvement `Sortie` (quantité négative) par ligne au journal, stock des postes inchangé. Le solde dû d'une commande annulée est 0.
- **Mode du règlement** choisi à chaque règlement (Espèces → 531, Mobile Money → 512), proposé d'après la commande ; le poste utilise le mode de la
  commande, d'où un règlement Mobile Money d'une commande « Crédit » comptabilisé en caisse.
- **Bon de commande** (le poste n'imprime que des listes), **relevé fournisseur**, historiques imprimables (`@media print`, bouton « Imprimer / PDF »).
- **Corriger une dépense** : annulation + nouvelle pièce, en une transaction.

## 6. Décisions à valider par le client

| # | Décision prise (option la plus prudente) | Alternative |
|---|---|---|
| **D1** | La réception au web **ne met pas à jour le stock du poste qui a passé la commande** (décision « stock propre ») : ce poste doit ajuster son stock lui-même. | Faire appliquer par le poste, à l'absorption, la réception d'une de **ses** commandes faite ailleurs (stock + PMP). |
| **D2** | Annuler une commande **déjà réglée** extourne aussi les règlements : on suppose que le fournisseur **rembourse** (la caisse reçoit). Un avertissement est affiché. | Refuser l'annulation tant que le remboursement n'est pas saisi ; ou créer une créance sur le fournisseur (409). |
| **D3** | Une commande **livrée** peut être annulée (mouvement `Sortie` au journal). | Réserver l'annulation aux commandes « Commandé » et traiter un retour par un avoir. |
| **D4** | La charge est constatée **à la commande** (comme le poste), pas à la réception. | Constater à la réception (stock en cours) : changement du poste. |
| **D5** | **Pas de TVA** sur les achats (comme le poste). | Compte 4452 « TVA déductible » si l'entreprise y est assujettie. |
| **D6** | Modification et annulation écrivent leurs extournes **à la date du jour** ; si le mois du jour est clôturé, l'opération est refusée avec le motif du serveur. | Date de la pièce d'origine (impossible si le mois est clos). |
| **D7** | Quantité d'une ligne = **entier** (comme le poste) ; un intrant ne figure qu'**une fois** par commande (au poste, un second clic ajoute 1). | Quantités décimales (le stock du poste est entier : il arrondirait à la réception). |
| **D8** | Annuler une commande qui a été **modifiée** puis réglée extourne toutes les pièces vivantes d'un coup. | — |
| **D9** | Le montant réglé à la commande est **borné au total** sans message (comme le poste). | Refuser un montant supérieur au total. |

## 7. Tests et mutations

- **Poste** (`achats_web_poste_test.dart`, 9 tests ; `achats_sync_poste_test.dart` adapté) : référence `ACH-WEB-…`, mode Crédit, remplacement des
  lignes d'une commande « Commandé », lignes figées d'un achat livré, version plus ancienne, intrant inconnu, aucun effet sur stock / PMP / journal /
  écritures, règlement borné (401 reste à zéro), règlement sur commande annulée.
- **Web** (`AchatsOperationsWebTest`, 34 tests ; `AchatsWebTest` adapté) : droits de **chaque** méthode (composant neuf par appel), chaque message de
  validation, écritures **chiffrées à la main**, numérotation, modes 512/531, borne au total, prix à deux décimales, période clôturée (aucune trace),
  réception, règlements, modification, annulation (livrée ou non), cohérence 401, bon de commande, historique, relevé, états imprimables, exports XLSX
  (contenu relu, droit), correction d'une dépense (et rollback).
- **Mutations** : voir le rapport du coordinateur (script `b_mut_achats.py`, 40 mutations sur le service, les écritures, la table serveur, les droits).

## 8. Écarts et limites

- **Stock, PMP, valeur, seuils critiques** : absents du web (propres à chaque poste). **Exclus du web** : l'ajustement d'inventaire et la fabrication de
  provende (ils modifient le stock), et la suppression d'un intrant (le poste l'archive localement ; le serveur n'a pas de pierre tombale d'intrant).
  Création et modification d'intrants : faites (référentiel). Journal : consultation, impression, export.
- **Commande d'un poste non encore synchronisé** : si le web modifie ou annule un achat dont les écritures n'ont pas encore atteint le serveur,
  il n'y a pas de pièce à extourner ; une modification écrit alors une pièce complète (risque de double comptage à l'arrivée de celle du poste).
  À éviter : synchroniser le poste avant.
- Les règlements sont **cumulés** sur l'achat (colonne `paye`) : l'historique détaillé des règlements est dans le journal (`REG-…`), pas dans l'achat.
- Pas de pièce justificative (le poste n'en stocke pas), pas de PDF binaire : des vues imprimables (« Enregistrer au format PDF » du navigateur) ;
  les tableaux s'exportent en **XLSX** (jamais CSV).
- La suppression de fournisseur reste une suppression douce, refusée tant qu'une dette est ouverte.
