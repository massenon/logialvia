<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call([
            RolesAndPermissionsSeeder::class,
            ModulesActifsSeeder::class,
            ParametresEntrepriseSeeder::class,
            AdminSeeder::class,
        ]);
    }
}
