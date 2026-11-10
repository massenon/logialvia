# 47c — Comptabilité SYSCOHADA : report à nouveau, clôture, parité web ↔ poste

> Rôle tenu : expert-comptable SYSCOHADA révisé (Acte uniforme OHADA relatif au droit comptable et à l'information
> financière, révisé 2017, applicable depuis le 1ᵉʳ janvier 2018). Le Dart est la source ; le web s'y conforme.
> Code : `logialvia_app/lib/comptabilite/domain/services/report_a_nouveau.dart` (source),
> `logialvia_laravel/app/Services/Comptabilite/ReportANouveau.php` (port fidèle).

## 1. Le problème (doute majeur de `46d_` D11, `46f_`)

Avant ce lot, le Dart :

- **ne cumulait pas l'ouverture** : bilan, compte de résultat et TAFIRE lisaient les écritures de l'exercice seul, alors que
  le TAFIRE soustrayait l'ouverture. Dès qu'un exercice antérieur existait, l'écran « Flux de Trésorerie » affichait
  « Incohérence de 133 000 FCFA » sur le jeu commun ;
- **ne générait aucune écriture de report à nouveau** : le doc J1 §1.4 les prévoit, aucun code ne les écrivait, alors que
  l'étape 3 de l'assistant de clôture les annonçait ;
- calculait le résultat net sans la classe 8.

## 2. Règles retenues (avec leur référence SYSCOHADA)

| # | Règle | Référence |
|---|---|---|
| R1 | **Résultat net** = produits − charges des classes **6, 7 et 8** (HAO, participation, impôt sur le résultat compris). | Plan comptable SYSCOHADA : classes 6 charges des AO, 7 produits des AO, 8 autres charges et produits (HAO) ; comptes 81 à 89 |
| R2 | À la clôture de N, **solde des comptes de gestion** : pièce `CL-N-RESULTAT` (journal `CL`, au 31/12/N) crédite les charges, débite les produits, et porte le résultat au **131** (bénéfice, créditeur) ou **139** (perte, débiteur). | Classe 13 « Résultat net de l'exercice » ; mécanique de la balance de clôture |
| R3 | **Affectation** : pièce `CL-N-AFFECTATION`. Bénéfice : 131 soldé au profit de **111** (réserve légale), **118** (autres réserves), **465** (associés, dividendes à payer) et du **121** (report à nouveau créditeur, le reste). Perte : 139 soldé au débit du **129** (report à nouveau débiteur). | Comptes 11 (réserves), 12 (report à nouveau : 121 solde créditeur, 129 solde débiteur), 465 ; AUSCGIE sur l'affectation du résultat |
| R4 | **À-nouveaux** : pièce `AN-(N+1)` (journal `AN`, au 01/01/N+1) = soldes des comptes de **classes 1 à 5** après affectation, chacun gardant son sens. **Jamais** de classe 6, 7 ni 8 : ils sont nuls après R2. | Principe de continuité : le bilan d'ouverture reprend le bilan de clôture |
| R5 | **États de N « avant affectation »** : bilan, compte de résultat et TAFIRE ignorent les écritures `CL` (sinon le résultat disparaîtrait de son propre compte de résultat). La **balance** et le **grand livre** lisent le livre complet (un compte de gestion y est soldé). | Le bilan SYSCOHADA se présente avant ou après affectation ; on retient « avant » pour N |
| R6 | **États de N+1** : ouverture (les `AN`) **cumulée** aux mouvements. Trésorerie d'ouverture du TAFIRE = Σ des soldes 5xx reportés. | Continuité des exercices |
| R7 | **Ouverture sans à-nouveaux** (N−1 non clôturé, ou clôturé avant ce code) : **clôture virtuelle** de N−1, résultat porté au 121 (bénéfice) ou 129 (perte). Elle ne s'écrit nulle part. | — |
| R8 | **Contrôles** : balance équilibrée (débit = crédit) avant toute clôture ; à-nouveaux équilibrés ; comptes présents au plan ; affectation cohérente (≥ 0, ≤ bénéfice, aucun dividende sur une perte, aucun dividende tant que le bénéfice n'absorbe pas un 129 antérieur). Sinon la clôture est **refusée**, rien n'est écrit. | BR-CPT-004 (F6 §3) |
| R9 | **Idempotence** : pièces et lignes ont des identifiants **déterministes** (`piece:cloture:N:resultat`, `piece:an:N+1`, `ligne:<clé>:<compte>`). Clôturer deux fois, rejouer le fait de clôture, ou recevoir du serveur une pièce déjà écrite ne duplique rien. | — |
| R10 | **Réouverture** (administratrice, `close-fiscal-year`) : retire les `CL` de N et les `AN` de N+1, déverrouille N. Refusée si N+1 est clôturé. Au poste : refusée aussi quand le serveur a accepté la clôture (fait partagé) — il faut alors rouvrir depuis le serveur (web), que les postes suivent. Tracée à l'audit. | — |

## 3. Architecture (couches)

### Poste (Dart)

- `ReportANouveau` : fonction **pure** (aperçu = écriture) ; `soldesOuverture`, `soldesDeFin`, `calculer`.
- `PiecesClotureDrift` : écrit/retire les pièces `CL`/`AN`. Lignes créées `synced` : **jamais envoyées** (dérivées).
- `ComptabiliteRepositoryDrift.cloturerExercice(annee, affectation)`, `rouvrirExercice`, `chargerAffectation`, `rouvrirLocalement`.
- Schéma **v44** : colonne `exercice_comptable.affectation` (JSON `{reserve_legale, autres_reserves, dividendes}`), migration
  idempotente (`_ajouterColonne` + prise en compte dans le rebuild v41).
- Synchronisation : le fait `clotures_exercice` porte `affectation` ; le poste accepte les journaux `AN`/`CL` **reçus**
  du serveur ; une clôture refusée rouvre l'exercice et retire `CL`/`AN` ; une **réouverture serveur** (`rouvert_le`) est suivie.
- Écran de clôture : assistant en **4 étapes** (inventaire · solde des classes 6-8 · affectation · à-nouveaux), modale avec
  saisie de l'affectation et aperçu, bouton « Rouvrir l'exercice », journaux `AN`/`CL` filtrables et non modifiables.
- `rapports` : les `CL`/`AN` sont exclus des recettes/dépenses et des mouvements de trésorerie.

### Serveur (Laravel)

- `ReportANouveau` (port), migration `2026_11_09_153000_add_report_a_nouveau_to_exercices.php` : `clotures_exercice.affectation`,
  `exercices_comptables.affectation` et `rouvert_le`.
- `ClotureExerciceTable::absorber` : droit `close-fiscal-year`, balance équilibrée, ordre des exercices, **génère lui-même** `CL`
  et `AN` depuis SON livre (mêmes identifiants que le poste), refuse avec motif si affectation ou à-nouveaux incohérents.
  `rouvrir()` : droit `close-fiscal-year`, retire les écritures dérivées, date `rouvert_le`.
- `EcrituresTable` : les journaux `CL`/`AN` ne sont **jamais acceptés d'un poste** ; seul le serveur les écrit (`pourCloture()`,
  droit `close-fiscal-year`, verrou mensuel levé pour le 31/12 et le 01/01).
- Le serveur sert `CL`/`AN` aux autres postes comme n'importe quelle pièce.

### Web (Livewire)

- Tous les écrans lisent via `ReportANouveau` (ouverture cumulée) : états, balance, grand livre, bilan de l'entreprise, hub.
- Clôture : même assistant 4 étapes, modale d'affectation, réouverture. Exports XLSX et vues imprimables (voir §6).

## 4. Erreurs d'expert trouvées et corrigées (poste ET web)

| # | Erreur | Correction | Test chiffré (calcul à la main) |
|---|---|---|---|
| E1 | Bilan, résultat, TAFIRE sans ouverture | R6/R7 | jeu 2024 : bilan 2025 = 1 750 000 des deux côtés |
| E2 | Aucun report à nouveau | R2-R4 | à-nouveaux 1 550 000 = 1 550 000 |
| E3 | Résultat net sans classe 8 | R1 | 891 de 75 000 : résultat 300 000 → 225 000 |
| E4 | **Bilan déséquilibré dès un amortissement** : comptes 28-29 omis de l'actif, 25 omis, 14-15 et 13 omis du passif | postes ajoutés | TAFIRE avec amortissement 30 000 : bilan équilibré |
| E5 | **TAFIRE faux** : le financement soustrayait le résultat (jamais inscrit en classe 1 avant clôture) ; les dotations comptées deux fois (exploitation et investissement) ; comparé à la seule Trésorerie-Actif | construction à identité exacte : ouverture + flux = clôture nette | jeu commun : financement **500 000** (l'apport) et non 267 000 ; clôture 545 000 = trésorerie nette |
| E6 | **Bilan de l'Entreprise** sans immobilisations, ni réserves/report, ni emprunts, ni autres dettes : « Écart −200 000 » sur le jeu commun = l'immobilisation 231 absente de l'écran | lignes ajoutées | jeu commun : 775 000 = 775 000, écart 0 |
| E7 | Cascade du compte de résultat incomplète (63, 603-608, 69, 71-74, 78-79, HAO 81-86/88 absents ; 78 pris pour des produits HAO) : la fin de cascade pouvait différer du résultat net | postes complets | résultat 133 000 inchangé sur le jeu |
| E8 | Sens naturel faux : 129/139 (débiteurs), 28/29/39/49/56/59 (créditeurs) | `estDebiteurParNature` | grand livre |
| E9 | Rapports (recettes/dépenses, mouvements de trésorerie) auraient compté `CL`/`AN` | filtre de journaux | — |
| E10 | Pourcentage/écran « Flux de Trésorerie » : « Incohérence » permanente dès un exercice antérieur | E1 + E5 | jeu commun : aucune incohérence |

## 5. Décisions à valider par le client

| # | Décision | Alternative |
|---|---|---|
| V1 | Comptes de résultat : **131** bénéfice / **139** perte (déjà semé et affiché par l'assistant). | 132 pour la perte (variante du plan révisé) |
| V2 | Dividendes à payer au **465** dès l'affectation, réserve légale **111**, autres réserves **118** : l'affectation est décidée **à la clôture** (écran) ; en droit, elle l'est par l'Assemblée en N+1. | Écrire le 131 dans les à-nouveaux et affecter par OD en N+1 |
| V3 | **Réserve légale** : aucune obligation codée (10 % du bénéfice jusqu'à 20 % du capital pour les SARL/SA, AUSCGIE art. 346) : la forme juridique n'est pas connue. | Imposer 10 % |
| V4 | États de N « avant affectation » (R5). | Bilan après affectation |
| V5 | La **réouverture** d'un exercice transmis se fait au serveur (web) et les postes la suivent (`rouvert_le`) ; le poste ne la fait seul que si la clôture n'est pas acceptée. | Interdire toute réouverture (BR-CPT-001 stricte) |
| V6 | Un **report à nouveau débiteur** (129) n'est pas compensé automatiquement par un 121 existant ; le bilan les additionne. | Compensation à l'affectation |

## 6. Parité web ↔ poste

| Écran du poste | Web | Statut |
|---|---|---|
| Journal (saisie OD, annulation, filtres, recherche) | `Journal` | complet ; modification → annulation (pièce transmise = fait immuable, D1 de `46d_`) ; journaux `AN`/`CL` en lecture seule |
| Grand livre (période, recherche) | `GrandLivre` | complet, ouverture cumulée |
| Balance (exercice / mois) | `BalanceGenerale` | complet, ouverture = à-nouveaux |
| Plan comptable (créer, modifier, archiver) | `PlanComptableEcran` | complet (demandes au serveur) |
| Analytique | `Analytique` | complet |
| États financiers (bilan, résultat, TAFIRE, notes) | `EtatsFinanciers` | complet ; notes 2-4 calculées |
| Bilan de l'entreprise | `BilanEntreprise` | complet |
| Clôture mensuelle (clore / déclore) | `Cloture` | complet |
| Assistant de clôture annuelle (4 étapes) + réouverture | `Cloture` | **complet** (ce lot) |
| Saisie de dépenses | `Depenses` | complet ; **pas de pièce justificative** au web |
| Exports | XLSX (« Exporter ») sur journal, grand livre, balance, plan, dépenses, analytique, états, bilan ; vue imprimable (« Imprimer / PDF », `@media print`) sur tous les écrans | `view-comptabilite` vérifié dans chaque méthode ; **le PDF généré du poste n'est pas reproduit** (déclaré à l'écran) |

## 7. Écarts et limites

- **Numérotation du plan comptable non conforme au plan SYSCOHADA révisé** (héritée du prototype, **non modifiée** : elle est
  codée dans les écritures automatiques, les rapports et l'historique de tous les postes ; la renuméroter exige une migration
  coordonnée poste + serveur) : 601 « Achats de matières » / 602 « Achats de marchandises » sont **inversés** (SYSCOHADA :
  601 marchandises, 602 matières premières) ; 701 « Ventes de produits avicoles » / 707 « Ventes de marchandises » aussi
  (SYSCOHADA : 701 marchandises, 702-706 produits fabriqués, 707 produits accessoires) ; **531 Caisse** (SYSCOHADA : 571) ;
  613 Locations / 616 Assurances / 624 Transports / 628 Charges diverses ne sont pas les numéros du plan (622 locations, 625
  assurances, 61x transports, 65x charges diverses) ; 622 « Frais vétérinaires » est une location au plan officiel. À arbitrer
  avant la première déclaration fiscale : proposer une table de correspondance et une migration d'écritures.
- **TVA collectée/déductible (443/445)** : les écritures automatiques de vente et d'achat ne séparent pas la TVA ; le résultat
  est donc calculé sur des montants TTC pour les ventes taxables. Hors périmètre (composants commerce/achats).
- Le TAFIRE reste **simplifié** (variation du BFR agrégée, pas de capacité d'autofinancement détaillée ni de cessions).
- Provisions pour dépréciation : seuls 28, 29, 39, 49 sont traités comme charges non décaissées.
- La clôture générée au serveur dépend du **livre du serveur** : un poste appairé doit être synchronisé avant de clôturer
  (déjà exigé).
- Les clôtures déjà faites avant ce lot n'ont pas d'à-nouveaux : l'ouverture suivante est reconstituée (R7) ; rouvrir puis
  reclôturer les écrit.
- Le web n'envoie pas de pièces justificatives pour les dépenses.
