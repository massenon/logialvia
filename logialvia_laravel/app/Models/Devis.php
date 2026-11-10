<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Devis de prestations — FAIT synchronise. Dates a la microseconde. */
class Devis extends Model
{
    use HasUuids;

    protected $table = 'devis';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'montant_estime' => 'float',
            'validite_jours' => 'integer',
            'date_emission' => 'datetime',
            'supprime_le' => 'datetime',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
        ];
    }

    public function dateExpiration()
    {
        return $this->date_emission->addDays($this->validite_jours);
    }
}
