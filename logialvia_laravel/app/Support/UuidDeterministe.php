<?php

namespace App\Support;

/**
 * UUID DETERMINISTE (version 5, SHA-1) calcule depuis une cle metier : le MEME calcul que
 * `uuidDeterministe` du poste (`core/sync/identifiant_poste.dart`). Deux postes qui
 * saisissent la meme fiche journaliere (espece + date) obtiennent le meme identifiant ;
 * le serveur le recalcule pour le verifier.
 */
final class UuidDeterministe
{
    public static function de(string $cle): string
    {
        $octets = substr(sha1('logialvia:'.$cle, true), 0, 16);
        $octets[6] = chr((ord($octets[6]) & 0x0f) | 0x50); // version 5
        $octets[8] = chr((ord($octets[8]) & 0x3f) | 0x80); // variante RFC 4122
        $hex = bin2hex($octets);

        return substr($hex, 0, 8).'-'.substr($hex, 8, 4).'-'.substr($hex, 12, 4).'-'.substr($hex, 16, 4).'-'.substr($hex, 20);
    }

    /** UUID de la fiche de cette filiere pour ce jour civil (`AAAA-MM-JJ`). */
    public static function ficheJournee(string $espece, string $jour): string
    {
        return self::de("fiche_journee:$espece|$jour");
    }

    /** UUID du compteur de ventes du jour de ce POSTE (son `device_id`). */
    public static function ventesJour(string $espece, string $jour, string $poste): string
    {
        return self::de("fiche_ventes_jour:$espece|$jour|$poste");
    }

    /** UUID du soin engendre par une echeance du calendrier pour une bande (`47e_`) : comme au poste. */
    public static function soinProphylaxie(string $bandeId, string $echeanceId): string
    {
        return self::de("soin_prophylaxie:$bandeId|$echeanceId");
    }

    /** UUID de l'effet de stock (`47s_`) d'une nature donnée sur un fait : le même qu'au poste. */
    public static function effetStock(string $faitId, string $nature): string
    {
        return self::de("effet:$nature:$faitId");
    }

    public static function note(int $annee, int $numero): string
    {
        return self::de("note:$annee-$numero");
    }

    public static function cloturePeriodique(int $annee, int $mois): string
    {
        return self::de("cloture-periodique:$annee-$mois");
    }

    public static function clotureExercice(int $annee): string
    {
        return self::de("cloture-exercice:$annee");
    }
}
