<?php

namespace App\Sync\Tables;

use App\Models\ModuleActif;
use App\Sync\TableSync;

/** Referentiel : le serveur gagne. */
class ModulesActifsTable extends TableSync
{
    public function nom(): string
    {
        return 'modules_actifs';
    }

    public function nature(): string
    {
        return self::REFERENTIEL;
    }

    protected function modele(): string
    {
        return ModuleActif::class;
    }

    public function colonneCurseur(): string
    {
        return 'updated_at';
    }
}
