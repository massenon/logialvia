<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\Clients;
use App\Models\Client;
use App\Models\User;
use App\Models\Vente;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Clients et Creances » : faits (dernier ecrivain gagne), solde derive, creances en lecture. */
class ClientsWebTest extends TestCase
{
    use RefreshDatabase;

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

    private function client(array $surcharge = []): Client
    {
        $c = (new Client)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => 'Amina Bako',
            'telephone' => '97000000', 'date_naissance' => null, 'dernier_contact' => now()->subDays(3),
            'solde_creance' => 0, 'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ], $surcharge));
        $c->save();

        return $c;
    }

    private function vente(Client $client, array $surcharge = []): Vente
    {
        $v = (new Vente)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => 'V-P1-2026-001',
            'portee_reference' => '', 'client' => $client->nom, 'client_id' => $client->id,
            'date_vente' => now()->subDays(2), 'mode' => 'Espèces', 'status' => 'Avance',
            'total' => 10000, 'paye' => 4000, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $v->save();

        return $v;
    }

    // ------------------------------------------------------------------- Acces

    public function test_visiteur_et_animalier_n_ouvrent_pas_la_page(): void
    {
        $this->get('/clients')->assertRedirect(route('login'));
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/clients')->assertForbidden();
    }

    public function test_le_caissier_et_le_comptable_l_ouvrent_et_c_est_bien_l_ecran_converti(): void
    {
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get('/clients')->assertOk()
            ->assertSee('Clients et Créances')->assertDontSee('arrive bientôt');
        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/clients')->assertOk();
    }

    // ----------------------------------------------------------------- Lecture

    public function test_kpis_clients_et_creances_viennent_de_la_base(): void
    {
        $a = $this->client(['nom' => 'Amina Bako', 'solde_creance' => 6000]);
        $this->client(['nom' => 'Kofi', 'telephone' => null]);
        $this->client(['nom' => 'Ancien client', 'supprime_le' => now()]);
        $this->vente($a);
        $this->vente($a, ['reference' => 'V-P1-2026-002', 'date_vente' => now()->subDays(15), 'total' => 5000, 'paye' => 0]);
        $this->vente($a, ['reference' => 'V-P1-2026-003', 'status' => 'Payée', 'paye' => 10000]);
        $this->vente($a, ['reference' => 'V-P1-2026-004', 'status' => 'Annulée', 'total' => 8000, 'paye' => 0]);

        Livewire::actingAs($this->utilisateur('caissier', 'amina'))->test(Clients::class)
            ->assertSeeHtml('data-kpi="clients">2<')
            ->assertSeeHtml('data-kpi="anciens">1<')
            ->assertSee('Amina Bako')->assertDontSee('Ancien client')
            ->assertSeeHtml('data-creance="V-P1-2026-001"')->assertSeeHtml('data-creance="V-P1-2026-002"')
            ->assertDontSeeHtml('data-creance="V-P1-2026-003"')->assertDontSeeHtml('data-creance="V-P1-2026-004"')
            ->assertSee('6 000 F')->assertSee('15 j');
    }

    public function test_les_anniversaires_des_7_prochains_jours_sont_listes(): void
    {
        $this->client(['nom' => 'Bientot', 'date_naissance' => now()->addDays(3)->subYears(30)->format('Y-m-d')]);
        $this->client(['nom' => 'Loin', 'date_naissance' => now()->addDays(20)->subYears(30)->format('Y-m-d')]);

        Livewire::actingAs($this->utilisateur('caissier', 'amina'))->test(Clients::class)
            ->assertSeeHtml('data-kpi="crm">1<')
            ->assertSeeHtmlInOrder(['data-table="crm"', 'Bientot'])
            ->assertDontSee('Aucun événement');
    }

    public function test_la_recherche_filtre_par_nom_ou_telephone(): void
    {
        $this->client(['nom' => 'Amina Bako', 'telephone' => '97000000']);
        $this->client(['nom' => 'Kofi', 'telephone' => '96111111']);

        Livewire::actingAs($this->utilisateur('caissier', 'amina'))->test(Clients::class)
            ->set('recherche', 'kof')->assertSeeHtml('data-client="Kofi"')->assertDontSeeHtml('data-client="Amina Bako"')
            ->set('recherche', '9700')->assertSeeHtml('data-client="Amina Bako"')->assertDontSeeHtml('data-client="Kofi"');
    }

    // ----------------------------------------------------------------- Ecriture

    public function test_un_client_ajoute_est_ecrit_comme_par_un_poste(): void
    {
        Livewire::actingAs($this->utilisateur('caissier', 'amina'))->test(Clients::class)
            ->call('nouveau')->set('nom', ' Fatou Diallo ')->set('telephone', '95000000')->set('dateNaissance', '1990-05-12')
            ->call('enregistrer')
            ->assertSet('erreur', null)->assertSet('formulaire', false)->assertSee('Client enregistré.');

        $c = Client::query()->where('nom', 'Fatou Diallo')->firstOrFail();
        $this->assertSame(Catalogue::POSTE_WEB, $c->device_id);
        $this->assertSame('1990-05-12', $c->date_naissance->format('Y-m-d'));
        $this->assertSame(0.0, $c->solde_creance, 'le solde est derive, jamais saisi');
        $this->assertTrue($c->serveur_modifie_le->greaterThan(now()->subMinute()));
    }

    public function test_un_nom_vide_ou_une_date_invalide_est_refuse_avec_le_message_du_serveur(): void
    {
        $composant = Livewire::actingAs($this->utilisateur('caissier', 'amina'))->test(Clients::class)->call('nouveau');

        $composant->set('nom', '')->call('enregistrer')
            ->assertSet('erreur', 'Le nom du client est obligatoire.')->assertSet('formulaire', true);
        $composant->set('nom', 'X')->set('dateNaissance', 'pas-une-date')->call('enregistrer')
            ->assertSet('erreur', 'La date de naissance est invalide.');

        $this->assertSame(0, Client::query()->count());
    }

    public function test_modifier_garde_le_dernier_contact_et_fait_avancer_le_curseur_des_postes(): void
    {
        $c = $this->client();
        $contact = $c->dernier_contact;
        $avant = $c->serveur_modifie_le;

        Livewire::actingAs($this->utilisateur('caissier', 'amina'))->test(Clients::class)
            ->call('modifier', $c->id)->assertSet('nom', 'Amina Bako')
            ->set('telephone', '98000000')->call('enregistrer')->assertSet('erreur', null);

        $c->refresh();
        $this->assertSame('98000000', $c->telephone);
        $this->assertEquals($contact, $c->dernier_contact);
        $this->assertTrue($c->serveur_modifie_le->greaterThan($avant), 'les postes la recevront au prochain tirage');
    }

    public function test_une_ecriture_du_web_l_emporte_sur_une_saisie_plus_ancienne_d_un_poste(): void
    {
        $c = $this->client(['updated_at' => now()->subHours(2)]);

        Livewire::actingAs($this->utilisateur('caissier', 'amina'))->test(Clients::class)
            ->call('modifier', $c->id)->set('nom', 'Nom du web')->call('enregistrer');

        $this->assertSame('Nom du web', $c->fresh()->nom);
    }

    public function test_la_suppression_est_douce_et_les_ventes_gardent_leur_client(): void
    {
        $c = $this->client();
        $v = $this->vente($c);
        $composant = Livewire::actingAs($this->utilisateur('caissier', 'amina'))->test(Clients::class);

        $composant->call('demanderSuppression', $c->id)->assertSee('Supprimer ce client ?');
        $this->assertNull($c->fresh()->supprime_le, 'rien tant que la modale n\'est pas confirmee');
        $composant->call('annuler')->assertDontSee('Supprimer ce client ?');

        $composant->call('demanderSuppression', $c->id)->call('confirmerSuppression')
            ->assertSee('supprimé')->assertDontSeeHtml('data-client="Amina Bako"');

        $this->assertNotNull($c->fresh()->supprime_le);
        $this->assertSame($c->id, $v->fresh()->client_id);
        $this->assertSame(1, Client::query()->count());
    }

    // -------------------------------------------------------------------- Droits

    public function test_le_comptable_consulte_sans_pouvoir_ecrire(): void
    {
        $c = $this->client();
        $comptable = $this->utilisateur('comptable', 'compta');

        Livewire::actingAs($comptable)->test(Clients::class)
            ->assertSee('Amina Bako')
            ->assertDontSee('Ajouter un Client')->assertDontSee('Modifier')->assertDontSee('Supprimer');

        $appel = fn (string $methode, array $args = []) => Livewire::actingAs($comptable)->test(Clients::class)
            ->call($methode, ...$args)->assertForbidden();
        $appel('nouveau');
        $appel('modifier', [$c->id]);
        $appel('demanderSuppression', [$c->id]);
        $appel('confirmerSuppression');
        $this->assertNull($c->fresh()->supprime_le);
    }
}
