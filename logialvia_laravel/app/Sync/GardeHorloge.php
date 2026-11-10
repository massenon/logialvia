<?php

namespace App\Sync;

use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;

/**
 * Garde d'HORLOGE (`47g_`). « Dernier ecrivain gagne » compare des instants de SAISIE ecrits
 * par les postes : un poste dont l'horloge avance de plusieurs jours (ou annees) ecrirait des
 * instants dans le futur, gagnerait TOUTES les comparaisons et gelerait les lignes contre les
 * autres postes. Un instant de saisie qui depasse l'horloge du SERVEUR de plus de la tolerance
 * est donc refuse, avec le code stable `horloge_en_avance` et un motif francais explicite.
 *
 * Les instants controles sont ceux que le poste ECRIT comme instant de saisie (pas les dates
 * metier : une echeance ou une date de vente peut legitimement etre dans le futur).
 */
final class GardeHorloge
{
    /** Tolerance : un decalage de 5 minutes ou moins est un ecart d'horloge ordinaire. */
    public const TOLERANCE_SECONDES = 300;

    /** Code stable du refus (le poste le reconnait, jamais le texte). */
    public const CODE = 'horloge_en_avance';

    /** Cles de ligne qui sont des instants de saisie ecrits par le poste. */
    public const CLES_INSTANT = ['updated_at', 'horodatage', 'saisi_le', 'supprime_le', 'archive_le'];

    public static function maintenant(): CarbonImmutable
    {
        return CarbonImmutable::now('UTC');
    }

    /**
     * Avance de cet instant sur l'horloge du serveur, en secondes (arrondi au-dessus) ;
     * `null` si l'instant est dans la tolerance (egalite comprise), vide ou illisible (la
     * validation des champs s'en charge).
     */
    public static function avance(mixed $instant): ?int
    {
        if (! is_string($instant) && ! $instant instanceof CarbonInterface) {
            return null;
        }

        try {
            $t = $instant instanceof CarbonInterface
                ? CarbonImmutable::instance($instant)->utc()
                : CarbonImmutable::parse($instant)->utc();
        } catch (\Throwable) {
            return null;
        }

        $maintenant = self::maintenant();
        $micro = ($t->getTimestamp() - $maintenant->getTimestamp()) * 1_000_000
            + ((int) $t->format('u') - (int) $maintenant->format('u'));

        return $micro > self::TOLERANCE_SECONDES * 1_000_000 ? (int) ceil($micro / 1_000_000) : null;
    }

    /**
     * Motif du refus d'une ligne (ou d'une demande) dont un instant de saisie est en avance ;
     * `null` si tous sont dans la tolerance.
     *
     * @param  array<string, mixed>  $ligne
     */
    public static function controler(array $ligne): ?string
    {
        $max = null;

        foreach (self::CLES_INSTANT as $cle) {
            if (array_key_exists($cle, $ligne) && ($a = self::avance($ligne[$cle])) !== null) {
                $max = max($max ?? 0, $a);
            }
        }

        return $max === null ? null : self::motif($max);
    }

    public static function motif(int $secondes): string
    {
        return "L'horloge de ce poste avance de ".self::duree($secondes).' : corrigez la date et l\'heure du poste.';
    }

    /**
     * « 2 ans », « 2 jours », « 1 h 05 », « 7 min » : une duree lisible. Au-dela d'une minute elle
     * est arrondie a la minute la plus proche (la mesure est toujours entachee du temps de reponse).
     */
    public static function duree(int $secondes): string
    {
        $secondes = max(0, $secondes);
        if ($secondes >= 60) {
            $secondes = (int) (round($secondes / 60) * 60);
        }

        if ($secondes >= 365 * 86400) {
            $n = intdiv($secondes, 365 * 86400);

            return $n.($n > 1 ? ' ans' : ' an');
        }
        if ($secondes >= 86400) {
            $n = intdiv($secondes, 86400);

            return $n.($n > 1 ? ' jours' : ' jour');
        }
        if ($secondes >= 3600) {
            $h = intdiv($secondes, 3600);
            $m = intdiv($secondes % 3600, 60);

            return $m === 0 ? "$h h" : sprintf('%d h %02d', $h, $m);
        }
        if ($secondes >= 60) {
            return intdiv($secondes, 60).' min';
        }

        return $secondes.' s';
    }
}
