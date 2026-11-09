<?php

namespace Tests\Feature\Web;

use App\Livewire\BalanceGenerale;
use App\Livewire\Cloture;
use App\Livewire\EtatsFinanciers;
use App\Livewire\Journal;
use App\Models\EcritureComptable;
use App\Models\ExerciceComptable;
use App\Models\PieceComptable;
use App\Models\PlanComptable;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\MoteurComptable;
use App\Services\Comptabilite\ReportANouveau;
use App\Sync\Tables\ClotureExerciceTable;
use App\Sync\Tables\EcrituresTable;
use App\Support\UuidDeterministe;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\Concerns\JeuComptable;
use Tests\TestCase;

/**
 * Report a nouveau et cloture annuelle SYSCOHADA (`47c_`) — port fidele du Dart
 * (`report_a_nouveau_test.dart`). Chiffres calcules A LA MAIN, memes que le poste (jeu N) :
 *
 *   apport 531 D 1 000 000 / 101 C ; vente 531 D 600 000 / 701 C ; achat 601 D 250 000 / 401 C ;
 *   depense 624 D 50 000 / 531 C ; immobilisation 231 D 300 000 / 531 C.
 *
 * Produits 600 000 − charges 300 000 = resultat 300 000. Soldes de bilan en fin d'exercice :
 * 531 D 1 250 000 ; 231 D 300 000 ; 101 C 1 000 000 ; 401 C 250 000. Affectation : reserve legale
 * 30 000, dividendes 100 000, report a nouveau 170 000. A-nouveaux : D 1 550 000 = C 1 550 000.
 */
class ReportANouveauTest extends TestCase
{
    use JeuComptable, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerPourLesEcrans();
        PlanComptable::query()->firstOrCreate(['numero_compte' => '231'], ['libelle' => 'Bâtiments', 'classe' => '2', 'archive' => false]);
    }

    private function jeu(): int
    {
        $n = $this->annee();
        $this->poserPiece('P1', $n, 1, 5, 'OD', [['571', 1000000, 0, null], ['101', 0, 1000000, null]]);
        $this->poserPiece('P2', $n, 2, 5, 'OD', [['571', 600000, 0, null], ['702', 0, 600000, null]]);
        $this->poserPiece('P3', $n, 3, 5, 'OD', [['602', 250000, 0, null], ['401', 0, 250000, null]]);
        $this->poserPiece('P4', $n, 4, 5, 'OD', [['618', 50000, 0, null], ['571', 0, 50000, null]]);
        $this->poserPiece('P5', $n, 5, 5, 'OD', [['231', 300000, 0, null], ['571', 0, 300000, null]]);

        return $n;
    }

    private function toutes(): array
    {
        return LivreComptable::toutes()->all();
    }

    private function net(string $journal, int $exercice, string $compte): float
    {
        return (float) collect($this->toutes())
            ->filter(fn ($e) => $e->journal === $journal && $e->exercice === $exercice && $e->compte === $compte)
            ->sum(fn ($e) => $e->debit - $e->credit);
    }

    private function cloturer(int $n, array $champs = []): \Livewire\Features\SupportTesting\Testable
    {
        $c = Livewire::test(Cloture::class)->call('demanderCloture');
        foreach ($champs as $nom => $valeur) {
            $c->set($nom, $valeur);
        }

        return $c->call('cloturerExercice');
    }

    // ------------------------------------------------------------ Calcul pur

    public function test_le_calcul_donne_resultat_300000_trois_pieces_et_des_a_nouveaux_equilibres(): void
    {
        $n = $this->jeu();
        $affectation = ReportANouveau::affectation(['reserve_legale' => 30000, 'dividendes' => 100000]);
        $c = ReportANouveau::calculer($this->toutes(), $n, $affectation);

        $this->assertSame([], $c['anomalies']);
        $this->assertSame(300000.0, $c['resultat']);
        $this->assertSame(["CL-$n-RESULTAT", "CL-$n-AFFECTATION", 'AN-'.($n + 1)], array_column($c['pieces'], 'numero'));

        // Piece de resultat : 601 et 624 creditees (250 000 + 50 000), 701 debitee 600 000, 131 creditee 300 000.
        $res = $c['pieces'][0]['lignes'];
        $this->assertSame(600000.0, (float) array_sum(array_column($res, 'debit')));
        $this->assertSame(600000.0, (float) array_sum(array_column($res, 'credit')));

        $aff = collect($c['pieces'][1]['lignes'])->mapWithKeys(fn ($l) => [$l['compte'] => $l['credit']])->all();
        $this->assertEquals(['131' => 0, '111' => 30000, '465' => 100000, '121' => 170000], $aff);

        $this->assertEquals([
            '101' => -1000000.0, '111' => -30000.0, '121' => -170000.0, '231' => 300000.0,
            '401' => -250000.0, '465' => -100000.0, '571' => 1250000.0,
        ], $c['reportes']);
        $an = end($c['pieces']);
        $this->assertSame(1550000.0, (float) array_sum(array_column($an['lignes'], 'debit')));
        $this->assertSame(1550000.0, (float) array_sum(array_column($an['lignes'], 'credit')));
        foreach ($an['lignes'] as $l) {
            $this->assertNotContains($l['compte'][0], ['6', '7', '8'], 'jamais de classe 6, 7 ni 8 dans les a-nouveaux');
        }
    }

    public function test_une_perte_va_au_129_et_aucun_dividende_n_est_possible(): void
    {
        $n = $this->jeu();
        $this->poserPiece('P6', $n, 6, 5, 'OD', [['618', 800000, 0, null], ['571', 0, 800000, null]]);
        $c = ReportANouveau::calculer($this->toutes(), $n);

        $this->assertSame(-500000.0, $c['resultat']);
        $this->assertSame([['129', 500000.0, 0.0], ['139', 0.0, 500000.0]], array_map(fn ($l) => [$l['compte'], $l['debit'], $l['credit']], $c['pieces'][1]['lignes']));
        $this->assertEquals(500000.0, $c['reportes']['129']);

        $refus = ReportANouveau::validerAffectation(ReportANouveau::affectation(['dividendes' => 1]), -100.0);
        $this->assertStringContainsString('Aucune distribution', (string) $refus);
        $this->assertNotNull(ReportANouveau::validerAffectation(ReportANouveau::affectation(['dividendes' => 300001]), 300000.0));
        $this->assertStringContainsString('absorber', (string) ReportANouveau::validerAffectation(ReportANouveau::affectation(['dividendes' => 250000]), 300000.0, 100000.0));
    }

    public function test_la_classe_8_entre_dans_le_resultat_net(): void
    {
        $n = $this->jeu();
        PlanComptable::query()->create(['numero_compte' => '891', 'libelle' => 'Impôt sur le résultat', 'classe' => '8', 'archive' => false]);
        $this->poserPiece('P7', $n, 7, 5, 'OD', [['891', 75000, 0, null], ['571', 0, 75000, null]]);

        $this->assertSame(225000.0, MoteurComptable::resultatNet(ReportANouveau::soldesDeFin($this->toutes(), $n)));
        $this->assertSame(225000.0, ReportANouveau::calculer($this->toutes(), $n)['resultat']);
    }

    public function test_les_identifiants_sont_ceux_du_poste(): void
    {
        // Calcules par `uuidDeterministe` du Dart (report_a_nouveau_test.dart).
        $this->assertSame('6d8b152a-62f8-57ae-a525-cb336a28a3c3', ReportANouveau::idPiece('cloture:2026:resultat'));
        $this->assertSame('f8658418-261c-542b-9baa-5a6204579d85', ReportANouveau::idPiece('an:2027'));
        $this->assertSame('735d7a68-4f35-5cd8-8097-0400f95b9bc6', ReportANouveau::idLigne('an:2027', '531'));
    }

    // ------------------------------------------------------- Cloture ecrite

    public function test_la_cloture_ecrit_cl_et_an_verrouille_et_solde_les_classes_6_7(): void
    {
        $n = $this->jeu();
        $admin = $this->utilisateurAvecRole('admin', 'gerante');
        $this->actingAs($admin);

        $this->cloturer($n, ['reserveLegale' => '30000', 'dividendes' => '100000'])->assertSet('erreur', null)
            ->assertSee("Exercice $n clôturé");

        foreach (['602', '618', '702', '131'] as $compte) {
            $this->assertSame(0.0, (float) collect($this->toutes())->filter(fn ($e) => $e->exercice === $n && $e->compte === $compte)->sum(fn ($e) => $e->debit - $e->credit), "compte $compte solde");
        }
        $this->assertSame(-170000.0, (float) collect($this->toutes())->filter(fn ($e) => $e->exercice === $n && $e->compte === '121')->sum(fn ($e) => $e->debit - $e->credit));

        $an = collect($this->toutes())->filter(fn ($e) => $e->journal === 'AN' && $e->exercice === $n + 1);
        $this->assertCount(7, $an);
        $this->assertSame(1550000.0, (float) $an->sum('debit'));
        $this->assertSame(1550000.0, (float) $an->sum('credit'));
        $this->assertSame(1250000.0, $this->net('AN', $n + 1, '571'));
        $this->assertTrue((bool) ExerciceComptable::query()->find($n)->is_cloture);
        $this->assertEqualsCanonicalizing(['reserve_legale' => 30000, 'autres_reserves' => 0, 'dividendes' => 100000], json_decode(ExerciceComptable::query()->find($n)->affectation, true));
        $this->assertDatabaseHas('clotures_exercice', ['annee' => $n]);

        // Les identifiants sont ceux du poste.
        $this->assertTrue(PieceComptable::query()->whereKey(ReportANouveau::idPiece('an:'.($n + 1)))->exists());
    }

    public function test_la_cloture_est_idempotente_rejouee_elle_ne_duplique_rien(): void
    {
        $n = $this->jeu();
        $admin = $this->utilisateurAvecRole('admin', 'gerante');
        $this->actingAs($admin);
        $this->cloturer($n);
        $pieces = PieceComptable::query()->count();
        $lignes = EcritureComptable::query()->count();

        // Rejeu du fait de cloture (autre poste, reprise reseau) : accepte, rien ne change.
        $motif = (new ClotureExerciceTable)->pourUtilisateur($admin)->absorber('11111111-1111-4111-8111-111111111111', [
            'id' => UuidDeterministe::clotureExercice($n), 'annee' => $n,
            'date_cloture' => now()->toIso8601String(), 'updated_at' => now()->toIso8601String(),
        ]);

        $this->assertNull($motif);
        $this->assertSame($pieces, PieceComptable::query()->count());
        $this->assertSame($lignes, EcritureComptable::query()->count());
    }

    public function test_une_affectation_incoherente_refuse_la_cloture_sans_rien_ecrire(): void
    {
        $n = $this->jeu();
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));

        $this->cloturer($n, ['dividendes' => '999999'])->assertSet('erreur', "L'affectation (999999) dépasse le bénéfice (300000).");

        $this->assertFalse((bool) ExerciceComptable::query()->find($n)->is_cloture);
        $this->assertSame(0, PieceComptable::query()->whereIn('journal_code', ['CL', 'AN'])->count());
    }

    public function test_un_poste_ne_peut_pas_envoyer_de_pieces_cl_ou_an(): void
    {
        $n = $this->annee();
        $admin = $this->utilisateurAvecRole('admin', 'gerante');
        foreach (['CL', 'AN'] as $journal) {
            $motif = (new EcrituresTable)->pourUtilisateur($admin)->absorber('11111111-1111-4111-8111-111111111111', [
                'id' => (string) \Illuminate\Support\Str::uuid(), 'numero_piece' => 'X', 'date_ecriture' => now()->toIso8601String(),
                'exercice_annee' => $n, 'journal_code' => $journal, 'plan_version' => 2, 'updated_at' => now()->toIso8601String(),
                'lignes' => [
                    ['id' => (string) \Illuminate\Support\Str::uuid(), 'numero_compte' => '571', 'debit' => 5, 'credit' => 0, 'libelle' => 'x'],
                    ['id' => (string) \Illuminate\Support\Str::uuid(), 'numero_compte' => '101', 'debit' => 0, 'credit' => 5, 'libelle' => 'x'],
                ],
            ]);
            $this->assertStringContainsString('code journal est inconnu', (string) $motif);
        }
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_seule_l_administratrice_cloture_et_rouvre(): void
    {
        $n = $this->jeu();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        Livewire::test(Cloture::class)->call('demanderReouverture')->assertForbidden();
        Livewire::test(Cloture::class)->call('rouvrirExercice')->assertForbidden();

        $motif = (new ClotureExerciceTable)->pourUtilisateur(auth()->user())->rouvrir($n);
        $this->assertStringContainsString('Droit insuffisant', (string) $motif);
    }

    // ------------------------------------------------------------ Reouverture

    public function test_rouvrir_annule_les_a_nouveaux_et_les_ecritures_de_cloture_puis_on_recloture(): void
    {
        $n = $this->jeu();
        $admin = $this->utilisateurAvecRole('admin', 'gerante');
        $this->actingAs($admin);
        $this->cloturer($n, ['reserveLegale' => '30000']);

        Livewire::test(Cloture::class)->call('demanderReouverture')->assertSeeHtml('data-modale="reouverture"')
            ->call('rouvrirExercice')->assertSet('erreur', null)->assertSee("Exercice $n rouvert");

        $e = ExerciceComptable::query()->find($n);
        $this->assertFalse((bool) $e->is_cloture);
        $this->assertNotNull($e->rouvert_le, 'les postes suivent la reouverture');
        $this->assertNull($e->affectation);
        $this->assertSame(0, PieceComptable::query()->whereIn('journal_code', ['CL', 'AN'])->count());
        $this->assertDatabaseMissing('clotures_exercice', ['annee' => $n]);
        $this->assertDatabaseHas('audit_logs', ['action' => 'comptabilite.reouverture_exercice']);

        $this->cloturer($n);
        $this->assertSame(1, PieceComptable::query()->where('journal_code', 'AN')->count());
        $this->assertNull(ExerciceComptable::query()->find($n)->rouvert_le);
    }

    public function test_rouvrir_est_refuse_si_l_exercice_suivant_est_cloture(): void
    {
        $n = $this->jeu();
        $admin = $this->utilisateurAvecRole('admin', 'gerante');
        $this->actingAs($admin);
        $this->cloturer($n);
        ExerciceComptable::query()->where('annee', $n + 1)->update(['is_cloture' => true]);

        $motif = (new ClotureExerciceTable)->pourUtilisateur($admin)->rouvrir($n);

        $this->assertSame('L\'exercice '.($n + 1).' est clôturé : rouvrez-le d\'abord.', $motif);
        $this->assertTrue((bool) ExerciceComptable::query()->find($n)->is_cloture);
    }

    // ------------------------------------------------------ Etats de N+1

    public function test_les_etats_de_l_exercice_suivant_partent_de_l_ouverture(): void
    {
        $n = $this->jeu();
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));
        $this->cloturer($n, ['reserveLegale' => '30000', 'dividendes' => '100000']);
        $this->poserPiece('V25', $n + 1, 2, 5, 'OD', [['571', 200000, 0, null], ['702', 0, 200000, null]]);

        $soldes = ReportANouveau::soldesDeFin($this->toutes(), $n + 1);
        $bilan = MoteurComptable::bilan($soldes);
        // Actif 300 000 + 1 450 000 = 1 750 000 ; passif 1 000 000 + 200 000 (30 000 + 170 000) + 200 000 + 250 000 + 100 000.
        $this->assertSame(1750000.0, $bilan['total_actif']);
        $this->assertSame(1750000.0, $bilan['total_passif']);
        $this->assertTrue($bilan['equilibre']);
        $this->assertSame(200000.0, MoteurComptable::resultatNet($soldes));

        $tafire = MoteurComptable::tafire($soldes, ReportANouveau::soldesDOuverture($this->toutes(), $n + 1));
        $this->assertSame(1250000.0, $tafire['tresorerie_ouverture']);
        $this->assertSame(200000.0, $tafire['flux_exploitation']);
        $this->assertSame(0.0, $tafire['flux_investissement'] + 0.0);
        $this->assertSame(0.0, $tafire['flux_financement'] + 0.0);
        $this->assertSame(1450000.0, $tafire['tresorerie_cloture']);

        Livewire::test(EtatsFinanciers::class)->set('exercice', $n + 1)->call('choisir', 'flux')
            ->assertSee('Trésorerie de clôture (TAFIRE) = Trésorerie nette (Bilan) = 1 450 000 FCFA.')->assertDontSee('Incohérence');
    }

    public function test_la_balance_de_l_exercice_suivant_a_pour_ouverture_les_a_nouveaux(): void
    {
        $n = $this->jeu();
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));
        $this->cloturer($n);
        $this->poserPiece('V25', $n + 1, 2, 5, 'OD', [['571', 200000, 0, null], ['702', 0, 200000, null]]);

        Livewire::test(BalanceGenerale::class)->set('exercice', $n + 1)
            ->assertDontSeeHtml('data-bandeau="desequilibre"')
            ->assertSeeHtmlInOrder(['data-compte="571"', '1 250 000', '200 000', '1 450 000'])
            ->assertDontSeeHtml('data-compte="602"');

        // L'exercice clos se lit encore : 701 y est solde par la cloture, la balance reste equilibree.
        Livewire::test(BalanceGenerale::class)->set('exercice', $n)->assertDontSeeHtml('data-bandeau="desequilibre"')->assertSeeHtml('data-compte="131"');
    }

    public function test_sans_cloture_l_ouverture_est_une_cloture_virtuelle(): void
    {
        $n = $this->jeu();
        $this->poserPiece('V25', $n + 1, 2, 5, 'OD', [['571', 200000, 0, null], ['702', 0, 200000, null]]);

        $ouverture = ReportANouveau::soldesOuverture($this->toutes(), $n + 1);
        $this->assertSame(1250000.0, $ouverture['571']);
        $this->assertSame(-300000.0, $ouverture['121']);
        foreach (array_keys($ouverture) as $compte) {
            $this->assertNotContains(((string) $compte)[0], ['6', '7', '8']);
        }
        $this->assertTrue(MoteurComptable::bilan(ReportANouveau::soldesDeFin($this->toutes(), $n + 1))['equilibre']);
    }

    public function test_le_journal_montre_les_pieces_de_cloture_et_les_filtre(): void
    {
        $n = $this->jeu();
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));
        $this->cloturer($n);

        Livewire::test(Journal::class)->set('exercice', $n)->set('journal', 'CL')->assertSee("CL-$n-RESULTAT")->assertDontSee('P1');
        Livewire::test(Journal::class)->set('exercice', $n + 1)->set('journal', 'AN')->assertSee('AN-'.($n + 1));
    }

    public function test_tafire_exact_avec_amortissement_et_emprunt(): void
    {
        $n = $this->jeu();
        foreach ([['281', 'Amortissements', '2'], ['681', 'Dotations amortissements', '6'], ['161', 'Emprunts', '1']] as [$c, $l, $k]) {
            PlanComptable::query()->firstOrCreate(['numero_compte' => $c], ['libelle' => $l, 'classe' => $k, 'archive' => false]);
        }
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));
        $this->cloturer($n, ['reserveLegale' => '30000', 'dividendes' => '100000']);
        $m = $n + 1;
        $this->poserPiece('E1', $m, 1, 5, 'OD', [['571', 400000, 0, null], ['161', 0, 400000, null]]);
        $this->poserPiece('A1', $m, 2, 5, 'OD', [['681', 30000, 0, null], ['281', 0, 30000, null]]);
        $this->poserPiece('V2', $m, 3, 5, 'OD', [['411', 100000, 0, null], ['702', 0, 100000, null]]);

        $soldes = ReportANouveau::soldesDeFin($this->toutes(), $m);
        $t = MoteurComptable::tafire($soldes, ReportANouveau::soldesDOuverture($this->toutes(), $m));
        // Resultat 70 000 + non decaisse 30 000 − creances 100 000 = 0 ; financement 400 000 (emprunt).
        $this->assertEqualsWithDelta(0.0, $t['flux_exploitation'], 0.001);
        $this->assertEqualsWithDelta(400000.0, $t['flux_financement'], 0.001);
        $this->assertEqualsWithDelta(1650000.0, $t['tresorerie_cloture'], 0.001);
        $this->assertEqualsWithDelta($soldes->parClasse('5'), $t['tresorerie_cloture'], 0.001);
        $this->assertTrue(MoteurComptable::bilan($soldes)['equilibre']);
    }
}
