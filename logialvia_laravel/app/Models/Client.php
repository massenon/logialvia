<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Client — table de FAITS synchronisee. Dates a la microseconde : le curseur de
 * tirage s'y compare, une precision a la seconde ferait sauter des lignes.
 */
class Client extends Model
{
    use HasUuids;

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'solde_creance' => 'float',
            'date_naissance' => 'date:Y-m-d',
            'dernier_contact' => 'datetime',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
            'supprime_le' => 'datetime',
        ];
    }
}
