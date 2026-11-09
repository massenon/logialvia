<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Cloture (ou decloture) d'un mois — fait « dernier ecrivain gagne » par (annee, mois). */
class CloturePeriodique extends Model
{
    use HasUuids;

    protected $table = 'clotures_periodiques';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'is_cloture' => 'boolean',
            'date_cloture' => 'datetime',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'annee' => 'integer',
            'mois' => 'integer',
        ];
    }
}
