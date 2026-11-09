<?php

namespace App\Support;

use App\Models\CycleCouveuse;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Support\Collection;

/**
 * Suivi d'un couvoir en incubation continue — PORT des calculs du poste
 * (`cycle_incubation.dart`, `suivi_incubation.dart`, `statistiques_mirages.dart`).
 *
 * Le Dart est la source : memes formules, memes seuils, memes arrondis. Tout est calcule a
 * partir d'une date de reference injectee (jamais l'horloge), ce qui rend « le TER a une date
 * precise » verifiable. Les dates de lot sont des DATES CIVILES : on compare des jours, pas des
 * instants, pour qu'un fuseau n'avance ni ne recule un mirage.
 */
class SuiviIncubation
{
    /** Premier mirage : retrait des œufs clairs (jamais fecondes). */
    public const JOUR_MIRAGE_1 = 7;

    /** Second mirage : retrait des œufs gates (embryon arrete). */
    public const JOUR_MIRAGE_2 = 14;

    public const EN_INCUBATION = 'En Incubation';

    public const ECLOSION_EFFECTUEE = 'Éclosion Effectuée';

    public const REMPLACE = 'Remplacé';

    /** Duree d'incubation par espece. La pintade incube 28 jours (pas 27) — corrige par la Gerante. */
    public const ESPECES = [
        'goliath' => ['libelle' => 'Goliath', 'duree' => 21],
        'pintade' => ['libelle' => 'Pintade', 'duree' => 28],
    ];

    /** Un jour civil (minuit UTC du `Y-m-d`), insensible au fuseau. */
    public static function jour(CarbonInterface|string $date): CarbonImmutable
    {
        $texte = $date instanceof CarbonInterface ? $date->format('Y-m-d') : substr($date, 0, 10);

        return CarbonImmutable::parse($texte, 'UTC')->startOfDay();
    }

    public static function libelleEspece(string $espece): string
    {
        return self::ESPECES[$espece]['libelle'] ?? ucfirst($espece);
    }

    /** Une espece inconnue retombe sur Goliath (21 j) plutot que de planter, comme le Dart. */
    public static function duree(string $espece): int
    {
        return self::ESPECES[$espece]['duree'] ?? self::ESPECES['goliath']['duree'];
    }

    // ------------------------------------------------------------ Calendrier

    public static function dateChargement(CycleCouveuse $lot): CarbonImmutable
    {
        return self::jour($lot->date_incubation);
    }

    public static function dateMirage1(CycleCouveuse $lot): CarbonImmutable
    {
        return self::dateChargement($lot)->addDays(self::JOUR_MIRAGE_1);
    }

    public static function dateMirage2(CycleCouveuse $lot): CarbonImmutable
    {
        return self::dateChargement($lot)->addDays(self::JOUR_MIRAGE_2);
    }

    /** Calculee a l'affichage, jamais saisie (Doc F3) : duree propre a l'espece. */
    public static function dateEclosionPrevue(CycleCouveuse $lot): CarbonImmutable
    {
        return self::dateChargement($lot)->addDays(self::duree($lot->espece));
    }

    public static function age(CycleCouveuse $lot, CarbonInterface $t): int
    {
        return (int) self::dateChargement($lot)->diffInDays(self::jour($t), false);
    }

    public static function enCours(CycleCouveuse $lot): bool
    {
        return $lot->statut === self::EN_INCUBATION;
    }

    public static function estSousLot(CycleCouveuse $lot): bool
    {
        return $lot->lot_parent_id !== null;
    }

    // ---------------------------------------------------------------- Taux

    /** Œufs encore en incubation apres les deux mirages : E(0) − [B(7) + M(14)]. */
    public static function retenus(CycleCouveuse $lot): int
    {
        return $lot->oeufs_couves - ($lot->oeufs_blancs_j7 ?? 0) - ($lot->oeufs_gates_j14 ?? 0);
    }

    /** Taux d'Eclosion Reel (TER) : eclos / retenus × 100 ; `null` sans eclosion ou sans œuf retenu. */
    public static function ter(CycleCouveuse $lot): ?float
    {
        if ($lot->poussins_nes === null) {
            return null;
        }
        $retenus = self::retenus($lot);

        return $retenus <= 0 ? null : $lot->poussins_nes / $retenus * 100;
    }

    /** Taux brut : eclos / œufs charges × 100. */
    public static function tauxBrut(CycleCouveuse $lot): ?float
    {
        if ($lot->poussins_nes === null || $lot->oeufs_couves <= 0) {
            return null;
        }

        return $lot->poussins_nes / $lot->oeufs_couves * 100;
    }

    /** Pourcentage a la francaise, comme `Formats.pourcentage` du poste : « 85,0 % ». */
    public static function pourcentage(?float $valeur): string
    {
        return $valeur === null ? '—' : number_format($valeur, 1, ',', '').' %';
    }

    // ------------------------------------------------------------ Echeances

    /**
     * Echeances atteintes ou depassees a la date [$t], pour les lots en incubation. Un mirage
     * sans œufs renseignes reste du, meme une semaine apres. Le plus en retard d'abord.
     *
     * @param  Collection<int, CycleCouveuse>  $lots
     * @return list<array{lot: CycleCouveuse, type: string, date: CarbonImmutable, ecart: int}>
     */
    public static function alertes(Collection $lots, CarbonInterface $t): array
    {
        $jour = self::jour($t);
        $alertes = [];

        foreach ($lots as $lot) {
            if (! self::enCours($lot)) {
                continue;
            }
            if ($lot->oeufs_blancs_j7 === null && ! $jour->lt(self::dateMirage1($lot))) {
                $alertes[] = self::alerte($lot, 'mirage1', self::dateMirage1($lot), $jour);
            }
            if ($lot->oeufs_gates_j14 === null && ! $jour->lt(self::dateMirage2($lot))) {
                $alertes[] = self::alerte($lot, 'mirage2', self::dateMirage2($lot), $jour);
            }
            if (! $jour->lt(self::dateEclosionPrevue($lot))) {
                $alertes[] = self::alerte($lot, 'eclosion', self::dateEclosionPrevue($lot), $jour);
            }
        }

        usort($alertes, fn (array $a, array $b) => $b['ecart'] <=> $a['ecart']);

        return $alertes;
    }

    private static function alerte(CycleCouveuse $lot, string $type, CarbonImmutable $date, CarbonImmutable $jour): array
    {
        return ['lot' => $lot, 'type' => $type, 'date' => $date, 'ecart' => (int) $date->diffInDays($jour, false)];
    }

    /**
     * Echeances a venir dans les [$jours] prochains jours : pour preparer, pas pour rattraper.
     *
     * @param  Collection<int, CycleCouveuse>  $lots
     * @return list<array{lot: CycleCouveuse, type: string, date: CarbonImmutable, ecart: int}>
     */
    public static function aVenir(Collection $lots, CarbonInterface $t, int $jours = 3): array
    {
        $jour = self::jour($t);
        $limite = $jour->addDays($jours);
        $aVenir = [];

        $ajouter = function (CycleCouveuse $lot, string $type, CarbonImmutable $date) use (&$aVenir, $jour, $limite) {
            if ($date->gt($jour) && ! $date->gt($limite)) {
                $aVenir[] = self::alerte($lot, $type, $date, $jour);
            }
        };

        foreach ($lots as $lot) {
            if (! self::enCours($lot)) {
                continue;
            }
            if ($lot->oeufs_blancs_j7 === null) {
                $ajouter($lot, 'mirage1', self::dateMirage1($lot));
            }
            if ($lot->oeufs_gates_j14 === null) {
                $ajouter($lot, 'mirage2', self::dateMirage2($lot));
            }
            $ajouter($lot, 'eclosion', self::dateEclosionPrevue($lot));
        }

        usort($aVenir, fn (array $a, array $b) => $a['date'] <=> $b['date']);

        return $aVenir;
    }

    public static function libelleEcheance(string $type): array
    {
        return [
            'mirage1' => ['Mirage 1', 'Retrait des œufs clairs'],
            'mirage2' => ['Mirage 2', 'Retrait des œufs gâtés'],
            'eclosion' => ['Éclosion', 'Relève des poussins'],
        ][$type];
    }

    // ----------------------------------------------------------- Agregats

    /**
     * TER moyen a la date [$t] : moyenne PONDEREE par les œufs retenus (pas moyenne des taux),
     * sur les lots dont l'eclosion est enregistree et dont la date d'eclosion prevue n'est pas
     * posterieure a [$t].
     *
     * @param  Collection<int, CycleCouveuse>  $lots
     */
    public static function terMoyen(Collection $lots, CarbonInterface $t): ?float
    {
        $jour = self::jour($t);
        $eclos = 0;
        $retenus = 0;

        foreach ($lots as $lot) {
            if ($lot->poussins_nes === null || self::dateEclosionPrevue($lot)->gt($jour) || self::retenus($lot) <= 0) {
                continue;
            }
            $eclos += $lot->poussins_nes;
            $retenus += self::retenus($lot);
        }

        return $retenus <= 0 ? null : $eclos / $retenus * 100;
    }

    /** Taux d'eclosion BRUT moyen (moyenne arithmetique des taux bruts), `null` sans eclosion. */
    public static function tauxBrutMoyen(Collection $lots): ?float
    {
        $taux = $lots->map(fn (CycleCouveuse $l) => self::tauxBrut($l))->filter(fn ($x) => $x !== null);

        return $taux->isEmpty() ? null : $taux->sum() / $taux->count();
    }

    /** Poussins attendus sur les cycles en cours, projetes depuis le taux brut moyen historique. */
    public static function poussinsAttendus(Collection $lots): int
    {
        $taux = self::tauxBrutMoyen($lots);
        if ($taux === null) {
            return 0;
        }
        $oeufs = $lots->filter(fn (CycleCouveuse $l) => self::enCours($l))->sum('oeufs_couves');

        return (int) round($oeufs * $taux / 100);
    }

    public static function oeufsEnIncubation(Collection $lots): int
    {
        return (int) $lots->filter(fn (CycleCouveuse $l) => self::enCours($l))
            ->sum(fn (CycleCouveuse $l) => self::retenus($l));
    }

    /** Œufs en incubation dans une machine (retenus apres mirages, lots en cours seulement). */
    public static function occupation(Collection $lots, string $machineId): int
    {
        return (int) $lots->filter(fn (CycleCouveuse $l) => $l->machine_id === $machineId && self::enCours($l))
            ->sum(fn (CycleCouveuse $l) => self::retenus($l));
    }

    /** Lots en cours dont un mirage est deja du mais n'a pas ete saisi. */
    public static function miragesManquants(Collection $lots, CarbonInterface $t): Collection
    {
        $jour = self::jour($t);

        return $lots->filter(function (CycleCouveuse $l) use ($jour) {
            if (! self::enCours($l)) {
                return false;
            }

            return ($l->oeufs_blancs_j7 === null && ! $jour->lt(self::dateMirage1($l)))
                || ($l->oeufs_gates_j14 === null && ! $jour->lt(self::dateMirage2($l)));
        })->values();
    }

    // -------------------------------------------- Statistiques des mirages

    /** Infertilite : clairs / charges × 100 (il accuse les reproducteurs, pas la machine). */
    public static function tauxInfertilite(CycleCouveuse $lot): ?float
    {
        return $lot->oeufs_blancs_j7 === null || $lot->oeufs_couves <= 0
            ? null
            : $lot->oeufs_blancs_j7 / $lot->oeufs_couves * 100;
    }

    /** Mortalite embryonnaire : gates / œufs presents au second mirage × 100 (il accuse la conduite). */
    public static function mortaliteEmbryonnaire(CycleCouveuse $lot): ?float
    {
        if ($lot->oeufs_gates_j14 === null) {
            return null;
        }
        $presents = $lot->oeufs_couves - ($lot->oeufs_blancs_j7 ?? 0);

        return $presents <= 0 ? null : $lot->oeufs_gates_j14 / $presents * 100;
    }

    /** Perte du lot : (charges − eclos) / charges × 100, seulement une fois eclos. */
    public static function tauxPerteLot(CycleCouveuse $lot): ?float
    {
        if ($lot->poussins_nes === null || $lot->oeufs_couves <= 0) {
            return null;
        }

        return ($lot->oeufs_couves - $lot->poussins_nes) / $lot->oeufs_couves * 100;
    }

    /**
     * Agregat des mirages sur un ensemble de lots.
     *
     * @param  Collection<int, CycleCouveuse>  $lots
     * @return array<string, int|float|null>
     */
    public static function agregat(Collection $lots): array
    {
        $chargesAvecMirage1 = $lots->filter(fn ($l) => $l->oeufs_blancs_j7 !== null)->sum('oeufs_couves');
        $presentsAvecMirage2 = $lots->filter(fn ($l) => $l->oeufs_gates_j14 !== null)
            ->sum(fn ($l) => $l->oeufs_couves - ($l->oeufs_blancs_j7 ?? 0));
        $retenusDesEclos = $lots->filter(fn ($l) => $l->poussins_nes !== null)
            ->sum(fn ($l) => self::retenus($l));
        $eclosTotal = $lots->sum(fn ($l) => $l->poussins_nes ?? 0);
        $clairs = $lots->sum(fn ($l) => $l->oeufs_blancs_j7 ?? 0);
        $gates = $lots->sum(fn ($l) => $l->oeufs_gates_j14 ?? 0);
        $closes = $lots->filter(fn ($l) => $l->poussins_nes !== null);
        $chargesCloses = $closes->sum('oeufs_couves');

        return [
            'lots' => $lots->count(),
            'charges' => (int) $lots->sum('oeufs_couves'),
            'clairs' => (int) $clairs,
            'gates' => (int) $gates,
            'retenus' => (int) $lots->sum(fn ($l) => self::retenus($l)),
            'eclos' => (int) $eclosTotal,
            'infertilite' => $chargesAvecMirage1 <= 0 ? null : $clairs / $chargesAvecMirage1 * 100,
            'mortalite' => $presentsAvecMirage2 <= 0 ? null : $gates / $presentsAvecMirage2 * 100,
            'ter' => $retenusDesEclos <= 0 ? null : $eclosTotal / $retenusDesEclos * 100,
            'perte' => $chargesCloses <= 0 ? null : ($chargesCloses - $closes->sum('poussins_nes')) / $chargesCloses * 100,
        ];
    }
}
