<?php

namespace Tests\Feature\Sync;

use App\Models\PlanComptable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** Plan comptable : referentiel, le poste PROPOSE (type `compte_comptable`), le serveur decide. */
class PlanComptableDemandesTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
        $this->amorcerComptabilite();
    }

    private function compte(array $surcharge = []): array
    {
        return array_merge([
            'numero_compte' => '635', 'libelle' => 'Frais bancaires', 'classe' => '6', 'archive' => false,
        ], $surcharge);
    }

    private function demander(array $poste, array $compte, ?string $saisi = null, ?string $id = null)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $poste['device'],
            'demandes' => [[
                'id' => $id ?? (string) Str::uuid(),
                'type' => 'compte_comptable',
                'saisi_le' => $saisi ?? now()->format('Y-m-d\TH:i:s.u\Z'),
                'donnees' => $compte,
            ]],
        ]);
    }

    public function test_un_compte_propose_est_cree_et_decide(): void
    {
        $a = $this->poste('admin', 'gerante');

        $this->demander($a, $this->compte())->assertJsonPath('rejected', []);

        $c = PlanComptable::query()->find('635');
        $this->assertSame('Frais bancaires', $c->libelle);
        $this->assertGreaterThan($c->created_at, $c->updated_at, 'une demande acceptee DECIDE le compte');
        $this->assertNotNull($c->saisi_le);
    }

    public function test_les_comptes_semes_ne_sont_pas_decides(): void
    {
        foreach (PlanComptable::query()->get() as $c) {
            $this->assertEquals($c->created_at, $c->updated_at, "{$c->numero_compte} est une valeur de semis");
        }
    }

    public function test_renommer_un_compte_seme_le_decide_et_une_demande_identique_n_y_change_rien(): void
    {
        $a = $this->poste('admin', 'gerante');
        $identique = $this->compte(['numero_compte' => '624', 'libelle' => 'Transports']);

        $this->demander($a, $identique)->assertJsonPath('rejected', []);
        $c = PlanComptable::query()->find('624');
        $this->assertEquals($c->created_at, $c->updated_at, 'contenu identique : rien n\'est decide');

        $this->demander($a, $this->compte(['numero_compte' => '624', 'libelle' => 'Transports et déplacements']))
            ->assertJsonPath('rejected', []);
        $c = PlanComptable::query()->find('624')->fresh();
        $this->assertSame('Transports et déplacements', $c->libelle);
        $this->assertGreaterThan($c->created_at, $c->updated_at);
    }

    public function test_une_demande_plus_ancienne_est_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->demander($a, $this->compte(['libelle' => 'Récent']), now()->format('Y-m-d\TH:i:s.u\Z'));

        $this->demander($a, $this->compte(['libelle' => 'Ancien']), now()->subHour()->format('Y-m-d\TH:i:s.u\Z'))
            ->assertJsonPath('rejected.0.motif', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.');

        $this->assertSame('Récent', PlanComptable::query()->find('635')->libelle);
    }

    public function test_archiver_un_compte_est_une_demande_comme_une_autre(): void
    {
        $a = $this->poste('admin', 'gerante');

        $this->demander($a, $this->compte(['numero_compte' => '613', 'libelle' => 'Locations', 'classe' => '6', 'archive' => true]))
            ->assertJsonPath('rejected', []);

        $this->assertTrue(PlanComptable::query()->find('613')->archive);
    }

    public function test_numero_libelle_et_classe_sont_controles(): void
    {
        $a = $this->poste('admin', 'gerante');

        $this->demander($a, $this->compte(['numero_compte' => '999', 'classe' => '9']))
            ->assertJsonPath('rejected.0.motif', 'Un numéro de compte SYSCOHADA commence par un chiffre de 1 à 7.');
        $this->demander($a, $this->compte(['numero_compte' => '63x']))
            ->assertJsonPath('rejected.0.motif', 'Un numéro de compte SYSCOHADA commence par un chiffre de 1 à 7.');
        $this->demander($a, $this->compte(['libelle' => '']))
            ->assertJsonPath('rejected.0.motif', 'Le libellé est obligatoire.');
        $this->demander($a, $this->compte(['classe' => '7']))
            ->assertJsonPath('rejected.0.motif', 'Le numéro 635 ne peut pas appartenir à la classe 7.');
        $this->demander($a, $this->compte(['classe' => '8', 'numero_compte' => '635']))
            ->assertJsonPath('rejected.0.motif', 'La classe d\'un compte va de 1 à 7.');

        $this->assertFalse(PlanComptable::query()->whereKey('635')->exists());
    }

    public function test_un_compte_mouvemente_peut_etre_renomme_sans_toucher_a_ses_ecritures(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->pousserTable($a, 'ecriture_comptable', [$this->pieceComptable()]);

        $this->demander($a, $this->compte(['numero_compte' => '624', 'libelle' => 'Transports et déplacements']))
            ->assertJsonPath('rejected', []);

        $this->assertSame('Transports et déplacements', PlanComptable::query()->find('624')->libelle);
        $this->assertSame(1, \App\Models\EcritureComptable::query()->where('numero_compte', '624')->count());
        // Sa classe ne peut pas changer : elle EST le premier chiffre de son numero.
        $this->demander($a, $this->compte(['numero_compte' => '624', 'libelle' => 'X', 'classe' => '7']), now()->addMinute()->format('Y-m-d\TH:i:s.u\Z'))
            ->assertJsonPath('rejected.0.motif', 'Le numéro 624 ne peut pas appartenir à la classe 7.');
    }

    public function test_sans_gerer_la_comptabilite_la_demande_est_refusee(): void
    {
        $caissier = $this->poste('caissier');
        $comptable = $this->poste('comptable');

        $this->demander($caissier, $this->compte())
            ->assertJsonPath('rejected.0.motif', 'Droit insuffisant pour modifier le plan comptable.');
        $this->demander($comptable, $this->compte())->assertJsonPath('rejected', []);
    }

    public function test_une_demande_rejouee_rend_la_meme_issue(): void
    {
        $a = $this->poste('admin', 'gerante');
        $id = (string) Str::uuid();
        $this->demander($a, $this->compte(), null, $id)->assertJsonPath('accepted.0', $id);

        $this->demander($a, $this->compte(['libelle' => 'Autre']), null, $id)->assertJsonPath('accepted.0', $id);

        $this->assertSame('Frais bancaires', PlanComptable::query()->find('635')->libelle);
    }

    public function test_le_plan_redescend_vers_les_postes_apres_une_decision(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('comptable');
        $this->demander($a, $this->compte());

        $plan = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.plan_comptable'))->keyBy('numero_compte');

        $this->assertSame('Frais bancaires', $plan['635']['libelle']);
        $this->assertArrayHasKey('saisi_le', $plan['635']);
        $this->assertSame(25, $plan->count());
    }
}
