<?php

namespace Tests\Feature\Web;

use App\Livewire\Ventes;
use App\Models\LigneVente;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Models\Vente;
use Carbon\CarbonImmutable;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Ventes » : KPI, historique (liste, filtres, detail). La caisse, l'annulation et le recouvrement : `CommerceWebTest`. */
class VentesWebTest extends TestCase
{
    use RefreshDatabase;

    private int $n = 0;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        // Midi (heure de l'entreprise) : evite tout effet de bord autour de minuit.
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

    private function vente(array $surcharge = []): Vente
    {
        $this->n++;
        $v = (new Vente)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(),
            'reference' => sprintf('V-P1-2026-%03d', $this->n), 'portee_reference' => '',
            'client' => 'Amina Bako', 'client_id' => null,
            'date_vente' => CarbonImmutable::now(), 'mode' => 'Espèces', 'status' => 'Payée',
            'total' => 10000, 'paye' => 10000, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $v->save();

        return $v;
    }

    private function ligne(Vente $v, string $nom, float $qte, float $pu): void
    {
        $produit = ProduitVendable::query()->first() ?? ProduitVendable::query()->create([
            'name' => 'Produit', 'cat' => 'Divers', 'price' => 1, 'unit' => 'pièce', 'icon' => 'category', 'saisi_le' => now(),
        ]);
        (new LigneVente)->forceFill([
            'id' => (string) Str::uuid(), 'vente_id' => $v->id, 'produit_id' => $produit->id,
            'name' => $nom, 'qte' => $qte, 'pu' => $pu,
        ])->save();
    }

    private function caissier(): User
    {
        return $this->utilisateur('caissier', 'amina');
    }

    // ------------------------------------------------------------------- Acces

    public function test_visiteur_et_animalier_n_ouvrent_pas_la_page(): void
    {
        $this->get('/ventes')->assertRedirect(route('login'));
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/ventes')->assertForbidden();
    }

    public function test_le_caissier_et_le_comptable_l_ouvrent_et_c_est_bien_l_ecran_converti(): void
    {
        $this->actingAs($this->caissier())->get('/ventes')->assertOk()
            ->assertSee('Historique des Ventes')->assertDontSee('arrive bientôt');
        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/ventes')->assertOk();
    }

    public function test_l_ecran_declare_ses_ecarts_avec_le_poste(): void
    {
        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')
            ->assertSeeHtml('data-ecart="ventes"')->assertSee('Stock propre à chaque poste')
            ->assertSee('désigne donc un')->assertSee('décrémente SON stock')->assertSee('XLSX');
    }

    // --------------------------------------------------------------------- KPI

    public function test_kpi_ca_et_panier_moyen_du_jour_excluent_les_annulees_et_les_autres_jours(): void
    {
        $this->vente(['total' => 10000]);
        $this->vente(['total' => 5000, 'status' => 'Avance', 'paye' => 1000]);
        $this->vente(['total' => 99000, 'status' => 'Annulée']);
        $this->vente(['total' => 70000, 'date_vente' => CarbonImmutable::now()->subDay()]);

        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')
            ->assertSeeHtml('data-kpi="ca">15 000 ')
            ->assertSeeHtml('data-kpi="panier">7 500<')
            ->assertSeeHtml('data-kpi="attente">1<');
    }

    public function test_sans_vente_du_jour_le_panier_moyen_est_un_tiret(): void
    {
        $this->vente(['date_vente' => CarbonImmutable::now()->subDays(3)]);

        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')
            ->assertSeeHtml('data-kpi="ca">0 ')->assertSeeHtml('data-kpi="panier">—<')
            ->assertSee('Aucune vente aujourd\'hui');
    }

    public function test_le_jour_se_compte_dans_le_fuseau_de_l_entreprise_pas_en_utc(): void
    {
        // 00:30 locale (UTC+1) = 23:30 UTC la veille : c'est AUJOURD'HUI. 23:30 locale hier : non.
        $this->vente(['total' => 1000, 'date_vente' => CarbonImmutable::parse('2026-11-09 00:30:00', config('logialvia.fuseau'))->utc()]);
        $this->vente(['total' => 2000, 'date_vente' => CarbonImmutable::parse('2026-11-08 23:30:00', config('logialvia.fuseau'))->utc()]);
        $this->vente(['total' => 4000, 'date_vente' => CarbonImmutable::parse('2026-11-09 23:30:00', config('logialvia.fuseau'))->utc()]);
        $this->vente(['total' => 8000, 'date_vente' => CarbonImmutable::parse('2026-11-10 00:30:00', config('logialvia.fuseau'))->utc()]);

        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')->assertSeeHtml('data-kpi="ca">5 000 ');
    }

    public function test_les_ventes_en_attente_comptent_toutes_les_avances_de_tous_les_jours(): void
    {
        $this->vente(['status' => 'Avance', 'date_vente' => CarbonImmutable::now()->subDays(40)]);
        $this->vente(['status' => 'Avance']);
        $this->vente(['status' => 'Payée']);

        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')->assertSeeHtml('data-kpi="attente">2<');
    }

    // ------------------------------------------------------------------- Liste

    public function test_la_liste_montre_colonnes_dates_locales_et_ordre_recent_d_abord(): void
    {
        $this->vente(['reference' => 'V-ANCIEN', 'date_vente' => CarbonImmutable::now()->subDays(5), 'total' => 1500]);
        $this->vente(['reference' => 'V-RECENT', 'client' => 'Kofi', 'total' => 12345]);

        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')
            ->assertSeeHtmlInOrder(['data-vente="V-RECENT"', 'V-RECENT', '09/11/2026', 'Kofi', '12 345', 'Payée', 'data-vente="V-ANCIEN"', '04/11/2026'])
            ->assertSee('Référence')->assertSee('Montant')->assertSee('Statut');
    }

    public function test_la_liste_vide_affiche_le_message_du_poste(): void
    {
        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')->assertSee('Aucune vente ne correspond.');
    }

    public function test_la_recherche_filtre_par_reference_ou_client_sans_casse(): void
    {
        $this->vente(['reference' => 'V-P1-2026-AAA', 'client' => 'Amina Bako']);
        $this->vente(['reference' => 'V-P1-2026-BBB', 'client' => 'Kofi']);

        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')
            ->set('recherche', 'kof')->assertSeeHtml('data-vente="V-P1-2026-BBB"')->assertDontSeeHtml('data-vente="V-P1-2026-AAA"')
            ->set('recherche', '2026-aaa')->assertSeeHtml('data-vente="V-P1-2026-AAA"')->assertDontSeeHtml('data-vente="V-P1-2026-BBB"')
            ->set('recherche', '  ')->assertSeeHtml('data-vente="V-P1-2026-AAA"')->assertSeeHtml('data-vente="V-P1-2026-BBB"');
    }

    public function test_les_jokers_sql_de_la_recherche_sont_litteraux(): void
    {
        $this->vente(['reference' => 'V-1', 'client' => 'Amina']);

        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')
            ->set('recherche', '%')->assertDontSeeHtml('data-vente="V-1"')
            ->set('recherche', '_')->assertDontSeeHtml('data-vente="V-1"');
    }

    public function test_le_filtre_de_statut_et_la_recherche_se_combinent(): void
    {
        $this->vente(['reference' => 'V-PAYEE', 'client' => 'Amina', 'status' => 'Payée']);
        $this->vente(['reference' => 'V-AVANCE', 'client' => 'Amina', 'status' => 'Avance']);
        $this->vente(['reference' => 'V-ANNULEE', 'client' => 'Kofi', 'status' => 'Annulée']);

        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')
            ->assertSeeHtml('data-vente="V-ANNULEE"')
            ->set('statut', 'Avance')->assertSeeHtml('data-vente="V-AVANCE"')
            ->assertDontSeeHtml('data-vente="V-PAYEE"')->assertDontSeeHtml('data-vente="V-ANNULEE"')
            ->set('statut', 'Annulée')->assertSeeHtml('data-vente="V-ANNULEE"')->assertDontSeeHtml('data-vente="V-AVANCE"')
            ->set('statut', 'Payée')->set('recherche', 'Kofi')->assertDontSeeHtml('data-vente="V-PAYEE"')
            ->set('statut', 'inconnu')->set('recherche', '')->assertSeeHtml('data-vente="V-PAYEE"')->assertSeeHtml('data-vente="V-ANNULEE"');
    }

    // ------------------------------------------------------------------ Detail

    public function test_le_detail_montre_les_lignes_le_total_et_le_reste_du_d_une_avance(): void
    {
        $v = $this->vente(['status' => 'Avance', 'total' => 9000, 'paye' => 2500, 'mode' => 'Mobile Money', 'ligne_mobile_money' => 'MTN 97000000']);
        $this->ligne($v, 'Poulet', 3, 2000);
        $this->ligne($v, 'Oeufs', 1, 3000);
        $autre = $this->vente(['reference' => 'V-AUTRE']);
        $this->ligne($autre, 'Intrus', 1, 1);

        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')
            ->assertDontSeeHtml('data-detail=')
            ->call('ouvrir', $v->id)
            ->assertSeeHtml('data-detail="'.$v->reference.'"')
            ->assertSee('Vente '.$v->reference)->assertSee('Mobile Money')->assertSee('MTN 97000000')
            ->assertSee('Avance (Solde Restant Dû)')->assertSee('Reste dû')->assertSee('6 500 FCFA')
            ->assertSeeHtmlInOrder(['Oeufs × 1', '3 000', 'Poulet × 3', '6 000'])
            ->assertSee('9 000 FCFA')->assertDontSee('Intrus')
            ->call('fermer')->assertDontSeeHtml('data-detail=');
    }

    public function test_le_detail_d_une_vente_payee_est_comptant_et_celui_d_une_annulee_montre_le_motif(): void
    {
        $payee = $this->vente();
        $annulee = $this->vente(['status' => 'Annulée', 'motif_annulation' => 'Erreur de saisie', 'paye' => 0]);

        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')
            ->call('ouvrir', $payee->id)->assertSee('Comptant')->assertDontSee('Reste dû')->assertDontSee('Motif d\'annulation')
            ->call('ouvrir', $annulee->id)->assertSee('Motif d\'annulation')->assertSee('Erreur de saisie')->assertDontSee('Reste dû');
    }

    public function test_ouvrir_une_vente_inconnue_ne_montre_rien(): void
    {
        Livewire::actingAs($this->caissier())->test(Ventes::class)->set('onglet', 'historique')
            ->call('ouvrir', (string) Str::uuid())->assertSet('venteId', null)->assertDontSeeHtml('data-detail=');
    }

    // ------------------------------------------------------------- Consultation

    public function test_le_comptable_consulte_sans_aucun_bouton_d_ecriture_et_sans_rien_ecrire(): void
    {
        $v = $this->vente();
        $this->ligne($v, 'Poulet', 1, 10000);
        $avant = [Vente::query()->count(), LigneVente::query()->count(), $v->fresh()->getAttributes()];

        Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Ventes::class)
            ->assertSee('exige le droit de gérer les ventes')->assertDontSee('Encaisser la Vente')
            ->set('onglet', 'historique')->assertDontSeeHtml('data-action="annuler-vente"')->assertDontSeeHtml('data-action="modifier-vente"')
            ->set('recherche', 'x')->set('statut', 'Avance')->set('statut', '')->set('recherche', '')
            ->call('ouvrir', $v->id)->call('fermer');

        $this->assertSame($avant, [Vente::query()->count(), LigneVente::query()->count(), $v->fresh()->getAttributes()]);
    }
}
