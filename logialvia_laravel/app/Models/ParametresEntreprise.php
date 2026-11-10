<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Parametres de l'entreprise : UNE seule ligne (voir [self::courant()]). */
class ParametresEntreprise extends Model
{
    use HasUuids;

    protected $table = 'parametres_entreprise';

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return [
            'mecef_actif' => 'boolean',
            'mode_donnees_test' => 'boolean',
            'smtp_port' => 'integer',
            'delai_paiement_jours' => 'integer',
        ];
    }

    /** La ligne unique, creee avec ses valeurs par defaut si elle manque. */
    public static function courant(): self
    {
        // `fresh()` : une ligne creee sans attribut n'a, en memoire, aucune des valeurs
        // par defaut de la base (raison sociale, prefixes) tant qu'on ne la relit pas.
        return self::query()->first() ?? self::query()->create([])->fresh();
    }
}
