<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Bande d'elevage : des sujets mis en place a une date, sur une filiere. `effectif_initial`
 * est une declaration INDICATIVE ; l'effectif reel n'est jamais stocke.
 */
class Bande extends Model
{
    use HasUuids;

    protected $table = 'bandes';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'effectif_initial' => 'integer',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
        ];
    }
}
