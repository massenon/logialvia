<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Ligne d'ecriture : voyage DANS sa piece, jamais seule. Immuable. */
class EcritureComptable extends Model
{
    use HasUuids;

    protected $table = 'ecritures_comptables';

    public $timestamps = false;

    protected $guarded = [];

    protected function casts(): array
    {
        return ['debit' => 'float', 'credit' => 'float'];
    }

    public function piece(): BelongsTo
    {
        return $this->belongsTo(PieceComptable::class, 'piece_id');
    }
}
