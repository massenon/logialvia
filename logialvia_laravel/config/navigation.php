<?php

/**
 * Barre laterale de LogiALVIA — transcription du poste Flutter
 * (`logialvia_app/lib/core/router/navigation_model.dart`, lui-meme issu de `sidebar.js`).
 * `tests/Feature/ConformiteNavigationDartTest.php` compare ce fichier au Dart : ordre,
 * libelles, routes, modules et groupes de roles. Ne pas modifier d'un seul cote.
 */

return [
    [
        'titre' => 'PILOTAGE',
        'roles' => ['admin', 'animalier', 'caissier'],
        'entrees' => [
            ['libelle' => 'Tableau de Bord', 'icone' => 'dashboard', 'route' => '/dashboard', 'module' => null],
        ],
    ],
    [
        'titre' => 'ÉLEVAGE & COUVEUSE',
        'roles' => ['admin', 'animalier'],
        'entrees' => [
            ['libelle' => 'Cycle Couveuse', 'icone' => 'egg', 'route' => '/elevage/couveuse', 'module' => null],
            ['libelle' => 'Statistiques Mirages', 'icone' => 'visibility', 'route' => '/elevage/mirages', 'module' => null],
            ['libelle' => 'Fiche Goliaths', 'icone' => 'pets', 'route' => '/elevage/goliaths', 'module' => null],
            ['libelle' => 'Fiche Pintades', 'icone' => 'pets', 'route' => '/elevage/pintades', 'module' => null],
            ['libelle' => 'Fiche Poissons-Chats', 'icone' => 'set_meal', 'route' => '/elevage/poissons-chats', 'module' => 'pisciculture'],
            ['libelle' => 'Fiche Lapins', 'icone' => 'cruelty_free', 'route' => '/elevage/lapins', 'module' => 'cuniculture'],
            ['libelle' => 'Fiche Escargots', 'icone' => 'eco', 'route' => '/elevage/escargots', 'module' => 'heliciculture'],
            ['libelle' => 'Fiche Ovins', 'icone' => 'grass', 'route' => '/elevage/ovins', 'module' => 'ovins'],
            ['libelle' => 'Fiche Poulets/Pondeuses', 'icone' => 'egg_alt', 'route' => '/elevage/poulets-pondeuses', 'module' => 'aviculture_classique'],
            ['libelle' => 'Dashboard Élevage', 'icone' => 'monitoring', 'route' => '/elevage/dashboard', 'module' => null],
            ['libelle' => 'Paramètres Élevage', 'icone' => 'tune', 'route' => '/parametres/elevage', 'module' => null],
            ['libelle' => 'Soins & Calendrier', 'icone' => 'vaccines', 'route' => '/elevage/soins', 'module' => null],
        ],
    ],
    [
        'titre' => 'VENTES & CLIENTS',
        'roles' => ['admin', 'caissier'],
        'entrees' => [
            ['libelle' => 'Ventes', 'icone' => 'point_of_sale', 'route' => '/ventes', 'module' => null],
            ['libelle' => 'Clients et Créances', 'icone' => 'payments', 'route' => '/clients', 'module' => null],
            ['libelle' => 'Inventaire', 'icone' => 'inventory', 'route' => '/inventaire', 'module' => null],
            ['libelle' => 'Facturation MeCeF', 'icone' => 'receipt_long', 'route' => '/factures-mecef', 'module' => 'mecef'],
        ],
    ],
    [
        'titre' => 'ACHATS & FOURNISSEURS',
        'roles' => ['admin'],
        'entrees' => [
            ['libelle' => 'Achats & Commandes', 'icone' => 'local_shipping', 'route' => '/achats', 'module' => null],
            ['libelle' => 'Fournisseurs', 'icone' => 'contact_page', 'route' => '/fournisseurs', 'module' => null],
            ['libelle' => 'Saisie Dépenses', 'icone' => 'receipt', 'route' => '/depenses', 'module' => null],
        ],
    ],
    [
        'titre' => 'STOCKS & CATALOGUE',
        'roles' => ['admin'],
        'entrees' => [
            ['libelle' => 'Gestion Stocks', 'icone' => 'inventory_2', 'route' => '/stocks', 'module' => null],
            ['libelle' => 'Catalogue & Seuils', 'icone' => 'category', 'route' => '/catalogue', 'module' => null],
        ],
    ],
    [
        'titre' => 'COMPTABILITÉ',
        'roles' => ['admin'],
        'entrees' => [
            ['libelle' => 'Comptabilité', 'icone' => 'account_balance', 'route' => '/comptabilite', 'module' => null],
            ['libelle' => 'Grand Livre', 'icone' => 'import_contacts', 'route' => '/comptabilite/grand-livre', 'module' => null],
            ['libelle' => 'Balance Générale', 'icone' => 'balance', 'route' => '/comptabilite/balance', 'module' => null],
            ['libelle' => 'États Financiers', 'icone' => 'description', 'route' => '/comptabilite/etats-financiers', 'module' => null],
            ['libelle' => 'Bilan de l\'Entreprise', 'icone' => 'account_balance_wallet', 'route' => '/comptabilite/bilan', 'module' => null],
        ],
    ],
    [
        'titre' => 'PARAMÈTRES',
        'roles' => ['admin'],
        'entrees' => [
            ['libelle' => 'Paramètres Général', 'icone' => 'settings', 'route' => '/parametres/generaux', 'module' => null],
        ],
    ],
    [
        'titre' => 'ÉDITIONS',
        'roles' => ['admin'],
        'entrees' => [
            ['libelle' => 'Rapports & États', 'icone' => 'picture_as_pdf', 'route' => '/rapports', 'module' => null],
        ],
    ],
];
