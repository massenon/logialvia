<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Groupe de taxe (grille de la facturation e-MECeF) — REFERENTIEL, miroir de `GROUPES_TAXE`
 * du poste. Dates a la microseconde : `created_at == updated_at` signale une valeur de semis.
 */
class GroupeTaxe extends Model
{
    use HasUuids;

    protected $table = 'groupes_taxe';

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return ['taux' => 'float', 'ordre' => 'integer'];
    }
}
