<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\FicheEspece;
use App\Models\Bande;
use App\Models\FicheJournee;
use App\Models\FicheVentesJour;
use App\Models\ModuleActif;
use App\Models\User;
use App\Support\UuidDeterministe;
use Carbon\CarbonImmutable;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Features\SupportLockedProperties\CannotUpdateLockedPropertyException;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Fiches d'elevage du web (`/elevage/<filiere>`) : un composant, sept routes. Ecritures par
 * `TableSync::absorber` (device web) ; effectifs recalcules, jamais saisis ; cascade ; bandes.
 */
class FicheEspeceWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        // « Aujourd'hui » est fige : le jour par defaut, la cloture et les mois en dependent.
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-11-09 10:00:00', 'UTC'));
    }

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function utilisateur(string $role, string $username = 'u'): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    private ?User $animalier = null;

    /** Compte qui peut VOIR l'elevage sans le gerer (aucun des quatre roles ne l'est : role de test). */
    private function lecteur(): User
    {
        $role = \Spatie\Permission\Models\Role::create(['name' => 'lecteur-elevage', 'guard_name' => 'web']);
        $role->givePermissionTo('view-elevage');
        app(\Spatie\Permission\PermissionRegistrar::class)->forgetCachedPermissions();

        return $this->utilisateur('lecteur-elevage', 'lecteur');
    }

    private function animalier(): User
    {
        return $this->animalier ??= $this->utilisateur('animalier', 'eleveur');
    }

    private function activer(string ...$modules): void
    {
        foreach ($modules as $module) {
            ModuleActif::query()->where('module_id', $module)->update(['is_actif' => true]);
        }
    }

    /** Le composant, comme s'il etait servi sur cette route. */
    private function fiche(User $u, string $route = '/elevage/goliaths')
    {
        return Livewire::actingAs($u)->test(FicheEspece::class, ['route' => $route]);
    }

    /** Une journee deja au serveur (ecrite par un poste). */
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

    private function compteur(string $device, string $espece, string $jour, int $qte): FicheVentesJour
    {
        $c = (new FicheVentesJour)->forceFill([
            'id' => UuidDeterministe::ventesJour($espece, $jour, $device), 'device_id' => $device,
            'espece' => $espece, 'date' => $jour, 'qte' => $qte,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $c->save();

        return $c;
    }

    private function bande(string $code = 'B1', array $surcharge = []): Bande
    {
        $b = (new Bande)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'espece' => 'goliaths', 'code' => $code,
            'date_mise_en_bande' => '2026-10-20', 'effectif_initial' => 120, 'date_cloture' => null, 'observations' => 'Enclos E2',
            'updated_at' => CarbonImmutable::parse('2026-11-01 08:00:00', 'UTC'),
            'serveur_modifie_le' => CarbonImmutable::parse('2026-11-01 08:00:00', 'UTC'),
        ], $surcharge));
        $b->save();

        return $b;
    }

    // ------------------------------------------------------------------- Acces

    public function test_visiteur_caissier_et_comptable_n_ouvrent_pas_la_fiche(): void
    {
        $this->get('/elevage/goliaths')->assertRedirect(route('login'));
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get('/elevage/goliaths')->assertForbidden();
        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/elevage/goliaths')->assertForbidden();
    }

    public function test_l_animalier_et_l_administrateur_l_ouvrent_et_c_est_bien_l_ecran_converti(): void
    {
        foreach ([$this->animalier(), $this->utilisateur('admin', 'gerante')] as $u) {
            $this->actingAs($u)->get('/elevage/goliaths')->assertOk()->assertSee('Fiche Goliaths')->assertDontSee('arrive bientôt');
        }
    }

    public function test_les_sept_routes_ouvrent_leur_filiere_quand_leur_module_est_actif(): void
    {
        $this->activer('cuniculture', 'pisciculture', 'heliciculture', 'bovins', 'aviculture_classique');
        $u = $this->animalier();

        foreach ([
            '/elevage/goliaths' => 'Fiche Goliaths', '/elevage/pintades' => 'Fiche Pintades', '/elevage/lapins' => 'Fiche Lapins',
            '/elevage/poissons-chats' => 'Fiche Poissons-Chats', '/elevage/escargots' => 'Fiche Escargots',
            '/elevage/bovins' => 'Fiche Bovins', '/elevage/poulets-pondeuses' => 'Fiche Poulets',
        ] as $route => $titre) {
            $this->actingAs($u)->get($route)->assertOk()->assertSee($titre);
        }
    }

    public function test_une_filiere_dont_le_module_est_inactif_repond_404(): void
    {
        $u = $this->animalier();
        foreach (['/elevage/lapins', '/elevage/poissons-chats', '/elevage/escargots', '/elevage/bovins', '/elevage/poulets-pondeuses'] as $route) {
            $this->actingAs($u)->get($route)->assertNotFound();
        }
        $this->actingAs($u)->get('/elevage/goliaths')->assertOk();
        $this->actingAs($u)->get('/elevage/pintades')->assertOk();
    }

    public function test_poulets_et_pondeuses_sont_deux_onglets_d_une_meme_route(): void
    {
        $this->activer('aviculture_classique');
        $this->journee('poulets', '2026-11-05', ['effectif' => 30, 'eff_cat1_day' => 30]);
        $this->journee('pondeuses', '2026-11-05', ['effectif' => 77, 'eff_cat1_day' => 77, 'mort_cat4' => 0, 'don_cat4' => 0, 'eff_cat4_day' => 0]);

        $c = $this->fiche($this->animalier(), '/elevage/poulets-pondeuses')
            ->assertSee('Fiche Poulets')->assertSeeHtml('data-onglets')->assertSee('Pondeuses')
            ->assertSeeHtml('data-kpi="effectif">30<');

        $c->call('choisirOnglet', 'pondeuses')->assertSee('Fiche Pondeuses')->assertSeeHtml('data-kpi="effectif">77<')
            ->assertSeeHtml('data-oeufs>');
    }

    public function test_un_onglet_etranger_a_la_route_est_refuse_et_la_filiere_est_verrouillee(): void
    {
        $this->fiche($this->animalier(), '/elevage/goliaths')->call('choisirOnglet', 'pintades')->assertNotFound();

        $this->expectException(CannotUpdateLockedPropertyException::class);
        $this->fiche($this->animalier(), '/elevage/goliaths')->set('espece', 'pintades');
    }

    // ----------------------------------------------------------------- Lecture

    public function test_le_jour_par_defaut_est_aujourd_hui_dans_le_fuseau_de_l_entreprise(): void
    {
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-11-09 23:30:00', 'UTC')); // 00:30 le 10 a Porto-Novo

        $this->fiche($this->animalier())->assertSet('jour', '2026-11-10');
    }

    public function test_les_kpi_viennent_de_la_derniere_journee_saisie_du_mois_et_du_cumul(): void
    {
        // 1er jour saisi : effectif 100 apres 4 morts (base 104) ; dernier : 90 dont 20 immatures et 30 matures.
        $this->journee('goliaths', '2026-11-02', ['effectif' => 100, 'mort_cat1' => 3, 'mort_cat3' => 1, 'eff_cat1_day' => 50, 'eff_cat2_day' => 25, 'eff_cat3_day' => 25]);
        $this->journee('goliaths', '2026-11-06', ['effectif' => 90, 'mort_cat2' => 4, 'eff_cat1_day' => 40, 'eff_cat2_day' => 20, 'eff_cat3_day' => 30]);
        $this->journee('goliaths', '2026-11-08', ['effectif' => 999, 'is_recorded' => false]); // projetee : ignoree
        $this->journee('goliaths', '2026-10-30', ['effectif' => 555, 'mort_cat1' => 50]); // autre mois : ignoree

        $this->fiche($this->animalier())
            ->assertSeeHtml('data-kpi="effectif">90<')
            ->assertSeeHtml('data-kpi="matures">30<')
            ->assertSeeHtml('data-kpi="immatures">20<')
            // (4 + 4) morts / base (100 + 4) = 7,7 %
            ->assertSeeHtml('data-kpi="mortalite">7,7 %<')
            ->assertSee('Mature (Éligibles Vente)')->assertSee('Goliathau (Immatures)');
    }

    public function test_sans_journee_saisie_les_kpi_sont_a_zero_avec_leur_message(): void
    {
        $this->fiche($this->animalier())
            ->assertSeeHtml('data-kpi="effectif">0<')->assertSeeHtml('data-kpi="mortalite">0,0 %<')
            ->assertSee('Aucune journée saisie ce mois-ci');
    }

    public function test_le_tableau_mensuel_montre_les_jours_saisis_et_des_tirets_pour_les_autres(): void
    {
        $this->journee('goliaths', '2026-11-05', ['achat' => 12, 'ne' => 3, 'vente' => 1, 'mort_cat1' => 2, 'mort_cat2' => 1, 'don_cat3' => 4, 'effectif' => 40]);

        $c = $this->fiche($this->animalier())->assertSee('Historique du Mois — Novembre 2026');
        $html = $c->html();

        $this->assertMatchesRegularExpression('#data-jour="5".*?05/11.*?>12<.*?>3<.*?>1<.*?>3<.*?>4<.*?>40<#s', $html);
        $this->assertMatchesRegularExpression('#data-jour="6".*?06/11.*?—.*?—.*?—.*?—.*?—.*?—#s', $html);
        $this->assertSame(30, substr_count($html, 'data-jour="'));
    }

    public function test_choisir_un_autre_mois_change_l_historique_et_cliquer_un_jour_le_rend_actif(): void
    {
        $this->journee('goliaths', '2026-10-15', ['achat' => 7, 'effectif' => 7]);

        $c = $this->fiche($this->animalier())->set('jour', '2026-10-15')
            ->assertSee('Historique du Mois — Octobre 2026')->assertSee('Saisie Journalière — 15/10/2026')
            ->assertSet('achat', 7);

        $c->call('selectionnerJour', 20)->assertSet('jour', '2026-10-20')->assertSet('achat', 0);
    }

    public function test_une_date_invalide_ou_hors_bornes_ramene_au_jour_et_le_dit(): void
    {
        foreach (['2026-02-31', 'n\'importe quoi', '2019-12-31', '2028-01-01'] as $mauvaise) {
            $this->fiche($this->animalier())->set('jour', $mauvaise)
                ->assertSet('jour', '2026-11-09')->assertSee('Cette date n\'est pas valide');
        }
        $this->fiche($this->animalier())->set('jour', '2027-12-31')->assertSet('jour', '2027-12-31');
    }

    public function test_un_jour_hors_du_mois_est_refuse(): void
    {
        // novembre n'a que 30 jours
        $this->fiche($this->animalier())->call('selectionnerJour', 31)->assertStatus(422);
    }

    public function test_le_formulaire_reprend_la_journee_enregistree(): void
    {
        $this->journee('goliaths', '2026-11-09', [
            'achat' => 5, 'ne' => 2, 'mort_cat2' => 3, 'don_cat1' => 1, 'poids_general_g' => 1500,
            'traitement_obs' => 'Vermifuge', 'traitement_valide' => true,
        ]);

        $this->fiche($this->animalier())->assertSet('achat', 5)->assertSet('ne', 2)->assertSet('morts', [0, 3, 0])
            ->assertSet('dons', [1, 0, 0])->assertSet('poids', '1500')->assertSet('observation', 'Vermifuge')
            ->assertSet('traitementValide', true);
    }

    public function test_les_ventes_du_pos_sont_la_somme_des_compteurs_de_tous_les_postes_en_lecture_seule(): void
    {
        $this->compteur((string) Str::uuid(), 'goliaths', '2026-11-09', 2);
        $this->compteur((string) Str::uuid(), 'goliaths', '2026-11-09', 3);
        $this->compteur((string) Str::uuid(), 'goliaths', '2026-11-08', 50); // autre jour
        $this->compteur((string) Str::uuid(), 'pintades', '2026-11-09', 40); // autre filiere

        $this->fiche($this->animalier())->assertSeeHtml('data-champ="vente"')
            ->assertSeeHtml('value="5" readonly data-champ="vente"');
    }

    public function test_les_totaux_se_calculent_en_direct_sans_rien_ecrire(): void
    {
        $this->journee('goliaths', '2026-11-08', ['effectif' => 100, 'eff_cat1_day' => 40, 'eff_cat2_day' => 30, 'eff_cat3_day' => 30]);
        $this->compteur((string) Str::uuid(), 'goliaths', '2026-11-09', 6);

        $c = $this->fiche($this->animalier())
            ->set('achat', '20')->set('ne', '5')->set('morts.0', '2')->set('dons.2', '3');

        // 100 + 20 + 5 - (2 morts + 6 ventes + 3 dons) = 114 ; mortalite 2 / 100.
        $c->assertSeeHtml('data-total="effectif">114<')->assertSeeHtml('data-total="mortalite">2,0 %<');
        $this->assertSame(1, FicheJournee::query()->count(), 'rien n\'est ecrit tant qu\'on n\'enregistre pas');
    }

    public function test_la_vue_hebdomadaire_agrege_les_semaines_comme_le_dart(): void
    {
        $this->journee('goliaths', '2026-11-03', ['achat' => 10, 'ne' => 2, 'vente' => 1, 'mort_cat1' => 3, 'effectif' => 50, 'traitement_obs' => 'Vermifuge']);
        $this->journee('goliaths', '2026-11-06', ['achat' => 5, 'mort_cat2' => 2, 'effectif' => 48, 'traitement_obs' => 'Vitamines']);
        $this->journee('goliaths', '2026-11-20', ['effectif' => 40]);

        $c = $this->fiche($this->animalier())->call('basculer', true);

        $c->assertSeeHtml('data-table="hebdomadaire"')->assertDontSeeHtml('data-table="mensuel"')
            ->assertSee('Semaine 1 (1-7 novembre)')->assertSee('Semaine 4 (22-30 novembre)')
            ->assertSee('Cumul NÉS (COUVEUSE)') // libelle du glossaire, en majuscules (Dart : `toUpperCase`)
            ->assertSee('Vermifuge · Vitamines');
        $html = $c->html();
        // Semaine 1 : achats 15, nes 2, morts 5, ventes 1, fin 48, mortalite 5 / 0 (sans veille : effectif initial).
        $this->assertMatchesRegularExpression('#data-semaine="1".*?>15<.*?>2<.*?>5<.*?>1<.*?>48<#s', $html);
        $this->assertMatchesRegularExpression('#data-semaine="2".*?—.*?—.*?—.*?—.*?—.*?—#s', $html);

        $c->call('basculer', false)->assertSeeHtml('data-table="mensuel"');
    }

    public function test_le_rappel_du_cycle_et_les_ecarts_declares_sont_affiches(): void
    {
        $this->fiche($this->animalier())
            ->assertSee('Rappel du Cycle :')->assertSee('Naissance (Couveuse)')->assertSee('Goliathau (0 → 4 mois)')
            ->assertSee('Mature (≥ 4 mois, ≥ 2,8 kg) — Éligible à la Vente')
            ->assertSeeHtml('data-ecart="rationnement"')->assertSee('disponibles sur le poste');
    }

    public function test_les_libelles_propres_a_la_filiere_viennent_du_dart(): void
    {
        $this->activer('cuniculture', 'heliciculture');
        $this->fiche($this->animalier(), '/elevage/lapins')->assertSee('Nés (Mise bas)')->assertSee('Reproducteur')->assertSee('Chair (Immatures)');
        $this->fiche($this->animalier(), '/elevage/escargots')->assertSee('Nés (Éclosions)')->assertSee('Naissain')->assertSee('Marchand (Immatures)');
    }

    // ------------------------------------------------------------------- Bande

    public function test_sans_bande_le_bandeau_propose_la_declaration(): void
    {
        $this->fiche($this->animalier())->assertSee('Aucune bande déclarée à cette date')->assertSee('Déclarer une Mise en Bande');
    }

    public function test_la_bande_en_cours_montre_son_code_son_cycle_et_son_effectif_indicatif(): void
    {
        $this->bande('B1'); // mise en place le 20/10 : le 09/11 est le jour 21 du cycle

        $this->fiche($this->animalier())->assertSee('Bande B1 — mise en place le 20/10/2026')
            ->assertSee('120 sujets mis en place · Enclos E2')->assertSeeHtml('data-cycle-jour>Jour de cycle J21<')
            ->assertSee('Clôturer la Bande')->assertSeeHtml('L\'effectif mis en place est indicatif');
    }

    public function test_une_bande_cloturee_avant_le_jour_ou_pas_encore_commencee_ne_couvre_pas_la_date(): void
    {
        $this->bande('B1', ['date_mise_en_bande' => '2026-09-01', 'date_cloture' => '2026-10-15']);
        $this->bande('B2', ['date_mise_en_bande' => '2026-12-01']);

        $this->fiche($this->animalier())->assertSee('Aucune bande déclarée à cette date');
    }

    public function test_de_deux_bandes_qui_se_chevauchent_la_plus_recente_est_retenue(): void
    {
        $this->bande('B1', ['date_mise_en_bande' => '2026-10-01']);
        $this->bande('B2', ['date_mise_en_bande' => '2026-11-03']);

        $this->fiche($this->animalier())->assertSee('Bande B2')->assertDontSee('Bande B1 —');
    }

    public function test_les_bandes_d_une_autre_filiere_sont_ignorees(): void
    {
        $this->bande('B1', ['espece' => 'pintades']);

        $this->fiche($this->animalier())->assertSee('Aucune bande déclarée à cette date');
    }

    // ---------------------------------------------------------------- Ecriture

    public function test_enregistrer_calcule_les_effectifs_depuis_la_veille_et_ecrit_par_le_web(): void
    {
        $this->journee('goliaths', '2026-11-08', ['effectif' => 100, 'eff_cat1_day' => 40, 'eff_cat2_day' => 30, 'eff_cat3_day' => 30]);
        $this->compteur((string) Str::uuid(), 'goliaths', '2026-11-09', 6);

        $this->fiche($this->animalier())
            ->set('achat', '20')->set('ne', '5')->set('morts.0', '2')->set('morts.2', '1')->set('dons.1', '3')
            ->set('poids', '1800')->set('observation', 'RAS')->set('traitementValide', true)
            ->call('enregistrer')
            ->assertSee('Saisie du jour 9 enregistrée avec succès.')->assertSet('erreur', null);

        $f = FicheJournee::query()->where('espece', 'goliaths')->where('date', '2026-11-09')->sole();
        $this->assertSame(UuidDeterministe::ficheJournee('goliaths', '2026-11-09'), $f->id);
        $this->assertSame(Catalogue::POSTE_WEB, $f->device_id);
        $this->assertTrue($f->is_recorded);
        $this->assertSame([20, 5, 6], [$f->achat, $f->ne, $f->vente], 'les ventes viennent du POS');
        // Poussins (recoit achats+nes) : 40 + 25 - 2 ; Goliathau (deduite des ventes) : 30 - 6 - 3 ; Mature : 30 - 1.
        $this->assertSame([63, 21, 29], [$f->eff_cat1_day, $f->eff_cat2_day, $f->eff_cat3_day]);
        // 100 + 20 + 5 - 3 morts - 6 ventes - 3 dons.
        $this->assertSame(113, $f->effectif);
        $this->assertSame(1800, $f->poids_general_g);
        $this->assertSame('RAS', $f->traitement_obs);
        $this->assertTrue($f->traitement_valide);
        $this->assertNull($f->mort_cat4, 'trois categories : pas de categorie 4');
        $this->assertEquals(now(), $f->serveur_modifie_le, 'le curseur de tirage avance : les postes la recevront');
    }

    public function test_sans_veille_les_effectifs_partent_de_zero(): void
    {
        $this->fiche($this->animalier())->set('achat', '10')->call('enregistrer');

        $f = FicheJournee::query()->sole();
        $this->assertSame(10, $f->effectif);
        $this->assertSame([10, 0, 0], [$f->eff_cat1_day, $f->eff_cat2_day, $f->eff_cat3_day]);
    }

    public function test_un_effectif_ne_devient_jamais_negatif(): void
    {
        $this->journee('goliaths', '2026-11-08', ['effectif' => 5, 'eff_cat1_day' => 5]);

        $this->fiche($this->animalier())->set('morts.0', '9')->call('enregistrer');

        $f = FicheJournee::query()->where('date', '2026-11-09')->sole();
        $this->assertSame(0, $f->effectif);
        $this->assertSame(0, $f->eff_cat1_day);
    }

    public function test_la_veille_est_la_derniere_journee_saisie_meme_d_un_autre_mois(): void
    {
        $this->journee('goliaths', '2026-10-28', ['effectif' => 70, 'eff_cat1_day' => 70]);
        $this->journee('goliaths', '2026-11-07', ['effectif' => 999, 'is_recorded' => false]); // non saisie : ignoree

        $this->fiche($this->animalier())->set('achat', '1')->call('enregistrer');

        $this->assertSame(71, FicheJournee::query()->where('date', '2026-11-09')->sole()->effectif);
    }

    public function test_la_cascade_recalcule_les_jours_suivants_deja_saisis_jusqu_au_premier_trou(): void
    {
        $this->journee('goliaths', '2026-11-05', ['effectif' => 10, 'eff_cat1_day' => 10, 'achat' => 10]);
        $this->journee('goliaths', '2026-11-06', ['effectif' => 12, 'eff_cat1_day' => 12, 'ne' => 2]);
        $this->journee('goliaths', '2026-11-07', ['effectif' => 11, 'eff_cat1_day' => 11, 'mort_cat1' => 1]);
        // 8 : trou (non saisi) ; 9 : saisi mais au-dela du trou, il ne doit pas etre recalcule.
        $this->journee('goliaths', '2026-11-08', ['effectif' => 0, 'is_recorded' => false]);
        $this->journee('goliaths', '2026-11-09', ['effectif' => 777, 'eff_cat1_day' => 777]);

        // On corrige le 5 : 10 achats -> 50.
        $this->fiche($this->animalier())->set('jour', '2026-11-05')->set('achat', '50')->call('enregistrer');

        $this->assertSame(50, FicheJournee::query()->where('date', '2026-11-05')->sole()->effectif);
        $this->assertSame(52, FicheJournee::query()->where('date', '2026-11-06')->sole()->effectif);
        $this->assertSame(51, FicheJournee::query()->where('date', '2026-11-07')->sole()->effectif);
        $this->assertSame(51, FicheJournee::query()->where('date', '2026-11-07')->sole()->eff_cat1_day);
        $this->assertSame(777, FicheJournee::query()->where('date', '2026-11-09')->sole()->effectif, 'au-dela du trou : intact');
    }

    public function test_les_jours_recalcules_par_la_cascade_sont_ecrits_par_le_web_et_redescendent(): void
    {
        $this->journee('goliaths', '2026-11-05', ['effectif' => 10, 'eff_cat1_day' => 10]);
        $suivant = $this->journee('goliaths', '2026-11-06', ['effectif' => 10, 'eff_cat1_day' => 10]);
        $avant = $suivant->serveur_modifie_le;

        $this->fiche($this->animalier())->set('jour', '2026-11-05')->set('achat', '5')->call('enregistrer');

        $suivant->refresh();
        $this->assertSame(Catalogue::POSTE_WEB, $suivant->device_id);
        $this->assertTrue($suivant->serveur_modifie_le->greaterThan($avant));
        $this->assertSame(5, $suivant->effectif, 'le 5 passe de 10 a 5 : le 6 le suit');
    }

    public function test_pondeuses_la_saisie_calcule_le_stock_d_oeufs_et_la_cascade_le_recalcule(): void
    {
        $this->activer('aviculture_classique');
        $quatre = ['mort_cat4' => 0, 'don_cat4' => 0, 'eff_cat4_day' => 0];
        $this->journee('pondeuses', '2026-11-07', $quatre + ['effectif' => 50, 'eff_cat1_day' => 50, 'stock_final_oeufs' => 40, 'oeufs_pondus' => 10, 'oeufs_casses' => 0, 'sorties_plateaux' => 0, 'srh' => 30, 'ts' => 55]);
        $this->journee('pondeuses', '2026-11-10', $quatre + ['effectif' => 50, 'eff_cat1_day' => 50, 'oeufs_pondus' => 20, 'oeufs_casses' => 0, 'sorties_plateaux' => 1, 'srh' => 0, 'ts' => 0, 'stock_final_oeufs' => 0]);
        $this->journee('pondeuses', '2026-11-09', $quatre + ['effectif' => 50, 'eff_cat1_day' => 50, 'oeufs_pondus' => 5, 'oeufs_casses' => 0, 'sorties_plateaux' => 0, 'srh' => 0, 'ts' => 5, 'stock_final_oeufs' => 5]);

        $this->fiche($this->animalier(), '/elevage/poulets-pondeuses')->call('choisirOnglet', 'pondeuses')
            ->set('jour', '2026-11-08')
            ->set('oeufsPondus', '100')->set('oeufsCasses', '10')->set('sortiesPlateaux', '2')
            ->call('enregistrer')->assertSet('erreur', null);

        $f = FicheJournee::query()->where('espece', 'pondeuses')->where('date', '2026-11-08')->sole();
        // SRH = Stock Final de la veille (40, et non son Total Stock de 55) ; TS = (100 - 10) + 40 ; sorties = 2 x 30 ; final = TS - sorties.
        $this->assertSame([40, 130, 70], [$f->srh, $f->ts, $f->stock_final_oeufs]);
        $this->assertSame([100, 10, 2], [$f->oeufs_pondus, $f->oeufs_casses, $f->sorties_plateaux]);
        $this->assertSame(0, $f->mort_cat4, 'pondeuses : quatre categories');

        // Cascade : le 9 repart du stock final du 8 (70) : TS = 5 + 70 ; le 10 enchaine, sorties 30.
        $neuf = FicheJournee::query()->where('espece', 'pondeuses')->where('date', '2026-11-09')->sole();
        $this->assertSame([70, 75, 75], [$neuf->srh, $neuf->ts, $neuf->stock_final_oeufs]);
        $dix = FicheJournee::query()->where('espece', 'pondeuses')->where('date', '2026-11-10')->sole();
        $this->assertSame([75, 95, 65], [$dix->srh, $dix->ts, $dix->stock_final_oeufs]);
    }

    public function test_hors_pondeuses_aucune_donnee_d_oeufs_n_est_ecrite(): void
    {
        $this->fiche($this->animalier())->set('achat', '3')->call('enregistrer');

        $f = FicheJournee::query()->sole();
        $this->assertNull($f->oeufs_pondus);
        $this->assertNull($f->stock_final_oeufs);
    }

    public static function saisiesInvalides(): array
    {
        return [
            'achat négatif' => [['achat' => '-1'], 'Les mouvements ne peuvent être négatifs.'],
            'nés négatifs' => [['ne' => '-4'], 'Les mouvements ne peuvent être négatifs.'],
            'mortalité négative' => [['morts.0' => '-2'], 'Mortalité Poussins invalide.'],
            'dons négatifs' => [['dons.1' => '-2'], 'Dons Goliathau invalide.'],
            'texte au lieu d\'un nombre' => [['achat' => 'beaucoup'], 'Chaque champ de la saisie doit être un nombre entier.'],
            'décimal' => [['morts.1' => '1.5'], 'Chaque champ de la saisie doit être un nombre entier.'],
        ];
    }

    /** @dataProvider saisiesInvalides */
    public function test_une_saisie_invalide_est_refusee_avec_le_message_du_dart_et_rien_n_est_ecrit(array $saisie, string $message): void
    {
        $c = $this->fiche($this->animalier());
        foreach ($saisie as $champ => $valeur) {
            $c->set($champ, $valeur);
        }

        $c->call('enregistrer')->assertSet('erreur', $message)->assertSee($message);

        $this->assertSame(0, FicheJournee::query()->count());
    }

    public function test_pondeuses_les_oeufs_casses_ne_depassent_pas_les_oeufs_pondus(): void
    {
        $this->activer('aviculture_classique');

        $this->fiche($this->animalier(), '/elevage/poulets-pondeuses')->call('choisirOnglet', 'pondeuses')
            ->set('oeufsPondus', '10')->set('oeufsCasses', '12')
            ->assertSee('Ne peut dépasser les œufs pondus.')
            ->call('enregistrer')->assertSet('erreur', 'Les œufs cassés (12) ne peuvent dépasser les œufs pondus (10).');

        $this->assertSame(0, FicheJournee::query()->count());
    }

    public function test_la_saisie_du_web_l_emporte_meme_si_l_horloge_d_un_poste_avait_de_l_avance(): void
    {
        // Un poste dont l'horloge avance d'une heure a ecrit ce jour : la saisie de l'utilisatrice du
        // web, faite APRES l'avoir vu, ne doit pas etre ignoree par « dernier ecrivain gagne ».
        $this->journee('goliaths', '2026-11-09', ['achat' => 1, 'effectif' => 1, 'eff_cat1_day' => 1, 'updated_at' => now()->addHour()]);

        $this->fiche($this->animalier())->set('achat', '40')->call('enregistrer')->assertSet('erreur', null);

        $f = FicheJournee::query()->sole();
        $this->assertSame(40, $f->achat);
        $this->assertTrue($f->updated_at->greaterThan(now()->addHour()));
    }

    public function test_ligne_entiere_une_pesee_effacee_efface_celle_du_poste(): void
    {
        $this->journee('goliaths', '2026-11-09', ['poids_general_g' => 1500, 'traitement_obs' => 'du poste']);

        $this->fiche($this->animalier())->set('poids', '')->set('observation', '')->call('enregistrer');

        $f = FicheJournee::query()->sole();
        $this->assertNull($f->poids_general_g);
        $this->assertNull($f->traitement_obs);
    }

    public function test_ressaisir_une_journee_ne_cree_pas_de_doublon(): void
    {
        $c = $this->fiche($this->animalier())->set('achat', '3')->call('enregistrer');
        $c->set('achat', '4')->call('enregistrer');

        $this->assertSame(1, FicheJournee::query()->count());
        $this->assertSame(4, FicheJournee::query()->sole()->achat);
    }

    // --------------------------------------------------------------- Bande : ecriture

    public function test_declarer_une_bande_propose_b1_puis_le_premier_numero_libre(): void
    {
        $c = $this->fiche($this->animalier())->call('ouvrirBande')->assertSet('bandeCode', 'B1')->assertSet('bandeDate', '2026-11-09');
        $c->call('declarerBande');

        $this->fiche($this->animalier())->call('ouvrirBande')->assertSet('bandeCode', 'B2');
        // Un « trou » : B2 est pris sous un autre numero d'ordre -> le premier numero libre apres le compte.
        $this->bande('B3');
        $this->fiche($this->animalier())->call('ouvrirBande')->assertSet('bandeCode', 'B4');
    }

    public function test_declarer_une_bande_l_ecrit_par_le_web_avec_ses_champs(): void
    {
        $this->fiche($this->animalier())->call('ouvrirBande')
            ->set('bandeCode', '  B7 ')->set('bandeDate', '2026-11-01')->set('bandeEffectif', '150')->set('bandeObservations', 'Enclos E3')
            ->call('declarerBande')->assertSet('erreurBande', null)->assertSet('formulaireBande', false)
            ->assertSee('Bande B7 déclarée.')->assertSee('Bande B7 — mise en place le 01/11/2026')->assertSeeHtml('data-cycle-jour>Jour de cycle J9<');

        $b = Bande::query()->sole();
        $this->assertSame(Catalogue::POSTE_WEB, $b->device_id);
        $this->assertSame(['goliaths', 'B7', '2026-11-01', 150, null, 'Enclos E3'],
            [$b->espece, $b->code, $b->date_mise_en_bande, $b->effectif_initial, $b->date_cloture, $b->observations]);
    }

    public function test_un_code_deja_pris_pour_la_filiere_est_refuse_avec_le_motif_du_serveur(): void
    {
        $this->bande('B1');

        $this->fiche($this->animalier())->call('ouvrirBande')->set('bandeCode', 'B1')->call('declarerBande')
            ->assertSet('erreurBande', 'Ce code de bande est déjà utilisé pour cette filière.')->assertSet('formulaireBande', true);

        $this->assertSame(1, Bande::query()->count());
    }

    public static function bandesInvalides(): array
    {
        return [
            'code vide' => [['bandeCode' => ' '], 'Le code de la bande est obligatoire.'],
            'date invalide' => [['bandeDate' => '2026-02-30'], 'La date de mise en place de la bande est invalide.'],
            'effectif négatif' => [['bandeEffectif' => '-5'], 'L\'effectif mis en place ne peut pas être négatif.'],
            'effectif en texte' => [['bandeEffectif' => 'beaucoup'], 'L\'effectif mis en place doit être un nombre entier.'],
        ];
    }

    /** @dataProvider bandesInvalides */
    public function test_une_bande_invalide_est_refusee_avec_son_motif(array $saisie, string $motif): void
    {
        $c = $this->fiche($this->animalier())->call('ouvrirBande');
        foreach ($saisie as $champ => $valeur) {
            $c->set($champ, $valeur);
        }

        $c->call('declarerBande')->assertSet('erreurBande', $motif);

        $this->assertSame(0, Bande::query()->count());
    }

    public function test_cloturer_la_bande_pose_la_date_du_jour_apres_confirmation(): void
    {
        $b = $this->bande('B1');

        $c = $this->fiche($this->animalier())->call('demanderCloture')->assertSet('confirmerCloture', true)
            ->assertSee('Clôturer la Bande ?')->assertSee('Bande B1');
        $this->assertNull($b->fresh()->date_cloture, 'rien tant que la modale n\'est pas confirmee');

        $c->call('cloturerBande')->assertSet('confirmerCloture', false)->assertSee('Bande B1 clôturée.');

        $this->assertSame('2026-11-09', $b->fresh()->date_cloture);
        $this->assertSame(Catalogue::POSTE_WEB, $b->fresh()->device_id);
        // Le lendemain, la bande ne couvre plus la date.
        $c->set('jour', '2026-11-10')->assertSee('Aucune bande déclarée à cette date');
    }

    public function test_la_cloture_est_datee_d_aujourd_hui_meme_quand_on_consulte_un_autre_jour(): void
    {
        $b = $this->bande('B1');

        $this->fiche($this->animalier())->set('jour', '2026-11-05')->call('demanderCloture')->call('cloturerBande');

        $this->assertSame('2026-11-09', $b->fresh()->date_cloture, 'comme au poste : « le cycle s\'arrete a aujourd\'hui »');
    }

    public function test_annuler_ferme_les_modales_sans_rien_ecrire(): void
    {
        $this->bande('B1');
        $c = $this->fiche($this->animalier())->call('demanderCloture')->call('annuler')->assertSet('confirmerCloture', false);
        $c->call('ouvrirBande')->call('annuler')->assertSet('formulaireBande', false);

        $this->assertNull(Bande::query()->sole()->date_cloture);
    }

    public function test_cloturer_sans_bande_en_cours_le_dit(): void
    {
        $this->fiche($this->animalier())->call('cloturerBande')->assertSet('erreur', 'Aucune bande en cours.');
    }

    // -------------------------------------------------------------------- Droits

    public static function methodesQuiEcrivent(): array
    {
        return [['enregistrer'], ['ouvrirBande'], ['declarerBande'], ['demanderCloture'], ['cloturerBande']];
    }

    /** @dataProvider methodesQuiEcrivent */
    public function test_sans_le_droit_de_gerer_l_elevage_aucune_methode_n_ecrit(string $methode): void
    {
        $this->fiche($this->lecteur())->call($methode)->assertForbidden();
        $this->assertSame(0, FicheJournee::query()->count());
        $this->assertSame(0, Bande::query()->count());
    }

    public function test_en_lecture_seule_aucun_bouton_n_est_propose(): void
    {
        $this->bande('B1');
        $this->fiche($this->lecteur())->assertDontSee('Enregistrer')->assertDontSee('Clôturer la Bande')->assertDontSee('Déclarer une Mise en Bande')
            ->assertSee('Bande B1');
    }

    public function test_un_module_desactive_apres_l_ouverture_de_la_page_bloque_l_ecriture(): void
    {
        $this->activer('cuniculture');
        $c = $this->fiche($this->animalier(), '/elevage/lapins')->set('achat', '3');
        ModuleActif::query()->where('module_id', 'cuniculture')->update(['is_actif' => false]);

        $c->call('enregistrer')->assertNotFound();
        $this->assertSame(0, FicheJournee::query()->count());
    }

    public function test_une_route_etrangere_a_l_ecran_est_refusee(): void
    {
        $this->fiche($this->animalier(), '/elevage/couveuse')->assertNotFound();
    }

    // -------------------------------------------------------------------- Routes

    public function test_les_routes_declarees_sont_les_huit_ecrans_convertis(): void
    {
        $declarees = \App\Support\Ecrans::declarees();
        foreach (array_keys(FicheEspece::ROUTES) as $route) {
            $this->assertContains($route, $declarees);
        }
        $this->assertContains('/elevage/dashboard', $declarees);
        $this->assertNotContains('/elevage/couveuse', $declarees, 'couveuse : autre tranche');
    }
}
