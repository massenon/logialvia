<?php

namespace Tests\Feature\Sync;

use App\Models\Achat;
use App\Models\Poste;
use App\Models\Vente;
use App\Support\RechercheLike;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * Portabilite SQLite -> MySQL/MariaDB (`47r_`). Chaque essai ici a rougi sur MariaDB 10.11
 * AVANT sa correction ; sur SQLite il verrouille la forme portable (le job CI `mysql.yml`
 * rejoue toute la suite sur MySQL 8).
 */
class PortabiliteMysqlTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    public function test_la_recherche_contient_n_emploie_aucun_antislash_et_garde_les_jokers_litteraux(): void
    {
        // `escape '\'` ne se ferme pas en MySQL (le antislash echappe le guillemet).
        $sql = Vente::query()->tap(fn ($q) => RechercheLike::appliquer($q, ['reference', 'client'], '50%_x'))->toSql();

        $this->assertStringNotContainsString('\\', $sql);
        $this->assertStringContainsString("escape '!'", $sql);
        $this->assertSame('%50!%!_x%', RechercheLike::motif('50%_x'));
        $this->assertSame('%a!!b%', RechercheLike::motif('a!b'));
    }

    public function test_la_recherche_trouve_sans_confondre_les_jokers(): void
    {
        foreach (['V-1' => '100% laine', 'V-2' => '100 pour cent', 'V-3' => 'a_b'] as $ref => $client) {
            DB::table('ventes')->insert($this->venteMinimale($ref, $client));
        }

        $trouve = fn (string $t) => Vente::query()->tap(fn ($q) => RechercheLike::appliquer($q, ['reference', 'client'], $t))
            ->pluck('reference')->sort()->values()->all();

        $this->assertSame(['V-1'], $trouve('100%'));
        $this->assertSame(['V-3'], $trouve('a_b'));
        $this->assertSame(['V-1', 'V-2'], $trouve('100'));
        $this->assertSame(['V-1'], $trouve('LAINE'), 'insensible a la casse');
    }

    public function test_le_curseur_memorise_est_une_date_sql_et_non_un_texte_iso_avec_z(): void
    {
        // MySQL/MariaDB refusent « 2026-11-09T20:58:13.872917Z » dans un datetime(6).
        $a = $this->poste('admin', 'gerante');
        $this->avecJeton($a['jeton'])->getJson('/api/sync/pull')->assertOk();

        $brut = (string) DB::table('postes')->where('device_id', $a['device'])->value('curseur_tirage');
        $this->assertMatchesRegularExpression('/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}$/', $brut);
        $this->assertNotNull(Poste::query()->where('device_id', $a['device'])->first()->curseur_tirage);
    }

    public function test_les_lignes_gardent_l_ordre_du_poste_et_non_celui_des_uuid(): void
    {
        // InnoDB range par cle primaire (UUID aleatoire) ; SQLite par insertion : sans
        // colonne `ordre`, MySQL melangeait les lignes d'une commande.
        $a = $this->poste('admin', 'gerante');
        $f = $this->ligneFournisseur();
        $this->intrantConnu($a);
        $this->intrantConnu($a, ['code' => 'INT-002', 'name' => 'Soja']);
        $this->avecJeton($a['jeton'])->postJson('/api/sync/push', [
            'device_id' => $a['device'], 'reset_mark' => 'initiale', 'tables' => ['fournisseurs' => [$f]],
        ])->assertOk();

        $ids = ['ffffffff-0000-4000-8000-000000000003', 'aaaaaaaa-0000-4000-8000-000000000001', 'cccccccc-0000-4000-8000-000000000002'];
        $lignes = array_map(fn ($id, $i) => [
            'id' => $id, 'intrant_code' => $i % 2 === 0 ? 'INT-001' : 'INT-002', 'nom' => 'L'.$i, 'qte' => 10 + $i, 'pu_achat' => 100,
        ], $ids, array_keys($ids));
        $achat = $this->ligneAchat($f['id'], ['lignes' => $lignes, 'total' => 3030, 'paye' => 0]);

        $this->avecJeton($a['jeton'])->postJson('/api/sync/push', [
            'device_id' => $a['device'], 'reset_mark' => 'initiale', 'tables' => ['achats' => [$achat]],
        ])->assertOk()->assertJsonPath('achats.rejected', []);

        $this->assertSame($ids, Achat::query()->findOrFail($achat['id'])->lignes->pluck('id')->all());

        $b = $this->poste('admin', 'bako');
        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.achats'))->firstWhere('id', $achat['id']);
        $this->assertSame($ids, array_column($recu['lignes'], 'id'));
    }

    private function venteMinimale(string $reference, string $client): array
    {
        $poste = $this->poste('admin', 'u'.substr(md5($reference), 0, 6));

        return [
            'id' => (string) \Illuminate\Support\Str::uuid(), 'device_id' => $poste['device'], 'reference' => $reference,
            'portee_reference' => 'P1', 'client' => $client, 'date_vente' => now()->format('Y-m-d H:i:s.u'),
            'status' => 'Payée', 'total' => 1000, 'paye' => 1000, 'mode' => 'Espèces',
            'updated_at' => now()->format('Y-m-d H:i:s.u'), 'serveur_modifie_le' => now()->format('Y-m-d H:i:s.u'),
        ];
    }
}
