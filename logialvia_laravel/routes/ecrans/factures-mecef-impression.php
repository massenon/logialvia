<?php

use App\Http\Controllers\FactureImprimableController;
use Illuminate\Support\Facades\Route;

// `47a2_` : vue imprimable d'une facture ou d'un avoir. Hors `Ecrans::declarer` (la matrice des droits reste egale aux
// routes du poste) ; meme droit et meme module que `/factures-mecef`.
Route::get('/factures-mecef/{facture}/imprimer', FactureImprimableController::class)
    ->middleware(['can:view-facturation', 'ecran.actif:/factures-mecef'])
    ->name('factures-mecef.imprimer');
