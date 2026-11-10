<?php

namespace Tests\Feature\Web;

use App\Livewire\GestionUtilisateurs;
use App\Livewire\ParametresGeneraux;
use App\Models\AuditLog;
use App\Models\User;
use App\Services\PostesService;
use App\Services\UtilisateursService;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Tests\TestCase;

/** Gestion web des comptes du serveur : droits, regle de mot de passe, garde-fous d'expert, audit (doc 47u §1). */
class GestionUtilisateursWebTest extends TestCase
{
    use \Tests\Concerns\LitXlsx, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
    }

    private function compte(string $role, string $username): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username), 'email' => $username.'@exemple.bj']);
        $u->assignRole($role);

        return $u;
    }

    private function admin(string $username = 'gerante'): User
    {
        return $this->compte('admin', $username);
    }

    private function composant(User $acteur)
    {
        return Livewire::actingAs($acteur)->test(GestionUtilisateurs::class);
    }

    private function remplir($c, array $surcharge = [])
    {
        foreach (array_merge([
            'nom' => 'Amina Bio', 'identifiant' => 'amina', 'email' => '', 'role' => 'caissier',
            'motDePasse' => 'Temporaire1', 'confirmation' => 'Temporaire1',
        ], $surcharge) as $propriete => $valeur) {
            $c->set($propriete, $valeur);
        }

        return $c;
    }

    private function dernierAudit(string $action): ?AuditLog
    {
        return AuditLog::query()->where('action', $action)->latest('created_at')->first();
    }

    // ------------------------------------------------------------------- Acces

    public function test_seul_manage_users_ouvre_la_gestion(): void
    {
        foreach (['caissier', 'animalier', 'comptable'] as $i => $role) {
            Livewire::actingAs($this->compte($role, "u$i"))->test(GestionUtilisateurs::class)->assertForbidden();
        }
        // Un compte qui voit les parametres sans manage-users : l'onglet ne montre aucune gestion.
        $lecteur = $this->compte('comptable', 'lecteur');
        $lecteur->givePermissionTo('view-parametres');
        Livewire::actingAs($lecteur)->test(ParametresGeneraux::class)->call('choisirOnglet', 2)
            ->assertDontSeeHtml('wire:click="nouveau"')->assertSee('réservée à l\'administrateur', false);

        $this->composant($this->admin())->assertOk()->assertSee('Gestion des Utilisateurs')->assertSee('Ajouter un Utilisateur');
    }

    public function test_la_liste_montre_role_statut_et_jamais_un_secret(): void
    {
        $admin = $this->admin();
        $inactif = $this->compte('animalier', 'ali');
        $inactif->forceFill(['is_active' => false, 'must_change_password' => true])->save();

        $html = $this->composant($admin)
            ->assertSeeHtml('data-compte="ali"')->assertSee('Agent d\'Élevage')->assertSee('Désactivé')
            ->assertSee('Mot de passe temporaire')->assertSee('(vous)')->html();

        $this->assertStringNotContainsString($admin->password, $html);
        $this->assertStringNotContainsString($inactif->password, $html);
        $this->assertStringNotContainsString('password', strtolower(preg_replace('/type="password"|wire:model="[^"]*"|autocomplete="[^"]*"/', '', $html)));
    }

    public function test_la_recherche_filtre_les_comptes(): void
    {
        $this->compte('caissier', 'amina');
        $this->compte('caissier', 'bruno');

        $this->composant($this->admin())->set('recherche', 'brun')
            ->assertSeeHtml('data-compte="bruno"')->assertDontSeeHtml('data-compte="amina"');
    }

    // ---------------------------------------------------------------- Creation

    public function test_creer_un_compte_avec_mot_de_passe_temporaire_et_audit(): void
    {
        $admin = $this->admin();
        $c = $this->remplir($this->composant($admin))->call('nouveau');
        $this->remplir($c)->call('enregistrer')->assertSet('erreur', null)->assertSet('formulaire', false)
            ->assertSee('Compte « amina » créé')->assertSet('motDePasse', '')->assertSet('confirmation', '');

        $u = User::query()->where('username', 'amina')->firstOrFail();
        $this->assertSame('Amina Bio', $u->name);
        $this->assertTrue($u->hasRole('caissier'));
        $this->assertTrue($u->is_active);
        $this->assertTrue($u->must_change_password, 'mot de passe administre = temporaire');
        $this->assertTrue(Hash::check('Temporaire1', $u->password));

        $audit = $this->dernierAudit('utilisateur.cree');
        $this->assertSame($admin->id, $audit->utilisateur_id);
        $this->assertSame(['cible' => 'amina', 'role' => 'caissier'], $audit->detail);
        $this->assertStringNotContainsString('Temporaire1', json_encode($audit->getAttributes()));
    }

    public function test_les_quatre_roles_sont_attribuables(): void
    {
        $c = $this->composant($this->admin());
        foreach (['admin', 'comptable', 'caissier', 'animalier'] as $i => $role) {
            $c->call('nouveau');
            $this->remplir($c, ['identifiant' => "r$i", 'role' => $role])->call('enregistrer')->assertSet('erreur', null);
            $this->assertTrue(User::query()->where('username', "r$i")->firstOrFail()->hasRole($role));
        }
        $this->composant($this->admin('autre'))->call('nouveau')->assertSee('Administrateur')->assertSee('Comptable')
            ->assertSee('Agent de Vente')->assertSee('Agent d\'Élevage');
    }

    /** @dataProvider creationsRefusees */
    public function test_chaque_regle_de_creation_a_son_message(array $surcharge, string $message): void
    {
        $this->compte('caissier', 'pris');
        User::query()->where('username', 'pris')->update(['email' => 'pris@exemple.bj']);

        $c = $this->composant($this->admin())->call('nouveau');
        $this->remplir($c, $surcharge)->call('enregistrer')->assertSet('erreur', $message)->assertSet('formulaire', true);

        $this->assertSame(2, User::withTrashed()->count(), 'seuls l\'administrateur et le compte deja pris existent');
        $this->assertNull($this->dernierAudit('utilisateur.cree'));
    }

    public static function creationsRefusees(): array
    {
        return [
            'nom vide' => [['nom' => '  '], 'Le nom complet est obligatoire.'],
            'identifiant vide' => [['identifiant' => ' '], 'L\'identifiant de connexion est obligatoire.'],
            'identifiant trop long' => [['identifiant' => str_repeat('a', 61)], 'L\'identifiant de connexion est trop long (60 caractères au plus).'],
            'role absent' => [['role' => ''], 'Le rôle est obligatoire.'],
            'role inconnu' => [['role' => 'acheteur'], 'Ce rôle n\'existe pas.'],
            'identifiant pris' => [['identifiant' => 'pris'], 'Cet identifiant est déjà utilisé (un compte supprimé le garde : restaurez-le depuis la Corbeille).'],
            'email invalide' => [['email' => 'pas-un-mail'], 'Le format de l\'adresse e-mail est invalide.'],
            'email pris' => [['email' => 'pris@exemple.bj'], 'Cette adresse e-mail est déjà utilisée.'],
            'mot de passe vide' => [['motDePasse' => '', 'confirmation' => ''], 'Le mot de passe est obligatoire.'],
            'trop court' => [['motDePasse' => 'Ab1', 'confirmation' => 'Ab1'], 'Le mot de passe doit compter au moins 8 caractères.'],
            'sans majuscule' => [['motDePasse' => 'temporaire1', 'confirmation' => 'temporaire1'], 'Le mot de passe doit contenir au moins une majuscule.'],
            'sans chiffre' => [['motDePasse' => 'Temporaire', 'confirmation' => 'Temporaire'], 'Le mot de passe doit contenir au moins un chiffre.'],
            'confirmation differente' => [['confirmation' => 'Autre12345'], 'Les deux mots de passe ne correspondent pas.'],
        ];
    }

    public function test_un_identifiant_courriel_remplit_la_colonne_email_pour_la_connexion(): void
    {
        $c = $this->composant($this->admin())->call('nouveau');
        $this->remplir($c, ['identifiant' => 'amina@allmany.bj'])->call('enregistrer')->assertSet('erreur', null);

        $u = User::query()->where('username', 'amina@allmany.bj')->firstOrFail();
        $this->assertSame('amina@allmany.bj', $u->email, 'la connexion cherche la colonne email quand l\'identifiant contient @');
    }

    public function test_un_compte_supprime_garde_son_identifiant(): void
    {
        $gone = $this->compte('caissier', 'amina');
        $gone->delete();

        $c = $this->composant($this->admin())->call('nouveau');
        $this->remplir($c)->call('enregistrer')->assertSee('restaurez-le depuis la Corbeille');
    }

    // ------------------------------------------------------------ Modification

    public function test_modifier_nom_role_et_email(): void
    {
        $admin = $this->admin();
        $cible = $this->compte('caissier', 'amina');

        $this->composant($admin)->call('modifier', $cible->id)
            ->assertSet('nom', 'Amina')->assertSet('role', 'caissier')->assertSet('identifiant', 'amina')
            ->set('nom', 'Amina Bio')->set('role', 'comptable')->set('email', 'nouveau@exemple.bj')
            ->call('enregistrer')->assertSet('erreur', null)->assertSee('Compte modifié.');

        $cible->refresh();
        $this->assertSame('Amina Bio', $cible->name);
        $this->assertTrue($cible->hasRole('comptable'));
        $this->assertFalse($cible->hasRole('caissier'));
        $this->assertSame('nouveau@exemple.bj', $cible->email);
        $this->assertSame('amina', $cible->username, 'l\'identifiant de connexion ne change jamais');
        $this->assertSame(['cible' => 'amina', 'role_avant' => 'caissier', 'role_apres' => 'comptable'], $this->dernierAudit('utilisateur.modifie')->detail);
    }

    public function test_modifier_refuse_nom_vide_role_inconnu_et_email_deja_pris(): void
    {
        $admin = $this->admin();
        $cible = $this->compte('caissier', 'amina');
        $this->compte('caissier', 'bruno');
        $c = $this->composant($admin)->call('modifier', $cible->id);

        $c->set('nom', ' ')->call('enregistrer')->assertSet('erreur', 'Le nom complet est obligatoire.');
        $c->set('nom', 'Amina')->set('role', 'acheteur')->call('enregistrer')->assertSet('erreur', 'Ce rôle n\'existe pas.');
        $c->set('role', '')->call('enregistrer')->assertSet('erreur', 'Le rôle est obligatoire.');
        $c->set('role', 'caissier')->set('email', 'bruno@exemple.bj')->call('enregistrer')->assertSet('erreur', 'Cette adresse e-mail est déjà utilisée.');
        $c->set('email', 'x')->call('enregistrer')->assertSet('erreur', 'Le format de l\'adresse e-mail est invalide.');
        $this->assertSame('caissier', $cible->fresh()->roles->first()->name);
    }

    public function test_on_ne_modifie_pas_son_propre_role_mais_son_nom_oui(): void
    {
        $admin = $this->admin();
        $this->admin('autre'); // un second administrateur existe : seul « soi-meme » bloque

        $c = $this->composant($admin)->call('modifier', $admin->id)->set('role', 'comptable')->call('enregistrer')
            ->assertSet('erreur', 'Vous ne pouvez pas modifier le rôle de votre propre compte.');
        $this->assertTrue($admin->fresh()->hasRole('admin'));

        $c->set('role', 'admin')->set('nom', 'Gérante Principale')->call('enregistrer')->assertSet('erreur', null);
        $this->assertSame('Gérante Principale', $admin->fresh()->name);
    }

    public function test_le_dernier_administrateur_actif_ne_peut_pas_etre_retrograde(): void
    {
        $dernier = $this->admin('seul');
        $gestionnaire = $this->compte('comptable', 'gestionnaire');
        $gestionnaire->givePermissionTo('manage-users');

        $erreur = app(UtilisateursService::class)->modifier($gestionnaire, $dernier->id, 'Seul', 'caissier', null);

        $this->assertSame('Impossible de rétrograder le dernier compte administrateur actif.', $erreur);
        $this->assertTrue($dernier->fresh()->hasRole('admin'));
        // Un administrateur DESACTIVE ne compte pas comme relais.
        $this->admin('dormant')->forceFill(['is_active' => false])->save();
        $this->assertSame($erreur, app(UtilisateursService::class)->modifier($gestionnaire, $dernier->id, 'Seul', 'caissier', null));
    }

    public function test_un_administrateur_peut_etre_retrograde_quand_un_autre_reste_actif(): void
    {
        $admin = $this->admin();
        $autre = $this->admin('autre');

        $this->assertNull(app(UtilisateursService::class)->modifier($admin, $autre->id, 'Autre', 'comptable', null));
        $this->assertTrue($autre->fresh()->hasRole('comptable'));
    }

    // ---------------------------------------------------- Desactivation / suppression

    private function jetons(User $u, int $n = 2): void
    {
        for ($i = 0; $i < $n; $i++) {
            app(PostesService::class)->appairer($u, (string) Str::uuid());
        }
    }

    public function test_desactiver_retire_les_jetons_refuse_la_connexion_et_se_defait(): void
    {
        $admin = $this->admin();
        $cible = $this->compte('caissier', 'amina');
        $cible->forceFill(['password' => 'Motdepasse1'])->save();
        $this->jetons($cible);
        $this->assertSame(2, $cible->tokens()->count());

        $this->composant($admin)->call('demanderAction', 'desactiver', $cible->id)
            ->assertSet('actionAConfirmer', 'desactiver')->assertSee('Désactiver ce compte ?')
            ->call('confirmerAction')->assertSet('erreur', null)->assertSee('désactivé');

        $this->assertFalse($cible->fresh()->is_active);
        $this->assertSame(0, $cible->tokens()->count(), 'un compte desactive perd ses jetons de poste');
        $this->assertSame(['cible' => 'amina', 'jetons_supprimes' => 2], $this->dernierAudit('utilisateur.desactive')->detail);

        $resultat = app(\App\Services\AuthentificationService::class)->verifier('amina', 'Motdepasse1');
        $this->assertNull($resultat['utilisateur']);
        $this->assertSame(\App\Services\AuthentificationService::MESSAGE_DESACTIVE, $resultat['erreur']);

        $this->composant($admin)->call('reactiver', $cible->id)->assertSee('Compte réactivé.');
        $this->assertTrue($cible->fresh()->is_active);
        $this->assertNotNull($this->dernierAudit('utilisateur.reactive'));
    }

    public function test_un_compte_desactive_en_session_est_deconnecte_au_prochain_clic(): void
    {
        $cible = $this->compte('animalier', 'ali');
        $this->actingAs($cible)->get('/profil')->assertOk();

        $cible->forceFill(['is_active' => false])->save();
        $this->get('/profil')->assertRedirect(route('login'));
        $this->assertGuest();
        $this->get('/login')->assertSee('Ce compte a été désactivé.', false);
    }

    public function test_le_controle_du_compte_est_aussi_applique_aux_appels_livewire_d_une_page_ouverte(): void
    {
        $this->assertContains(\App\Http\Middleware\CompteActifWeb::class, \Livewire\Livewire::getPersistentMiddleware());
    }

    public function test_on_ne_desactive_ni_ne_supprime_son_propre_compte(): void
    {
        $admin = $this->admin();
        $this->admin('autre');
        $service = app(UtilisateursService::class);

        $this->assertSame('Vous ne pouvez pas désactiver votre propre compte.', $service->desactiver($admin, $admin->id));
        $this->assertSame('Vous ne pouvez pas supprimer votre propre compte.', $service->supprimer($admin, $admin->id));
        $this->assertSame('Pour changer votre propre mot de passe, passez par Mon Profil.', $service->reinitialiserMotDePasse($admin, $admin->id, 'Temporaire1', 'Temporaire1'));
        $this->assertTrue($admin->fresh()->is_active);
        $this->assertNull($admin->fresh()->deleted_at);

        // Et l'interface ne propose meme pas les boutons sur sa propre ligne.
        $html = $this->composant($admin)->html();
        $this->assertStringNotContainsString("demanderAction('supprimer', '{$admin->id}')", $html);
        $this->assertStringContainsString("demanderAction('supprimer', '".User::query()->where('username', 'autre')->value('id')."')", $html);
    }

    public function test_le_dernier_administrateur_actif_est_protege(): void
    {
        $admin = $this->admin();
        $gestionnaire = $this->compte('comptable', 'gestionnaire');
        $gestionnaire->givePermissionTo('manage-users');
        $service = app(UtilisateursService::class);

        $this->assertSame('Impossible de désactiver le dernier compte administrateur actif.', $service->desactiver($gestionnaire, $admin->id));
        $this->assertSame('Impossible de supprimer le dernier compte administrateur actif.', $service->supprimer($gestionnaire, $admin->id));
        $this->assertTrue($admin->fresh()->is_active);
        $this->assertNull($admin->fresh()->deleted_at);

        // Un administrateur DESACTIVE ne compte pas : le seul actif reste protege malgre un second compte admin inactif.
        $inactif = $this->admin('dormant');
        $inactif->forceFill(['is_active' => false])->save();
        $this->assertSame('Impossible de supprimer le dernier compte administrateur actif.', $service->supprimer($gestionnaire, $admin->id));

        // Un second administrateur ACTIF leve la protection.
        $this->admin('relais');
        $this->assertNull($service->desactiver($gestionnaire, $admin->id));
    }

    public function test_supprimer_archive_le_compte_retire_les_jetons_et_audite(): void
    {
        $admin = $this->admin();
        $cible = $this->compte('caissier', 'amina');
        $this->jetons($cible, 1);

        $this->composant($admin)->call('demanderAction', 'supprimer', $cible->id)->assertSee('Supprimer ce compte ?')
            ->call('confirmerAction')->assertSet('erreur', null)->assertSee('archivé')->assertDontSeeHtml('data-compte="amina"');

        $this->assertNull(User::query()->find($cible->id));
        $this->assertNotNull(User::onlyTrashed()->find($cible->id), 'suppression logique : jamais d\'effacement');
        $this->assertSame(0, $cible->tokens()->count());
        $this->assertSame(['cible' => 'amina', 'jetons_supprimes' => 1], $this->dernierAudit('utilisateur.archive')->detail);
        // La session d'un compte supprime ne retrouve plus son utilisateur.
        $this->assertNull(app(\App\Services\AuthentificationService::class)->verifier('amina', 'password')['utilisateur']);
    }

    public function test_une_action_inconnue_ne_demande_aucune_confirmation(): void
    {
        $cible = $this->compte('caissier', 'amina');
        $this->composant($this->admin())->call('demanderAction', 'purger', $cible->id)->assertSet('actionAConfirmer', null)
            ->call('confirmerAction')->assertSet('erreur', null);
        $this->assertNotNull(User::query()->find($cible->id));
    }

    // ---------------------------------------------------- Reinitialisation du mot de passe

    public function test_reinitialiser_pose_un_mot_de_passe_temporaire_et_revoque_les_postes(): void
    {
        $admin = $this->admin();
        $cible = $this->compte('caissier', 'amina');
        $this->jetons($cible);

        $this->composant($admin)->call('demanderReinitialisation', $cible->id)->assertSee('Réinitialiser le mot de passe')
            ->set('motDePasse', 'Provisoire9')->set('confirmation', 'Provisoire9')->call('reinitialiser')
            ->assertSet('erreur', null)->assertSet('motDePasse', '')->assertSet('confirmation', '')->assertSet('reinitialisationId', null)
            ->assertSee('Mot de passe temporaire posé pour « amina »')->assertDontSee('Provisoire9');

        $cible->refresh();
        $this->assertTrue(Hash::check('Provisoire9', $cible->password));
        $this->assertTrue($cible->must_change_password, 'changement obligatoire a la prochaine connexion');
        $this->assertSame(0, $cible->tokens()->count());
        $audit = $this->dernierAudit('utilisateur.mdp_reinitialise');
        $this->assertSame(['cible' => 'amina', 'jetons_supprimes' => 2], $audit->detail);
        $this->assertStringNotContainsString('Provisoire9', json_encode($audit->getAttributes()));
    }

    public function test_apres_reinitialisation_seul_le_changement_de_mot_de_passe_est_ouvert(): void
    {
        $cible = $this->compte('caissier', 'amina');
        app(UtilisateursService::class)->reinitialiserMotDePasse($this->admin(), $cible->id, 'Provisoire9', 'Provisoire9');

        $this->app['auth']->forgetGuards();
        $this->actingAs($cible->fresh())->get('/dashboard')->assertRedirect(route('mot-de-passe'));
        $this->actingAs($cible->fresh())->get('/mot-de-passe')->assertOk();
    }

    /** @dataProvider motsDePasseRefuses */
    public function test_la_reinitialisation_applique_la_regle_du_poste(string $mdp, string $confirmation, string $message): void
    {
        $cible = $this->compte('caissier', 'amina');
        $avant = $cible->password;

        $this->composant($this->admin())->call('demanderReinitialisation', $cible->id)
            ->set('motDePasse', $mdp)->set('confirmation', $confirmation)->call('reinitialiser')->assertSet('erreur', $message);

        $this->assertSame($avant, $cible->fresh()->password);
        $this->assertFalse($cible->fresh()->must_change_password);
    }

    public static function motsDePasseRefuses(): array
    {
        return [
            'vide' => ['', '', 'Le mot de passe est obligatoire.'],
            'court' => ['Ab1', 'Ab1', 'Le mot de passe doit compter au moins 8 caractères.'],
            'sans majuscule' => ['provisoire9', 'provisoire9', 'Le mot de passe doit contenir au moins une majuscule.'],
            'sans chiffre' => ['Provisoire', 'Provisoire', 'Le mot de passe doit contenir au moins un chiffre.'],
            'confirmation' => ['Provisoire9', 'Provisoire8', 'Les deux mots de passe ne correspondent pas.'],
        ];
    }

    // ------------------------------------------------------------------- Droits

    public function test_chaque_methode_d_ecriture_reverifie_le_droit(): void
    {
        $admin = $this->admin();
        $cible = $this->compte('caissier', 'amina');
        $intrus = $this->compte('comptable', 'intrus'); // aucun manage-users

        $appels = [
            ['nouveau', []], ['modifier', [$cible->id]], ['enregistrer', []], ['annuler', null],
            ['demanderReinitialisation', [$cible->id]], ['reinitialiser', []],
            ['demanderAction', ['supprimer', $cible->id]], ['confirmerAction', []], ['reactiver', [$cible->id]], ['exporter', []],
        ];
        foreach ($appels as [$methode, $arguments]) {
            if ($arguments === null) {
                continue; // `annuler` ne touche aucune donnee : il ferme seulement la modale
            }
            // Composant NEUF par appel (l'etat d'un test ne doit jamais masquer un droit manquant) :
            // monte par un administrateur, puis appele apres perte du droit (compte retrograde en cours de page).
            $composant = Livewire::actingAs($admin)->test(GestionUtilisateurs::class);
            $this->actingAs($intrus);
            $composant->call($methode, ...$arguments)->assertForbidden();
        }

        $this->assertNotNull(User::query()->find($cible->id));
        $this->assertTrue($cible->fresh()->is_active);
        $this->assertNotNull($admin);
    }

    public function test_le_service_reverifie_le_droit_lui_meme(): void
    {
        $cible = $this->compte('caissier', 'amina');
        $intrus = $this->compte('comptable', 'intrus');
        $service = app(UtilisateursService::class);

        foreach ([
            fn () => $service->creer($intrus, 'N', 'n', null, 'caissier', 'Temporaire1', 'Temporaire1'),
            fn () => $service->modifier($intrus, $cible->id, 'N', 'caissier', null),
            fn () => $service->desactiver($intrus, $cible->id),
            fn () => $service->reactiver($intrus, $cible->id),
            fn () => $service->reinitialiserMotDePasse($intrus, $cible->id, 'Temporaire1', 'Temporaire1'),
            fn () => $service->supprimer($intrus, $cible->id),
            fn () => $service->restaurer($intrus, $cible->id),
            fn () => $service->purger($intrus, $cible->id),
        ] as $appel) {
            try {
                $appel();
                $this->fail('le service aurait du refuser (403)');
            } catch (HttpException $e) {
                $this->assertSame(403, $e->getStatusCode());
            }
        }
        $this->assertNull(User::query()->where('username', 'n')->first());
    }

    public function test_la_route_exige_view_parametres_et_le_composant_manage_users(): void
    {
        $this->actingAs($this->compte('comptable', 'compta'))->get('/parametres/generaux')->assertForbidden();
        $this->actingAs($this->admin())->get('/parametres/generaux')->assertOk();
    }

    // ------------------------------------------------------- Restauration / purge

    public function test_restaurer_un_compte_archive_puis_le_purger_est_reserve_a_l_administrateur(): void
    {
        $admin = $this->admin();
        $cible = $this->compte('caissier', 'amina');
        $service = app(UtilisateursService::class);
        $service->supprimer($admin, $cible->id);

        $this->assertNull($service->restaurer($admin, $cible->id));
        $this->assertNotNull(User::query()->find($cible->id));
        $this->assertNotNull($this->dernierAudit('utilisateur.restaure'));

        $service->supprimer($admin, $cible->id);
        $gestionnaire = $this->compte('comptable', 'gestionnaire');
        $gestionnaire->givePermissionTo('manage-users');
        try {
            $service->purger($gestionnaire, $cible->id);
            $this->fail('la purge est reservee a l\'administrateur');
        } catch (HttpException $e) {
            $this->assertSame(403, $e->getStatusCode());
        }
        $this->assertNotNull(User::onlyTrashed()->find($cible->id));

        $this->assertNull($service->purger($admin, $cible->id));
        $this->assertNull(User::withTrashed()->find($cible->id));
        $this->assertNotNull($this->dernierAudit('utilisateur.purge'), 'la trace survit au compte efface');
    }

    public function test_l_export_xlsx_liste_les_comptes_sans_aucun_secret_et_exige_le_droit(): void
    {
        $admin = $this->admin();
        $this->compte('animalier', 'ali')->forceFill(['is_active' => false, 'must_change_password' => true, 'name' => '=1+1'])->save();

        $c = $this->composant($admin)->call('exporter');
        $c->assertFileDownloaded('utilisateurs.xlsx', null, \App\Support\ExportXlsx::TYPE);
        $lignes = $this->lignesXlsx(base64_decode($c->effects['download']['content']));
        $this->assertSame(['Nom complet', 'Identifiant', 'E-mail', 'Rôle', 'Statut', 'Mot de passe temporaire', 'Dernière connexion'], $lignes[0]);
        $this->assertCount(3, $lignes);
        $texte = implode('|', array_merge(...$lignes));
        $this->assertStringContainsString('=1+1', $texte);
        $this->assertStringContainsString('Désactivé', $texte);
        $this->assertStringNotContainsString($admin->password, $texte);
        $this->assertStringNotContainsString('$2y$', $texte);

        $neuf = $this->composant($admin);
        $this->actingAs($this->compte('comptable', 'intrus'));
        $neuf->call('exporter')->assertForbidden();
    }
}
