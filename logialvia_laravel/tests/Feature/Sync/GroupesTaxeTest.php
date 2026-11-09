<?php

namespace Tests\Feature\Sync;

use App\Models\GroupeTaxe;
use App\Support\UuidDeterministe;
use App\Sync\MoteurSynchronisation;
use Database\Seeders\GroupesTaxeSeeder;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** P9 — la grille de taxation : référentiel semé à l'identique du poste, le serveur gagne. */
class GroupesTaxeTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    /** Valeurs figées : calculées par le Dart (`uuidDeterministe('groupe_taxe:A')`). */
    private const ID_A = 'cc7f16d2-cdc8-5c30-8f4b-d53be458e98c';

    private const ID_B = 'fd27a3e2-e56c-50d9-8212-1525b58e06cf';

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
        $this->seed(GroupesTaxeSeeder::class);
    }

    public function test_l_uuid_deterministe_est_celui_que_calcule_le_poste(): void
    {
        $this->assertSame(self::ID_A, UuidDeterministe::de('groupe_taxe:A'));
        $this->assertSame(self::ID_B, UuidDeterministe::de('groupe_taxe:B'));
        $this->assertMatchesRegularExpression('/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/', UuidDeterministe::de('autre'));
    }

    public function test_la_grille_est_semee_a_l_identique_du_poste(): void
    {
        $a = GroupeTaxe::query()->where('code', 'A')->first();
        $b = GroupeTaxe::query()->where('code', 'B')->first();

        $this->assertSame(2, GroupeTaxe::query()->count());
        $this->assertSame([self::ID_A, 'Exonéré', 0.0, 1], [$a->id, $a->libelle, $a->taux, $a->ordre]);
        $this->assertSame([self::ID_B, 'Taux normal 18 %', 18.0, 2], [$b->id, $b->libelle, $b->taux, $b->ordre]);
    }

    public function test_une_valeur_de_semis_a_created_at_egal_updated_at(): void
    {
        foreach (GroupeTaxe::query()->get() as $g) {
            $this->assertEquals($g->created_at, $g->updated_at, 'valeur de semis : jamais une décision du serveur');
        }
    }

    public function test_le_semis_est_idempotent_et_ne_reecrit_pas_un_groupe_corrige(): void
    {
        GroupeTaxe::query()->where('code', 'B')->update(['taux' => 19.0, 'libelle' => 'Taux corrigé']);

        $this->seed(GroupesTaxeSeeder::class);

        $this->assertSame(2, GroupeTaxe::query()->count());
        $b = GroupeTaxe::query()->where('code', 'B')->first();
        $this->assertSame([19.0, 'Taux corrigé'], [$b->taux, $b->libelle]);
    }

    public function test_deux_groupes_ne_partagent_pas_la_meme_lettre(): void
    {
        $this->expectException(QueryException::class);

        GroupeTaxe::query()->create(['code' => 'A', 'libelle' => 'Doublon', 'taux' => 5.0, 'ordre' => 9]);
    }

    public function test_la_grille_descend_vers_ceux_qui_voient_la_facturation(): void
    {
        $caissier = $this->poste('caissier', 'amina');

        $groupes = $this->avecJeton($caissier['jeton'])->getJson('/api/sync/pull')->assertOk()->json('tables.groupes_taxe');

        $this->assertCount(2, $groupes);
        $a = collect($groupes)->firstWhere('code', 'A');
        $this->assertSame(self::ID_A, $a['id']);
        $this->assertSame(0, $a['taux']);
        $this->assertSame($a['created_at'], $a['updated_at'], 'le poste reconnaît ainsi une valeur de semis');
    }

    public function test_un_envoi_du_poste_est_ignore_et_n_ecrit_rien(): void
    {
        $a = $this->poste('comptable', 'compta');

        $reponse = $this->avecJeton($a['jeton'])->postJson('/api/sync/push', [
            'device_id' => $a['device'],
            'reset_mark' => 'initiale',
            'tables' => ['groupes_taxe' => [[
                'id' => self::ID_B, 'code' => 'B', 'libelle' => 'Pirate', 'taux' => 99, 'ordre' => 2,
            ]]],
        ])->assertOk();

        $this->assertSame(self::ID_B, $reponse->json('groupes_taxe.ignored.0.id'));
        $this->assertStringContainsString('le serveur fait foi', $reponse->json('groupes_taxe.ignored.0.motif'));
        $this->assertSame(18.0, GroupeTaxe::query()->where('code', 'B')->first()->taux);
    }

    public function test_la_grille_est_servie_avant_les_factures(): void
    {
        $noms = array_map(fn ($t) => $t->nom(), app(MoteurSynchronisation::class)->tables());

        $this->assertLessThan(array_search('factures', $noms, true), array_search('groupes_taxe', $noms, true));
        $this->assertLessThan(array_search('groupes_taxe', $noms, true), array_search('ventes', $noms, true), 'après les ventes');
    }
}
