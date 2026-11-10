<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Fournisseur — FAIT synchronise. Dates a la microseconde (le curseur de tirage s'y compare). */
class Fournisseur extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'supprime_le' => 'datetime',
        ];
    }
}
