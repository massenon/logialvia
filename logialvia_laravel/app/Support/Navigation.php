<?php

namespace App\Support;

use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\User;

/**
 * Barre laterale du web (`config/navigation.php`, transcrite du Dart).
 *
 * Une entree est visible quand le compte a le DROIT de sa route (matrice de
 * `config/logialvia.php`) ET que son module est actif (Doc I2 §3). Un groupe sans
 * entree visible disparait. Le droit n'est jamais seulement masque : chaque route le
 * reverifie (`routes/web.php`).
 */
class Navigation
{
    /** @return list<array{titre: string, entrees: list<array<string, mixed>>}> */
    public static function pourUtilisateur(User $utilisateur): array
    {
        $modules = ModuleActif::query()->pluck('is_actif', 'module_id');
        $mecef = (bool) ParametresEntreprise::courant()->mecef_actif;
        $groupes = [];

        foreach (config('navigation') as $groupe) {
            $entrees = array_values(array_filter(
                $groupe['entrees'],
                fn (array $e) => self::droitPour($utilisateur, $e['route'])
                    && self::moduleActif($e['module'], $modules, $mecef),
            ));

            if ($entrees !== []) {
                $groupes[] = ['titre' => $groupe['titre'], 'entrees' => $entrees];
            }
        }

        return $groupes;
    }

    public static function droitPour(User $utilisateur, string $route): bool
    {
        $permission = Droits::routes()[$route][0] ?? null;

        return $permission === null || $utilisateur->can($permission);
    }

    /** Le module d'une route est-il actif ? `null` = toujours. */
    public static function moduleDeRouteActif(string $route): bool
    {
        $module = Droits::routes()[$route][1] ?? null;

        return self::moduleActif(
            $module,
            ModuleActif::query()->pluck('is_actif', 'module_id'),
            (bool) ParametresEntreprise::courant()->mecef_actif,
        );
    }

    private static function moduleActif(?string $module, $modules, bool $mecef): bool
    {
        if ($module === null) {
            return true;
        }

        return $module === 'mecef' ? $mecef : (bool) ($modules[$module] ?? false);
    }

    /** Libelle de la route pour le fil d'Ariane / le titre (`null` si hors barre). */
    public static function libelle(string $route): ?string
    {
        foreach (config('navigation') as $groupe) {
            foreach ($groupe['entrees'] as $e) {
                if ($e['route'] === $route) {
                    return $e['libelle'];
                }
            }
        }

        return null;
    }
}
