<?php

namespace Tests\Feature\Sync;

use App\Livewire\Catalogue;
use App\Models\Client;
use App\Models\Vente;
use App\Sync\Tables\VentesTable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * Le web est un poste de code `WEB` : sa reference `V-WEB-AAAA-NNN` est GLOBALE (comme `V-P2-…`), acceptee a la
 * reception, et la reaffectation d'une vente a un autre client recalcule les DEUX soldes.
 */
class VentesWebReferenceTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function pousser(array $poste, array $ventes): array
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'], 'reset_mark' => 'initiale', 'tables' => ['ventes' => $ventes],
        ])->assertOk()->json('ventes');
    }

    public function test_la_reference_du_web_est_acceptee_et_globale(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $p = $this->produitConnu($a);

        $v = $this->ligneVente($p, ['reference' => 'V-WEB-2026-001']);
        $this->assertSame([$v['id']], $this->pousser($a, [$v])['accepted']);
        $this->assertSame('', Vente::query()->find($v['id'])->portee_reference, 'globale : aucun poste ne peut la reprendre');

        // Un AUTRE poste ne peut pas reprendre la reference du web.
        $autre = $this->ligneVente($p, ['reference' => 'V-WEB-2026-001']);
        $this->assertSame(VentesTable::MOTIF_REFERENCE, $this->pousser($b, [$autre])['rejected'][0]['motif']);
        $this->assertSame(1, Vente::query()->count());
    }

    public function test_les_formes_voisines_restent_refusees_et_les_anciennes_restent_acceptees(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);

        foreach (['V-WEB-2026', 'V-WEB-26-001', 'V-WEB-2026-01', 'V-WEBB-2026-001', 'V-web-2026-001', 'V-P-2026-001', 'WEB-2026-001'] as $reference) {
            $bilan = $this->pousser($a, [$this->ligneVente($p, ['reference' => $reference])]);
            $this->assertSame('La référence de la vente est invalide (attendu : V-P2-2026-001).', $bilan['rejected'][0]['motif'], $reference);
        }
        foreach (['V-2026-001', 'V-P2-2026-001', 'V-WEB-2026-001'] as $reference) {
            $this->assertCount(1, $this->pousser($a, [$this->ligneVente($p, ['reference' => $reference])])['accepted'], $reference);
        }
        $portee = fn (string $r) => Vente::query()->where('reference', $r)->value('portee_reference');
        $this->assertSame(['', '', $a['device']], [$portee('V-P2-2026-001'), $portee('V-WEB-2026-001'), $portee('V-2026-001')]);
    }

    public function test_reaffecter_une_vente_a_un_autre_client_recalcule_les_deux_soldes(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);
        $c1 = $this->ligneClient(['nom' => 'Premier']);
        $c2 = $this->ligneClient(['nom' => 'Second']);
        $this->avecJeton($a['jeton'])->postJson('/api/sync/push', ['device_id' => $a['device'], 'reset_mark' => 'initiale', 'tables' => ['clients' => [$c1, $c2]]])->assertOk();

        $v = $this->ligneVente($p, ['client' => 'Premier', 'client_id' => $c1['id'], 'status' => 'Avance', 'paye' => 20000]);
        $this->pousser($a, [$v]);
        $this->assertSame(30000.0, Client::query()->find($c1['id'])->solde_creance);

        // Plus tard, la vente est rattachee au second client.
        $v['client'] = 'Second';
        $v['client_id'] = $c2['id'];
        $v['updated_at'] = now()->addMinute()->format('Y-m-d\TH:i:s.u\Z');
        $this->pousser($a, [$v]);
        $this->assertSame(0.0, Client::query()->find($c1['id'])->solde_creance, 'le premier client perd la creance');
        $this->assertSame(30000.0, Client::query()->find($c2['id'])->solde_creance);

        // Detachee de tout client : le second est aussi recalcule.
        $v['client_id'] = null;
        $v['updated_at'] = now()->addMinutes(2)->format('Y-m-d\TH:i:s.u\Z');
        $this->pousser($a, [$v]);
        $this->assertSame(0.0, Client::query()->find($c2['id'])->solde_creance);

        // Une saisie PLUS ANCIENNE ne change rien (dernier ecrivain gagne) et ne casse aucun solde.
        $v['client_id'] = $c1['id'];
        $v['updated_at'] = now()->subDay()->format('Y-m-d\TH:i:s.u\Z');
        $this->pousser($a, [$v]);
        $this->assertNull(Vente::query()->find($v['id'])->client_id);
        $this->assertSame(0.0, Client::query()->find($c1['id'])->solde_creance);
    }

    public function test_une_vente_du_web_est_servie_aux_postes_avec_ses_lignes(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);
        $id = (string) Str::uuid();

        $motif = (new VentesTable)->absorber(Catalogue::POSTE_WEB, $this->ligneVente($p, ['id' => $id, 'reference' => 'V-WEB-2026-001']));
        $this->assertNull($motif);

        $recue = collect($this->avecJeton($a['jeton'])->getJson('/api/sync/pull')->json('tables.ventes'))->firstWhere('id', $id);
        $this->assertSame(Catalogue::POSTE_WEB, $recue['device_id']);
        $this->assertSame('V-WEB-2026-001', $recue['reference']);
        $this->assertCount(1, $recue['lignes']);
    }
}
