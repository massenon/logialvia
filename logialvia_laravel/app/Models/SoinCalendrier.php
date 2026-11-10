<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Soin du calendrier — FAIT synchronise. Dates a la microseconde. */
class SoinCalendrier extends Model
{
    use HasUuids;

    protected $table = 'soins_calendrier';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'date_prevue' => 'date:Y-m-d',
            'remanence_jours' => 'integer',
            'cout_fcfa' => 'integer',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
        ];
    }
}
