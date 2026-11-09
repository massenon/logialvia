<?php

namespace Tests\Feature\Sync;

use App\Models\ProduitVendable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** Le catalogue est un REFERENTIEL : le poste propose, le serveur decide ; jamais de stock. */
class ProduitsDemandesTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function demander(array $poste, array $produit, ?string $saisi = null, ?string $id = null)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $poste['device'],
            'demandes' => [[
                'id' => $id ?? (string) Str::uuid(),
                'type' => 'produit_vendable',
                'saisi_le' => $saisi ?? now()->format('Y-m-d\TH:i:s.u\Z'),
                'donnees' => $produit,
            ]],
        ]);
    }

    public function test_un_produit_propose_par_un_caissier_est_cree(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->ligneProduit();

        $this->demander($a, $p)->assertOk()->assertJsonPath('rejected', []);

        $this->assertSame('Goliath mature', ProduitVendable::query()->find($p['id'])->name);
    }

    public function test_le_stock_n_est_jamais_accepte(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->ligneProduit() + ['stock' => 99];

        $this->demander($a, $p)->assertJsonPath('rejected.0.motif', 'Le stock n\'est pas synchronisé : il reste propre à chaque poste.');
        $this->assertSame(0, ProduitVendable::query()->count());
    }

    public function test_sans_le_droit_de_vendre_le_catalogue_n_est_pas_modifiable(): void
    {
        $comptable = $this->poste('comptable');

        $this->demander($comptable, $this->ligneProduit())->assertJsonPath('rejected.0.motif', 'Droit insuffisant pour modifier le catalogue.');
    }

    public static function produitsInvalides(): array
    {
        return [
            'tarif nul' => [['price' => 0], 'Le tarif indicatif doit être supérieur à 0.'],
            'fourchette inversée' => [['price' => 100, 'price_max' => 50], 'Le prix haut de fourchette ne peut être inférieur au prix bas.'],
            'coût au-dessus du tarif' => [['price' => 100, 'cout_revient' => 150], 'Le coût de revient dépasse le tarif indicatif : chaque vente serait à perte.'],
            'sans désignation' => [['name' => ''], 'La désignation du produit est obligatoire.'],
            'seuil négatif' => [['threshold' => -1], 'Le seuil d\'alerte ne peut être négatif.'],
        ];
    }

    /** @dataProvider produitsInvalides */
    public function test_un_produit_invalide_est_refuse_avec_les_messages_du_catalogue(array $surcharge, string $motif): void
    {
        $a = $this->poste('caissier', 'amina');

        $this->demander($a, $this->ligneProduit($surcharge))->assertJsonPath('rejected.0.motif', $motif);
        $this->assertSame(0, ProduitVendable::query()->count());
    }

    public function test_deux_postes_semes_du_meme_catalogue_proposent_les_memes_produits_sans_conflit(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $p = $this->ligneProduit();
        $this->demander($a, $p, '2026-11-01T10:00:00.000000Z')->assertJsonPath('rejected', []);

        // Contenu identique, saisie plus ANCIENNE : ce n'est pas un conflit.
        $this->demander($b, $p, '2026-11-01T09:00:00.000000Z')->assertJsonPath('rejected', []);

        $this->assertSame(1, ProduitVendable::query()->count());
    }

    public function test_une_modification_plus_ancienne_que_la_derniere_acceptee_est_refusee_une_plus_recente_gagne(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $p = $this->ligneProduit();
        $this->demander($a, $p, '2026-11-01T10:00:00.000000Z')->assertOk();

        $this->demander($b, array_merge($p, ['price' => 30000]), '2026-11-01T09:00:00.000000Z')
            ->assertJsonPath('rejected.0.motif', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.');
        $this->assertSame(25000.0, ProduitVendable::query()->find($p['id'])->price);

        $this->demander($b, array_merge($p, ['price' => 30000]), '2026-11-01T11:00:00.000000Z')->assertJsonPath('rejected', []);
        $this->assertSame(30000.0, ProduitVendable::query()->find($p['id'])->price);
    }

    public function test_une_demande_rejouee_ne_reapplique_rien(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->ligneProduit();
        $idDemande = (string) Str::uuid();
        $this->demander($a, $p, null, $idDemande)->assertOk();
        ProduitVendable::query()->whereKey($p['id'])->update(['price' => 1234]);

        $this->demander($a, array_merge($p, ['price' => 99]), null, $idDemande)->assertJsonPath('accepted.0', $idDemande);

        $this->assertSame(1234.0, ProduitVendable::query()->find($p['id'])->price);
    }

    public function test_le_produit_redescend_vers_les_autres_postes_sans_stock(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $p = $this->produitConnu($a);

        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.produits_vendables'))->firstWhere('id', $p);

        $this->assertSame('Goliath mature', $recu['name']);
        $this->assertArrayNotHasKey('stock', $recu);
    }

    public function test_un_envoi_direct_d_un_produit_est_ignore_et_journalise(): void
    {
        $a = $this->poste('caissier', 'amina');

        $reponse = $this->avecJeton($a['jeton'])->postJson('/api/sync/push', [
            'device_id' => $a['device'], 'reset_mark' => 'initiale',
            'tables' => ['produits_vendables' => [$this->ligneProduit()]],
        ])->assertOk()->json('produits_vendables');

        $this->assertCount(1, $reponse['ignored']);
        $this->assertSame(0, ProduitVendable::query()->count());
    }

    // ------------------------------------------------- Suppression (pierre tombale)

    public function test_une_suppression_marque_le_produit_archive_sans_l_effacer(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->ligneProduit();
        $this->demander($a, $p)->assertJsonPath('rejected', []);

        $this->travel(2)->seconds();
        $this->demander($a, $p + ['archive' => true])->assertOk()->assertJsonPath('rejected', []);

        $row = ProduitVendable::query()->find($p['id']);
        $this->assertNotNull($row, 'jamais efface : un autre poste peut le citer');
        $this->assertNotNull($row->archive_le);
    }

    public function test_l_archivage_descend_vers_les_autres_postes(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('admin', 'bako');
        $p = $this->ligneProduit();
        $this->demander($a, $p);
        $curseur = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('server_time');

        $this->travel(5)->seconds();
        $this->demander($a, $p + ['archive' => true]);

        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull?since='.urlencode($curseur))->json('tables.produits_vendables'))->firstWhere('id', $p['id']);
        $this->assertNotNull($recu['archive_le']);
    }

    public function test_une_restauration_leve_l_archivage(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->ligneProduit();
        $this->demander($a, $p);
        $this->travel(2)->seconds();
        $this->demander($a, $p + ['archive' => true]);

        $this->travel(2)->seconds();
        $this->demander($a, $p)->assertJsonPath('rejected', []);

        $this->assertNull(ProduitVendable::query()->find($p['id'])->archive_le);
    }

    public function test_un_archivage_plus_ancien_que_la_derniere_decision_est_refuse(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->ligneProduit();
        $this->demander($a, $p);

        $this->demander($a, $p + ['archive' => true], now()->subDay()->format('Y-m-d\TH:i:s.u\Z'))
            ->assertJsonPath('rejected.0.motif', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.');

        $this->assertNull(ProduitVendable::query()->find($p['id'])->archive_le);
    }

    public function test_un_archivage_rejoue_est_accepte_sans_rien_changer(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->ligneProduit();
        $this->demander($a, $p);
        $this->travel(2)->seconds();
        $this->demander($a, $p + ['archive' => true]);
        $avant = ProduitVendable::query()->find($p['id'])->archive_le;

        $this->demander($a, $p + ['archive' => true], now()->addSeconds(30)->format('Y-m-d\TH:i:s.u\Z'))->assertJsonPath('rejected', []);

        $this->assertEquals($avant, ProduitVendable::query()->find($p['id'])->archive_le);
    }

    public function test_un_drapeau_d_archivage_invalide_est_refuse(): void
    {
        $a = $this->poste('caissier', 'amina');

        $this->demander($a, $this->ligneProduit() + ['archive' => 'peut-être'])
            ->assertJsonPath('rejected.0.motif', 'Le drapeau d\'archivage du produit est invalide.');
    }
}
