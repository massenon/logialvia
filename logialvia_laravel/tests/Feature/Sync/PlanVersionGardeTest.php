<?php

namespace Tests\Feature\Sync;

use App\Models\PieceComptable;
use App\Models\PlanComptable;
use App\Support\PlanSyscohada;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * GARDE DE VERSION DU PLAN (`47p_` §7) : un poste non migre enverrait d'anciens numeros (601/602 inverses,
 * 531 pour la caisse) qui seraient silencieusement MAL comptabilises. Le serveur refuse, avec un motif
 * francais explicite, tout lot d'ecritures (et toute demande de compte) sans la bonne `plan_version`.
 */
class PlanVersionGardeTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    private const MOTIF = "Ce poste utilise l'ancien plan comptable : mettez-le à jour avant d'envoyer des écritures.";

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
        $this->amorcerComptabilite();
        config(['logialvia.sync.recouvrement_secondes' => 0]);
    }

    /** Une piece d'achat de matieres telle qu'un poste de version donnee l'enverrait (`null` : poste sans version). */
    private function piece(?int $version, string $compteMatieres = '602'): array
    {
        $piece = $this->pieceComptable([
            'journal_code' => 'AC', 'achat_ref' => 'ACH-P1-'.$this->anneeComptable().'-001', 'numero_piece' => 'ACH-P1-'.$this->anneeComptable().'-001',
            'lignes' => [$this->ligneEcriture($compteMatieres, 250000, 0), $this->ligneEcriture('401', 0, 250000)],
        ]);
        if ($version === null) {
            unset($piece['plan_version']);
        } else {
            $piece['plan_version'] = $version;
        }

        return $piece;
    }

    public function test_un_poste_sans_version_de_plan_est_refuse_avec_le_motif_explicite(): void
    {
        $a = $this->poste('admin', 'gerante');
        $bilan = $this->pousserTable($a, 'ecriture_comptable', [$this->piece(null)]);

        $this->assertSame([], $bilan['accepted']);
        $this->assertSame(self::MOTIF, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, PieceComptable::query()->count(), 'rien n\'est ecrit : jamais de 601/602 inverses en silence');
    }

    public function test_une_version_ancienne_ou_inconnue_est_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');
        foreach ([1, 0, 3, 99] as $version) {
            $bilan = $this->pousserTable($a, 'ecriture_comptable', [$this->piece($version)]);
            $this->assertSame(self::MOTIF, $bilan['rejected'][0]['motif'], "version $version");
        }
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_un_poste_migre_est_accepte(): void
    {
        $a = $this->poste('admin', 'gerante');
        $piece = $this->piece(PlanSyscohada::VERSION);

        $bilan = $this->pousserTable($a, 'ecriture_comptable', [$piece]);

        $this->assertSame([$piece['id']], $bilan['accepted']);
        $this->assertSame(1, PieceComptable::query()->count());
    }

    public function test_deux_postes_dont_un_non_migre_le_serveur_ne_prend_que_le_bon(): void
    {
        $migre = $this->poste('admin', 'gerante');
        $ancien = $this->poste('admin', 'gerante2');
        $bonne = $this->piece(PlanSyscohada::VERSION);
        $mauvaise = $this->piece(null);

        $r1 = $this->pousserTable($migre, 'ecriture_comptable', [$bonne]);
        $r2 = $this->pousserTable($ancien, 'ecriture_comptable', [$mauvaise]);

        $this->assertSame([$bonne['id']], $r1['accepted']);
        $this->assertSame(self::MOTIF, $r2['rejected'][0]['motif']);
        $this->assertSame([$bonne['id']], PieceComptable::query()->pluck('id')->all());
    }

    public function test_un_lot_mixte_refuse_seulement_les_pieces_sans_version(): void
    {
        $a = $this->poste('admin', 'gerante');
        $bonne = $this->piece(PlanSyscohada::VERSION);
        $mauvaise = $this->piece(null);
        $mauvaise['numero_piece'] = 'ACH-P1-AUTRE';

        $bilan = $this->pousserTable($a, 'ecriture_comptable', [$bonne, $mauvaise]);

        $this->assertSame([$bonne['id']], $bilan['accepted']);
        $this->assertCount(1, $bilan['rejected']);
        $this->assertSame($mauvaise['id'], $bilan['rejected'][0]['id']);
    }

    public function test_le_rejeu_d_une_piece_deja_acceptee_reste_accepte_avec_la_bonne_version(): void
    {
        $a = $this->poste('admin', 'gerante');
        $piece = $this->piece(PlanSyscohada::VERSION);
        $this->pousserTable($a, 'ecriture_comptable', [$piece]);

        $bilan = $this->pousserTable($a, 'ecriture_comptable', [$piece]);

        $this->assertSame([$piece['id']], $bilan['accepted']);
        $this->assertSame(1, PieceComptable::query()->count());
    }

    public function test_les_pieces_servies_et_le_plan_portent_la_version(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('comptable', 'paul');
        $this->pousserTable($a, 'ecriture_comptable', [$this->piece(PlanSyscohada::VERSION)]);

        $tables = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables');

        $this->assertSame([PlanSyscohada::VERSION], collect($tables['ecriture_comptable'])->pluck('plan_version')->unique()->values()->all());
        $this->assertSame([PlanSyscohada::VERSION], collect($tables['plan_comptable'])->pluck('plan_version')->unique()->values()->all());
        $this->assertCount(60, $tables['plan_comptable']);
    }

    public function test_une_demande_de_compte_d_un_ancien_poste_est_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');
        $demande = fn (array $donnees) => $this->avecJeton($a['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $a['device'],
            'demandes' => [[
                'id' => (string) Str::uuid(), 'type' => 'compte_comptable',
                'saisi_le' => now()->format('Y-m-d\TH:i:s.u\Z'), 'donnees' => $donnees,
            ]],
        ]);
        $compte = ['numero_compte' => '613', 'libelle' => 'Locations', 'classe' => '6', 'archive' => false];

        $demande($compte)->assertJsonPath('rejected.0.motif', "Ce poste utilise l'ancien plan comptable : mettez-le à jour avant de proposer un compte.");
        $this->assertNull(PlanComptable::query()->find('613'), '613 (ancien numero des locations) ne renait pas');

        $demande(array_merge($compte, ['plan_version' => 2, 'numero_compte' => '6221', 'libelle' => 'Location enclos']))->assertJsonPath('rejected', []);
        $this->assertSame('Location enclos', PlanComptable::query()->find('6221')->libelle);
    }
}
