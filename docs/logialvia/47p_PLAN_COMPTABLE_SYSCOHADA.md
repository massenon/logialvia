# 47p — Plan comptable SYSCOHADA révisé : numérotation officielle, TVA ventilée, migration coordonnée

> Rôle tenu : expert-comptable OHADA, SYSCOHADA révisé (Acte uniforme relatif au droit comptable et à l'information
> financière, 2017, en vigueur le 1ᵉʳ janvier 2018). Le Dart est la source ; le web s'y conforme.
> Code : `logialvia_app/lib/comptabilite/domain/plan_syscohada.dart` (poste, source),
> `logialvia_laravel/app/Support/PlanSyscohada.php` (web, port comparé au Dart par un test).

## 1. Source du plan : ce qui a été (et n'a pas été) obtenu

**Le texte officiel de l'OHADA n'a PAS pu être téléchargé.** Constat, le 2026-11-09 :

| Tentative | Résultat |
|---|---|
| `curl https://www.ohada.org/` depuis l'environnement de développement | échec de connexion (code 000) : le proxy de l'environnement n'autorise pas ce site |
| `WebFetch` d'un plan comptable SYSCOHADA public tiers : fichier `l10n_syscohada/data/template/account.account-syscohada.csv` du dépôt public Odoo, branche 17.0 (CSV, 131 369 caractères) | **lu** à travers un outil qui renvoie un résumé (les 100 000 premiers caractères, deux passes) ; le fichier brut n'a donc **pas pu être enregistré tel quel** |
| Téléchargement du même fichier par `curl` | refusé par le garde-fou de l'environnement (sortie du périmètre autorisé) ; **non retenté** |

Conséquences, dites sans détour :

1. **Rien n'est « téléchargé et vérifié contre le texte officiel ».** Les numéros et libellés du plan retenu sont
   **reconstitués de la connaissance du SYSCOHADA révisé** et **recoupés** avec le plan tiers ci-dessus (structure à 2, 3 et
   4 chiffres : 4431, 4432, 4441, 4449, 4451, 4452, 5711, 5712, 601x, 602x, 604x, 70xx dont 7071, 622x, 624x, 625x, 658x…).
   Ce plan tiers n'est **pas** le texte de l'OHADA : traduction automatique par endroits (« Produits de soins » pour
   « Produits d'entretien », « Abandon de créances convenu »…), libellés tronqués ou fautifs ; **il n'a servi qu'à
   confirmer la numérotation**, jamais à recopier un libellé douteux.
2. Le dossier `docs/logialvia/syscohada/` contient : `SOURCE.md` (URL, date, format, ce qui a été lu) et
   `plan_syscohada_revise_ferme.csv` (le plan retenu, marqué **« reconstitué, non vérifié contre le texte officiel »**).
3. **Décision à valider par l'expert-comptable (§9, V1)** : relire les 60 numéros/libellés contre le Journal officiel
   de l'OHADA avant la première déclaration fiscale. Les libellés sont isolés dans une seule liste (`PlanSyscohada.comptes`)
   ; en corriger un est une modification d'une ligne par côté (le test de conformité signale tout écart Dart ↔ web).

## 2. Plan applicable de la ferme

Sous-ensemble utile du plan officiel : capital 101, réserves 111/118, report à nouveau 121/129, résultat 131/139, emprunts
162, immobilisations 231-246 et amortissements 283-284, stocks 31/32/36, fournisseurs 401/409, clients 411/419, personnel
421/422, organismes sociaux 431, **État : 4431/4432 TVA facturée, 4441 TVA due, 4449 crédit de TVA, 4451/4452 TVA
récupérable**, dividendes 465, trésorerie 552 (monnaie électronique) / 571 (caisse), charges 601-681, produits 701-771.
La Gérante peut **ajouter des sous-comptes** (« Nouveau compte » du plan) : ils sont conservés et suivent leur compte lors de
la migration (§6). Le semis n'**ajoute** que les comptes absents et ne touche jamais un compte renommé ou archivé.

Classe 8 (HAO, participation, impôt sur le résultat) : **non semée**. Le plan synchronisé n'accepte que les classes 1 à 7
(`^[1-7]…`, côté poste et serveur) ; les comptes 81 à 89 restent calculés par le moteur (`CalculerResultatNet`) mais ne
peuvent pas être saisis (limite préexistante, §10).

| Numéro | Libellé (officiel, à valider) | Classe |
|---|---|---|
| 101 | Capital social | 1 |
| 111 | Réserve légale | 1 |
| 118 | Autres réserves | 1 |
| 121 | Report à nouveau créditeur | 1 |
| 129 | Report à nouveau débiteur | 1 |
| 131 | Résultat net de l'exercice : bénéfice | 1 |
| 139 | Résultat net de l'exercice : perte | 1 |
| 162 | Emprunts et dettes auprès des établissements de crédit | 1 |
| 231 | Bâtiments industriels, agricoles, administratifs et commerciaux sur sol propre | 2 |
| 242 | Matériel et outillage agricole | 2 |
| 244 | Matériel et mobilier | 2 |
| 245 | Matériel de transport | 2 |
| 246 | Immobilisations animales et agricoles | 2 |
| 283 | Amortissements des bâtiments, installations techniques et agencements | 2 |
| 284 | Amortissements du matériel | 2 |
| 31 | Marchandises | 3 |
| 32 | Matières premières et fournitures liées | 3 |
| 36 | Produits finis | 3 |
| 401 | Fournisseurs, dettes en compte | 4 |
| 409 | Fournisseurs débiteurs : avances et acomptes versés | 4 |
| 411 | Clients | 4 |
| 419 | Clients créditeurs, avances et acomptes reçus | 4 |
| 421 | Personnel, avances et acomptes | 4 |
| 422 | Personnel, rémunérations dues | 4 |
| 431 | Sécurité sociale | 4 |
| 4431 | TVA facturée sur ventes | 4 |
| 4432 | TVA facturée sur prestations de services | 4 |
| 4441 | État, TVA due | 4 |
| 4449 | État, crédit de TVA à reporter | 4 |
| 4451 | État, TVA récupérable sur immobilisations | 4 |
| 4452 | État, TVA récupérable sur achats | 4 |
| 465 | Associés, dividendes à payer | 4 |
| 552 | Monnaie électronique : téléphone portable | 5 |
| 571 | Caisse siège social | 5 |
| 601 | Achats de marchandises | 6 |
| 602 | Achats de matières premières et fournitures liées | 6 |
| 604 | Achats stockés de matières et fournitures consommables | 6 |
| 605 | Autres achats | 6 |
| 611 | Transports sur achats | 6 |
| 612 | Transports sur ventes | 6 |
| 618 | Autres frais de transport | 6 |
| 622 | Locations et charges locatives | 6 |
| 624 | Entretien, réparations et maintenance | 6 |
| 625 | Primes d'assurance | 6 |
| 628 | Frais de télécommunications | 6 |
| 631 | Frais bancaires | 6 |
| 632 | Rémunérations d'intermédiaires et de conseils | 6 |
| 641 | Impôts et taxes directs | 6 |
| 658 | Charges diverses | 6 |
| 661 | Rémunérations directes versées au personnel national | 6 |
| 664 | Charges sociales | 6 |
| 671 | Intérêts des emprunts | 6 |
| 681 | Dotations aux amortissements d'exploitation | 6 |
| 701 | Ventes de marchandises | 7 |
| 702 | Ventes de produits finis | 7 |
| 706 | Services vendus | 7 |
| 707 | Produits accessoires | 7 |
| 7071 | Ports, emballages perdus et autres frais facturés | 7 |
| 758 | Produits divers | 7 |
| 771 | Intérêts de prêts et créances diverses | 7 |

**Trésorerie : pourquoi 552 et pas 52x pour le Mobile Money.** L'ancien « 512 Banques — Mobile Money » n'est pas une banque :
le plan révisé ouvre le compte 55 « Instruments de monnaie électronique », 552 « téléphone portable ». C'est le seul numéro
officiel qui décrit réellement le compte. Un compte bancaire (521 « Banques locales ») s'ajoutera à la demande ; il n'est
**pas semé** pour ne pas afficher une ligne « 521 » à zéro à l'état de trésorerie (le libellé court de l'état ne connaît que
Caisse et Mobile Money).

## 3. Table de correspondance ancien → nouveau (complète, justifiée)

La table est appliquée aux comptes du plan, aux écritures (journaux ordinaires **et** `CL`/`AN`) et aux **sous-comptes**
(préfixe : `6011` sous l'ancien 601 devient `6021` sous le nouveau 602). Les autres comptes de l'ancien plan **gardent leur
numéro** (31, 32, 401, 411, 419, 101, 111, 118, 121, 129, 131, 139, 465) ; leur libellé passe à l'officiel s'il était encore
celui d'origine.

| Ancien | Libellé ancien | Nouveau | Libellé officiel | Justification |
|---|---|---|---|---|
| 531 | Caisse | **571** | Caisse siège social | 53 = chèques postaux/Trésor ; la caisse est le 57 |
| 512 | Banques — Mobile Money | **552** | Monnaie électronique : téléphone portable | cf. §2 |
| 601 | Achats de Matières (Intrants Provende) | **602** | Achats de matières premières et fournitures liées | provende = matière première consommée |
| 602 | Achats de Marchandises (Commerce Annexe) | **601** | Achats de marchandises | 601 = marchandises : **croisement 601↔602 corrigé** |
| 622 | Frais Vétérinaires | **604** | Achats stockés de matières et fournitures consommables | produits et soins vétérinaires = fournitures consommables ; 622 est la **location** au plan officiel |
| 613 | Locations | **622** | Locations et charges locatives | 613 = transports pour le compte de tiers |
| 616 | Assurances | **625** | Primes d'assurance | 616 = transports de plis |
| 624 | Transports | **618** | Autres frais de transport | 61 = transports ; 624 = entretien, réparations |
| 628 | Charges Diverses de Gestion | **658** | Charges diverses | 65 = autres charges ; 628 = télécommunications |
| 701 | Ventes de Produits Avicoles | **702** | Ventes de produits finis | animaux, œufs, poissons… = produits finis de l'exploitation (701 marchandises, 703 intermédiaires, 704 résiduels, 705 travaux, 706 services) |
| 707 (ligne de vente de marchandises : centre « Commerce Annexe ») | Ventes de Marchandises | **701** | Ventes de marchandises | revente en l'état = marchandises |
| 707 (ligne **sans centre** d'une pièce de vente : frais de livraison facturés) | idem (mal rangés) | **7071** | Ports, emballages perdus et autres frais facturés | 707 = produits accessoires, 7071 = frais facturés |

Choix tranchés (voir aussi §9) : les produits des filières vont en **702 (produits finis)**, jamais en 701 ; 703 (produits
intermédiaires), 704 (résiduels : fumier, plumes), 705 (travaux) et 706 (services) restent à ouvrir quand le métier les
vendra ; 72x (production immobilisée : reproducteurs élevés pour l'exploitation) n'est pas écrit automatiquement.

**Le piège du croisement.** 601↔602 et 613→622 (qui reprend le numéro de l'ancien 622, lui-même renuméroté en 604) :
toutes les lignes passent d'abord par des numéros temporaires `~M<n>`, puis aux numéros définitifs (§6).

## 4. TVA ventilée (Bénin : 18 %)

Les **prix du catalogue sont TTC**. Le taux vient du **groupe de taxe du produit** (`groupes_taxe` : A exonéré 0 %, B 18 %,
`facturation_mecef_tables.dart`, `CalculFacture`) — l'élevage reste exonéré par défaut (décision de la Gérante, `groupes_taxe_seeder`).

| Opération | Écriture |
|---|---|
| Vente (TTC = T, taux t) | trésorerie/clients **D T** ; produit **C (T − TVA)** ; **4431 TVA facturée sur ventes C TVA** |
| Frais de livraison facturés (TTC = L) | **7071 C (L − TVA)** ; **4432 TVA facturée sur prestations de services C TVA** |
| Achat (TTC = A, taux t) | charge **D (A − TVA)** ; **4452 TVA récupérable sur achats D TVA** ; trésorerie/fournisseur **C A** |
| Annulation d'une vente | écriture inverse, TVA comprise (poste : recalculée ; web : contrepasse ce que le livre porte) |
| Recouvrement / règlement | inchangé : 411/401 et trésorerie (la TVA a été facturée à la vente) |

- **Arrondi** : TVA = `round(TTC × t / (100 + t))` au franc (FCFA sans décimale), identique poste (`roundToDouble`) et web
  (`round`) ; un taux nul laisse le montant intact. Calculée par **ligne de ventilation** (compte, centre, taux). La TVA d'une
  facture e-MECeF est calculée ligne à ligne sans arrondi : un écart de **moins de 0,5 F par ligne de ventilation** est possible
  entre le journal et la facture imprimée (§10).
- **Taux de la livraison facturée** : celui du panier s'il est **unique**, sinon 0 (exonéré) — règle simple et déterministe,
  à valider (§9, V5).
- **Le résultat ne contient plus de TVA** : vente taxable 11 800 TTC − achat 5 900 TTC → produits 10 000 − charges 5 000 =
  **résultat 5 000** ; 4431 = −1 800 (dette), 4452 = +900 (créance), bilan équilibré (test chiffré poste **et** web).
- Pas d'écriture de **déclaration** (virement 4431/4452 → 4441/4449) : à passer en OD à la période (hors périmètre).
- Sens naturel corrigé : 4431/4441 créditeurs ; **4452, 4449, 409, 421 débiteurs** (jusqu'ici tout le 44 était créditeur).

## 5. Garde de version du plan (`plan_version`)

Risque : un poste non migré qui enverrait d'anciens numéros à un serveur migré serait **silencieusement mal comptabilisé**
(601/602 inversés, 531 inconnu mais 601/602/701/707 acceptés).

- Version courante : `PlanSyscohada.version = 2` (1 = ancien plan, jamais envoyé : absent).
- **Poste** : chaque pièce envoyée porte `plan_version` ; chaque demande de compte aussi. Le poste n'envoie ses écritures
  **qu'après sa migration** (la migration v48 s'exécute à l'ouverture de la base, avant toute synchronisation). Il **refuse**
  (compte comme refusée) toute pièce ou ligne de plan reçue sans la bonne version : serveur non migré ou autre plan.
- **Serveur** : `EcrituresTable::absorber` refuse **le lot (la pièce) entier** sans la bonne `plan_version`, avec le motif
  « Ce poste utilise l'ancien plan comptable : mettez-le à jour avant d'envoyer des écritures. » ; une demande de compte sans
  version reçoit « … avant de proposer un compte. ». Les pièces et lignes de plan **servies** portent `plan_version`.
  Les chemins internes du web (saisie, ventes, clôture) posent la version eux-mêmes.
- **Récupération** : à la migration du poste, ses pièces refusées pour cette raison (statut `conflict`, motif « ancien plan
  comptable ») repassent à `pending` et repartent renumérotées.
- Ordre de déploiement : **serveur d'abord**. Un poste migré qui parlerait à un serveur *pas encore* migré enverrait des
  numéros du nouveau plan à un serveur qui ignore la version (limite §10).

## 6. Migration de l'historique (coordonnée poste v48 + serveur `2026_11_09_160000`)

- **Poste** : bloc `if (from < 48)` de `app_database.dart` → `MigrationPlanSyscohada` ; **serveur** : migration
  `2026_11_09_160000_renumerote_plan_comptable_syscohada.php` → `RenumerotationPlan` (port fidèle).
- **Une transaction**, tout ou rien (test : coupure au milieu → base inchangée, puis la migration aboutit).
- **Idempotente / rejouable** : poste, marqueur `PRAGMA application_id` (= `0x41564C00 + version`, dans l'en-tête SQLite,
  donc recopié par une sauvegarde ; une table dédiée aurait obligé à regénérer `app_database.g.dart`, partagé entre agents) ;
  serveur, colonne `plan_comptable.plan_version` (ajoutée avant, passée à 2 **dans** la transaction, défaut 2 ensuite).
  Une base neuve est marquée migrée d'office.
- **Phases** : (A) lignes → numéros temporaires `~M<n>` (une règle par compte, frais de livraison avant la règle générale
  du 707) ; (B) numéros temporaires → définitifs, le plan reçoit la cible (libellé **personnalisé** de l'ancien compte reporté,
  y compris sur un sous-compte ; sinon libellé officiel ; archivage reporté) ; (C) anciens comptes sans objet retirés
  (531, 512, 613, 616…) ; (D) libellés d'origine → officiels, comptes officiels absents ajoutés.
- **Autres champs qui stockent un numéro** : demandes de plan en attente du poste (`demandes_referentiel`, clé et JSON
  renumérotés, version ajoutée) ; clôtures `CL`/`AN` (mêmes lignes : renumérotées avec le reste, UUID **inchangés** — leur
  identité de synchronisation reste stable). Notes annexes : texte libre, aucun numéro stocké. `exercice.affectation` : montants
  seulement. Le journal des demandes du serveur est un historique d'audit : **non réécrit**.
- **Vérification avant/après** (sinon exception, donc rollback) : nombre de lignes, débit total, crédit total, **solde de chaque
  compte** à la table près — l'attendu est recalculé ligne par ligne par `nouveauNumero`, **indépendante du SQL**.
- **Fusion** : si un numéro cible existe déjà (sous-compte créé à la main sous un numéro officiel), les écritures s'y
  fusionnent et la ligne de plan existante est gardée.

## 7. Où sont les numéros (aucun littéral dispersé)

Une classe par côté : `PlanSyscohada` (Dart) et `App\Support\PlanSyscohada` (PHP). Branchés : écritures automatiques de
vente/achat/règlement, moteur comptable (cascade du compte de résultat, bilan, TAFIRE, bilan de l'entreprise, analytique,
charges fixes, sens naturel), clôture (`ReportANouveau`/`ComptesCloture` retiré), rapports (centres de profit, libellés de
trésorerie), écrans (journal, dépenses, règlement, clôture), pilotage. `ConformitePlanSyscohadaDartTest` compare constantes,
plan, libellés anciens et table de correspondance Dart ↔ PHP **et** scanne le code des deux côtés : tout littéral entre
guillemets d'un ancien numéro est une régression. Les préfixes **structurels** de classe (`'28'`, `'39'`, `'60'`, `'44'`…) restent
littéraux : ils décrivent la structure du plan révisé, pas un compte de la ferme.

## 8. Tests (jeux chiffrés à la main, identiques poste et web)

| Test | Ce qu'il prouve |
|---|---|
| `migration_v48_plan_syscohada_test.dart` ↔ `MigrationPlanSyscohadaTest` | poste v47 migré ; balance identique à l'ancien numéro près (571 = 1 607 600 D / 40 000 C…), D = C = 2 037 600, 25 lignes ; croisements 601↔602, 613→622, sous-comptes 6011↔6021 ; 707 livraison → 7071 / marchandises → 701 ; libellés ; rejeu ; **interruption + reprise** ; demandes et pièces refusées ; **bilan 1 657 600 = 1 657 600, résultat 357 500, marge commerciale 48 000** |
| `PlanVersionGardeTest` (serveur) | poste sans version / version 1, 0, 3, 99 refusés avec le motif ; poste migré accepté ; **deux postes dont un non migré** ; lot mixte ; rejeu ; version servie ; demande de compte d'un ancien poste |
| `comptabilite_sync_poste_test`, `report_a_nouveau_test` (faux serveur qui rejoue la garde) | le poste envoie la version, refuse un plan/une pièce d'un autre plan |
| `ecritures_ventes_commun_test.dart` ↔ `EcrituresAutomatiquesVentesTest` | A-F (inchangés, renumérotés) + **G** 11 800 TTC → 10 000 + 1 800 (4431) ; **H** livraison 1 180 → 1 000 (7071) + 180 (4432) ; **I** panier mixte, livraison exonérée ; **J** annulation reprend la TVA ; **K** recouvrement ne touche pas la TVA |
| `plan_syscohada_test.dart` ↔ `EcrituresAutomatiquesAchatsTvaTest` | achat 59 000 TTC → 50 000 + 9 000 (4452) ; achat mixte ; achat exonéré ; **résultat 5 000 sans TVA**, bilan équilibré ; sens naturel ; arrondis 1 000 → 153, 5 000 → 763 |
| contrôles d'expert déjà écrits (équilibre, actif = passif, TAFIRE, jeu commun de 133 000) | restent verts, renumérotés |

**Mutations** (cassée la règle, un test rougit) : les **12 règles** de correspondance, une à une, côté Dart **et** côté PHP :
12/12 mutants tués ; garde de version supprimée (3 tests rouges) ; `plan_version` retiré de l'envoi du poste (18 tests rouges) ;
arrondi de la TVA `round` → `floor` (poste et web : rouge) ; constante TVA 4431 → 4432 (rouge). Les fichiers sont restaurés.

Essai réel `bash logialvia_app/outils/essai_vrai_serveur.sh` : **55 essais verts** contre le vrai serveur (poste → serveur →
poste, avec la garde active).

## 9. Décisions à valider par l'expert-comptable

| # | Décision | Alternative |
|---|---|---|
| V1 | **Relire les 60 numéros/libellés contre le Journal officiel OHADA** (non téléchargé, §1). | — |
| V2 | **Mobile Money en 552** (monnaie électronique) plutôt qu'en 521. | 521 « Banques locales » |
| V3 | **Produits des filières en 702** (produits finis). | 703/704 selon la nature (fumier, plumes = résiduels 704) ; 706 pour des prestations |
| V4 | **Fournitures et soins vétérinaires en 604** (achats stockés consommables). Les honoraires du vétérinaire, eux, relèvent de 632. | 6041/6044 plus fin ; 632 pour les visites |
| V5 | **TVA des frais de livraison** : taux du panier s'il est unique, sinon exonéré. TVA sur 4432 (prestations). | Accessoire suivant toujours le principal le plus taxé ; ou tout en 4431 |
| V6 | **Arrondi de la TVA au franc par ligne de ventilation** (écart < 0,5 F/ligne avec la facture e-MECeF). | Arrondir à la facture ; ou ne pas arrondir |
| V7 | **Historique des ventes taxables** : conservé TTC (aucune TVA reconstituée) ; seules les ventes d'après la migration ventilent. Reconstituer depuis les factures e-MECeF serait possible mais discutable (taux du groupe à la date de vente). | Écriture de régularisation 4431 par OD |
| V8 | **Ligne 707 sans centre d'une pièce de vente = frais de livraison** (7071) ; une OD manuelle sur 707 sans pièce de vente reste « marchandises » (701). | Revue manuelle des 707 historiques |
| V9 | Sous-comptes créés à la main : **suivent leur compte** (préfixe), fusion si le numéro cible existe. | Les laisser en place (risque : changent de sens) |
| V10 | Pas d'écriture automatique de **déclaration de TVA** (4431/4452 → 4441/4449). | OD mensuelle générée |
| V11 | 36 « Produits finis » et 246 « Immobilisations animales et agricoles » semés pour les stocks d'animaux / reproducteurs, **sans écriture automatique** (valorisation des stocks hors périmètre). | — |

## 10. Limites

- **Texte officiel non vérifié** (§1) ; libellés reconstitués.
- **Achats : la TVA déductible est câblée mais le taux est 0** : un intrant n'a pas encore de groupe de taxe (colonne à créer
  sur `intrants` avec sa synchronisation : touche les tables d'achats et le stock, en cours chez d'autres agents). La
  génération (`pourAchat`) extrait déjà la TVA du TTC et la porte au 4452 dès qu'un taux lui est fourni ; testée en direct.
- **Dépenses saisies à la main** : toujours sans ventilation de TVA (la saisie n'a pas de champ taux).
- **Annulation d'une vente au poste** : l'écriture inverse est recalculée avec le taux **courant** du groupe de taxe ; si ce
  taux a changé depuis la vente, la TVA reprise diffère. Le web, lui, contrepasse ce que le livre porte réellement.
- **Poste migré face à un serveur pas encore migré** : le serveur ancien ignore `plan_version` ; déployer le serveur d'abord.
- Classe 8 non saisissable (limite préexistante des classes `1-7` du plan synchronisé).
- La migration serveur est testée sous SQLite ; sous MySQL, le `->change()` de la valeur par défaut de `plan_version`
  s'appuie sur le support natif de Laravel 12 (non rejoué ici : essai MySQL à faire par l'agent réseau/MySQL).
- Les PDF du manuel (`docs/manuel`) ne sont pas régénérés (consigne) : ils citent encore l'ancien plan.
- Les états financiers restent ceux de `47c_` (TAFIRE simplifié) ; la TVA y est dans les tiers (créances/dettes), pas dans
  la trésorerie : le TAFIRE reste équilibré (identité vérifiée par le jeu commun).
