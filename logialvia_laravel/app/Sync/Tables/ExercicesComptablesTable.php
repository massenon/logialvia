<?php

namespace App\Sync\Tables;

use App\Models\ExerciceComptable;
use App\Sync\TableSync;
use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Builder;

/**
 * Exercices comptables : REFERENTIEL pose par le serveur. Cle naturelle : l'annee.
 *
 * Un poste ne l'envoie jamais : un exercice s'ouvre quand une ecriture y arrive, et se
 * CLOT par le fait lourd `clotures_exercice` (`ClotureExerciceTable`). Aucune declôture
 * (BR-CPT-001) : seule la remise a zero du serveur rouvre les exercices.
 */
class ExercicesComptablesTable extends TableSync
{
    public function nom(): string
    {
        return 'exercice_comptable';
    }

    public function nature(): string
    {
        return self::REFERENTIEL;
    }

    protected function modele(): string
    {
        return ExerciceComptable::class;
    }

    public function colonneCurseur(): string
    {
        return 'updated_at';
    }

    public function droitLecture(): ?string
    {
        return 'view-comptabilite';
    }

    public function requeteTirage(?CarbonInterface $depuis, CarbonInterface $jusqua): Builder
    {
        $colonne = $this->colonneCurseur();
        $requete = $this->requete()->where($colonne, '<=', $jusqua->format('Y-m-d H:i:s.u'));
        if ($depuis !== null) {
            $requete->where($colonne, '>=', $depuis->format('Y-m-d H:i:s.u'));
        }

        return $requete->orderBy($colonne)->orderBy('annee');
    }

    /** Sans `cloture_par` (identifiant interne) : le poste n'en a pas l'usage. */
    public function exporter($ligne): array
    {
        $donnees = parent::exporter($ligne);
        unset($donnees['cloture_par']);

        return $donnees;
    }
}
