<?php

namespace Tests\Feature\Sync;

use App\Models\Client;
use App\Models\ModuleActif;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** Tirage (pull) : curseur du serveur, pages stables, droits par table. */
class PullTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
        config(['logialvia.sync.recouvrement_secondes' => 0]);
    }

    private function client(array $attributs = []): Client
    {
        return Client::query()->create(array_merge([
            'id' => (string) Str::uuid(),
            'nom' => 'Client '.Str::random(4),
            'updated_at' => now(),
            'serveur_modifie_le' => now(),
        ], $attributs));
    }

    public function test_un_tirage_complet_rend_les_referentiels_et_les_clients(): void
    {
        $poste = $this->poste('caissier');
        $this->client(['nom' => 'Aïssatou']);

        $reponse = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->assertOk();

        $reponse->assertJsonStructure(['server_time', 'page', 'last_page', 'reset_mark', 'tables' => ['modules_actifs', 'parametres_entreprise', 'clients']]);
        $reponse->assertJsonPath('page', 1)->assertJsonPath('last_page', 1)->assertJsonPath('reset_mark', 'initiale');
        $this->assertCount(5, $reponse->json('tables.modules_actifs'));
        $this->assertCount(1, $reponse->json('tables.parametres_entreprise'));
        $this->assertSame('Aïssatou', $reponse->json('tables.clients.0.nom'));
        $this->assertMatchesRegularExpression('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/', $reponse->json('server_time'));
    }

    public function test_la_marque_de_remise_a_zero_n_est_pas_servie_comme_une_donnee(): void
    {
        $poste = $this->poste('caissier');

        $ligne = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->json('tables.parametres_entreprise.0');

        $this->assertArrayNotHasKey('marque_remise_a_zero', $ligne);
    }

    public function test_seules_les_tables_lisibles_par_le_compte_sont_servies(): void
    {
        $this->client();

        $caissier = $this->avecJeton($this->poste('caissier')['jeton'])->getJson('/api/sync/pull')->json('tables');
        $this->assertArrayHasKey('clients', $caissier);

        // L'animalier n'a pas view-ventes : la table n'est PAS servie (pas vide : absente).
        $animalier = $this->avecJeton($this->poste('animalier')['jeton'])->getJson('/api/sync/pull')->json('tables');
        $this->assertArrayNotHasKey('clients', $animalier);
        $this->assertArrayHasKey('modules_actifs', $animalier, 'Les referentiels sont lisibles par tous.');
    }

    public function test_since_ne_rend_que_ce_qui_a_change(): void
    {
        $poste = $this->poste('caissier');
        $this->client(['nom' => 'Ancien', 'serveur_modifie_le' => now()->subHour()]);

        $curseur = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->json('server_time');
        $this->travel(5)->seconds();
        $this->client(['nom' => 'Nouveau']);

        $noms = collect($this->avecJeton($poste['jeton'])->getJson('/api/sync/pull?since='.urlencode($curseur))->json('tables.clients'))->pluck('nom');

        $this->assertSame(['Nouveau'], $noms->all());
    }

    public function test_un_referentiel_modifie_redescend(): void
    {
        $poste = $this->poste('caissier');
        $curseur = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->json('server_time');
        $this->travel(5)->seconds();

        ModuleActif::query()->where('module_id', 'ovins')->update(['is_actif' => true]);

        $modules = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull?since='.urlencode($curseur))->json('tables.modules_actifs');
        $this->assertCount(1, $modules);
        $this->assertSame('ovins', $modules[0]['module_id']);
        $this->assertTrue($modules[0]['is_actif']);
    }

    public function test_le_recouvrement_reprend_une_ecriture_validee_juste_apres_la_lecture(): void
    {
        config(['logialvia.sync.recouvrement_secondes' => 2]);
        $poste = $this->poste('caissier');
        $curseur = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->json('server_time');

        // Ecriture dont l'instant de reception tombe 1 s AVANT le curseur : validee
        // apres la lecture du tirage precedent. Sans recouvrement, elle serait perdue.
        $this->client(['nom' => 'Tardif', 'serveur_modifie_le' => now()->subSecond()]);

        $noms = collect($this->avecJeton($poste['jeton'])->getJson('/api/sync/pull?since='.urlencode($curseur))->json('tables.clients'))->pluck('nom');
        $this->assertContains('Tardif', $noms->all());
    }

    // ------------------------------------------------------------ Pagination

    public function test_la_pagination_ne_perd_et_ne_duplique_aucune_ligne(): void
    {
        config(['logialvia.sync.lignes_par_page' => 3]);
        $poste = $this->poste('caissier');
        for ($i = 1; $i <= 7; $i++) {
            $this->client(['nom' => "C$i", 'serveur_modifie_le' => now()->subSeconds(100 - $i)]);
        }

        $page1 = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->assertJsonPath('last_page', 3)->json();
        $until = urlencode($page1['server_time']);
        $vus = collect($page1['tables']['clients'])->pluck('nom');
        foreach ([2, 3] as $page) {
            $suite = $this->avecJeton($poste['jeton'])->getJson("/api/sync/pull?page=$page&until=$until")->json();
            $vus = $vus->merge(collect($suite['tables']['clients'])->pluck('nom'));
            $this->assertSame($page1['server_time'], $suite['server_time'], 'Le curseur est le meme sur toutes les pages.');
        }

        $this->assertCount(7, $vus);
        $this->assertCount(7, $vus->unique(), 'Aucune ligne en double.');
    }

    public function test_une_ecriture_arrivee_entre_deux_pages_ne_decale_pas_les_pages(): void
    {
        config(['logialvia.sync.lignes_par_page' => 3]);
        $poste = $this->poste('caissier');
        for ($i = 1; $i <= 6; $i++) {
            $this->client(['nom' => "C$i", 'serveur_modifie_le' => now()->subSeconds(100 - $i)]);
        }

        $page1 = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->json();
        $until = urlencode($page1['server_time']);

        // Un autre poste ecrit PENDANT la pagination, avec un instant qui se glisserait
        // au milieu de l'ordre si les pages n'etaient pas figees.
        $this->travel(2)->seconds();
        $this->client(['nom' => 'Intrus', 'serveur_modifie_le' => now()]);

        $page2 = $this->avecJeton($poste['jeton'])->getJson("/api/sync/pull?page=2&until=$until")->json();
        $vus = collect($page1['tables']['clients'])->merge($page2['tables']['clients'])->pluck('nom');

        $this->assertSame(['C1', 'C2', 'C3', 'C4', 'C5', 'C6'], $vus->all());

        // L'intrus n'est pas perdu : il arrive au tirage suivant.
        $suivant = collect($this->avecJeton($poste['jeton'])->getJson('/api/sync/pull?since='.urlencode($page2['server_time']))->json('tables.clients'))->pluck('nom');
        $this->assertContains('Intrus', $suivant->all());
    }

    // ------------------------------------------------------------ Validation

    public function test_un_curseur_invalide_est_refuse(): void
    {
        $poste = $this->poste('caissier');

        $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull?since=pas-une-date')
            ->assertStatus(422)->assertJsonValidationErrors('since');
        $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull?page=0')
            ->assertStatus(422)->assertJsonValidationErrors('page');
    }

    public function test_sans_jeton_le_tirage_est_refuse(): void
    {
        $this->getJson('/api/sync/pull')->assertStatus(401);
    }

    public function test_les_pierres_tombales_redescendent(): void
    {
        $poste = $this->poste('caissier');
        $this->client(['nom' => 'Supprimé', 'supprime_le' => now()]);

        $ligne = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->json('tables.clients.0');

        $this->assertNotNull($ligne['supprime_le'], 'Une suppression doit se propager aux autres postes.');
    }
}
