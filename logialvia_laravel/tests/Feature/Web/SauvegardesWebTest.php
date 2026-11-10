<?php

namespace Tests\Feature\Web;

use App\Livewire\ParametresGeneraux;
use App\Livewire\SauvegardesWeb;
use App\Models\AuditLog;
use App\Models\Client;
use App\Models\User;
use App\Services\PostesService;
use App\Services\SauvegardeLogiqueService;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/** Sauvegarde logique des donnees du serveur : administrateur seul, sans aucun secret, auditee (doc 47u §5). */
class SauvegardesWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
    }

    private function compte(string $role, string $username): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    private function lecteur(): User
    {
        $u = $this->compte('comptable', 'lecteur');
        $u->givePermissionTo('view-parametres');

        return $u;
    }

    /** @return array<string, mixed> Le JSON telecharge. */
    private function contenu($reponse): array
    {
        $this->assertSame('application/json; charset=utf-8', $reponse->headers->get('Content-Type'));
        ob_start();
        $reponse->sendContent();
        $texte = (string) ob_get_clean();
        $json = json_decode($texte, true);
        $this->assertIsArray($json, 'le fichier est du JSON valide');

        return $json;
    }

    public function test_l_onglet_sauvegardes_propose_le_telechargement_a_l_administrateur(): void
    {
        $admin = $this->compte('admin', 'gerante');
        Livewire::actingAs($admin)->test(ParametresGeneraux::class)->call('choisirOnglet', 5)
            ->assertSeeHtml('data-onglet="sauvegardes"')->assertSeeHtml('data-action="telecharger-sauvegarde"')
            ->assertSee('sauvegarde logique')->assertSeeHtml('data-ecart="sauvegardes"')->assertSee('ne sait pas le restaurer')
            ->assertDontSeeHtml('data-ecart="au-poste"');
    }

    public function test_un_lecteur_voit_l_onglet_sans_bouton(): void
    {
        Livewire::actingAs($this->lecteur())->test(ParametresGeneraux::class)->call('choisirOnglet', 5)
            ->assertDontSeeHtml('data-action="telecharger-sauvegarde"')->assertSee('réservé à l\'administrateur', false);
    }

    public function test_le_telechargement_reprend_les_donnees_sans_aucun_secret(): void
    {
        $admin = $this->compte('admin', 'gerante');
        $admin->forceFill(['password' => 'Secret-Tres-Long-1', 'remember_token' => 'JETONREMEMBER'])->save();
        $secretHash = $admin->fresh()->password;
        $poste = (string) Str::uuid();
        app(PostesService::class)->appairer($admin, $poste);
        (new Client)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => $poste, 'nom' => 'Amina Bako', 'solde_creance' => 0,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ])->save();
        AuditLog::query()->create(['action' => 'web.login', 'identifiant' => 'gerante', 'detail' => ['x' => 1]]);

        $c = Livewire::actingAs($admin)->test(SauvegardesWeb::class)->call('telecharger');
        $c->assertFileDownloaded();
        $reponse = app(SauvegardeLogiqueService::class)->telecharger($admin);
        $this->assertMatchesRegularExpression('/logialvia-sauvegarde-logique-\d{8}-\d{6}\.json/', $reponse->headers->get('Content-Disposition'));
        $json = $this->contenu($reponse);

        $this->assertSame('sauvegarde_logique', $json['type']);
        $this->assertSame('Amina Bako', $json['tables']['clients'][0]['nom']);
        $this->assertSame('gerante', $json['tables']['users'][0]['username']);
        $this->assertSame(1, $json['lignes_par_table']['clients']);
        $this->assertArrayHasKey('audit_logs', $json['tables']);

        $texte = json_encode($json);
        foreach ([$secretHash, 'JETONREMEMBER', 'Secret-Tres-Long-1'] as $secret) {
            $this->assertStringNotContainsString($secret, $texte);
        }
        foreach (['migrations', 'personal_access_tokens', 'sessions', 'password_reset_tokens', 'cache', 'jobs'] as $exclue) {
            $this->assertArrayNotHasKey($exclue, $json['tables'], "$exclue ne se sauvegarde jamais");
        }
        $this->assertArrayNotHasKey('password', $json['tables']['users'][0]);
        $this->assertArrayNotHasKey('remember_token', $json['tables']['users'][0]);
    }

    public function test_le_telechargement_est_inscrit_au_journal_d_audit(): void
    {
        $admin = $this->compte('admin', 'gerante');
        Livewire::actingAs($admin)->test(SauvegardesWeb::class)->call('telecharger');

        $audit = AuditLog::query()->where('action', 'sauvegarde.telechargee')->firstOrFail();
        $this->assertSame($admin->id, $audit->utilisateur_id);
        $this->assertGreaterThan(5, $audit->detail['tables']);
    }

    public function test_seul_l_administrateur_telecharge(): void
    {
        $admin = $this->compte('admin', 'gerante');
        // Un compte qui a manage-parametres sans etre administrateur n'a pas la sauvegarde.
        $gerant = $this->compte('comptable', 'gerant');
        $gerant->givePermissionTo('view-parametres', 'manage-parametres');

        foreach ([$this->compte('caissier', 'caisse'), $this->lecteur(), $gerant] as $intrus) {
            $c = Livewire::actingAs($admin)->test(SauvegardesWeb::class);
            $this->actingAs($intrus);
            $c->call('telecharger')->assertForbidden();
        }
        $this->assertSame(0, AuditLog::query()->where('action', 'sauvegarde.telechargee')->count());

        // Le service refuse aussi sans passer par le composant.
        $this->expectException(\Symfony\Component\HttpKernel\Exception\HttpException::class);
        app(SauvegardeLogiqueService::class)->telecharger($gerant);
    }

    public function test_le_composant_n_est_pas_ouvert_sans_voir_les_parametres(): void
    {
        Livewire::actingAs($this->compte('caissier', 'caisse'))->test(SauvegardesWeb::class)->assertForbidden();
    }
}
