# F6 — Module : Comptabilité Complète (Niveau Professionnel, Conformité SYSCOHADA)

**Ce document remplace intégralement la version précédente**, jugée insuffisante. Le module Comptabilité est reconstruit pour couvrir l'ensemble des états et outils d'un logiciel comptable professionnel conforme au référentiel **SYSCOHADA** (Système Comptable OHADA, applicable au Bénin) : Journal, Grand Livre, Balance Générale, Bilan, Compte de Résultat, Tableau des Flux de Trésorerie (TAFIRE), Notes Annexes, Clôture Périodique et Annuelle.

Règles métier de référence : BR-CPT-001 à 006 (Doc B6, enrichi ci-dessous). Modèle de données : Doc D1, enrichi ci-dessous (§9).

---

## 1. Écrans du Module (10 écrans, révisé de 7 à 10)

| # | Écran | Fichier Dart | Route | État |
|---|---|---|---|---|
| 1 | Saisie des Dépenses | `saisie_depenses_screen.dart` | `/depenses` | ✅ implémenté |
| 2 | Hub Comptabilité | `comptabilite_hub_screen.dart` | `/comptabilite` | ✅ implémenté |
| 3 | Journal Comptable | `journal_comptable_screen.dart` | `/comptabilite/journal` | ✅ implémenté |
| 4 | **Grand Livre** | `grand_livre_screen.dart` | `/comptabilite/grand-livre` | ✅ implémenté |
| 5 | **Balance Générale** | `balance_generale_screen.dart` | `/comptabilite/balance` | ✅ implémenté |
| 6 | Plan Comptable | `plan_comptable_screen.dart` | `/comptabilite/plan` | ✅ implémenté |
| 7 | Comptabilité Analytique | `comptabilite_analytique_screen.dart` | `/comptabilite/analytique` | ✅ implémenté (portée réduite — voir l'encadré du §7) |
| 8 | **États Financiers** (Bilan + Compte de Résultat + TAFIRE + Notes Annexes) | `etats_financiers_screen.dart` | `/comptabilite/etats-financiers` | ✅ implémenté |
| 9 | Clôture (Périodique **et** Annuelle) | `cloture_exercice_screen.dart` | `/comptabilite/cloture` | ✅ implémenté |
| 10 | Bilan Entreprise → ~~absorbé dans l'écran 8~~ **écran distinct rétabli** (voir §10.19) | `/comptabilite/bilan` | `BilanEntrepriseScreen` | Gérante |

> **Correction de ce document** : les mentions « (inchangé) » des écrans 1, 6 et 7 laissaient entendre qu'ils existaient déjà en Dart. Ils n'existaient qu'en HTML — les 9 écrans ont été écrits pour ce module.

**Routage.** `assets/js/sidebar.js` ne référence que **4** des 9 écrans (`/comptabilite`, `/comptabilite/grand-livre`, `/comptabilite/balance`, `/comptabilite/etats-financiers`) ; les 5 autres ne sont atteignables que par les tuiles du hub — c'est exactement le comportement du prototype, reproduit tel quel (`AppRouter._routesHubComptabilite`). `/depenses` figure, lui, dans le groupe COMMERCIAL de la barre latérale.

**Un seul ViewModel pour les 9 écrans** (`ComptabiliteViewModel`) : ils lisent la même table `ECRITURE_COMPTABLE` et doivent afficher le même Résultat Net (BR-CPT-005). Neuf ViewModels auraient chacun leur copie des écritures, donc leur propre version du résultat — précisément ce que la règle interdit.

---

## 2. Écran — Grand Livre (nouveau)

Liste chronologique de **toutes les écritures d'un compte donné**, avec solde progressif — l'outil de vérification compte par compte, complémentaire du Journal (qui liste tout, tous comptes mélangés, par date).

### Structure
1. Sélecteur de compte (recherche par numéro ou libellé, Doc E4 §5)
2. KPI du compte sélectionné : Solde d'Ouverture, Total Débit Période, Total Crédit Période, Solde Final
3. `DataTable` : Date, N° Pièce/Origine, Libellé, Débit, Crédit, **Solde Progressif** (colonne cumulative, propre au Grand Livre)
4. Bouton "Imprimer PDF" (Doc E9, réutilise le générateur générique)

### Règle de Calcul — Solde Progressif
```dart
class GrandLivreCalculator {
  List<LigneGrandLivre> calculer(String compteType, double soldeOuverture, List<EcritureComptable> ecritures) {
    var solde = soldeOuverture;
    final lignes = <LigneGrandLivre>[];
    for (final e in ecritures..sort((a, b) => a.dateEcriture.compareTo(b.dateEcriture))) {
      // BR-CPT-007 : le sens du solde progressif depend de la nature du compte
      // (comptes de classe 1,4,5 crediteurs vs 2,3,4,5,6 debiteurs — Doc B6)
      solde += _estCompteDebiteurParNature(compteType) ? (e.debit - e.credit) : (e.credit - e.debit);
      lignes.add(LigneGrandLivre(ecriture: e, soldeProgressif: solde));
    }
    return lignes;
  }
}
```

---

## 3. Écran — Balance Générale (nouveau)

Vue de synthèse — **un seul tableau, une ligne par compte utilisé sur la période**, condition indispensable de tout logiciel comptable professionnel pour vérifier l'équilibre global avant de produire les états financiers.

### Structure
1. Sélecteur de période (mois, trimestre, exercice complet)
2. KPI : Total Débits, Total Crédits, **Écart** (doit toujours afficher 0 — alerte visuelle rouge si ≠ 0, signe d'une écriture déséquilibrée quelque part)
3. `DataTable` (colonnes fixes, format standard de balance à 6 colonnes) :

| N° Compte | Libellé | Solde Ouverture (D) | Solde Ouverture (C) | Mouvements (D) | Mouvements (C) | Solde Final (D) | Solde Final (C) |
|---|---|---|---|---|---|---|---|

### Règle Métier — Équilibre Global (nouvelle règle à cataloguer)
> **BR-CPT-004** (nouvelle) : La somme de tous les Soldes Finaux Débiteurs de la Balance Générale doit toujours être égale à la somme de tous les Soldes Finaux Créditeurs. Tout écart signale une anomalie de saisie à corriger avant toute clôture (périodique ou annuelle).

```dart
class BalanceGeneraleValidator {
  bool estEquilibree(List<LigneBalance> lignes) {
    final totalDebit = lignes.fold(0.0, (s, l) => s + l.soldeFinalDebit);
    final totalCredit = lignes.fold(0.0, (s, l) => s + l.soldeFinalCredit);
    return (totalDebit - totalCredit).abs() < 0.01; // tolerance d'arrondi FCFA
  }
}
```

**Interdiction structurelle** : la Clôture Périodique et la Clôture Annuelle (§8) DOIVENT vérifier `BalanceGeneraleValidator.estEquilibree()` en première étape — une clôture ne peut jamais s'exécuter sur une balance déséquilibrée (renforce BR-CPT-001/002 déjà posées).

---

## 4. Écran — États Financiers (refonte complète)

Un seul écran à onglets internes (`TabController`), regroupant les 4 états financiers réglementaires SYSCOHADA + un sélecteur de période commun.

```
┌─────────────────────────────────────────────────┐
│ [Bilan] [Compte de Résultat] [Flux de Trésorerie] │ [Notes Annexes]
├─────────────────────────────────────────────────┤
│         Sélecteur de période / exercice           │
│         Bouton "Exporter PDF" (état actif)         │
├─────────────────────────────────────────────────┤
│              Contenu de l'onglet actif             │
└─────────────────────────────────────────────────┘
```

### Onglet 1 — Bilan (structure SYSCOHADA complète, pas un résumé)

**ACTIF**
| Rubrique | Comptes SYSCOHADA source |
|---|---|
| Charges Immobilisées | Classe 2, comptes 20 |
| Immobilisations Incorporelles | Classe 2, comptes 21 |
| Immobilisations Corporelles | Classe 2, comptes 22-24 |
| Immobilisations Financières | Classe 2, comptes 26-27 |
| **= Total Actif Immobilisé** | |
| Stocks | Classe 3 |
| Créances et Emplois Assimilés (Clients, autres créances) | Classe 4, soldes débiteurs |
| **= Total Actif Circulant** | |
| Trésorerie-Actif (Caisse, Mobile Money) | Classe 5, soldes débiteurs |
| **= TOTAL GÉNÉRAL ACTIF** | |

**PASSIF**
| Rubrique | Comptes SYSCOHADA source |
|---|---|
| Capital | Classe 1, compte 10 |
| Réserves, Report à Nouveau, Résultat Net de l'exercice | Classe 1, comptes 11-13 (RAN alimenté par BR-CPT-002) |
| **= Total Capitaux Propres** | |
| Dettes Financières | Classe 1, comptes 16-19 |
| **= Total Ressources Stables** | |
| Dettes Circulantes (Fournisseurs, Fiscal, Social) | Classe 4, soldes créditeurs |
| **= Total Passif Circulant** | |
| Trésorerie-Passif (découvert bancaire éventuel) | Classe 5, soldes créditeurs |
| **= TOTAL GÉNÉRAL PASSIF** | |

**Contrôle d'équilibre affiché en permanence** : `TOTAL GÉNÉRAL ACTIF = TOTAL GÉNÉRAL PASSIF`, badge vert si égal, rouge sinon (même logique que BR-CPT-004).

### Onglet 2 — Compte de Résultat (structure en cascade SYSCOHADA, pas une simple liste Charges/Produits)

```
  Ventes de Marchandises et Produits (classe 70)
− Achats de Marchandises Consommés (classe 60)
= MARGE COMMERCIALE
+ Production de l'Exercice (le cas échéant)
− Consommations en Provenance des Tiers (classes 60-62 hors marchandises)
= VALEUR AJOUTÉE
− Charges de Personnel (classe 66)
− Impôts et Taxes (classe 64)
= EXCÉDENT BRUT D'EXPLOITATION (EBE)
+ Autres Produits d'Exploitation − Autres Charges d'Exploitation
− Dotations aux Amortissements et Provisions (classe 68)
= RÉSULTAT D'EXPLOITATION
+ Résultat Financier (Produits Financiers classe 77 − Charges Financières classe 67)
= RÉSULTAT DES ACTIVITÉS ORDINAIRES (RAO)
+ Résultat Hors Activités Ordinaires (classes 78/88 − 68/83)
− Participation des Travailleurs − Impôt sur les Sociétés
= RÉSULTAT NET DE L'EXERCICE
```

**Cohérence obligatoire** : le "RÉSULTAT NET DE L'EXERCICE" calculé ici DOIT être strictement égal au solde du compte 13 (Résultat de l'exercice) affiché au Bilan (Onglet 1) — vérification croisée automatique, alerte si divergence.

### Onglet 3 — Tableau des Flux de Trésorerie (TAFIRE simplifié)

Adapté à l'échelle de l'exploitation (une exploitation agricole de cette taille n'a pas la même complexité qu'un grand groupe — structure SYSCOHADA respectée mais présentation simplifiée) :

```
FLUX DE TRÉSORERIE LIÉS AUX ACTIVITÉS OPÉRATIONNELLES
  Résultat Net de l'Exercice
  + Dotations aux Amortissements (charge non décaissée)
  − Variation du Besoin en Fonds de Roulement (Stocks + Créances − Dettes Circulantes)
  = FLUX NET DE TRÉSORERIE D'EXPLOITATION

FLUX DE TRÉSORERIE LIÉS AUX ACTIVITÉS D'INVESTISSEMENT
  − Acquisitions d'Immobilisations
  + Cessions d'Immobilisations
  = FLUX NET DE TRÉSORERIE D'INVESTISSEMENT

FLUX DE TRÉSORERIE LIÉS AUX ACTIVITÉS DE FINANCEMENT
  + Nouveaux Emprunts − Remboursements d'Emprunts
  + Apports en Capital
  = FLUX NET DE TRÉSORERIE DE FINANCEMENT

VARIATION DE TRÉSORERIE DE LA PÉRIODE
  = Flux Exploitation + Flux Investissement + Flux Financement

Trésorerie à l'Ouverture + Variation = Trésorerie à la Clôture
  (doit être egal a la Tresorerie-Actif du Bilan, Onglet 1)
```

```dart
class TafireCalculator {
  TafireResult calculer(int exerciceAnnee, ComptabiliteRepository repo) {
    final resultatNet = /* depuis compte 13 */;
    final dotationsAmortissement = /* somme classe 68 */;
    final variationBfr = /* (stocks fin - stocks debut) + (creances fin - creances debut)
                              - (dettes circ fin - dettes circ debut) */;
    final fluxExploitation = resultatNet + dotationsAmortissement - variationBfr;
    // ... investissement et financement, structure identique
    return TafireResult(fluxExploitation: fluxExploitation, /* ... */);
  }
}
```

### Onglet 4 — Notes Annexes

Contenu textuel/tabulaire structuré, propre à chaque exercice, expliquant les méthodes et détaillant certains postes du Bilan/Compte de Résultat — **obligatoire en SYSCOHADA**, souvent omis dans les implémentations "légères", d'où l'insistance de votre demande.

| Note | Contenu attendu |
|---|---|
| Note 1 — Méthodes Comptables | Texte libre : méthode d'amortissement (linéaire), méthode de valorisation des stocks (PMP — cohérent avec `INTRANTS.pmp`, Doc D1), devise (FCFA) |
| Note 2 — Immobilisations | Tableau détaillé : nature, valeur brute, amortissements cumulés, valeur nette — détail du poste "Immobilisations Corporelles" du Bilan |
| Note 3 — Stocks | Détail par catégorie (Intrants Provende / Produits Vendables / Marchandises), quantités et valeurs — cohérent avec Doc D1 §Intrants/ProduitsVendables |
| Note 4 — Créances et Dettes | Ancienneté des créances clients et dettes fournisseurs (cohérent avec Doc F4/F5, Clients/Fournisseurs) |
| Note 5 — Engagements Hors Bilan | Texte libre : engagements non comptabilisés (garanties données/reçues) — vide par défaut pour une petite exploitation, mais le champ doit exister |

**Saisie** : formulaire de texte structuré + tableaux, un formulaire par note, persistance liée à l'exercice comptable (`NOTES_ANNEXES`, Doc D1 §9 ci-dessous).

---

## 5. Nouvelle Règle Métier — Cohérence Croisée entre États

> **BR-CPT-005** (nouvelle) : Le Résultat Net affiché au Compte de Résultat, le solde du compte 13 au Bilan, et le point de départ du calcul de Flux d'Exploitation au TAFIRE doivent être **strictement identiques** à tout instant — calculés depuis la même source (`ECRITURE_COMPTABLE`, Doc D1), jamais trois calculs indépendants qui pourraient diverger.

```dart
// Assurer cette coherence structurellement : UN SEUL usecase calcule le
// Resultat Net, reutilise par les 3 etats — jamais 3 implementations paralleles
// (Strict Avoid §5/§12, deja pose comme principe transversal du projet).
class CalculerResultatNetUseCase {
  Future<double> executer(int exerciceAnnee) async { /* source unique de verite */ }
}
```

---

## 6. Écran — Clôture Périodique et Annuelle (fusion, enrichi)

**Distinction nouvelle, absente de la version précédente de ce document** :

| Type | Fréquence | Effet |
|---|---|---|
| **Clôture Périodique** (mensuelle) | Chaque fin de mois | Verrouille les écritures du mois écoulé (`isLocked` par mois, pas par exercice complet), calcule les totaux mensuels pour la Balance Générale et les Rapports (Doc F7), **ne génère pas de RAN** — l'exercice reste ouvert |
| **Clôture Annuelle** | Une fois par exercice | Processus complet déjà détaillé en Doc J1 : verrouillage total de l'exercice + génération du RAN + ouverture du nouvel exercice |

### Nouvelle Règle Métier — Clôture Périodique
> **BR-CPT-006** (nouvelle) : Une écriture appartenant à un mois clôturé (clôture périodique) ne peut plus être modifiée, **sauf** par un utilisateur avec le rôle `admin`, qui peut exceptionnellement "déclôturer" un mois pour correction — action journalisée (BR-ADM-003). Ce mécanisme de déblocage exceptionnel n'existe **pas** pour la clôture annuelle (BR-CPT-001, verrouillage strictement définitif).

### Structure d'Écran — Onglet Clôture Périodique (nouveau)
1. Sélecteur de mois à clôturer
2. Vérification préalable : `BalanceGeneraleValidator.estEquilibree()` (§3) — bloque la clôture si déséquilibrée
3. Bouton "Clôturer le Mois" (confirmation standard, Doc E5 §3 — pas le renforcement de la clôture annuelle, Doc J1)
4. Liste des mois déjà clôturés, avec bouton "Déclôturer" visible uniquement pour `admin` (Doc I1)

---

## 7. Comptabilité Analytique — enrichissement (cohérence avec le nouveau niveau de détail)

L'écran déjà documenté (précédemment §5 de la version courte) doit maintenant produire un **Compte de Résultat par Centre de Profit** (même structure en cascade que §4 Onglet 2, mais filtrée par `espece`/centre), pas seulement CA/Coûts/Marge en 3 chiffres bruts.

> ⚠️ **CETTE EXIGENCE N'EST PAS RÉALISABLE EN L'ÉTAT DU MODÈLE DE DONNÉES — constat d'implémentation.**
>
> « Filtrée par `espece`/centre » suppose que chaque écriture porte un **axe analytique**. `ECRITURE_COMPTABLE` (Doc D1 §9) n'a aucune colonne de ce type, aucun écran n'en saisit, et le prototype `comptabilite-analytique.html` ne calcule rien : ses trois centres (Goliaths 58 000, Pintades 40 000, Commerce Annexe 44 000) sont des constantes JavaScript posées « pour être cohérentes avec `rapports-exports.html` ».
>
> Le problème n'est d'ailleurs pas que technique : un sac de provende nourrit plusieurs espèces à la fois. Le rattacher à une seule filière serait une clé de répartition — une estimation de gestion, pas une écriture comptable.
>
> **Ce qui est livré**, et qui est réellement dérivable du grand livre : la ventilation **Avicole** (701 / 601 + 622) contre **Commerce Annexe** (707 / 602) — la même que le KPI « Chiffre d'Affaires » du tableau de bord, donc cohérente avec le reste de l'application. Les charges de structure (613, 616, 624, 628) sont affichées **non affectées** plutôt que réparties arbitrairement, et l'écran énonce la limite à l'utilisatrice.
>
> **Pour obtenir la ventilation par filière**, il faudrait : (a) ajouter une colonne `centreAnalytique` à `ECRITURE_COMPTABLE`, (b) la renseigner dans `GenererEcrituresAutomatiques` en éclatant le crédit 701 par espèce des lignes de vente, (c) décider d'une clé de répartition des charges communes, et (d) la faire valider par la Gérante. Ces 4 points sont hors du périmètre de ce document et doivent être arbitrés avant développement.

---

## 8. Récapitulatif — Cohérence avec Doc J1/J2 (déjà existants)

- Doc J1 (Bascule & Clôture d'Exercice) reste la référence du **processus détaillé** de clôture annuelle (les 5 étapes déjà spécifiées) — ce document F6 ajoute la Clôture Périodique en complément, ne remplace pas J1
- Doc J2 (Rapports et États) reste la référence de la **génération PDF** de ces états — ce document F6 précise le **contenu structurel exact** que J2 doit exporter

---

## 9. Modèle de Données — Intégré à Doc D1

Les 2 tables nécessaires à ce module (`NOTES_ANNEXES`, `CLOTURES_PERIODIQUES`) sont désormais intégrées directement dans **Doc D1** (dictionnaire de données, diagramme ERD, et liste `@DriftDatabase`) — pas dupliquées ici, conformément au principe de source unique déjà appliqué sur l'ensemble de cette série (Strict Avoid §12).

**Contrainte à retenir** : toute écriture sur `ECRITURE_COMPTABLE` doit désormais vérifier un **double verrouillage** — `EXERCICE_COMPTABLE.isCloture` (BR-CPT-001) **et** `CLOTURES_PERIODIQUES` du mois concerné (BR-CPT-006) — avant d'être acceptée.

---

## 10. Constatations d'implémentation (Flutter Desktop) — Strict Avoid §7

Écrit au moment de la conversion du prototype. Chaque point est un écart **réel** entre ce document / le prototype et ce que le code peut faire honnêtement. Rien n'a été « amélioré » de sa propre initiative : soit le prototype a été suivi, soit l'écart est motivé et signalé à l'écran.

### 10.1 `m10-comptabilite-data.js` appartient à un autre projet — non utilisé

Le dossier `prototype_html` contient `m10-comptabilite-data.js` et 5 pages `m10-*.html` avec un plan comptable complet. **Il a été écarté.** Il décrit une activité d'hôtellerie-restauration — « Prestations d'hébergement », « Ventes bar », « Prestations touristiques (circuits) », « Caisse — Restaurant », « Frais plateforme de gestion (hébergement cPanel) » — et son en-tête référence `SEEDER_TEST_LARAVEL.md` et `SPEC_ECRAN_M10_*.md`, documents absents de ce projet. Aucune page `m10-*.html` n'est référencée par `assets/js/sidebar.js`.

L'utiliser aurait donné à une exploitation avicole de Natitingou des comptes de bar et de location de véhicules. **Source retenue** : `plan-comptable.html`, le seul écran relié à la navigation LogiALVIA.

### 10.2 Le plan comptable du prototype ne permet pas de produire un Bilan

`plan-comptable.html` liste **12 comptes**, et **aucun de classe 1** (capitaux). Sans Capital, Report à Nouveau ni Résultat de l'exercice, le passif du Bilan est structurellement vide et l'équilibre Actif = Passif exigé au §4 Onglet 1 est impossible.

3 comptes ont été ajoutés au socle, aux numéros standard SYSCOHADA — **ce ne sont pas des inventions, mais leur absence du prototype est un manque réel** :

| Compte | Libellé | Motif |
|---|---|---|
| 101 | Capital Social | Apport de l'exploitante — sans lui, aucun financement au passif |
| 121 | Report à Nouveau | Alimenté par le RAN de la clôture annuelle (BR-CPT-002) |
| 131 | Résultat de l'Exercice | Poste de rattachement du Résultat Net au Bilan (BR-CPT-005) |

### 10.3 Deux écrans du prototype se contredisent sur les comptes de charges

`saisie-depenses.html` (l.44-49) impute les dépenses sur **613 Locations, 616 Assurances, 624 Transports, 628 Charges Diverses de Gestion**. Aucun des quatre ne figure dans le tableau `PLAN_COMPTABLE` de `plan-comptable.html`.

Côté web chaque page a son propre tableau JavaScript, l'incohérence reste invisible. Ici les deux écrans lisent la **même** table `PLAN_COMPTABLE` : sans ces comptes, la clé étrangère de `ECRITURE_COMPTABLE` rejette toute dépense. Les 4 comptes sont ajoutés au socle avec les libellés exacts de l'écran des dépenses (`PlanComptableSeeder.comptesDepensesAjoutes`).

**Conséquence sur le déploiement** : une base installée avant cet ajout a déjà un plan non vide, et un seeder « si la table est vide, la remplir » ne l'aurait jamais complétée. `PlanComptableSeeder.completerComptesManquants()` insère les numéros absents à chaque démarrage, **sans jamais écraser** un compte renommé ou archivé par la Gérante. Vérifié sur la base réelle : 15 → 19 comptes, `schemaVersion` inchangé (11), aucune autre table touchée.

### 10.4 « Compte de Trésorerie Débité » — le libellé du prototype est inversé

`saisie-depenses.html` intitule le champ « Compte de Trésorerie **Débité** ». Lors d'une dépense la trésorerie est **créditée** (elle diminue) et c'est le compte de charge qui est débité. La mécanique du prototype, elle, était juste (`compteToCredit()` crédite bien 531/512) : seul le libellé était faux. Corrigé en « Compte de Trésorerie **Crédité** ».

### 10.5 Le filtre de statut des dépenses était décoratif — ÉCART_DELIBERE

Le même écran propose un filtre « Payée / En attente » alors que son formulaire n'offre que Caisse (531) et Mobile Money (512) : toute dépense saisie est décaissée, donc « Payée ». Le choix « En attente » ne pouvait jamais rien renvoyer — une fonctionnalité décorative au sens du Master Prompt §2.3.

Le choix **« À crédit — Fournisseur (401) »** a donc été ajouté au sélecteur de règlement. Le statut devient une lecture du réel : une charge soldée par un compte 40x reste due, tout autre compte de règlement la rend payée. Aucun champ « statut » n'est stocké — il est dérivé de l'écriture, donc toujours vrai.

### 10.6 Le tableau du Journal ne sait pas représenter une écriture réelle — ÉCART_DELIBERE

`journal-comptable.html` affiche **une ligne par pièce**, avec deux colonnes « Débit » et « Crédit » contenant chacune un *nom de compte*, plus une colonne « Montant ». Cette disposition ne représente qu'une pièce à exactement deux lignes.

Or les écritures automatiques du système en comptent trois ou quatre : une vente partiellement réglée génère 531 (débit) + 411 (débit) / 701 (crédit) + 707 (crédit). La colonne « Débit » devrait alors contenir deux comptes et « Montant » deux montants.

Le tableau adopte la disposition d'un journal professionnel : **une ligne par ligne d'écriture**, groupée par pièce, colonnes N° Pièce / Date / Journal / Compte / Libellé / Débit / Crédit. La modale de saisie manuelle du prototype (un compte à débiter, un à créditer, un montant, « l'équilibre est garanti par construction ») est conservée **mot pour mot**.

### 10.7 Le sens naturel des comptes du prototype ne couvre que 6 comptes

`grand-livre.html` code le sens du solde dans deux tableaux en dur (`COMPTES_DEBITEURS_PAR_NATURE = ['531','512','601']`, `COMPTES_CREDITEURS_PAR_NATURE = ['701','401']`) — et son propre commentaire hésite sur 411 (« Clients, mais suivi côté client = actif, donc débiteur en réalité »). Le §2 de ce document est ambigu de la même façon : il range les classes **4 et 5 des deux côtés**.

`CompteComptable.estDebiteurParNature` (BR-CPT-007) tranche pour **tous** les comptes du plan : classes 2/3/6 débitrices, 1/7 créditrices, et pour 4/5 arbitrage sur le numéro (411 débiteur ; 419, 40x, 42x, 43x, 44x créditeurs ; classe 5 débitrice). Cette règle est testée.

### 10.8 Le Grand Livre filtré par période exigeait un report d'ouverture

Le prototype ne filtre pas réellement : ses bornes de date sont câblées à l'affichage sans effet sur le solde d'ouverture. Restreindre la période sans reporter les écritures antérieures donnerait une colonne « Solde Progressif » fausse dès la première ligne.

Implémenté : `soldeOuvertureCompte` = reports des exercices antérieurs **+** écritures de l'exercice antérieures à la date de début. Par ailleurs la recherche plein texte **masque des lignes sans altérer les totaux ni le solde final** — les KPI annoncent « Période », pas « lignes affichées ». Les deux comportements sont couverts par des tests. Une ligne « Report — solde d'ouverture » ouvre le tableau : sans elle, la première valeur du solde progressif sortirait de nulle part.

### 10.9 Notes Annexes — 3 notes calculées, 2 rédigées

Les notes 2 (Immobilisations), 3 (Stocks) et 4 (Créances et Dettes) sont **calculées depuis la Balance**, pas saisies : une annexe saisie à la main peut contredire le bilan qu'elle commente. Les notes 1 (Méthodes Comptables) et 5 (Engagements Hors Bilan) sont rédactionnelles, pré-remplies avec le texte du prototype et persistées par exercice dans `NOTES_ANNEXES`.

**Non repris** : l'« Ancienneté » des créances (« 12 jours », « Urgent ») de la note 4. Elle se calcule sur les échéances client du module Ventes, pas sur des soldes comptables agrégés ; le suivi client par client existe déjà sur l'écran Clients & Créances, vers lequel la note renvoie.

### 10.10 Le contrôle TAFIRE ↔ Bilan était annoncé mais jamais fait

`etats-financiers.html` affiche la phrase « La Trésorerie à la Clôture doit être égale à la Trésorerie-Actif du Bilan — vérification automatique ci-dessous » suivie d'un `<div id="tafire-verif">` que son script ne remplit jamais. La vérification est réellement effectuée : `tafire.tresorerieCloture` contre `soldes.debiteursParClasse('5')`, avec le montant de l'écart affiché en cas d'incohérence.

### 10.11 La clôture périodique n'a aucun écran dans le prototype

`cloture-exercice.html` ne traite que la clôture **annuelle**. Le §6 ci-dessus et BR-CPT-006 imposent pourtant un double verrouillage exercice + mois, et `CLOTURES_PERIODIQUES` existe pour cela. Sans écran, le verrou mensuel serait du code mort et la déclôture réservée à `admin` inaccessible.

La grille des 12 mois de l'écran Clôture est donc **pilotée par la règle métier, pas par le prototype** — signalée comme telle dans le code. Le double verrouillage est appliqué dans la **couche de persistance** (`_verifierVerrouillage`), pas seulement dans l'interface : une écriture automatique générée par une vente antidatée passe par le même chemin et obéit à la même règle. Testé.

L'assistant de clôture en 3 étapes du prototype est conservé, mais ses étapes ne sont plus des cases à cocher décoratives (`markCloturStep()` ne faisait que masquer un bouton) : l'étape 1 se valide quand les 12 mois sont clôturés, l'étape 2 quand la balance est équilibrée et affiche le résultat réellement calculé, l'étape 3 porte le bouton de clôture, désactivé tant que la balance est déséquilibrée (BR-CPT-004).

### 10.12 Correction du croquis de code du §5

Le §5 esquisse `CalculerResultatNetUseCase.executer(int exerciceAnnee) async → Future<double>`. L'implémentation réelle est **synchrone et pure** : `CalculerResultatNet.calculer(SoldesComptes) → double`, les écritures étant déjà chargées par le ViewModel partagé. Le principe posé par BR-CPT-005 — une source unique réutilisée par le Bilan, le Compte de Résultat et le TAFIRE — est respecté à la lettre et vérifié par un test dédié qui compare les trois états.

### 10.13 Pièces jointes et exports PDF — non implémentés, signalés

- Le champ « Reçu / Facture (Photo) » de `saisie-depenses.html` n'est pas repris : Doc D1 ne comporte aucun champ de pièce jointe et l'application ne stocke aucun fichier. Une zone de dépôt qui n'enregistre rien serait décorative (Master Prompt §2.3). L'écran l'explique et invite à reporter le numéro de reçu dans le libellé.
- Les boutons « Exporter PDF » des 6 écrans du module sont omis tant que **Doc E9 (Impression & PDF)** n'est pas implémenté — même traitement que sur les modules F2 à F5.
- Le sélecteur « Consultation Historique » de `cloture-exercice.html` est remplacé par le sélecteur d'exercice présent en en-tête de tous les écrans du module : le prototype le laissait `disabled` avec la mention « Aucun exercice clôturé pour le moment ». Ici la bascule fonctionne réellement, sur tous les exercices ouverts par les clôtures successives.

### 10.14 Numérotation des pièces

Le prototype code ses numéros en dur (`'OD-2026-0' + (143 + n)`). La séquence est ici déduite des pièces réellement enregistrées sur l'exercice : `OD-<année>-NNNN` pour les opérations diverses, `DEP-<année>-NNNN` pour les dépenses. Deux pièces ne peuvent pas porter le même numéro et la numérotation repart à 1 sur un nouvel exercice.

### 10.15 Suppression d'une pièce, pas d'une ligne

Une dépense ou une opération diverse est équilibrée sur 2 lignes. Supprimer une seule ligne déséquilibrerait la balance : `supprimerPiece()` supprime **toutes** les lignes du même `numeroPiece`, dans une transaction, après contrôle du double verrouillage. Une pièce portant un `venteRef` ou un `achatRef` est refusée — il faut annuler l'opération d'origine, qui contrepasse (BR-CPT-003). Testé.

### 10.16 Modification d'un compte — le numéro est immuable

`plan-comptable.html` propose un bouton « Modifier » qui laisse changer le numéro. Le numéro est la clé étrangère de toutes les écritures déjà passées : le renommer les orphelinerait. Il est donc en lecture seule en modification, et **changer la classe d'un compte déjà mouvementé est refusé** — cela déplacerait rétroactivement ses écritures d'un poste du bilan à un autre. Testé.

L'action « archive » du prototype est conservée telle quelle, mais rendue réversible et explicite : un compte archivé disparaît de la saisie sans que ses écritures quittent le Journal, le Grand Livre ou la Balance.

### 10.17 Où sont passées les dépenses ?

Le prototype stocke ses dépenses dans un tableau `DEPENSES` **séparé** du tableau `JOURNAL` — d'où leur désynchronisation permanente : les 27 000 F de charges diverses de `saisie-depenses.html` n'apparaissent nulle part dans `journal-comptable.html`.

Ici une dépense **n'est pas une entité** : c'est une pièce comptable, reconstruite à l'affichage depuis ses écritures (ligne au débit d'un compte de classe 6, sans `achatRef`). Le critère est structurel, pas une convention de libellé — un achat d'intrant, qui débite lui aussi un compte de classe 6 mais porte un `achatRef`, n'apparaît volontairement pas sur cet écran pour ne pas doubler ce que tient déjà Achats & Commandes. Testé dans les deux sens.

### 10.18 État de vérification

| Contrôle | Résultat |
|---|---|
| `flutter analyze` | **0 problème** |
| `flutter test` | **281 tests, 281 réussis** (dont 31 moteur comptable + 21 ViewModel/écrans F6) |
| `flutter build windows --debug` | compilé |
| Lancement réel + migration v11 | base existante conservée, plan complété de 15 à 19 comptes, aucune donnée perdue |
| Liens morts (`EcranAVenir`) sur le module | **aucun** — les 9 routes résolvent vers un écran réel |

### 10.19 Le Bilan de l'Entreprise avait été supprimé à tort — écran rétabli

**Demandé par la Gérante après la recette K2.**

Le §1 de ce document fondait la suppression de `bilan-entreprise.html` sur le commentaire du prototype lui-même — `comptabilite-hub.html` l.140 : *« CORRECTIF : remplace bilan-entreprise.html — page unifiée des 4 états »*. L'écran avait donc été absorbé dans l'onglet « Bilan » des États Financiers.

C'était une erreur d'analyse. Les deux écrans portent les mêmes chiffres, pas la même question.

| | États Financiers → onglet Bilan | Bilan de l'Entreprise |
|---|---|---|
| Destinataire | le comptable, l'administration fiscale | la Gérante |
| Structure | rubriques SYSCOHADA, Actif Immobilisé / Circulant / Trésorerie, sous-totaux | **7 lignes**, une par compte réellement mouvementé |
| Question | « mes états sont-ils conformes ? » | « **qu'est-ce que je possède, qu'est-ce que je dois ?** » |

Confondre l'information et sa présentation revenait à supprimer le seul des deux que la Gérante ouvre.

#### Les 7 postes, tels que le prototype les nomme

| ACTIF | Compte | | PASSIF | Compte |
|---|---|---|---|---|
| Stocks (Intrants + Marchandises) | 31/32 | | Capital Initial | 101 |
| Clients (Solde Restant Dû) | 411 | | Résultat de l'Exercice | 13 |
| Banques — Mobile Money | 512 | | Fournisseurs (Dettes) | 401 |
| Caisse | 531 | | | |

Le Résultat de l'Exercice n'est **pas** lu sur un compte 13 : il vient de `CalculerResultatNet`, comme partout ailleurs dans le module. Un test vérifie que les deux bilans annoncent le même — c'est BR-CPT-005.

#### ⚠️ Le Capital Initial du prototype est une variable d'ajustement — non reproduit

`bilan-entreprise.html` l.14 :

```js
var capitalInitial = totalActif - dettesFournisseurs - resultatNet;
```

Le capital n'est pas lu, il est **déduit de ce qu'il faut pour que l'égalité tombe juste**. Le bandeau vert « Bilan équilibré — Total Actif = Total Passif » qui suit ne vérifie donc rien : il ne peut pas être rouge. C'est le pattern `validateSale()` que le Cahier des Charges §2.3 interdit, transposé à un contrôle comptable.

Le capital est ici lu au compte 101, comme tout autre poste. Trois conséquences assumées :

1. Sans apport saisi au 101, l'actif dépasse le passif ;
2. l'écart est affiché **sur sa propre ligne, en rouge**, au lieu d'être fondu dans le capital ;
3. le bandeau devient un vrai contrôle et distingue **trois** états — vide, équilibré, en écart.

L'écart n'est pas une anomalie de calcul : c'est de l'argent dont l'origine n'a pas été enregistrée. Le bandeau nomme la cause et l'action — saisir l'apport au compte 101 depuis le Journal Comptable — et distingue les deux sens : un actif excédentaire signale un apport manquant, un passif excédentaire une contrepartie oubliée. Cinq tests couvrent ces cas.

#### Accès

Trois entrées, conformément à la demande : la **tuile** du hub Comptabilité (rétablie à la place qu'elle occupait avant le CORRECTIF), l'**Accès Rapide** flottant, et la **barre latérale**, en fin de rubrique COMPTABILITÉ. Route `/comptabilite/bilan`, écran `BilanEntrepriseScreen`, export PDF par le générateur unique de Doc E9.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **433 tests au vert** dont 9 dédiés à cet écran · build compilé, application relancée · schéma inchangé par cet écran — il ne fait que lire `ECRITURE_COMPTABLE`.

## Finalisation — Rapports, Saisie Dépenses, Balance Générale

Les trois écrans existaient ; il leur manquait à chacun un geste que le prototype propose.

### Rapports & États — colonne Actions des créances

`rapports-exports.html` l.640-641 place deux icônes sur chaque ligne de créance :

| Icône | Action du prototype | Ici |
|---|---|---|
| `mail` | `exportLettreRelance(client, solde, facture)` | **branchée** sur `DocumentsCommercial.lettreRelance` |
| `payments` | `window.location.href = 'relances-clients.html'` | navigation vers `/clients` |

⚠️ **La lettre de relance était déjà écrite** — reprise mot pour mot dans `DocumentsCommercial` lors du portage de Doc E9 — mais **branchée nulle part**. Un document complet sans porte d'entrée : personne ne pouvait l'imprimer.

Le second bouton reste une **navigation**, pas une action. L'encaissement se saisit dans Clients & Créances, qui tient le suivi du solde et passe l'écriture comptable. Le dupliquer dans les Rapports créerait un second chemin d'encaissement, donc un risque de double règlement sur la même facture.

Un `IconeExportPdf` a été ajouté au socle : même en-tête officielle et même générateur unique que `BoutonExportPdf`, au format d'une cellule de tableau.

### Saisie Dépenses — modification d'une dépense

`editExpense()` (l.344) manquait : seule la suppression était portée. Corriger une dépense obligeait donc à la supprimer puis à la ressaisir — et à lui donner un **nouveau numéro de pièce**, alors que l'ancien figure sur le reçu papier déjà classé.

La modale est la même, préremplie, et son bouton devient « Mettre à Jour la Dépense » comme dans le prototype.

**`remplacerPiece()` est ajouté au repository, en une seule transaction.** Enchaîner `supprimerPiece` puis `enregistrerPiece` laisserait, si la seconde échoue, une pièce disparue et une charge évaporée du Compte de Résultat. Le numéro de pièce est **conservé**.

Trois garde-fous, tous testés :

- les mêmes contrôles que la saisie s'appliquent — partie double ligne à ligne, puis équilibre du lot : une modification ne peut pas produire une pièce déséquilibrée (BR-CPT-001) ;
- **les deux dates** sont vérifiées contre le verrouillage périodique — l'ancienne, parce qu'on retire une écriture de sa période, et la nouvelle, parce qu'on en dépose une ;
- une pièce générée par une vente ou un achat reste **immodifiable** : c'est l'opération d'origine qu'il faut corriger.

### Balance Générale — sélecteur de période

`bal-periode-select` (l.67) offre « Mois en cours — Août 2026 » et « Exercice complet — 2026 ». Il manquait : la balance couvrait toujours l'exercice entier.

Ce n'est pas un filtre d'affichage. Le format 6 colonnes distingue **Solde Ouverture / Mouvements Période / Solde Final** : restreindre la période **déplace la frontière** entre les deux premières. En mois courant, tout ce qui précède le 1ᵉʳ du mois — exercices antérieurs compris — bascule dans l'ouverture. Se contenter de masquer les lignes hors période donnerait un solde final faux.

Un test vérifie l'invariant qui justifie ce format : **le solde final est identique dans les deux périmètres**, seule la répartition change. Le périmètre retenu est imprimé sur le PDF — deux balances du même exercice n'ont pas les mêmes soldes d'ouverture selon qu'elles couvrent le mois ou l'année.

Sur un exercice passé, « mois en cours » n'a pas de sens : décembre est retenu, dernier mois de cet exercice.

### Saisie des Dépenses — l'écran était cassé, refait d'après le HTML

Signalé par la Gérante. Deux défauts, l'un visible, l'autre structurel.

#### 1. Une exception de rendu à chaque affichage

Les trois cartes KPI dessinaient leur liseré d'accent avec un `Container(width: 4)` placé dans un `Row(crossAxisAlignment: stretch)`. Dans une colonne défilante la hauteur disponible est **infinie** : `stretch` réclamait donc une hauteur infinie, et Flutter levait `BoxConstraints forces an infinite height` **à chaque rendu**. C'est ce qui cassait l'écran.

`border-l-4` du prototype est littéralement une bordure gauche, mais Flutter refuse un `borderRadius` sur une bordure de couleurs non uniformes. Le liseré est donc peint dans un `Stack` : le `Positioned` s'étire sur la hauteur que le contenu impose, bornée par construction.

**Le même défaut existait sur les cartes KPI des Rapports** (`CarteKpiRapport`) : corrigé aussi.

#### 2. Le formulaire n'était pas au bon endroit

`saisie-depenses.html` **pose le formulaire sur la page**, entre les KPI et la barre de filtres :

```html
<div class="bg-white rounded-lg border border-outline-variant shadow-sm p-lg mb-lg">
  <h3>Nouvelle Dépense</h3>
  <p class="text-xs text-outline mb-md">Enregistrez une charge d'exploitation…</p>
  <form class="grid grid-cols-1 md:grid-cols-2 gap-md">…</form>
</div>
```

Il avait été porté en **modale**, ouverte par un bouton de l'en-tête. Ce n'est pas un détail de présentation : la saisie des dépenses est un écran de **saisie répétitive**. La Gérante enregistre plusieurs charges à la suite et voit la liste se remplir. Une modale impose un clic d'ouverture par dépense et masque le tableau pendant la saisie.

C'est aussi ce qui rend `editExpense()` cohérent : le prototype ne rouvre rien, il **remplit ce formulaire-ci** et y fait défiler la page — d'où le bouton qui devient « Mettre à Jour la Dépense ». Le défilement est reproduit (`scrollIntoView`), et un bouton « Annuler la modification » permet de ressortir du mode édition.

#### Layout rétabli, dans l'ordre du prototype

| Bloc | Détail |
|---|---|
| 3 KPI | Dépenses du Mois (navy), Charges Fixes (or), Charges Variables (vert) |
| Carte « Nouvelle Dépense » | grille **2 colonnes** (`md:grid-cols-2`), 6 champs en `h-11`, bouton aligné à droite sur toute la largeur |
| Barre de filtres | **carte à part entière** — recherche, statut, Réinitialiser, et l'export PDF poussé à droite (`ml-auto`) |
| Tableau | Date, Libellé, Catégorie, Montant, Statut, Actions |

La zone « Reçu / Facture (Photo) » est **conservée** — elle fait partie du layout — mais elle dit qu'aucun fichier n'est stocké au lieu de simuler un dépôt. Le champ « Compte de Trésorerie » garde sa correction : le prototype écrit « Débité », or la trésorerie est **créditée** lors d'une dépense.

Huit tests de widget vérifient la structure : les 6 champs visibles sans aucun clic, l'absence de dialogue, et l'ordre KPI → formulaire → filtres → tableau.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **493 tests au vert** · build **release** compilé, packagé et **lancé**.

## Axe analytique — la marge par filière était incalculable

### Ce qui limitait la Comptabilité Analytique

Sans axe, la ventilation ne pouvait reposer que sur ce que le **numéro de compte** laisse deviner : 601 et 622 pour l'avicole, 602 pour le commerce annexe. Deux conséquences :

1. Une facture d'électricité (628), un transport (624) ou une assurance (616) restait en « charges non affectées » — la marge par filière était **incomplète**.
2. Tout l'avicole formait **un seul bloc**, alors que `comptabilite-analytique.html` l.146-149 ventile bien **Goliaths**, **Pintades** et **Commerce Annexe** séparément.

### `ECRITURE_COMPTABLE.axeAnalytique` — v19

Une colonne texte nullable, portée par la **ligne** d'écriture. C'est ce qui permet à la Comptabilité Analytique de ventiler **sans jamais lire les tables de l'élevage ou du commerce** : le contexte Comptabilité reste fermé (Doc C1 §7).

| Origine | Comment l'axe est renseigné |
|---|---|
| Vente | automatiquement, depuis `PRODUITS_VENDABLES.espece` — une ligne 701 par filière |
| Annulation de vente | la contrepassation porte **le même axe** que l'écriture d'origine |
| Dépense | sélecteur « Centre analytique (facultatif) » à la saisie |

Seule la ligne de **charge** porte le centre : la contrepartie de trésorerie n'appartient à aucune filière.

### Deux sources, dans un ordre strict

1. L'**axe** quand il est renseigné — imputation explicite, elle prime toujours ;
2. à défaut, l'**heuristique du numéro de compte**, exactement comme avant la v19.

Une ligne comptée par l'axe n'est **jamais recomptée** par l'heuristique. Un test le vérifie sur un compte 622 imputé aux Pintades : sans cette règle, les 2 000 F pèseraient à la fois sur les Pintades et sur l'avicole non précisé.

### Rien n'est réparti au prorata

Les charges de structure — électricité, transport, assurances — servent toute l'exploitation. Elles restent affichées **à part**, jamais ventilées selon une clé. Une clé de répartition que personne n'a fixée produirait des marges par filière fausses **avec l'air d'être exactes**.

De même, l'avicole non imputé forme son propre centre — « **Avicole — filière non précisée** » — plutôt que d'être réparti entre Goliaths et Pintades au jugé.

### L'invariant qui garantit que rien ne se perd

```
Σ marges + produits non affectés − charges non affectées = Résultat Net
```

`produitsNonAffectes` a été ajouté pour cela : sans lui, l'égalité serait fausse dès la première subvention (75) ou produit financier (77) encaissé. Deux tests la vérifient, dont un après imputation partielle.

### Les écritures antérieures ne sont pas réimputées

Elles restent à `null` et retombent sur l'heuristique, exactement comme avant. Deviner où une ancienne facture d'électricité aurait dû s'imputer serait de l'invention.

**Vérification** : `flutter analyze` 0 problème · `flutter test` **534 tests au vert** · build **release** compilé, packagé et lancé · migration **v18 → v19**.
