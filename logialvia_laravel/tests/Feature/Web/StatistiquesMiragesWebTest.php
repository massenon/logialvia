<?php

namespace Tests\Feature\Web;

use App\Livewire\StatistiquesMirages;
use App\Models\CycleCouveuse;
use App\Models\MachineIncubateur;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Statistiques des Mirages » : lecture seule, taux calcules comme au poste. */
class StatistiquesMiragesWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        $this->travelTo(now('UTC')->setDate(2026, 11, 8)->setTime(10, 0));
    }

    private function utilisateur(string $role, string $username = 'u'): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    private function machine(string $code = 'INC-01'): MachineIncubateur
    {
        $m = (new MachineIncubateur)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'code' => $code,
            'libelle' => 'Couveuse', 'capacite_oeufs' => 500, 'active' => true,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $m->save();

        return $m;
    }

    private function lot(array $surcharge = []): CycleCouveuse
    {
        $l = (new CycleCouveuse)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'code_incubation' => 'C-P1-2026-001',
            'portee_code' => '', 'espece' => 'goliath', 'date_incubation' => '2026-10-20',
            'oeufs_couves' => 100, 'poussins_nes' => null, 'oeufs_perdus' => null, 'statut' => 'En Incubation',
            'machine_id' => null, 'oeufs_blancs_j7' => null, 'oeufs_gates_j14' => null, 'lot_parent_id' => null,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $l->save();

        return $l;
    }

    private function admin()
    {
        return Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(StatistiquesMirages::class);
    }

    /** Un couvoir de trois lots, dont les taux sont calculables a la main (voir les tests). */
    private function couvoir(): array
    {
        $machine = $this->machine();
        $a = $this->lot(['code_incubation' => 'C-P1-2026-001', 'date_incubation' => '2026-09-01', 'oeufs_couves' => 200,
            'oeufs_blancs_j7' => 20, 'oeufs_gates_j14' => 10, 'poussins_nes' => 150, 'oeufs_perdus' => 10,
            'statut' => 'Éclosion Effectuée', 'machine_id' => $machine->id]);
        $b = $this->lot(['code_incubation' => 'C-P1-2026-002', 'espece' => 'pintade', 'date_incubation' => '2026-11-05',
            'oeufs_couves' => 100, 'oeufs_blancs_j7' => 10]);
        $c = $this->lot(['code_incubation' => 'C-P1-2026-003', 'oeufs_couves' => 50, 'machine_id' => $machine->id]);

        return [$a, $b, $c, $machine];
    }

    // ------------------------------------------------------------------- Acces

    public function test_visiteur_caissier_et_comptable_n_ouvrent_pas_la_page(): void
    {
        $this->get('/elevage/mirages')->assertRedirect(route('login'));
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get('/elevage/mirages')->assertForbidden();
        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/elevage/mirages')->assertForbidden();
    }

    public function test_l_animalier_et_l_administrateur_l_ouvrent_et_c_est_bien_l_ecran_converti(): void
    {
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/elevage/mirages')->assertOk()
            ->assertSee('Statistiques des Mirages')->assertDontSee('arrive bientôt');
        $this->actingAs($this->utilisateur('admin', 'gerante'))->get('/elevage/mirages')->assertOk();
    }

    // ----------------------------------------------------------------- Lecture

    public function test_les_kpis_sont_ceux_du_poste(): void
    {
        $this->couvoir();

        $this->admin()
            ->assertSeeHtml('data-kpi="charges">350<')->assertSee('3 lot(s)')
            ->assertSeeHtml('data-kpi="clairs">30<')
            // Infertilité : 30 clairs sur les 300 œufs des lots dont le mirage 1 est fait.
            ->assertSee('Infertilité 10,0 % — reproducteurs')
            ->assertSeeHtml('data-kpi="gates">10<')
            // Mortalité : 10 gâtés sur les 180 œufs présents au second mirage du seul lot mirée.
            ->assertSee('Mortalité embryonnaire 5,6 % — conduite')
            ->assertSeeHtml('data-kpi="retenus">310<')
            // TER : 150 éclos sur les 170 retenus du seul lot éclos.
            ->assertSeeHtml('data-kpi="ter">88,2 %<')
            // Perte : (200 − 150) / 200 sur les lots clôturés seulement.
            ->assertSeeHtml('data-kpi="perte">25,0 %<');
    }

    public function test_le_detail_par_lot_distingue_non_mire_de_zero(): void
    {
        $this->couvoir();
        $this->lot(['code_incubation' => 'C-P1-2026-004', 'oeufs_couves' => 80, 'oeufs_blancs_j7' => 0]);

        $this->admin()
            ->assertSeeHtml('data-lot="C-P1-2026-001"')
            ->assertSee('20  (10,0 %)')       // clairs du lot éclos
            ->assertSee('10  (5,6 %)')        // gâtés / œufs présents au second mirage
            ->assertSee('Non mirés')          // mirage 2 du lot B, mirages du lot C
            ->assertSee('0  (0,0 %)')         // mirage fait, zéro œuf clair : pas « Non mirés »
            ->assertSee('88,2 %')->assertSee('25,0 %')
            ->assertSee('Goliath')->assertSee('Pintade');
    }

    public function test_un_lot_dont_tout_a_ete_retire_n_a_pas_de_taux(): void
    {
        $this->lot(['oeufs_couves' => 100, 'oeufs_blancs_j7' => 60, 'oeufs_gates_j14' => 40, 'poussins_nes' => 0, 'statut' => 'Éclosion Effectuée']);

        $this->admin()->assertSeeHtml('data-kpi="ter">—<');
    }

    public function test_les_mirages_manquants_sont_signales_avec_leurs_codes(): void
    {
        $this->couvoir();

        $this->admin()->assertSeeHtml('data-bloc="manquants"')
            ->assertSee('1 lot(s) attendent un mirage échu : C-P1-2026-003.')
            ->assertSee('un mirage oublié gonfle le dénominateur du TER', false);
    }

    public function test_aucun_bandeau_quand_aucun_mirage_n_est_du(): void
    {
        $this->lot(['date_incubation' => '2026-11-06']);

        $this->admin()->assertDontSeeHtml('data-bloc="manquants"');
    }

    public function test_les_filtres_espece_et_incubateur_recalculent_les_kpis(): void
    {
        [, , , $machine] = $this->couvoir();

        $c = $this->admin();
        $c->set('filtreEspece', 'pintade')->assertSeeHtml('data-kpi="charges">100<')->assertSeeHtml('data-kpi="ter">—<')
            ->assertSeeHtml('data-lot="C-P1-2026-002"')->assertDontSeeHtml('data-lot="C-P1-2026-001"');
        $c->set('filtreEspece', '')->set('filtreMachine', $machine->id)
            ->assertSeeHtml('data-kpi="charges">250<')->assertSeeHtml('data-lot="C-P1-2026-003"')
            ->assertDontSeeHtml('data-lot="C-P1-2026-002"');
    }

    public function test_un_lot_supprime_n_entre_dans_aucun_taux(): void
    {
        $this->lot(['oeufs_couves' => 100, 'supprime_le' => now()]);

        $this->admin()->assertSeeHtml('data-kpi="charges">0<')
            ->assertSee('Aucun lot d\'incubation ne correspond à ces filtres.', false);
    }

    public function test_la_vue_cartes_existe_pour_les_petits_ecrans(): void
    {
        $this->couvoir();

        $this->admin()->assertSeeHtml('data-vue="cartes"')->assertSeeHtml('data-carte-lot="C-P1-2026-001"');
    }

    // ------------------------------------------------------------- Lecture seule

    public function test_l_ecran_n_ecrit_jamais_rien(): void
    {
        $this->couvoir();
        $avant = CycleCouveuse::query()->orderBy('code_incubation')->get()->map->getAttributes()->all();

        $c = $this->admin();
        $c->set('filtreEspece', 'goliath')->set('filtreMachine', '');

        $this->assertSame($avant, CycleCouveuse::query()->orderBy('code_incubation')->get()->map->getAttributes()->all());
        $this->assertFalse(method_exists(StatistiquesMirages::class, 'enregistrerMirage'));
        $c->assertDontSeeHtml('wire:click');
    }
}
