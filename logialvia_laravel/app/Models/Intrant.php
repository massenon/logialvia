<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

/** Intrant — REFERENTIEL (sans stock ni PMP : propres a chaque poste). Cle : le code. */
class Intrant extends Model
{
    protected $primaryKey = 'code';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    /**
     * Pierre tombale (`archive_le`, 47h D4) : un intrant supprime au poste est ARCHIVE, jamais
     * efface. Les ecrans (web) ne voient que les intrants actifs ; la synchronisation, elle,
     * lit et sert aussi les archives (`withoutGlobalScopes`).
     */
    protected static function booted(): void
    {
        static::addGlobalScope('actifs', fn (Builder $q) => $q->whereNull('archive_le'));
    }

    protected function casts(): array
    {
        return ['threshold' => 'integer', 'saisi_le' => 'datetime', 'archive_le' => 'datetime'];
    }
}
