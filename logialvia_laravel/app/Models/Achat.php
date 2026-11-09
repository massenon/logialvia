<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Achat — FAIT synchronise. Dates a la microseconde. */
class Achat extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'date_achat' => 'datetime',
            'echeance' => 'datetime',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'total' => 'float',
            'paye' => 'float',
        ];
    }

    public function lignes(): HasMany
    {
        return $this->hasMany(LigneAchat::class, 'achat_id')->orderBy('ordre');
    }
}
