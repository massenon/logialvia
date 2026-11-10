<?php

namespace Tests\Feature\Sync;

use App\Models\MouvementProduit;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * Journal des corrections de stock des produits vendables (fait immuable).
 * Stock propre a chaque poste : le journal est un historique, jamais un stock.
 */
class JournalProduitsTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function bilan(array $poste, array $mouvements): array
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => 'initiale',
            'tables' => ['mouvements_produit' => $mouvements],
        ])->assertOk()->json('mouvements_produit');
    }

    public function test_une_correction_est_enregistree_et_redistribuee_sans_stock(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $p = $this->produitConnu($a);
        $m = $this->ligneMouvementProduit($p);

        $this->assertSame([$m['id']], $this->bilan($a, [$m])['accepted']);

        $row = MouvementProduit::query()->find($m['id']);
        $this->assertSame($a['device'], $row->device_id);
        $this->assertSame(-3.0, $row->quantite);
        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.mouvements_produit'))->firstWhere('id', $m['id']);
        $this->assertSame($a['device'], $recu['device_id']);
        $this->assertArrayNotHasKey('stock', $recu);
    }

    public function test_un_produit_inconnu_fait_refuser_le_mouvement(): void
    {
        $a = $this->poste('admin', 'gerante');
        $id = (string) Str::uuid();

        $bilan = $this->bilan($a, [$this->ligneMouvementProduit($id)]);

        $this->assertSame("Produit inconnu du serveur : « $id ».", $bilan['rejected'][0]['motif']);
        $this->assertSame(0, MouvementProduit::query()->count());
    }

    /** @dataProvider invalides */
    public function test_un_mouvement_invalide_est_refuse_avec_un_motif_francais(array $surcharge, string $motif): void
    {
        $a = $this->poste('admin', 'gerante');
        $p = $this->produitConnu($a);

        $bilan = $this->bilan($a, [$this->ligneMouvementProduit($p, $surcharge)]);

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, MouvementProduit::query()->count());
    }

    public static function invalides(): array
    {
        return [
            'UUID invalide' => [['id' => 'pas-un-uuid'], "L'identifiant du mouvement doit être un UUID."],
            'produit non UUID' => [['produit_id' => 'x'], 'Le produit du mouvement doit être un UUID.'],
            'motif vide' => [['motif' => ''], 'Le motif du mouvement est obligatoire.'],
            'date invalide' => [['horodatage' => 'hier'], 'La date du mouvement est invalide.'],
            'quantité nulle' => [['quantite' => 0], "La quantité d'un mouvement ne peut pas être nulle."],
            'quantité texte' => [['quantite' => 'beaucoup'], 'La quantité du mouvement est invalide.'],
        ];
    }

    public function test_un_mouvement_est_immuable_et_son_rejeu_ne_duplique_rien(): void
    {
        $a = $this->poste('admin', 'gerante');
        $p = $this->produitConnu($a);
        $m = $this->ligneMouvementProduit($p);
        $this->bilan($a, [$m]);

        $this->assertSame([$m['id']], $this->bilan($a, [array_merge($m, ['quantite' => 999, 'motif' => 'Falsifié'])])['accepted']);

        $this->assertSame(1, MouvementProduit::query()->count());
        $this->assertSame(-3.0, MouvementProduit::query()->find($m['id'])->quantite);
    }

    public function test_les_droits_du_journal(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $p = $this->produitConnu($admin);

        $caissier = $this->poste('caissier', 'amina'); // manage-ventes : peut corriger
        $this->assertCount(1, $this->bilan($caissier, [$this->ligneMouvementProduit($p)])['accepted']);

        $comptable = $this->poste('comptable');
        $refus = $this->bilan($comptable, [$this->ligneMouvementProduit($p)]);
        $this->assertSame('Droit insuffisant pour écrire dans « mouvements_produit ».', $refus['rejected'][0]['motif']);

        $animalier = $this->poste('animalier', 'eleveur');
        $this->assertArrayNotHasKey('mouvements_produit', $this->avecJeton($animalier['jeton'])->getJson('/api/sync/pull')->json('tables'));
    }

    public function test_un_envoi_direct_du_stock_n_existe_pas_et_le_journal_ne_touche_aucun_produit(): void
    {
        $a = $this->poste('admin', 'gerante');
        $p = $this->produitConnu($a);
        $avant = \App\Models\ProduitVendable::query()->find($p)->toArray();

        $this->bilan($a, [$this->ligneMouvementProduit($p, ['quantite' => 500])]);

        $this->assertSame($avant, \App\Models\ProduitVendable::query()->find($p)->toArray());
    }
}
