<?php

namespace App\Services\Comptabilite;

use App\Support\UuidDeterministe;
use Carbon\CarbonImmutable;

/**
 * Report a nouveau et cloture annuelle — SYSCOHADA revise (OHADA 2018).
 *
 * PORT FIDELE de `report_a_nouveau.dart` (le Dart est la source) ; `ReportANouveauTest` rejoue
 * le jeu 2024 calcule a la main au poste (`report_a_nouveau_test.dart`). Voir `47c_` :
 *
 *  1. resultat : classes 6, 7 et 8 → compte 131 (benefice) ou 139 (perte), piece `CL-N-RESULTAT` ;
 *  2. affectation : 131 → reserves 111/118, dividendes a payer 465, report a nouveau 121 ; perte :
 *     139 → report a nouveau debiteur 129, piece `CL-N-AFFECTATION` ;
 *  3. a-nouveaux : soldes des classes 1 a 5 en `AN-(N+1)` au 01/01/N+1 — jamais les classes 6, 7, 8.
 *
 * Les etats de N se lisent « avant affectation » (journal `CL` exclu) ; N+1 part de l'ouverture.
 * Tant que N n'est pas cloture, l'ouverture de N+1 est une cloture VIRTUELLE (121/129).
 */
final class ReportANouveau
{
    public const CLOTURE = 'CL';

    public const A_NOUVEAU = 'AN';

    public const TOLERANCE = 0.01;

    public const RESERVE_LEGALE = '111';

    public const AUTRES_RESERVES = '118';

    public const REPORT_CREDITEUR = '121';

    public const REPORT_DEBITEUR = '129';

    public const RESULTAT_BENEFICE = '131';

    public const RESULTAT_PERTE = '139';

    public const DIVIDENDES_A_PAYER = '465';

    public const LIBELLES_JOURNAUX = [
        self::A_NOUVEAU => 'À-Nouveaux (Report à Nouveau)',
        self::CLOTURE => 'Écritures de Clôture',
    ];

    public static function estDeCloture(string $journal): bool
    {
        return $journal === self::CLOTURE || $journal === self::A_NOUVEAU;
    }

    public static function centime(float $v): float
    {
        return round($v * 100) / 100;
    }

    private static function estDeGestion(string $compte): bool
    {
        return $compte !== '' && in_array($compte[0], ['6', '7', '8'], true);
    }

    // ----------------------------------------------------------------- lectures

    /** Lignes que les etats de N lisent : sans a-nouveaux (l'ouverture) ni ecritures de cloture. */
    public static function mouvementsCourants(iterable $toutes, int $annee): array
    {
        $r = [];
        foreach ($toutes as $e) {
            if ($e->exercice === $annee && ! self::estDeCloture($e->journal)) {
                $r[] = $e;
            }
        }

        return $r;
    }

    /** Lignes du LIVRE de N : tout sauf les a-nouveaux ; la cloture y figure. */
    public static function mouvementsDuLivre(iterable $toutes, int $annee): array
    {
        $r = [];
        foreach ($toutes as $e) {
            if ($e->exercice === $annee && $e->journal !== self::A_NOUVEAU) {
                $r[] = $e;
            }
        }

        return $r;
    }

    /** @return array<string, float> soldes nets (debit − credit) au 1er janvier de `$annee`. */
    public static function soldesOuverture(iterable $toutes, int $annee): array
    {
        $toutes = is_array($toutes) ? $toutes : iterator_to_array($toutes, false);

        $an = [];
        $aDesANouveaux = false;
        foreach ($toutes as $e) {
            if ($e->exercice === $annee && $e->journal === self::A_NOUVEAU) {
                $aDesANouveaux = true;
                $an[$e->compte] = ($an[$e->compte] ?? 0.0) + $e->debit - $e->credit;
            }
        }
        if ($aDesANouveaux) {
            return self::sansNuls($an);
        }

        $precedent = null;
        foreach ($toutes as $e) {
            if ($e->exercice < $annee && ($precedent === null || $e->exercice > $precedent)) {
                $precedent = $e->exercice;
            }
        }
        if ($precedent === null) {
            return [];
        }

        return self::clotureVirtuelle($toutes, $precedent);
    }

    private static function clotureVirtuelle(array $toutes, int $annee): array
    {
        $soldes = self::soldesOuverture($toutes, $annee);
        foreach (self::mouvementsDuLivre($toutes, $annee) as $e) {
            $soldes[$e->compte] = ($soldes[$e->compte] ?? 0.0) + $e->debit - $e->credit;
        }
        $bilan = [];
        $residu = 0.0;
        foreach ($soldes as $compte => $net) {
            if (self::estDeGestion((string) $compte)) {
                $residu += $net;
            } else {
                $bilan[$compte] = $net;
            }
        }
        $residu = self::centime($residu);
        if (abs($residu) >= self::TOLERANCE) {
            $cible = $residu > 0 ? self::REPORT_DEBITEUR : self::REPORT_CREDITEUR;
            $bilan[$cible] = ($bilan[$cible] ?? 0.0) + $residu;
        }

        return self::sansNuls($bilan);
    }

    private static function sansNuls(array $m): array
    {
        $r = [];
        foreach ($m as $compte => $v) {
            if (abs(self::centime($v)) >= self::TOLERANCE) {
                $r[(string) $compte] = self::centime($v);
            }
        }

        return $r;
    }

    /** Soldes de FIN pour les etats : ouverture + mouvements courants (cloture exclue). */
    public static function soldesDeFin(iterable $toutes, int $annee): Soldes
    {
        $toutes = is_array($toutes) ? $toutes : iterator_to_array($toutes, false);
        $soldes = self::soldesOuverture($toutes, $annee);
        foreach (self::mouvementsCourants($toutes, $annee) as $e) {
            $soldes[$e->compte] = ($soldes[$e->compte] ?? 0.0) + $e->debit - $e->credit;
        }

        return new Soldes($soldes);
    }

    public static function soldesDOuverture(iterable $toutes, int $annee): Soldes
    {
        return new Soldes(self::soldesOuverture($toutes, $annee));
    }

    // ---------------------------------------------------------------- affectation

    /**
     * @param  array{reserve_legale?: mixed, autres_reserves?: mixed, dividendes?: mixed}|null  $brut
     * @return array{reserve_legale: float, autres_reserves: float, dividendes: float}
     */
    public static function affectation(?array $brut): array
    {
        $lire = fn (string $cle) => isset($brut[$cle]) && is_numeric($brut[$cle]) && $brut[$cle] >= 0 ? (float) $brut[$cle] : 0.0;

        return [
            'reserve_legale' => $lire('reserve_legale'),
            'autres_reserves' => $lire('autres_reserves'),
            'dividendes' => $lire('dividendes'),
        ];
    }

    public static function totalDistribue(array $a): float
    {
        return $a['reserve_legale'] + $a['autres_reserves'] + $a['dividendes'];
    }

    /** Motif du refus de l'affectation, ou `null`. */
    public static function validerAffectation(array $a, float $resultat, float $reportDebiteurAnterieur = 0.0): ?string
    {
        if ($a['reserve_legale'] < 0 || $a['autres_reserves'] < 0 || $a['dividendes'] < 0) {
            return 'Les montants d\'affectation ne peuvent pas être négatifs.';
        }
        $total = self::totalDistribue($a);
        if ($resultat <= self::TOLERANCE) {
            return $total > self::TOLERANCE
                ? 'Aucune distribution n\'est possible sur un résultat nul ou déficitaire : la perte est portée au report à nouveau débiteur (129).'
                : null;
        }
        if ($total > $resultat + self::TOLERANCE) {
            return sprintf('L\'affectation (%s) dépasse le bénéfice (%s).', number_format($total, 0, '', ''), number_format($resultat, 0, '', ''));
        }
        if ($a['dividendes'] > self::TOLERANCE && $reportDebiteurAnterieur > self::TOLERANCE
            && $a['dividendes'] + $a['reserve_legale'] + $a['autres_reserves'] + $reportDebiteurAnterieur > $resultat + self::TOLERANCE) {
            return sprintf('Un report à nouveau débiteur de %s subsiste : le bénéfice doit d\'abord l\'absorber avant tout dividende.', number_format($reportDebiteurAnterieur, 0, '', ''));
        }

        return null;
    }

    // ------------------------------------------------------------------- cloture

    /**
     * Calcule (sans rien ecrire) les pieces de la cloture de `$annee`.
     *
     * @param  array{reserve_legale: float, autres_reserves: float, dividendes: float}|null  $affectation
     * @param  list<string>  $comptesConnus  vide : pas de controle du plan
     * @return array{exercice: int, resultat: float, pieces: list<array>, anomalies: list<string>, reportes: array<string, float>}
     */
    public static function calculer(iterable $toutes, int $annee, ?array $affectation = null, array $comptesConnus = []): array
    {
        $toutes = is_array($toutes) ? $toutes : iterator_to_array($toutes, false);
        $affectation ??= self::affectation(null);
        $anomalies = [];

        $nets = [];
        foreach (self::mouvementsCourants($toutes, $annee) as $e) {
            $nets[$e->compte] = ($nets[$e->compte] ?? 0.0) + $e->debit - $e->credit;
        }

        $ouverture = self::soldesOuverture($toutes, $annee);
        $ecart = array_sum($ouverture) + array_sum($nets);
        if (abs(self::centime($ecart)) >= self::TOLERANCE) {
            $anomalies[] = sprintf('Balance déséquilibrée de %s FCFA : la clôture est refusée (BR-CPT-004).', number_format(abs(self::centime($ecart)), 0, '', ''));
        }

        $gestion = [];
        foreach ($nets as $c => $v) {
            if (self::estDeGestion((string) $c) && abs(self::centime($v)) >= self::TOLERANCE) {
                $gestion[] = (string) $c;
            }
        }
        sort($gestion, SORT_STRING);
        $resultat = 0.0;
        foreach ($gestion as $c) {
            $resultat -= $nets[$c];
        }
        $resultat = self::centime($resultat);

        $debiteurAnterieur = max(0.0, $ouverture[self::REPORT_DEBITEUR] ?? 0.0);
        $refus = self::validerAffectation($affectation, $resultat, $debiteurAnterieur);
        if ($refus !== null) {
            // Affectation refusee : aucune piece n'est proposee (elles ne s'equilibreraient pas).
            $anomalies[] = $refus;

            return ['exercice' => $annee, 'resultat' => $resultat, 'pieces' => [], 'anomalies' => $anomalies, 'reportes' => []];
        }

        $dateCloture = CarbonImmutable::create($annee, 12, 31, 12, 0, 0, config('logialvia.fuseau'));
        $dateOuverture = CarbonImmutable::create($annee + 1, 1, 1, 12, 0, 0, config('logialvia.fuseau'));
        $pieces = [];

        $ligne = fn (string $compte, float $debit, float $credit, string $libelle) => compact('compte', 'debit', 'credit', 'libelle');

        if ($gestion !== []) {
            $lignes = [];
            foreach ($gestion as $c) {
                $lignes[] = $ligne(
                    $c,
                    $nets[$c] < 0 ? self::centime(-$nets[$c]) : 0.0,
                    $nets[$c] > 0 ? self::centime($nets[$c]) : 0.0,
                    "Solde du compte de gestion — Exercice $annee",
                );
            }
            if ($resultat >= self::TOLERANCE) {
                $lignes[] = $ligne(self::RESULTAT_BENEFICE, 0.0, $resultat, "Résultat net (bénéfice) de l'exercice $annee");
            } elseif ($resultat <= -self::TOLERANCE) {
                $lignes[] = $ligne(self::RESULTAT_PERTE, -$resultat, 0.0, "Résultat net (perte) de l'exercice $annee");
            }
            if (count($lignes) >= 2) {
                $pieces[] = [
                    'cle' => "cloture:$annee:resultat", 'numero' => "CL-$annee-RESULTAT", 'journal' => self::CLOTURE,
                    'date' => $dateCloture, 'exercice' => $annee, 'lignes' => $lignes,
                ];
            }
        }

        if ($resultat >= self::TOLERANCE) {
            $lignes = [$ligne(self::RESULTAT_BENEFICE, $resultat, 0.0, "Affectation du résultat $annee")];
            $credit = function (string $compte, float $montant, string $libelle) use (&$lignes, $ligne) {
                if ($montant >= self::TOLERANCE) {
                    $lignes[] = $ligne($compte, 0.0, self::centime($montant), $libelle);
                }
            };
            $credit(self::RESERVE_LEGALE, $affectation['reserve_legale'], "Dotation à la réserve légale — résultat $annee");
            $credit(self::AUTRES_RESERVES, $affectation['autres_reserves'], "Dotation aux autres réserves — résultat $annee");
            $credit(self::DIVIDENDES_A_PAYER, $affectation['dividendes'], "Dividendes à payer — résultat $annee");
            $credit(self::REPORT_CREDITEUR, self::centime($resultat - self::totalDistribue($affectation)), "Report à nouveau — résultat $annee");
            $pieces[] = [
                'cle' => "cloture:$annee:affectation", 'numero' => "CL-$annee-AFFECTATION", 'journal' => self::CLOTURE,
                'date' => $dateCloture, 'exercice' => $annee, 'lignes' => $lignes,
            ];
        } elseif ($resultat <= -self::TOLERANCE) {
            $pieces[] = [
                'cle' => "cloture:$annee:affectation", 'numero' => "CL-$annee-AFFECTATION", 'journal' => self::CLOTURE,
                'date' => $dateCloture, 'exercice' => $annee,
                'lignes' => [
                    $ligne(self::REPORT_DEBITEUR, -$resultat, 0.0, "Perte $annee portée en report à nouveau débiteur"),
                    $ligne(self::RESULTAT_PERTE, 0.0, -$resultat, "Affectation de la perte $annee"),
                ],
            ];
        }

        // Soldes apres cloture : ouverture + mouvements courants + pieces de cloture.
        $apres = $ouverture;
        foreach ($nets as $c => $v) {
            $apres[$c] = ($apres[$c] ?? 0.0) + $v;
        }
        foreach ($pieces as $p) {
            foreach ($p['lignes'] as $l) {
                $apres[$l['compte']] = ($apres[$l['compte']] ?? 0.0) + $l['debit'] - $l['credit'];
            }
        }
        $reportes = [];
        foreach ($apres as $c => $v) {
            if (self::estDeGestion((string) $c)) {
                continue;
            }
            if (abs(self::centime($v)) >= self::TOLERANCE) {
                $reportes[(string) $c] = self::centime($v);
            }
        }
        ksort($reportes, SORT_STRING);
        $lignesAn = [];
        foreach ($reportes as $c => $v) {
            $lignesAn[] = $ligne((string) $c, $v > 0 ? $v : 0.0, $v < 0 ? -$v : 0.0, "À-nouveau — Exercice $annee");
        }
        if (count($lignesAn) >= 2) {
            $ecartAn = array_sum(array_column($lignesAn, 'debit')) - array_sum(array_column($lignesAn, 'credit'));
            if (abs(self::centime($ecartAn)) >= self::TOLERANCE) {
                $anomalies[] = 'Les à-nouveaux ne s\'équilibrent pas : clôture refusée.';
            }
            $pieces[] = [
                'cle' => 'an:'.($annee + 1), 'numero' => 'AN-'.($annee + 1), 'journal' => self::A_NOUVEAU,
                'date' => $dateOuverture, 'exercice' => $annee + 1, 'lignes' => $lignesAn,
            ];
        } elseif ($lignesAn !== []) {
            $anomalies[] = 'Les à-nouveaux ne peuvent pas être équilibrés.';
        }

        if ($comptesConnus !== []) {
            $manquants = [];
            foreach ($pieces as $p) {
                foreach ($p['lignes'] as $l) {
                    if (! in_array($l['compte'], $comptesConnus, true)) {
                        $manquants[$l['compte']] = true;
                    }
                }
            }
            if ($manquants !== []) {
                $liste = array_keys($manquants);
                sort($liste, SORT_STRING);
                $anomalies[] = 'Compte(s) absent(s) du plan comptable : '.implode(', ', $liste).'.';
            }
        }

        return ['exercice' => $annee, 'resultat' => $resultat, 'pieces' => $pieces, 'anomalies' => $anomalies, 'reportes' => $reportes];
    }

    public static function idPiece(string $cle): string
    {
        return UuidDeterministe::de("piece:$cle");
    }

    public static function idLigne(string $cle, string $compte): string
    {
        return UuidDeterministe::de("ligne:$cle:$compte");
    }
}
