<?php

use App\Http\Controllers\ImpressionsAchats;
use App\Livewire\Fournisseurs;
use App\Support\Ecrans;
use Illuminate\Support\Facades\Route;

Ecrans::declarer('/fournisseurs', Fournisseurs::class);

// Vues imprimables : fournisseurs & dettes (PDF du poste) et releve d'un fournisseur.
Route::middleware(['can:view-achats', 'ecran.actif:/fournisseurs'])->group(function () {
    Route::get('/fournisseurs/impression', [ImpressionsAchats::class, 'fournisseurs'])->name('fournisseurs.impression');
    Route::get('/fournisseurs/{fournisseur}/releve', [ImpressionsAchats::class, 'releve'])->name('fournisseurs.releve');
});
