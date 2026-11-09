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
        // Connexion d'un poste : 5 tentatives par minute, par identifiant ET adresse.
        RateLimiter::for('connexion-api', function (Request $request) {
            return Limit::perMinute(5)->by(
                mb_strtolower((string) $request->input('identifiant')).'|'.$request->ip(),
            );
        });
    }
}
