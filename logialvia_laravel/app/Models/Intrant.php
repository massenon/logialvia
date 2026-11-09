<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** Intrant — REFERENTIEL (sans stock ni PMP : propres a chaque poste). Cle : le code. */
class Intrant extends Model
{
    protected $primaryKey = 'code';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected function casts(): array
    {
        return ['threshold' => 'integer', 'saisi_le' => 'datetime'];
    }
}
