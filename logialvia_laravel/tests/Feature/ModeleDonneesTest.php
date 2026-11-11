<?php

namespace Tests\Feature;

use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\User;
use Database\Seeders\AdminSeeder;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\PersonalAccessToken;
use Spatie\Permission\Models\Permission;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

/**
 * W1 — socle de donnees du serveur : cles UUID (DV-19), 4 roles (DV-07), modules,
 * parametres. Chaque test verifie l'ETAT DE LA BASE, pas la valeur de retour.
 */
class ModeleDonneesTest extends TestCase
{
    use RefreshDatabase;

    private function amorcer(): void
    {
        $this->seed(RolesAndPermissionsSeeder::class);
    }

    private function utilisateur(string $role): User
    {
        $this->amorcer();
        $utilisateur = User::factory()->create();
        $utilisateur->assignRole($role);

        return $utilisateur->fresh();
    }

    // ------------------------------------------------------------------ UUID

    public function test_un_utilisateur_a_une_cle_uuid(): void
    {
        $utilisateur = User::factory()->create();

        $this->assertMatchesRegularExpression(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/',
            $utilisateur->id,
        );
        $this->assertSame($utilisateur->id, User::query()->where('username', $utilisateur->username)->value('id'));
    }

    public function test_la_suppression_est_logique_seulement(): void
    {
        $utilisateur = User::factory()->create();
        $utilisateur->delete();

        $this->assertNull(User::query()->find($utilisateur->id));
        $this->assertNotNull(User::withTrashed()->find($utilisateur->id), 'La ligne doit rester en base.');
        $this->assertDatabaseHas('users', ['id' => $utilisateur->id]);
    }

    public function test_un_jeton_sanctum_se_rattache_a_la_cle_uuid_de_l_utilisateur(): void
    {
        $utilisateur = User::factory()->create();
        $jeton = $utilisateur->createToken('poste-2d9f');

        $this->assertDatabaseHas('personal_access_tokens', [
            'tokenable_id' => $utilisateur->id,
            'name' => 'poste-2d9f',
        ]);

        $retrouve = PersonalAccessToken::findToken($jeton->plainTextToken);
        $this->assertNotNull($retrouve);
        $this->assertTrue($retrouve->tokenable->is($utilisateur));
    }

    public function test_les_roles_se_rattachent_a_la_cle_uuid(): void
    {
        $utilisateur = $this->utilisateur('animalier');

        $this->assertDatabaseHas('model_has_roles', ['model_id' => $utilisateur->id]);
        $this->assertTrue($utilisateur->hasRole('animalier'));
    }

    // ----------------------------------------------------------- Roles, droits

    public function test_quatre_roles_et_les_droits_de_la_configuration(): void
    {
        $this->amorcer();

        $this->assertEqualsCanonicalizing(
            array_keys(config('logialvia.roles')),
            Role::query()->pluck('name')->all(),
        );
        $this->assertSame(
            ['admin', 'animalier', 'caissier', 'comptable'],
            Role::query()->orderBy('name')->pluck('name')->all(),
        );
        $this->assertSame(count(config('logialvia.permissions')), Permission::query()->count());
    }

    public function test_l_administrateur_a_tous_les_droits_explicitement(): void
    {
        $admin = $this->utilisateur('admin');

        foreach (config('logialvia.permissions') as $permission) {
            $this->assertTrue($admin->can($permission), "admin devrait avoir $permission");
        }
        $this->assertCount(count(config('logialvia.permissions')), $admin->getAllPermissions());
    }

    public function test_les_cellules_de_la_matrice_validee(): void
    {
        $caissier = $this->utilisateur('caissier');
        $this->assertTrue($caissier->can('view-ventes'));
        $this->assertTrue($caissier->can('manage-ventes'));
        // DV-06 : consulte et reimprime les factures, ne les annule pas ; pas d'inventaire.
        $this->assertTrue($caissier->can('view-facturation'));
        $this->assertFalse($caissier->can('manage-facturation'));
        $this->assertFalse($caissier->can('view-stocks'));
        $this->assertFalse($caissier->can('view-comptabilite'));
        $this->assertFalse($caissier->can('manage-users'));

        $animalier = $this->utilisateur('animalier');
        $this->assertTrue($animalier->can('view-elevage'));
        $this->assertTrue($animalier->can('manage-elevage'));
        $this->assertFalse($animalier->can('view-ventes'));
        $this->assertFalse($animalier->can('view-parametres'));
        $this->assertFalse($animalier->can('manage-modules'), "L'activation d'une filiere reste a l'administrateur.");

        $comptable = $this->utilisateur('comptable');
        $this->assertTrue($comptable->can('view-comptabilite'));
        $this->assertTrue($comptable->can('manage-comptabilite'));
        $this->assertTrue($comptable->can('view-rapports'));
        $this->assertTrue($comptable->can('manage-facturation'));
        $this->assertFalse($comptable->can('view-stocks'));
        $this->assertFalse($comptable->can('manage-elevage'));
        $this->assertFalse($comptable->can('close-fiscal-year'), 'Admin seul par defaut (DV-15).');
    }

    public function test_l_amorcage_des_roles_est_idempotent(): void
    {
        $this->amorcer();
        $this->amorcer();

        $this->assertSame(4, Role::query()->count());
        $this->assertSame(count(config('logialvia.permissions')), Permission::query()->count());
    }

    // ---------------------------------------------------------------- Modules

    public function test_les_cinq_modules_sont_desactives_par_defaut(): void
    {
        $this->seed(ModulesActifsSeeder::class);

        $modules = ModuleActif::query()->get();
        $this->assertCount(5, $modules);
        $this->assertTrue($modules->every(fn ($m) => $m->is_actif === false));
        $this->assertEqualsCanonicalizing(array_keys(config('logialvia.modules')), $modules->pluck('module_id')->all());
        $this->assertNull(
            ModuleActif::query()->whereIn('module_id', ['goliaths', 'pintades'])->first(),
            'Goliaths et Pintades sont toujours actifs : aucune ligne.',
        );
    }

    public function test_relancer_l_amorcage_ne_remet_pas_un_module_a_zero(): void
    {
        $this->seed(ModulesActifsSeeder::class);
        ModuleActif::query()->where('module_id', 'ovins')->update(['is_actif' => true]);

        $this->seed(ModulesActifsSeeder::class);

        $this->assertSame(5, ModuleActif::query()->count(), 'Aucun doublon.');
        $this->assertTrue(ModuleActif::query()->where('module_id', 'ovins')->value('is_actif'));
    }

    // -------------------------------------------------------------- Parametres

    public function test_les_parametres_sont_une_ligne_unique(): void
    {
        $premiere = ParametresEntreprise::courant();
        $seconde = ParametresEntreprise::courant();

        $this->assertTrue($premiere->is($seconde));
        $this->assertSame(1, ParametresEntreprise::query()->count());
        $this->assertSame('ALLMANY ET COMPAGNIE', $premiere->raison_sociale);
        $this->assertFalse($premiere->mecef_actif);
        $this->assertFalse($premiere->mode_donnees_test);
    }

    // ------------------------------------------------------- Premier administrateur

    public function test_sans_mot_de_passe_en_environnement_aucun_administrateur_n_est_cree(): void
    {
        config(['logialvia.admin.password' => null]);
        $this->amorcer();

        $this->seed(AdminSeeder::class);

        $this->assertSame(0, User::query()->count());
    }

    public function test_un_mot_de_passe_trop_court_n_ouvre_aucun_compte(): void
    {
        config(['logialvia.admin.password' => 'court']);
        $this->amorcer();

        $this->seed(AdminSeeder::class);

        $this->assertSame(0, User::query()->count());
    }

    public function test_l_administrateur_initial_doit_changer_son_mot_de_passe(): void
    {
        config(['logialvia.admin.password' => 'Motdepasse-initial-1', 'logialvia.admin.username' => 'gerante']);
        $this->amorcer();

        $this->seed(AdminSeeder::class);
        $this->seed(AdminSeeder::class);

        $admin = User::query()->where('username', 'gerante')->sole();
        $this->assertSame(1, User::query()->count(), 'Relancer ne duplique pas.');
        $this->assertTrue($admin->hasRole('admin'));
        $this->assertTrue($admin->must_change_password);
        $this->assertTrue($admin->is_active);
        $this->assertNotSame('Motdepasse-initial-1', $admin->password, 'Jamais en clair.');
        $this->assertTrue(Hash::check('Motdepasse-initial-1', $admin->password));
    }
}
