<?php

namespace Tests\Feature\Web;

use App\Livewire\PostesAppairage;
use App\Models\AuditLog;
use App\Models\Poste;
use App\Models\User;
use App\Services\PostesService;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Laravel\Sanctum\PersonalAccessToken;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Postes & Appairage » : liste, etat, revocation par modale, droits. */
class PostesAppairageTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
    }

    private function utilisateur(string $role, string $username = 'u'): User
    {
        $utilisateur = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $utilisateur->assignRole($role);

        return $utilisateur;
    }

    private function appairer(User $utilisateur, ?string $poste = null): Poste
    {
        return app(PostesService::class)->appairer($utilisateur, $poste ?? (string) Str::uuid())['poste'];
    }

    // ------------------------------------------------------------------- Acces

    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/parametres/postes')->assertRedirect(route('login'));
    }

    public function test_un_caissier_n_ouvre_pas_la_page(): void
    {
        $this->actingAs($this->utilisateur('caissier'))->get('/parametres/postes')->assertForbidden();
    }

    public function test_un_animalier_et_un_comptable_non_plus(): void
    {
        $this->actingAs($this->utilisateur('animalier', 'a'))->get('/parametres/postes')->assertForbidden();
        $this->actingAs($this->utilisateur('comptable', 'c'))->get('/parametres/postes')->assertForbidden();
    }

    public function test_un_administrateur_ouvre_la_page(): void
    {
        $this->actingAs($this->utilisateur('admin'))->get('/parametres/postes')
            ->assertOk()
            ->assertSee('Postes &amp; Appairage', false);
    }

    // ------------------------------------------------------------------ Liste

    public function test_la_page_liste_les_postes_avec_leur_code_et_leur_etat(): void
    {
        $admin = $this->utilisateur('admin', 'admin');
        $marie = $this->utilisateur('caissier', 'marie');
        $vivant = $this->appairer($marie);
        $revoque = $this->appairer($marie);
        app(PostesService::class)->revoquer($revoque->device_id, $admin);

        Livewire::actingAs($admin)->test(PostesAppairage::class)
            ->assertSee($vivant->code)
            ->assertSee($revoque->code)
            ->assertSee('Appairé')
            ->assertSee('Révoqué')
            ->assertSee('Marie');
    }

    public function test_la_colonne_droits_donne_le_compte_le_role_et_ce_que_le_poste_peut_envoyer(): void
    {
        $admin = $this->utilisateur('admin', 'admin');
        $caisse = $this->appairer($this->utilisateur('caissier', 'marie'));
        $gerante = $this->appairer($this->utilisateur('admin', 'gerante'));

        $composant = Livewire::actingAs($admin)->test(PostesAppairage::class)
            ->assertSee('Droits')
            ->assertSeeHtml('data-droits="'.$caisse->code.'"')
            ->assertSeeHtml('data-droits="'.$gerante->code.'"')
            ->assertSee('marie')
            ->assertSee('Agent de Vente')
            ->assertSee('gerante')
            ->assertSee('Administrateur');

        // Le caissier ne propose qu'un type de reglage (le catalogue) ; l'administrateur tous.
        $composant->assertSee('propose 1 type(s) de réglages')->assertSee('propose 8 type(s) de réglages');
    }

    public function test_un_compte_sans_droit_d_ecriture_est_dit_en_lecture_seule(): void
    {
        $sans = User::factory()->create(['username' => 'vide', 'name' => 'Vide']);
        $poste = $this->appairer($sans);

        Livewire::actingAs($this->utilisateur('admin', 'admin'))->test(PostesAppairage::class)
            ->assertSeeHtml('data-droits="'.$poste->code.'"')
            ->assertSee('Lecture seule : rien à envoyer au serveur')
            ->assertSee('Aucun rôle');
    }

    public function test_sans_poste_la_page_l_explique(): void
    {
        Livewire::actingAs($this->utilisateur('admin'))->test(PostesAppairage::class)
            ->assertSee('Aucun poste appairé');
    }

    public function test_les_codes_se_trient_p2_avant_p10(): void
    {
        $admin = $this->utilisateur('admin', 'admin');
        for ($i = 0; $i < 10; $i++) {
            $this->appairer($admin);
        }

        $html = Livewire::actingAs($admin)->test(PostesAppairage::class)->html();

        $this->assertLessThan(strpos($html, 'data-poste="P10"'), strpos($html, 'data-poste="P2"'));
    }

    public function test_l_etat_sans_jeton_apparait_quand_le_jeton_a_expire(): void
    {
        $admin = $this->utilisateur('admin', 'admin');
        $poste = $this->appairer($admin);
        PersonalAccessToken::query()->where('name', $poste->device_id)->update(['expires_at' => now()->subDay()]);

        $this->assertSame('sans_jeton', $poste->fresh()->etat());
        Livewire::actingAs($admin)->test(PostesAppairage::class)->assertSee('Sans jeton');
    }

    public function test_les_dates_s_affichent_en_francais_et_a_l_heure_du_benin(): void
    {
        $admin = $this->utilisateur('admin', 'admin');
        $poste = $this->appairer($admin);
        // 23 h 30 UTC = 00 h 30 le lendemain a Natitingou (UTC+1).
        $poste->forceFill([
            'appaire_le' => '2026-11-09 23:30:00',
            'dernier_contact_le' => now()->subMinutes(5),
        ])->save();

        $html = Livewire::actingAs($admin)->test(PostesAppairage::class)->html();

        $this->assertStringContainsString('10/11/2026 00:30', $html);
        $this->assertStringContainsString('il y a', $html);
        $this->assertStringNotContainsString(' ago', $html);
    }

    public function test_chaque_poste_a_aussi_sa_carte_pour_le_mobile(): void
    {
        // Sous 640 px le tableau est masque : l'etat et le bouton de revocation
        // doivent exister dans des cartes, sinon ils se cachent derriere un defilement.
        $admin = $this->utilisateur('admin', 'admin');
        $poste = $this->appairer($admin);

        $html = Livewire::actingAs($admin)->test(PostesAppairage::class)->html();

        $this->assertStringContainsString('data-carte-poste="'.$poste->code.'"', $html);
        $this->assertStringContainsString('class="flex flex-col gap-sm sm:hidden"', $html);
        $this->assertStringContainsString('hidden overflow-x-auto', $html);
        $this->assertSame(
            2,
            substr_count($html, "demanderRevocation('{$poste->device_id}')"),
            'Un bouton dans le tableau, un dans la carte.',
        );
    }

    // ------------------------------------------------------------- Revocation

    public function test_demander_la_revocation_ouvre_la_modale_sans_rien_revoquer(): void
    {
        $admin = $this->utilisateur('admin', 'admin');
        $poste = $this->appairer($admin);

        Livewire::actingAs($admin)->test(PostesAppairage::class)
            ->call('demanderRevocation', $poste->device_id)
            ->assertSet('posteAConfirmer', $poste->device_id)
            ->assertSee("Révoquer l'appairage ?", false);

        $this->assertNull($poste->fresh()->revoque_le);
        $this->assertSame(1, $poste->jetonsActifs()->count());
    }

    public function test_annuler_ferme_la_modale_et_ne_revoque_rien(): void
    {
        $admin = $this->utilisateur('admin', 'admin');
        $poste = $this->appairer($admin);

        Livewire::actingAs($admin)->test(PostesAppairage::class)
            ->call('demanderRevocation', $poste->device_id)
            ->call('annuler')
            ->assertSet('posteAConfirmer', null)
            ->assertDontSee("Révoquer l'appairage ?", false);

        $this->assertNull($poste->fresh()->revoque_le);
    }

    public function test_confirmer_revoque_le_poste_en_base_et_journalise(): void
    {
        $admin = $this->utilisateur('admin', 'admin');
        $poste = $this->appairer($this->utilisateur('caissier', 'marie'));

        Livewire::actingAs($admin)->test(PostesAppairage::class)
            ->call('demanderRevocation', $poste->device_id)
            ->call('confirmerRevocation')
            ->assertSet('posteAConfirmer', null)
            ->assertSee("Appairage révoqué pour le poste {$poste->code}");

        // Relecture en base, le seul critere qui compte.
        $this->assertNotNull($poste->fresh()->revoque_le);
        $this->assertSame('revoque', $poste->fresh()->etat());
        $this->assertSame(0, PersonalAccessToken::query()->where('name', $poste->device_id)->count());
        $trace = AuditLog::query()->where('action', 'sync.appairage_revoque')->sole();
        $this->assertSame($admin->id, $trace->utilisateur_id);
    }

    public function test_un_poste_revoque_n_a_plus_de_bouton_de_revocation(): void
    {
        $admin = $this->utilisateur('admin', 'admin');
        $poste = $this->appairer($admin);
        app(PostesService::class)->revoquer($poste->device_id, $admin);

        Livewire::actingAs($admin)->test(PostesAppairage::class)
            ->assertDontSee("wire:click=\"demanderRevocation('{$poste->device_id}')\"", false);
    }

    // ---------------------------------------- Le droit est reverifie dans les methodes

    public function test_un_caissier_ne_peut_pas_appeler_les_methodes_directement(): void
    {
        $caissier = $this->utilisateur('caissier', 'marie');
        $poste = $this->appairer($caissier);

        Livewire::actingAs($caissier)->test(PostesAppairage::class)->assertForbidden();

        $this->assertNull($poste->fresh()->revoque_le);
        $this->assertSame(1, $poste->jetonsActifs()->count());
    }

    public function test_perdre_le_droit_en_cours_de_session_bloque_la_revocation(): void
    {
        $admin = $this->utilisateur('admin', 'admin');
        $poste = $this->appairer($admin);

        $composant = Livewire::actingAs($admin)->test(PostesAppairage::class)
            ->call('demanderRevocation', $poste->device_id);

        // L'administrateur perd son role pendant que la modale est ouverte.
        $admin->syncRoles(['caissier']);
        app(\Spatie\Permission\PermissionRegistrar::class)->forgetCachedPermissions();

        $composant->call('confirmerRevocation')->assertForbidden();
        $this->assertNull($poste->fresh()->revoque_le);
    }

    public function test_revoquer_un_identifiant_inconnu_n_ouvre_pas_la_modale(): void
    {
        Livewire::actingAs($this->utilisateur('admin'))->test(PostesAppairage::class)
            ->call('demanderRevocation', (string) Str::uuid())
            ->assertSet('posteAConfirmer', null);
    }
}
