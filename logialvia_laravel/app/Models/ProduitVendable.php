<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Produit du catalogue — REFERENTIEL (sans stock : donnee derivee, jamais synchronisee). */
class ProduitVendable extends Model
{
    use HasUuids;

    protected $table = 'produits_vendables';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'price' => 'float',
            'price_max' => 'float',
            'cout_revient' => 'float',
            'threshold' => 'integer',
            'saisi_le' => 'datetime',
            'archive_le' => 'datetime',
        ];
    }
}
