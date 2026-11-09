<?php

use App\Livewire\Auth\ChangerMotDePasse;
use App\Livewire\Auth\Connexion;
use App\Livewire\PostesAppairage;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route;

// Invites : connexion.
Route::get('/login', Connexion::class)->middleware('guest')->name('login');

Route::post('/deconnexion', function () {
    Auth::logout();
    request()->session()->invalidate();
    request()->session()->regenerateToken();

    return redirect()->route('login');
})->middleware('auth')->name('deconnexion');

// Connectes. Un mot de passe temporaire ne laisse ouverte que son changement.
Route::middleware('auth')->group(function () {
    Route::get('/mot-de-passe', ChangerMotDePasse::class)->name('mot-de-passe');

    Route::middleware('mdp.web')->group(function () {
        Route::view('/', 'accueil')->name('accueil');

        // Ecran web propre au serveur : l'onglet « Postes & Appairage » des Parametres.
        Route::get('/parametres/postes', PostesAppairage::class)
            ->middleware('can:manage-users')
            ->name('postes');
    });
});
