<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Effet de stock appliqué par un poste désigné (`47s_`) — FAIT immuable. Une ligne par
 * (fait, nature) : « réception », « annulation_reception », « vente », « annulation_vente »,
 * « correction ». Dates à la microseconde.
 */
class EffetStock extends Model
{
    use HasUuids;

    protected $table = 'effets_stock';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'applique_le' => 'datetime',
            'serveur_modifie_le' => 'datetime',
        ];
    }

    public function estUnAvertissement(): bool
    {
        return $this->etat !== 'applique';
    }
}
