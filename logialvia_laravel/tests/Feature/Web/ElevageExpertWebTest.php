<?php

namespace Tests\Feature\Web;

use App\Livewire\Couveuse;
use App\Livewire\FicheEspece;
use App\Models\Bande;
use App\Models\BaremeRation;
use App\Models\CycleCouveuse;
use App\Models\EcheanceProphylaxie;
use App\Models\FicheJournee;
use App\Models\SoinCalendrier;
use App\Models\TauxRationPoids;
use App\Models\User;
use App\Support\ExportXlsx;
use App\Support\UuidDeterministe;
use Carbon\CarbonImmutable;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Concerns\LitXlsx;
use Tests\TestCase;

/**
 * Elevage expert au web (`47e_`) : vraisemblance, taux de mortalite, chaine d'effectifs,
 * divergence, rationnement, prophylaxie du jour, recodage de bande, export XLSX.
 */
class ElevageExpertWebTest extends TestCase
{
    use LitXlsx, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-11-09 10:00:00', 'UTC'));
    }

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function utilisateur(string $role, string $username): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    private function fiche(string $role = 'animalier', string $route = '/elevage/goliaths')
    {
        return Livewire::actingAs($this->utilisateur($role, $role.Str::random(4)))->test(FicheEspece::class, ['route' => $route]);
    }

    /** Une journee deja au serveur, ecrite par un autre appareil. */
    private function journee(string $espece, string $jour, array $surcharge = []): FicheJournee
    {
        $f = (new FicheJournee)->forceFill(array_merge([
            'id' => UuidDeterministe::ficheJournee($espece, $jour), 'device_id' => (string) Str::uuid(),
            'espece' => $espece, 'date' => $jour,
            'achat' => 0, 'ne' => 0, 'vente' => 0,
            'mort_cat1' => 0, 'mort_cat2' => 0, 'mort_cat3' => 0, 'mort_cat4' => null,
            'don_cat1' => 0, 'don_cat2' => 0, 'don_cat3' => 0, 'don_cat4' => null,
            'effectif' => 0, 'eff_cat1_day' => 0, 'eff_cat2_day' => 0, 'eff_cat3_day' => 0, 'eff_cat4_day' => null,
            'traitement_valide' => false, 'is_recorded' => true,
            'updated_at' => CarbonImmutable::parse('2026-11-01 08:00:00', 'UTC'),
            'serveur_modifie_le' => CarbonImmutable::parse('2026-11-01 08:00:00', 'UTC'),
        ], $surcharge));
        $f->save();

        return $f;
    }

    // ===================================================== vraisemblance

    public function test_plus_de_morts_que_de_sujets_est_refuse_et_rien_n_est_ecrit(): void
    {
        $this->journee('goliaths', '2026-11-08', ['effectif' => 10, 'eff_cat1_day' => 10]);
        $c = $this->fiche()->set('morts.0', '11')->call('enregistrer');

        $c->assertSet('erreur', 'Morts et dons de « Poussins » (11) : supérieurs à l\'effectif disponible (10). Saisissez d\'abord les entrées (achats, naissances) ou corrigez la mortalité.');
        $this->assertNull(FicheJournee::query()->where('date', '2026-11-09')->first());
    }

    public function test_tous_les_sujets_morts_est_accepte(): void
    {
        $this->journee('goliaths', '2026-11-08', ['effectif' => 10, 'eff_cat1_day' => 10]);
        $this->fiche()->set('morts.0', '10')->call('enregistrer')->assertSet('erreur', null);
        $this->assertSame(0, FicheJournee::query()->where('date', '2026-11-09')->sole()->effectif);
    }

    public function test_les_avertissements_s_affichent_en_direct_sans_bloquer(): void
    {
        $this->journee('goliaths', '2026-11-08', ['effectif' => 200, 'eff_cat1_day' => 200]);
        $c = $this->fiche()->set('morts.0', '5');

        $c->assertSeeHtml('data-controle-avertissement')->assertSee('Mortalité du jour de 2,5 %');
        $c->call('enregistrer')->assertSet('erreur', null);
        $this->assertSame(195, FicheJournee::query()->where('date', '2026-11-09')->sole()->effectif);
    }

    public function test_une_pesee_aberrante_avertit(): void
    {
        $this->journee('goliaths', '2026-11-08', ['effectif' => 100, 'eff_cat3_day' => 100]);
        $this->fiche()->set('poids', '1250000')
            ->assertSee('Poids moyen de 12500 g par sujet : hors des repères Goliaths (30 à 6000 g).');
    }

    public function test_plus_d_oeufs_que_de_pondeuses_est_refuse(): void
    {
        $this->activer('aviculture_classique');
        $this->journee('pondeuses', '2026-11-08', ['effectif' => 100, 'eff_cat4_day' => 100]);
        $c = $this->fiche('animalier', '/elevage/poulets-pondeuses')->call('choisirOnglet', 'pondeuses')
            ->set('oeufsPondus', '101')->call('enregistrer');

        $this->assertStringStartsWith('Les œufs pondus (101) dépassent le nombre de pondeuses (100)', $c->get('erreur'));
    }

    private function activer(string ...$modules): void
    {
        foreach ($modules as $module) {
            \App\Models\ModuleActif::query()->where('module_id', $module)->update(['is_actif' => true]);
        }
    }

    // ============================================================ mortalite

    public function test_le_taux_cumule_compte_les_entrees_du_mois(): void
    {
        // 200 achetes le 3, 5 morts le 3 : exposes 0 + 200 -> 2,5 %. 100 de plus le 20 : 5 / 300 = 1,7 %.
        $this->journee('goliaths', '2026-11-03', ['achat' => 200, 'mort_cat1' => 5, 'effectif' => 195, 'eff_cat1_day' => 195]);
        $this->journee('goliaths', '2026-11-20', ['achat' => 100, 'effectif' => 295, 'eff_cat1_day' => 295]);

        $this->fiche()->assertSeeHtml('data-niveau-mortalite="normal"')->assertSee('1,7 %');
    }

    public function test_le_niveau_de_mortalite_cumulee_suit_les_seuils_10_et_20(): void
    {
        $this->journee('goliaths', '2026-11-03', ['achat' => 100, 'mort_cat1' => 11, 'effectif' => 89, 'eff_cat1_day' => 89]);
        $this->fiche()->assertSeeHtml('data-niveau-mortalite="avertissement"')->assertSee('11,0 %');

        FicheJournee::query()->update(['mort_cat1' => 21, 'effectif' => 79, 'eff_cat1_day' => 79]);
        $this->fiche()->assertSeeHtml('data-niveau-mortalite="critique"');
    }

    // ===================================================== chaine d'effectifs

    public function test_une_fiche_d_un_autre_poste_casse_la_chaine_et_le_bouton_la_repare(): void
    {
        $this->journee('goliaths', '2026-11-05', ['achat' => 50, 'effectif' => 50, 'eff_cat1_day' => 50]);
        // Le 6 a ete saisi sans voir le 5 : 7 sujets au lieu de 57.
        $this->journee('goliaths', '2026-11-06', ['achat' => 7, 'effectif' => 7, 'eff_cat1_day' => 7]);

        $c = $this->fiche()->assertSeeHtml('data-chaine')->assertSee('1 jour dont l\'effectif ne découle pas de la veille', false);
        $c->call('recalculerChaine')->assertSet('message', '1 jour recalculé.')->assertDontSeeHtml('data-chaine');

        $f = FicheJournee::query()->where('date', '2026-11-06')->sole();
        $this->assertSame(57, $f->effectif);
        $this->assertSame(57, $f->eff_cat1_day);
        $this->assertSame(50, FicheJournee::query()->where('date', '2026-11-05')->sole()->effectif, 'le jour coherent n\'est pas reecrit');
    }

    public function test_une_chaine_coherente_ne_reecrit_rien(): void
    {
        $this->journee('goliaths', '2026-11-05', ['achat' => 50, 'effectif' => 50, 'eff_cat1_day' => 50]);
        $avant = FicheJournee::query()->first()->updated_at;

        $this->fiche()->assertDontSeeHtml('data-chaine')->call('recalculerChaine')->assertSet('message', 'La chaîne était déjà cohérente.');

        $this->assertEquals($avant, FicheJournee::query()->first()->updated_at);
    }

    public function test_recalculer_la_chaine_exige_le_droit_de_gerer(): void
    {
        $this->journee('goliaths', '2026-11-05', ['achat' => 50, 'effectif' => 5, 'eff_cat1_day' => 5]);
        $role = \Spatie\Permission\Models\Role::create(['name' => 'lecteur-elevage', 'guard_name' => 'web']);
        $role->givePermissionTo('view-elevage');
        app(\Spatie\Permission\PermissionRegistrar::class)->forgetCachedPermissions();

        $this->fiche('lecteur-elevage')->call('recalculerChaine')->assertForbidden();
        $this->assertSame(5, FicheJournee::query()->first()->effectif);
    }

    // ============================================================ divergence

    private function divergence(): FicheJournee
    {
        $f = $this->journee('goliaths', '2026-11-05', [
            'achat' => 10, 'effectif' => 10, 'eff_cat1_day' => 10, 'traitement_obs' => 'A',
            'variantes' => [[
                'device_id' => (string) Str::uuid(),
                'updated_at' => '2026-11-01T07:00:00.000000Z',
                'contenu' => [
                    'espece' => 'goliaths', 'date' => '2026-11-05', 'achat' => 25, 'ne' => 0, 'vente' => 0,
                    'mort_cat1' => 0, 'mort_cat2' => 0, 'mort_cat3' => 0, 'mort_cat4' => null,
                    'don_cat1' => 0, 'don_cat2' => 0, 'don_cat3' => 0, 'don_cat4' => null,
                    'effectif' => 25, 'eff_cat1_day' => 25, 'eff_cat2_day' => 0, 'eff_cat3_day' => 0, 'eff_cat4_day' => null,
                    'srh' => null, 'ts' => null, 'stock_final_oeufs' => null,
                    'oeufs_pondus' => null, 'oeufs_casses' => null, 'sorties_plateaux' => null,
                    'poids_general_g' => null, 'traitement_obs' => 'B', 'traitement_valide' => false, 'is_recorded' => true,
                ],
            ]],
        ]);

        return $f;
    }

    public function test_une_fiche_en_divergence_montre_les_deux_versions(): void
    {
        $this->divergence();
        $this->fiche()->call('selectionnerJour', 5)
            ->assertSeeHtml('data-divergence')->assertSee('modifiée ailleurs')
            ->assertSeeHtml('data-version="0"')->assertSeeHtml('data-version="1"')
            ->assertSee('Version courante')->assertSee('« A »')->assertSee('« B »');
    }

    public function test_une_fiche_sans_divergence_n_a_aucun_bandeau(): void
    {
        $this->journee('goliaths', '2026-11-05', ['achat' => 10, 'effectif' => 10, 'eff_cat1_day' => 10]);
        $this->fiche()->call('selectionnerJour', 5)->assertDontSeeHtml('data-divergence');
    }

    public function test_garder_la_version_de_l_autre_poste_la_ressaisit_et_efface_les_variantes(): void
    {
        $f = $this->divergence();
        $this->fiche()->call('selectionnerJour', 5)->call('garderVersion', 1)
            ->assertSet('message', 'Version gardée : la fiche n\'est plus en divergence.')
            ->assertDontSeeHtml('data-divergence');

        $f = FicheJournee::query()->find($f->id);
        $this->assertSame('B', $f->traitement_obs);
        $this->assertSame(25, $f->achat);
        $this->assertSame(25, $f->effectif, 'effectifs recalcules de la veille');
        $this->assertEmpty($f->variantes ?? []);
    }

    public function test_garder_la_version_courante_efface_les_variantes(): void
    {
        $f = $this->divergence();
        $this->fiche()->call('selectionnerJour', 5)->call('garderVersion', 0);

        $f = FicheJournee::query()->find($f->id);
        $this->assertSame('A', $f->traitement_obs);
        $this->assertEmpty($f->variantes ?? []);
    }

    public function test_choisir_une_version_exige_le_droit_de_gerer(): void
    {
        $this->divergence();
        $role = \Spatie\Permission\Models\Role::create(['name' => 'lecteur-elevage', 'guard_name' => 'web']);
        $role->givePermissionTo('view-elevage');
        app(\Spatie\Permission\PermissionRegistrar::class)->forgetCachedPermissions();

        $this->fiche('lecteur-elevage')->call('selectionnerJour', 5)->call('garderVersion', 1)->assertForbidden();
        $this->assertNotEmpty(FicheJournee::query()->first()->variantes);
    }

    public function test_la_saisie_du_web_sur_une_fiche_changee_entre_temps_devient_une_divergence(): void
    {
        $this->journee('goliaths', '2026-11-09', ['achat' => 5, 'effectif' => 5, 'eff_cat1_day' => 5, 'traitement_obs' => 'poste']);
        $c = $this->fiche();
        // Un poste modifie la fiche APRES l'ouverture de l'ecran du web.
        FicheJournee::query()->update([
            'achat' => 8, 'effectif' => 8, 'eff_cat1_day' => 8, 'traitement_obs' => 'poste v2',
            'updated_at' => CarbonImmutable::parse('2026-11-09 09:00:00', 'UTC'),
        ]);

        $c->set('achat', '6')->call('enregistrer');

        $f = FicheJournee::query()->where('date', '2026-11-09')->sole();
        $this->assertSame(6, $f->achat, 'la saisie du web, plus recente, est courante');
        $this->assertCount(1, $f->variantes, 'celle du poste est conservee, pas ecrasee');
        $this->assertSame('poste v2', $f->variantes[0]['contenu']['traitement_obs']);
    }

    public function test_une_suite_normale_du_web_ne_cree_pas_de_divergence(): void
    {
        $this->journee('goliaths', '2026-11-09', ['achat' => 5, 'effectif' => 5, 'eff_cat1_day' => 5]);
        $this->fiche()->set('achat', '6')->call('enregistrer');

        $this->assertEmpty(FicheJournee::query()->where('date', '2026-11-09')->sole()->variantes ?? []);
    }

    // ============================================================ rationnement

    public function test_la_provende_se_calcule_des_baremes_synchronises(): void
    {
        BaremeRation::query()->create(['id' => (string) Str::uuid(), 'espece' => 'goliaths', 'stade' => 'Mature', 'ration_grammes_par_jour' => 130, 'confirme' => false, 'saisi_le' => now()]);
        $this->journee('goliaths', '2026-11-08', ['effectif' => 40, 'eff_cat1_day' => 10, 'eff_cat2_day' => 10, 'eff_cat3_day' => 20]);

        // 10 x 30 + 10 x 60 + 20 x 130 (bareme modifie) = 300 + 600 + 2600 = 3 500 g.
        $this->fiche()->assertSeeHtml('data-rationnement')->assertSee('Provende du jour : 3 500 g (3,5 kg)');
    }

    public function test_le_stade_seme_du_bareme_pilote_la_categorie_equivalente(): void
    {
        BaremeRation::query()->create(['id' => (string) Str::uuid(), 'espece' => 'pintades', 'stade' => 'Alevins', 'ration_grammes_par_jour' => 40, 'confirme' => false, 'saisi_le' => now()]);
        $this->journee('pintades', '2026-11-08', ['effectif' => 10, 'eff_cat1_day' => 10]);

        $this->fiche('animalier', '/elevage/pintades')->assertSee('Provende du jour : 400 g (0,4 kg)');
    }

    public function test_le_calcul_des_rations_et_de_la_provende_aux_valeurs_du_dart(): void
    {
        $c = \App\Support\CalculFicheJournaliere::class;
        $this->assertSame(120, $c::rationCategorie('lapins', 2, []), 'reproducteur lapin : 120 g (Q-ELV-2)');
        $this->assertSame(45, $c::rationCategorie('lapins', 0, ['Sevré / Lapereaux' => 45]));
        $this->assertSame(40, $c::rationCategorie('pintades', 0, ['Poussins' => 40, 'Alevins' => 35]));
        $this->assertSame(35, $c::rationCategorie('pintades', 0, ['Alevins' => 35]));
        // Poissons-chats : repli par tete 1 / 3 / 8 g ; 1 000 juveniles = 3 000 g.
        $this->assertSame(3000, $c::provendeDuJour('poissons-chats', [0, 1000, 0], [], [], null)['grammes']);
        // Au poids vif : 1 000 juveniles de 50 g = 50 000 g a 4 % = 2 000 g.
        $classes = [['poids_min_g' => 20, 'poids_max_g' => 100, 'taux_pourcent' => 4.0]];
        $p = $c::provendeDuJour('poissons-chats', [0, 1000, 0], [], $classes, 50000);
        $this->assertSame([2000, true, 4.0, 50], [$p['grammes'], $p['sur_poids_vif'], $p['taux_pourcent'], $p['poids_moyen_g']]);
        // Borne basse incluse, haute exclue.
        $this->assertTrue($c::provendeDuJour('poissons-chats', [0, 1, 0], [], $classes, 20)['sur_poids_vif']);
        $this->assertFalse($c::provendeDuJour('poissons-chats', [0, 1, 0], [], $classes, 100)['sur_poids_vif']);
    }

    public function test_les_chiffres_du_stock_sont_grises_disponibles_sur_le_poste(): void
    {
        $this->fiche()->assertSeeHtml('data-stock-poste')->assertSee('Provende en stock et autonomie : Disponible sur le poste');
    }

    // ===================================================== prophylaxie du jour

    private function bandeEtCalendrier(): array
    {
        $bande = Bande::query()->create([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'espece' => 'goliaths', 'code' => 'B1',
            'date_mise_en_bande' => '2026-11-05', 'effectif_initial' => 100,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        // 2026-11-09 = J5 de la bande du 05/11.
        $echeance = EcheanceProphylaxie::query()->create([
            'id' => (string) Str::uuid(), 'espece' => 'goliaths', 'jour_cycle' => 5, 'traitement' => 'Vaccin Newcastle',
            'produit' => 'ND-Lasota', 'remanence_jours' => 0, 'dose' => '1 goutte', 'saisi_le' => now(),
        ]);

        return [$bande, $echeance];
    }

    public function test_la_prophylaxie_du_jour_suit_le_jour_du_cycle(): void
    {
        $this->bandeEtCalendrier();
        $this->fiche()->assertSeeHtml('data-prophylaxie')->assertSee('Vaccin Newcastle')->assertSee('J5 du cycle');
        $this->fiche()->call('selectionnerJour', 10)->assertSee('Aucun traitement prévu au J6 du cycle.');
    }

    public function test_sans_bande_aucune_date_de_traitement_n_est_calculable(): void
    {
        $this->fiche()->assertSee('Sans bande, aucune date de traitement n\'est calculable', false);
    }

    public function test_planifier_une_echeance_cree_le_soin_deterministe_lie_a_la_bande(): void
    {
        [$bande, $echeance] = $this->bandeEtCalendrier();
        $this->fiche()->call('planifierEcheance', $echeance->id, 'Vaccination')->assertSet('message', 'Vaccin Newcastle planifié.');

        $soin = SoinCalendrier::query()->sole();
        $this->assertSame(UuidDeterministe::soinProphylaxie($bande->id, $echeance->id), $soin->id);
        $this->assertSame($bande->id, $soin->bande_id);
        $this->assertSame($echeance->id, $soin->echeance_prophylaxie_id);
        $this->assertSame('2026-11-09', $soin->date_prevue->format('Y-m-d'));
        $this->assertSame('Planifié', $soin->statut);
    }

    public function test_planifier_deux_fois_ne_cree_pas_de_doublon(): void
    {
        [, $echeance] = $this->bandeEtCalendrier();
        $c = $this->fiche()->call('planifierEcheance', $echeance->id, 'Vaccination');
        $c->call('planifierEcheance', $echeance->id, 'Vitamines')->assertSet('erreur', 'Cette échéance est déjà planifiée.');

        $this->assertSame(1, SoinCalendrier::query()->count());
    }

    public function test_un_type_d_action_inconnu_est_refuse(): void
    {
        [, $echeance] = $this->bandeEtCalendrier();
        $this->fiche()->call('planifierEcheance', $echeance->id, 'Sorcellerie')->assertSet('erreur', 'Ce type d\'action n\'existe pas.');
        $this->assertSame(0, SoinCalendrier::query()->count());
    }

    public function test_planifier_exige_le_droit_de_gerer(): void
    {
        [, $echeance] = $this->bandeEtCalendrier();
        $role = \Spatie\Permission\Models\Role::create(['name' => 'lecteur-elevage', 'guard_name' => 'web']);
        $role->givePermissionTo('view-elevage');
        app(\Spatie\Permission\PermissionRegistrar::class)->forgetCachedPermissions();

        $this->fiche('lecteur-elevage')->call('planifierEcheance', $echeance->id, 'Vaccination')->assertForbidden();
        $this->assertSame(0, SoinCalendrier::query()->count());
    }

    // ============================================================== recodage

    public function test_recoder_une_bande_trace_l_ancien_code(): void
    {
        [$bande] = $this->bandeEtCalendrier();
        $c = $this->fiche()->call('ouvrirRecodage')->assertSet('nouveauCode', 'B1-WEB');
        $c->call('recoderBande')->assertSet('message', 'Bande recodée en B1-WEB.');

        $b = Bande::query()->find($bande->id);
        $this->assertSame('B1-WEB', $b->code);
        $this->assertStringContainsString('Recodée de B1 en B1-WEB le 2026-11-09', $b->observations);
    }

    public function test_recoder_vers_un_code_deja_pris_est_refuse(): void
    {
        [$bande] = $this->bandeEtCalendrier();
        Bande::query()->create([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'espece' => 'goliaths', 'code' => 'B2',
            'date_mise_en_bande' => '2026-01-01', 'date_cloture' => '2026-02-01', 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $this->fiche()->call('ouvrirRecodage')->set('nouveauCode', 'B2')->call('recoderBande')
            ->assertSet('erreurRecodage', 'Ce code de bande est déjà utilisé pour cette filière.');
        $this->assertSame('B1', Bande::query()->find($bande->id)->code);
    }

    public function test_un_code_de_recodage_vide_est_refuse(): void
    {
        $this->bandeEtCalendrier();
        $this->fiche()->call('ouvrirRecodage')->set('nouveauCode', '  ')->call('recoderBande')
            ->assertSet('erreurRecodage', 'Le code de la bande est obligatoire.');
    }

    public function test_recoder_exige_le_droit_de_gerer(): void
    {
        $this->bandeEtCalendrier();
        $role = \Spatie\Permission\Models\Role::create(['name' => 'lecteur-elevage', 'guard_name' => 'web']);
        $role->givePermissionTo('view-elevage');
        app(\Spatie\Permission\PermissionRegistrar::class)->forgetCachedPermissions();

        $this->fiche('lecteur-elevage')->call('ouvrirRecodage')->assertForbidden();
    }

    // ============================================================ export XLSX

    public function test_export_xlsx_du_mois_avec_le_contenu_de_l_ecran(): void
    {
        $this->journee('goliaths', '2026-11-03', ['achat' => 20, 'ne' => 2, 'mort_cat1' => 1, 'effectif' => 21, 'eff_cat1_day' => 21, 'poids_general_g' => 900, 'traitement_obs' => 'RAS']);
        $c = $this->fiche('admin')->call('exporter');

        $c->assertFileDownloaded('fiche-goliaths-2026-11.xlsx', null, ExportXlsx::TYPE);
        $lignes = $this->lignesXlsx(base64_decode($c->effects['download']['content']));
        $this->assertSame(['Fiche Goliaths — Novembre 2026'], $lignes[0]);
        $this->assertSame(['Date', 'Achats', 'Nés (Couveuse)', 'Vente', 'Morts', 'Dons', 'Effectif', 'Pesée (g)', 'Observation de traitement'], $lignes[2]);
        $this->assertSame(['03/11/2026', '20', '2', '0', '1', '0', '21', '900', 'RAS'], $lignes[3]);
        $this->assertCount(4, $lignes, 'seuls les jours saisis sont exportes');
    }

    public function test_l_export_exige_le_droit_export_elevage(): void
    {
        $role = \Spatie\Permission\Models\Role::create(['name' => 'lecteur-elevage', 'guard_name' => 'web']);
        $role->givePermissionTo('view-elevage');
        app(\Spatie\Permission\PermissionRegistrar::class)->forgetCachedPermissions();

        $this->fiche('lecteur-elevage')->call('exporter')->assertForbidden();
    }

    public function test_l_ecran_propose_l_impression_et_l_export(): void
    {
        $this->fiche('admin')->assertSeeHtml('data-action="imprimer"')->assertSee('Imprimer / PDF')->assertSeeHtml('data-action="exporter"')->assertSee('Exporter (XLSX)');
    }

    // ============================================================== couveuse

    private function lot(string $espece, string $charge): CycleCouveuse
    {
        return (new CycleCouveuse)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'code_incubation' => 'C-WEB-2026-001',
            'espece' => $espece, 'date_incubation' => $charge, 'oeufs_couves' => 100, 'statut' => 'En Incubation',
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
    }

    public function test_un_mirage_premature_est_refuse(): void
    {
        $lot = $this->lot('goliath', '2026-11-05');
        $lot->save();
        // Au 9 novembre le lot a 4 jours : pas de mirage J+7 avant J+5.
        $c = Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(Couveuse::class)
            ->set('mirageLotId', $lot->id)->set('mirageJour', 7)->set('mirageRetires', '5')->call('enregistrerMirage');

        $c->assertSet('erreur', "Le mirage à J+7 ne peut pas se faire avant J+5 : ce lot n'a que 4 jours d'incubation.");
        $this->assertNull($lot->fresh()->oeufs_blancs_j7);
    }

    public function test_une_eclosion_premature_est_refusee_et_une_eclosion_a_terme_acceptee(): void
    {
        $lot = $this->lot('goliath', '2026-11-05');
        $lot->save();
        $c = Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(Couveuse::class)
            ->set('eclosionLotId', $lot->id)->set('poussins', '50')->set('perdus', '5')->call('enregistrerEclosion');
        $c->assertSet('erreur', "Éclosion impossible : ce lot n'a que 4 jours d'incubation, Goliath incube 21 jours (éclosion possible à partir de J+17).");
        $this->assertSame('En Incubation', $lot->fresh()->statut);

        $ancien = $this->lot('pintade', '2026-10-12'); // 28 jours au 9 novembre
        $ancien->code_incubation = 'C-WEB-2026-002';
        $ancien->save();
        $c = Livewire::actingAs($this->utilisateur('animalier', 'eleveur2'))->test(Couveuse::class)
            ->set('eclosionLotId', $ancien->id)->set('poussins', '50')->set('perdus', '5')->call('enregistrerEclosion');
        $c->assertSet('erreur', null);
        $this->assertSame('Éclosion Effectuée', $ancien->fresh()->statut);
    }

    // ======================================================= reperes (poste)

    public function test_les_reperes_zootechniques_aux_valeurs_du_dart(): void
    {
        $r = \App\Support\ReperesZootechniques::class;
        $this->assertSame('normal', $r::niveauMortaliteJour(1.0));
        $this->assertSame('avertissement', $r::niveauMortaliteJour(1.01));
        $this->assertSame('avertissement', $r::niveauMortaliteJour(2.0));
        $this->assertSame('critique', $r::niveauMortaliteJour(2.01));
        $this->assertSame('normal', $r::niveauMortaliteCumul(10));
        $this->assertSame('avertissement', $r::niveauMortaliteCumul(10.5));
        $this->assertSame('avertissement', $r::niveauMortaliteCumul(20));
        $this->assertSame('critique', $r::niveauMortaliteCumul(20.1));
        $this->assertEqualsWithDelta(5.0, $r::tauxMortaliteCumule(12, 100, 140), 1e-9);
        $this->assertNull($r::tauxMortaliteCumule(2, 0, 0));
        $this->assertEqualsWithDelta(50.0, $r::gmqGrammesParJour(500, 1850, 27), 1e-9);
        $this->assertEqualsWithDelta(-10.0, $r::gmqGrammesParJour(1000, 900, 10), 1e-9);
        $this->assertNull($r::gmqGrammesParJour(1, 2, 0));
        $this->assertEqualsWithDelta(2.0, $r::indiceConsommation(3000, 1500), 1e-9);
        $this->assertNull($r::indiceConsommation(3000, 0));
        $this->assertSame(['min' => 2000, 'max' => 120000], $r::poidsMoyenPlausibleG('ovins'));
    }

    public function test_les_semaines_comptent_les_entrees_dans_l_effectif_expose(): void
    {
        $journees = [2 => [
            'achat' => 200, 'ne' => 0, 'vente' => 0, 'morts' => [5, 0, 0], 'dons' => [0, 0, 0],
            'effectif' => 195, 'is_recorded' => true, 'traitement_obs' => null,
        ]];
        $s = \App\Support\AgregationHebdomadaire::calculer(30, $journees, 0);
        $this->assertEqualsWithDelta(2.5, $s[0]['taux_mortalite'], 1e-9);

        // Une veille non saisie garde le dernier effectif connu (80), pas l'effectif de debut de mois (100).
        $journees = [
            6 => ['achat' => 0, 'ne' => 0, 'vente' => 0, 'morts' => [0, 0, 0], 'dons' => [0, 0, 0], 'effectif' => 80, 'is_recorded' => true, 'traitement_obs' => null],
            9 => ['achat' => 0, 'ne' => 0, 'vente' => 0, 'morts' => [4, 0, 0], 'dons' => [0, 0, 0], 'effectif' => 76, 'is_recorded' => true, 'traitement_obs' => null],
        ];
        $s = \App\Support\AgregationHebdomadaire::calculer(30, $journees, 100);
        $this->assertSame(80, $s[1]['effectif_debut']);
        $this->assertEqualsWithDelta(5.0, $s[1]['taux_mortalite'], 1e-9);
    }

    public function test_la_ration_d_un_poisson_chat_et_d_un_reproducteur_lapin_suivent_le_dart(): void
    {
        $this->assertSame([1, 3, 8], array_column(\App\Support\FilieresElevage::configuration('poissons-chats')['categories'], 1));
        $this->assertSame(120, \App\Support\FilieresElevage::configuration('lapins')['categories'][2][1]);
    }

    public function test_aucun_taux_de_ration_n_est_requis_pour_les_filieres_au_ration_par_tete(): void
    {
        TauxRationPoids::query()->count();
        $this->assertFalse(in_array('goliaths', \App\Support\FilieresElevage::RATION_AU_POIDS_VIF, true));
    }

    // ================================================================== GMQ

    public function test_le_gmq_du_dashboard_vient_des_pesees_des_fiches(): void
    {
        // 500 g de poids moyen le 15/10 puis 1 855,7 g (180 000 / 97) le 8/11 : (1 855,7 - 500) / 24 j = 56,5 g/j.
        $this->journee('goliaths', '2026-10-15', ['effectif' => 100, 'poids_general_g' => 50000]);
        $this->journee('goliaths', '2026-11-08', ['effectif' => 97, 'poids_general_g' => 180000]);

        Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(\App\Livewire\DashboardElevage::class)
            ->assertSeeHtml('data-gmq="goliaths"')->assertSee('Goliaths : 56,5 g/j')->assertSee('500 g → 1856 g en 24 j');
    }

    public function test_sans_deux_pesees_le_gmq_est_declare_absent(): void
    {
        $this->journee('goliaths', '2026-11-08', ['effectif' => 97, 'poids_general_g' => 180000]);

        Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(\App\Livewire\DashboardElevage::class)
            ->assertSeeHtml('data-gmq="vide"')->assertDontSeeHtml('data-gmq="goliaths"');
    }

    public function test_le_gmq_calcule_aux_valeurs_du_dart(): void
    {
        $g = \App\Support\ReperesZootechniques::gmqSurPesees([
            ['date' => '2026-10-12', 'poids_total_g' => 50000, 'effectif' => 100],
            ['date' => '2026-11-08', 'poids_total_g' => 180000, 'effectif' => 97],
        ]);
        $this->assertSame(27, $g['jours']);
        $this->assertEqualsWithDelta(500.0, $g['poids_initial_g'], 1e-9);
        $this->assertEqualsWithDelta(1855.67, $g['poids_final_g'], 0.01);
        $this->assertEqualsWithDelta(50.2, $g['gmq'], 0.1);
        $this->assertNull(\App\Support\ReperesZootechniques::gmqSurPesees([['date' => '2026-11-08', 'poids_total_g' => 5, 'effectif' => 1]]));
        $this->assertNull(\App\Support\ReperesZootechniques::gmqSurPesees([
            ['date' => '2026-11-08', 'poids_total_g' => 5, 'effectif' => 1], ['date' => '2026-11-08', 'poids_total_g' => 6, 'effectif' => 1],
        ]));
    }

    // ======================================== dashboard : couveuse, rappels, alertes

    private function soin(string $statut, string $date, string $type = 'Vaccination'): SoinCalendrier
    {
        return SoinCalendrier::query()->create([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'espece' => 'goliaths', 'date_prevue' => $date,
            'type_soin' => $type, 'statut' => $statut, 'remanence_jours' => 0, 'cout_fcfa' => 0,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
    }

    private function dashboard()
    {
        return Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(\App\Livewire\DashboardElevage::class);
    }

    public function test_un_soin_planifie_dont_la_date_est_passee_est_en_retard(): void
    {
        $this->soin('Planifié', '2026-11-05', 'Vaccin Newcastle');   // passe : en retard
        $this->soin('Planifié', '2026-11-12', 'Vermifuge');            // futur : a venir
        $this->soin('En retard', '2026-11-20', 'Vitamines');          // marque a la main
        $this->soin('Effectué', '2026-11-01', 'Traitement curatif');  // fait : nulle part

        $c = $this->dashboard();
        $c->assertSeeHtml('data-panneau="alertes"')->assertSee('Vaccin Newcastle — Goliaths (En Retard, prévu le 05/11/2026)')
            ->assertSee('Vitamines — Goliaths (En Retard, prévu le 20/11/2026)')
            ->assertDontSee('Vermifuge — Goliaths (En Retard')->assertDontSee('Traitement curatif — Goliaths');
        $c->assertSee('Vermifuge')->assertDontSee('Traitement curatif');
    }

    public function test_sans_soin_en_retard_le_dashboard_le_dit(): void
    {
        $this->soin('Planifié', '2026-11-12');
        $this->dashboard()->assertSeeHtml('data-alerte="vide"')->assertSee('Aucun soin en retard.');
    }

    public function test_les_rappels_sont_les_cinq_prochains_soins_non_effectues(): void
    {
        foreach (range(1, 7) as $i) {
            $this->soin('Planifié', '2026-11-'.str_pad((string) (9 + $i), 2, '0', STR_PAD_LEFT), 'Soin n°'.$i);
        }
        $html = $this->dashboard()->html();
        $this->assertSame(5, substr_count($html, 'data-rappel="'.''), 'cinq rappels au plus');
        $this->assertStringContainsString('Soin n°1', $html);
        $this->assertStringContainsString('Soin n°5', $html);
        $this->assertStringNotContainsString('Soin n°6', $html);
    }

    public function test_la_carte_couveuse_compte_les_lots_synchronises(): void
    {
        $this->lot('goliath', '2026-11-01')->save();
        $eclos = $this->lot('goliath', '2026-09-01');
        $eclos->forceFill(['code_incubation' => 'C-WEB-2026-009', 'statut' => 'Éclosion Effectuée', 'oeufs_couves' => 200, 'poussins_nes' => 160])->save();

        // 1 cycle en cours de 100 oeufs ; taux brut moyen 160 / 200 = 80 % ; 100 x 80 % = 80 poussins attendus.
        $this->dashboard()->assertSeeHtml('data-couveuse="cycles">1<')->assertSeeHtml('data-couveuse="oeufs">100<')
            ->assertSeeHtml('data-couveuse="taux">80,0 %<')->assertSeeHtml('data-couveuse="attendus">80<');
    }

    public function test_les_stocks_d_intrants_restent_grises_disponibles_sur_le_poste(): void
    {
        $this->dashboard()->assertSeeHtml('data-stock-poste')->assertSee('Stocks d\'intrants sous leur seuil : Disponible sur le poste', false);
    }
}
