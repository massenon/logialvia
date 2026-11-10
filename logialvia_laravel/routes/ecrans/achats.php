<?php

use App\Http\Controllers\ImpressionsAchats;
use App\Livewire\Achats;
use App\Support\Ecrans;
use Illuminate\Support\Facades\Route;

Ecrans::declarer('/achats', Achats::class);

// Vues imprimables (equivalent des PDF du poste) : lecture seule, meme droit et meme module que l'ecran.
Route::middleware(['can:view-achats', 'ecran.actif:/achats'])->group(function () {
    Route::get('/achats/impression', [ImpressionsAchats::class, 'historique'])->name('achats.impression');
    Route::get('/achats/{achat}/bon', [ImpressionsAchats::class, 'bonDeCommande'])->name('achats.bon');
});
