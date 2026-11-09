<?php

namespace App\Sync\Tables;

use App\Models\PlanComptable;
use App\Sync\TableSync;
use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Builder;

/**
 * Plan comptable : REFERENTIEL, le serveur gagne. Cle naturelle : le numero de compte
 * (le meme sur tous les postes, plan seme a l'identique par `PlanComptableSeeder`).
 *
 * Un poste ne l'ENVOIE pas, il le PROPOSE (`POST /api/sync/demandes`, type
 * `compte_comptable`) ; le serveur decide et redistribue. Un compte jamais decide a
 * `updated_at == created_at` : valeur de semis, que le poste n'absorbe pas.
 */
class PlanComptableTable extends TableSync
{
    public function nom(): string
    {
        return 'plan_comptable';
    }

    public function nature(): string
    {
        return self::REFERENTIEL;
    }

    protected function modele(): string
    {
        return PlanComptable::class;
    }

    public function colonneCurseur(): string
    {
        return 'updated_at';
    }

    public function droitLecture(): ?string
    {
        return 'view-comptabilite';
    }

    /** L'ordre de tirage d'un referentiel a cle texte : par numero de compte. */
    public function requeteTirage(?CarbonInterface $depuis, CarbonInterface $jusqua): Builder
    {
        $colonne = $this->colonneCurseur();
        $requete = $this->requete()->where($colonne, '<=', $jusqua->format('Y-m-d H:i:s.u'));
        if ($depuis !== null) {
            $requete->where($colonne, '>=', $depuis->format('Y-m-d H:i:s.u'));
        }

        return $requete->orderBy($colonne)->orderBy('numero_compte');
    }
}
