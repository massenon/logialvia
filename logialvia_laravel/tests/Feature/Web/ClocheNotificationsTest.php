<?php

namespace Tests\Feature\Web;

use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\User;
use App\Models\Vente;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\TestCase;

/** Cloche de la barre du haut : les alertes du compte, sur toutes les pages, selon ses droits. */
class ClocheNotificationsTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        ParametresEntreprise::courant();
        Cache::flush();
    }

    private function connecte(string $role): User
    {
        $u = User::factory()->create(['username' => $role, 'name' => ucfirst($role)]);
        $u->assignRole($role);
        $this->actingAs($u);

        return $u;
    }

    private function venteEnAvance(): Vente
    {
        $v = (new Vente)->forceFill([
            'id' => (string) \Illuminate\Support\Str::uuid(), 'device_id' => (string) \Illuminate\Support\Str::uuid(), 'reference' => 'V-P1-2026-1',
            'portee_reference' => '', 'client' => 'Amina Bako', 'client_id' => null,
            'date_vente' => now(), 'mode' => 'Espèces', 'status' => 'Avance',
            'total' => 10000, 'paye' => 2000, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $v->save();

        return $v;
    }

    public function test_sans_alerte_la_cloche_le_dit_et_n_a_pas_de_pastille(): void
    {
        $this->connecte('admin');

        $this->get('/ventes')->assertOk()->assertSee('Aucune alerte en cours.')->assertDontSeeHtml('bg-error-deep text-caption');
    }

    public function test_une_vente_en_avance_non_soldee_alerte_sur_toutes_les_pages(): void
    {
        $this->venteEnAvance();
        $this->connecte('admin');

        foreach (['/ventes', '/clients', '/elevage/goliaths'] as $page) {
            Cache::flush();
            $this->get($page)->assertOk()
                ->assertSee('Soldes restant dus — 1 vente(s) en avance non soldée(s).')
                ->assertSeeHtml('bg-error-deep text-caption');
        }
    }

    public function test_un_animalier_ne_voit_pas_les_alertes_de_vente(): void
    {
        $this->venteEnAvance();
        $this->connecte('animalier');

        $this->get('/elevage/goliaths')->assertOk()->assertDontSee('Soldes restant dus');
    }
}
