<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Entree d'infirmerie / quarantaine — FAIT synchronise. Dates a la microseconde. */
class EntreeInfirmerie extends Model
{
    use HasUuids;

    protected $table = 'infirmerie';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'date_entree' => 'date:Y-m-d',
            'date_sortie' => 'date:Y-m-d',
            'categorie_mortalite' => 'integer',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
        ];
    }
}
