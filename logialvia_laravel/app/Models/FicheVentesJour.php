<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Compteur de ventes du jour d'UN poste (`fiche_ventes_jour`) : une ligne par
 * (poste, espece, date). La lecture SOMME les lignes du jour. `date` : texte `AAAA-MM-JJ`.
 */
class FicheVentesJour extends Model
{
    use HasUuids;

    protected $table = 'fiche_ventes_jour';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'qte' => 'integer',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
        ];
    }
}
