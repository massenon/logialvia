<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Echeance du calendrier de prophylaxie — REFERENTIEL, pierre tombale `archive_le`. */
class EcheanceProphylaxie extends Model
{
    use HasUuids;

    protected $table = 'calendrier_prophylaxie';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'jour_cycle' => 'integer',
            'remanence_jours' => 'integer',
            'saisi_le' => 'datetime',
            'archive_le' => 'datetime',
        ];
    }
}
