<?php

namespace App\Providers;

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
        // Navigation sans rechargement (wire:navigate) : si un deploiement change les fichiers du build, la page
        // suivante est chargee en entier au lieu de melanger d'anciens et de nouveaux fichiers.
        \Illuminate\Support\Facades\Vite::useScriptTagAttributes(['data-navigate-track' => 'reload']);
        \Illuminate\Support\Facades\Vite::useStyleTagAttributes(['data-navigate-track' => 'reload']);

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
    }
}
