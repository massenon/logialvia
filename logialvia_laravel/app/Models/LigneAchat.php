<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Ligne d'achat : voyage DANS son achat, jamais seule. Immuable apres creation. */
class LigneAchat extends Model
{
    use HasUuids;

    protected $table = 'lignes_achat';

    public $timestamps = false;

    protected $guarded = [];

    protected function casts(): array
    {
        return ['qte' => 'float', 'pu_achat' => 'float'];
    }
}
