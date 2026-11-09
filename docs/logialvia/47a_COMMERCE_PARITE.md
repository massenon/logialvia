# 47a — Parité du commerce au web : caisse, historique, retours, recouvrement, impressions

> **Statut au 09/11/2026.** Complète `45_` (§6c à §8), `46_` (§6 à §15), `46d_` (comptabilité) et `46f_`. Le Dart est la source ;
> le web s'y conforme, sauf les écarts listés au §5 (chacun est à valider). **Aucune décision du §6 n'a été validée par le client.**
> Aucune table ni colonne nouvelle : la version de schéma du poste reste **42** (la 43 est réservée aux devis et factures, la 48 que
> j'avais en réserve n'a pas servi).

## 1. Ce qui est possible au web maintenant

| Écran / geste | Où | Droit | Écriture |
|---|---|---|---|
| **Caisse** (« Enregistrer Vente ») : grille de produits (recherche, catégorie, fourchette de prix), vente à la pièce (quantité + **montant global saisi**), panier (modifier, retirer, empiler), client choisi dans la liste (ou nom libre), mode (espèces, Mobile Money avec la ligne créditée), condition (comptant / avance avec échéance), livraison (4 modes, frais facturés ajoutés au total), monnaie à rendre, encaissement | `/ventes` | `manage-ventes` (reverifié dans **chaque** méthode et dans le service) | `VentesTable::absorber` + `EcrituresTable::absorber` + `VentesJourTable::absorber`, une transaction |
| **Historique** : filtres (référence/client, statut), détail, **annulation avec motif** (écriture d'extourne), **modification** des champs autorisés (§2.4), export **XLSX**, impression | `/ventes` | `manage-ventes` ; export `export-ventes` | idem |
| **Retours et Avoirs** : consultation des ventes annulées et de leur motif (comme le poste, voir §2.5) | `/ventes` | `view-ventes` | aucune |
| **Recouvrement** d'une créance (total ou partiel), lettre de relance, export XLSX des créances | `/clients` | `manage-ventes` ; export `export-ventes` | idem |
| **Vues imprimables** : facture de vente, historique, suivi des soldes clients, lettre de relance (`@media print` + « Imprimer / PDF ») | `/impression/…` | facture, lettre : `view-ventes` ; tableaux : `export-ventes` | aucune |

Hors de cette tranche : l'onglet « Devis Prestations » (agent Devis/Factures — `Ventes::ONGLETS` est la liste où l'ajouter) et les factures
d'avoir normalisées e-MECeF (`FacturesMecef`).

## 2. Règles

### 2.1 Une vente est un fait avec ses lignes

Écrite par `VentesTable::absorber` (device `Catalogue::POSTE_WEB`) : mêmes validations, mêmes motifs de refus que pour un poste. Référence
**`V-WEB-AAAA-NNN`** (code de poste `WEB`, comme `OD-WEB-2026-0001`), séquence déduite des ventes réellement enregistrées (maximum + 1, 3 chiffres),
**jamais renumérotée** (annuler ne libère pas le numéro) ; si deux comptes valident en même temps, la seconde est refusée par l'unicité et le web
recompte (3 essais). La référence du web est **globale** (comme `V-P2-…`) : `VentesTable::porteeReference` et la regex du serveur **et du poste**
(`table_ventes_poste.dart`) l'acceptent. Total = somme des **montants saisis** (jamais quantité × prix) + frais d'une livraison **facturée**. Le prix
unitaire de la ligne est **déduit** (montant ÷ quantité). Comptant : `paye = total` (pas le montant remis en main). Validations (messages du Dart,
mot pour mot) : panier vide ; quantité entière ≥ 1 et montant > 0 ; Mobile Money sans « Téléphone Principal » aux Paramètres Généraux ; avance sans
montant ; avance qui solde (« choisissez Comptant ») ; comptant insuffisant ; livraison facturée sans frais.

### 2.2 Stock : propre à chaque poste (décision du client)

Une vente au web **ne décrémente aucun stock** et n'écrit aucun mouvement de produit ; l'écran le dit (`data-ecart="ventes"`) et la modale d'annulation
précise qu'aucun stock n'est restitué. Les contrôles de stock du poste (rupture, quantité > stock) n'existent donc pas au web.

### 2.3 Compteur `fiche_ventes_jour` (`46a_`)

Le web est un poste : **une ligne** par (filière, jour) pour le device `WEB`, identifiant déterministe `UuidDeterministe::ventesJour(filière, jour, WEB)`,
`qte` **remplacée** (jamais additionnée en base), jamais négative. Vente : `+qte` ; annulation d'une vente **du web** : `−qte`. L'annulation d'une vente
**d'un poste** ne touche **ni** le compteur du web **ni** celui du poste (un compteur ne se corrige que par son poste ; voir D6). La date est le jour civil
de la vente dans le fuseau de l'exploitation. `fiche_journee.vente` reste un instantané (D3 de `46a_`).

### 2.4 Écritures automatiques — `EcrituresAutomatiquesVentes`

Port de `generer_ecritures_automatiques.dart` ; comptes du plan (19 comptes, aucun inventé) : **531** caisse, **512** Mobile Money, **411** clients,
**701** ventes avicoles, **707** ventes de marchandises. Pièce de vente : journal `VT`, numéro = référence, `vente_ref`. Encaissement `531/512` au débit,
créance `411` au débit du reste dû, produits au crédit par (compte, centre analytique) — « Commerce Annexe » → 707, sinon 701 avec le centre de la filière
du produit (`null` si inconnue). Recouvrement : `REG-<référence>`, journal `CA`, trésorerie D / 411 C. Annulation : `ANN-<référence>`, journal `OD`.

Jeu chiffré à la main, **commun au poste et au web** (`ecritures_ventes_commun_test.dart` / `EcrituresAutomatiquesVentesTest.php`) :

| Cas | Lignes (compte, débit, crédit, centre) |
|---|---|
| A. 2 goliaths 12 000, comptant espèces | 531 D 12 000 · 701 C 12 000 (Goliaths) |
| B. goliath 6 000 + pintade 6 500 + 3 tee-shirts 3 000, avance Mobile Money, 4 000 reçus | 411 D 11 500 · 512 D 4 000 · 701 C 6 500 (Pintades) · 701 C 6 000 (Goliaths) · 707 C 3 000 (Commerce Annexe) |
| C. goliath 6 000 + livraison facturée 1 500, comptant | 531 D 7 500 · 701 C 6 000 (Goliaths) · 707 C 1 500 (sans centre) — pièce **équilibrée** |
| D. recouvrement de la créance de 8 500 | 531 D 8 500 · 411 C 8 500 (poste : borné ; web : excédent **refusé**) |
| E. B + recouvrement 2 000 (Mobile Money) + annulation | ANN : 701 D 6 500 (Pintades) · 701 D 6 000 (Goliaths) · 707 D 3 000 · 411 C 9 500 · 512 C 6 000 ; 411, 512, 701, 707 soldés |
| F. annulation de C | 531, 701, 707 soldés (frais repris) |

Équilibre débit = crédit vérifié par le serveur pour chaque pièce (tolérance 0,01), verrous de période (mois, exercice) et plan, **comme pour un poste**.
Droit : une pièce automatique (`vente_ref`) est acceptée avec `manage-ventes` — le caissier n'a pas besoin de la comptabilité.

### 2.5 Annulation, retours et avoirs

Annulation **logique** (BR-VTE-004, jamais de suppression) : statut « Annulée », motif **obligatoire** (4 motifs proposés), `paye` conservé, pièce d'extourne
dans la même transaction, vente « déjà annulée » refusée. Elle fonctionne aussi sur une vente **d'un poste** (la vente garde son `device_id` et sa référence ;
son curseur de tirage avance : les postes la reçoivent).

**« Retours et Avoirs » au poste = une vue de consultation des ventes annulées**, sans saisie ni table propre (`OngletRetours`). Le web fait de même. Il n'existe
**pas** de facture d'avoir dans ce module : les avoirs normalisés (FA) sont les factures de l'agent Devis/Factures. D'où : aucune table, aucune migration.

### 2.6 Modification d'une vente

Le poste n'en a pas. Le web autorise **uniquement** les champs sans effet comptable : **client** (liste ou nom), **échéance** (vente en avance), **adresse et
contact de livraison**. Montant, lignes, mode, date, statut, payé : refusés (« Annulez la vente pour la corriger »). Une vente annulée ne se modifie pas.
Le solde dérivé des **deux** clients (ancien et nouveau) est recalculé par le serveur (voir §4).

### 2.7 Recouvrement

`VentesWeb::recouvrer` : montant > 0, **refusé s'il dépasse le reste dû** (« Le montant dépasse le reste dû (8 500 FCFA). »), vente en avance seulement, mode
au choix (défaut : celui de la vente). `paye` augmente ; soldée, `paye` vaut **exactement** le total et le statut passe « Payée ». `solde_creance` du client est
**dérivé** (jamais saisi). Lettre : avec échéance « Lettre de Relance » (« reste impayée »), sans échéance « Rappel de Solde » (le solde est dû, pas en retard).

### 2.8 Impressions et exports

Format d'export des tableaux : **XLSX** (consigne du client, `App\Support\ExportXlsx`), bouton « Exporter (XLSX) », droit `export-ventes` vérifié **dans la méthode**
(403 sinon), mêmes lignes et mêmes filtres que l'écran ; un texte saisi commençant par `=` n'est jamais une formule. Facture, ticket, lettre : pages HTML
autonomes (aucun asset) avec `@media print` et « Imprimer / PDF » ; l'historique imprimé suit les filtres de l'écran.

## 3. Erreurs d'expert trouvées en portant (corrigées)

| # | Constat | Correction |
|---|---|---|
| **E1** | **Poste** : une livraison facturée entrait dans le total mais pas dans les crédits : la pièce de vente était **déséquilibrée** des frais. Le serveur la refuse ; au poste l'échec est **avalé** (`catch` muet) : la vente n'avait jamais d'écriture. | Frais crédités (707, sans centre) à la vente, repris à l'annulation ; test C/F rouge avant, vert après. |
| **E2** | **Poste** : un recouvrement supérieur au reste dû était borné dans la vente mais **comptabilisé en entier** (411 créditeur de l'excédent). Le test existant ne regardait que `paye`. | L'écriture porte le montant réellement encaissé ; test D. |
| **E3** | **Poste** : une vente modifiée ailleurs (client, échéance, adresse, contact) arrivait « identique » si statut et montants ne changeaient pas et **se perdait en silence**. | Comparaison étendue, champs de livraison écrits ; 5 tests, 7 mutations tuées. |
| **E4** | **Serveur** : réaffecter une vente à un autre client ne recalculait que le **nouveau** solde ; l'ancien client gardait une créance fantôme. | Les deux soldes recalculés (test à trois étapes). |
| **E5** | **Poste, à signaler** : l'annulation recalcule la contrepassation depuis la catégorie **courante** du produit et le mode de la vente : un produit recatégorisé, ou un recouvrement fait par un autre moyen, désoldait 701/707 ou 531/512. | Le web contrepasse ce que le grand livre porte (§5, D3). Le poste n'est **pas** modifié. |
| **E6** | **Poste, à signaler** : l'historique PDF est titré « filtré » (Doc E9 §5) mais exporte `vm.ventes` sans filtre. | Le web imprime selon les filtres de l'écran. |

## 4. Contrôle d'expert SYSCOHADA (non corrigé : à arbitrer avec l'expert-comptable du client)

1. **Numérotation du plan.** Le plan (semé à l'identique au poste et au serveur) place « Ventes de produits avicoles » en **701** et « Ventes de marchandises » en
   **707**. Dans le SYSCOHADA révisé : **701 = ventes de marchandises**, 702 = produits finis, 707 = produits accessoires. La **caisse** est au **57x** (571) et
   les banques au **52x** ; le plan utilise 531 (« Caisse ») et 512 (« Mobile Money »). Le web **reprend le plan du poste** (le Dart est la source et
   `ConformiteComptabiliteDartTest` le compare compte pour compte) ; changer les numéros est une décision du plan, pas de cette tranche.
2. **TVA.** Les groupes de taxe (A exonéré, B 18 %) n'existent que pour les factures e-MECeF. Ni le poste ni le web ne ventilent la TVA collectée (443) à la
   vente : le produit est crédité **au montant saisi**. Le client a arbitré que l'élevage est exonéré ; un produit du groupe B (commerce annexe) serait, lui,
   à ventiler HT/TVA. **À valider** (prix saisis TTC ?).
3. **Frais de livraison facturée** : crédités en 707 faute de compte dédié (« ports et frais accessoires facturés » est un 707x). **À valider.**
4. **Avances et acomptes** : la vente à crédit passe le reste en 411 ; le compte 419 (avances reçues) du plan n'est pas utilisé (pas d'acompte avant vente).

## 5. Écarts web / poste (déclarés dans les écrans)

| Écart | Raison |
|---|---|
| Annulation : contrepassation du **grand livre** et non recalculée depuis la vente | E5 ; même résultat dans le cas courant, jamais deux fois |
| Écriture refusée (mois ou exercice clôturé) : **l'opération entière est refusée** avec le motif ; le poste garde la vente sans écriture | E1 : jamais une vente sans écriture |
| Recouvrement : excédent **refusé** (le poste le borne) ; **mode de règlement au choix** (le poste prend celui de la vente) | un client peut solder en Mobile Money une vente payée en espèces ; 531/512 doivent suivre |
| Pas de contrôle de stock, pas de restitution de stock à l'annulation | décision « stock propre à chaque poste » |
| Modification d'une vente (champs sans effet comptable) | absent du poste ; besoin évident (mauvais client) |
| Annuler une vente de poste dont les écritures ne sont pas encore arrivées : **refusé** (« synchronisez le poste ») | sinon une extourne sans original |
| Facture, historique, soldes, lettre : pages imprimables, pas de PDF généré par le serveur | les PDF restent au poste ; XLSX pour les tableaux |
| Pas de fourchette bloquante : le montant négocié n'est pas contrôlé contre `price`/`price_max` | comme le poste |
| « Marquer contacté » (CRM) et date de dernier contact : non repris (le « Relancer » du poste horodate seulement) | hors périmètre commerce ; le lien « Lettre de relance » le remplace |

## 6. Décisions à valider par le client

| Id | Décision prise | Alternative |
|---|---|---|
| **D1** | Référence du web **`V-WEB-AAAA-NNN`**, globale. | Code `P0` partagé ; numéro attribué par le serveur. |
| **D2** | Une écriture refusée **annule** la vente du web (atomicité). | Garder la vente sans écriture comme le poste (livre faux). |
| **D3** | Annulation = contrepassation de ce que le grand livre porte. | Recalcul depuis la vente (poste). |
| **D4** | Frais de livraison facturée : **707** sans centre ; TVA non ventilée ; plan 701/707/531/512 repris (§4). | Compte dédié 7071 ; TVA 443 ; renumérotation SYSCOHADA. |
| **D5** | Champs modifiables d'une vente : client, échéance, adresse et contact de livraison. | Aucun (comme le poste), ou aussi le mode (avec écriture de reclassement). |
| **D6** | Annuler une vente de **poste** depuis le web ne corrige pas le compteur du jour de ce poste (ni le stock). Si le poste annule aussi hors ligne, deux extournes sont possibles (le web ne voit que ce que le serveur connaît). | Réserver l'annulation au poste d'origine. |
| **D7** | Recouvrement : mode au choix, excédent refusé. | Mode de la vente imposé ; excédent borné. |
| **D8** | Droits : caisse, annulation, modification, recouvrement `manage-ventes` (agent de vente, administrateur) ; export `export-ventes` ; le **comptable consulte** (`view-ventes`) sans écrire ni exporter. | Donner `export-ventes` au comptable. |
| **D9** | Une saisie du web est datée du plus tardif de (maintenant, ligne connue + 1 µs) : elle gagne contre un poste en avance. | Horloge du serveur seule (saisie ignorée sans bruit). |

## 7. Tests

- **Poste** : `test/commercial/ecritures_ventes_commun_test.dart` (6, cas A à F ; C, D et F rouges avant correction), `ventes_sync_poste_test.dart` (+8 : V-WEB acceptée,
  forme voisine refusée, client / client rattaché / échéance / adresse / contact appliqués un par un). **7 mutations** tuées (regex WEB, chaque champ de la comparaison,
  chaque écriture de champ).
- **Serveur** : `Feature/Web/EcrituresAutomatiquesVentesTest` (9 : jeu commun, catégorie modifiée, recouvrement par un autre moyen, constructeurs purs), `Feature/Sync/VentesWebReferenceTest`
  (4 : référence globale, formes voisines, deux soldes, vente du web servie avec ses lignes).
- **Web** : `Feature/Web/CommerceWebTest` (44 : accès, droit de **chaque** méthode d'écriture et du service, grille et fourchette, vente à la pièce, chaque message de validation,
  encaissement et absence de stock, références, Mobile Money / avance / livraison, client par nom et homonymes, compteur du jour, mois clôturé, annulation, retours, modification,
  recouvrement, factures, historique et soldes imprimables, lettre, exports XLSX et leur droit), `VentesWebTest` adapté (16).
- Mutations PHP : voir le rapport de tranche.

## 8. Limites

- Aucun essai contre le **vrai** serveur Laravel depuis le poste (`serveur_reel_test.dart` non étendu) ; le faux serveur rejoue la regex `V-WEB`.
- `FacturesTable::venteGlobale` (agent Devis/Factures) ne reconnaît que `V-P…` : une facture d'une vente `V-WEB-…` serait traitée comme référence **locale à son poste**. À aligner
  (`V-(P\d+|WEB)-…`) lors de la fusion.
- Deux postes ou deux comptes web qui annulent la même vente hors ligne peuvent passer deux extournes (D6).
- Aucune pièce justificative, aucun envoi de la lettre (impression seulement, comme le poste : pas de passerelle SMS ou courriel).
- Fichiers partagés touchés : `faux_serveur_sync.dart` (une regex, ligne 750). Aucun autre fichier partagé.
