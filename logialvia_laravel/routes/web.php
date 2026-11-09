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
        Route::redirect('/', '/dashboard')->name('accueil');

        // Chaque route du poste a son adresse ici. Tant qu'un ecran n'est pas converti, la
        // page « bientot » la tient : droit ET module restent verifies des maintenant.
        foreach (array_keys(config('logialvia.routes')) as $route) {
            if (in_array($route, config('logialvia.routes_web_implementees', []), true)) {
                continue;
            }
            [$permission] = config('logialvia.routes')[$route];
            Route::get($route, function () use ($route) {
                abort_unless(\App\Support\Navigation::moduleDeRouteActif($route), 404);

                return view('a-venir', ['titre' => \App\Support\Navigation::libelle($route) ?? 'Écran']);
            })->middleware($permission ? "can:$permission" : [])->name('a-venir.'.ltrim($route, '/'));
        }

        // Ecran web propre au serveur : l'onglet « Postes & Appairage » des Parametres.
        Route::get('/parametres/postes', PostesAppairage::class)
            ->middleware('can:manage-users')
            ->name('postes');
    });
});
