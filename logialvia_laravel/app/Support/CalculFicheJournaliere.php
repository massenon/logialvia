<?php

namespace App\Support;

/**
 * Calcul d'une journee de fiche d'elevage — PORT de `calcul_fiche_journaliere.dart`
 * (le Dart est la source). Aucun effectif n'est jamais saisi : il est recalcule de la
 * veille et des mouvements du jour (BR-ELV-007). Aucun effectif ne devient negatif
 * (BR-ELV-001) : borne a 0, plafond a 999 999.
 *
 * Les provendes (rationnement) ne sont PAS portees : les baremes de ration ne sont pas
 * synchronises (palier `P7c`).
 */
final class CalculFicheJournaliere
{
    public const PLAFOND = 999999;

    public const OEUFS_PAR_PLATEAU = 30;

    private static function borner(int $valeur): int
    {
        return max(0, min(self::PLAFOND, $valeur));
    }

    /**
     * @param  list<int>  $effectifsVeille  effectifs par categorie de la derniere journee saisie avant
     * @param  array{achat?: int, ne?: int, vente?: int, morts?: list<int>, dons?: list<int>}  $mouvements
     * @return array{effectif_total: int, par_categorie: list<int>, taux_mortalite: float}
     */
    public static function calculerJour(string $espece, array $effectifsVeille, int $effectifTotalVeille, array $mouvements): array
    {
        $achat = $mouvements['achat'] ?? 0;
        $ne = $mouvements['ne'] ?? 0;
        $vente = $mouvements['vente'] ?? 0;
        $morts = $mouvements['morts'] ?? [];
        $dons = $mouvements['dons'] ?? [];

        $resultat = [];
        foreach (FilieresElevage::configuration($espece)['categories'] as $i => [, , $recoit, $deduite]) {
            $valeur = $effectifsVeille[$i] ?? 0;
            if ($recoit) {
                $valeur += $achat + $ne;
            }
            if ($deduite) {
                $valeur -= $vente;
            }
            $valeur -= ($morts[$i] ?? 0) + ($dons[$i] ?? 0);
            $resultat[] = self::borner($valeur);
        }

        $totalMorts = array_sum($morts);
        $totalDons = array_sum($dons);

        return [
            'effectif_total' => self::borner($effectifTotalVeille + $achat + $ne - $totalMorts - $vente - $totalDons),
            'par_categorie' => $resultat,
            'taux_mortalite' => self::tauxMortaliteJour($totalMorts, $effectifTotalVeille),
        ];
    }

    /** (morts du jour / effectif de la veille) x 100 ; 0 sans effectif la veille. */
    public static function tauxMortaliteJour(int $totalMorts, int $effectifVeille): float
    {
        return $effectifVeille > 0 ? ($totalMorts / $effectifVeille) * 100 : 0.0;
    }

    /**
     * Suivi du stock d'oeufs (Pondeuses). `srh` est le STOCK FINAL de la veille, jamais
     * son Total Stock.
     *
     * @return array{srh: int, total_stock: int, sorties_oeufs: int, stock_final: int}
     */
    public static function stockOeufs(int $srhOuverture, int $oeufsPondus, int $oeufsCasses, int $sortiesPlateaux): array
    {
        $commercialisables = self::borner($oeufsPondus - $oeufsCasses);
        $totalStock = $commercialisables + $srhOuverture;
        $sortiesOeufs = $sortiesPlateaux * self::OEUFS_PAR_PLATEAU;

        return [
            'srh' => $srhOuverture,
            'total_stock' => $totalStock,
            'sorties_oeufs' => $sortiesOeufs,
            'stock_final' => self::borner($totalStock - $sortiesOeufs),
        ];
    }

    /** Poids moyen en grammes (arrondi) ; 0 sans effectif. */
    public static function poidsMoyenGrammes(int $poidsTotalGrammes, int $effectif): int
    {
        return $effectif <= 0 ? 0 : (int) round($poidsTotalGrammes / $effectif);
    }
}
