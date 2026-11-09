<?php

namespace Tests\Feature\Web;

use App\Livewire\FacturesMecef;
use App\Models\Facture;
use App\Models\LigneFacture;
use App\Models\ParametresEntreprise;
use App\Models\Poste;
use App\Models\User;
use Carbon\CarbonImmutable;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Écran web « Facturation MeCeF » : factures et avoirs en LECTURE SEULE (une facture est une pièce fiscale
 * émise par le poste, qui seul détient le jeton e-MECeF et transmet à la DGI : le web ne transmet RIEN).
 */
class FacturesMecefWebTest extends TestCase
{
    use RefreshDatabase;

    private int $n = 0;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        ParametresEntreprise::courant()->forceFill(['mecef_actif' => true])->save();
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-11-09 12:00:00', config('logialvia.fuseau')));
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

    private function caissier(): User
    {
        return $this->utilisateur('caissier', 'amina');
    }

    private function facture(array $surcharge = [], array $lignes = []): Facture
    {
        $this->n++;
        $f = (new Facture)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(),
            'reference' => sprintf('FV-P1-2026-%03d', $this->n), 'portee_reference' => '', 'type' => 'FV',
            'vente_ref' => null, 'origine_ref' => null, 'date_facture' => CarbonImmutable::now(),
            'client' => 'DOSSOU Félicité', 'total_ht' => 10000, 'total_taxe' => 1800, 'total_ttc' => 11800,
            'statut' => 'a_transmettre', 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $f->save();

        foreach ($lignes ?: [['designation' => 'Goliath mature', 'quantite' => 1, 'prix_unitaire_ht' => 10000, 'groupe_taxe' => 'B', 'taux_taxe' => 18, 'montant_ht' => 10000, 'montant_taxe' => 1800]] as $l) {
            (new LigneFacture)->forceFill($l + ['id' => (string) Str::uuid(), 'facture_id' => $f->id, 'unite' => null])->save();
        }

        return $f;
    }

    private function normalisee(array $surcharge = []): Facture
    {
        return $this->facture($surcharge + [
            'statut' => 'normalisee', 'code_mecef' => 'CODE-A', 'nim' => 'NIM-1', 'compteur' => '12/50',
            'lien_verification' => 'https://dgi.example/v/1', 'date_normalisation' => CarbonImmutable::now(),
        ]);
    }

    // ------------------------------------------------------------------- Accès

    public function test_visiteur_et_animalier_n_ouvrent_pas_la_page(): void
    {
        $this->get('/factures-mecef')->assertRedirect(route('login'));
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/factures-mecef')->assertForbidden();
    }

    public function test_le_caissier_le_comptable_et_l_admin_la_lisent_et_c_est_bien_l_ecran_converti(): void
    {
        $this->actingAs($this->caissier())->get('/factures-mecef')->assertOk()
            ->assertSee('Facturation MeCeF')->assertSee('Factures et avoirs')->assertDontSee('arrive bientôt');
        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/factures-mecef')->assertOk();
        $this->actingAs($this->utilisateur('admin', 'gerante'))->get('/factures-mecef')->assertOk();
    }

    public function test_le_module_mecef_suit_le_reglage_de_l_entreprise(): void
    {
        ParametresEntreprise::courant()->forceFill(['mecef_actif' => false])->save();

        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/factures-mecef')->assertNotFound();

        ParametresEntreprise::courant()->forceFill(['mecef_actif' => true])->save();
        $this->actingAs($this->utilisateur('comptable', 'compta2'))->get('/factures-mecef')->assertOk();
    }

    public function test_l_entree_de_la_barre_laterale_suit_aussi_le_reglage(): void
    {
        $caissier = $this->caissier();
        $this->actingAs($caissier)->get('/dashboard')->assertSee('Facturation MeCeF');

        ParametresEntreprise::courant()->forceFill(['mecef_actif' => false])->save();
        $this->actingAs($caissier)->get('/dashboard')->assertDontSee('Facturation MeCeF');
    }

    public function test_l_ecran_declare_ses_ecarts_avec_le_poste(): void
    {
        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->assertSeeHtml('data-ecart="factures-mecef"')
            ->assertSee('consultation')->assertSee('jeton')->assertSee('Le web ne transmet rien')
            ->assertSee('avoirs')->assertSee('export PDF')->assertSee('code de normalisation');
    }

    // --------------------------------------------------------------------- KPI

    public function test_le_facture_net_est_les_ventes_moins_les_avoirs_et_les_compteurs_suivent_les_statuts(): void
    {
        $this->facture(['total_ttc' => 11800]);                                         // à transmettre
        $this->normalisee(['total_ttc' => 5000]);                                       // normalisée
        $this->facture(['statut' => 'rejetee', 'erreur_transmission' => 'Réseau', 'total_ttc' => 2000]);
        $this->facture(['type' => 'FA', 'reference' => 'FA-P1-2026-001', 'origine_ref' => 'FV-P1-2026-001', 'motif' => 'Retour', 'total_ttc' => 3000]);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->assertSeeHtml('data-kpi="net">15 800 ')   // 11 800 + 5 000 + 2 000 − 3 000
            ->assertSeeHtml('data-kpi="a-transmettre">2<') // la facture à transmettre ET l'avoir (à transmettre aussi)
            ->assertSeeHtml('data-kpi="normalisees">1<')
            ->assertSeeHtml('data-kpi="rejetees">1<')
            // Les indicateurs portent sur TOUTES les factures, pas sur la liste filtrée (Dart).
            ->call('filtrer', 'normalisee')->set('recherche', 'introuvable')
            ->assertSeeHtml('data-kpi="net">15 800 ')->assertSeeHtml('data-kpi="a-transmettre">2<')
            ->assertSeeHtml('data-kpi="normalisees">1<')->assertSeeHtml('data-kpi="rejetees">1<');
    }

    public function test_un_avoir_se_retranche_il_ne_s_additionne_pas(): void
    {
        $this->facture(['total_ttc' => 10000]);
        $this->facture(['type' => 'FA', 'reference' => 'FA-P1-2026-001', 'origine_ref' => 'FV-P1-2026-001', 'motif' => 'Retour', 'total_ttc' => 10000]);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)->assertSeeHtml('data-kpi="net">0 ');
    }

    public function test_normalisee_exige_un_code_rendu_par_la_dgi_pas_le_seul_statut(): void
    {
        $this->normalisee();
        // Statut « normalisée » sans code : ce que le Dart appelle un mensonge sur le document imprimé.
        $this->facture(['statut' => 'normalisee', 'code_mecef' => '  ', 'nim' => 'N']);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)->assertSeeHtml('data-kpi="normalisees">1<');
    }

    public function test_sans_facture_tout_est_a_zero(): void
    {
        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->assertSeeHtml('data-kpi="net">0 ')->assertSeeHtml('data-kpi="a-transmettre">0<')
            ->assertSeeHtml('data-kpi="normalisees">0<')->assertSeeHtml('data-kpi="rejetees">0<');
    }

    // ------------------------------------------------------------------- Liste

    public function test_la_liste_montre_colonnes_dates_locales_et_ordre_recent_d_abord(): void
    {
        $this->facture(['reference' => 'FV-ANCIENNE', 'date_facture' => CarbonImmutable::now()->subDays(5), 'total_ttc' => 1500]);
        $this->facture(['reference' => 'FV-RECENTE', 'client' => 'Kofi', 'total_ttc' => 12345]);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->assertSeeHtmlInOrder(['data-facture="FV-RECENTE"', 'FV-RECENTE', '09/11/2026', 'Kofi', '12 345 FCFA', 'À transmettre', 'data-facture="FV-ANCIENNE"', '04/11/2026'])
            ->assertSee('Référence')->assertSee('Total TTC')->assertSee('Statut');
    }

    public function test_la_date_se_lit_dans_le_fuseau_de_l_entreprise(): void
    {
        // 00:30 locale (UTC+1) = 23:30 UTC la veille : la facture est datée d'AUJOURD'HUI.
        $this->facture(['reference' => 'FV-NUIT', 'date_facture' => CarbonImmutable::parse('2026-11-09 00:30:00', config('logialvia.fuseau'))->utc()]);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->assertSeeHtmlInOrder(['data-facture="FV-NUIT"', '09/11/2026'])->assertDontSee('08/11/2026');
    }

    public function test_un_avoir_est_en_negatif_et_nomme_la_facture_qu_il_corrige(): void
    {
        $this->facture(['reference' => 'FV-P1-2026-001', 'total_ttc' => 11800]);
        $this->facture(['type' => 'FA', 'reference' => 'FA-P1-2026-001', 'origine_ref' => 'FV-P1-2026-001', 'motif' => 'Retour', 'total_ttc' => 11800]);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->assertSeeHtmlInOrder(['data-facture="FA-P1-2026-001"', 'sur FV-P1-2026-001', '-11 800 FCFA']);
    }

    public function test_la_pastille_de_statut_porte_le_libelle_du_poste_et_l_erreur_au_survol(): void
    {
        $this->facture(['reference' => 'FV-REJ', 'statut' => 'rejetee', 'erreur_transmission' => 'e-MECeF a refusé la facture (HTTP 422)']);
        $this->normalisee(['reference' => 'FV-OK']);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->assertSeeHtml('title="e-MECeF a refusé la facture (HTTP 422)"')
            ->assertSee('Rejetée')->assertSee('Normalisée')->assertSee('À transmettre', false);
    }

    public function test_la_liste_vide_affiche_les_messages_du_poste(): void
    {
        $caissier = $this->caissier();
        Livewire::actingAs($caissier)->test(FacturesMecef::class)
            ->assertSee('Aucune facture émise. Les factures émises depuis le poste apparaissent ici.');

        $this->facture();
        Livewire::actingAs($caissier)->test(FacturesMecef::class)
            ->set('recherche', 'introuvable')->assertSee('Aucune facture ne correspond à ces filtres.');
    }

    public function test_le_tableau_et_les_cartes_existent_pour_les_petits_ecrans(): void
    {
        $this->facture(['reference' => 'FV-X']);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->assertSeeHtml('data-table="factures"')->assertSeeHtml('data-carte-facture="FV-X"')->assertSeeHtml('data-vue="cartes"');
    }

    // ---------------------------------------------------------------- Filtres

    public function test_la_recherche_filtre_par_reference_ou_client_sans_casse(): void
    {
        $this->facture(['reference' => 'FV-P1-2026-AAA', 'client' => 'Amina Bako']);
        $this->facture(['reference' => 'FV-P1-2026-BBB', 'client' => 'Kofi']);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->set('recherche', 'kof')->assertSeeHtml('data-facture="FV-P1-2026-BBB"')->assertDontSeeHtml('data-facture="FV-P1-2026-AAA"')
            ->set('recherche', '2026-aaa')->assertSeeHtml('data-facture="FV-P1-2026-AAA"')->assertDontSeeHtml('data-facture="FV-P1-2026-BBB"')
            ->set('recherche', '  ')->assertSeeHtml('data-facture="FV-P1-2026-AAA"')->assertSeeHtml('data-facture="FV-P1-2026-BBB"');
    }

    public function test_les_jokers_sql_de_la_recherche_sont_litteraux(): void
    {
        $this->facture(['reference' => 'FV-1', 'client' => 'Amina']);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->set('recherche', '%')->assertDontSeeHtml('data-facture="FV-1"')
            ->set('recherche', '_')->assertDontSeeHtml('data-facture="FV-1"');
    }

    public function test_le_filtre_de_statut_se_combine_avec_la_recherche(): void
    {
        $this->facture(['reference' => 'FV-ATT', 'client' => 'Amina']);
        $this->normalisee(['reference' => 'FV-NOR', 'client' => 'Amina']);
        $this->facture(['reference' => 'FV-REJ', 'client' => 'Kofi', 'statut' => 'rejetee']);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->assertSeeHtml('data-facture="FV-REJ"')
            ->call('filtrer', 'normalisee')->assertSeeHtml('data-facture="FV-NOR"')
            ->assertDontSeeHtml('data-facture="FV-ATT"')->assertDontSeeHtml('data-facture="FV-REJ"')
            ->call('filtrer', 'rejetee')->assertSeeHtml('data-facture="FV-REJ"')->assertDontSeeHtml('data-facture="FV-NOR"')
            ->call('filtrer', 'a_transmettre')->assertSeeHtml('data-facture="FV-ATT"')->assertDontSeeHtml('data-facture="FV-REJ"')
            ->call('filtrer', 'normalisee')->set('recherche', 'Kofi')->assertDontSeeHtml('data-facture="FV-NOR"')->assertDontSeeHtml('data-facture="FV-REJ"')
            ->call('filtrer', 'inconnu')->set('recherche', '')->assertSeeHtml('data-facture="FV-ATT"')->assertSeeHtml('data-facture="FV-NOR"')->assertSeeHtml('data-facture="FV-REJ"')
            ->call('filtrer', 'a_transmettre')->call('filtrer', '')->assertSeeHtml('data-facture="FV-REJ"');
    }

    public function test_les_filtres_marquent_le_bouton_actif(): void
    {
        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->assertSeeHtml('data-filtre="toutes" aria-pressed="true"')
            ->call('filtrer', 'rejetee')
            ->assertSeeHtml('data-filtre="rejetee" aria-pressed="true"')->assertSeeHtml('data-filtre="toutes" aria-pressed="false"')
            ->call('filtrer', 'inconnu')
            ->assertSeeHtml('data-filtre="toutes" aria-pressed="true"')->assertSeeHtml('data-filtre="rejetee" aria-pressed="false"');
    }

    // ------------------------------------------------------------------ Détail

    public function test_le_detail_d_une_facture_normalisee_montre_lignes_groupes_et_champs_de_la_dgi(): void
    {
        $poste = Poste::query()->create(['device_id' => ($device = (string) Str::uuid()), 'code' => 'P7']);
        $f = $this->normalisee([
            'reference' => 'FV-P2-2026-007', 'device_id' => $device, 'client_ifu' => '3201234567890', 'client_adresse' => 'Natitingou',
            'vente_ref' => 'V-P2-2026-004', 'total_ht' => 15000, 'total_taxe' => 1800, 'total_ttc' => 16800,
        ]);
        (new LigneFacture)->forceFill([
            'id' => (string) Str::uuid(), 'facture_id' => $f->id, 'designation' => 'Oeufs', 'quantite' => 5, 'unite' => 'plateau',
            'prix_unitaire_ht' => 1000, 'groupe_taxe' => 'A', 'taux_taxe' => 0, 'montant_ht' => 5000, 'montant_taxe' => 0,
        ])->save();

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->call('ouvrir', $f->id)
            ->assertSeeHtml('data-detail="FV-P2-2026-007"')->assertSee('Facture de vente FV-P2-2026-007')
            ->assertSee('3201234567890')->assertSee('Natitingou')->assertSee('V-P2-2026-004')
            ->assertSee('CODE-A')->assertSee('NIM-1')->assertSee('12/50')->assertSee('https://dgi.example/v/1')
            ->assertSee('Émise sur')->assertSee('P7')
            ->assertSeeHtmlInOrder(['Goliath mature', 'Oeufs × 5 plateau'])
            ->assertSeeHtml('data-groupe="A"')->assertSeeHtml('data-groupe="B"')
            ->assertSeeHtml('data-total="ht">15 000 FCFA')->assertSeeHtml('data-total="taxe">1 800 FCFA')->assertSeeHtml('data-total="ttc">16 800 FCFA')
            ->call('fermer')->assertDontSeeHtml('data-detail=');
        $this->assertNotNull($poste->id);
    }

    public function test_les_totaux_par_groupe_cumulent_base_et_taxe_dans_l_ordre_des_lettres(): void
    {
        $f = $this->facture([], [
            ['designation' => 'L1', 'quantite' => 1, 'prix_unitaire_ht' => 100, 'groupe_taxe' => 'B', 'taux_taxe' => 18, 'montant_ht' => 100, 'montant_taxe' => 18],
            ['designation' => 'L2', 'quantite' => 1, 'prix_unitaire_ht' => 200, 'groupe_taxe' => 'B', 'taux_taxe' => 18, 'montant_ht' => 200, 'montant_taxe' => 36],
            ['designation' => 'L3', 'quantite' => 1, 'prix_unitaire_ht' => 50, 'groupe_taxe' => 'A', 'taux_taxe' => 0, 'montant_ht' => 50, 'montant_taxe' => 0],
        ]);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)->call('ouvrir', $f->id)
            ->assertSeeHtmlInOrder(['data-groupe="A"', 'base 50 · taxe 0', 'data-groupe="B"', 'base 300 · taxe 54']);
    }

    public function test_le_detail_d_une_facture_rejetee_montre_l_erreur_pas_de_code(): void
    {
        $f = $this->facture(['statut' => 'rejetee', 'erreur_transmission' => 'HTTP 422 : IFU invalide']);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)->call('ouvrir', $f->id)
            ->assertSee('Erreur de transmission')->assertSee('HTTP 422 : IFU invalide')->assertDontSeeHtml('>Code MeCeF</dt>');
    }

    public function test_le_detail_d_une_facture_a_transmettre_n_affiche_aucun_champ_de_la_dgi(): void
    {
        $f = $this->facture();

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)->call('ouvrir', $f->id)
            ->assertSee('Statut')->assertSee('À transmettre')
            ->assertDontSeeHtml('>Code MeCeF</dt>')->assertDontSeeHtml('>NIM</dt>')->assertDontSeeHtml('>Compteur</dt>');
    }

    public function test_le_detail_d_un_avoir_montre_le_motif_la_facture_corrigee_et_le_total_negatif(): void
    {
        $this->facture(['reference' => 'FV-P1-2026-001']);
        $avoir = $this->facture(['type' => 'FA', 'reference' => 'FA-P1-2026-001', 'origine_ref' => 'FV-P1-2026-001', 'motif' => 'Retour de marchandise', 'total_ttc' => 11800]);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)->call('ouvrir', $avoir->id)
            ->assertSee("Facture d'avoir FA-P1-2026-001")->assertSee('Facture corrigée')->assertSee('Retour de marchandise')
            ->assertSeeHtml('data-total="ttc">-11 800 FCFA');
    }

    public function test_un_poste_inconnu_se_lit_par_son_identifiant_tronque(): void
    {
        $f = $this->facture(['device_id' => '12345678-aaaa-bbbb-cccc-1234567890ab']);

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)->call('ouvrir', $f->id)->assertSee('Poste 12345678');
    }

    public function test_ouvrir_une_facture_inconnue_ne_montre_rien(): void
    {
        $this->facture();

        Livewire::actingAs($this->caissier())->test(FacturesMecef::class)
            ->call('ouvrir', (string) Str::uuid())->assertDontSeeHtml('data-detail=');
    }

    // ------------------------------------------------- Lecture seule, aucune transmission

    public function test_aucun_bouton_d_ecriture_aucune_ecriture_en_base_et_aucun_appel_reseau_meme_pour_l_admin(): void
    {
        Http::fake();
        $f = $this->facture();
        $this->normalisee();
        $etat = fn () => [
            Facture::query()->orderBy('reference')->get()->toArray(),
            LigneFacture::query()->orderBy('id')->get()->toArray(),
        ];
        $avant = $etat();

        Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(FacturesMecef::class)
            ->assertDontSee('Émettre une Facture')->assertDontSeeHtml('wire:click="transmettre')->assertDontSee('Transmettre à e-MECeF')
            ->assertDontSee('Saisir le code')->assertDontSee('Émettre un avoir')
            ->call('ouvrir', $f->id)->call('fermer')->call('filtrer', 'rejetee')->set('recherche', 'x');

        $this->assertSame($avant, $etat(), 'rien ne s\'écrit : ni statut, ni code, ni instant de saisie');
        Http::assertNothingSent();
    }

    public function test_le_composant_n_expose_aucune_methode_d_ecriture_ni_de_transmission(): void
    {
        $publiques = collect((new \ReflectionClass(FacturesMecef::class))->getMethods(\ReflectionMethod::IS_PUBLIC))
            ->filter(fn (\ReflectionMethod $m) => $m->class === FacturesMecef::class)->map->getName()->sort()->values()->all();

        $this->assertSame(['fermer', 'filtrer', 'ouvrir', 'render'], $publiques, 'lecture, filtre et détail : rien d\'autre');
    }

    public function test_le_composant_n_a_ni_jeton_ni_url_ni_client_http(): void
    {
        $code = fn (string $fichier) => preg_replace('~/\*.*?\*/|//[^\n]*|\{\{--.*?--\}\}~s', '', file_get_contents($fichier));
        $php = $code((new \ReflectionClass(FacturesMecef::class))->getFileName());
        $vue = $code(resource_path('views/livewire/factures-mecef.blade.php'));

        foreach (['Http', 'mecef_url', 'mecef_nim', 'jeton', 'curl', 'file_get_contents', 'ParametresEntreprise'] as $interdit) {
            $this->assertStringNotContainsStringIgnoringCase($interdit, $php, "le composant ne touche pas à : $interdit");
        }
        $this->assertStringNotContainsString('wire:click="transmettre', $vue);
        $this->assertStringNotContainsString('wire:submit', $vue, 'aucun formulaire : rien ne s\'écrit');
    }
}
