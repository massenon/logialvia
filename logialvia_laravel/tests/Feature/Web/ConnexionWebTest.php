<?php

namespace Tests\Feature\Web;

use App\Livewire\Auth\ChangerMotDePasse;
use App\Livewire\Auth\Connexion;
use App\Models\AuditLog;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Livewire\Livewire;
use Tests\TestCase;

/** Connexion web : memes regles et memes messages que l'appairage d'un poste. */
class ConnexionWebTest extends TestCase
{
    use RefreshDatabase;

    private const MOT_DE_PASSE = 'motdepasse-solide-1';

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        RateLimiter::clear('');
    }

    private function compte(array $attributs = []): User
    {
        $utilisateur = User::factory()->create(array_merge([
            'username' => 'marie',
            'password' => self::MOT_DE_PASSE,
        ], $attributs));
        $utilisateur->assignRole('caissier');

        return $utilisateur;
    }

    public function test_la_page_de_connexion_s_affiche(): void
    {
        $this->get('/login')->assertOk()->assertSee('Se connecter');
    }

    public function test_une_connexion_reussie_ouvre_la_session(): void
    {
        $utilisateur = $this->compte();

        Livewire::test(Connexion::class)
            ->set('identifiant', 'marie')
            ->set('password', self::MOT_DE_PASSE)
            ->call('connecter')
            ->assertRedirect('/');

        $this->assertAuthenticatedAs($utilisateur);
        $this->assertNotNull($utilisateur->fresh()->last_login_at);
        $this->assertSame(1, AuditLog::query()->where('action', 'web.login')->count());
    }

    public function test_un_mauvais_mot_de_passe_affiche_le_meme_message_que_l_api(): void
    {
        $this->compte();

        Livewire::test(Connexion::class)
            ->set('identifiant', 'marie')
            ->set('password', 'faux')
            ->call('connecter')
            ->assertSet('erreur', 'Identifiant ou mot de passe incorrect.')
            ->assertSet('password', '');

        $this->assertGuest();
    }

    public function test_un_compte_desactive_est_refuse_avec_son_motif(): void
    {
        $this->compte(['is_active' => false]);

        Livewire::test(Connexion::class)
            ->set('identifiant', 'marie')
            ->set('password', self::MOT_DE_PASSE)
            ->call('connecter')
            ->assertSet('erreur', "Ce compte a été désactivé. Contactez l'administrateur.");

        $this->assertGuest();
    }

    public function test_les_champs_vides_sont_signales_en_francais(): void
    {
        Livewire::test(Connexion::class)
            ->call('connecter')
            ->assertSee("L'identifiant est obligatoire.")
            ->assertSee('Le mot de passe est obligatoire.');
    }

    public function test_la_connexion_web_est_limitee_a_cinq_par_minute(): void
    {
        $this->compte();
        $page = Livewire::test(Connexion::class)->set('identifiant', 'marie');

        for ($i = 0; $i < 5; $i++) {
            $page->set('password', 'faux-'.$i)->call('connecter');
        }

        $page->set('password', self::MOT_DE_PASSE)->call('connecter');

        $this->assertStringContainsString('Trop de tentatives', $page->get('erreur'));
        // Meme avec le BON mot de passe : la limite protege la devinette.
        $this->assertGuest();
    }

    public function test_un_connecte_n_est_plus_renvoye_vers_la_connexion(): void
    {
        $this->actingAs($this->compte())->get('/login')->assertRedirect();
    }

    public function test_la_deconnexion_ferme_la_session(): void
    {
        $this->actingAs($this->compte())->post('/deconnexion')->assertRedirect(route('login'));

        $this->assertGuest();
    }

    // ---------------------------------------------------- Mot de passe temporaire

    public function test_un_mot_de_passe_temporaire_ne_laisse_ouvert_que_son_changement(): void
    {
        $utilisateur = $this->compte(['must_change_password' => true]);
        $this->actingAs($utilisateur);

        $this->get('/')->assertRedirect(route('mot-de-passe'));
        $this->get('/parametres/postes')->assertRedirect(route('mot-de-passe'));
        $this->get('/mot-de-passe')->assertOk();
    }

    public function test_le_changement_leve_l_obligation_et_coupe_les_jetons(): void
    {
        $utilisateur = $this->compte(['must_change_password' => true]);
        $utilisateur->createToken('un-poste');

        Livewire::actingAs($utilisateur)->test(ChangerMotDePasse::class)
            ->set('actuel', self::MOT_DE_PASSE)
            ->set('nouveau', 'Nouveau-mot-de-passe-2')
            ->set('confirmation', 'Nouveau-mot-de-passe-2')
            ->call('enregistrer')
            ->assertRedirect('/');

        $utilisateur->refresh();
        $this->assertFalse($utilisateur->must_change_password);
        $this->assertTrue(Hash::check('Nouveau-mot-de-passe-2', $utilisateur->password));
        $this->assertSame(0, $utilisateur->tokens()->count(), 'Les postes doivent se reconnecter.');
    }

    public function test_le_changement_refuse_un_mot_de_passe_court_ou_une_confirmation_differente(): void
    {
        $utilisateur = $this->compte(['must_change_password' => true]);

        $page = Livewire::actingAs($utilisateur)->test(ChangerMotDePasse::class)
            ->set('actuel', self::MOT_DE_PASSE)
            ->set('nouveau', 'court')
            ->set('confirmation', 'court')
            ->call('enregistrer')
            ->assertSet('erreur', 'Le mot de passe doit compter au moins 8 caractères.');

        $page->set('nouveau', 'Nouveau-mot-de-passe-2')
            ->set('confirmation', 'autre-chose-vraiment')
            ->call('enregistrer')
            ->assertSet('erreur', 'La confirmation ne correspond pas.');

        $page->set('actuel', 'mauvais')->call('enregistrer')
            ->assertSet('erreur', 'Le mot de passe actuel est incorrect.');

        $this->assertTrue($utilisateur->fresh()->must_change_password);
    }
}
