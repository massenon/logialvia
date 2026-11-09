<?php

namespace Tests\Feature\Web;

use App\Livewire\Achats;
use App\Models\Achat;
use App\Models\Fournisseur;
use App\Models\LigneAchat;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Achats & Commandes » : lecture seule (la reception et le reglement restent au poste). */
class AchatsWebTest extends TestCase
{
    use RefreshDatabase;

    private int $sequence = 0;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
    }

    private function utilisateur(string $role, string $username = 'u'): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    private function fournisseur(string $nom = 'Agri Plus'): Fournisseur
    {
        $f = (new Fournisseur)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => $nom,
            'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ]);
        $f->save();

        return $f;
    }

    private function achat(Fournisseur $f, array $surcharge = []): Achat
    {
        $this->sequence++;
        $a = (new Achat)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(),
            'reference' => sprintf('ACH-P1-2026-%03d', $this->sequence), 'portee_reference' => '',
            'fournisseur_id' => $f->id, 'date_achat' => now(), 'statut' => 'Livré',
            'total' => 10000, 'paye' => 4000, 'mode' => 'Espèces',
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $a->save();

        return $a;
    }

    private function ligne(Achat $a, array $surcharge = []): LigneAchat
    {
        $l = (new LigneAchat)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'achat_id' => $a->id, 'intrant_code' => 'INT-001',
            'nom' => 'Maïs grain', 'qte' => 20, 'pu_achat' => 250,
        ], $surcharge));
        $l->save();

        return $l;
    }

    // ------------------------------------------------------------------- Acces

    public function test_visiteur_animalier_et_caissier_n_ouvrent_pas_la_page(): void
    {
        $this->get('/achats')->assertRedirect(route('login'));
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/achats')->assertForbidden();
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get('/achats')->assertForbidden();
    }

    public function test_le_comptable_consulte_sans_aucune_action_et_l_admin_voit_la_declaration_du_stock(): void
    {
        $f = $this->fournisseur();
        $a = $this->achat($f, ['statut' => 'Commandé', 'total' => 8000, 'paye' => 0]);
        $this->ligne($a);

        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/achats')->assertOk()
            ->assertSee('Achats &amp; Commandes', false)->assertDontSee('arrive bientôt')
            ->assertSeeHtml('data-ecart="lecture-seule"')->assertDontSeeHtml('data-ecart="stock-poste"')
            ->assertDontSee('Nouvelle commande')->assertDontSee('Réceptionner')->assertDontSee('Régler')
            ->assertDontSeeHtml('data-action="modifier"')->assertDontSeeHtml('data-action="annuler-commande"')
            ->assertSee('Imprimer / PDF')->assertSeeHtml('data-action="bon-de-commande"');

        $this->actingAs($this->utilisateur('admin', 'chef'))->get('/achats')->assertOk()
            ->assertSeeHtml('data-ecart="stock-poste"')->assertDontSeeHtml('data-ecart="lecture-seule"')
            ->assertSee('aucun stock ni PMP à jour', false)
            ->assertSeeHtml('data-action="nouvelle-commande"')->assertSeeHtml('data-action="receptionner"')
            ->assertSeeHtml('data-action="modifier"')->assertSeeHtml('data-action="annuler-commande"')
            ->assertSeeHtml('data-action="regler"');
    }

    // ----------------------------------------------------------------- Lecture

    public function test_les_kpis_viennent_des_achats(): void
    {
        $f = $this->fournisseur();
        $this->achat($f, ['statut' => 'Commandé', 'total' => 8000, 'paye' => 0]);
        $this->achat($f, ['statut' => 'Commandé', 'total' => 2000, 'paye' => 0, 'date_achat' => now()->subMonths(3)]);
        $this->achat($f, ['statut' => 'Livré', 'total' => 5000]);
        $this->achat($f, ['statut' => 'Annulé', 'total' => 9000]);
        $this->achat($f, ['statut' => 'Livré', 'total' => 7000, 'date_achat' => now()->subMonths(2)]);

        Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)
            ->assertSeeHtml('data-kpi="en-cours">2<')
            ->assertSeeHtml('data-kpi="engage">10 000 ')        // 8000 + 2000 : commandes non receptionnees
            ->assertSeeHtml('data-kpi="mois">13 000 ');         // 8000 + 5000 : ni annule ni ancien
    }

    public function test_la_liste_montre_total_paye_solde_statut_et_anciennete(): void
    {
        $f = $this->fournisseur('Provende SA');
        $this->achat($f, ['reference' => 'ACH-P1-2026-100', 'date_achat' => now()->subDays(15), 'mode' => 'Mobile Money']);
        $this->achat($f, ['reference' => 'ACH-P1-2026-101', 'total' => 5000, 'paye' => 5000, 'mode' => null]);
        $this->achat($f, ['reference' => 'ACH-P1-2026-102', 'statut' => 'Annulé', 'total' => 3000, 'paye' => 0]);
        $this->achat($f, ['reference' => 'ACH-P1-2026-103', 'statut' => 'Commandé', 'total' => 2000, 'paye' => 0, 'date_achat' => now()->subDays(2)]);

        Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)
            ->assertSeeHtmlInOrder(['data-achat="ACH-P1-2026-100"', 'Provende SA', 'Mobile Money', 'Livré', '10 000', '4 000', '6 000 F', '15 j'])
            ->assertSeeHtml('bg-error-container text-error-deep">15 j<')
            ->assertSeeHtmlInOrder(['data-achat="ACH-P1-2026-101"', '5 000', '5 000', 'Soldée'])
            ->assertSeeHtmlInOrder(['data-achat="ACH-P1-2026-102"', 'Annulé', '3 000', 'Soldée'])   // annule : rien a payer
            ->assertSeeHtmlInOrder(['data-achat="ACH-P1-2026-103"', 'Commandé', '2 000', '2 000 F', '2 j'])
            ->assertSeeHtml('bg-surface-zebra text-outline">2 j<')
            ->assertSeeHtml('bg-success-container text-success-deep" data-statut>Livré<');
    }

    public function test_un_achat_annule_ou_surpaye_n_a_aucun_solde_du(): void
    {
        $f = $this->fournisseur();
        $this->achat($f, ['reference' => 'ACH-P1-2026-100', 'statut' => 'Annulé', 'total' => 3000, 'paye' => 0]);
        $this->achat($f, ['reference' => 'ACH-P1-2026-101', 'total' => 5000, 'paye' => 6000]);

        Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)
            ->assertSee('Soldée')->assertDontSee('-1 000')->assertDontSeeHtml('text-error-deep" data-solde')->assertDontSee('Reste')
            ->assertSeeHtml('<span class="text-outline">—</span>')           // pas d'anciennete sans dette
            ->assertDontSee(' j</span>', false);
    }

    public function test_la_date_s_affiche_au_fuseau_de_l_entreprise(): void
    {
        $f = $this->fournisseur();
        // 23 h 30 UTC = 00 h 30 le lendemain a Porto-Novo (UTC+1).
        $this->achat($f, ['date_achat' => '2026-03-10 23:30:00']);

        Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)
            ->assertSee('11/03/2026')->assertDontSee('10/03/2026');
    }

    public function test_les_achats_sont_du_plus_recent_au_plus_ancien(): void
    {
        $f = $this->fournisseur();
        $this->achat($f, ['reference' => 'ACH-P1-2026-100', 'date_achat' => now()->subDays(5)]);
        $this->achat($f, ['reference' => 'ACH-P1-2026-101', 'date_achat' => now()->subDay()]);

        Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)
            ->assertSeeHtmlInOrder(['data-achat="ACH-P1-2026-101"', 'data-achat="ACH-P1-2026-100"']);
    }

    public function test_un_fournisseur_supprime_garde_son_nom_sur_ses_achats(): void
    {
        $f = $this->fournisseur('Ancien fournisseur');
        $f->forceFill(['supprime_le' => now()])->save();
        $this->achat($f, ['reference' => 'ACH-P1-2026-100']);

        Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)
            ->assertSeeHtmlInOrder(['data-achat="ACH-P1-2026-100"', 'Ancien fournisseur']);
    }

    public function test_les_filtres_statut_et_recherche(): void
    {
        $a = $this->fournisseur('Agri Plus');
        $b = $this->fournisseur('Provende SA');
        $this->achat($a, ['reference' => 'ACH-P1-2026-100', 'statut' => 'Livré']);
        $this->achat($b, ['reference' => 'ACH-P1-2026-101', 'statut' => 'Commandé']);
        $this->achat($b, ['reference' => 'ACH-P1-2026-102', 'statut' => 'Annulé']);

        Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)
            ->set('statut', 'Commandé')
            ->assertSeeHtml('data-achat="ACH-P1-2026-101"')
            ->assertDontSeeHtml('data-achat="ACH-P1-2026-100"')->assertDontSeeHtml('data-achat="ACH-P1-2026-102"')
            ->set('statut', 'Annulé')
            ->assertSeeHtml('data-achat="ACH-P1-2026-102"')->assertDontSeeHtml('data-achat="ACH-P1-2026-101"')
            ->set('statut', 'Statut inconnu')                                   // ignore : tous
            ->assertSeeHtml('data-achat="ACH-P1-2026-100"')->assertSeeHtml('data-achat="ACH-P1-2026-102"')
            ->set('statut', '')
            ->set('recherche', 'provende')
            ->assertSeeHtml('data-achat="ACH-P1-2026-101"')->assertDontSeeHtml('data-achat="ACH-P1-2026-100"')
            ->set('recherche', '100')
            ->assertSeeHtml('data-achat="ACH-P1-2026-100"')->assertDontSeeHtml('data-achat="ACH-P1-2026-101"')
            ->set('recherche', 'provende')->set('statut', 'Annulé')             // les deux filtres se cumulent
            ->assertSeeHtml('data-achat="ACH-P1-2026-102"')->assertDontSeeHtml('data-achat="ACH-P1-2026-101"')
            ->set('recherche', 'zzz')->assertSee('Aucun achat ne correspond.');
    }

    public function test_les_kpis_ignorent_les_filtres(): void
    {
        $f = $this->fournisseur();
        $this->achat($f, ['statut' => 'Commandé', 'total' => 8000, 'paye' => 0]);
        $this->achat($f, ['statut' => 'Livré']);

        Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)
            ->set('statut', 'Livré')->assertSeeHtml('data-kpi="en-cours">1<');
    }

    public function test_sans_achat_l_etat_vide_est_affiche(): void
    {
        Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)
            ->assertSee('Aucune commande enregistrée.')
            ->assertSeeHtml('data-kpi="en-cours">0<');
    }

    public function test_le_detail_des_lignes_se_deplie_et_se_replie(): void
    {
        $f = $this->fournisseur();
        $a = $this->achat($f, ['reference' => 'ACH-P1-2026-100']);
        $autre = $this->achat($f, ['reference' => 'ACH-P1-2026-101']);
        $this->ligne($a, ['intrant_code' => 'INT-001', 'nom' => 'Maïs grain', 'qte' => 20, 'pu_achat' => 250]);
        $this->ligne($a, ['intrant_code' => 'INT-002', 'nom' => 'Soja', 'qte' => 2.5, 'pu_achat' => 400]);
        $this->ligne($autre, ['intrant_code' => 'INT-009', 'nom' => 'Sel']);

        Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)
            ->assertDontSeeHtml('data-lignes-de=')
            ->call('basculer', $a->id)
            ->assertSet('ouvert', $a->id)
            ->assertSeeHtml('data-lignes-de="ACH-P1-2026-100"')
            ->assertSeeHtmlInOrder(['data-ligne="INT-001"', 'Maïs grain', '20', '250 F', '5 000 F'])
            ->assertSeeHtml('font-bold">5 000 F</td>')->assertSeeHtml('font-bold">1 000 F</td>')
            ->assertSeeHtmlInOrder(['data-ligne="INT-002"', 'Soja', '2,5', '400 F', '1 000 F'])
            ->assertDontSeeHtml('data-ligne="INT-009"')
            ->call('basculer', $autre->id)->assertSeeHtml('data-ligne="INT-009"')->assertDontSeeHtml('data-ligne="INT-001"')
            ->call('basculer', $autre->id)->assertSet('ouvert', null)->assertDontSeeHtml('data-lignes-de=');
    }

    public function test_la_liste_est_plafonnee_comme_sur_le_poste(): void
    {
        $f = $this->fournisseur();
        for ($i = 0; $i < Achats::LIMITE + 5; $i++) {
            $this->achat($f, ['date_achat' => now()->subMinutes($i)]);
        }

        $html = Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)->html();
        $this->assertSame(Achats::LIMITE, substr_count($html, 'data-achat="'));
    }

    // ------------------------------------------------------------ Lecture seule

    public function test_aucun_bouton_d_ecriture_et_aucune_ecriture_possible(): void
    {
        $f = $this->fournisseur();
        $a = $this->achat($f, ['statut' => 'Commandé', 'total' => 8000, 'paye' => 0]);
        $this->ligne($a);
        $avant = $a->fresh()->getAttributes();

        $c = Livewire::actingAs($this->utilisateur('comptable', 'compta'))->test(Achats::class)
            ->assertDontSee('Réceptionner')->assertDontSee('Valider la Commande')->assertDontSee('Régler')
            ->assertDontSee('Nouvelle commande')->assertDontSee('Supprimer');
        $c->call('basculer', $a->id);

        $this->assertSame($avant, $a->fresh()->getAttributes());
        $this->assertSame(1, Achat::query()->count());
        $this->assertSame(1, LigneAchat::query()->count());
    }
}
