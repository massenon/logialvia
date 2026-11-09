<?php

namespace App\Support;

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
                    ['Reproducteur', 110, false, false],
                ],
                'etapes' => ['Naissance', 'Chair', 'Reproducteur'],
                'libelle_achats' => 'Achats', 'libelle_naissances' => 'Nés (Mise bas)',
            ],
            'poissons-chats' => [
                'libelle' => 'Poissons-Chats', 'icone' => 'set_meal', 'route' => '/elevage/poissons-chats',
                'categories' => [
                    ['Alevin', 30, true, false],
                    ['Juvénile', 60, false, true],
                    ['Mature', 110, false, false],
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
                'libelle' => 'Bovins', 'icone' => 'agriculture', 'route' => '/elevage/bovins',
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
}
