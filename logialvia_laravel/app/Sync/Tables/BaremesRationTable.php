<?php

namespace App\Sync\Tables;

use App\Models\BaremeRation;
use App\Sync\TableSync;

/**
 * Referentiel : le serveur gagne. Un poste ne l'ENVOIE pas, il le PROPOSE
 * (`POST /api/sync/demandes`, type `bareme_ration`). Cle naturelle : (espece, stade).
 */
class BaremesRationTable extends TableSync
{
    public function nom(): string
    {
        return 'baremes_ration';
    }

    public function nature(): string
    {
        return self::REFERENTIEL;
    }

    protected function modele(): string
    {
        return BaremeRation::class;
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
