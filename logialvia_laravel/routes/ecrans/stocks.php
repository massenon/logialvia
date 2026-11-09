<?php

use App\Http\Controllers\ImpressionsAchats;
use App\Livewire\GestionStocks;
use App\Support\Ecrans;
use Illuminate\Support\Facades\Route;

Ecrans::declarer('/stocks', GestionStocks::class);

// Journal imprimable (sans stock ni PMP : propres a chaque poste).
Route::get('/stocks/impression', [ImpressionsAchats::class, 'journalStocks'])
    ->middleware(['can:view-stocks', 'ecran.actif:/stocks'])
    ->name('stocks.impression');
