<?php

/**
 * Droits et modules de LogiALVIA (web).
 *
 * SOURCE des decisions : `docs/logialvia/20_MODULES_INDEX.md` (matrice RBAC,
 * DV-06, DV-07, DV-15). Le poste Flutter porte sa propre matrice
 * (`permission_service.dart`) ; `tests/Feature/ConformiteDroitsDartTest.php` la
 * compare a celle-ci et ne tolere que les ecarts DECLARES (voir plus bas).
 */

return [

    /*
    | Routes authentifiees du poste = routes du web (37 moins les 3 publiques).
    | route => [permission requise (null = connexion seule), module activable (null = toujours)]
    */
    'routes' => [
        '/dashboard' => [null, null],

        '/elevage/dashboard' => ['view-elevage', null],
        '/elevage/goliaths' => ['view-elevage', null],
        '/elevage/pintades' => ['view-elevage', null],
        '/elevage/lapins' => ['view-elevage', 'cuniculture'],
        '/elevage/poissons-chats' => ['view-elevage', 'pisciculture'],
        '/elevage/escargots' => ['view-elevage', 'heliciculture'],
        '/elevage/bovins' => ['view-elevage', 'bovins'],
        '/elevage/poulets-pondeuses' => ['view-elevage', 'aviculture_classique'],
        '/elevage/couveuse' => ['view-elevage', null],
        '/elevage/mirages' => ['view-elevage', null],
        '/elevage/soins' => ['view-elevage', null],
        '/parametres/elevage' => ['view-elevage', null],

        '/ventes' => ['view-ventes', null],
        '/clients' => ['view-ventes', null],
        '/inventaire' => ['view-stocks', null],
        '/factures-mecef' => ['view-facturation', 'mecef'],

        '/achats' => ['view-achats', null],
        '/fournisseurs' => ['view-achats', null],
        '/depenses' => ['view-achats', null],
        '/stocks' => ['view-stocks', null],
        '/catalogue' => ['view-stocks', null],

        '/comptabilite' => ['view-comptabilite', null],
        '/comptabilite/journal' => ['view-comptabilite', null],
        '/comptabilite/grand-livre' => ['view-comptabilite', null],
        '/comptabilite/balance' => ['view-comptabilite', null],
        '/comptabilite/plan' => ['view-comptabilite', null],
        '/comptabilite/analytique' => ['view-comptabilite', null],
        '/comptabilite/etats-financiers' => ['view-comptabilite', null],
        '/comptabilite/bilan' => ['view-comptabilite', null],
        '/comptabilite/cloture' => ['view-comptabilite', null],

        '/rapports' => ['view-rapports', null],
        '/parametres/generaux' => ['view-parametres', null],

        '/profil' => [null, null],
        '/aide' => [null, null],
        '/contact' => [null, null],
    ],

    /*
    | Modules basculables et fiche associee — miroir de `ModulesActifsSeeder`
    | du poste. Goliaths et Pintades n'y figurent pas : toujours actifs.
    */
    'modules' => [
        'pisciculture' => 'poissons-chats',
        'cuniculture' => 'lapins',
        'aviculture_classique' => 'poulets',
        'heliciculture' => 'escargots',
        'bovins' => 'bovins',
    ],

    /*
    | `mecef` n'est pas un module de filiere : il pilote l'ecran de facturation
    | normalisee. Il suit son propre reglage (parametres_entreprise.mecef_actif).
    */

    /*
    | Roles (DV-07 : 4 roles) et leurs droits. L'administrateur recoit TOUS les
    | droits explicitement : il n'y a pas de `Gate::before` (un droit non seme
    | ne s'ouvre pas tout seul).
    */
    'roles' => [
        'admin' => 'Administrateur',
        'comptable' => 'Comptable',
        'caissier' => 'Agent de Vente',
        'animalier' => "Agent d'Élevage",
    ],

    'permissions' => [
        'view-elevage', 'manage-elevage', 'archive-elevage', 'export-elevage',
        'view-ventes', 'manage-ventes', 'export-ventes',
        'view-achats', 'manage-achats',
        'view-stocks', 'manage-stocks',
        'view-facturation', 'manage-facturation',
        'view-comptabilite', 'manage-comptabilite', 'close-fiscal-year',
        'view-rapports', 'export-rapports',
        'view-parametres', 'manage-parametres', 'manage-users', 'manage-modules',
    ],

    'role_permissions' => [
        // `admin` : voir la boucle du seeder (toutes les permissions).
        'admin' => '*',

        // Celui qui encaisse n'est pas celui qui comptabilise.
        'comptable' => [
            'view-ventes',          // consultation (propose)
            'view-facturation', 'manage-facturation', // (propose)
            'view-achats',          // consultation (propose)
            'view-comptabilite', 'manage-comptabilite',
            'view-rapports', 'export-rapports',
            // close-fiscal-year : admin seul (DV-15), a confirmer (Q-DV-7).
        ],

        // DV-06 : le caissier consulte et reimprime les factures (view), sans
        // annuler ni creer d'avoir (pas de manage-facturation) ; pas d'inventaire
        // (view-stocks), pas de stocks ni de catalogue.
        'caissier' => [
            'view-ventes', 'manage-ventes', 'export-ventes',
            'view-facturation',
        ],

        'animalier' => [
            'view-elevage', 'manage-elevage', 'archive-elevage', 'export-elevage',
        ],
    ],

    /*
    | Synchronisation (`docs/logialvia/46_CONTRAT_SYNCHRONISATION.md`).
    | Les tables sont traitees DANS CET ORDRE (dependances : clients avant ventes...),
    | quel que soit l'ordre du lot recu.
    */
    // Trois verrous (blueprint §6) : bascule, mot de confirmation, audit.
    'remise_a_zero' => [
        'activee' => (bool) env('REMISE_A_ZERO_ACTIVEE', false),
        'mot' => 'REMETTRE A ZERO',
    ],

    'sync' => [
        'tables' => [
            \App\Sync\Tables\ModulesActifsTable::class,
            \App\Sync\Tables\ParametresEntrepriseTable::class,
            \App\Sync\Tables\ProduitsVendablesTable::class,
            \App\Sync\Tables\IntrantsTable::class,
            \App\Sync\Tables\BaremesRationTable::class,
            \App\Sync\Tables\TauxRationPoidsTable::class,
            \App\Sync\Tables\CalendrierProphylaxieTable::class,
            \App\Sync\Tables\ClientsTable::class,
            \App\Sync\Tables\FournisseursTable::class,
            \App\Sync\Tables\VentesTable::class,
            \App\Sync\Tables\GroupesTaxeTable::class,
            \App\Sync\Tables\FacturesTable::class,
            \App\Sync\Tables\AchatsTable::class,
            \App\Sync\Tables\MouvementsIntrantTable::class,
            \App\Sync\Tables\MouvementsProduitTable::class,
            // Elevage, palier 7a (`46a_`) : fiches journalieres, compteurs de ventes du jour, bandes.
            \App\Sync\Tables\FichesJourneeTable::class,
            \App\Sync\Tables\VentesJourTable::class,
            \App\Sync\Tables\BandesTable::class,
            // Couveuse (7b) : les incubateurs AVANT les lots qui les occupent.
            \App\Sync\Tables\MachinesIncubateurTable::class,
            \App\Sync\Tables\CyclesCouveuseTable::class,
            \App\Sync\Tables\SoinsCalendrierTable::class,
            \App\Sync\Tables\InfirmerieTable::class,
        ],
        // Lignes par table et par page de tirage.
        'lignes_par_page' => (int) env('SYNC_LIGNES_PAR_PAGE', 200),
        // Chevauchement du curseur : une ecriture validee juste apres la lecture du
        // tirage precedent est reprise au suivant. Sans danger : tout est idempotent.
        'recouvrement_secondes' => (int) env('SYNC_RECOUVREMENT_SECONDES', 2),
    ],

    /*
    | Fuseau des dates METIER affichees (Natitingou, Benin). Les instants
    | techniques restent stockes en UTC ; on ne convertit qu'a l'affichage.
    */
    'fuseau' => 'Africa/Porto-Novo',

    /*
    | Duree de vie du jeton d'un poste (blueprint : 90 jours).
    */
    'jeton_duree_jours' => (int) env('SANCTUM_EXPIRATION_JOURS', 90),

    /*
    | Premier administrateur (AdminSeeder). Le mot de passe vient de
    | l'environnement, jamais du code.
    */
    'admin' => [
        'username' => env('ADMIN_INITIAL_USERNAME', 'admin'),
        'password' => env('ADMIN_INITIAL_PASSWORD'),
    ],

    /*
    | Ecarts CONNUS et DECLARES entre le poste Flutter et ces decisions : le poste
    | doit etre aligne (`docs/logialvia/45_` §4b). Le test de conformite des
    | droits ne tolere QUE ceux-la.
    | role => routes que le poste autorise encore a tort.
    */
    'ecarts_poste_connus' => [
        'caissier' => ['/inventaire'],
    ],
];
