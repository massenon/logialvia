<?php

// Les autres reglages gardent les valeurs de Livewire (config fusionnee).
return [
    /*
     * 47x_ : Livewire et Alpine sont empaquetes par Vite (resources/js/app.js, chunk `vendor-livewire`) ;
     * Livewire n'injecte donc plus son propre <script> bloquant (livewire.min.js, 167 Ko non compresses).
     * Les vues declarent @livewireStyles et @livewireScriptConfig.
     */
    'inject_assets' => false,
];
