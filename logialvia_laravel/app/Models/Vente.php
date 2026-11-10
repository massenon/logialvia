<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Vente — FAIT synchronise. Dates a la microseconde (le curseur de tirage s'y compare). */
class Vente extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'date_vente' => 'datetime',
            'echeance' => 'datetime',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'total' => 'float',
            'paye' => 'float',
            'livraison_frais' => 'float',
        ];
    }

    public function lignes(): HasMany
    {
        return $this->hasMany(LigneVente::class, 'vente_id')->orderBy('ordre');
    }
}
