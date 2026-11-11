<?php

// Les autres reglages gardent les valeurs de Livewire (config fusionnee).
return [
    /*
     * 47x_ : Livewire et Alpine sont empaquetes par Vite (resources/js/app.js, chunk `vendor-livewire`) ;
     * Livewire n'injecte donc plus son propre <script> bloquant (livewire.min.js, 167 Ko non compresses).
     * Les vues declarent @livewireStyles et @livewireScriptConfig.
     */
    'inject_assets' => false,

    /*
     * Navigation sans rechargement (`wire:navigate`, liens internes des vues) : la page suivante est prechargee au
     * survol, puis le contenu est echange sans recharger le CSS, le JS ni les polices. Barre de progression doree
     * si la reponse du serveur tarde.
     */
    'navigate' => [
        'show_progress_bar' => true,
        'progress_bar_color' => '#B58B2A',
    ],
];
