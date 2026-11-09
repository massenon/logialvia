<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Une journee d'une fiche d'elevage (`fiche_journee`) : une ligne par (espece, date).
 * Dates techniques a la microseconde ; `date` reste un TEXTE `AAAA-MM-JJ` (date civile,
 * jamais un instant : aucun cast, aucune conversion de fuseau).
 */
class FicheJournee extends Model
{
    use HasUuids;

    protected $table = 'fiche_journee';

    public $timestamps = false;

    protected $guarded = [];

    protected $dateFormat = 'Y-m-d H:i:s.u';

    protected function casts(): array
    {
        return [
            'achat' => 'integer', 'ne' => 'integer', 'vente' => 'integer',
            'mort_cat1' => 'integer', 'mort_cat2' => 'integer', 'mort_cat3' => 'integer', 'mort_cat4' => 'integer',
            'don_cat1' => 'integer', 'don_cat2' => 'integer', 'don_cat3' => 'integer', 'don_cat4' => 'integer',
            'effectif' => 'integer',
            'eff_cat1_day' => 'integer', 'eff_cat2_day' => 'integer', 'eff_cat3_day' => 'integer', 'eff_cat4_day' => 'integer',
            'srh' => 'integer', 'ts' => 'integer', 'stock_final_oeufs' => 'integer',
            'oeufs_pondus' => 'integer', 'oeufs_casses' => 'integer', 'sorties_plateaux' => 'integer',
            'poids_general_g' => 'integer',
            'traitement_valide' => 'boolean',
            'is_recorded' => 'boolean',
            'updated_at' => 'datetime',
            'serveur_modifie_le' => 'datetime',
        ];
    }
}
