<?php

namespace Tests\Feature\Api;

use App\Models\AuditLog;
use App\Models\Poste;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\TestCase;

/**
 * W2 — appairage d'un poste (`43_` §1) : connexion par poste, un jeton par poste,
 * revocation, le jeton dit qui parle. Chaque test verifie l'ETAT DE LA BASE.
 */
class AppairageTest extends TestCase
{
    use RefreshDatabase;

    private const MOT_DE_PASSE = 'motdepasse-solide-1';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        RateLimiter::clear('');
    }

    /**
     * Requete portant ce jeton. Plusieurs requetes d'un MEME test partagent la garde
     * d'authentification, qui garde l'utilisateur en memoire : on l'oublie avant chaque
     * appel, comme le fait un vrai serveur entre deux requetes.
     */
    private function avecJeton(string $jeton): static
    {
        $this->app['auth']->forgetGuards();

        return $this->withToken($jeton);
    }

    private function compte(array $attributs = [], string $role = 'caissier'): User
    {
        $utilisateur = User::factory()->create(array_merge([
            'username' => 'marie',
            'password' => self::MOT_DE_PASSE,
        ], $attributs));
        $utilisateur->assignRole($role);

        return $utilisateur;
    }

    private function connexion(string $identifiant, ?string $poste = null, string $motDePasse = self::MOT_DE_PASSE)
    {
        return $this->postJson('/api/auth/login', [
            'identifiant' => $identifiant,
            'password' => $motDePasse,
            'device_name' => $poste ?? (string) Str::uuid(),
        ]);
    }

    // ---------------------------------------------------------------- Connexion

    public function test_la_connexion_cree_un_jeton_nomme_d_apres_le_poste(): void
    {
        $utilisateur = $this->compte();
        $poste = (string) Str::uuid();

        $reponse = $this->connexion('marie', $poste)->assertOk();

        $reponse->assertJsonStructure(['token', 'expires_at', 'user' => ['id', 'username', 'roles'], 'must_change_password', 'poste' => ['id', 'code']]);
        $reponse->assertJsonPath('user.id', $utilisateur->id);
        $reponse->assertJsonPath('user.roles.0', 'caissier');

        // Relecture en base : le jeton porte le NOM du poste, pas celui de la machine.
        $this->assertDatabaseHas('personal_access_tokens', ['name' => $poste, 'tokenable_id' => $utilisateur->id]);
        $this->assertSame(1, PersonalAccessToken::query()->count());
        $this->assertNotNull(PersonalAccessToken::query()->first()->expires_at);
    }

    public function test_le_jeton_dure_90_jours(): void
    {
        $this->compte();
        $this->connexion('marie')->assertOk();

        $jours = now()->diffInDays(PersonalAccessToken::query()->first()->expires_at, true);
        $this->assertEqualsWithDelta(90, $jours, 1);
    }

    public function test_se_reconnecter_supprime_l_ancien_jeton_du_meme_poste(): void
    {
        $this->compte();
        $poste = (string) Str::uuid();

        $premier = $this->connexion('marie', $poste)->json('token');
        $second = $this->connexion('marie', $poste)->json('token');

        $this->assertSame(1, PersonalAccessToken::query()->where('name', $poste)->count(), 'Un seul jeton actif par poste.');
        $this->assertNull(PersonalAccessToken::findToken($premier));
        $this->assertNotNull(PersonalAccessToken::findToken($second));
    }

    public function test_deux_postes_ont_chacun_leur_jeton(): void
    {
        $this->compte();

        $this->connexion('marie');
        $this->connexion('marie');

        $this->assertSame(2, PersonalAccessToken::query()->count());
        $this->assertSame(2, Poste::query()->count());
    }

    public function test_le_poste_recoit_un_code_stable_p1_p2(): void
    {
        $this->compte();
        $a = (string) Str::uuid();
        $b = (string) Str::uuid();

        $this->assertSame('P1', $this->connexion('marie', $a)->json('poste.code'));
        $this->assertSame('P2', $this->connexion('marie', $b)->json('poste.code'));
        // Se reconnecter ne change jamais le code (DV-21 : il prefixe les pieces).
        $this->assertSame('P1', $this->connexion('marie', $a)->json('poste.code'));
        $this->assertSame(2, Poste::query()->count());
    }

    public function test_l_identifiant_peut_etre_l_adresse_e_mail(): void
    {
        $this->compte(['email' => 'marie@example.test']);

        $this->connexion('marie@example.test')->assertOk();
    }

    public function test_un_mauvais_mot_de_passe_est_refuse_et_journalise_sans_jeton(): void
    {
        $this->compte();

        $this->connexion('marie', null, 'mauvais-mot-de-passe')
            ->assertStatus(401)
            ->assertJsonPath('message', 'Identifiant ou mot de passe incorrect.');

        $this->assertSame(0, PersonalAccessToken::query()->count());
        $this->assertSame(0, Poste::query()->count());
        $journal = AuditLog::query()->where('action', 'login.failed')->sole();
        $this->assertSame('marie', $journal->identifiant);
        $this->assertStringNotContainsString('mauvais-mot-de-passe', json_encode($journal->detail ?? []));
    }

    public function test_un_identifiant_inconnu_recoit_le_meme_message_qu_un_mauvais_mot_de_passe(): void
    {
        $this->connexion('personne')
            ->assertStatus(401)
            ->assertJsonPath('message', 'Identifiant ou mot de passe incorrect.');
    }

    public function test_un_compte_desactive_est_refuse_avec_son_motif(): void
    {
        $this->compte(['is_active' => false]);

        $this->connexion('marie')
            ->assertStatus(403)
            ->assertJsonPath('message', "Ce compte a été désactivé. Contactez l'administrateur.");

        $this->assertSame(0, PersonalAccessToken::query()->count());
    }

    public function test_un_compte_supprime_logiquement_est_refuse(): void
    {
        $this->compte()->delete();

        $this->connexion('marie')->assertStatus(401);
    }

    public function test_le_nom_du_poste_doit_etre_un_uuid(): void
    {
        $this->compte();

        $this->postJson('/api/auth/login', [
            'identifiant' => 'marie',
            'password' => self::MOT_DE_PASSE,
            'device_name' => 'PC-de-la-gerante',
        ])->assertStatus(422)->assertJsonValidationErrors('device_name');
    }

    public function test_la_connexion_n_est_pas_limitee(): void
    {
        $this->compte();

        // Decision du client : aucun blocage de connexion, ni au web ni a l'appairage d'un poste.
        for ($i = 0; $i < 12; $i++) {
            $this->connexion('marie', null, 'faux-'.$i)->assertStatus(401);
        }

        $this->connexion('marie')->assertOk();
    }

    public function test_la_connexion_laisse_une_trace_d_audit(): void
    {
        $utilisateur = $this->compte();
        $poste = (string) Str::uuid();

        $this->connexion('marie', $poste)->assertOk();

        $trace = AuditLog::query()->where('action', 'api.login')->sole();
        $this->assertSame($utilisateur->id, $trace->utilisateur_id);
        $this->assertSame('P1', $trace->detail['poste']);
        $this->assertSame($poste, $trace->detail['device_id']);
    }

    // --------------------------------------------------------- me / deconnexion

    public function test_me_rend_l_utilisateur_et_le_poste(): void
    {
        $this->compte();
        $reponse = $this->connexion('marie');
        $code = $reponse->json('poste.code');

        $this->avecJeton($reponse->json('token'))->getJson('/api/auth/me')
            ->assertOk()
            ->assertJsonPath('user.username', 'marie')
            ->assertJsonPath('poste.code', $code);
    }

    public function test_sans_jeton_l_api_repond_401_en_json(): void
    {
        $this->getJson('/api/auth/me')->assertStatus(401);
        // Meme sans en-tete Accept.
        $this->get('/api/auth/me')->assertStatus(401)->assertHeader('content-type', 'application/json');
    }

    public function test_la_deconnexion_supprime_le_jeton(): void
    {
        $this->compte();
        $jeton = $this->connexion('marie')->json('token');

        $this->avecJeton($jeton)->postJson('/api/auth/logout')->assertOk();

        $this->assertSame(0, PersonalAccessToken::query()->count());
    }

    public function test_un_contact_met_a_jour_le_dernier_contact_du_poste(): void
    {
        $this->compte();
        $poste = (string) Str::uuid();
        $jeton = $this->connexion('marie', $poste)->json('token');
        Poste::query()->where('device_id', $poste)->update(['dernier_contact_le' => now()->subDays(3)]);

        $this->avecJeton($jeton)->getJson('/api/auth/me')->assertOk();

        $contact = Poste::query()->where('device_id', $poste)->value('dernier_contact_le');
        $this->assertTrue(\Illuminate\Support\Carbon::parse($contact)->isToday());
    }

    // -------------------------------------------------- compte desactive / mdp temporaire

    public function test_un_compte_desactive_apres_connexion_est_refuse_partout(): void
    {
        $utilisateur = $this->compte();
        $jeton = $this->connexion('marie')->json('token');
        $utilisateur->update(['is_active' => false]);

        $this->avecJeton($jeton)->getJson('/api/auth/me')
            ->assertStatus(403)
            ->assertJsonPath('code', 'compte_desactive');
    }

    public function test_un_mot_de_passe_temporaire_n_ouvre_que_son_changement(): void
    {
        $this->compte(['must_change_password' => true]);
        $reponse = $this->connexion('marie')->assertOk()->assertJsonPath('must_change_password', true);
        $jeton = $reponse->json('token');

        // Tout est refuse (403, motif en francais)...
        $this->avecJeton($jeton)->getJson('/api/sync/pull')
            ->assertStatus(403)
            ->assertJsonPath('code', 'changement_mot_de_passe_obligatoire');
        // ... sauf me, la deconnexion et le changement lui-meme.
        $this->avecJeton($jeton)->getJson('/api/auth/me')->assertOk();
    }

    public function test_le_changement_de_mot_de_passe_leve_l_obligation_et_coupe_les_autres_postes(): void
    {
        $utilisateur = $this->compte(['must_change_password' => true]);
        $autre = $this->connexion('marie')->json('token');
        $jeton = $this->connexion('marie')->json('token');

        $this->avecJeton($jeton)->postJson('/api/auth/mot-de-passe', [
            'mot_de_passe_actuel' => self::MOT_DE_PASSE,
            'nouveau_mot_de_passe' => 'Nouveau-mot-de-passe-2',
            'nouveau_mot_de_passe_confirmation' => 'Nouveau-mot-de-passe-2',
        ])->assertOk();

        $utilisateur->refresh();
        $this->assertFalse($utilisateur->must_change_password);
        $this->assertTrue(\Illuminate\Support\Facades\Hash::check('Nouveau-mot-de-passe-2', $utilisateur->password));
        $this->assertNotNull(PersonalAccessToken::findToken($jeton), 'Le poste courant garde son jeton.');
        $this->assertNull(PersonalAccessToken::findToken($autre), 'Les autres postes doivent se reconnecter.');
        $this->assertSame(1, AuditLog::query()->where('action', 'api.mot_de_passe_change')->count());
    }

    public function test_un_nouveau_mot_de_passe_trop_court_est_refuse(): void
    {
        $this->compte(['must_change_password' => true]);
        $jeton = $this->connexion('marie')->json('token');

        $this->avecJeton($jeton)->postJson('/api/auth/mot-de-passe', [
            'mot_de_passe_actuel' => self::MOT_DE_PASSE,
            'nouveau_mot_de_passe' => 'court',
            'nouveau_mot_de_passe_confirmation' => 'court',
        ])->assertStatus(422)->assertJsonValidationErrors('nouveau_mot_de_passe');

        $this->assertTrue(User::query()->where('username', 'marie')->value('must_change_password'));
    }

    public function test_l_api_applique_la_regle_du_dart_avec_ses_messages(): void
    {
        $this->compte(['must_change_password' => true]);
        $jeton = $this->connexion('marie')->json('token');

        foreach ([
            'Abcdef1' => 'Le mot de passe doit compter au moins 8 caractères.',
            'abcdefg1' => 'Le mot de passe doit contenir au moins une majuscule.',
            'Abcdefgh' => 'Le mot de passe doit contenir au moins un chiffre.',
        ] as $mot => $message) {
            $this->avecJeton($jeton)->postJson('/api/auth/mot-de-passe', [
                'mot_de_passe_actuel' => self::MOT_DE_PASSE,
                'nouveau_mot_de_passe' => $mot,
                'nouveau_mot_de_passe_confirmation' => $mot,
            ])->assertStatus(422)->assertJsonPath('errors.nouveau_mot_de_passe.0', $message);
        }

        $this->avecJeton($jeton)->postJson('/api/auth/mot-de-passe', [
            'mot_de_passe_actuel' => self::MOT_DE_PASSE,
            'nouveau_mot_de_passe' => 'Abcdefg1',
            'nouveau_mot_de_passe_confirmation' => 'Abcdefg1',
        ])->assertOk();
    }

    // ------------------------------------------------------------- Le jeton dit qui parle

    public function test_le_push_d_un_autre_poste_est_refuse_sans_rien_ecrire_ni_journaliser(): void
    {
        $this->compte();
        $poste = (string) Str::uuid();
        $jeton = $this->connexion('marie', $poste)->json('token');
        $avant = AuditLog::query()->count();

        $this->avecJeton($jeton)->postJson('/api/sync/push', [
            'device_id' => (string) Str::uuid(), // un AUTRE poste
            'tables' => ['ventes' => [['id' => (string) Str::uuid()]]],
        ])->assertStatus(403)->assertJsonPath('code', 'poste_different_du_jeton');

        $this->assertSame($avant, AuditLog::query()->count(), 'Rien n\'est journalise.');
    }

    public function test_un_push_sans_device_id_est_refuse(): void
    {
        $this->compte();
        $jeton = $this->connexion('marie')->json('token');

        $this->avecJeton($jeton)->postJson('/api/sync/push', ['tables' => []])
            ->assertStatus(403)
            ->assertJsonPath('code', 'poste_different_du_jeton');
    }

    public function test_une_lecture_au_nom_d_un_autre_poste_est_refusee_mais_l_absence_est_tolere(): void
    {
        $this->compte();
        $poste = (string) Str::uuid();
        $jeton = $this->connexion('marie', $poste)->json('token');
        $autre = (string) Str::uuid();

        foreach (['/api/sync/pull', '/api/sync/demande'] as $route) {
            $this->avecJeton($jeton)->getJson("$route?device_id=$autre")
                ->assertStatus(403)->assertJsonPath('code', 'poste_different_du_jeton');
            $this->avecJeton($jeton)->getJson("$route?device_id=$poste")->assertOk();
            $this->avecJeton($jeton)->getJson($route)->assertOk(); // ancien poste : pas de device_id
        }
        $this->avecJeton($jeton)->postJson('/api/sync/resynchronisation/acquittement', ['device_id' => $autre])
            ->assertStatus(403);
        $this->avecJeton($jeton)->postJson('/api/sync/resynchronisation/acquittement', ['device_id' => $poste])
            ->assertOk();
    }

    public function test_le_push_de_son_propre_poste_passe_le_garde_fou(): void
    {
        $this->compte();
        $poste = (string) Str::uuid();
        $jeton = $this->connexion('marie', $poste)->json('token');

        // Le garde-fou laisse passer le bon poste ; un lot vide est accepte, sans trace.
        $this->avecJeton($jeton)->postJson('/api/sync/push', [
            'device_id' => $poste,
            'reset_mark' => 'initiale',
            'tables' => [],
        ])->assertOk();
    }

    // ------------------------------------------------------------------ Revocation

    private function administrateur(): User
    {
        return $this->compte(['username' => 'admin', 'name' => 'Admin'], 'admin');
    }

    public function test_la_revocation_supprime_tous_les_jetons_du_poste_tous_comptes(): void
    {
        $this->administrateur();
        $this->compte(['username' => 'paul']);
        $poste = (string) Str::uuid();

        // Deux comptes se sont reconnectes sur le meme poste : un seul jeton reste,
        // on cree donc un second jeton du meme nom a la main (cas limite).
        $jetonMarie = $this->connexion('paul', $poste)->json('token');
        User::query()->where('username', 'admin')->first()->createToken($poste);
        $this->assertSame(2, PersonalAccessToken::query()->where('name', $poste)->count());

        $jetonAdmin = $this->connexion('admin', (string) Str::uuid())->json('token');
        $this->avecJeton($jetonAdmin)->postJson('/api/parametres/postes/revoquer', ['device_name' => $poste])
            ->assertOk()
            ->assertJsonPath('jetons_supprimes', 2);

        $this->assertSame(0, PersonalAccessToken::query()->where('name', $poste)->count());
        $this->assertNull(PersonalAccessToken::findToken($jetonMarie));
        $this->assertNotNull(Poste::query()->where('device_id', $poste)->value('revoque_le'));
    }

    public function test_un_poste_revoque_recoit_401_au_contact_suivant(): void
    {
        $this->administrateur();
        $this->compte();
        $poste = (string) Str::uuid();
        $jeton = $this->connexion('marie', $poste)->json('token');
        $jetonAdmin = $this->connexion('admin', (string) Str::uuid())->json('token');

        $this->avecJeton($jetonAdmin)->postJson('/api/parametres/postes/revoquer', ['device_name' => $poste])->assertOk();

        $this->avecJeton($jeton)->getJson('/api/auth/me')->assertStatus(401);
    }

    public function test_la_revocation_est_journalisee(): void
    {
        $admin = $this->administrateur();
        $this->compte();
        $poste = (string) Str::uuid();
        $this->connexion('marie', $poste);
        $jetonAdmin = $this->connexion('admin', (string) Str::uuid())->json('token');

        $this->avecJeton($jetonAdmin)->postJson('/api/parametres/postes/revoquer', ['device_name' => $poste])->assertOk();

        $trace = AuditLog::query()->where('action', 'sync.appairage_revoque')->sole();
        $this->assertSame($admin->id, $trace->utilisateur_id);
        $this->assertSame($poste, $trace->detail['device_id']);
        $this->assertSame('P1', $trace->detail['poste']);
    }

    public function test_seul_un_administrateur_peut_revoquer(): void
    {
        $this->compte();
        $poste = (string) Str::uuid();
        $jeton = $this->connexion('marie', $poste)->json('token');

        $this->avecJeton($jeton)->postJson('/api/parametres/postes/revoquer', ['device_name' => $poste])
            ->assertStatus(403);

        $this->assertNull(Poste::query()->where('device_id', $poste)->value('revoque_le'));
        $this->assertNotNull(PersonalAccessToken::findToken($jeton));
    }

    public function test_revoquer_un_poste_inconnu_repond_404(): void
    {
        $this->administrateur();
        $jetonAdmin = $this->connexion('admin')->json('token');

        $this->avecJeton($jetonAdmin)->postJson('/api/parametres/postes/revoquer', ['device_name' => (string) Str::uuid()])
            ->assertStatus(404);
    }

    public function test_reappairer_un_poste_revoque_leve_la_revocation_et_garde_son_code(): void
    {
        $this->administrateur();
        $this->compte();
        $poste = (string) Str::uuid();
        $code = $this->connexion('marie', $poste)->json('poste.code');
        $jetonAdmin = $this->connexion('admin', (string) Str::uuid())->json('token');
        $this->avecJeton($jetonAdmin)->postJson('/api/parametres/postes/revoquer', ['device_name' => $poste])->assertOk();

        $this->connexion('marie', $poste)->assertOk()->assertJsonPath('poste.code', $code);

        $this->assertNull(Poste::query()->where('device_id', $poste)->value('revoque_le'));
    }
}
