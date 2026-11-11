<?php

namespace Tests\Feature\Web;

use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/** Vues imprimables (doc 47u §6) : bouton « Imprimer / PDF » + feuille de style @media print. */
class VuesImprimablesTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
    }

    private function admin(): User
    {
        $u = User::factory()->create(['username' => 'gerante']);
        $u->assignRole('admin');

        return $u;
    }

    public function test_la_feuille_de_style_masque_le_menu_la_barre_et_les_boutons_a_l_impression(): void
    {
        $css = (string) file_get_contents(resource_path('css/app.css'));

        $this->assertStringContainsString('@media print', $css);
        $bloc = substr($css, strpos($css, '@media print'));
        foreach (['.no-print', "aside[aria-label='Navigation']", 'display: none !important', 'break-inside: avoid', 'display: table-header-group', '@page'] as $regle) {
            $this->assertStringContainsString($regle, $bloc);
        }
    }

    public function test_le_menu_et_la_barre_du_haut_ont_la_structure_que_la_feuille_cible(): void
    {
        $page = $this->actingAs($this->admin())->get('/parametres/audit')->assertOk();

        $page->assertSee('<aside id="sidebar" aria-label="Navigation"', false)->assertSee('aria-label="Navigation"', false);
        $this->assertMatchesRegularExpression('#<body[^>]*>\s*<div[^>]*>.*?<div class="flex min-w-0 flex-1 flex-col">\s*<header#s', $page->getContent());
    }

    public function test_le_bouton_imprimer_est_sur_chaque_ecran_d_administration_a_tableau(): void
    {
        $admin = $this->admin();

        foreach (['/parametres/audit'] as $chemin) {
            $this->actingAs($admin)->get($chemin)->assertOk()->assertSee('data-action="imprimer"', false)->assertSee('Imprimer / PDF')
                ->assertSee('onclick="window.print()"', false);
        }
        \Livewire\Livewire::actingAs($admin)->test(\App\Livewire\CorbeilleWeb::class)->assertSeeHtml('data-action="imprimer"');
        \Livewire\Livewire::actingAs($admin)->test(\App\Livewire\GestionUtilisateurs::class)->assertSeeHtml('data-action="imprimer"');
    }

    public function test_les_commandes_ne_s_impriment_pas(): void
    {
        $admin = $this->admin();
        $html = \Livewire\Livewire::actingAs($admin)->test(\App\Livewire\JournalAudit::class)->html();

        // Filtres, pagination et boutons d'action portent `no-print`.
        $this->assertGreaterThanOrEqual(3, substr_count($html, 'no-print'));
        $this->assertMatchesRegularExpression('/no-print[^>]*>\s*<button[^>]*data-action="exporter"|data-action="exporter"[^>]*>/', $html);
    }
}
