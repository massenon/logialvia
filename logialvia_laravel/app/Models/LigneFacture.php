<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Ligne de facture : voyage DANS sa facture, jamais seule. Immuable apres creation. */
class LigneFacture extends Model
{
    use HasUuids;

    protected $table = 'lignes_facture';

    public $timestamps = false;

    protected $guarded = [];

    protected function casts(): array
    {
        return [
            'quantite' => 'float',
            'prix_unitaire_ht' => 'float',
            'taux_taxe' => 'float',
            'montant_ht' => 'float',
            'montant_taxe' => 'float',
        ];
    }
}
