<?php

namespace Tests\Feature\Web;

use App\Livewire\Analytique;
use App\Livewire\BalanceGenerale;
use App\Livewire\BilanEntreprise;
use App\Livewire\Depenses;
use App\Livewire\EtatsFinanciers;
use App\Livewire\GrandLivre;
use App\Livewire\Journal;
use App\Livewire\PlanComptableEcran;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\Concerns\JeuComptable;
use Tests\Concerns\LitXlsx;
use Tests\TestCase;

/**
 * Parite web ↔ poste : chaque tableau comptable s'exporte en XLSX (jamais CSV), avec le contenu de l'ecran,
 * sous le droit `view-comptabilite` verifie DANS la methode ; chaque ecran a sa vue imprimable
 * (bouton « Imprimer / PDF », feuille de style d'impression) — le PDF genere du poste n'est pas reproduit.
 */
class ComptabiliteExportsTest extends TestCase
{
    use JeuComptable, LitXlsx, RefreshDatabase;

    private const ECRANS = [
        Journal::class, GrandLivre::class, BalanceGenerale::class, PlanComptableEcran::class,
        Depenses::class, Analytique::class, EtatsFinanciers::class, BilanEntreprise::class,
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerPourLesEcrans();
    }

    private function xlsx($composant): array
    {
        return $this->lignesXlsx(base64_decode($composant->effects['download']['content']));
    }

    public function test_sans_le_droit_de_voir_la_comptabilite_aucun_export_ne_sort(): void
    {
        $this->poserLeJeuCommun();
        $caissier = User::factory()->create(['username' => 'nobody']);
        $this->actingAs($caissier);

        foreach (self::ECRANS as $classe) {
            Livewire::test($classe)->call('exporter')->assertForbidden();
        }
    }

    public function test_chaque_ecran_propose_l_export_xlsx_et_l_impression(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        foreach (self::ECRANS as $classe) {
            Livewire::test($classe)->assertSeeHtml('data-action="exporter"')->assertSeeHtml('data-action="imprimer"')
                ->assertSee('Exporter (XLSX)')->assertSee('Imprimer / PDF');
        }
        // L'entete d'impression ne s'affiche qu'a l'impression.
        Livewire::test(BalanceGenerale::class)->assertSeeHtml('data-entete-impression')->assertSeeHtml('print:block');
    }

    public function test_le_journal_s_exporte_avec_ses_filtres_et_ses_totaux(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $c = Livewire::test(Journal::class)->set('journal', 'VT')->call('exporter')->assertFileDownloaded('journal-comptable-'.$this->annee().'.xlsx');
        $lignes = $this->xlsx($c);

        $this->assertSame(['Date', 'Journal', 'Pièce', 'Compte', 'Libellé', 'Débit', 'Crédit'], $lignes[1]);
        // VT : deux ventes (120 000 + 30 000 + 50 000 au debit ; 120 000 + 80 000 au credit).
        $this->assertSame(['Total', '', '', '', '', '200000', '200000'], array_slice($lignes, -1)[0]);
        foreach (array_slice($lignes, 2, -1) as $l) {
            $this->assertSame('VT', $l[1]);
        }
    }

    public function test_la_balance_et_le_grand_livre_exportent_les_chiffres_de_l_ecran(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $balance = $this->xlsx(Livewire::test(BalanceGenerale::class)->call('exporter'));
        $total = end($balance);
        // Jeu commun, ouverture cumulee : ouverture 100 000 ; mouvements 987 000 ; soldes finaux 842 000.
        $this->assertSame(['Total', '', '100000', '100000', '987000', '987000', '842000', '842000'], $total);
        $c531 = collect($balance)->first(fn ($l) => ($l[0] ?? '') === '571');
        $this->assertSame('545000', $c531[6]);

        $gl = $this->xlsx(Livewire::test(GrandLivre::class)->set('compte', '571')->call('exporter'));
        $this->assertSame('Solde d\'ouverture', $gl[2][0]);
        $this->assertSame('100000', $gl[2][5]);
        $this->assertSame('545000', end($gl)[5]);
    }

    public function test_les_etats_s_exportent_par_onglet_et_le_bilan_reste_equilibre(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $bilan = $this->xlsx(Livewire::test(EtatsFinanciers::class)->call('exporter'));
        $this->assertContains('TOTAL GÉNÉRAL ACTIF', array_column($bilan, 0));
        $actif = collect($bilan)->first(fn ($l) => ($l[0] ?? '') === 'TOTAL GÉNÉRAL ACTIF')[2];
        $passif = collect($bilan)->first(fn ($l) => ($l[0] ?? '') === 'TOTAL GÉNÉRAL PASSIF')[2];
        $this->assertSame('775000', $actif);
        $this->assertSame($actif, $passif);

        $flux = $this->xlsx(Livewire::test(EtatsFinanciers::class)->call('choisir', 'flux')->call('exporter'));
        $this->assertContains('Trésorerie de clôture', array_column($flux, 0));
        $this->assertSame('545000', collect($flux)->first(fn ($l) => ($l[0] ?? '') === 'Trésorerie de clôture')[2]);

        $entreprise = $this->xlsx(Livewire::test(BilanEntreprise::class)->call('exporter'));
        $this->assertSame('775000', collect($entreprise)->first(fn ($l) => ($l[0] ?? '') === 'TOTAL ACTIF')[2]);
        $this->assertSame('775000', collect($entreprise)->first(fn ($l) => ($l[0] ?? '') === 'TOTAL PASSIF')[2]);
    }

    public function test_plan_depenses_et_analytique_s_exportent(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $plan = $this->xlsx(Livewire::test(PlanComptableEcran::class)->call('exporter'));
        $this->assertSame(['Compte', 'Libellé', 'Classe', 'Statut'], $plan[1]);
        $this->assertContains('111', array_column($plan, 0));
        $this->assertContains('129', array_column($plan, 0));

        $dep = $this->xlsx(Livewire::test(Depenses::class)->call('exporter'));
        $this->assertSame('Date', $dep[1][0]);
        // Deux depenses du jeu : 15 000 (624) + 12 000 (616).
        $this->assertSame('27000', end($dep)[4]);

        $ana = $this->xlsx(Livewire::test(Analytique::class)->call('exporter'));
        $this->assertSame(['Centre', 'Revenus', 'Coûts', 'Marge'], $ana[1]);
        $this->assertContains('Goliaths', array_column($ana, 0));
    }

    public function test_aucun_export_n_ecrit_en_csv(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        foreach (self::ECRANS as $classe) {
            $c = Livewire::test($classe)->call('exporter');
            $this->assertStringEndsWith('.xlsx', $c->effects['download']['name']);
        }
    }
}
