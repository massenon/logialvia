<?php

namespace App\Sync\Tables;

use App\Models\TauxRationPoids;
use App\Sync\TableSync;

/**
 * Referentiel : le serveur gagne. Un poste ne l'ENVOIE pas, il le PROPOSE
 * (`POST /api/sync/demandes`, type `taux_ration_poids`). Cle naturelle : (espece, poids min).
 */
class TauxRationPoidsTable extends TableSync
{
    public function nom(): string
    {
        return 'taux_ration_poids';
    }

    public function nature(): string
    {
        return self::REFERENTIEL;
    }

    protected function modele(): string
    {
        return TauxRationPoids::class;
    }

    public function colonneCurseur(): string
    {
        return 'updated_at';
    }

    public function droitLecture(): ?string
    {
        return 'view-elevage';
    }
}
