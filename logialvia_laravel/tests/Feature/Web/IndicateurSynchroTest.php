<?php

namespace Tests\Feature\Web;

use App\Livewire\IndicateurSynchro;
use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\Poste;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/** Icône de synchronisation de la barre du haut : état réel des postes, réservé à qui gère les postes. */
class IndicateurSynchroTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        ParametresEntreprise::courant();
    }

    private function connecte(string $role): User
    {
        $u = User::factory()->create(['username' => $role, 'name' => ucfirst($role)]);
        $u->assignRole($role);
        $this->actingAs($u);

        return $u;
    }

    private function poste(string $code, ?\DateTimeInterface $contact, bool $revoque = false): Poste
    {
        return Poste::query()->create([
            'device_id' => (string) \Illuminate\Support\Str::uuid(), 'code' => $code,
            'appaire_le' => now()->subDay(), 'dernier_contact_le' => $contact, 'revoque_le' => $revoque ? now() : null,
        ]);
    }

    public function test_sans_poste_l_icone_dit_qu_aucun_poste_n_est_appaire(): void
    {
        $this->connecte('admin');

        Livewire::test(IndicateurSynchro::class)->assertSee('Aucun poste appairé')->assertSee("Aucun poste n'est appairé à ce serveur.", false);
    }

    public function test_un_poste_joint_a_l_instant_est_en_ligne(): void
    {
        $this->connecte('admin');
        $this->poste('P1', now()->subSeconds(20));
        $this->poste('P2', now()->subSeconds(60));

        Livewire::test(IndicateurSynchro::class)->assertSee('2 postes en ligne')->assertSeeHtml('data-synchro-poste="P1"')->assertSee('En ligne')->assertDontSee('sans contact');
    }

    public function test_un_poste_silencieux_depuis_une_heure_est_signale_en_rouge(): void
    {
        $this->connecte('admin');
        $this->poste('P1', now()->subSeconds(10));
        $this->poste('P2', now()->subHour());

        Livewire::test(IndicateurSynchro::class)->assertSee('1 poste sans contact')->assertSee('Sans contact')->assertSeeHtml('text-error-deep');
    }

    public function test_un_poste_revoque_ne_compte_pas_et_n_alerte_pas(): void
    {
        $this->connecte('admin');
        $this->poste('P1', now()->subSeconds(5));
        $this->poste('P2', now()->subDays(3), revoque: true);

        Livewire::test(IndicateurSynchro::class)->assertSee('1 poste en ligne')->assertSee('Révoqué');
    }

    public function test_un_poste_jamais_joint_est_signale(): void
    {
        $this->connecte('admin');
        $this->poste('P1', null);

        Livewire::test(IndicateurSynchro::class)->assertSee('1 poste sans contact')->assertSee('Appairé, jamais joint');
    }

    public function test_l_icone_figure_dans_la_barre_pour_l_administrateur_seulement(): void
    {
        $this->connecte('admin');
        $this->get('/dashboard')->assertOk()->assertSeeHtml('data-synchro');
        auth()->logout();

        foreach (['caissier', 'animalier'] as $role) {
            $this->connecte($role);
            $this->get('/dashboard')->assertOk()->assertDontSeeHtml('data-synchro');
            auth()->logout();
        }
    }

    public function test_le_composant_refuse_un_compte_sans_le_droit_de_gerer_les_postes(): void
    {
        $this->connecte('caissier');

        Livewire::test(IndicateurSynchro::class)->assertForbidden();
    }
}
