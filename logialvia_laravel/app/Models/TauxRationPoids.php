<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Taux de ration par classe de poids vif (espece + poids minimal) — REFERENTIEL. */
class TauxRationPoids extends Model
{
    use HasUuids;

    protected $table = 'taux_ration_poids';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'poids_min_g' => 'integer',
            'poids_max_g' => 'integer',
            'taux_pourcent' => 'float',
            'confirme' => 'boolean',
            'saisi_le' => 'datetime',
            'archive_le' => 'datetime',
        ];
    }

    /** « Moins de 150 kg », « De 5 à moins de 20 g », « 500 g et plus » (comme le poste). */
    public function libelleClasse(): string
    {
        $poids = function (int $g): array {
            if ($g < 1000) {
                return [(string) $g, 'g'];
            }
            $kg = $g / 1000;

            return [$kg == round($kg) ? (string) (int) round($kg) : str_replace('.', ',', number_format($kg, 1, '.', '')), 'kg'];
        };

        $max = $this->poids_max_g;
        [$nb, $ub] = $poids($this->poids_min_g);
        if ($this->poids_min_g <= 0 && $max !== null) {
            [$nh, $uh] = $poids($max);

            return "Moins de $nh $uh";
        }
        if ($max === null) {
            return "$nb $ub et plus";
        }
        [$nh, $uh] = $poids($max);

        return $ub === $uh ? "De $nb à moins de $nh $uh" : "De $nb $ub à moins de $nh $uh";
    }
}
