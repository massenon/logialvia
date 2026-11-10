<?php

namespace App\Support;

/**
 * Controle de vraisemblance d'expert — PORT de `controle_vraisemblance.dart` (memes regles,
 * memes messages ; le Dart est la source).
 *
 *  - `erreurs` : saisie IMPOSSIBLE (plus de morts que de sujets, plus d'oeufs que de pondeuses) :
 *    refusee ;
 *  - `avertissements` : saisie improbable, affichee, jamais bloquante.
 */
final class ControleVraisemblance
{
    /** Entier sans separateur de milliers ; decimale a la virgule (comme le Dart). */
    public static function fmt(int|float $v): string
    {
        return floor((float) $v) === (float) $v
            ? (string) (int) $v
            : str_replace('.', ',', number_format((float) $v, 1, '.', ''));
    }

    private static function arrondi1(float $v): float
    {
        return round($v, 1);
    }

    /**
     * @param  list<int>  $effectifsVeille
     * @param  array{achat?: int, ne?: int, vente?: int, morts?: list<int>, dons?: list<int>}  $mouvements
     * @param  array{effectif_total: int}  $effectifsDuJour
     * @return array{erreurs: list<string>, avertissements: list<string>}
     */
    public static function controlerJournee(
        string $espece,
        array $effectifsVeille,
        array $mouvements,
        array $effectifsDuJour,
        int $effectifTotalVeille = 0,
        ?int $poidsTotalGrammes = null,
        ?int $oeufsPondus = null,
        ?int $oeufsCasses = null,
        ?int $sortiesPlateaux = null,
        int $stockOeufsDisponible = 0,
    ): array {
        $erreurs = [];
        $avertissements = [];
        $config = FilieresElevage::configuration($espece);
        $achat = $mouvements['achat'] ?? 0;
        $ne = $mouvements['ne'] ?? 0;
        $vente = $mouvements['vente'] ?? 0;
        $morts = $mouvements['morts'] ?? [];
        $dons = $mouvements['dons'] ?? [];
        $indexCommercialisee = -1;

        foreach ($config['categories'] as $i => [$libelle, , $recoit, $deduite]) {
            $veille = $effectifsVeille[$i] ?? 0;
            $disponible = $veille + ($recoit ? $achat + $ne : 0);
            $retires = ($morts[$i] ?? 0) + ($dons[$i] ?? 0);
            if ($retires > $disponible) {
                $erreurs[] = 'Morts et dons de « '.$libelle.' » ('.self::fmt($retires).') : '
                    .'supérieurs à l\'effectif disponible ('.self::fmt($disponible).'). '
                    .'Saisissez d\'abord les entrées (achats, naissances) ou corrigez la mortalité.';
            }
            if ($deduite) {
                $indexCommercialisee = $i;
                $apresRetraits = $disponible - $retires;
                if ($vente > $apresRetraits && $vente > 0) {
                    $avertissements[] = 'Les ventes du jour ('.self::fmt($vente).') dépassent l\'effectif '
                        .'de « '.$libelle.' » ('.self::fmt(max(0, $apresRetraits)).') : '
                        .'la fiche sera ramenée à 0. Vérifiez les entrées déjà saisies.';
                }
            }
        }

        if ($oeufsPondus !== null && $oeufsPondus > 0) {
            $pondeuses = $indexCommercialisee >= 0 ? ($effectifsVeille[$indexCommercialisee] ?? 0) : 0;
            if ($pondeuses > 0) {
                if ($oeufsPondus > $pondeuses) {
                    $erreurs[] = 'Les œufs pondus ('.self::fmt($oeufsPondus).') dépassent le nombre de '
                        .'pondeuses ('.self::fmt($pondeuses).') : une poule pond au plus un œuf par jour.';
                } else {
                    $taux = $oeufsPondus / $pondeuses * 100;
                    if ($taux > ReperesZootechniques::TAUX_PONTE_EXCEPTIONNEL) {
                        $avertissements[] = 'Taux de ponte de '.self::fmt(self::arrondi1($taux)).' % : '
                            .'au-delà de '.self::fmt(ReperesZootechniques::TAUX_PONTE_EXCEPTIONNEL).' % '
                            .'c\'est exceptionnel. Vérifiez le décompte des œufs.';
                    }
                }
            }
            if ($oeufsCasses !== null && $oeufsCasses <= $oeufsPondus) {
                $part = $oeufsCasses / $oeufsPondus * 100;
                if ($part > ReperesZootechniques::PART_OEUFS_CASSES_A_VERIFIER) {
                    $avertissements[] = 'Œufs cassés : '.self::fmt(self::arrondi1($part)).' % des '
                        .'œufs pondus (un élevage maîtrisé reste sous '
                        .self::fmt(ReperesZootechniques::PART_OEUFS_CASSES_A_VERIFIER / 2).' %). '
                        .'Vérifiez les pondoirs et la collecte.';
                }
            }
        }
        if ($sortiesPlateaux !== null && $sortiesPlateaux > 0
            && $sortiesPlateaux * CalculFicheJournaliere::OEUFS_PAR_PLATEAU > $stockOeufsDisponible) {
            $avertissements[] = 'Les sorties ('.self::fmt($sortiesPlateaux * CalculFicheJournaliere::OEUFS_PAR_PLATEAU)
                .' œufs) dépassent le stock disponible ('.self::fmt($stockOeufsDisponible).') : '
                .'le stock final sera ramené à 0.';
        }

        if ($poidsTotalGrammes !== null && $poidsTotalGrammes > 0) {
            $effectif = $effectifsDuJour['effectif_total'];
            if ($effectif <= 0) {
                $avertissements[] = 'Une pesée est saisie alors qu\'aucun sujet vivant n\'est comptabilisé.';
            } else {
                $moyen = $poidsTotalGrammes / $effectif;
                $repere = ReperesZootechniques::poidsMoyenPlausibleG($espece);
                if ($moyen < $repere['min'] || $moyen > $repere['max']) {
                    $avertissements[] = 'Poids moyen de '.self::fmt((int) round($moyen)).' g par sujet : hors des '
                        .'repères '.$config['libelle'].' ('.self::fmt($repere['min']).' à '
                        .self::fmt($repere['max']).' g). Vérifiez l\'unité (la pesée se saisit en '
                        .'grammes) et l\'effectif.';
                }
            }
        }

        $totalMorts = array_sum($morts);
        if ($effectifTotalVeille > 0 && $totalMorts > 0) {
            $taux = $totalMorts / $effectifTotalVeille * 100;
            $affiche = self::fmt(self::arrondi1($taux));
            $niveau = ReperesZootechniques::niveauMortaliteJour($taux);
            if ($niveau === ReperesZootechniques::CRITIQUE) {
                $avertissements[] = 'Mortalité du jour de '.$affiche.' % : seuil critique '
                    .'('.self::fmt(ReperesZootechniques::MORTALITE_JOUR_CRITIQUE).' %) dépassé. '
                    .'Isolez les sujets malades et prévenez le vétérinaire.';
            } elseif ($niveau === ReperesZootechniques::AVERTISSEMENT) {
                $avertissements[] = 'Mortalité du jour de '.$affiche.' % : au-dessus du seuil '
                    .'d\'avertissement ('.self::fmt(ReperesZootechniques::MORTALITE_JOUR_AVERTISSEMENT).' %).';
            }
        }

        return ['erreurs' => $erreurs, 'avertissements' => $avertissements];
    }

    /** Message de refus d'un mirage premature (J+7 : pas avant J+5 ; J+14 : pas avant J+12). */
    public static function erreurMirage(int $ageJours, int $jour): ?string
    {
        $minimum = $jour === 7 ? ReperesZootechniques::MIRAGE_1_AU_PLUS_TOT : ReperesZootechniques::MIRAGE_2_AU_PLUS_TOT;
        if ($ageJours >= $minimum) {
            return null;
        }

        return 'Le mirage à J+'.$jour.' ne peut pas se faire avant J+'.$minimum.' : ce lot '
            .'n\'a que '.$ageJours.' jour'.($ageJours > 1 ? 's' : '').' d\'incubation.';
    }

    /** Message de refus d'une eclosion plus de 4 jours avant le terme de l'espece. */
    public static function erreurEclosion(int $ageJours, string $libelleEspece, int $dureeJours): ?string
    {
        $premiere = $dureeJours - ReperesZootechniques::ECLOSION_AVANCE_MAXIMALE_JOURS;
        if ($ageJours >= $premiere) {
            return null;
        }

        return 'Éclosion impossible : ce lot n\'a que '.$ageJours.' jour'.($ageJours > 1 ? 's' : '')
            .' d\'incubation, '.$libelleEspece.' incube '.$dureeJours.' jours (éclosion '
            .'possible à partir de J+'.$premiere.').';
    }
}
