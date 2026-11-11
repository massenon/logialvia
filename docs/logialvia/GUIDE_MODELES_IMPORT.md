# GUIDE_MODELES_IMPORT — Exports existants et modèles d'import (proposés)

**Statut : vérifié dans le code le 2026-11-11.** Ce guide répond à deux questions : (1) **que peut-on exporter aujourd'hui** de LogiALVIA (web et poste), avec quels formats et quelles colonnes ; (2) **peut-on importer des données en masse**. Réponse à la seconde, établie par recherche dans le code : **non, l'importation n'existe pas**, ni au web ni au poste (§4). La section « Modèles proposés » (§6) est une **proposition, non implémentée**, destinée à préparer la saisie initiale des clients, fournisseurs, produits et intrants avec le client.

Documents liés : `28_MODULE_RAPPORTS_EXPORTS_IMPORTS.md` (cahier des charges ; son §5 « Importation en masse — À CONCEVOIR » est cohérent avec ce constat), `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` (bloc 21), `47n_TESTS_NAVIGATEUR.md` (vérification des exports), `47u_ADMINISTRATION_PARITE.md` (sauvegardes).

## 1. Formats réellement produits

| Plateforme | Format | Où | Source |
|---|---|---|---|
| Web | **XLSX** (Office Open XML, une feuille, sans dépendance externe : écrit avec `ZipArchive`) | bouton « Exporter » (le libellé de l'en-tête des écrans de comptabilité est « Exporter (XLSX) ») | `logialvia_laravel/app/Support/ExportXlsx.php` |
| Web | Vue **imprimable** (`@media print`, enregistrable en PDF par le navigateur) | « Imprimer / PDF » et routes `…/imprimer`, `…/impression` | `routes/ecrans/*.php`, `app/Http/Controllers/ImpressionsCommerce.php` |
| Web | **JSON** « sauvegarde logique » des données du serveur (téléchargement, administrateur seul, sans mot de passe ni jeton) ; non restaurable par le web | Paramètres Généraux > onglet Sauvegardes | `app/Services/SauvegardeLogiqueService.php`, `app/Livewire/SauvegardesWeb.php` |
| Poste | **PDF** (générateur unique, police Roboto embarquée), bouton « Exporter PDF » (libellé par défaut de `BoutonExportPdf`) : boîte d'impression du système ou enregistrement du fichier | écrans listés au §3 | `logialvia_app/lib/core/pdf/` |
| Poste | **CSV d'une table** : séparateur point-virgule, BOM UTF-8, une ligne d'en-têtes même pour une table vide, **toutes les colonnes de la table Drift** | Paramètres Généraux > Sauvegardes > « Exporter une table en CSV » | `logialvia_app/lib/administration/domain/services/service_sauvegarde.dart` (`exporterTable`) |
| Poste | Copie complète de la base `.sqlite` (`VACUUM INTO`) et **restauration** au redémarrage | Paramètres Généraux > Sauvegardes | `service_sauvegarde.dart`, `service_restauration.dart` |

Aucun export **CSV** n'existe au web ; aucun export **XLSX** n'existe au poste (le poste ne dépend d'aucun paquet tableur : `logialvia_app/pubspec.yaml` ne déclare que `pdf` et `printing` pour l'export).

### Règles de typage des XLSX du web (`ExportXlsx`)

- Un nombre (`int` ou `float`) est une cellule **numérique** formatée `#,##0` ou `#,##0.00` ; tout le reste est du **texte** (`inlineStr`).
- Un texte qui commence par `=`, `+`, `-` ou `@` n'est **jamais évalué** comme formule.
- `ExportXlsx::typer` transforme les entiers écrits en texte (`1000`, `-400`) en nombres ; les identifiants (n° de compte, code, référence, n° de pièce) restent du texte.
- La première ligne est le **titre** en gras (ou l'en-tête quand il n'y a pas de titre) ; la largeur des colonnes suit le contenu.
- Le test navigateur `e2e/verifier_xlsx.py` (appelé par `e2e/transversaux.mjs`) ouvre chaque export avec `openpyxl` et vérifie : feuille nommée, en-tête sans cellule vide, nombres typés (aucun nombre rangé en texte), ligne et colonnes présentes. `47n_` indique **15 écrans** vérifiés (la liste `EXPORTS` de `e2e/transversaux.mjs` compte bien 15 entrées) ; le code expose **20 méthodes d'export** (§2). **5 exports ne sont pas couverts par cette vérification automatique** : Comptabilité Analytique, États Financiers, Bilan de l'Entreprise, Gestion Utilisateurs, Corbeille.

```bash
python3 -I logialvia_laravel/e2e/verifier_xlsx.py fichier.xlsx
bash logialvia_laravel/e2e/lancer.sh
```

## 2. Exports XLSX du web : écran, droit, colonnes

Les colonnes sont celles écrites dans la méthode `exporter()` du composant Livewire cité. « Titre » = première ligne de la feuille quand elle existe.

| Écran (route) | Composant | Droit requis | Fichier | Feuille | Colonnes |
|---|---|---|---|---|---|
| Historique des ventes (`/ventes`) | `Ventes` | `export-ventes` | `historique-ventes.xlsx` | Historique | Référence · Date · Client · Mode · Statut · Total · Payé · Reste dû |
| Clients : créances (`/clients`) | `Clients` | `export-ventes` | `creances-clients.xlsx` | Créances | Client · Référence Vente · Date · Échéance · Montant Total · Déjà Réglé · Solde Restant Dû · Ancienneté (jours) |
| Devis de prestations (`/ventes/devis`) | `Devis` | `export-ventes` | `devis-prestations.xlsx` | Devis | Référence · Client · Objet · Montant estimé (FCFA) · Émis le · Expire le · Statut |
| Factures e-MECeF (`/factures-mecef`) | `FacturesMecef` | `view-facturation` | `factures-mecef.xlsx` | Factures | Référence · Date · Client · Facture corrigée · Total TTC (FCFA) · Statut |
| Achats & Commandes (`/achats`) | `Achats` | `view-achats` | `achats.xlsx` | Achats | Référence · Date · Fournisseur · Mode · Statut · Total · Payé · Reste dû · Échéance |
| Fournisseurs & Dettes (`/fournisseurs`) | `Fournisseurs` | `view-achats` | `fournisseurs-dettes.xlsx` | Fournisseurs | Bloc 1 : Nom · Téléphone · Adresse · Fournit · Commandes · Total achats · Solde dû. Bloc 2 « Dettes en cours » : Fournisseur · Référence · Total · Réglé · Solde dû · Échéance · Ancienneté (jours) |
| Gestion des Stocks (`/stocks`) : journal | `GestionStocks` | `view-stocks` | `journal-mouvements.xlsx` | Journal | Date / Heure · Poste · Référence · Article · Type · Motif · Quantité (100 derniers mouvements : `LIMITE_JOURNAL`) |
| Fiche d'élevage (`/elevage/<filière>`) | `FicheEspece` | `view-elevage` + `export-elevage` | `fiche-<filière>-AAAA-MM.xlsx` | libellé de la filière | Date · (libellé « achats » de la filière) · (libellé « naissances ») · Vente · Morts · Dons · Effectif · Pesée (g) · Observation de traitement ; une ligne par jour **enregistré** du mois affiché |
| Rapports & États (`/rapports`) | `Rapports` | `view-rapports` + `export-rapports` | `rapport-<onglet>-AAAAMMJJ-AAAAMMJJ.xlsx` | nom de l'onglet | Onglet **Recettes et Dépenses** : Période · N° Pièce · Catégorie SYSCOHADA · Centre de Profit · Encaissement · Décaissement · Solde Cumulé. **État de Trésorerie** : Date · Compte · Type d'Opération · Libellé · Entrée · Sortie · Solde Progressif. **Créances Clients** : Code · Client · N° Facture · Date Vente · Échéance · Montant Initial · Acomptes · Solde Dû · Retard · Statut. **Dettes Fournisseurs** : Code · Fournisseur · N° Bon/Facture · Date Achat · Échéance · Montant Total · Réglé · Solde Restant · Statut. **Rapport Élevage** : trois tableaux (Recensement & Structure du Cheptel ; Mouvements, Traitements & Ventes ; Couvoir & Suivi d'Incubation). L'onglet **Rapport de Stocks** n'exporte rien (stock propre à chaque poste) |
| Journal Comptable (`/comptabilite/journal`) | `Journal` | `view-comptabilite` | `journal-comptable-AAAA.xlsx` | Journal | Date · Journal · Pièce · Compte · Libellé · Débit · Crédit (+ ligne Total) |
| Grand Livre (`/comptabilite/grand-livre`) | `GrandLivre` | `view-comptabilite` | `grand-livre-AAAA.xlsx` | Grand Livre | Date · Pièce · Libellé · Débit · Crédit · Solde progressif (+ ouverture et total période) |
| Balance Générale (`/comptabilite/balance`) | `BalanceGenerale` | `view-comptabilite` | `balance-generale-AAAA.xlsx` | Balance Générale | Compte · Libellé · Ouverture débit · Ouverture crédit · Mouvements débit · Mouvements crédit · Solde débit · Solde crédit (+ ligne Total) |
| Plan Comptable (`/comptabilite/plan`) | `PlanComptableEcran` | `view-comptabilite` | `plan-comptable.xlsx` | Plan Comptable | Compte · Libellé · Classe · Statut |
| Comptabilité Analytique (`/comptabilite/analytique`) | `Analytique` | `view-comptabilite` | `comptabilite-analytique-AAAA.xlsx` | Comptabilité Analytique | Centre · Revenus · Coûts · Marge (+ Total, Charges non affectées) |
| États Financiers (`/comptabilite/etats-financiers`) | `EtatsFinanciers` | `view-comptabilite` | `etats-financiers-AAAA.xlsx` | États Financiers | Poste · Comptes · Montant (onglet actif ; bilan : ACTIF / PASSIF ; TAFIRE avec trésorerie d'ouverture et de clôture) |
| Bilan de l'Entreprise (`/comptabilite/bilan`) | `BilanEntreprise` | `view-comptabilite` | `bilan-entreprise-AAAA.xlsx` | Bilan de l'Entreprise | ACTIF / PASSIF · Compte · Montant (+ TOTAL ACTIF, TOTAL PASSIF) |
| Saisie des Dépenses (`/depenses`) | `Depenses` | `view-comptabilite` | `depenses-AAAA.xlsx` | Saisie des Dépenses | Date · Pièce · Libellé · Compte · Montant · Statut · Centre (+ Total affiché) |
| Journal d'audit (`/parametres/audit`) | `JournalAudit` | `manage-users` | `journal-audit.xlsx` | Journal d'audit | Date · Utilisateur · Identifiant · Action · Code action · Détail · Adresse IP |
| Gestion Utilisateurs (Paramètres Généraux) | `GestionUtilisateurs` | `manage-users` | `utilisateurs.xlsx` | Utilisateurs | Nom complet · Identifiant · E-mail · Rôle · Statut · Mot de passe temporaire · Dernière connexion |
| Corbeille (Paramètres Généraux) | `CorbeilleWeb` | `view-parametres` | `corbeille.xlsx` | Corbeille | Module · Type · Désignation · Archivé le (UTC) · Origine |

Notes de lecture :
- Les droits sont ceux relevés dans l'appel `abort_unless(...)` ou la méthode de contrôle de chaque `exporter()`.
- **Rôles** : `export-ventes` est donné à `caissier` et à `admin` ; `export-rapports` à `comptable` et `admin` ; `export-elevage` à `animalier` et `admin` (`config/logialvia.php`, `role_permissions`).
- **Pas d'export XLSX** pour le **Catalogue** (`/catalogue`), la **liste des clients**, la **liste des intrants** ni la **liste des fournisseurs seule** : seuls existent les exports ci-dessus (créances, dettes, journal des mouvements). Au poste, le Catalogue s'exporte en PDF.

## 3. Exports PDF du poste (bouton « Exporter PDF »)

Chaque bouton construit le document **au clic**, avec les filtres et la période en vigueur (`BoutonExportPdf.construire`). Titres de document (fichiers `documents_*.dart`) :

| Module | Écran | Titre du document |
|---|---|---|
| Commercial | Historique des ventes | Historique des Ventes (colonnes : Référence · Date · Client · Mode · Total · Payé · Reste Dû · Statut) |
| Commercial | Clients | Suivi des Soldes Clients |
| Commercial | Catalogue | Catalogue Produits & Seuils d'Alerte (colonnes : SKU · Désignation · Catégorie · Prix · Unité · Stock · Seuil · Statut) |
| Commercial | Facture de vente (modale) | Facture de Vente — référence ; facture e-MECeF (`documents_mecef.dart`) |
| Approvisionnement | Achats & Commandes | Achats & Commandes |
| Approvisionnement | Fournisseurs | Fournisseurs & Dettes (tableaux « Fournisseurs » et « Dettes en cours ») |
| Approvisionnement | Gestion des Stocks | État des Stocks d'Intrants (tableaux « Intrants » et « Journal des mouvements ») |
| Comptabilité | Journal, Balance, Plan, Grand Livre, Analytique, Dépenses, Clôture | Journal Comptable · Balance Générale · Plan Comptable · (grand livre) · Comptabilité Analytique · Saisie des Dépenses · Clôture d'Exercice AAAA |
| Comptabilité | États financiers (onglet actif) | Bilan · Compte de Résultat · Tableau des Flux de Trésorerie (TAFIRE simplifié) · Notes Annexes |
| Comptabilité | Bilan de l'Entreprise | Bilan de l'Entreprise |
| Rapports | Rapports & États (6 onglets) | Recettes et Dépenses · État de Trésorerie · Créances Clients · Dettes Fournisseurs · Rapport Élevage · Rapport de Stocks |
| Rapports | Inventaire | Inventaire (Intrants valorisés au PMP ; produits finis au coût de revient ; animaux sur pied comptés, non valorisés) |
| Élevage | Couveuse, Soins & Calendrier, Paramètres Élevage | Cycle Couveuse — Suivi d'Incubation · Calendrier de Soins & Infirmerie · Fiche de Rationnement, Intrants de Provende, Numérotation des Bandes et Sujets |
| Pilotage | Dashboard Élevage | Dashboard Élevage — Vue Consolidée |

Autres sorties du poste : le **manuel utilisateur PDF** généré par les tests (`docs/manuel/LogiALVIA-Manuel-Utilisation.pdf`, `GENERER_MANUEL=1 flutter test test/manuel/captures_test.dart`, voir `CLAUDE.md`) ; il n'est pas un export de données.

## 4. L'importation : ce qui existe, noir sur blanc

Recherches effectuées dans le dépôt :

```bash
grep -rniE "importer|import[A-Z(]|FilePicker|file_picker|file_selector" logialvia_app/lib --include=*.dart
grep -rniE "WithFileUploads|type=\"file\"|UploadedFile|->file\(" logialvia_laravel/app logialvia_laravel/resources
grep -n "file_picker\|file_selector\|excel\|csv" logialvia_app/pubspec.yaml
grep -n "maatwebsite\|phpoffice\|league/csv" logialvia_laravel/composer.json
```

Résultat (relevé le 2026-11-11) :
- **Web** : aucun composant d'envoi de fichier (`WithFileUploads`, `<input type="file">`, `UploadedFile`) ; aucune bibliothèque de lecture de tableur dans `composer.json` ; aucun écran « Importation ».
- **Poste** : aucun sélecteur de fichier (`file_picker` / `file_selector` absents de `pubspec.yaml`), aucun lecteur CSV ou XLSX ; les mots « import » rencontrés dans `lib/` sont des instructions Dart `import`, pas une fonction métier.
- Le cahier des charges le dit déjà : `28_` §5 « fonction INEXISTANTE ailleurs » (« À CONCEVOIR », « rien n'est construit ») ; `GUIDE_PORTAGE_VERS_AUTRE_LOGICIEL.md` bloc 21.

### Ce qui ressemble à un import sans en être un

| Mécanisme | Ce que c'est | Limite |
|---|---|---|
| **Restauration d'une sauvegarde** au poste | remet en place une base `.sqlite` générée par le poste, choisie **dans la liste des sauvegardes de l'application** (pas de sélecteur de fichier libre), appliquée au redémarrage, avec copie de sécurité de la base précédente et quatre contrôles préalables (`service_restauration.dart`) | ne lit pas un tableur ; remplace **toute** la base |
| **Semis** du plan comptable, des groupes de taxe, des modules et des paramètres | jeux de données posés par les migrations/seeders (`PlanComptableSeeder`, `GroupesTaxeSeeder`, `ModulesActifsSeeder`, `ParametresEntrepriseSeeder`) ; le plan SYSCOHADA vient de `app/Support/PlanSyscohada.php` (60 comptes, `47p_`) | ne se déclenche pas depuis un fichier fourni par l'utilisateur |
| **Adoption initiale** du poste | au premier cycle de synchronisation, le poste **propose** au serveur son catalogue, ses intrants, ses paramètres d'élevage et son plan (`adopter*SiBesoin`, `47h_` D1) | n'importe rien depuis l'extérieur |
| **Synchronisation** poste ↔ web | échange entre bases de LogiALVIA (`BLUEPRINT_SYNCHRONISATION_POSTES.md`) | pas un import de fichier |
| Fichier `docs/logialvia/syscohada/plan_syscohada_revise_ferme.csv` | source documentaire du plan, comparée aux numéros du code (`47p_` §1) | n'est lu par aucun écran |

### Procédure réelle aujourd'hui pour saisir des données en nombre

1. **Clients, fournisseurs, produits, intrants** : saisie **un par un** dans les écrans Clients, Fournisseurs, Catalogue (`/catalogue`) et Gestion Stocks (`/stocks`) du web, ou du poste. Une création faite au poste voyage ensuite par synchronisation (`clients`, `fournisseurs` : faits ; `produits_vendables`, `intrants` : demandes de référentiel).
2. **Stock initial** : il est **propre à chaque poste** (`47s_`). Au poste, le formulaire du Catalogue journalise un « Stock initial » ; au web, le stock n'existe pas : une correction de stock désigne un **poste de stock** qui l'applique à sa synchronisation suivante (`Catalogue::enregistrerCorrection`, `47s_`).
3. **Reprise d'un historique** (ventes, achats, écritures) : aucun outil ; une écriture se saisit au Journal comptable (opérations diverses) ; pas d'import d'historique.
4. **Sauvegarde avant toute saisie massive** : voir `CLOTURE_EXERCICE_SYSCOHADA.md` §9 pour l'emplacement des sauvegardes.

## 5. Règles de validation réelles à respecter par tout futur import

Un import ne doit **ajouter aucune règle** (principe de `28_` §5) : chaque ligne doit passer par les mêmes contrôles que l'écran. Contrôles relevés dans le code (`app/Sync/Tables/*Table.php`, `app/Sync/DemandesReferentiel.php`, `app/Livewire/Catalogue.php`) :

| Objet | Champ | Règle réelle |
|---|---|---|
| Client | `nom` | obligatoire, texte, 255 car. max (« Le nom du client est obligatoire. ») |
| Client | `telephone` | facultatif, 40 car. max |
| Client | `date_naissance` | facultatif, date valide |
| Fournisseur | `nom` | obligatoire, 255 max |
| Fournisseur | `telephone` | facultatif, 40 max |
| Fournisseur | `adresse`, `fournit` | facultatifs, 255 max |
| Produit vendable | `name` | obligatoire, 255 max |
| Produit vendable | `cat` | obligatoire, 80 max ; le formulaire web propose : Avicole, Commerce Annexe, Cuniculture, Héliciculture, Élevage ovin, Pisciculture (`Catalogue::CATEGORIES`) |
| Produit vendable | `price` | obligatoire, numérique, **> 0** (« Le tarif indicatif doit être supérieur à 0. ») |
| Produit vendable | `price_max` | facultatif, ≥ `price` |
| Produit vendable | `unit` | obligatoire, 40 max ; `u` si vide dans le formulaire web |
| Produit vendable | `cout_revient` | facultatif, ≥ 0 et **≤ `price`** (« Le coût de revient dépasse le tarif indicatif : chaque vente serait à perte. ») |
| Produit vendable | `groupe_taxe` | `A` (Exonéré, 0 %) ou `B` (Taux normal 18 %) d'après `GroupesTaxeSeeder` ; `A` par défaut |
| Produit vendable | `threshold` (seuil d'alerte) | entier ≥ 0 |
| Produit vendable | `espece` (filière) | l'une de `goliaths`, `pintades`, `lapins`, `poissons-chats`, `poulets`, `pondeuses`, `escargots`, `ovins` (`FilieresElevage::LIBELLES`) ; vide autorisé |
| Produit vendable | `sku` | 40 max ; **attribué par le système** à la création (`prochainSku`) |
| Produit vendable | `stock` | **interdit** dans une demande : « Le stock n'est pas synchronisé : il reste propre à chaque poste. » |
| Intrant | `code` | obligatoire, 40 max (clé) |
| Intrant | `name` | obligatoire, 255 max |
| Intrant | `cat` | obligatoire, 80 max ; le formulaire propose : Intrants Provende, Marchandises, Vétérinaire (`GestionStocks::CATEGORIES`) |
| Intrant | `unit` | obligatoire, 40 max ; `kg` par défaut dans le formulaire web |
| Intrant | `threshold` | entier ≥ 0 |
| Intrant | `stock`, `pmp` | **interdits** : propres à chaque poste |

Droits : créer un produit exige `manage-ventes` (`DemandesReferentiel`), un client `manage-ventes`, un fournisseur `manage-achats`, un intrant `manage-stocks` ou `manage-achats` (`DemandesReferentiel::DROITS_PAR_TYPE`). Les doublons : pour `clients` et `fournisseurs`, « doublon de nom signalé, jamais fusionné en silence » (`46_` §2.3) ; pour les produits, la clé est l'UUID (UUID v5 déterministe de `produit:<sku>|<désignation>` pour les produits semés, `46_` §12).

## 6. Modèles de fichiers PROPOSÉS — non implémentés

> **PROPOSITION, NON IMPLÉMENTÉE.** Aucun écran du logiciel ne lit ces fichiers aujourd'hui. Ils servent à **préparer et nettoyer** les données du client (cahiers, tableurs existants) en vue d'une saisie, ou d'un futur assistant d'importation à valider (questions Q-IMP-1 à Q-IMP-3 de `28_` §5). Les colonnes reprennent les champs réels du §5 ; les exemples sont **fictifs**.

Conventions communes proposées :
- Format **XLSX** (cohérent avec les exports du web) ou **CSV UTF-8 avec BOM, séparateur point-virgule** (cohérent avec l'export CSV du poste) ; une feuille par objet, **première ligne = en-têtes exacts** ci-dessous, aucune ligne de titre.
- Dates au format `AAAA-MM-JJ` ; montants en FCFA, entiers, **sans séparateur de milliers** ; téléphones **en texte** (ne pas perdre le zéro initial ni le `+`).
- Une ligne en erreur est refusée avec son numéro et le **motif de la règle réelle du §5**, les autres lignes entrent (principe de `28_` §5).
- Un stock ne s'importe jamais comme une valeur : s'il est fourni, il devient un **mouvement « Stock initial »** attribué à un **poste désigné** (`47s_`).

### 6.1 Clients (`clients.xlsx`, feuille « Clients »)

| Colonne | Obligatoire | Format | Règle |
|---|---|---|---|
| `nom` | oui | texte, 255 max | nom du client |
| `telephone` | non | texte, 40 max | ex. `+22997000000` |
| `date_naissance` | non | `AAAA-MM-JJ` | date valide |

```text
nom;telephone;date_naissance
Restaurant Le Baobab (exemple fictif);+22997000001;
Mme Exemple Dupont (fictif);+22996000002;1985-04-12
```

### 6.2 Fournisseurs (`fournisseurs.xlsx`, feuille « Fournisseurs »)

| Colonne | Obligatoire | Format | Règle |
|---|---|---|---|
| `nom` | oui | texte, 255 max | |
| `telephone` | non | texte, 40 max | |
| `adresse` | non | texte, 255 max | |
| `fournit` | non | texte, 255 max | ce que fournit le fournisseur |

```text
nom;telephone;adresse;fournit
Provenderie Exemple (fictif);+22997000003;Cotonou, zone industrielle;Provende, concentrés
Pharmacie vétérinaire Exemple (fictif);+22996000004;Natitingou;Vaccins, vitamines
```

### 6.3 Catalogue produits (`produits.xlsx`, feuille « Produits »)

| Colonne | Obligatoire | Format | Règle |
|---|---|---|---|
| `designation` | oui | texte, 255 max | champ `name` |
| `categorie` | oui | texte, 80 max | l'une des catégories du formulaire (§5) |
| `filiere` | non | clé de filière | `goliaths`, `pintades`, `lapins`, `poissons-chats`, `poulets`, `pondeuses`, `escargots`, `ovins` |
| `prix` | oui | nombre > 0 | champ `price` |
| `prix_max` | non | nombre ≥ `prix` | fourchette haute |
| `unite` | non | texte, 40 max | `u` si vide |
| `cout_revient` | non | nombre ≥ 0 et ≤ `prix` | |
| `groupe_taxe` | non | `A` ou `B` | `A` par défaut |
| `seuil_alerte` | non | entier ≥ 0 | |
| `stock_initial` | non | nombre | **jamais écrit directement** : mouvement « Stock initial » au poste désigné |
| `poste_stock` | si `stock_initial` | code de poste (`P1`, `P2`…) | `47s_` |

```text
designation;categorie;filiere;prix;prix_max;unite;cout_revient;groupe_taxe;seuil_alerte;stock_initial;poste_stock
Pintade vive (exemple);Avicole;pintades;4500;5500;u;3000;A;10;40;P1
Œufs de pintade, plateau (exemple);Avicole;pintades;2500;;plateau;1800;A;5;12;P1
Poisson-chat vif (exemple);Pisciculture;poissons-chats;2000;;kg;1400;A;20;0;P1
```

Le `sku` n'est pas dans le modèle : il est attribué par le système (`prochainSku`). L'icône est fixée par le système (`category` par défaut au web, `Catalogue.php`).

### 6.4 Intrants (`intrants.xlsx`, feuille « Intrants »)

| Colonne | Obligatoire | Format | Règle |
|---|---|---|---|
| `code` | oui | texte, 40 max, unique | clé de l'intrant |
| `designation` | oui | texte, 255 max | champ `name` |
| `categorie` | oui | texte, 80 max | `Intrants Provende`, `Marchandises` ou `Vétérinaire` (propositions du formulaire) |
| `unite` | non | texte, 40 max | `kg` par défaut au web |
| `seuil_alerte` | non | entier ≥ 0 | |
| `stock_initial` | non | nombre | mouvement « Stock initial » sur un poste (le stock et le PMP **ne sont pas synchronisés**) |
| `pmp_initial` | non | entier ≥ 0 | **à définir** : le PMP est propre au poste ; la façon de l'initialiser est une question ouverte (non traitée dans le code web) |
| `poste_stock` | si `stock_initial` | code de poste | |

```text
code;designation;categorie;unite;seuil_alerte;stock_initial;pmp_initial;poste_stock
MAIS;Maïs grain (exemple);Intrants Provende;kg;200;1500;250;P1
VIT-AD3E;Vitamines AD3E (exemple);Vétérinaire;l;5;12;;P1
```

### 6.5 Points ouverts avant toute implémentation (à trancher avec le client)

1. Faut-il un import **web d'abord, puis poste** (doctrine de `28_` §5) ? Le poste n'a pas de sélecteur de fichier : il faudrait ajouter une dépendance (`28_` §5, « Dépendances »).
2. Origine des données (cahiers, tableurs) et date d'ouverture du stock initial (`28_` Q-IMP-1).
3. Gestion d'un fichier réimporté : idempotence par clé naturelle (`nom` pour clients et fournisseurs, `code` pour intrants, désignation + filière pour produits) et journal d'import (`28_` §5).
4. Initialisation du **PMP** des intrants (§6.4).
5. Les **bandes**, **plan comptable complémentaire** et **barèmes de rationnement** sont cités par `28_` comme modules d'import possibles : aucun modèle n'est proposé ici faute d'avoir été demandé.

## 7. Vérifier ce guide

```bash
grep -rn "ExportXlsx::telecharger" logialvia_laravel/app | wc -l
grep -n "exporterTable\|tablesExportables" logialvia_app/lib/administration/domain/services/service_sauvegarde.dart
grep -rn "BoutonExportPdf(" logialvia_app/lib | grep -v "class " | wc -l
```
