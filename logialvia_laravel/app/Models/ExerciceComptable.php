<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/** Exercice comptable — REFERENTIEL, cle naturelle : l'annee. Pose par le serveur. */
class ExerciceComptable extends Model
{
    protected $table = 'exercices_comptables';

    protected $primaryKey = 'annee';

    public $incrementing = false;

    protected $keyType = 'int';

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return ['is_cloture' => 'boolean', 'date_cloture' => 'datetime', 'annee' => 'integer'];
    }
}
