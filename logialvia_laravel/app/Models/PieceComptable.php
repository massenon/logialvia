<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Piece comptable — FAIT IMMUABLE, voyage avec ses lignes. Dates a la microseconde. */
class PieceComptable extends Model
{
    use HasUuids;

    protected $table = 'pieces_comptables';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'date_ecriture' => 'datetime',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'exercice_annee' => 'integer',
        ];
    }

    public function lignes(): HasMany
    {
        return $this->hasMany(EcritureComptable::class, 'piece_id');
    }
}
