<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Incubateur du couvoir — FAIT synchronise. Dates a la microseconde (curseur de tirage). */
class MachineIncubateur extends Model
{
    use HasUuids;

    protected $table = 'machines_incubateur';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'capacite_oeufs' => 'integer',
            'active' => 'boolean',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'supprime_le' => 'datetime',
        ];
    }
}
