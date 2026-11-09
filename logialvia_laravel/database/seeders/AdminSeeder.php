<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;

/**
 * Premier administrateur. Le mot de passe vient de l'ENVIRONNEMENT
 * (`ADMIN_INITIAL_PASSWORD`), jamais du code : un mot de passe ecrit dans un depot
 * public est un mot de passe publie. Il doit etre change a la premiere connexion.
 *
 * Sans cette variable, rien n'est cree (et le seeder le dit) : mieux vaut pas de
 * compte qu'un compte au mot de passe connu.
 */
class AdminSeeder extends Seeder
{
    public function run(): void
    {
        $motDePasse = config('logialvia.admin.password');

        if (! is_string($motDePasse) || \App\Support\RegleMotDePasse::erreur($motDePasse) !== null) {
            $this->command?->warn(
                'ADMIN_INITIAL_PASSWORD absent ou trop faible (8 caracteres, 1 majuscule, 1 chiffre) : aucun administrateur cree.',
            );

            return;
        }

        $admin = User::query()->firstOrCreate(
            ['username' => config('logialvia.admin.username')],
            [
                'name' => 'Administrateur',
                'password' => $motDePasse,
                'is_active' => true,
                'must_change_password' => true,
            ],
        );

        $admin->syncRoles(['admin']);
    }
}
