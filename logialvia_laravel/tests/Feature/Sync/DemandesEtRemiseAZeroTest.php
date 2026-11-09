<?php

namespace Tests\Feature\Sync;

use App\Models\Client;
use App\Models\ParametresEntreprise;
use App\Models\Poste;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** W3b : demande de synchronisation, resynchronisation, remise a zero. */
class DemandesEtRemiseAZeroTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function demande(array $poste)
    {
        return $this->avecJeton($poste['jeton'])->getJson('/api/sync/demande');
    }

    // ---------------------------------------------------- Demande de synchro

    public function test_sans_demande_le_poste_ne_synchronise_pas(): void
    {
        $b = $this->poste('caissier');
        $this->demande($b)->assertOk()->assertJson(['synchroniser' => false, 'resynchronisation_complete' => false]);
    }

    public function test_une_demande_pour_tous_est_servie_une_fois_par_poste(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');

        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/postes/synchroniser')->assertOk();

        $this->demande($a)->assertJson(['synchroniser' => true]);
        $this->demande($a)->assertJson(['synchroniser' => false]);   // une seule synchro par demande
        $this->demande($b)->assertJson(['synchroniser' => true]);    // l'autre poste a la sienne
    }

    public function test_une_demande_ciblee_ne_concerne_que_ce_poste(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');

        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/postes/synchroniser', ['device_name' => $a['device']])->assertOk();

        $this->demande($b)->assertJson(['synchroniser' => false]);
        $this->demande($a)->assertJson(['synchroniser' => true]);
    }

    public function test_une_demande_expire_apres_60_minutes(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $a = $this->poste('caissier', 'amina');
        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/postes/synchroniser')->assertOk();

        $this->travel(61)->minutes();

        $this->demande($a)->assertJson(['synchroniser' => false]);
    }

    public function test_seul_un_gestionnaire_demande_une_synchronisation(): void
    {
        $caissier = $this->poste('caissier');
        $this->avecJeton($caissier['jeton'])->postJson('/api/parametres/postes/synchroniser')->assertStatus(403);
        $this->avecJeton($caissier['jeton'])->postJson('/api/parametres/postes/renvoyer', ['device_name' => $caissier['device']])->assertStatus(403);
    }

    public function test_un_poste_revoque_ne_lit_plus_les_demandes(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $b = $this->poste('caissier', 'bako');
        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/postes/revoquer', ['device_name' => $b['device']])->assertOk();

        $this->demande($b)->assertStatus(401);
    }

    // ------------------------------------------------- Resynchronisation

    public function test_le_curseur_n_est_memorise_qu_a_la_derniere_page(): void
    {
        config(['logialvia.sync.lignes_par_page' => 1]);
        $a = $this->poste('caissier', 'amina');
        $autre = $this->poste('caissier', 'bako');
        $this->avecJeton($autre['jeton'])->postJson('/api/sync/push', [
            'device_id' => $autre['device'], 'reset_mark' => 'initiale',
            'tables' => ['clients' => [$this->ligneClient(), $this->ligneClient()]],
        ])->assertOk();

        $p1 = $this->avecJeton($a['jeton'])->getJson('/api/sync/pull')->assertOk()->json();
        $this->assertGreaterThan(1, $p1['last_page']);
        $this->assertNull(Poste::query()->where('device_id', $a['device'])->value('curseur_tirage'));

        $until = urlencode($p1['server_time']);
        $this->avecJeton($a['jeton'])->getJson("/api/sync/pull?page={$p1['last_page']}&until=$until")->assertOk();
        $this->assertNotNull(Poste::query()->where('device_id', $a['device'])->value('curseur_tirage'));
    }

    public function test_renvoyer_vers_un_poste_puis_acquittement(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');

        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/postes/renvoyer', ['device_name' => $a['device']])->assertOk();

        $this->demande($a)->assertJson(['resynchronisation_complete' => true]);
        $this->demande($a)->assertJson(['resynchronisation_complete' => true]); // tant que non acquitte
        $this->demande($b)->assertJson(['resynchronisation_complete' => false]);

        $this->avecJeton($a['jeton'])->postJson('/api/sync/resynchronisation/acquittement')->assertOk();
        $this->demande($a)->assertJson(['resynchronisation_complete' => false]);
    }

    public function test_renvoyer_vers_un_poste_inconnu_est_refuse(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $this->avecJeton($admin['jeton'])
            ->postJson('/api/parametres/postes/renvoyer', ['device_name' => '3dd59ecd-1a56-4ea6-9014-641c14c8bef2'])
            ->assertStatus(404);
    }

    // ------------------------------------------------------- Remise a zero

    private function remettre(array $poste, string $mot)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/parametres/remise-a-zero', ['confirmation' => $mot]);
    }

    private function avecUnClient(array $poste): string
    {
        $ligne = $this->ligneClient();
        $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'], 'reset_mark' => ParametresEntreprise::courant()->fresh()->marque_remise_a_zero,
            'tables' => ['clients' => [$ligne]],
        ])->assertOk();

        return $ligne['id'];
    }

    public function test_la_remise_a_zero_est_desactivee_par_defaut(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $this->avecUnClient($admin);

        $this->remettre($admin, 'REMETTRE A ZERO')->assertStatus(403);

        $this->assertSame(1, Client::query()->count());
    }

    public function test_mauvais_mot_de_confirmation_n_efface_rien(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $admin = $this->poste('admin', 'gerante');
        $this->avecUnClient($admin);

        $this->remettre($admin, 'remettre a zero')->assertStatus(403);

        $this->assertSame(1, Client::query()->count());
        $this->assertDatabaseHas('audit_logs', ['action' => 'sync.remise_a_zero_refusee']);
    }

    public function test_seul_l_administrateur_peut_remettre_a_zero(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $comptable = $this->poste('comptable');
        $this->remettre($comptable, 'REMETTRE A ZERO')->assertStatus(403);
    }

    public function test_remise_a_zero_efface_l_activite_et_garde_comptes_et_referentiels(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $admin = $this->poste('admin', 'gerante');
        $a = $this->poste('caissier', 'amina');
        $this->avecUnClient($a);
        $avant = ParametresEntreprise::courant()->fresh()->marque_remise_a_zero;
        $modules = \App\Models\ModuleActif::query()->count();
        $comptes = \App\Models\User::query()->count();

        $this->remettre($admin, 'REMETTRE A ZERO')->assertOk();

        $this->assertSame(0, Client::query()->count());
        $this->assertSame($modules, \App\Models\ModuleActif::query()->count());
        $this->assertSame($comptes, \App\Models\User::query()->count());
        $this->assertNotSame($avant, ParametresEntreprise::courant()->fresh()->marque_remise_a_zero);
        $this->assertDatabaseHas('audit_logs', ['action' => 'sync.remise_a_zero']);
    }

    public function test_apres_la_remise_a_zero_un_poste_ancien_est_refuse_en_409_puis_repart(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $admin = $this->poste('admin', 'gerante');
        $a = $this->poste('caissier', 'amina');
        $marqueAncienne = ParametresEntreprise::courant()->fresh()->marque_remise_a_zero;
        $this->remettre($admin, 'REMETTRE A ZERO')->assertOk();

        // Saisie d'avant la remise a zero : elle ressusciterait, donc refus net.
        $this->avecJeton($a['jeton'])->postJson('/api/sync/push', [
            'device_id' => $a['device'], 'reset_mark' => $marqueAncienne,
            'tables' => ['clients' => [$this->ligneClient(['nom' => 'Fantome'])]],
        ])->assertStatus(409)->assertJson(['code' => 'remise_a_zero_inconnue']);
        $this->assertSame(0, Client::query()->count());

        // Le tirage lui apprend la nouvelle marque ; il peut alors envoyer.
        $nouvelle = $this->avecJeton($a['jeton'])->getJson('/api/sync/pull')->assertOk()->json('reset_mark');
        $this->assertNotSame($marqueAncienne, $nouvelle);
        $this->avecJeton($a['jeton'])->postJson('/api/sync/push', [
            'device_id' => $a['device'], 'reset_mark' => $nouvelle,
            'tables' => ['clients' => [$this->ligneClient(['nom' => 'Apres'])]],
        ])->assertOk();
        $this->assertSame(1, Client::query()->count());
    }

    public function test_la_remise_a_zero_annule_les_demandes_et_les_curseurs(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $admin = $this->poste('admin', 'gerante');
        $a = $this->poste('caissier', 'amina');
        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/postes/synchroniser')->assertOk();
        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/postes/renvoyer', ['device_name' => $a['device']])->assertOk();

        $this->remettre($admin, 'REMETTRE A ZERO')->assertOk();

        $this->demande($a)->assertJson(['synchroniser' => false, 'resynchronisation_complete' => false]);
    }
}
