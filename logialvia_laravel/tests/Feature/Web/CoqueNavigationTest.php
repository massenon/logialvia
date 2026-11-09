<?php

namespace Tests\Feature\Web;

use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** La coque web : barre laterale filtree par droits et modules, routes protegees. */
class CoqueNavigationTest extends TestCase
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

    public function test_la_racine_mene_au_tableau_de_bord(): void
    {
        $this->connecte('admin');

        $this->get('/')->assertRedirect('/dashboard');
    }

    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/ventes')->assertRedirect(route('login'));
    }

    public function test_l_administrateur_voit_tous_les_groupes_actifs(): void
    {
        $this->connecte('admin');

        $page = $this->get('/dashboard')->assertOk();
        foreach (['PILOTAGE', 'ÉLEVAGE &amp; COUVEUSE', 'VENTES &amp; CLIENTS', 'ACHATS &amp; FOURNISSEURS', 'STOCKS &amp; CATALOGUE', 'COMPTABILITÉ', 'PARAMÈTRES', 'ÉDITIONS'] as $groupe) {
            $page->assertSee($groupe, false);
        }
        $page->assertSee('Postes &amp; Appairage', false);
    }

    public function test_un_caissier_ne_voit_pas_l_elevage_ni_la_comptabilite(): void
    {
        $this->connecte('caissier');

        $this->get('/dashboard')->assertOk()
            ->assertSee('VENTES &amp; CLIENTS', false)
            ->assertDontSee('COMPTABILITÉ')
            ->assertDontSee('ACHATS &amp; FOURNISSEURS', false)
            ->assertDontSee('Postes &amp; Appairage', false);
    }

    public function test_un_animalier_voit_l_elevage_mais_pas_les_ventes(): void
    {
        $this->connecte('animalier');

        $this->get('/dashboard')->assertOk()
            ->assertSee('Fiche Goliaths')
            ->assertDontSee('VENTES &amp; CLIENTS', false);
    }

    public function test_un_module_inactif_disparait_de_la_barre_et_ferme_sa_route(): void
    {
        $this->connecte('admin');
        // Les filieres optionnelles sont inactives tant que la Gerante ne les active pas.
        $this->get('/dashboard')->assertDontSee('Fiche Lapins');
        $this->get('/elevage/lapins')->assertNotFound();

        ModuleActif::query()->where('module_id', 'cuniculture')->update(['is_actif' => true]);
        $this->get('/dashboard')->assertSee('Fiche Lapins');
        $this->get('/elevage/lapins')->assertOk();

        ModuleActif::query()->where('module_id', 'cuniculture')->update(['is_actif' => false]);

        $this->get('/dashboard')->assertDontSee('Fiche Lapins');
        $this->get('/elevage/lapins')->assertNotFound();
    }

    public function test_la_facturation_mecef_suit_le_reglage_de_l_entreprise(): void
    {
        $this->connecte('admin');
        ParametresEntreprise::courant()->forceFill(['mecef_actif' => false])->save();
        $this->get('/dashboard')->assertDontSee('Facturation MeCeF');
        $this->get('/factures-mecef')->assertNotFound();

        ParametresEntreprise::courant()->forceFill(['mecef_actif' => true])->save();

        $this->get('/dashboard')->assertSee('Facturation MeCeF');
        $this->get('/factures-mecef')->assertOk();
    }

    public function test_sans_le_droit_la_route_est_interdite_meme_si_on_connait_l_adresse(): void
    {
        $this->connecte('caissier');

        $this->get('/comptabilite')->assertForbidden();
        $this->get('/elevage/goliaths')->assertForbidden();
        $this->get('/ventes')->assertOk();
    }

    public function test_un_ecran_non_converti_affiche_la_page_bientot(): void
    {
        $this->connecte('admin');

        $this->get('/comptabilite/balance')->assertOk()
            ->assertSee('Balance Générale')
            ->assertSee('Cet écran arrive bientôt sur le web');
    }

    public function test_l_entree_de_la_page_ouverte_est_marquee(): void
    {
        $this->connecte('admin');

        $this->get('/ventes')->assertSee('aria-current="page"', false);
    }

    public function test_le_menu_du_compte_mene_au_profil_a_l_aide_et_au_contact_pour_tous_les_roles(): void
    {
        foreach (['admin', 'comptable', 'caissier', 'animalier'] as $role) {
            $this->connecte($role);

            $this->get('/dashboard')->assertOk()
                ->assertSeeHtml('data-menu="compte"')
                ->assertSee('Mon Profil')->assertSee('Aide &amp; À Propos', false)->assertSee('Contact éditeur')
                ->assertSeeHtml('href="/profil"')->assertSeeHtml('href="/aide"')->assertSeeHtml('href="/contact"');

            foreach (['/profil', '/aide', '/contact'] as $page) {
                $this->get($page)->assertOk();
            }
            auth()->logout();
        }
    }

    public function test_un_visiteur_n_a_pas_de_menu_de_compte(): void
    {
        $this->get('/login')->assertDontSeeHtml('data-menu="compte"');
    }
}
