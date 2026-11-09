<?php

namespace App\Support;

/**
 * Reperes zootechniques — PORT de `reperes_zootechniques.dart` (le Dart est la source ;
 * `ConformiteReperesDartTest` relit les constantes du Dart). Seuils de mortalite DV-13
 * (recommandes, a confirmer avec le technicien) : comparaisons STRICTES.
 */
final class ReperesZootechniques
{
    public const NORMAL = 'normal';

    public const AVERTISSEMENT = 'avertissement';

    public const CRITIQUE = 'critique';

    public const MORTALITE_JOUR_AVERTISSEMENT = 1.0;

    public const MORTALITE_JOUR_CRITIQUE = 2.0;

    public const MORTALITE_CUMUL_AVERTISSEMENT = 10.0;

    public const MORTALITE_CUMUL_CRITIQUE = 20.0;

    public const TAUX_PONTE_EXCEPTIONNEL = 96.0;

    public const PART_OEUFS_CASSES_A_VERIFIER = 10.0;

    public const MIRAGE_1_AU_PLUS_TOT = 5;

    public const MIRAGE_2_AU_PLUS_TOT = 12;

    public const ECLOSION_AVANCE_MAXIMALE_JOURS = 4;

    /** Durees d'incubation de reference (volailles), en jours. */
    public const DUREES_INCUBATION_JOURS = [
        'poule' => 21, 'goliath' => 21, 'pintade' => 28, 'canard' => 28,
        'canard de Barbarie' => 35, 'dinde' => 28, 'oie' => 30, 'caille' => 17,
    ];

    public static function niveauMortaliteJour(float $tauxPourcent): string
    {
        return $tauxPourcent > self::MORTALITE_JOUR_CRITIQUE ? self::CRITIQUE
            : ($tauxPourcent > self::MORTALITE_JOUR_AVERTISSEMENT ? self::AVERTISSEMENT : self::NORMAL);
    }

    public static function niveauMortaliteCumul(float $tauxPourcent): string
    {
        return $tauxPourcent > self::MORTALITE_CUMUL_CRITIQUE ? self::CRITIQUE
            : ($tauxPourcent > self::MORTALITE_CUMUL_AVERTISSEMENT ? self::AVERTISSEMENT : self::NORMAL);
    }

    /**
     * Taux cumule (%) = morts / (effectif de depart + entrees) : l'effectif EXPOSE au risque.
     * `null` sans effectif expose (« — », jamais « 0 % »).
     */
    public static function tauxMortaliteCumule(int $morts, int $effectifDepart, int $entrees): ?float
    {
        $base = $effectifDepart + $entrees;

        return $base <= 0 ? null : $morts / $base * 100;
    }

    /** Gain moyen quotidien (g/jour/sujet) ; `null` si l'intervalle n'est pas strictement positif. */
    public static function gmqGrammesParJour(float $poidsMoyenInitialG, float $poidsMoyenFinalG, int $jours): ?float
    {
        return $jours <= 0 ? null : ($poidsMoyenFinalG - $poidsMoyenInitialG) / $jours;
    }

    /** Indice de consommation = aliment / gain de poids ; `null` sans gain strictement positif. */
    public static function indiceConsommation(float $alimentConsomme, float $gainPoidsTotal): ?float
    {
        return $gainPoidsTotal <= 0 ? null : $alimentConsomme / $gainPoidsTotal;
    }

    /**
     * GMQ d'une filiere sur ses pesees : entre la premiere et la derniere (poids moyen = pesee /
     * effectif), sur au moins deux jours distincts ; `null` sinon (jamais une courbe inventee).
     *
     * @param  list<array{date: string, poids_total_g: int, effectif: int}>  $pesees
     * @return array{gmq: float, poids_initial_g: float, poids_final_g: float, jours: int}|null
     */
    public static function gmqSurPesees(array $pesees): ?array
    {
        $valides = array_values(array_filter($pesees, fn (array $p) => $p['poids_total_g'] > 0 && $p['effectif'] > 0));
        usort($valides, fn (array $a, array $b) => strcmp($a['date'], $b['date']));
        if (count($valides) < 2) {
            return null;
        }
        $premiere = $valides[0];
        $derniere = $valides[count($valides) - 1];
        $jours = (int) \Carbon\CarbonImmutable::createFromFormat('!Y-m-d', $premiere['date'])
            ->diffInDays(\Carbon\CarbonImmutable::createFromFormat('!Y-m-d', $derniere['date']), false);
        $debut = $premiere['poids_total_g'] / $premiere['effectif'];
        $fin = $derniere['poids_total_g'] / $derniere['effectif'];
        $gmq = self::gmqGrammesParJour($debut, $fin, $jours);

        return $gmq === null ? null : ['gmq' => $gmq, 'poids_initial_g' => $debut, 'poids_final_g' => $fin, 'jours' => $jours];
    }

    /** @return array{min: int, max: int} Fourchette du poids MOYEN d'un sujet, en grammes. */
    public static function poidsMoyenPlausibleG(string $espece): array
    {
        return match ($espece) {
            'goliaths' => ['min' => 30, 'max' => 6000],
            'pintades' => ['min' => 25, 'max' => 2800],
            'lapins' => ['min' => 30, 'max' => 7000],
            'poulets' => ['min' => 30, 'max' => 6000],
            'pondeuses' => ['min' => 30, 'max' => 4000],
            'poissons-chats' => ['min' => 0, 'max' => 15000],
            'escargots' => ['min' => 0, 'max' => 250],
            'bovins' => ['min' => 15000, 'max' => 1100000],
            default => ['min' => 0, 'max' => 2000000],
        };
    }
}
