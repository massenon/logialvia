<?php

namespace App\Support;

/**
 * Lecture de la matrice de droits (`config/logialvia.php`).
 *
 * Un seul endroit sait quelles routes un role peut ouvrir : les tests de
 * conformite, puis les middlewares des ecrans, l'utiliseront tous.
 */
class Droits
{
    /** @return array<string, array{0: ?string, 1: ?string}> */
    public static function routes(): array
    {
        return config('logialvia.routes');
    }

    /** @return list<string> Toutes les permissions du role. */
    public static function permissionsDuRole(string $role): array
    {
        $droits = config("logialvia.role_permissions.$role");

        if ($droits === '*') {
            return config('logialvia.permissions');
        }

        return $droits ?? [];
    }

    /**
     * Routes qu'un role peut ouvrir (hors filtre des modules actifs).
     *
     * @return list<string>
     */
    public static function routesAutorisees(string $role): array
    {
        $permissions = self::permissionsDuRole($role);
        $autorisees = [];

        foreach (self::routes() as $route => [$permission]) {
            if ($permission === null || in_array($permission, $permissions, true)) {
                $autorisees[] = $route;
            }
        }

        return $autorisees;
    }
}
