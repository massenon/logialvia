<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\Couveuse;
use App\Models\Client;
use App\Models\CycleCouveuse;
use App\Models\MachineIncubateur;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ecran web « Cycle Couveuse » : lots et incubateurs sont des faits (dernier ecrivain gagne),
 * les mirages deux colonnes du lot, la suppression une pierre tombale. Aucun effet de bord.
 */
class CouveuseWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        // Un 8 novembre : les calendriers des lots ci-dessous sont deterministes.
        $this->travelTo(now('UTC')->setDate(2026, 11, 8)->setTime(10, 0));
    }

    private function utilisateur(string $role, string $username = 'u'): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    private function machine(array $surcharge = []): MachineIncubateur
    {
        $m = (new MachineIncubateur)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'code' => 'INC-01',
            'libelle' => 'Couveuse atelier', 'capacite_oeufs' => 528, 'active' => true,
            'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ], $surcharge));
        $m->save();

        return $m;
    }

    private function lot(array $surcharge = []): CycleCouveuse
    {
        $l = (new CycleCouveuse)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'code_incubation' => 'C-P1-2026-001',
            'portee_code' => '', 'espece' => 'goliath', 'date_incubation' => '2026-10-20',
            'oeufs_couves' => 200, 'poussins_nes' => null, 'oeufs_perdus' => null, 'statut' => 'En Incubation',
            'machine_id' => null, 'oeufs_blancs_j7' => null, 'oeufs_gates_j14' => null, 'lot_parent_id' => null,
            'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ], $surcharge));
        $l->save();

        return $l;
    }

    private function composant(User $u, string $classe = Couveuse::class)
    {
        return Livewire::actingAs($u)->test($classe);
    }

    private function admin()
    {
        return $this->composant($this->utilisateur('admin', 'gerante'));
    }

    // ------------------------------------------------------------------- Acces

    public function test_visiteur_caissier_et_comptable_n_ouvrent_pas_la_page(): void
    {
        $this->get('/elevage/couveuse')->assertRedirect(route('login'));
        $this->get('/elevage/mirages')->assertRedirect(route('login'));
        foreach (['/elevage/couveuse', '/elevage/mirages'] as $route) {
            $this->actingAs($this->utilisateur('caissier', 'amina'.Str::random(3)))->get($route)->assertForbidden();
            $this->actingAs($this->utilisateur('comptable', 'compta'.Str::random(3)))->get($route)->assertForbidden();
        }
    }

    public function test_l_animalier_et_l_administrateur_l_ouvrent_et_c_est_bien_l_ecran_converti(): void
    {
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/elevage/couveuse')->assertOk()
            ->assertSee('Cycle Couveuse')->assertDontSee('arrive bientôt');
        $this->actingAs($this->utilisateur('admin', 'gerante'))->get('/elevage/couveuse')->assertOk();
    }

    // ----------------------------------------------------------------- Lecture

    public function test_les_kpis_viennent_de_la_base(): void
    {
        $machine = $this->machine();
        // Lot clos : 200 charges, 20 clairs, 10 gates, 150 eclos -> retenus 170, TER 88,2 %, brut 75,0 %.
        $this->lot(['code_incubation' => 'C-P1-2026-001', 'date_incubation' => '2026-09-01', 'machine_id' => $machine->id,
            'oeufs_blancs_j7' => 20, 'oeufs_gates_j14' => 10, 'poussins_nes' => 150, 'oeufs_perdus' => 10, 'statut' => 'Éclosion Effectuée']);
        // Lot en cours : 100 charges, 10 clairs -> 90 retenus en incubation.
        $this->lot(['code_incubation' => 'C-P1-2026-002', 'machine_id' => $machine->id, 'oeufs_couves' => 100, 'oeufs_blancs_j7' => 10]);

        $this->admin()
            ->assertSeeHtml('data-kpi="en-cours">1<')
            ->assertSeeHtml('data-kpi="oeufs">90<')
            ->assertSeeHtml('data-kpi="reel">88,2 %<')
            ->assertSeeHtml('data-kpi="brut">75,0 %<')
            // 100 œufs en cours × 75 % de taux brut moyen.
            ->assertSeeHtml('data-kpi="attendus">75<')
            ->assertSee('1 incubateur(s)');
    }

    public function test_sans_eclosion_les_taux_sont_des_tirets_et_aucune_projection(): void
    {
        $this->lot();

        $this->admin()
            ->assertSeeHtml('data-kpi="reel">—<')
            ->assertSeeHtml('data-kpi="brut">—<')
            ->assertSeeHtml('data-kpi="attendus">—<')
            ->assertSee('Nécessite au moins une éclosion enregistrée');
    }

    public function test_le_parc_calcule_l_occupation_et_signale_une_surcharge(): void
    {
        $a = $this->machine(['code' => 'INC-01', 'capacite_oeufs' => 528]);
        $b = $this->machine(['code' => 'INC-02', 'capacite_oeufs' => 100, 'libelle' => 'Annexe']);
        $c = $this->machine(['code' => 'INC-03', 'capacite_oeufs' => null, 'libelle' => 'Sans capacité']);
        $this->lot(['code_incubation' => 'C-P1-2026-001', 'machine_id' => $a->id, 'oeufs_couves' => 200, 'oeufs_blancs_j7' => 20]);
        $this->lot(['code_incubation' => 'C-P1-2026-002', 'machine_id' => $b->id, 'oeufs_couves' => 250]);
        $this->lot(['code_incubation' => 'C-P1-2026-003', 'machine_id' => $c->id, 'oeufs_couves' => 40]);
        // Un lot clos n'occupe plus la machine.
        $this->lot(['code_incubation' => 'C-P1-2026-004', 'machine_id' => $a->id, 'oeufs_couves' => 300, 'poussins_nes' => 200, 'statut' => 'Éclosion Effectuée']);

        $this->admin()
            ->assertSeeHtmlInOrder(['data-machine="INC-01"', '180 / 528 œufs', '34,1 % de la capacité'])
            ->assertSee('250 / 100 œufs')->assertSee('Capacité annoncée dépassée')
            ->assertSee('40 œufs en incubation')->assertSee('Capacité non renseignée');
    }

    public function test_le_tableau_montre_les_lots_avec_leurs_mirages_leur_machine_et_leur_lignee(): void
    {
        $machine = $this->machine();
        $parent = $this->lot(['code_incubation' => 'C-P1-2026-001', 'date_incubation' => '2026-09-01', 'machine_id' => $machine->id,
            'statut' => 'Remplacé', 'poussins_nes' => 150, 'oeufs_blancs_j7' => 20, 'oeufs_gates_j14' => 10]);
        $this->lot(['code_incubation' => 'C-P1-2026-002', 'lot_parent_id' => $parent->id, 'machine_id' => $machine->id,
            'date_incubation' => '2026-11-05', 'oeufs_couves' => 90]);

        $this->admin()
            ->assertSee('C-P1-2026-001')->assertSee('C-P1-2026-002')
            ->assertSee('↳ remplace C-P1-2026-001')
            ->assertSee('INC-01')
            ->assertSee('20 retirés')->assertSee('10 retirés')
            ->assertSee('Remplacé')->assertSee('En Incubation')
            // Le sous-lot (chargé le 5/11) : âge J+3, mirage 1 prévu le 12/11, éclosion le 26/11.
            ->assertSee('J+3')->assertSee('12/11/2026')->assertSee('26/11/2026');
    }

    public function test_un_mirage_du_est_a_saisir_et_un_mirage_a_zero_est_distinct_de_non_mire(): void
    {
        // Charge le 20/10 : mirage 1 le 27/10 (du), mirage 2 le 03/11 (du).
        $this->lot(['code_incubation' => 'C-P1-2026-001', 'oeufs_blancs_j7' => 0]);
        // Charge le 05/11 : aucun mirage du (mirage 1 le 12/11).
        $this->lot(['code_incubation' => 'C-P1-2026-002', 'date_incubation' => '2026-11-05']);

        $this->admin()
            ->assertSee('0 retiré')       // mirage fait, zéro œuf clair : ce n'est pas « À saisir »
            ->assertSee('À saisir')       // le mirage 2 du premier lot
            ->assertSee('12/11/2026');
    }

    public function test_alertes_et_prochaines_echeances_suivent_la_date_de_reference(): void
    {
        // Charge le 20/10 : mirage 1 le 27/10, mirage 2 le 03/11, eclosion le 10/11 (J+21).
        $this->lot(['code_incubation' => 'C-P1-2026-001']);

        $composant = $this->admin()
            ->assertSeeHtml('data-bloc="a-venir"')   // l'éclosion du 10/11 est dans les 3 jours
            ->assertSee('Éclosion — Relève des poussins')
            ->assertSeeHtml('data-bloc="alertes"')
            ->assertSee('2 échéance(s) du couvoir, dont 2 en retard')
            ->assertSee('Mirage 1 — Retrait des œufs clairs')
            ->assertSee('depuis 12 j');

        // « Situation au » 24/10 : rien n'est encore dû.
        $composant->set('reference', '2026-10-24')
            ->assertDontSeeHtml('data-bloc="alertes"')
            ->assertSee('Revenir à aujourd\'hui', false);
        $composant->call('aujourdhui')->assertSeeHtml('data-bloc="alertes"');
    }

    public function test_les_filtres_statut_espece_et_machine(): void
    {
        $m = $this->machine();
        $this->lot(['code_incubation' => 'C-P1-2026-001', 'machine_id' => $m->id]);
        $this->lot(['code_incubation' => 'C-P1-2026-002', 'espece' => 'pintade']);
        $this->lot(['code_incubation' => 'C-P1-2026-003', 'poussins_nes' => 90, 'statut' => 'Éclosion Effectuée']);

        $c = $this->admin();
        $c->set('filtreStatut', 'en_cours')->assertSeeHtml('data-lot="C-P1-2026-001"')->assertDontSeeHtml('data-lot="C-P1-2026-003"');
        $c->set('filtreStatut', 'eclos')->assertSeeHtml('data-lot="C-P1-2026-003"')->assertDontSeeHtml('data-lot="C-P1-2026-001"');
        $c->set('filtreStatut', '')->set('filtreEspece', 'pintade')->assertSeeHtml('data-lot="C-P1-2026-002"')->assertDontSeeHtml('data-lot="C-P1-2026-001"');
        $c->set('filtreEspece', '')->set('filtreMachine', $m->id)->assertSeeHtml('data-lot="C-P1-2026-001"')->assertDontSeeHtml('data-lot="C-P1-2026-002"');
    }

    public function test_un_lot_supprime_n_est_pas_affiche_et_le_vide_est_dit(): void
    {
        $this->lot(['code_incubation' => 'C-P1-2026-009', 'supprime_le' => now()]);

        $this->admin()->assertDontSee('C-P1-2026-009')
            ->assertSee('Aucun cycle d\'incubation enregistré', false)
            ->assertSee('Aucun incubateur déclaré');
    }

    public function test_la_vue_cartes_existe_pour_les_petits_ecrans(): void
    {
        $this->lot(['code_incubation' => 'C-P1-2026-001']);

        $this->admin()->assertSeeHtml('data-vue="cartes"')->assertSeeHtml('data-carte-lot="C-P1-2026-001"');
    }

    // ------------------------------------------------------- Declarer un cycle

    public function test_declarer_un_cycle_ecrit_un_lot_par_le_chemin_du_poste(): void
    {
        $machine = $this->machine();
        $avant = now()->subMinute();

        $this->admin()->call('nouveauLot')
            ->set('espece', 'goliath')->set('dateChargement', '2026-11-08')->set('machineId', $machine->id)->set('oeufs', '200')
            ->assertSee('Mirage 1 le 15/11/2026')->assertSee('Éclosion prévue le 29/11/2026')
            ->call('enregistrerLot')->assertSet('formulaireLot', false)->assertSee('Cycle enregistré avec succès.');

        $lot = CycleCouveuse::query()->sole();
        $this->assertSame('C-WEB-2026-001', $lot->code_incubation);
        $this->assertSame(Catalogue::POSTE_WEB, $lot->device_id);
        $this->assertSame('En Incubation', $lot->statut);
        $this->assertSame(200, $lot->oeufs_couves);
        $this->assertSame($machine->id, $lot->machine_id);
        $this->assertNull($lot->oeufs_blancs_j7);
        $this->assertTrue($lot->serveur_modifie_le->greaterThan($avant), 'le curseur de tirage avance');
        $this->assertSame(Catalogue::POSTE_WEB, $lot->portee_code, 'code web : unique parmi les lots du web');
    }

    public function test_les_codes_du_web_se_suivent_et_ne_collisionnent_pas_avec_ceux_des_postes(): void
    {
        $this->lot(['code_incubation' => 'C-P1-2026-001']);
        $c = $this->admin();

        foreach (['2026-11-01', '2026-11-02'] as $date) {
            $c->call('nouveauLot')->set('espece', 'pintade')->set('dateChargement', $date)->set('oeufs', '50')->call('enregistrerLot');
        }

        $this->assertSame(['C-P1-2026-001', 'C-WEB-2026-001', 'C-WEB-2026-002'], CycleCouveuse::query()->orderBy('code_incubation')->pluck('code_incubation')->all());
    }

    public static function creationsInvalides(): array
    {
        return [
            'sans espèce' => [['espece' => ''], "L'espèce est obligatoire."],
            'sans date' => [['dateChargement' => ''], 'La date est obligatoire.'],
            'sans œufs' => [['oeufs' => ''], "Le nombre d'œufs est obligatoire."],
            'zéro œuf' => [['oeufs' => '0'], "Le nombre d'œufs est obligatoire."],
            'œufs en texte' => [['oeufs' => 'abc'], "Le nombre d'œufs est obligatoire."],
            'incubateur inconnu' => [['machineId' => 'cccccccc-0000-4000-8000-000000000001'], 'Incubateur inconnu du serveur.'],
        ];
    }

    /** @dataProvider creationsInvalides */
    public function test_une_creation_invalide_montre_son_message_et_n_ecrit_rien(array $surcharge, string $message): void
    {
        $saisie = array_merge(['espece' => 'goliath', 'dateChargement' => '2026-11-08', 'oeufs' => '100', 'machineId' => ''], $surcharge);
        $c = $this->admin()->call('nouveauLot');
        foreach ($saisie as $cle => $valeur) {
            $c->set($cle, $valeur);
        }

        $c->call('enregistrerLot')->assertSee($message)->assertSet('formulaireLot', true);

        $this->assertSame(0, CycleCouveuse::query()->count());
    }

    // ------------------------------------------------------------------ Modifier

    public function test_modifier_un_cycle_en_cours_change_le_lot_et_son_instant_de_saisie(): void
    {
        $lot = $this->lot(['oeufs_couves' => 200]);

        $this->admin()->call('modifierLot', $lot->id)
            ->assertSet('oeufs', '200')->assertSet('espece', 'goliath')
            ->set('espece', 'pintade')->set('oeufs', '180')->set('dateChargement', '2026-10-21')
            ->call('enregistrerLot')->assertSee('Cycle C-P1-2026-001 modifié.');

        $lot->refresh();
        $this->assertSame('pintade', $lot->espece);
        $this->assertSame(180, $lot->oeufs_couves);
        $this->assertSame('2026-10-21', $lot->date_incubation->format('Y-m-d'));
        $this->assertSame('C-P1-2026-001', $lot->code_incubation, 'le code ne change jamais');
        $this->assertSame(Catalogue::POSTE_WEB, $lot->device_id);
    }

    public function test_un_cycle_eclos_ne_se_modifie_plus(): void
    {
        $lot = $this->lot(['statut' => 'Éclosion Effectuée', 'poussins_nes' => 150]);

        $this->admin()->call('modifierLot', $lot->id)->set('espece', 'goliath')->set('dateChargement', '2026-10-20')->set('oeufs', '10')
            ->call('enregistrerLot')
            ->assertSee('Un cycle éclos ne peut plus être modifié : son taux d\'éclosion est déjà entré dans les statistiques.');

        $this->assertSame(200, $lot->fresh()->oeufs_couves);
    }

    public function test_non_precise_ne_retire_pas_l_incubateur_d_un_lot_comme_au_poste(): void
    {
        $machine = $this->machine();
        $lot = $this->lot(['machine_id' => $machine->id]);

        $this->admin()->call('modifierLot', $lot->id)->set('machineId', '')->call('enregistrerLot');

        $this->assertSame($machine->id, $lot->fresh()->machine_id);
    }

    public function test_une_saisie_du_web_l_emporte_meme_sur_un_poste_dont_l_horloge_avance(): void
    {
        // Le poste a daté sa saisie dans une heure : « dernier écrivain gagne » exige un instant
        // strictement postérieur, sinon la saisie du web serait ignorée sans le dire.
        $lot = $this->lot(['oeufs_couves' => 200, 'updated_at' => now()->addHour()]);

        $this->admin()->call('modifierLot', $lot->id)->set('oeufs', '150')->call('enregistrerLot');

        $this->assertSame(150, $lot->fresh()->oeufs_couves);
    }

    // -------------------------------------------------------------------- Mirage

    public function test_saisir_le_premier_puis_le_second_mirage(): void
    {
        $lot = $this->lot(['oeufs_couves' => 200]);

        $c = $this->admin()->call('ouvrirMirage', $lot->id, 7)
            ->assertSee('Mirage 1 (J+7) — C-P1-2026-001')->assertSee('échéance le 27/10/2026')
            ->set('mirageRetires', '22')->call('enregistrerMirage')->assertSee('Mirage enregistré sur C-P1-2026-001.');
        $this->assertSame(22, $lot->fresh()->oeufs_blancs_j7);
        $this->assertNull($lot->fresh()->oeufs_gates_j14, 'le second mirage n\'est pas fait');

        $c->call('ouvrirMirage', $lot->id, 14)->assertSee('Mirage 2 (J+14)')
            ->set('mirageRetires', '0')->call('enregistrerMirage');
        $this->assertSame(0, $lot->fresh()->oeufs_gates_j14, 'mirage fait, zéro œuf gâté');
    }

    public function test_un_mirage_se_corrige_et_la_valeur_precedente_est_proposee(): void
    {
        $lot = $this->lot(['oeufs_blancs_j7' => 22]);

        $this->admin()->call('ouvrirMirage', $lot->id, 7)->assertSet('mirageRetires', '22')
            ->set('mirageRetires', '25')->call('enregistrerMirage');

        $this->assertSame(25, $lot->fresh()->oeufs_blancs_j7);
    }

    public function test_les_validations_du_mirage(): void
    {
        $lot = $this->lot(['oeufs_couves' => 100, 'oeufs_gates_j14' => 30]);

        $c = $this->admin()->call('ouvrirMirage', $lot->id, 7);
        $c->set('mirageRetires', '')->call('enregistrerMirage')->assertSee('Le nombre d\'œufs retirés est obligatoire.');
        $c->set('mirageRetires', '71')->call('enregistrerMirage')
            ->assertSee('Ce lot ne contient que 100 œufs, dont 30 déjà retirés : impossible d\'en retirer 71 de plus.');
        $c->set('mirageRetires', '70')->call('enregistrerMirage')->assertDontSee('impossible d\'en retirer');
        $this->assertSame(70, $lot->fresh()->oeufs_blancs_j7, 'la borne exacte est acceptée');
    }

    public function test_un_lot_clos_n_accepte_plus_de_mirage(): void
    {
        $lot = $this->lot(['statut' => 'Éclosion Effectuée', 'poussins_nes' => 100]);

        $this->admin()->call('ouvrirMirage', $lot->id, 7)->set('mirageRetires', '5')->call('enregistrerMirage')
            ->assertSee('Ce lot est clôturé : ses mirages ne peuvent plus être saisis.');

        $this->assertNull($lot->fresh()->oeufs_blancs_j7);
    }

    public function test_un_jour_de_mirage_inconnu_est_refuse(): void
    {
        $lot = $this->lot();

        $this->admin()->call('ouvrirMirage', $lot->id, 9)->set('mirageRetires', '5')->call('enregistrerMirage')
            ->assertSee('Le mirage se fait à J+7 ou à J+14.');

        $this->assertNull($lot->fresh()->oeufs_blancs_j7);
    }

    // ------------------------------------------------------------------ Eclosion

    public function test_enregistrer_une_eclosion_cloture_le_lot(): void
    {
        $lot = $this->lot(['oeufs_couves' => 200, 'oeufs_blancs_j7' => 20, 'oeufs_gates_j14' => 10]);

        $this->admin()->call('ouvrirEclosion', $lot->id)
            ->assertSee('Enregistrer l\'Éclosion — C-P1-2026-001', false)->assertSee('encore en incubation : 170')
            ->set('poussins', '150')->set('perdus', '10')->call('enregistrerEclosion')
            ->assertSee('Éclosion du cycle C-P1-2026-001 enregistrée.');

        $lot->refresh();
        $this->assertSame('Éclosion Effectuée', $lot->statut);
        $this->assertSame(150, $lot->poussins_nes);
        $this->assertSame(10, $lot->oeufs_perdus);
        $this->assertSame(1, CycleCouveuse::query()->count(), 'pas de remplacement : pas de sous-lot');
    }

    public function test_une_eclosion_avec_remplacement_cree_un_sous_lot_dans_la_meme_machine(): void
    {
        $machine = $this->machine();
        $lot = $this->lot(['oeufs_couves' => 200, 'machine_id' => $machine->id]);

        $this->admin()->call('ouvrirEclosion', $lot->id)
            ->set('poussins', '150')->set('perdus', '20')
            ->set('remplacer', true)->set('remplacementOeufs', '180')->set('remplacementEspece', 'pintade')->set('remplacementDate', '2026-11-08')
            ->assertSee('Enregistrer et Remplacer')
            ->call('enregistrerEclosion');

        $this->assertSame('Remplacé', $lot->fresh()->statut);
        $enfant = CycleCouveuse::query()->where('lot_parent_id', $lot->id)->sole();
        $this->assertSame('C-WEB-2026-001', $enfant->code_incubation);
        $this->assertSame('pintade', $enfant->espece);
        $this->assertSame(180, $enfant->oeufs_couves);
        $this->assertSame('2026-11-08', $enfant->date_incubation->format('Y-m-d'));
        $this->assertSame($machine->id, $enfant->machine_id, 'la place reste la même');
        $this->assertSame('En Incubation', $enfant->statut);
    }

    public function test_remplacer_sans_quantite_ne_cree_rien_et_le_lot_est_simplement_eclos(): void
    {
        $lot = $this->lot();

        $this->admin()->call('ouvrirEclosion', $lot->id)->set('poussins', '100')->set('remplacer', true)->set('remplacementOeufs', '0')
            ->call('enregistrerEclosion');

        $this->assertSame('Éclosion Effectuée', $lot->fresh()->statut);
        $this->assertSame(1, CycleCouveuse::query()->count());
    }

    public static function eclosionsInvalides(): array
    {
        return [
            'quantité négative' => [['poussins' => '-5'], 'Les quantités ne peuvent être négatives.'],
            'perdus négatifs' => [['perdus' => '-1'], 'Les quantités ne peuvent être négatives.'],
            'au-delà des retenus' => [['poussins' => '150', 'perdus' => '21'], 'Poussins éclos + œufs perdus (171) dépasse les 170 œufs encore en incubation après les mirages.'],
            'espèce de remplacement inconnue' => [['poussins' => '10', 'remplacer' => true, 'remplacementOeufs' => '5', 'remplacementEspece' => 'autruche'], 'L\'espèce du remplacement est obligatoire.'],
            'date de remplacement absente' => [['poussins' => '10', 'remplacer' => true, 'remplacementOeufs' => '5', 'remplacementDate' => ''], 'La date d\'insertion est obligatoire.'],
        ];
    }

    /** @dataProvider eclosionsInvalides */
    public function test_une_eclosion_invalide_montre_son_message_et_ne_change_rien(array $saisie, string $message): void
    {
        $lot = $this->lot(['oeufs_couves' => 200, 'oeufs_blancs_j7' => 20, 'oeufs_gates_j14' => 10]);
        $c = $this->admin()->call('ouvrirEclosion', $lot->id);
        foreach ($saisie as $cle => $valeur) {
            $c->set($cle, $valeur);
        }

        $c->call('enregistrerEclosion')->assertSee($message);

        $this->assertSame('En Incubation', $lot->fresh()->statut);
        $this->assertNull($lot->fresh()->poussins_nes);
        $this->assertSame(1, CycleCouveuse::query()->count());
    }

    public function test_un_lot_deja_clos_ne_peut_pas_eclore_deux_fois(): void
    {
        $lot = $this->lot(['statut' => 'Éclosion Effectuée', 'poussins_nes' => 100]);

        $this->admin()->call('ouvrirEclosion', $lot->id)->set('poussins', '1')->call('enregistrerEclosion')->assertSee('Ce lot est déjà clôturé.');

        $this->assertSame(100, $lot->fresh()->poussins_nes);
    }

    // --------------------------------------------------------------- Suppression

    public function test_supprimer_un_cycle_pose_la_pierre_tombale_et_detache_ses_sous_lots(): void
    {
        $parent = $this->lot(['code_incubation' => 'C-P1-2026-001']);
        $enfant = $this->lot(['code_incubation' => 'C-P1-2026-002', 'lot_parent_id' => $parent->id]);

        $this->admin()->call('demanderSuppression', $parent->id)
            ->assertSee('Supprimer le cycle C-P1-2026-001 ?')->assertSee('Le lot disparaît du couvoir de tous les postes.')
            ->call('confirmerSuppression')->assertSee('Cycle C-P1-2026-001 supprimé.')->assertDontSeeHtml('data-lot="C-P1-2026-001"');

        $this->assertNotNull($parent->fresh()->supprime_le, 'jamais d\'effacement physique');
        $this->assertNull($enfant->fresh()->lot_parent_id, 'les œufs du sous-lot sont bien réels');
        $this->assertNull($enfant->fresh()->supprime_le);
        $this->assertTrue($enfant->fresh()->serveur_modifie_le->greaterThan(now()->subMinute()), 'le sous-lot modifié redescend vers les postes');
    }

    public function test_un_cycle_eclos_ne_se_supprime_pas(): void
    {
        $lot = $this->lot(['statut' => 'Éclosion Effectuée', 'poussins_nes' => 100]);

        $this->admin()->call('demanderSuppression', $lot->id)
            ->assertSee('Un cycle éclos ne peut pas être supprimé : ses poussins sont déjà entrés dans les effectifs de la filière.')
            ->assertSet('aSupprimer', null);

        $this->assertNull($lot->fresh()->supprime_le);
    }

    public function test_une_confirmation_forcee_sur_un_cycle_eclos_ne_supprime_rien(): void
    {
        // `aSupprimer` est une propriété publique : un client peut la forcer sans passer par la demande.
        $lot = $this->lot(['statut' => 'Éclosion Effectuée', 'poussins_nes' => 100]);

        $this->admin()->set('aSupprimer', $lot->id)->call('confirmerSuppression')
            ->assertSee('Un cycle éclos ne peut pas être supprimé');

        $this->assertNull($lot->fresh()->supprime_le);
    }

    public function test_annuler_la_suppression_ne_supprime_rien(): void
    {
        $lot = $this->lot();

        $this->admin()->call('demanderSuppression', $lot->id)->call('annuler')->call('confirmerSuppression');

        $this->assertNull($lot->fresh()->supprime_le);
    }

    // ---------------------------------------------------------------- Incubateur

    public function test_ajouter_un_incubateur_avec_l_identite_du_poste(): void
    {
        $this->admin()->call('nouvelIncubateur')
            ->set('machineCode', 'INC-01')->set('machineLibelle', 'Couveuse 528 œufs')->set('machineCapacite', '528')
            ->call('enregistrerIncubateur')->assertSee('Incubateur INC-01 enregistré.');

        $m = MachineIncubateur::query()->sole();
        // Même UUID que `uuidDeterministe('machine:inc-01')` du poste : « INC-01 » est le même
        // incubateur partout.
        $this->assertSame('ef7bcd40-7c36-5786-992e-94f3a9b0dc0f', $m->id);
        $this->assertSame('INC-01', $m->code);
        $this->assertSame(528, $m->capacite_oeufs);
        $this->assertTrue($m->active);
        $this->assertSame(Catalogue::POSTE_WEB, $m->device_id);
    }

    public static function incubateursInvalides(): array
    {
        return [
            'sans code' => [['machineCode' => ' '], 'Le code est obligatoire.'],
            'sans libellé' => [['machineLibelle' => ''], 'Le libellé est obligatoire.'],
            'doublon (casse ignorée)' => [['machineCode' => 'inc-01'], 'Un incubateur porte déjà le code inc-01.'],
            'capacité nulle' => [['machineCapacite' => '0'], 'La capacité doit être supérieure à 0.'],
            'capacité en texte' => [['machineCapacite' => '5x'], 'La capacité doit être supérieure à 0.'],
        ];
    }

    /** @dataProvider incubateursInvalides */
    public function test_un_incubateur_invalide_montre_son_message(array $surcharge, string $message): void
    {
        $this->machine(['code' => 'INC-01']);
        $saisie = array_merge(['machineCode' => 'INC-09', 'machineLibelle' => 'Annexe', 'machineCapacite' => ''], $surcharge);
        $c = $this->admin()->call('nouvelIncubateur');
        foreach ($saisie as $cle => $valeur) {
            $c->set($cle, $valeur);
        }

        $c->call('enregistrerIncubateur')->assertSee($message);

        $this->assertSame(1, MachineIncubateur::query()->count());
    }

    public function test_redeclarer_un_incubateur_existant_ne_le_modifie_pas_en_silence(): void
    {
        // Même code = même UUID : sans le contrôle de l'écran, la « création » serait une
        // modification silencieuse (dernier écrivain gagne) de l'incubateur existant.
        $existant = $this->machine(['id' => Couveuse::uuidDeCode('INC-01'), 'code' => 'INC-01', 'libelle' => 'Couveuse atelier', 'capacite_oeufs' => 528]);

        $this->admin()->call('nouvelIncubateur')
            ->set('machineCode', 'inc-01')->set('machineLibelle', 'Autre libellé')->set('machineCapacite', '10')
            ->call('enregistrerIncubateur')->assertSee('Un incubateur porte déjà le code inc-01.');

        $this->assertSame('Couveuse atelier', $existant->fresh()->libelle);
        $this->assertSame(528, $existant->fresh()->capacite_oeufs);
        $this->assertSame('INC-01', $existant->fresh()->code);
    }

    // -------------------------------------------------------------------- Droits

    public function test_un_compte_qui_ne_peut_que_lire_ne_voit_aucun_bouton(): void
    {
        $lecteur = User::factory()->create(['username' => 'lecteur', 'name' => 'Lecteur']);
        $lecteur->givePermissionTo('view-elevage');
        $this->machine();
        $this->lot();

        $this->composant($lecteur)
            ->assertSee('C-P1-2026-001')
            ->assertDontSee('Déclarer un Nouveau Cycle')->assertDontSee('Ajouter un Incubateur')
            ->assertDontSee('Éclosion</button>', false)->assertDontSee('Supprimer</button>', false)->assertDontSeeHtml('wire:click="ouvrirMirage');
    }

    public function test_chaque_methode_qui_ecrit_refuse_un_compte_sans_manage_elevage(): void
    {
        $lecteur = User::factory()->create(['username' => 'lecteur', 'name' => 'Lecteur']);
        $lecteur->givePermissionTo('view-elevage');
        $lot = $this->lot();

        $appels = [
            ['nouveauLot', []], ['modifierLot', [$lot->id]], ['enregistrerLot', []],
            ['ouvrirMirage', [$lot->id, 7]], ['enregistrerMirage', []],
            ['ouvrirEclosion', [$lot->id]], ['enregistrerEclosion', []],
            ['demanderSuppression', [$lot->id]], ['confirmerSuppression', []],
            ['nouvelIncubateur', []], ['enregistrerIncubateur', []],
        ];
        foreach ($appels as [$methode, $arguments]) {
            // Un composant neuf par appel : une exception laisse le composant inutilisable.
            $this->composant($lecteur)->call($methode, ...$arguments)->assertForbidden();
        }

        $this->assertNull($lot->fresh()->supprime_le);
        $this->assertSame(0, MachineIncubateur::query()->count());
    }

    // ------------------------------------------------- Ce que le web n'invente pas

    public function test_aucune_donnee_d_un_autre_domaine_n_est_ecrite(): void
    {
        $lot = $this->lot(['oeufs_couves' => 200]);

        $this->admin()->call('ouvrirEclosion', $lot->id)->set('poussins', '100')->call('enregistrerEclosion');

        $this->assertSame(0, Client::query()->count());
        $this->assertSame(0, \App\Models\Vente::query()->count());
        $this->assertSame(0, \App\Models\Intrant::query()->count());
        $this->assertSame(0, \App\Models\MouvementIntrant::query()->count());
    }
}
