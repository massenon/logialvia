<?php

namespace Tests\Feature\Web;

use App\Models\ParametresEntreprise;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Non-regression des defauts trouves DANS UN VRAI NAVIGATEUR (`docs/logialvia/47n_TESTS_NAVIGATEUR.md`). Le comportement
 * lui-meme est prouve par la suite `e2e/` (Playwright) ; ici on garde, cote PHP, ce que le HTML et les sources portent.
 */
class DefautsNavigateurTest extends TestCase
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

    private function connecte(string $role): void
    {
        $u = User::factory()->create(['username' => $role, 'name' => ucfirst($role)]);
        $u->assignRole($role);
        $this->actingAs($u);
    }

    public function test_le_menu_se_replie_sur_telephone_et_reste_visible_des_md(): void
    {
        $this->connecte('admin');

        $html = $this->get('/dashboard')->assertOk()->getContent();

        // Maquette dashboard.html : la barre laterale est un tiroir (hors ecran sous `lg`), ouvert par un bouton reserve
        // au telephone, relie a la barre par aria-controls ; elle est toujours visible des `lg`.
        $this->assertMatchesRegularExpression('/<button[^>]*data-menu-bascule[^>]*aria-controls="sidebar"[^>]*aria-expanded="false"[^>]*lg:hidden/s', $html);
        $this->assertStringContainsString('<aside id="sidebar" aria-label="Navigation"', $html);
        $this->assertStringContainsString('-translate-x-full lg:translate-x-0', $html);
        $this->assertStringContainsString('<nav id="menu-principal"', $html);
    }

    public function test_le_deces_est_decrit_comme_se_declarant_au_web(): void
    {
        $this->connecte('animalier');

        $html = $this->get('/elevage/soins')->assertOk()->getContent();

        $this->assertStringNotContainsString('ce que le web ne fait pas', $html);
    }

    public function test_les_onglets_des_parametres_passent_a_la_ligne_au_lieu_d_etre_coupes(): void
    {
        $this->connecte('admin');

        $html = $this->get('/parametres/generaux')->assertOk()->getContent();

        $this->assertMatchesRegularExpression('/role="tablist"[^>]*aria-label="Sections des param/', $html);
        $this->assertMatchesRegularExpression('/<div class="[^"]*flex-wrap[^"]*" role="tablist" aria-label="Sections des param/', $html);
    }

    public function test_les_sources_portent_les_garde_fous_du_navigateur(): void
    {
        $js = file_get_contents(resource_path('js/app.js'));
        $css = file_get_contents(resource_path('css/app.css'));

        // Saisie `debounce` puis clic immediat : la valeur est poussee a la perte du focus et a la validation.
        $this->assertStringContainsString("document.addEventListener('focusout'", $js);
        $this->assertStringContainsString("document.addEventListener('submit'", $js);
        $this->assertStringContainsString('.set(attribut.value, champ.value, false)', $js);
        // Session expiree (419) et reseau perdu (503 sans contenu) : messages en francais.
        $this->assertStringContainsString('status === 419', $js);
        $this->assertStringContainsString('Connexion au serveur perdue', $js);
        // Modales : focus, Tab piege, Echap.
        $this->assertStringContainsString("e.key === 'Escape'", $js);
        // Fleche des listes deroulantes : place reservee malgre les `px-*` des ecrans.
        $this->assertMatchesRegularExpression('/select:not\(\[multiple\]\)\s*\{\s*padding-right:/', $css);
    }
}
