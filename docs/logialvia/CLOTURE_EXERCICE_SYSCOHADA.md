# CLOTURE_EXERCICE_SYSCOHADA — Guide opérateur : clôture d'exercice et bascule

**Statut : guide rédigé le 2026-11-11 à partir du code du dépôt** (web Laravel et poste Flutter), relu règle par règle. Il ne remplace pas les documents de conception : `docs/J1_Bascule_Cloture_Exercice.md` (principe), `47c_COMPTABILITE_SYSCOHADA_RAN.md` (règles R1 à R10, report à nouveau), `47p_PLAN_COMPTABLE_SYSCOHADA.md` (numéros de comptes), `26_MODULE_COMPTABILITE_EXERCICES.md` (cahier des charges, en partie « proposé »), `46d_SYNC_COMPTABILITE.md` (synchronisation). En cas d'écart, **le code fait foi** ; les écarts constatés sont listés au §10 et au §11.

Écran : **Comptabilité > Clôture d'Exercice**, route `/comptabilite/cloture`, présent à l'identique (mêmes libellés, mêmes étapes) :
- au **web** : `logialvia_laravel/app/Livewire/Cloture.php`, vue `resources/views/livewire/comptabilite/cloture.blade.php`, route déclarée dans `routes/ecrans/comptabilite-cloture.php` ;
- au **poste Windows** : `logialvia_app/lib/comptabilite/presentation/screens/cloture_exercice_screen.dart`, route `/comptabilite/cloture` dans `lib/core/router/app_router.dart`.

Deux clôtures distinctes sur le même écran : la **clôture périodique** (un mois, §4) et la **clôture annuelle** (l'exercice, §5 à §7). Ne pas les confondre (J1, en-tête).

## 1. Qui peut faire quoi

| Action | Web (droit Laravel) | Poste (rôle Dart) |
|---|---|---|
| Voir l'écran et les exercices | `view-comptabilite` (route `/comptabilite/cloture`, `config/logialvia.php`) | `admin` seul (la route `/comptabilite/cloture` n'est dans la liste d'aucun autre rôle : `lib/core/router/permission_service.dart`) |
| Clore un mois | `manage-comptabilite` (admin, comptable) | tout rôle qui atteint l'écran, donc `admin` ; le ViewModel ne contrôle pas le rôle pour cette action |
| Déclôturer un mois | `close-fiscal-year` (admin seul) | `admin` (contrôle dans `ComptabiliteViewModel.decloturerMois`) |
| **Clôturer l'exercice** | `close-fiscal-year` (admin seul) | `admin` (contrôle dans `ComptabiliteViewModel.cloturerExercice`, pas seulement dans l'écran) |
| **Rouvrir l'exercice** | `close-fiscal-year` (admin seul) | `admin` (`ComptabiliteViewModel.rouvrirExercice`) |

Sources : `config/logialvia.php` (rôles `admin`, `comptable`, `caissier`, `animalier` ; le commentaire « close-fiscal-year : admin seul (DV-15), à confirmer (Q-DV-7) » est dans le tableau `role_permissions`), `app/Sync/Tables/ClotureExerciceTable.php` (`peutEcrire`, `rouvrir`), `app/Sync/Tables/CloturesPeriodiquesTable.php`.

Points à retenir :
- Le rôle **comptable** n'existe qu'au web. Le poste n'a que trois rôles (`admin`, `caissier`, `animalier`) : la comptabilité y est réservée à l'administrateur.
- Le comptable clôt les mois mais **ne clôt pas l'exercice** (46d §2.7, décision DV-15).
- Un bouton absent à l'écran traduit un droit manquant ; forcer l'appel serait refusé par le serveur (`abort_unless(... can('close-fiscal-year'), 403)` dans chaque méthode de `Cloture.php`, plus le contrôle de `ClotureExerciceTable`).

## 2. Prérequis avant de clôturer un exercice

À faire **avant** d'ouvrir l'assistant. Rien de ceci n'est vérifié par l'application, sauf mention contraire.

1. **Inventaire et régularisations** (étape 1 de l'assistant, manuelle) : rapprochement Espèces / Mobile Money, inventaire physique des stocks (écran Gestion Stocks), vérification des soldes clients et fournisseurs. L'écran dit : « Étape manuelle : clôturez les mois traités dans la grille ci-dessus au fur et à mesure. » Il affiche « Les 12 mois de l'exercice sont clôturés. » quand les 12 mois le sont, mais **ne l'exige pas** pour clôturer l'exercice (aucun contrôle dans `cloturerExercice()` ni dans `ClotureExerciceTable::absorber`).
2. **Tous les postes synchronisés** si l'exercice est tenu par plusieurs postes. Le serveur clôt depuis **son** livre : une pièce encore sur un poste hors ligne n'y est pas (47c §7). Une pièce saisie hors ligne pour l'exercice et arrivant **après** la clôture est refusée avec son motif (elle reste, marquée, dans les livres du poste).
   - Poste **appairé** : la clôture est refusée tant qu'une pièce de l'exercice n'est pas acceptée par le serveur. Message : « Synchronisez ce poste avant de clôturer : N pièce(s) de AAAA n'ont pas été acceptées par le serveur… » (`comptabilite_repository_drift.dart`, `cloturerExercice`). Un poste **jamais appairé** clôture seul.
3. **Balance équilibrée** (débit = crédit, tolérance 0,01). Contrôlée trois fois : par l'écran (bouton désactivé, KPI « Balance : Écart … »), par l'action (« Balance déséquilibrée de N FCFA. Une clôture annuelle est définitive… (BR-CPT-004). ») et par le serveur sur **toutes** les lignes de l'exercice (`Verrous::exerciceEquilibre`).
4. **Comptes présents au plan comptable** : tout compte utilisé par les pièces de clôture doit exister (`Compte(s) absent(s) du plan comptable : …`). Voir §8.
5. **Ordre des exercices** : on ne clôt pas N si N+1 est déjà clôturé (« L'exercice N+1 est déjà clôturé : clôturez les exercices dans l'ordre. »).
6. **Plan comptable à jour sur tous les postes** : le serveur refuse une pièce sans la bonne `plan_version` (47p §5). Déployer le serveur **avant** de migrer les postes.
7. **Sauvegarde** : voir §9, la clôture est définitive pour un comptable (seule la réouverture, §7, la défait).

Rôle requis : administrateur (§1). Date de clôture : **aucun contrôle de date** n'existe dans le code (on peut clôturer l'exercice avant le 31/12) ; le cahier des charges 26_ §11 (« Clôture refusée le 15/11/2026 : échéance non passée ») est une **proposition non implémentée**.

## 3. Choisir l'exercice

L'écran travaille sur l'**exercice choisi** :
- web : liste déroulante « Exercice » de l'en-tête (`livewire.comptabilite._entete`) ; l'exercice affiché est borné aux exercices connus (`LivreComptable::exerciceChoisi`) ;
- poste : clic sur un jeton de la frise des exercices (`vm.changerExercice`).

Vérifier l'année avant tout clic : « Clôturer l'Exercice 2026 » désigne l'année choisie. Le bandeau KPI donne l'état : **Résultat Provisoire**, **Comptes de Gestion à Solder** (nombre de comptes 6x/7x mouvementés), **Balance** (« Équilibrée » ou « Écart … »). La frise indique « En cours » ou « Clôturé » pour l'exercice sélectionné (« Exercice » pour les autres).

## 4. Clôture périodique (mois)

Grille de 12 jetons (janvier à décembre), 🔓 ouvert / 🔒 clos (web) ou icône cadenas (poste).

- **Clore** : refusé si l'exercice est déjà clôturé, ou si la balance est déséquilibrée (« Corrigez la saisie avant toute clôture (BR-CPT-004). »). Effet : « Mois de X clôturé. »
- **Déclôturer** : administrateur seul, **tracé au journal d'audit** (action `comptabilite.decloture` au web). Message : « Mois de X déclôturé — action tracée dans le journal d'audit. » Bouton absent pour les autres : « Déclôture réservée ».
- Un mois clos refuse **toute nouvelle écriture à sa date**, y compris l'écriture automatique d'une vente ou d'un achat antidaté (`Verrous::motifVerrou` : « Le mois M/AAAA est clôturé. Une administratrice peut le déclôturer pour correction (BR-CPT-006). »). Rien n'est supprimé.
- Quand l'exercice est clôturé, les boutons de mois ne sont plus proposés (web) ou sont inactifs (poste).
- Fait synchronisé en « dernier écrivain gagne », par (année, mois) : `CloturesPeriodiquesTable` (46d §2.6).

## 5. Clôture annuelle : l'assistant en 4 étapes

Libellés de l'écran (identiques web et poste) :

| Étape | Libellé | Nature |
|---|---|---|
| 1 | Travaux d'Inventaire & Régularisation | **manuelle** (aucune action de l'application) |
| 2 | Solde des Comptes de Gestion (Classes 6, 7 & 8) | calculée |
| 3 | Affectation du Résultat | saisie dans la fenêtre de confirmation |
| 4 | Génération des Écritures d'À-Nouveaux (RAN) | bouton **« Clôturer l'Exercice AAAA »** |

Déroulé :

1. Vérifier le bandeau KPI : balance « Équilibrée », résultat provisoire attendu.
2. Cliquer sur **Clôturer l'Exercice AAAA** (étape 4). Le bouton est inactif si la balance est déséquilibrée.
3. Dans la fenêtre « **Clôturer définitivement l'exercice AAAA ?** » : lire les conséquences (écritures verrouillées ; exercice AAAA+1 ouvert ; résultat net arrêté ; pièces hors ligne refusées au retour du poste), puis, **si le résultat est un bénéfice**, saisir l'affectation (§6). La fenêtre affiche en direct « Report à nouveau créditeur (121) » et d'éventuelles **anomalies** (texte rouge).
4. Confirmer par **« Clôturer l'exercice AAAA »** (bouton rouge). Message : « Exercice AAAA clôturé. L'exercice AAAA+1 est ouvert. » (poste : « … ouvert avec ses à-nouveaux. »).

Il n'y a **pas de saisie de mot de confirmation** (« CLOTURER ») : J1 §3 et 26_ §8 la prévoient, ni le web (`cloture.blade.php`) ni le poste ne l'implémentent (recherche de « CLOTURER » dans `lib/` et `app/`/`resources/` : aucune occurrence). La fenêtre précise : « Cette action ne peut pas être annulée depuis l'application » ; la seule défaite est la réouverture (§7).

Le tout s'exécute **dans une transaction** : au web `DB::transaction` autour de `ClotureExerciceTable::absorber` ; au poste `_db.transaction` dans `cloturerExercice`. Si une étape échoue, rien n'est écrit (47c R8).

## 6. Écritures générées

Calculées par `ReportANouveau` (poste : `lib/comptabilite/domain/services/report_a_nouveau.dart`, **source** ; web : `app/Services/Comptabilite/ReportANouveau.php`, port comparé par `ReportANouveauTest`). **Le serveur génère lui-même** ces pièces à partir de son livre (`ClotureExerciceTable::absorber`), jamais depuis ce qu'un poste enverrait : les journaux `CL` et `AN` sont **refusés s'ils viennent d'un poste** (`EcrituresTable::JOURNAUX_DE_CLOTURE`, test `test_un_poste_ne_peut_pas_envoyer_de_pieces_cl_ou_an`). Les identifiants sont déterministes : clôturer deux fois ou rejouer ne duplique rien (47c R9).

| Pièce | Journal | Date | Contenu |
|---|---|---|---|
| `CL-AAAA-RESULTAT` | `CL` | 31/12/AAAA | Solde chaque compte de **gestion** (classes 6, 7, 8) mouvementé : charges créditées, produits débités ; le résultat net va au **131** (bénéfice, créditeur) ou au **139** (perte, débiteur). Absente s'il n'y a aucun compte de gestion mouvementé |
| `CL-AAAA-AFFECTATION` | `CL` | 31/12/AAAA | Bénéfice : débit 131 ; crédits **111** réserve légale, **118** autres réserves, **465** dividendes à payer, et le reste au **121** report à nouveau créditeur. Perte : débit **129** report à nouveau débiteur / crédit 139 |
| `AN-AAAA+1` | `AN` | 01/01/AAAA+1 | **À-nouveaux (RAN)** : soldes des comptes des **classes 1 à 5** après affectation, chacun gardant son sens ; **jamais** de classe 6, 7 ou 8. Pièce créée dans l'exercice AAAA+1 |

Résultat net = produits − charges des classes **6, 7 et 8** (HAO, participation, impôt compris), via `ReportANouveau::calculer`. La classe 8 compte dans le résultat mais **ne peut pas être saisie** (le plan synchronisé n'accepte que `^[1-7]`, 47p §2 et §10).

### Affectation du bénéfice (règles vérifiées dans `validerAffectation`)

- Les trois montants (réserve légale 111, autres réserves 118, dividendes 465) sont saisis en FCFA ; **le reste va au 121**.
- Aucun montant négatif.
- Le total ne peut pas dépasser le bénéfice : « L'affectation (X) dépasse le bénéfice (Y). »
- Sur une perte ou un résultat nul : **aucune distribution** n'est acceptée ; la perte va au 129.
- Si un **129 antérieur** (report débiteur) existe, un dividende n'est accepté que si le bénéfice absorbe d'abord ce report.
- **Aucun taux n'est imposé** : pas de 10 % de réserve légale automatique (47c V3, la forme juridique n'étant pas connue). L'affectation est décidée à la clôture, alors qu'en droit l'Assemblée la vote en N+1 (47c V2). Le montant est conservé à l'exercice (`exercices_comptables.affectation`) et rappelé à l'étape 3 une fois clôturé.

### Effets de bord

- **Exercice** clos : définitif, `is_cloture = true`, `date_cloture`, `cloture_par` ; écritures verrouillées (dérivé de l'exercice).
- **Exercice AAAA+1** ouvert automatiquement (créé s'il n'existe pas).
- **Audit** : `comptabilite.cloture_exercice` (utilisateur, poste). Une trace du fait (qui, depuis quel poste, quand) est conservée dans `clotures_exercice`.
- **États financiers** : ceux de AAAA se lisent « **avant affectation** » (journal `CL` exclu ; bilan, compte de résultat, TAFIRE) ; ceux de AAAA+1 **cumulent** l'ouverture (`AN`). La balance et le grand livre lisent le livre complet (un compte de gestion y apparaît soldé). Règles R5 et R6 de 47c.
- **Rapports** : au **poste**, les journaux `CL` et `AN` sont exclus des recettes, dépenses et mouvements de trésorerie (`lib/rapports/data/repositories/rapports_repository_drift.dart`, `journalCode.isNotIn(['AN','CL'])`). Au **web**, `47c_` §3 annonce la même exclusion, mais la lecture de `app/Livewire/Rapports.php` et de `app/Services/Rapports/CalculRapports.php` ne montre **aucun filtre** sur les journaux (le livre complet de `LivreComptable::toutes()` est passé tel quel) : écart possible, **non testé ici** ; après une clôture, comparer l'onglet Rapports & États du web à celui du poste.
- Au journal, `AN` et `CL` sont filtrables et **non modifiables**.

## 7. Réouverture d'un exercice clôturé

Bouton **« Rouvrir l'Exercice AAAA »** (étape 4, visible seulement une fois l'exercice clos, administrateur seul). Fenêtre : « Les écritures de clôture (journal CL) de AAAA et les à-nouveaux (journal AN) de AAAA+1 seront retirés, et l'exercice AAAA redeviendra modifiable. Vous pourrez le clôturer de nouveau… »

Règles (code) :
- **Refusée** si l'exercice n'est pas clos, ou si l'exercice AAAA+1 est clos (« L'exercice AAAA+1 est clôturé : rouvrez-le d'abord. ») : rouvrir dans l'ordre inverse des clôtures.
- Retire les pièces `CL` de AAAA et `AN` de AAAA+1 (**pièces dérivées, jamais saisies**), supprime le fait de clôture, remet `is_cloture` à faux, date `rouvert_le`. Les postes suivent via `rouvert_le`.
- **Au poste appairé** : refusée si le serveur a accepté la clôture (fait partagé). Message : « La clôture de AAAA a été acceptée par le serveur : c'est un fait partagé. Elle se déclôture depuis le serveur (écran Clôture du web, droit close-fiscal-year), puis ce poste se synchronise. » Un poste jamais appairé, ou dont la clôture a été refusée, rouvre localement.
- Tracée à l'audit : `reouverture_exercice` au poste, `comptabilite.reouverture_exercice` au web.
- Après réouverture, on peut reclôturer : les pièces sont régénérées avec les mêmes identifiants.

La réouverture existe donc **malgré** la règle « définitif » de BR-CPT-001 et de l'écran (« La clôture annuelle est définitive ») ; c'est la décision 47c V5, **à valider par le client** (alternative : interdire toute réouverture). Le doc `46d_` §2.5 (« Aucune déclôture ») est antérieur à ce lot.

## 8. Plan comptable : numéros à connaître

Numéros du plan **révisé** en vigueur (47p, vérifié dans `lib/comptabilite/domain/plan_syscohada.dart` et `app/Support/PlanSyscohada.php`) :

| Rôle dans la clôture | Compte |
|---|---|
| Résultat bénéfice / perte | 131 / 139 |
| Réserve légale / autres réserves | 111 / 118 |
| Report à nouveau créditeur / débiteur | 121 / 129 |
| Dividendes à payer | 465 |
| Caisse / monnaie électronique (Mobile Money) | 571 / 552 |

Plan limité à **60 comptes** semés ; ajouter des sous-comptes est possible (« Nouveau compte »). L'ancienne numérotation (531 Caisse, 601/602 inversés…) décrite en 47c §7 **a été remplacée** par la migration v48 / `2026_11_09_160000` (47p) : ne pas suivre ce paragraphe de 47c. Le 611 « Transports sur achats » n'est pas confirmé par le PDF fourni par le client (47p §1). Relecture par l'expert-comptable recommandée avant la première déclaration fiscale (47p V1).

## 9. Pièges

1. **Clôturer avant que les postes aient tous synchronisé** : le serveur clôt sur son livre ; les pièces tardives sont refusées. Synchroniser chaque poste d'abord (au poste appairé, le contrôle est automatique, mais seulement pour **ce** poste).
2. **Poste hors ligne et exercice clos au web** : ses saisies de l'exercice sont refusées au retour, avec motif.
3. **Mauvais exercice sélectionné** : le bouton nomme l'année, vérifier.
4. **Balance déséquilibrée** : corriger par une écriture ou une contre-passation au Journal ; rien ne s'exécute tant que l'écart persiste.
5. **Affectation incohérente** : aucune pièce n'est proposée, la clôture est refusée avec le motif, rien n'est écrit.
6. **Réserve légale** : l'application n'impose aucun pourcentage ; c'est à l'opérateur de la saisir (47c V3).
7. **Bilan « avant affectation »** pour l'exercice clos : le résultat y reste sur « Résultat de l'exercice », c'est voulu (R5).
8. **Clôtures faites avant le lot 47c** : sans à-nouveaux ; l'ouverture suivante est reconstituée par une « clôture virtuelle » (121/129, rien n'est écrit). L'écran le dit. Rouvrir puis reclôturer écrit les vrais à-nouveaux.
9. **Réouverture du poste impossible** si le serveur a accepté (§7) : prévoir l'accès web administrateur.
10. **Plan comptable** : un poste non migré est refusé (`plan_version`) ; déployer serveur puis postes.
11. **Libellé d'audit** : au web, `LibellesAudit` nomme `comptabilite.decloture` « Exercice déclôturé » alors que l'action concerne un **mois** ; l'action `comptabilite.reouverture_exercice` n'a pas de libellé dédié dans ce fichier (recherche « reouvert » : aucune occurrence). Lire le détail (année, mois) dans le journal d'audit.
12. **Sauvegarde** : avant une clôture réelle, faire une sauvegarde. Web : Paramètres Généraux > Sauvegardes (téléchargement JSON, administrateur seul, 47u). Poste : Paramètres Généraux > onglet **Sauvegardes** (`onglet_sauvegardes.dart`).

## 10. Ce qui n'existe pas (encore)

À ne pas chercher dans l'application, avec la procédure réelle :

| Attendu (document de conception) | Réalité dans le code | Procédure réelle |
|---|---|---|
| Saisie du mot « CLOTURER » (J1 §3, 26_ §8) | Absente (web et poste) | Fenêtre de confirmation avec bouton rouge ; relire le résultat et l'année avant de cliquer |
| Garde d'échéance (« clôture refusée avant le 31/12 », 26_ §8 et §11) | Aucun contrôle de date | Respecter le calendrier par discipline : ne clôturer qu'après la fin de l'exercice |
| Obligation des 12 mois clos avant l'exercice | Non exigée (étape 1 manuelle) | Clore les 12 mois soi-même |
| Ouverture automatique de N+1 le 1er janvier par tâche planifiée, bouton dès le 1er décembre, « deux exercices ouverts au plus » (26_ §8, repris d'AgriERP) | Aucune tâche ni bouton ; N+1 est créé **par la clôture** ou, au serveur, ouvert à la première écriture (`Verrous::exercice`, borné à l'année courante + 1) | Clôturer N pour obtenir N+1 ; une première écriture de l'année crée l'exercice au serveur |
| Récapitulatif pré-clôture : tableau des soldes projetés (J1 §3) | Aperçu partiel : KPI (résultat, nombre de comptes de gestion, balance), nombre de comptes de bilan reportés et anomalies dans la fenêtre ; pas de tableau compte par compte | Consulter la **Balance Générale** et les **États Financiers** de l'exercice avant de clôturer |
| Exclusion des journaux `CL`/`AN` dans les Rapports du web (annoncée par 47c §3 et E9) | Présente au poste ; non retrouvée dans le code des Rapports web (§6) | Lire les rapports de l'exercice clos avec prudence au web ; comparer au poste |
| Verrou de classe 8 non soldée (26_ §8) | La classe 8 entre dans le résultat, aucun blocage dédié | Contrôler la balance |
| `isLocked` ligne à ligne (J1 §1.3) | Le verrouillage est **dérivé** de l'exercice clos (web) ; au poste le champ `isLocked` des écritures est posé à la clôture et retiré à la réouverture | Aucune action |
| Rôle comptable avec droit de clôturer (Q-DV-7 « à confirmer ») | `close-fiscal-year` : administrateur seul | Faire clôturer par l'administrateur |
| Déclôture d'exercice « jamais » (J1, BR-CPT-001 stricte, 46d §2.5) | **Réouverture existe** (§7) | Voir §7 |
| Registre d'immobilisations, dotation automatique, déclaration de TVA, paie (26_ §9 « PROPOSÉ — absents de logialvia ») | Aucune table ni service d'immobilisations (`database/migrations`, `lib/comptabilite/data` : aucune occurrence du mot) ; pas d'écriture de déclaration de TVA (47p V10) ; pas de paie (aucun module dans `app/` ni `lib/`) | Passer les dotations aux amortissements par une écriture manuelle (OD) au Journal avant la clôture ; le TAFIRE reste « simplifié » (47c §7) |
| Export PDF de la clôture au web | Vue imprimable (`Imprimer / PDF`) ; le PDF généré du poste n'est pas reproduit (47c §6) | Imprimer depuis le navigateur ou le poste |

## 11. Tests qui garantissent ce comportement

- Poste : `logialvia_app/test/comptabilite/report_a_nouveau_test.dart` (jeu 2024 calculé à la main : résultat 300 000, réserve légale 30 000, dividendes 100 000, report 170 000, à-nouveaux 1 550 000 de chaque côté), `comptabilite_view_model_test.dart`, `comptabilite_sync_poste_test.dart`.
- Web : `logialvia_laravel/tests/Feature/Web/ReportANouveauTest.php` (16 tests dont : clôture idempotente, affectation incohérente sans écriture, `CL`/`AN` refusés d'un poste, seule l'administratrice clôt et rouvre, réouverture puis reclôture, réouverture refusée si N+1 clos, ouverture de N+1 cumulée, clôture virtuelle) et `tests/Feature/Sync/ComptabiliteTest.php`.
- Essai réel poste ↔ vrai serveur : `logialvia_app/test/integration/serveur_reel_test.dart` (voir `47h_PREUVE_VRAI_SERVEUR.md`).
- Commandes : `php artisan test --filter=ReportANouveau` (depuis `logialvia_laravel/`) ; `flutter test test/comptabilite/` (depuis `logialvia_app/`).

```bash
cd logialvia_laravel && php artisan test --filter=ReportANouveauTest
cd ../logialvia_app && flutter test test/comptabilite/report_a_nouveau_test.dart
```

## 12. Aide-mémoire opérateur

```text
AVANT      sauvegarde faite · tous les postes synchronisés · 12 mois clos (par discipline)
           balance « Équilibrée » · bon exercice sélectionné · administrateur connecté
PENDANT    Clôturer l'Exercice AAAA → saisir l'affectation (si bénéfice) → lire les anomalies → confirmer
APRES      exercice AAAA sélectionné : « Clôturé » · AAAA+1 existe · journaux CL et AN visibles au Journal
SI ERREUR  Rouvrir l'Exercice AAAA (web si le serveur a accepté) → corriger → reclôturer
```
