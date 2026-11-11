<?php

namespace Tests\Feature\Sync;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * « Vérifier la cohérence » du poste (`GET /api/sync/coherence`) : ce que le serveur a de plus récent que le
 * dernier tirage du poste. Lecture seule, mêmes tables et mêmes droits que le tirage.
 */
class CoherenceTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function pousserClient(array $poste, string $nom): void
    {
        $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => 'initiale',
            'tables' => ['clients' => [$this->ligneClient(['nom' => $nom])]],
        ])->assertOk();
    }

    private function coherence(array $poste)
    {
        return $this->avecJeton($poste['jeton'])->getJson('/api/sync/coherence?device_id='.$poste['device']);
    }

    public function test_un_poste_qui_n_a_jamais_tire_a_tout_a_recevoir(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $this->pousserClient($a, 'Client de A');

        $r = $this->coherence($b)->assertOk()->assertJsonPath('curseur', null);

        $this->assertSame(1, $r->json('retard.clients'));
        $this->assertGreaterThan(1, $r->json('total'), 'les référentiels semés (modules, plan comptable…) comptent aussi');
    }

    public function test_apres_un_tirage_complet_il_ne_reste_rien_a_recevoir(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $this->pousserClient($a, 'Client de A');

        // B tire (toutes les pages) : le serveur retient son curseur à la dernière page.
        $page = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull?device_id='.$b['device'])->assertOk()->json();
        $this->assertSame(1, $page['last_page']);

        $this->coherence($b)->assertOk()->assertJsonPath('total', 0)->assertJsonPath('retard', []);
        $this->assertNotNull($this->coherence($b)->json('curseur'));
    }

    public function test_une_ecriture_posterieure_au_tirage_apparait_comme_retard(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $this->avecJeton($b['jeton'])->getJson('/api/sync/pull?device_id='.$b['device'])->assertOk();

        $this->travel(2)->seconds();
        $this->pousserClient($a, 'Nouveau chez A');

        $r = $this->coherence($b)->assertOk();
        $this->assertSame(1, $r->json('retard.clients'));
        $this->assertSame(1, $r->json('total'));
    }

    public function test_le_poste_ne_peut_pas_se_faire_passer_pour_un_autre_et_il_faut_un_jeton(): void
    {
        $a = $this->poste('caissier', 'amina');

        $this->getJson('/api/sync/coherence')->assertUnauthorized();
        $this->avecJeton($a['jeton'])->getJson('/api/sync/coherence?device_id='.\Illuminate\Support\Str::uuid())
            ->assertStatus(403)->assertJsonPath('code', 'poste_different_du_jeton');
    }

    public function test_seules_les_tables_que_le_compte_lit_comptent(): void
    {
        $a = $this->poste('caissier', 'amina');
        $animalier = $this->poste('animalier', 'ange');
        $this->pousserClient($a, 'Client de A');

        $r = $this->coherence($animalier)->assertOk();

        $this->assertArrayNotHasKey('clients', (array) $r->json('retard'), 'un animalier ne lit pas les clients');
    }
}
