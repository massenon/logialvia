<?php

namespace App\Support;

use App\Models\ModuleActif;

/**
 * Les 8 filieres d'elevage et leur configuration — TRANSCRITE de
 * `lib/elevage/domain/entities/configuration_espece.dart` (le Dart est la source) et
 * comparee a lui par `ConformiteFilieresDartTest`.
 *
 * Une categorie : [libelle, ration en g/jour, recoit achats et naissances, deduite des ventes].
 */
final class FilieresElevage
{
    /** @return array<string, array<string, mixed>> */
    public static function toutes(): array
    {
        return [
            'goliaths' => [
                'libelle' => 'Goliaths', 'icone' => 'pets', 'route' => '/elevage/goliaths',
                'categories' => [
                    ['Poussins', 30, true, false],
                    ['Goliathau', 60, false, true],
                    ['Mature', 110, false, false],
                ],
                'etapes' => ['Naissance (Couveuse)', 'Goliathau (0 → 4 mois)', 'Mature (≥ 4 mois, ≥ 2,8 kg) — Éligible à la Vente'],
                'libelle_achats' => 'Achats', 'libelle_naissances' => 'Nés (Couveuse)',
            ],
            'pintades' => [
                'libelle' => 'Pintades', 'icone' => 'pets', 'route' => '/elevage/pintades',
                'categories' => [
                    ['Poussins', 30, true, false],
                    ['Pintadau', 60, false, true],
                    ['Mature', 110, false, false],
                ],
                'etapes' => ['Naissance (Couveuse)', 'Pintadau (0 → 4 mois)', 'Mature — Éligible à la Vente'],
                'libelle_achats' => 'Achats', 'libelle_naissances' => 'Nés (Couveuse)',
            ],
            'lapins' => [
                'libelle' => 'Lapins', 'icone' => 'cruelty_free', 'route' => '/elevage/lapins',
                'categories' => [
                    ['Lapereau', 30, true, false],
                    ['Chair', 60, false, true],
                    ['Reproducteur', 120, false, false],
                ],
                'etapes' => ['Naissance', 'Chair', 'Reproducteur'],
                'libelle_achats' => 'Achats', 'libelle_naissances' => 'Nés (Mise bas)',
            ],
            'poissons-chats' => [
                'libelle' => 'Poissons-Chats', 'icone' => 'set_meal', 'route' => '/elevage/poissons-chats',
                'categories' => [
                    ['Alevin', 1, true, false],
                    ['Juvénile', 3, false, true],
                    ['Mature', 8, false, false],
                ],
                'etapes' => ['Alevin', 'Juvénile', 'Mature'],
                'libelle_achats' => 'Achats', 'libelle_naissances' => 'Nés',
            ],
            'poulets' => [
                'libelle' => 'Poulets', 'icone' => 'egg_alt', 'route' => '/elevage/poulets-pondeuses',
                'categories' => [
                    ['Poussin', 30, true, false],
                    ['Poulette', 60, false, true],
                    ['Adulte', 110, false, false],
                ],
                'etapes' => ['Poussin', 'Poulette', 'Adulte'],
                'libelle_achats' => 'Achats', 'libelle_naissances' => 'Nés / Transferts',
            ],
            'pondeuses' => [
                'libelle' => 'Pondeuses', 'icone' => 'egg', 'route' => '/elevage/poulets-pondeuses',
                'categories' => [
                    ['Poussin Ponte', 30, true, false],
                    ['Poussin Croissance', 60, false, false],
                    ['Poulette', 80, false, false],
                    ['Pondeuse', 110, false, true],
                ],
                'etapes' => ['Poussin Ponte', 'Poussin Croissance', 'Poulette', 'Pondeuse'],
                'libelle_achats' => 'Achats / Entrées', 'libelle_naissances' => 'Nés / Transferts',
            ],
            'escargots' => [
                'libelle' => 'Escargots', 'icone' => 'eco', 'route' => '/elevage/escargots',
                'categories' => [
                    ['Naissain', 1, true, false],
                    ['Marchand', 5, false, true],
                    ['Reproducteur', 8, false, false],
                ],
                'etapes' => ['Ponte et éclosion', 'Naissain', 'Marchand (≈ 6 à 8 mois, ≈ 100 g) — Éligible à la Vente', 'Reproducteur'],
                'libelle_achats' => 'Achats', 'libelle_naissances' => 'Nés (Éclosions)',
            ],
            'bovins' => [
                'libelle' => 'Bovins', 'icone' => 'grass', 'route' => '/elevage/bovins',
                'categories' => [
                    ['Veau', 1500, true, false],
                    ['Embouche', 7000, false, true],
                    ['Reproducteur', 9000, false, false],
                ],
                'etapes' => ['Naissance (vêlage)', 'Veau (0 → 6 mois)', 'Embouche (≥ 250 kg ou 24 mois) — Éligible à la Vente', 'Reproducteur'],
                'libelle_achats' => 'Achats', 'libelle_naissances' => 'Nés (Vêlage)',
            ],
        ];
    }

    /**
     * Autres intitules sous lesquels le BAREME d'une categorie peut avoir ete seme (`47e_`) :
     * transcrit de `CategorieEspece.stadesEquivalents` du Dart. Sans cela, une ration modifiee
     * pour « Sevre / Lapereaux » ou « Alevins » (stade seme a tort pour la pintade) restait sans
     * effet sur la provende.
     */
    public const STADES_EQUIVALENTS = [
        'pintades' => ['Poussins' => ['Alevins']],
        'lapins' => ['Lapereau' => ['Sevré / Lapereaux'], 'Chair' => ['Chair / Jeune']],
    ];

    /** Filieres rationnees en % du poids vif (matiere seche) : `rationEnPourcentagePoidsVif` du Dart. */
    public const RATION_AU_POIDS_VIF = ['poissons-chats', 'bovins'];

    /** @return list<string> Les identifiants, dans l'ordre du Dart. */
    public static function identifiants(): array
    {
        return array_keys(self::toutes());
    }

    public static function existe(mixed $espece): bool
    {
        return is_string($espece) && array_key_exists($espece, self::toutes());
    }

    /** @return array<string, mixed> */
    public static function configuration(string $espece): array
    {
        return self::toutes()[$espece];
    }

    public static function nombreCategories(string $espece): int
    {
        return count(self::configuration($espece)['categories']);
    }

    /** Les 8 filieres du poste : identifiant => libelle. */
    public const LIBELLES = [
        'goliaths' => 'Goliaths',
        'pintades' => 'Pintades',
        'lapins' => 'Lapins',
        'poissons-chats' => 'Poissons-Chats',
        'poulets' => 'Poulets',
        'pondeuses' => 'Pondeuses',
        'escargots' => 'Escargots',
        'bovins' => 'Bovins',
    ];

    /** Les 6 filieres de « Parametres Elevage » (`EspecesParametrables`). */
    public const PARAMETRABLES = ['goliaths', 'pintades', 'lapins', 'poissons-chats', 'escargots', 'bovins'];

    /** Filieres rationnees sur le poids vif : espece => [unite, grammes par unite, taux max en %]. */
    public const POIDS_VIF = [
        'bovins' => ['kg', 1000, 10.0],
        'poissons-chats' => ['g', 1, 25.0],
    ];

    /** Module activable => filieres qu'il ouvre (Goliaths et Pintades : toujours actives). */
    private const MODULES = [
        'pisciculture' => ['poissons-chats'],
        'cuniculture' => ['lapins'],
        'heliciculture' => ['escargots'],
        'bovins' => ['bovins'],
        'aviculture_classique' => ['poulets', 'pondeuses'],
    ];

    public static function libelle(string $espece): string
    {
        return self::LIBELLES[$espece] ?? $espece;
    }

    /** @return list<string> Filieres dont le module est actif (Goliaths et Pintades toujours). */
    public static function actives(): array
    {
        $modules = ModuleActif::query()->pluck('is_actif', 'module_id');
        $actives = ['goliaths', 'pintades'];
        foreach (self::MODULES as $module => $filieres) {
            if ($modules[$module] ?? false) {
                array_push($actives, ...$filieres);
            }
        }

        return array_values(array_intersect(array_keys(self::LIBELLES), $actives));
    }

    /** @return array<string, string> Filieres actives parmi celles de « Parametres Elevage ». */
    public static function parametrablesActives(): array
    {
        $actives = self::actives();

        return collect(self::PARAMETRABLES)
            ->filter(fn (string $e) => in_array($e, $actives, true))
            ->mapWithKeys(fn (string $e) => [$e => self::LIBELLES[$e]])
            ->all();
    }

    /**
     * UUID DETERMINISTE (version 5, SHA-1) calcule comme `uuidDeterministe` du poste :
     * meme cle, meme identifiant sur tous les postes ET sur le web.
     */
    public static function uuidDeterministe(string $cle): string
    {
        $octets = substr(sha1('logialvia:'.$cle, true), 0, 16);
        $octets[6] = chr((ord($octets[6]) & 0x0F) | 0x50);
        $octets[8] = chr((ord($octets[8]) & 0x3F) | 0x80);
        $hex = bin2hex($octets);

        return substr($hex, 0, 8).'-'.substr($hex, 8, 4).'-'.substr($hex, 12, 4).'-'.substr($hex, 16, 4).'-'.substr($hex, 20);
    }

    public static function idBareme(string $espece, string $stade): string
    {
        return self::uuidDeterministe("bareme_ration:$espece|$stade");
    }

    public static function idTaux(string $espece, int $poidsMinG): string
    {
        return self::uuidDeterministe("taux_ration_poids:$espece|$poidsMinG");
    }
}
