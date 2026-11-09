<?php

namespace Tests\Feature\Web;

use App\Livewire\DashboardElevage;
use App\Models\FicheJournee;
use App\Models\LigneVente;
use App\Models\ModuleActif;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Models\Vente;
use App\Support\UuidDeterministe;
use Carbon\CarbonImmutable;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/** Dashboard Elevage du web : filieres actives, recensement des fiches, ecarts declares, aucune ecriture. */
class DashboardElevageWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-11-18 10:00:00', 'UTC'));
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

    private function activer(string ...$modules): void
    {
        foreach ($modules as $module) {
            ModuleActif::query()->where('module_id', $module)->update(['is_actif' => true]);
        }
    }

    private function journee(string $espece, string $jour, array $surcharge = []): void
    {
        (new FicheJournee)->forceFill(array_merge([
            'id' => UuidDeterministe::ficheJournee($espece, $jour), 'device_id' => (string) Str::uuid(),
            'espece' => $espece, 'date' => $jour,
            'achat' => 0, 'ne' => 0, 'vente' => 0,
            'mort_cat1' => 0, 'mort_cat2' => 0, 'mort_cat3' => 0, 'mort_cat4' => null,
            'don_cat1' => 0, 'don_cat2' => 0, 'don_cat3' => 0, 'don_cat4' => null,
            'effectif' => 0, 'eff_cat1_day' => 0, 'eff_cat2_day' => 0, 'eff_cat3_day' => 0, 'eff_cat4_day' => null,
            'traitement_valide' => false, 'is_recorded' => true,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge))->save();
    }

    private function vendre(string $categorie, float $qte, float $pu, string $statut = 'Payée', string $quand = '2026-11-10 09:00:00'): void
    {
        $produit = (new ProduitVendable)->forceFill([
            'id' => (string) Str::uuid(), 'sku' => 'S'.Str::random(5), 'name' => 'P'.Str::random(4), 'cat' => $categorie,
            'price' => $pu, 'unit' => 'u', 'icon' => 'egg', 'groupe_taxe' => 'A', 'threshold' => 0,
            'saisi_le' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);
        $produit->save();
        $vente = (new Vente)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => 'V-P1-2026-'.Str::random(4),
            'portee_reference' => '', 'client' => 'Client', 'date_vente' => CarbonImmutable::parse($quand, 'UTC'),
            'mode' => 'Espèces', 'status' => $statut, 'total' => $qte * $pu, 'paye' => $qte * $pu,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $vente->save();
        (new LigneVente)->forceFill([
            'id' => (string) Str::uuid(), 'vente_id' => $vente->id, 'produit_id' => $produit->id, 'name' => $produit->name,
            'qte' => $qte, 'pu' => $pu, 'espece' => null,
        ])->save();
    }

    // ------------------------------------------------------------------- Acces

    public function test_visiteur_caissier_et_comptable_n_ouvrent_pas_le_dashboard(): void
    {
        $this->get('/elevage/dashboard')->assertRedirect(route('login'));
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get('/elevage/dashboard')->assertForbidden();
        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/elevage/dashboard')->assertForbidden();
    }

    public function test_l_animalier_et_l_administrateur_l_ouvrent_et_c_est_bien_l_ecran_converti(): void
    {
        foreach ([$this->utilisateur('animalier', 'eleveur'), $this->utilisateur('admin', 'gerante')] as $u) {
            $this->actingAs($u)->get('/elevage/dashboard')->assertOk()->assertSee('Dashboard Élevage')
                ->assertSee('Vue consolidée — filières actives et couveuse en un seul écran.')->assertDontSee('arrive bientôt');
        }
    }

    // ----------------------------------------------------------------- Lecture

    public function test_les_filieres_permanentes_sont_toujours_la_et_les_autres_suivent_leur_module(): void
    {
        $c = Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(DashboardElevage::class);
        $c->assertSeeHtml('data-filiere="goliaths"')->assertSeeHtml('data-filiere="pintades"')
            ->assertDontSeeHtml('data-filiere="lapins"')->assertDontSeeHtml('data-filiere="poulets"');

        $this->activer('cuniculture', 'aviculture_classique');
        $c = Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(DashboardElevage::class);
        $c->assertSeeHtml('data-filiere="lapins"')->assertSeeHtml('data-filiere="poulets"')
            ->assertDontSeeHtml('data-filiere="pondeuses"', 'comme le Dart : « aviculture classique » = poulets')
            ->assertDontSeeHtml('data-apercu="cuniculture"')->assertSeeHtml('data-apercu="pisciculture"');
    }

    public function test_une_carte_montre_la_derniere_journee_saisie_et_la_mortalite_du_mois(): void
    {
        // Mois en cours (novembre) : 1er jour saisi 100 apres 4 morts (base 104), puis 90 apres 4 morts.
        $this->journee('goliaths', '2026-11-02', ['effectif' => 100, 'mort_cat1' => 3, 'mort_cat3' => 1, 'eff_cat2_day' => 25, 'eff_cat3_day' => 25]);
        $this->journee('goliaths', '2026-11-12', ['effectif' => 90, 'mort_cat2' => 4, 'eff_cat2_day' => 20, 'eff_cat3_day' => 30]);
        $this->journee('goliaths', '2026-11-14', ['effectif' => 999, 'is_recorded' => false]);
        $this->journee('goliaths', '2026-10-30', ['effectif' => 555, 'mort_cat1' => 50]); // autre mois : hors mortalite

        $html = Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(DashboardElevage::class)
            ->assertSee('Goliathaux')->html();

        $carte = $this->carte($html, 'goliaths');
        $this->assertStringContainsString('data-chiffre="effectif">90<', $carte);
        $this->assertStringContainsString('data-chiffre="matures">30<', $carte);
        $this->assertStringContainsString('data-chiffre="jeunes">20<', $carte);
        $this->assertStringContainsString('data-chiffre="mortalite">7,7 %<', $carte); // 8 / 104
        $this->assertStringContainsString('text-error-deep" data-chiffre="mortalite"', $carte, '7,7 % >= 2 % : rouge');
    }

    public function test_une_mortalite_de_2_pour_cent_ou_plus_est_en_rouge_sinon_en_vert(): void
    {
        $this->journee('goliaths', '2026-11-02', ['effectif' => 98, 'mort_cat1' => 2]); // 2 / 100 = 2,0 %
        $this->journee('pintades', '2026-11-02', ['effectif' => 99, 'mort_cat1' => 1]); // 1 / 100 = 1,0 %

        $html = Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(DashboardElevage::class)->html();

        $this->assertStringContainsString('text-error-deep" data-chiffre="mortalite">2,0 %', $this->carte($html, 'goliaths'));
        $this->assertStringContainsString('text-success-deep" data-chiffre="mortalite">1,0 %', $this->carte($html, 'pintades'));
    }

    public function test_une_filiere_sans_saisie_le_dit_au_lieu_d_afficher_des_zeros(): void
    {
        $html = Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(DashboardElevage::class)->html();

        $this->assertStringContainsString('Aucune journée saisie pour cette filière.', $this->carte($html, 'goliaths'));
        $this->assertStringNotContainsString('data-chiffre', $this->carte($html, 'goliaths'));
    }

    public function test_chaque_carte_mene_a_la_fiche_de_sa_filiere(): void
    {
        $this->activer('cuniculture', 'aviculture_classique');

        Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(DashboardElevage::class)
            ->assertSeeHtml('href="/elevage/goliaths"')->assertSeeHtml('href="/elevage/pintades"')
            ->assertSeeHtml('href="/elevage/lapins"')->assertSeeHtml('href="/elevage/poulets-pondeuses"');
    }

    public function test_les_filieres_inactives_ont_leur_apercu_et_le_lien_vers_les_parametres_selon_le_droit(): void
    {
        $admin = Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(DashboardElevage::class);
        $admin->assertSee('Filière Cuniculture disponible — non activée pour le moment.')
            ->assertSee('Filière aviculture classique disponible — non activée pour le moment.')
            ->assertSee('Filière Pisciculture disponible — non activée pour le moment.')
            ->assertSee('Filière Héliciculture disponible — non activée pour le moment.')
            ->assertSee('Filière Bovins disponible — non activée pour le moment.')
            ->assertSee('Activer depuis Paramètres →');

        Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(DashboardElevage::class)
            ->assertSee('Filière Pisciculture disponible')->assertDontSee('Activer depuis Paramètres →');
    }

    public function test_les_donnees_absentes_du_serveur_sont_declarees_jamais_inventees(): void
    {
        $html = Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(DashboardElevage::class)->html();

        foreach (['Couveuse', 'Rappels Vétérinaires à Venir', 'Alertes Sanitaires du Jour'] as $carte) {
            $this->assertMatchesRegularExpression('#data-carte-poste="'.preg_quote($carte, '#').'".*?Disponible sur le poste#s', $html, $carte);
        }
        $this->assertStringContainsString('Gain Moyen Quotidien (GMQ) par Espèce', $html);
        $this->assertStringContainsString('data-bilan="couts">—<', $html);
        $this->assertStringContainsString('data-bilan="marge">—<', $html);
    }

    public function test_les_revenus_sont_les_ventes_avicoles_non_annulees_du_mois(): void
    {
        $this->vendre('Avicole', 2, 25000);                                   // 50 000
        $this->vendre('Avicole', 1, 10000, 'Payée', '2026-11-18 09:59:00');   // 10 000 (avant maintenant)
        $this->vendre('Commerce Annexe', 4, 1000);                            // hors elevage
        $this->vendre('Avicole', 3, 5000, 'Annulée');                         // annulee
        // Le mois se compte dans le fuseau de l'entreprise (UTC+1) : le 31/10 a 22h UTC est encore octobre.
        $this->vendre('Avicole', 1, 99000, 'Payée', '2026-10-31 22:00:00');   // mois precedent
        $this->vendre('Avicole', 1, 77000, 'Payée', '2026-11-19 09:00:00');   // apres maintenant

        Livewire::actingAs($this->utilisateur('animalier', 'eleveur'))->test(DashboardElevage::class)
            ->assertSeeHtml('data-bilan="revenus">60 000 ');
    }

    public function test_le_dashboard_n_ecrit_rien(): void
    {
        $this->journee('goliaths', '2026-11-02', ['effectif' => 10]);
        $avant = FicheJournee::query()->count();

        Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(DashboardElevage::class);

        $this->assertSame($avant, FicheJournee::query()->count());
        $propres = array_map(
            fn (\ReflectionMethod $m) => $m->getName(),
            array_filter(
                (new \ReflectionClass(DashboardElevage::class))->getMethods(\ReflectionMethod::IS_PUBLIC),
                fn (\ReflectionMethod $m) => $m->getDeclaringClass()->getName() === DashboardElevage::class,
            ),
        );
        $this->assertSame(['render'], array_values($propres), 'aucune methode publique d\'ecriture');
    }

    /** Le morceau de HTML de la carte d'une filiere. */
    private function carte(string $html, string $espece): string
    {
        $this->assertSame(1, preg_match('#<a href="[^"]*" data-filiere="'.$espece.'".*?</a>#s', $html, $m), "carte $espece");

        return $m[0];
    }
}
