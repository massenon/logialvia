<?php

namespace Tests\Feature\Web;

use App\Livewire\JournalAudit;
use App\Models\AuditLog;
use App\Models\User;
use App\Support\LibellesAudit;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/** Journal d'audit web : lecture seule, droit manage-users, filtres date / action / utilisateur, pagination (doc 47u §2). */
class JournalAuditWebTest extends TestCase
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

    private function admin(): User
    {
        return $this->compte('admin', 'gerante');
    }

    private function entree(string $action, ?User $u, string $quand, array $detail = [], ?string $ip = '10.0.0.1'): AuditLog
    {
        $l = AuditLog::query()->create([
            'action' => $action, 'utilisateur_id' => $u?->id, 'identifiant' => $u?->username, 'detail' => $detail ?: null, 'ip' => $ip,
        ]);
        $l->forceFill(['created_at' => $quand])->save();

        return $l;
    }

    // ------------------------------------------------------------------- Acces

    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/parametres/audit')->assertRedirect(route('login'));
    }

    public function test_seul_manage_users_ouvre_le_journal(): void
    {
        foreach (['caissier', 'animalier', 'comptable'] as $i => $role) {
            $this->actingAs($this->compte($role, "u$i"))->get('/parametres/audit')->assertForbidden();
        }
        $lecteur = $this->compte('comptable', 'lecteur');
        $lecteur->givePermissionTo('view-parametres');
        $this->actingAs($lecteur)->get('/parametres/audit')->assertForbidden();

        $this->actingAs($this->admin())->get('/parametres/audit')->assertOk()->assertSee('Journal d\'Audit', false)->assertDontSee('arrive bientôt');
    }

    public function test_les_liens_du_menu_et_des_parametres_menent_au_journal(): void
    {
        $admin = $this->admin();
        $this->actingAs($admin)->get('/parametres/generaux')->assertSee(route('audit'), false);
        $this->actingAs($admin)->get('/dashboard')->assertSee('href="'.route('audit').'"', false);
        $this->actingAs($this->compte('comptable', 'compta'))->get('/dashboard')->assertDontSee(route('audit'), false);
    }

    // ----------------------------------------------------------------- Contenu

    public function test_le_journal_liste_du_plus_recent_au_plus_ancien_avec_libelles_francais(): void
    {
        $admin = $this->admin();
        $this->entree('web.login', $admin, '2026-11-01 08:00:00');
        $this->entree('utilisateur.cree', $admin, '2026-11-02 08:00:00', ['cible' => 'amina', 'role' => 'caissier']);
        $this->entree('login.failed', null, '2026-11-03 08:00:00', [], '203.0.113.9');

        Livewire::actingAs($admin)->test(JournalAudit::class)
            ->assertSeeInOrder(['Connexion refusée (identifiants)', 'Compte créé', 'Connexion web'])
            ->assertSee('cible : amina')->assertSee('role : caissier')->assertSee('203.0.113.9')
            ->assertSee('3 entrée(s)');
    }

    public function test_les_heures_s_affichent_au_fuseau_du_benin(): void
    {
        $admin = $this->admin();
        $this->entree('web.login', $admin, '2026-11-01 23:30:00'); // UTC -> 00h30 le 2 a Natitingou (UTC+1)

        Livewire::actingAs($admin)->test(JournalAudit::class)->assertSee('02/11/2026 00:30:00');
    }

    public function test_un_secret_n_est_jamais_affiche_meme_s_il_est_dans_le_detail(): void
    {
        $admin = $this->admin();
        $this->entree('sync.push', $admin, '2026-11-01 08:00:00', [
            'poste' => 'P2', 'jeton' => 'abc123SECRET', 'mot_de_passe_temp' => 'Hunter2Hunter', 'jetons_supprimes' => 3,
            'Authorization' => 'Bearer zzz',
        ]);

        $html = Livewire::actingAs($admin)->test(JournalAudit::class)->assertSee('poste : P2')->assertSee('jetons_supprimes : 3')->html();
        foreach (['abc123SECRET', 'Hunter2Hunter', 'Bearer zzz'] as $secret) {
            $this->assertStringNotContainsString($secret, $html);
        }
        $this->assertSame(['jeton : ••••'], LibellesAudit::detail(['jeton' => 'x']));
    }

    public function test_une_action_inconnue_s_affiche_telle_quelle(): void
    {
        $this->assertSame('futur.action', LibellesAudit::action('futur.action'));
        $admin = $this->admin();
        $this->entree('futur.action', $admin, '2026-11-01 08:00:00');
        Livewire::actingAs($admin)->test(JournalAudit::class)->assertSee('futur.action');
    }

    public function test_journal_vide(): void
    {
        Livewire::actingAs($this->admin())->test(JournalAudit::class)->assertSee('Aucune entrée ne correspond à ces filtres.')->assertSee('0 entrée(s)');
    }

    // ------------------------------------------------------------------ Filtres

    public function test_filtre_par_action(): void
    {
        $admin = $this->admin();
        $this->entree('web.login', $admin, '2026-11-01 08:00:00');
        $this->entree('utilisateur.cree', $admin, '2026-11-02 08:00:00');

        Livewire::actingAs($admin)->test(JournalAudit::class)->set('action', 'utilisateur.cree')
            ->assertSeeHtml('data-ligne-audit="utilisateur.cree"')->assertDontSeeHtml('data-ligne-audit="web.login"')->assertSee('1 entrée(s)');
    }

    public function test_filtre_par_utilisateur(): void
    {
        $admin = $this->admin();
        $autre = $this->compte('caissier', 'amina');
        $this->entree('web.login', $admin, '2026-11-01 08:00:00');
        $this->entree('web.mot_de_passe_change', $autre, '2026-11-02 08:00:00');

        Livewire::actingAs($admin)->test(JournalAudit::class)->set('utilisateur', $autre->id)
            ->assertSeeHtml('data-ligne-audit="web.mot_de_passe_change"')->assertDontSeeHtml('data-ligne-audit="web.login"');
    }

    public function test_filtre_par_dates_fin_incluse_au_fuseau_du_benin(): void
    {
        $admin = $this->admin();
        $this->entree('a.avant', $admin, '2026-10-31 22:59:59');  // 31/10 23h59 Benin : avant
        $this->entree('b.debut', $admin, '2026-10-31 23:00:00');  // 01/11 00h00 Benin : dedans
        $this->entree('c.fin', $admin, '2026-11-02 22:59:59');    // 02/11 23h59 Benin : dedans (fin incluse)
        $this->entree('d.apres', $admin, '2026-11-02 23:00:00');  // 03/11 00h00 Benin : apres

        Livewire::actingAs($admin)->test(JournalAudit::class)->set('dateDebut', '2026-11-01')->set('dateFin', '2026-11-02')
            ->assertSeeHtml('data-ligne-audit="b.debut"')->assertSeeHtml('data-ligne-audit="c.fin"')
            ->assertDontSeeHtml('data-ligne-audit="a.avant"')->assertDontSeeHtml('data-ligne-audit="d.apres"')->assertSee('2 entrée(s)');
    }

    public function test_dates_invalides_ou_inversees_sont_signalees(): void
    {
        $c = Livewire::actingAs($this->admin())->test(JournalAudit::class);
        $c->set('dateDebut', '2026-13-45')->assertSet('erreur', 'La date de début est invalide.');
        $c->set('dateDebut', '')->set('dateFin', 'demain')->assertSet('erreur', 'La date de fin est invalide.');
        $c->set('dateDebut', '2026-11-05')->set('dateFin', '2026-11-01')->assertSet('erreur', 'La date de début ne peut pas dépasser la date de fin.');
        $c->call('reinitialiser')->assertSet('erreur', null)->assertSet('dateDebut', '');
    }

    public function test_reinitialiser_les_filtres(): void
    {
        $admin = $this->admin();
        $this->entree('web.login', $admin, '2026-11-01 08:00:00');
        Livewire::actingAs($admin)->test(JournalAudit::class)->set('action', 'inconnue')->assertSee('0 entrée(s)')
            ->call('reinitialiser')->assertSet('action', '')->assertSee('1 entrée(s)');
    }

    // --------------------------------------------------------------- Pagination

    public function test_pagination_par_25_avec_navigation_bornee(): void
    {
        $admin = $this->admin();
        for ($i = 1; $i <= 60; $i++) {
            $this->entree('sync.push', $admin, now()->subMinutes(200 - $i)->format('Y-m-d H:i:s'), ['n' => $i]);
        }

        $c = Livewire::actingAs($admin)->test(JournalAudit::class)->assertSee('60 entrée(s) — page 1 / 3')
            ->assertSee('n : 60')->assertDontSee('n : 35')->assertSeeHtml('disabled');
        $c->call('suivante')->assertSet('page', 2)->assertSee('n : 35')->assertDontSee('n : 60');
        $c->call('suivante')->call('suivante')->call('suivante')->assertSet('page', 3)->assertSee('n : 10')->assertDontSee('n : 11')->assertSee('page 3 / 3');
        $c->call('precedente')->call('precedente')->call('precedente')->assertSet('page', 1);
        $this->assertCount(25, $c->viewData('lignes'));
    }

    public function test_changer_de_filtre_revient_a_la_premiere_page(): void
    {
        $admin = $this->admin();
        for ($i = 1; $i <= 30; $i++) {
            $this->entree('sync.push', $admin, now()->subMinutes(100 - $i)->format('Y-m-d H:i:s'));
        }
        Livewire::actingAs($admin)->test(JournalAudit::class)->call('suivante')->assertSet('page', 2)
            ->set('action', 'sync.push')->assertSet('page', 1);
    }

    // -------------------------------------------------------------------- Droits

    public function test_chaque_methode_publique_reverifie_le_droit_et_rien_n_ecrit(): void
    {
        $admin = $this->admin();
        $intrus = $this->compte('comptable', 'intrus');
        $this->entree('web.login', $admin, '2026-11-01 08:00:00');

        foreach (['reinitialiser', 'precedente', 'suivante'] as $methode) {
            $c = Livewire::actingAs($admin)->test(JournalAudit::class);
            $this->actingAs($intrus);
            $c->call($methode)->assertForbidden();
        }
        $this->assertSame(1, AuditLog::query()->count(), 'lecture seule : aucune ecriture');

        $propres = collect((new \ReflectionClass(JournalAudit::class))->getMethods(\ReflectionMethod::IS_PUBLIC))
            ->filter(fn (\ReflectionMethod $m) => $m->class === JournalAudit::class)->map->name->sort()->values()->all();
        $this->assertSame(['mount', 'precedente', 'reinitialiser', 'render', 'suivante', 'updated'], $propres);
    }

    public function test_aucun_bouton_de_modification_et_impression_proposee(): void
    {
        $admin = $this->admin();
        $this->entree('web.login', $admin, '2026-11-01 08:00:00');
        Livewire::actingAs($admin)->test(JournalAudit::class)->assertDontSee('Supprimer')->assertDontSee('Effacer')
            ->assertSeeHtml('data-action="imprimer"')->assertSee('Imprimer / PDF');
    }
}
