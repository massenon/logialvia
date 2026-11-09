<?php

namespace Tests\Feature\Web;

use App\Livewire\Profil;
use App\Models\AuditLog;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Mon Profil » : identite du compte connecte et changement de mot de passe (regles de ChangerMotDePasse). */
class ProfilWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
    }

    private function utilisateur(string $role, string $username = 'amina', string $nom = 'Amina Koffi'): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => $nom, 'password' => 'Ancien-mot-de-passe-1']);
        $u->assignRole($role);

        return $u;
    }

    // ------------------------------------------------------------------- Acces

    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/profil')->assertRedirect(route('login'));
    }

    public function test_tout_compte_connecte_ouvre_son_profil(): void
    {
        foreach (['admin', 'comptable', 'caissier', 'animalier'] as $i => $role) {
            $this->actingAs($this->utilisateur($role, "u$i", "Nom $i"))->get('/profil')
                ->assertOk()->assertSee('Mon Profil')->assertDontSee('arrive bientôt');
        }
    }

    // ----------------------------------------------------------------- Contenu

    public function test_la_carte_montre_nom_identifiant_role_et_initiales(): void
    {
        Livewire::actingAs($this->utilisateur('caissier'))->test(Profil::class)
            ->assertSeeHtml('data-profil="nom">Amina Koffi<')
            ->assertSeeHtml('data-profil="identifiant">amina<')
            ->assertSeeHtml('data-profil="role">Agent de Vente<')
            ->assertSeeHtml('>AK</div>')
            ->assertSee('Modifier le Mot de Passe');
    }

    public function test_chaque_role_a_son_libelle_du_poste(): void
    {
        foreach (['admin' => 'Administrateur', 'comptable' => 'Comptable', 'caissier' => 'Agent de Vente', 'animalier' => 'Agent d\'Élevage'] as $role => $libelle) {
            Livewire::actingAs($this->utilisateur($role, "u_$role"))->test(Profil::class)
                ->assertSeeHtml('data-profil="role">'.e($libelle).'<');
        }
    }

    public function test_un_compte_sans_role_affiche_un_tiret_et_pas_d_erreur(): void
    {
        $u = User::factory()->create(['username' => 'sansrole', 'name' => 'Sans Role']);

        Livewire::actingAs($u)->test(Profil::class)->assertSeeHtml('data-profil="role">—<')->assertSeeHtml('>SR</div>');
    }

    public function test_on_ne_voit_que_son_propre_profil(): void
    {
        $this->utilisateur('admin', 'autre', 'Autre Personne');

        Livewire::actingAs($this->utilisateur('caissier'))->test(Profil::class)
            ->assertDontSee('Autre Personne')->assertDontSee('autre');
    }

    public function test_aucun_hash_ni_secret_n_est_expose(): void
    {
        $u = $this->utilisateur('caissier');
        $html = Livewire::actingAs($u)->test(Profil::class)->html();

        $this->assertStringNotContainsString($u->password, $html);
        $this->assertStringNotContainsString('Ancien-mot-de-passe-1', $html);
        $this->assertStringNotContainsString((string) $u->remember_token, $html);
    }

    public function test_les_trois_champs_sont_des_champs_mot_de_passe(): void
    {
        $this->actingAs($this->utilisateur('caissier'))->get('/profil')
            ->assertSee('type="password"', false)->assertSee('Ancien mot de passe *')->assertSee('Confirmer le nouveau mot de passe *');
    }

    // ------------------------------------------------------------ Mot de passe

    public function test_un_mauvais_mot_de_passe_actuel_est_refuse(): void
    {
        $u = $this->utilisateur('caissier');

        Livewire::actingAs($u)->test(Profil::class)
            ->set('actuel', 'faux')->set('nouveau', 'Nouveau-mot-de-passe-2')->set('confirmation', 'Nouveau-mot-de-passe-2')
            ->call('enregistrer')
            ->assertSet('erreur', 'Le mot de passe actuel est incorrect.')->assertSee('Le mot de passe actuel est incorrect.');

        $this->assertTrue(Hash::check('Ancien-mot-de-passe-1', $u->fresh()->password));
    }

    public function test_un_nouveau_mot_de_passe_trop_court_est_refuse(): void
    {
        $u = $this->utilisateur('caissier');

        Livewire::actingAs($u)->test(Profil::class)
            ->set('actuel', 'Ancien-mot-de-passe-1')->set('nouveau', 'court')->set('confirmation', 'court')
            ->call('enregistrer')
            ->assertSet('erreur', 'Le nouveau mot de passe doit comporter au moins 10 caractères.');

        $this->assertTrue(Hash::check('Ancien-mot-de-passe-1', $u->fresh()->password));
    }

    public function test_une_confirmation_differente_est_refusee(): void
    {
        $u = $this->utilisateur('caissier');

        Livewire::actingAs($u)->test(Profil::class)
            ->set('actuel', 'Ancien-mot-de-passe-1')->set('nouveau', 'Nouveau-mot-de-passe-2')->set('confirmation', 'Autre-mot-de-passe-33')
            ->call('enregistrer')
            ->assertSet('erreur', 'La confirmation ne correspond pas.');

        $this->assertTrue(Hash::check('Ancien-mot-de-passe-1', $u->fresh()->password));
    }

    public function test_le_changement_reussi_ecrit_le_hash_revoque_les_jetons_et_laisse_une_trace(): void
    {
        $u = $this->utilisateur('caissier');
        $u->createToken('poste-1');

        Livewire::actingAs($u)->test(Profil::class)
            ->set('actuel', 'Ancien-mot-de-passe-1')->set('nouveau', 'Nouveau-mot-de-passe-2')->set('confirmation', 'Nouveau-mot-de-passe-2')
            ->call('enregistrer')
            ->assertSet('erreur', null)->assertRedirect('/');

        $u->refresh();
        $this->assertTrue(Hash::check('Nouveau-mot-de-passe-2', $u->password));
        $this->assertFalse(Hash::check('Ancien-mot-de-passe-1', $u->password));
        $this->assertFalse($u->must_change_password);
        $this->assertSame(0, $u->tokens()->count(), 'les postes de ce compte devront se reconnecter');
        $this->assertTrue(AuditLog::query()->where('action', 'web.mot_de_passe_change')->exists());
    }

    public function test_la_page_profil_est_l_ecran_du_profil_et_pas_la_page_du_mot_de_passe_temporaire(): void
    {
        $this->actingAs($this->utilisateur('caissier'))->get('/profil')->assertDontSee('Votre mot de passe est temporaire');
    }

    public function test_un_compte_a_mot_de_passe_temporaire_n_ouvre_que_le_changement(): void
    {
        $u = $this->utilisateur('caissier');
        $u->forceFill(['must_change_password' => true])->save();

        $this->actingAs($u)->get('/profil')->assertRedirect();
    }
}
