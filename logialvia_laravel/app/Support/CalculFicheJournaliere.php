<?php

namespace App\Support;

/**
 * Calcul d'une journee de fiche d'elevage — PORT de `calcul_fiche_journaliere.dart`
 * (le Dart est la source). Aucun effectif n'est jamais saisi : il est recalcule de la
 * veille et des mouvements du jour (BR-ELV-007). Aucun effectif ne devient negatif
 * (BR-ELV-001) : borne a 0, plafond a 999 999.
 *
 * Rationnement (`47e_`) : barèmes et taux par classe de poids sont synchronises (`P7c`) ; la
 * provende se calcule ici comme au poste. Ce qui depend du STOCK d'intrants (provende en
 * stock, autonomie) reste propre a chaque poste.
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

    /**
     * Ration effective d'une categorie, en g/tete/jour : libelle de la categorie, puis ses stades
     * equivalents, puis la valeur de reference de la filiere (jamais 0 par defaut).
     *
     * @param  array<string, int>  $rationsConfigurees  stade => g/jour (Parametres Elevage)
     */
    public static function rationCategorie(string $espece, int $index, array $rationsConfigurees): int
    {
        $categories = FilieresElevage::configuration($espece)['categories'];
        if (! isset($categories[$index])) {
            return 0;
        }
        [$libelle, $reference] = $categories[$index];
        if (isset($rationsConfigurees[$libelle])) {
            return $rationsConfigurees[$libelle];
        }
        foreach (FilieresElevage::STADES_EQUIVALENTS[$espece][$libelle] ?? [] as $stade) {
            if (isset($rationsConfigurees[$stade])) {
                return $rationsConfigurees[$stade];
            }
        }

        return $reference;
    }

    /**
     * Provende du jour : ration par tete, ou — filiere au poids vif, pesee, effectif et classe
     * connus — pesee x taux. Le repli par tete est signale (`sur_poids_vif` faux).
     *
     * @param  list<int>  $effectifsParCategorie
     * @param  array<string, int>  $rationsConfigurees
     * @param  list<array{poids_min_g: int, poids_max_g: int|null, taux_pourcent: float}>  $tauxParClasse
     * @return array{grammes: int, sur_poids_vif: bool, taux_pourcent: float|null, poids_moyen_g: int|null}
     */
    public static function provendeDuJour(string $espece, array $effectifsParCategorie, array $rationsConfigurees, array $tauxParClasse, ?int $poidsTotalGrammes): array
    {
        $effectifTotal = 0;
        $parTete = 0;
        foreach (array_keys(FilieresElevage::configuration($espece)['categories']) as $i) {
            $effectif = $effectifsParCategorie[$i] ?? 0;
            $effectifTotal += $effectif;
            $parTete += $effectif * self::rationCategorie($espece, $i, $rationsConfigurees);
        }

        if (in_array($espece, FilieresElevage::RATION_AU_POIDS_VIF, true)
            && $poidsTotalGrammes !== null && $poidsTotalGrammes > 0 && $effectifTotal > 0) {
            $poidsMoyen = $poidsTotalGrammes / $effectifTotal;
            foreach ($tauxParClasse as $classe) {
                if ($poidsMoyen >= $classe['poids_min_g'] && ($classe['poids_max_g'] === null || $poidsMoyen < $classe['poids_max_g'])) {
                    return [
                        'grammes' => (int) round($poidsTotalGrammes * $classe['taux_pourcent'] / 100),
                        'sur_poids_vif' => true,
                        'taux_pourcent' => (float) $classe['taux_pourcent'],
                        'poids_moyen_g' => (int) round($poidsMoyen),
                    ];
                }
            }
        }

        return ['grammes' => $parTete, 'sur_poids_vif' => false, 'taux_pourcent' => null, 'poids_moyen_g' => null];
    }

    /** Poids moyen en grammes (arrondi) ; 0 sans effectif. */
    public static function poidsMoyenGrammes(int $poidsTotalGrammes, int $effectif): int
    {
        return $effectif <= 0 ? 0 : (int) round($poidsTotalGrammes / $effectif);
    }
}
