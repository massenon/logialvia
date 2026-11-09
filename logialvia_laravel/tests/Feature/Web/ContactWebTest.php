<?php

namespace Tests\Feature\Web;

use App\Livewire\Contact;
use App\Models\DemandeReferentiel;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Contactez l'Éditeur » : coordonnees statiques, aucun envoi (declare). */
class ContactWebTest extends TestCase
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
        $this->get('/contact')->assertRedirect(route('login'));
    }

    public function test_tout_compte_connecte_ouvre_la_page(): void
    {
        foreach (['admin', 'comptable', 'caissier', 'animalier'] as $i => $role) {
            $this->actingAs($this->utilisateur($role, "u$i"))->get('/contact')
                ->assertOk()->assertSee('Contactez l\'Éditeur', false)->assertDontSee('arrive bientôt');
        }
    }

    public function test_les_coordonnees_de_l_editeur_sont_la(): void
    {
        Livewire::actingAs($this->utilisateur('caissier'))->test(Contact::class)
            ->assertSee('rarhodes06@gmail.com')->assertSeeHtml('href="mailto:rarhodes06@gmail.com"')
            ->assertSee('FAGUEZ SARL')->assertSee('Dr MASSENON Rhodes')
            ->assertSee('+229 01 51 33 50 40')->assertSee('+229 01 97 31 24 37')
            ->assertSee('contact@massenonrhodes.com');
    }

    public function test_aucun_formulaire_et_l_ecart_est_declare(): void
    {
        $page = Livewire::actingAs($this->utilisateur('caissier'))->test(Contact::class)
            ->assertSeeHtml('data-ecart="aucun-envoi"')->assertSee('n\'envoie aucun message', false)
            ->assertDontSee('Message envoyé')->assertDontSeeHtml('<form')->assertDontSeeHtml('<textarea')
            ->assertDontSeeHtml('type="submit"');

        $this->assertSame(0, DemandeReferentiel::query()->count());
        $this->assertStringContainsString('v1.0.0', $page->html());
    }

    public function test_la_page_n_expose_aucune_action_appelable_depuis_le_navigateur(): void
    {
        $propres = collect((new \ReflectionClass(Contact::class))->getMethods(\ReflectionMethod::IS_PUBLIC))
            ->filter(fn (\ReflectionMethod $m) => $m->class === Contact::class)->map->name->all();

        $this->assertSame(['render'], array_values($propres), 'seule la lecture existe : aucune methode d\'ecriture');
    }
}
