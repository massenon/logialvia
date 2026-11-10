<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/** Module (filiere) basculable — miroir de `MODULES_ACTIFS` du poste. */
class ModuleActif extends Model
{
    use HasUuids;

    protected $table = 'modules_actifs';

    protected $fillable = ['module_id', 'is_actif', 'espece'];

    protected function casts(): array
    {
        return ['is_actif' => 'boolean'];
    }
}
