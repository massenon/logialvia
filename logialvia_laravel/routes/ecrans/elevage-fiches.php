<?php

use App\Livewire\FicheEspece;
use App\Support\Ecrans;

// Les 7 routes `/elevage/<filiere>` partagent UN composant (Dart : `FicheEspeceScreen`,
// Strict Avoid §5) ; `/elevage/poulets-pondeuses` porte deux onglets.
foreach (array_keys(FicheEspece::ROUTES) as $route) {
    Ecrans::declarer($route, FicheEspece::class);
}
