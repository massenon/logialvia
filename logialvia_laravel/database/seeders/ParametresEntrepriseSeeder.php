<?php

namespace Database\Seeders;

use App\Models\ParametresEntreprise;
use Illuminate\Database\Seeder;

class ParametresEntrepriseSeeder extends Seeder
{
    public function run(): void
    {
        ParametresEntreprise::courant();
    }
}
