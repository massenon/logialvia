<?php

namespace Tests\Feature\Web;

use App\Models\EcritureComptable;
use App\Models\PieceComptable;
use App\Services\Comptabilite\EcrituresAutomatiquesAchats as Achats;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\MoteurComptable;
use App\Services\Comptabilite\Saisie;
use App\Services\Comptabilite\Soldes;
use App\Support\PlanSyscohada;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\JeuComptable;
use Tests\TestCase;

/**
 * TVA DEDUCTIBLE des achats (`47p_` §6) : MEMES jeux chiffres a la main que
 * `test/comptabilite/plan_syscohada_test.dart` (poste). Montants TTC, TVA extraite au taux du compte (4452).
 */
class EcrituresAutomatiquesAchatsTvaTest extends TestCase
{
    use JeuComptable, RefreshDatabase;

    private Achats $achats;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerPourLesEcrans();
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-11-09 12:00:00', config('logialvia.fuseau')));
        $this->achats = new Achats(new Saisie($this->utilisateurAvecRole('comptable', 'paul')));
    }

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    /** Lignes d'une piece, debit decroissant puis compte (comme le poste). */
    private function piece(string $numero): array
    {
        $p = PieceComptable::query()->with('lignes')->where('numero_piece', $numero)->sole();
        $l = $p->lignes->map(fn (EcritureComptable $x) => [(string) $x->numero_compte, (float) $x->debit, (float) $x->credit])->all();
        usort($l, fn ($a, $b) => [$b[1], strcmp($a[0], $b[0])] <=> [$a[1], 0]);

        return $l;
    }

    private function acheter(string $ref, ?string $mode, float $total, float $paye, array $ventilation, array $taux = []): void
    {
        $this->assertNull($this->achats->pourAchat($ref, Saisie::instantMaintenant(), $mode, $total, $paye, $ventilation, $taux));
    }

    public function test_achat_de_matieres_59000_ttc_a_18_non_regle(): void
    {
        $this->acheter('ACH-1', 'Espèces', 59000, 0, [PlanSyscohada::ACHATS_MATIERES => 59000], [PlanSyscohada::ACHATS_MATIERES => 18]);

        $this->assertSame([['602', 50000.0, 0.0], ['4452', 9000.0, 0.0], ['401', 0.0, 59000.0]], $this->piece('ACH-1'));
    }

    public function test_achat_mixte_matieres_taxables_veterinaire_exonere_regle_en_partie(): void
    {
        $this->acheter('ACH-2', 'Mobile Money', 70800, 20000,
            [PlanSyscohada::ACHATS_MATIERES => 59000, PlanSyscohada::FRAIS_VETERINAIRES => 11800],
            [PlanSyscohada::ACHATS_MATIERES => 18]);

        $this->assertSame([['602', 50000.0, 0.0], ['604', 11800.0, 0.0], ['4452', 9000.0, 0.0], ['401', 0.0, 50800.0], ['552', 0.0, 20000.0]], $this->piece('ACH-2'));
    }

    public function test_achat_exonere_aucune_tva_tout_en_charge(): void
    {
        $this->acheter('ACH-3', 'Espèces', 12000, 12000, [PlanSyscohada::ACHATS_MATIERES => 12000]);

        $this->assertSame([['602', 12000.0, 0.0], ['571', 0.0, 12000.0]], $this->piece('ACH-3'));
    }

    public function test_le_resultat_ne_contient_plus_de_tva_et_le_bilan_reste_equilibre(): void
    {
        // Achat de marchandises 5 900 TTC (900 de TVA) payee comptant ; vente de 11 800 TTC (1 800) comptant.
        $this->acheter('A-1', 'Espèces', 5900, 5900, [PlanSyscohada::ACHATS_MARCHANDISES => 5900], [PlanSyscohada::ACHATS_MARCHANDISES => 18]);
        $this->assertNull((new Saisie($this->utilisateurAvecRole('comptable', 'paul2')))->enregistrer(
            Saisie::instantMaintenant(), 'VT', 'V-1', [
                ['compte' => '571', 'debit' => 11800, 'credit' => 0, 'libelle' => 'Vente'],
                ['compte' => '701', 'debit' => 0, 'credit' => 10000, 'libelle' => 'Vente'],
                ['compte' => '4431', 'debit' => 0, 'credit' => 1800, 'libelle' => 'TVA'],
            ],
        ));
        $s = Soldes::depuis(LivreComptable::toutes());

        $this->assertEquals(5000.0, MoteurComptable::resultatNet($s));
        $this->assertEquals(-1800.0, $s->solde('4431'));
        $this->assertEquals(900.0, $s->solde('4452'));
        $this->assertTrue(MoteurComptable::bilan($s)['equilibre']);
    }

    public function test_sens_naturel_tva_collectee_creditrice_recuperable_debitrice(): void
    {
        $sens = fn (string $n, string $c) => (new \App\Models\PlanComptable(['numero_compte' => $n, 'classe' => $c]))->estDebiteurParNature();
        $this->assertFalse($sens('4431', '4'));
        $this->assertFalse($sens('4441', '4'));
        $this->assertTrue($sens('4452', '4'));
        $this->assertTrue($sens('4449', '4'));
        $this->assertTrue($sens('409', '4'));
        $this->assertFalse($sens('401', '4'));
        $this->assertFalse($sens('419', '4'));
        $this->assertTrue($sens('571', '5'));
    }
}
