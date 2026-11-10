<?php

namespace App\Services\Comptabilite;

use App\Models\EcritureComptable;
use App\Models\ExerciceComptable;
use App\Models\PlanComptable;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * Lecture du livre comptable DU SERVEUR : toutes les pieces recues de tous les postes
 * (grand livre = TOUS les faits). Les lectures web sont calculees ici, a partir des
 * ecritures — jamais d'agregat stocke.
 */
final class LivreComptable
{
    /**
     * Toutes les lignes d'ecriture, tous exercices, de la plus ancienne a la plus recente.
     *
     * @return Collection<int, LigneEcriture>
     */
    public static function toutes(): Collection
    {
        $fuseau = config('logialvia.fuseau');
        $clos = ExerciceComptable::query()->where('is_cloture', true)->pluck('annee')->flip();

        return EcritureComptable::query()
            ->join('pieces_comptables as p', 'p.id', '=', 'ecritures_comptables.piece_id')
            ->select([
                'ecritures_comptables.id', 'ecritures_comptables.piece_id', 'ecritures_comptables.numero_compte',
                'ecritures_comptables.debit', 'ecritures_comptables.credit', 'ecritures_comptables.libelle',
                'ecritures_comptables.axe_analytique',
                'p.exercice_annee', 'p.date_ecriture', 'p.journal_code', 'p.numero_piece', 'p.vente_ref',
                'p.achat_ref', 'p.contrepasse_de', 'p.device_id', 'p.updated_at as saisie',
            ])
            ->orderBy('p.date_ecriture')->orderBy('p.updated_at')->orderBy('ecritures_comptables.id')
            ->get()
            ->map(fn ($l) => new LigneEcriture(
                id: $l->id,
                pieceId: $l->piece_id,
                exercice: (int) $l->exercice_annee,
                compte: $l->numero_compte,
                date: CarbonImmutable::parse($l->date_ecriture, 'UTC')->timezone($fuseau),
                debit: (float) $l->debit,
                credit: (float) $l->credit,
                libelle: $l->libelle,
                journal: $l->journal_code,
                numeroPiece: $l->numero_piece,
                venteRef: $l->vente_ref,
                achatRef: $l->achat_ref,
                axe: $l->axe_analytique,
                contrepasseDe: $l->contrepasse_de,
                deviceId: $l->device_id,
                verrouillee: $clos->has((int) $l->exercice_annee),
            ))
            ->values();
    }

    /** @return Collection<int, LigneEcriture> */
    public static function exercice(Collection $toutes, int $annee): Collection
    {
        return $toutes->filter(fn (LigneEcriture $e) => $e->exercice === $annee)->values();
    }

    /** Ecritures des exercices ANTERIEURS : elles forment les soldes d'ouverture. */
    public static function anterieures(Collection $toutes, int $annee): Collection
    {
        return $toutes->filter(fn (LigneEcriture $e) => $e->exercice < $annee)->values();
    }

    /** @return list<int> Exercices connus, du plus recent au plus ancien (l'annee courante toujours presente). */
    public static function exercices(): array
    {
        $annees = ExerciceComptable::query()->pluck('annee')->map(fn ($a) => (int) $a)->all();
        $courante = (int) CarbonImmutable::now(config('logialvia.fuseau'))->year;
        if (! in_array($courante, $annees, true)) {
            $annees[] = $courante;
        }
        rsort($annees);

        return $annees;
    }

    /** @return Collection<string, PlanComptable> Le plan, par numero, ordonne. */
    public static function plan(): Collection
    {
        return PlanComptable::query()->orderBy('numero_compte')->get()->keyBy('numero_compte');
    }

    /** L'exercice choisi, borne aux exercices connus (jamais une annee saisie a la main sans controle). */
    public static function exerciceChoisi(?int $demande): int
    {
        $connus = self::exercices();
        if ($demande !== null && in_array($demande, $connus, true)) {
            return $demande;
        }
        // Par defaut, comme au poste : l'annee en cours (sinon le plus recent exercice connu).
        $courante = (int) CarbonImmutable::now(config('logialvia.fuseau'))->year;

        return in_array($courante, $connus, true) ? $courante : $connus[0];
    }
}
