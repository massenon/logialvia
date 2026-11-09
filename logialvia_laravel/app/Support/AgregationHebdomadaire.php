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
            // Dernier effectif CONNU avant la semaine : une veille non saisie ne ramene pas a
            // l'effectif de debut de mois (`47e_`).
            $effectifDebut = $effectifInitial;
            for ($j = 1; $j < $debut; $j++) {
                $precedente = $journees[$j] ?? null;
                if ($precedente !== null && $precedente['is_recorded']) {
                    $effectifDebut = $precedente['effectif'];
                }
            }

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
                // Effectif EXPOSE : depart + entrees de la semaine (`47e_`).
                'taux_mortalite' => ($effectifDebut + $achats + $naissances) <= 0
                    ? null
                    : $morts / ($effectifDebut + $achats + $naissances) * 100,
            ];
        }

        return $semaines;
    }
}
