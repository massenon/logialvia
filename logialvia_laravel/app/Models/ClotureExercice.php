<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Fait de cloture annuelle recu d'un poste (trace du « fait lourd »). */
class ClotureExercice extends Model
{
    use HasUuids;

    protected $table = 'clotures_exercice';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return ['date_cloture' => 'datetime', 'updated_at' => 'datetime', 'serveur_modifie_le' => 'datetime'];
    }
}
