<?php

namespace App\Services\Comptabilite;

use App\Models\CloturePeriodique;
use App\Models\EcritureComptable;
use App\Models\ExerciceComptable;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;

/**
 * Regles de verrouillage et d'equilibre de la comptabilite (Doc F6 §3 et §9) — verifiees
 * par le SERVEUR, quel que soit le poste d'ou vient l'ecriture.
 *
 * ## Double verrouillage
 * Une ecriture est refusee si son EXERCICE est cloture (BR-CPT-001, definitif) ou si son
 * MOIS est cloture (BR-CPT-006). L'annee et le mois s'entendent dans le fuseau de
 * l'exploitation (`logialvia.fuseau`) : une ecriture du 1er janvier 00h30 a Natitingou
 * appartient a janvier, meme si son instant UTC est encore en decembre.
 */
final class Verrous
{
    public const TOLERANCE = 0.01;

    /** Premiere annee comptable acceptee : au-dela, une date est une erreur de saisie. */
    public const ANNEE_MIN = 2000;

    /** @return array{0: int, 1: int} [annee, mois] de l'instant, dans le fuseau metier. */
    public static function anneeMois(CarbonInterface $instant): array
    {
        $local = CarbonImmutable::instance($instant)->timezone(config('logialvia.fuseau'));

        return [(int) $local->year, (int) $local->month];
    }

    public static function anneeValide(int $annee): bool
    {
        return $annee >= self::ANNEE_MIN && $annee <= (int) CarbonImmutable::now(config('logialvia.fuseau'))->year + 1;
    }

    /**
     * L'exercice de cette annee, ouvert au besoin (un poste qui n'a jamais clos un exercice
     * l'ouvre en y ecrivant). `null` : annee hors des bornes acceptees.
     */
    public static function exercice(int $annee): ?ExerciceComptable
    {
        if (! self::anneeValide($annee)) {
            return null;
        }

        return ExerciceComptable::query()->firstOrCreate(
            ['annee' => $annee],
            ['is_cloture' => false],
        );
    }

    /** Motif du refus si l'exercice ou le mois est verrouille, sinon `null`. */
    public static function motifVerrou(int $annee, int $mois): ?string
    {
        $exercice = ExerciceComptable::query()->find($annee);
        if ($exercice !== null && $exercice->is_cloture) {
            return "L'exercice $annee est clôturé : aucune écriture ne peut y être ajoutée ni modifiée (BR-CPT-001).";
        }

        $cloture = CloturePeriodique::query()
            ->where('annee', $annee)->where('mois', $mois)->where('is_cloture', true)->exists();
        if ($cloture) {
            return "Le mois $mois/$annee est clôturé. Une administratrice peut le déclôturer pour correction (BR-CPT-006).";
        }

        return null;
    }

    /** @return array{debit: float, credit: float} Totaux de TOUTES les lignes de l'exercice. */
    public static function totaux(int $annee): array
    {
        $ligne = EcritureComptable::query()
            ->join('pieces_comptables', 'pieces_comptables.id', '=', 'ecritures_comptables.piece_id')
            ->where('pieces_comptables.exercice_annee', $annee)
            ->selectRaw('COALESCE(SUM(ecritures_comptables.debit), 0) as d, COALESCE(SUM(ecritures_comptables.credit), 0) as c')
            ->first();

        return ['debit' => (float) $ligne->d, 'credit' => (float) $ligne->c];
    }

    /** La balance de l'exercice est-elle equilibree (BR-CPT-004) ? */
    public static function exerciceEquilibre(int $annee): bool
    {
        $t = self::totaux($annee);

        return abs($t['debit'] - $t['credit']) < self::TOLERANCE;
    }
}
