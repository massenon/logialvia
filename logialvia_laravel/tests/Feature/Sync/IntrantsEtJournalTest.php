<?php

namespace Tests\Feature\Sync;

use App\Models\Intrant;
use App\Models\MouvementIntrant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * Intrants (referentiel) et journal des mouvements (fait immuable).
 * Decision du client : stock propre a chaque poste + journal partage.
 */
class IntrantsEtJournalTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function demander(array $poste, array $intrant, ?string $saisi = null, ?string $id = null)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $poste['device'],
            'demandes' => [[
                'id' => $id ?? (string) Str::uuid(),
                'type' => 'intrant',
                'saisi_le' => $saisi ?? now()->format('Y-m-d\TH:i:s.u\Z'),
                'donnees' => $intrant,
            ]],
        ]);
    }

    private function pousser(array $poste, array $mouvements)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => 'initiale',
            'tables' => ['mouvements_intrant' => $mouvements],
        ]);
    }

    private function bilan(array $poste, array $mouvements): array
    {
        return $this->pousser($poste, $mouvements)->assertOk()->json('mouvements_intrant');
    }

    // ----------------------------------------------------------------- Intrants

    public function test_un_intrant_propose_est_cree_sans_stock_ni_pmp(): void
    {
        $a = $this->poste('admin', 'gerante');

        $this->demander($a, $this->ligneIntrant())->assertJsonPath('rejected', []);

        $i = Intrant::query()->find('INT-001');
        $this->assertSame('Maïs', $i->name);
        $this->assertSame(25, $i->threshold);
        $this->assertArrayNotHasKey('stock', $i->getAttributes());
        $this->assertArrayNotHasKey('pmp', $i->getAttributes());
    }

    public function test_le_stock_et_le_pmp_ne_sont_jamais_acceptes(): void
    {
        $a = $this->poste('admin', 'gerante');

        $this->demander($a, $this->ligneIntrant() + ['stock' => 18])
            ->assertJsonPath('rejected.0.motif', 'Le stock n\'est pas synchronisé : il reste propre à chaque poste.');
        $this->demander($a, $this->ligneIntrant() + ['pmp' => 600])
            ->assertJsonPath('rejected.0.motif', 'Le pmp n\'est pas synchronisé : il reste propre à chaque poste.');
        $this->assertSame(0, Intrant::query()->count());
    }

    public function test_sans_le_droit_de_gerer_les_stocks_ou_les_achats_la_demande_est_refusee(): void
    {
        $caissier = $this->poste('caissier', 'amina');

        $this->demander($caissier, $this->ligneIntrant())->assertJsonPath('rejected.0.motif', 'Droit insuffisant pour modifier les intrants.');
    }

    public static function intrantsInvalides(): array
    {
        return [
            'sans désignation' => [['name' => ''], "La désignation de l'intrant est obligatoire."],
            'sans unité' => [['unit' => ''], "L'unité de l'intrant est obligatoire."],
            'seuil négatif' => [['threshold' => -1], 'Le seuil d\'alerte ne peut être négatif.'],
        ];
    }

    /** @dataProvider intrantsInvalides */
    public function test_un_intrant_invalide_est_refuse_avec_un_motif_francais(array $surcharge, string $motif): void
    {
        $a = $this->poste('admin', 'gerante');

        $this->demander($a, $this->ligneIntrant($surcharge))->assertJsonPath('rejected.0.motif', $motif);
        $this->assertSame(0, Intrant::query()->count());
    }

    public function test_deux_postes_semes_des_memes_intrants_ne_se_contredisent_pas(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $this->demander($a, $this->ligneIntrant(), '2026-11-01T10:00:00.000000Z')->assertJsonPath('rejected', []);

        $this->demander($b, $this->ligneIntrant(), '2026-11-01T09:00:00.000000Z')->assertJsonPath('rejected', []);

        $this->assertSame(1, Intrant::query()->count());
    }

    public function test_une_modification_plus_ancienne_est_refusee_une_plus_recente_gagne(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $this->demander($a, $this->ligneIntrant(), '2026-11-01T10:00:00.000000Z')->assertOk();

        $this->demander($b, $this->ligneIntrant(['threshold' => 99]), '2026-11-01T09:00:00.000000Z')
            ->assertJsonPath('rejected.0.motif', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.');
        $this->assertSame(25, Intrant::query()->find('INT-001')->threshold);

        $this->demander($b, $this->ligneIntrant(['threshold' => 99]), '2026-11-01T11:00:00.000000Z')->assertJsonPath('rejected', []);
        $this->assertSame(99, Intrant::query()->find('INT-001')->threshold);
    }

    public function test_les_intrants_redescendent_vers_les_postes_autorises_sans_stock(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->intrantConnu($a);
        $comptable = $this->poste('comptable');
        $caissier = $this->poste('caissier', 'amina');
        $animalier = $this->poste('animalier', 'eleveur');

        $recu = collect($this->avecJeton($comptable['jeton'])->getJson('/api/sync/pull')->json('tables.intrants'))->firstWhere('code', 'INT-001');
        $this->assertSame('Maïs', $recu['name']);
        $this->assertArrayNotHasKey('stock', $recu);
        $this->assertArrayHasKey('intrants', $this->avecJeton($animalier['jeton'])->getJson('/api/sync/pull')->json('tables'), 'l\'élevage consomme des intrants');
        $this->assertArrayNotHasKey('intrants', $this->avecJeton($caissier['jeton'])->getJson('/api/sync/pull')->json('tables'));
    }

    public function test_un_envoi_direct_d_un_intrant_est_ignore(): void
    {
        $a = $this->poste('admin', 'gerante');

        $r = $this->avecJeton($a['jeton'])->postJson('/api/sync/push', [
            'device_id' => $a['device'], 'reset_mark' => 'initiale',
            'tables' => ['intrants' => [$this->ligneIntrant()]],
        ])->assertOk()->json('intrants');

        $this->assertCount(1, $r['ignored']);
        $this->assertSame(0, Intrant::query()->count());
    }

    // ------------------------------------------------------------------ Journal

    public function test_un_mouvement_est_enregistre_et_redistribue_sans_toucher_aucun_stock(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $this->intrantConnu($a);
        $m = $this->ligneMouvement();

        $this->assertSame([$m['id']], $this->bilan($a, [$m])['accepted']);

        $row = MouvementIntrant::query()->find($m['id']);
        $this->assertSame($a['device'], $row->device_id);
        $this->assertSame(100.0, $row->quantite);
        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.mouvements_intrant'))->firstWhere('id', $m['id']);
        $this->assertSame('Entrée', $recu['type']);
        $this->assertSame($a['device'], $recu['device_id'], 'l\'origine accompagne le mouvement');
        $this->assertArrayNotHasKey('stock', $recu);
    }

    public function test_un_intrant_inconnu_fait_refuser_le_mouvement(): void
    {
        $a = $this->poste('admin', 'gerante');

        $bilan = $this->bilan($a, [$this->ligneMouvement('INT-FANTOME')]);

        $this->assertSame('Intrant inconnu du serveur : « INT-FANTOME ».', $bilan['rejected'][0]['motif']);
        $this->assertSame(0, MouvementIntrant::query()->count());
    }

    public static function mouvementsInvalides(): array
    {
        return [
            'type inconnu' => [['type' => 'Vol'], 'Le type de mouvement est inconnu.'],
            'quantité absente' => [['quantite' => null], 'La quantité du mouvement est obligatoire.'],
            'quantité nulle' => [['quantite' => 0], 'La quantité d\'un mouvement ne peut pas être nulle.'],
            'motif vide' => [['motif' => ''], 'Le motif du mouvement est obligatoire.'],
            'date invalide' => [['horodatage' => 'hier'], 'La date du mouvement est invalide.'],
        ];
    }

    /** @dataProvider mouvementsInvalides */
    public function test_un_mouvement_invalide_est_refuse_avec_un_motif_francais(array $surcharge, string $motif): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->intrantConnu($a);

        $bilan = $this->bilan($a, [$this->ligneMouvement('INT-001', $surcharge)]);

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, MouvementIntrant::query()->count());
    }

    public function test_une_sortie_et_un_ajustement_negatif_sont_acceptes(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->intrantConnu($a);
        $sortie = $this->ligneMouvement('INT-001', ['type' => 'Sortie', 'quantite' => -30, 'motif' => 'Fabrication FAB-2026-0001']);
        $ajust = $this->ligneMouvement('INT-001', ['type' => 'Ajustement', 'quantite' => -2, 'motif' => 'Inventaire']);

        $this->assertCount(2, $this->bilan($a, [$sortie, $ajust])['accepted']);
    }

    public function test_un_mouvement_est_immuable_et_son_rejeu_ne_duplique_rien(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->intrantConnu($a);
        $m = $this->ligneMouvement();
        $this->bilan($a, [$m]);

        $this->assertSame([$m['id']], $this->bilan($a, [array_merge($m, ['quantite' => 999, 'motif' => 'Falsifié'])])['accepted']);

        $this->assertSame(1, MouvementIntrant::query()->count());
        $row = MouvementIntrant::query()->find($m['id']);
        $this->assertSame(100.0, $row->quantite, 'un mouvement ne se modifie jamais');
        $this->assertSame('Réception commande ACH-P1-2026-001', $row->motif);
    }

    public function test_les_droits_du_journal(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $this->intrantConnu($admin);

        $animalier = $this->poste('animalier', 'eleveur'); // consomme la provende : manage-elevage
        $this->assertCount(1, $this->bilan($animalier, [$this->ligneMouvement('INT-001', ['type' => 'Sortie', 'quantite' => -5, 'motif' => 'Distribution'])])['accepted']);

        $caissier = $this->poste('caissier', 'amina');
        $refus = $this->bilan($caissier, [$this->ligneMouvement()]);
        $this->assertSame('Droit insuffisant pour écrire dans « mouvements_intrant ».', $refus['rejected'][0]['motif']);

        $comptable = $this->poste('comptable');
        $this->assertSame('Droit insuffisant pour écrire dans « mouvements_intrant ».', $this->bilan($comptable, [$this->ligneMouvement()])['rejected'][0]['motif']);
        $this->assertArrayHasKey('mouvements_intrant', $this->avecJeton($comptable['jeton'])->getJson('/api/sync/pull')->json('tables'), 'le comptable consulte');
        $this->assertArrayNotHasKey('mouvements_intrant', $this->avecJeton($caissier['jeton'])->getJson('/api/sync/pull')->json('tables'));
    }

    public function test_un_mouvement_saisi_hors_ligne_atteint_un_poste_deja_a_jour(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $this->intrantConnu($a);
        $curseur = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('server_time');

        $this->travel(5)->seconds();
        $vieux = $this->ligneMouvement('INT-001', ['horodatage' => now()->subDays(3)->format('Y-m-d\TH:i:s.u\Z')]);
        $this->bilan($a, [$vieux]);

        $recus = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull?since='.urlencode($curseur))->json('tables.mouvements_intrant');

        $this->assertSame([$vieux['id']], array_column($recus, 'id'));
    }
}
