<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Facture (FV) ou facture d'avoir (FA) — FAIT synchronise. Dates a la microseconde. */
class Facture extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'date_facture' => 'datetime',
            'date_normalisation' => 'datetime',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'total_ht' => 'float',
            'total_taxe' => 'float',
            'total_ttc' => 'float',
        ];
    }

    public function lignes(): HasMany
    {
        return $this->hasMany(LigneFacture::class, 'facture_id');
    }
}
