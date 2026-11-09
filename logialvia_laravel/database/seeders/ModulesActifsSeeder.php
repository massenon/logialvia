<?php

namespace Database\Seeders;

use App\Models\ModuleActif;
use Illuminate\Database\Seeder;

/**
 * Modules basculables, DESACTIVES par defaut (comme au poste). Idempotent : un
 * module deja present garde son etat, c'est un choix de la Gerante.
 */
class ModulesActifsSeeder extends Seeder
{
    public function run(): void
    {
        foreach (config('logialvia.modules') as $moduleId => $espece) {
            ModuleActif::query()->firstOrCreate(
                ['module_id' => $moduleId],
                ['is_actif' => false, 'espece' => $espece],
            );
        }
    }
}
