<?php

namespace App\Sync\Tables;

use App\Models\ParametresEntreprise;
use App\Sync\TableSync;
use Illuminate\Database\Eloquent\Model;

/** Referentiel : le serveur gagne. La marque de remise a zero n'est jamais servie ici. */
class ParametresEntrepriseTable extends TableSync
{
    public function nom(): string
    {
        return 'parametres_entreprise';
    }

    public function nature(): string
    {
        return self::REFERENTIEL;
    }

    protected function modele(): string
    {
        return ParametresEntreprise::class;
    }

    public function colonneCurseur(): string
    {
        return 'updated_at';
    }

    public function exporter(Model $ligne): array
    {
        $donnees = parent::exporter($ligne);
        unset($donnees['marque_remise_a_zero']); // servie a part (`reset_mark`)

        return $donnees;
    }
}
