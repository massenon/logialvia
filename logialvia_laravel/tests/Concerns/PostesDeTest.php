<?php

namespace Tests\Concerns;

use App\Models\User;
use App\Services\PostesService;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Support\Str;

/** Postes appaires pour les tests de synchronisation. */
trait PostesDeTest
{
    protected function amorcerSocle(): void
    {
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        \App\Models\ParametresEntreprise::courant();
    }

    protected function compteAvecRole(string $role, string $username): User
    {
        $utilisateur = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $utilisateur->assignRole($role);

        return $utilisateur;
    }

    /** @return array{jeton: string, device: string, utilisateur: User} */
    protected function poste(string $role = 'caissier', ?string $username = null): array
    {
        $utilisateur = $this->compteAvecRole($role, $username ?? $role.'-'.Str::random(5));
        $device = (string) Str::uuid();
        $appairage = app(PostesService::class)->appairer($utilisateur, $device);

        return ['jeton' => $appairage['jeton'], 'device' => $device, 'utilisateur' => $utilisateur];
    }

    /**
     * Requete portant ce jeton. Les requetes d'un MEME test partagent la garde
     * d'authentification : on l'oublie avant chaque appel, comme le fait un vrai
     * serveur entre deux requetes.
     */
    protected function avecJeton(string $jeton): static
    {
        $this->app['auth']->forgetGuards();

        return $this->withToken($jeton);
    }

    /** Une ligne `clients` telle qu'un poste l'enverrait. */
    protected function ligneClient(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(),
            'nom' => 'Client '.Str::random(4),
            'telephone' => null,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }
}
