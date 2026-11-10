<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Lot d'incubation (et ses mirages) — FAIT synchronise. Dates a la microseconde : le
 * curseur de tirage s'y compare. `date_incubation` est une date civile (sans fuseau).
 */
class CycleCouveuse extends Model
{
    use HasUuids;

    protected $table = 'cycle_couveuse';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'date_incubation' => 'date:Y-m-d',
            'oeufs_couves' => 'integer',
            'poussins_nes' => 'integer',
            'oeufs_perdus' => 'integer',
            'oeufs_blancs_j7' => 'integer',
            'oeufs_gates_j14' => 'integer',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'supprime_le' => 'datetime',
        ];
    }
}
