<?php

namespace App\Support;

/**
 * Vue hebdomadaire d'un mois de fiche — PORT de `agregation_hebdomadaire.dart`.
 * Les semaines sont 1-7, 8-14, 15-21 et 22-fin du mois (la derniere absorbe le reste).
 */
final class AgregationHebdomadaire
{
    /** @return list<array{0: int, 1: int}> */
    public static function decouper(int $nombreJoursDuMois): array
    {
        return [[1, 7], [8, 14], [15, 21], [22, $nombreJoursDuMois]];
    }

    /**
     * @param  array<int, array<string, mixed>>  $journees  journees au format `FichesElevage::versDomaine`, indexees par jour
     * @return list<array<string, mixed>>
     */
    public static function calculer(int $nombreJoursDuMois, array $journees, int $effectifInitial): array
    {
        $semaines = [];

        foreach (self::decouper($nombreJoursDuMois) as $i => [$debut, $fin]) {
            $veille = $debut > 1 ? ($journees[$debut - 1] ?? null) : null;
            $effectifDebut = $veille['effectif'] ?? $effectifInitial;

            $achats = $naissances = $morts = $ventes = 0;
            $effectifFin = $effectifDebut;
            $saisie = false;

            for ($jour = $debut; $jour <= $fin; $jour++) {
                $journee = $journees[$jour] ?? null;
                if ($journee === null || ! $journee['is_recorded']) {
                    continue;
                }
                $saisie = true;
                $achats += $journee['achat'];
                $naissances += $journee['ne'];
                $morts += array_sum($journee['morts']);
                $ventes += $journee['vente'];
                $effectifFin = $journee['effectif'];
            }

            $semaines[] = [
                'numero' => $i + 1,
                'premier_jour' => $debut,
                'dernier_jour' => $fin,
                'cumul_achats' => $achats,
                'cumul_naissances' => $naissances,
                'cumul_morts' => $morts,
                'cumul_ventes' => $ventes,
                'effectif_debut' => $effectifDebut,
                'effectif_fin' => $effectifFin,
                'a_des_journees_saisies' => $saisie,
                'taux_mortalite' => $effectifDebut <= 0 ? null : $morts / $effectifDebut * 100,
            ];
        }

        return $semaines;
    }
}
