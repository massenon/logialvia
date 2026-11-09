<?php

use App\Http\Controllers\ImpressionsCommerce;
use Illuminate\Support\Facades\Route;

// Vues imprimables du commerce (`ImpressionsCommerce`). Droit ET module verifies ici, comme `Ecrans::declarer`.
Route::get('/impression/ventes/historique', [ImpressionsCommerce::class, 'historique'])
    ->middleware(['can:export-ventes', 'ecran.actif:/ventes'])->name('ventes.historique.imprimer');
Route::get('/impression/ventes/{vente}/facture', [ImpressionsCommerce::class, 'facture'])
    ->middleware(['can:view-ventes', 'ecran.actif:/ventes'])->name('ventes.facture');
Route::get('/impression/clients/creances', [ImpressionsCommerce::class, 'creances'])
    ->middleware(['can:export-ventes', 'ecran.actif:/clients'])->name('clients.creances.imprimer');
Route::get('/impression/clients/relance/{vente}', [ImpressionsCommerce::class, 'relance'])
    ->middleware(['can:view-ventes', 'ecran.actif:/clients'])->name('clients.relance');
