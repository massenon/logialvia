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

    /**
     * Fil d'Ariane (Dart `NavigationModel.filDAriane`) : [groupe, ecran], ou [ecran] seul quand le groupe n'a qu'une entree
     * (le Tableau de Bord, comme `dashboard.html` l.29). `[]` hors barre.
     *
     * @return list<string>
     */
    public static function filDAriane(string $route): array
    {
        foreach (config('navigation') as $groupe) {
            foreach ($groupe['entrees'] as $e) {
                if ($e['route'] === $route) {
                    return count($groupe['entrees']) === 1 ? [$e['libelle']] : [self::titreLisible($groupe['titre']), $e['libelle']];
                }
            }
        }

        return [];
    }

    /** « ÉLEVAGE & COUVEUSE » -> « Élevage & Couveuse » (Dart `_titreLisible`). */
    public static function titreLisible(string $titre): string
    {
        return implode(' ', array_map(
            fn (string $mot) => mb_strlen($mot) <= 1 ? $mot : mb_strtoupper(mb_substr($mot, 0, 1)).mb_strtolower(mb_substr($mot, 1)),
            explode(' ', $titre),
        ));
    }

    /**
     * Entrees que le compte peut ouvrir, a plat (recherche globale : Dart `RechercheGlobale`).
     *
     * @return list<array{libelle: string, route: string, icone: string}>
     */
    public static function entreesAccessibles(User $utilisateur): array
    {
        $plat = [];
        foreach (self::pourUtilisateur($utilisateur) as $groupe) {
            foreach ($groupe['entrees'] as $e) {
                $plat[] = ['libelle' => $e['libelle'], 'route' => $e['route'], 'icone' => $e['icone']];
            }
        }

        return $plat;
    }

    /** Le compte peut-il ouvrir cette route, module actif compris ? (acces rapide, barre du bas). */
    public static function accessible(User $utilisateur, string $route): bool
    {
        return self::droitPour($utilisateur, $route) && self::moduleDeRouteActif($route);
    }
}
