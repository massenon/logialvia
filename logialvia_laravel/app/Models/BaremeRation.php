<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Bareme de rationnement (espece + stade) — REFERENTIEL, pierre tombale `archive_le`. */
class BaremeRation extends Model
{
    use HasUuids;

    protected $table = 'baremes_ration';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'ration_grammes_par_jour' => 'integer',
            'confirme' => 'boolean',
            'saisi_le' => 'datetime',
            'archive_le' => 'datetime',
        ];
    }
}
