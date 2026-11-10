<?php

namespace Tests\Feature\Sync;

use App\Models\Client;
use App\Models\LigneVente;
use App\Models\Vente;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** Ventes : un lot vente + lignes, une reference officielle, aucun stock ni ecriture. */
class VentesTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function pousser(array $poste, array $ventes, array $extra = [])
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => 'initiale',
            'tables' => array_merge(['ventes' => $ventes], $extra),
        ]);
    }

    private function bilan($reponse): array
    {
        return $reponse->assertOk()->json('ventes');
    }

    public function test_une_vente_et_ses_lignes_sont_enregistrees_ensemble(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);
        $v = $this->ligneVente($p);

        $bilan = $this->bilan($this->pousser($a, [$v]));

        $this->assertSame([$v['id']], $bilan['accepted']);
        $vente = Vente::query()->find($v['id']);
        $this->assertSame('V-P1-2026-001', $vente->reference);
        $this->assertSame($a['device'], $vente->device_id);
        $this->assertSame(50000.0, $vente->total);
        $this->assertSame(1, LigneVente::query()->where('vente_id', $v['id'])->count());
    }

    public function test_les_lignes_voyagent_dans_leur_vente_au_tirage_d_un_autre_poste(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $p = $this->produitConnu($a);
        $v = $this->ligneVente($p, ['lignes' => [
            ['id' => (string) Str::uuid(), 'produit_id' => $p, 'name' => 'Goliath mature', 'qte' => 1, 'pu' => 25000],
            ['id' => (string) Str::uuid(), 'produit_id' => $p, 'name' => 'Goliath mature', 'qte' => 3, 'pu' => 25000],
        ], 'total' => 100000, 'paye' => 100000]);
        $this->pousser($a, [$v])->assertOk();

        $recue = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.ventes'))->firstWhere('id', $v['id']);

        $this->assertCount(2, $recue['lignes']);
        $this->assertArrayNotHasKey('portee_reference', $recue, 'detail d\'implementation du serveur');
        $this->assertSame($a['device'], $recue['device_id']);
    }

    public function test_une_vente_dont_un_produit_est_inconnu_est_refusee_en_entier(): void
    {
        $a = $this->poste('caissier', 'amina');
        $connu = $this->produitConnu($a);
        $v = $this->ligneVente($connu, ['lignes' => [
            ['id' => (string) Str::uuid(), 'produit_id' => $connu, 'name' => 'Goliath mature', 'qte' => 1, 'pu' => 25000],
            ['id' => (string) Str::uuid(), 'produit_id' => (string) Str::uuid(), 'name' => 'Produit fantôme', 'qte' => 1, 'pu' => 100],
        ]]);

        $bilan = $this->bilan($this->pousser($a, [$v]));

        $this->assertSame('Produit inconnu du serveur : « Produit fantôme ».', $bilan['rejected'][0]['motif']);
        $this->assertSame(0, Vente::query()->count(), 'le lot ne se coupe jamais : aucune vente sans ses lignes');
        $this->assertSame(0, LigneVente::query()->count());
    }

    public function test_un_client_inconnu_est_refuse_un_client_connu_est_lie_et_son_solde_derive(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);
        $inconnu = $this->ligneVente($p, ['client_id' => (string) Str::uuid()]);
        $this->assertStringStartsWith('Client inconnu du serveur', $this->bilan($this->pousser($a, [$inconnu]))['rejected'][0]['motif']);

        $client = $this->ligneClient(['nom' => 'Mama Rita']);
        $this->avecJeton($a['jeton'])->postJson('/api/sync/push', [
            'device_id' => $a['device'], 'reset_mark' => 'initiale', 'tables' => ['clients' => [$client]],
        ])->assertOk();
        $avance = $this->ligneVente($p, ['client' => 'Mama Rita', 'client_id' => $client['id'], 'status' => 'Avance', 'paye' => 20000, 'reference' => 'V-P1-2026-002']);
        $this->assertSame([$avance['id']], $this->bilan($this->pousser($a, [$avance]))['accepted']);

        $this->assertSame(30000.0, Client::query()->find($client['id'])->solde_creance, 'solde = reste du, calcule par le serveur');
    }

    public function test_sans_le_droit_d_ecriture_toutes_les_ventes_sont_refusees(): void
    {
        $caissier = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($caissier);
        $comptable = $this->poste('comptable');

        $bilan = $this->bilan($this->pousser($comptable, [$this->ligneVente($p)]));

        $this->assertSame('Droit insuffisant pour écrire dans « ventes ».', $bilan['rejected'][0]['motif']);
        $this->assertSame(0, Vente::query()->count());
    }

    public function test_la_lecture_est_reservee_a_ceux_qui_peuvent_voir_les_ventes(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);
        $this->pousser($a, [$this->ligneVente($p)])->assertOk();
        $animalier = $this->poste('animalier', 'eleveur');

        $tables = $this->avecJeton($animalier['jeton'])->getJson('/api/sync/pull')->json('tables');

        $this->assertArrayNotHasKey('ventes', $tables);
        $this->assertArrayNotHasKey('produits_vendables', $tables);
    }

    // ----------------------------------------------------- Unicite des references

    public function test_une_reference_a_code_de_poste_est_unique_pour_tous(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $p = $this->produitConnu($a);
        $this->pousser($a, [$this->ligneVente($p, ['reference' => 'V-P2-2026-001'])])->assertOk();

        $autre = $this->ligneVente($p, ['reference' => 'V-P2-2026-001']);
        $bilan = $this->bilan($this->pousser($b, [$autre]));

        $this->assertSame('Cette référence est déjà utilisée par une autre vente.', $bilan['rejected'][0]['motif']);
        $this->assertSame(1, Vente::query()->count());
    }

    public function test_deux_postes_peuvent_avoir_chacun_la_meme_ancienne_reference_sans_code(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $p = $this->produitConnu($a);

        $va = $this->ligneVente($p, ['reference' => 'V-2026-001']);
        $vb = $this->ligneVente($p, ['reference' => 'V-2026-001']);

        $this->assertSame([$va['id']], $this->bilan($this->pousser($a, [$va]))['accepted']);
        $this->assertSame([$vb['id']], $this->bilan($this->pousser($b, [$vb]))['accepted']);
        $this->assertSame(2, Vente::query()->count());
    }

    public function test_un_meme_poste_ne_reutilise_pas_une_ancienne_reference(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);
        $this->pousser($a, [$this->ligneVente($p, ['reference' => 'V-2026-001'])])->assertOk();

        $bilan = $this->bilan($this->pousser($a, [$this->ligneVente($p, ['reference' => 'V-2026-001'])]));

        $this->assertSame('Cette référence est déjà utilisée par une autre vente.', $bilan['rejected'][0]['motif']);
    }

    public function test_une_ancienne_reference_ne_prend_pas_la_place_d_une_reference_a_code(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);
        $this->pousser($a, [$this->ligneVente($p, ['reference' => 'V-2026-001'])])->assertOk();

        $this->assertCount(1, $this->bilan($this->pousser($a, [$this->ligneVente($p, ['reference' => 'V-P1-2026-001'])]))['accepted']);
    }

    // ----------------------------------------------------------- Validation

    public static function ventesInvalides(): array
    {
        return [
            'référence invalide' => [['reference' => 'FACTURE-1'], 'La référence de la vente est invalide (attendu : V-P2-2026-001).'],
            'statut inconnu' => [['status' => 'Perdue'], 'Le statut de la vente est inconnu.'],
            'mode inconnu' => [['mode' => 'Troc'], 'Le mode de règlement est inconnu.'],
            'total négatif' => [['total' => -1], 'Le total de la vente ne peut pas être négatif.'],
            'payé au-delà du total' => [['paye' => 60000], 'Le montant payé dépasse le total de la vente.'],
            'aucune ligne' => [['lignes' => []], 'Une vente doit avoir au moins une ligne.'],
            'client vide' => [['client' => ''], 'Le client de la vente est obligatoire.'],
        ];
    }

    /** @dataProvider ventesInvalides */
    public function test_une_vente_invalide_est_refusee_avec_un_motif_francais(array $surcharge, string $motif): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);

        $bilan = $this->bilan($this->pousser($a, [$this->ligneVente($p, $surcharge)]));

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, Vente::query()->count());
    }

    public function test_une_quantite_nulle_est_refusee(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);
        $v = $this->ligneVente($p);
        $v['lignes'][0]['qte'] = 0;

        $this->assertSame('La quantité d\'une ligne doit être supérieure à 0.', $this->bilan($this->pousser($a, [$v]))['rejected'][0]['motif']);
    }

    // ------------------------------------------ Dernier ecrivain, immutabilite

    public function test_un_rejeu_est_accepte_sans_rien_dupliquer(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);
        $v = $this->ligneVente($p);
        $this->pousser($a, [$v])->assertOk();

        $this->assertSame([$v['id']], $this->bilan($this->pousser($a, [$v]))['accepted']);

        $this->assertSame(1, Vente::query()->count());
        $this->assertSame(1, LigneVente::query()->count());
    }

    public function test_l_entete_suit_le_dernier_ecrivain_les_lignes_ne_bougent_jamais(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);
        $v = $this->ligneVente($p, ['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->pousser($a, [$v])->assertOk();

        // Annulation plus recente : l'entete change ; des lignes differentes sont ignorees.
        $annulee = array_merge($v, [
            'status' => 'Annulée', 'motif_annulation' => 'Erreur', 'updated_at' => '2026-11-01T11:00:00.000000Z',
            'lignes' => [['id' => (string) Str::uuid(), 'produit_id' => $p, 'name' => 'Autre', 'qte' => 9, 'pu' => 1]],
        ]);
        $this->pousser($a, [$annulee])->assertOk();
        $vente = Vente::query()->find($v['id']);
        $this->assertSame('Annulée', $vente->status);
        $this->assertSame(1, $vente->lignes()->count());
        $this->assertSame(2.0, $vente->lignes()->first()->qte, 'les lignes d\'une vente sont immuables');

        // Saisie plus ANCIENNE arrivee en retard : sans effet.
        $ancienne = array_merge($v, ['status' => 'Payée', 'updated_at' => '2026-11-01T09:00:00.000000Z']);
        $this->pousser($a, [$ancienne])->assertOk();
        $this->assertSame('Annulée', Vente::query()->find($v['id'])->status);
    }

    public function test_la_reference_d_une_vente_ne_change_jamais(): void
    {
        $a = $this->poste('caissier', 'amina');
        $p = $this->produitConnu($a);
        $v = $this->ligneVente($p, ['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->pousser($a, [$v])->assertOk();

        $this->pousser($a, [array_merge($v, ['reference' => 'V-P1-2026-999', 'updated_at' => '2026-11-01T12:00:00.000000Z'])])->assertOk();

        $this->assertSame('V-P1-2026-001', Vente::query()->find($v['id'])->reference, 'numero officiel remis au client (DV-21)');
    }

    public function test_une_vente_saisie_hors_ligne_trois_jours_atteint_un_poste_deja_a_jour(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'bako');
        $p = $this->produitConnu($a);
        $curseur = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('server_time');

        $this->travel(5)->seconds();
        $vieille = $this->ligneVente($p, ['updated_at' => now()->subDays(3)->format('Y-m-d\TH:i:s.u\Z'), 'date_vente' => now()->subDays(3)->format('Y-m-d\TH:i:s.u\Z')]);
        $this->pousser($a, [$vieille])->assertOk();

        $recues = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull?since='.urlencode($curseur))->json('tables.ventes');

        $this->assertSame([$vieille['id']], array_column($recues, 'id'));
    }
}
