<?php

namespace App\Providers;

use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Un compte desactive ne garde pas la main sur une page deja ouverte : chaque appel Livewire
        // repasse par la verification du compte (`CompteActifWeb`, doc 47u).
        \Livewire\Livewire::addPersistentMiddleware([\App\Http\Middleware\CompteActifWeb::class]);

        // Cloche de la barre du haut : les alertes du compte (mêmes sources et mêmes droits que le tableau de bord).
        \Illuminate\Support\Facades\View::composer('components.layouts.app', function ($vue) {
            $utilisateur = \Illuminate\Support\Facades\Auth::user();
            if ($utilisateur !== null) {
                $vue->with('alertesBarre', app(\App\Services\TableauBordService::class)->alertesPourCompte($utilisateur));
            }
        });

        // Connexion d'un poste : 5 tentatives par minute, par identifiant ET adresse.
        RateLimiter::for('connexion-api', function (Request $request) {
            return Limit::perMinute(5)->by(
                mb_strtolower((string) $request->input('identifiant')).'|'.$request->ip(),
            );
        });
    }
}
