<?php

namespace Tests\Feature\Web;

use App\Livewire\Aide;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Aide & À Propos » : page statique, FAQ filtrable, vignettes filtrees par droit. */
class AideWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
    }

    private function utilisateur(string $role, string $username = 'u'): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/aide')->assertRedirect(route('login'));
    }

    public function test_tout_compte_connecte_ouvre_l_aide(): void
    {
        foreach (['admin', 'comptable', 'caissier', 'animalier'] as $i => $role) {
            $this->actingAs($this->utilisateur($role, "u$i"))->get('/aide')
                ->assertOk()->assertSee('Aide & À Propos')->assertDontSee('arrive bientôt');
        }
    }

    public function test_nom_version_et_editeur_sont_affiches(): void
    {
        Livewire::actingAs($this->utilisateur('caissier'))->test(Aide::class)
            ->assertSee('LogiALVIA v1.0.0')->assertSee('Version v1.0.0')
            ->assertSee('Application de Gestion et de Suivi Avicole d\'ALLMANY', false)
            ->assertSee('FAGUEZ SARL')->assertSee('Dr Rhodes MASSENON')
            ->assertSeeHtml('href="/contact"');
    }

    public function test_les_cinq_questions_du_poste_sont_la(): void
    {
        $page = Livewire::actingAs($this->utilisateur('admin'))->test(Aide::class);
        $page->assertSeeInOrder([
            'Comment enregistrer une nouvelle vente ?', 'Comment activer ou désactiver une filière (ex. Lapins) ?',
            'Comment fonctionne l', 'Comment administrer une dose et décrémenter le stock ?',
            'Comment relancer un client avec un solde impayé ?',
        ]);
        $this->assertSame(5, substr_count($page->html(), 'data-question'));
    }

    public function test_la_recherche_filtre_sur_les_mots_cles_et_le_texte(): void
    {
        Livewire::actingAs($this->utilisateur('admin'))->test(Aide::class)
            ->set('recherche', 'lapins')->assertSee('Comment activer ou désactiver')->assertDontSee('Comment enregistrer une nouvelle vente')
            // mot-cle sans accent absent du texte affiche
            ->set('recherche', 'desactiver')->assertSee('Comment activer ou désactiver')
            // dans la reponse seulement
            ->set('recherche', 'badge rouge')->assertSee('alerte de stock critique')->assertDontSee('Comment relancer')
            ->set('recherche', '  VENTE ')->assertSee('Comment enregistrer une nouvelle vente')
            ->set('recherche', 'zzzz')->assertSee('Aucun résultat pour cette recherche.')->assertDontSeeHtml('data-question')
            ->set('recherche', '')->assertDontSee('Aucun résultat');
    }

    public function test_un_administrateur_voit_les_huit_vignettes_dans_l_ordre(): void
    {
        $page = Livewire::actingAs($this->utilisateur('admin'))->test(Aide::class);

        $page->assertSeeInOrder([
            'Élevage & Couveuse', 'Ventes & Clients', 'Achats & Fournisseurs', 'Stocks & Catalogue',
            'Santé Animale', 'Clients & Relances', 'Comptabilité', 'Rapports & États',
        ]);
        foreach (['/elevage/dashboard', '/ventes', '/achats', '/stocks', '/elevage/soins', '/clients', '/comptabilite', '/rapports'] as $route) {
            $page->assertSeeHtml('data-vignette="'.$route.'"');
        }
    }

    public function test_une_vignette_n_est_proposee_qu_a_qui_peut_l_ouvrir(): void
    {
        $caissier = Livewire::actingAs($this->utilisateur('caissier'))->test(Aide::class);
        $caissier->assertSeeHtml('data-vignette="/ventes"')->assertSeeHtml('data-vignette="/clients"')
            ->assertDontSeeHtml('data-vignette="/comptabilite"')->assertDontSeeHtml('data-vignette="/achats"')
            ->assertDontSeeHtml('data-vignette="/elevage/dashboard"')->assertDontSeeHtml('data-vignette="/rapports"');

        Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(Aide::class)
            ->assertSeeHtml('data-vignette="/elevage/dashboard"')->assertSeeHtml('data-vignette="/elevage/soins"')
            ->assertDontSeeHtml('data-vignette="/ventes"');
    }
}
