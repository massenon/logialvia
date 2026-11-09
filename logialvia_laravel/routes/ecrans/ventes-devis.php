<?php

use App\Livewire\Devis;
use Illuminate\Support\Facades\Route;

// `47a2_` : onglet « Devis Prestations » de l'ecran Ventes. Volontairement HORS de `Ecrans::declarer` et de
// la matrice `config/logialvia.php` : cette matrice doit rester egale aux routes du poste (conformite Dart),
// et le poste n'a pas de route a part pour cet onglet. Meme droit que `/ventes` : `view-ventes`.
Route::get('/ventes/devis', Devis::class)->middleware('can:view-ventes')->name('ventes.devis');
