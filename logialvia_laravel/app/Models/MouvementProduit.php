<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Mouvement de produit vendable — FAIT immuable du journal. Dates a la microseconde. */
class MouvementProduit extends Model
{
    use HasUuids;

    protected $table = 'mouvements_produit';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'horodatage' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'quantite' => 'float',
        ];
    }
}
