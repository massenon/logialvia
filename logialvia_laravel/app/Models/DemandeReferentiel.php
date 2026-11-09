<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** Journal des demandes de modification de referentiel (voir la migration). */
class DemandeReferentiel extends Model
{
    protected $table = 'demandes_referentiel';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected function casts(): array
    {
        return ['donnees' => 'array'];
    }
}
