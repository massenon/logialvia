<?php

use App\Http\Controllers\ImpressionsAchats;
use App\Livewire\Depenses;
use App\Support\Ecrans;
use Illuminate\Support\Facades\Route;

Ecrans::declarer('/depenses', Depenses::class);

// Etat imprimable des depenses (PDF du poste) : meme lecture que l'export, droit de lire la comptabilite.
Route::get('/depenses/impression', [ImpressionsAchats::class, 'depenses'])
    ->middleware(['can:view-comptabilite', 'ecran.actif:/depenses'])
    ->name('depenses.impression');
