<?php

namespace App\Support;

use Illuminate\Support\Facades\Route;

/**
 * Registre des ecrans web convertis du Dart.
 *
 * Chaque ecran vit dans SON fichier `routes/ecrans/<nom>.php` (charge par `routes/web.php`)
 * et s'y declare avec `Ecrans::declarer('/route', Composant::class)`. Le droit de la route
 * (matrice `config/logialvia.php`) ET son module actif sont poses ici, jamais oublies.
 * Les routes du poste non declarees gardent la page « bientot ».
 * Un fichier par ecran : plusieurs personnes (ou agents) peuvent convertir des ecrans en
 * parallele sans toucher aux memes lignes.
 */
class Ecrans
{
    /** @var array<string, string> route => composant */
    private static array $declarees = [];

    /** @param class-string $composant Composant Livewire plein ecran. */
    public static function declarer(string $route, string $composant): void
    {
        abort_unless(array_key_exists($route, Droits::routes()), 500, "Route inconnue de la matrice des droits : $route");

        [$permission] = Droits::routes()[$route];
        self::$declarees[$route] = $composant;

        Route::get($route, $composant)
            ->middleware(array_filter([
                $permission ? "can:$permission" : null,
                'ecran.actif:'.$route,
            ]))
            ->name('ecran.'.ltrim($route, '/'));
    }

    /** @return list<string> */
    public static function declarees(): array
    {
        return array_keys(self::$declarees);
    }

    public static function oublier(): void
    {
        self::$declarees = [];
    }
}
