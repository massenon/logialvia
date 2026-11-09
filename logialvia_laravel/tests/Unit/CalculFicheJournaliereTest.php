<?php

namespace Tests\Unit;

use App\Support\AgregationHebdomadaire;
use App\Support\CalculFicheJournaliere;
use PHPUnit\Framework\TestCase;

/**
 * Le calcul d'une journée du web reprend les cas de `calcul_fiche_journaliere_test.dart`
 * (le Dart est la source) : mêmes entrées, mêmes résultats.
 */
class CalculFicheJournaliereTest extends TestCase
{
    private function calculer(array $mouvements, array $veille = [40, 30, 24], int $total = 94, string $espece = 'goliaths'): array
    {
        return CalculFicheJournaliere::calculerJour($espece, $veille, $total, $mouvements);
    }

    public function test_mouvements_sur_plusieurs_categories(): void
    {
        $r = $this->calculer(['morts' => [2, 0, 1], 'dons' => [0, 1, 0], 'vente' => 3]);

        // Poussins 40 - 2 ; Goliathau 30 - 3 (vente) - 1 (don) ; Mature 24 - 1.
        $this->assertSame([38, 26, 23], $r['par_categorie']);
        $this->assertSame(94 - 3 - 3 - 1, $r['effectif_total']);
    }

    public function test_achats_et_naissances_alimentent_uniquement_la_categorie_jeune(): void
    {
        $r = $this->calculer(['achat' => 10, 'ne' => 5]);

        $this->assertSame([55, 30, 24], $r['par_categorie']);
        $this->assertSame(109, $r['effectif_total']);
    }

    public function test_la_vente_est_deduite_de_la_categorie_commercialisee_pas_du_mature(): void
    {
        $r = $this->calculer(['vente' => 6]);

        $this->assertSame([40, 24, 24], $r['par_categorie']);
        $this->assertSame(88, $r['effectif_total']);
    }

    public function test_les_dons_se_comportent_comme_les_morts(): void
    {
        $r = $this->calculer(['dons' => [3, 0, 2]]);

        $this->assertSame([37, 30, 22], $r['par_categorie']);
        $this->assertSame(89, $r['effectif_total']);
    }

    public function test_mouvements_combines(): void
    {
        $r = $this->calculer(['achat' => 5, 'ne' => 3, 'morts' => [2, 4, 1], 'dons' => [1, 1, 0]]);

        $this->assertSame([45, 25, 23], $r['par_categorie']);
        $this->assertSame(93, $r['effectif_total']);
        $this->assertSame(93, array_sum($r['par_categorie']));
    }

    public function test_aucun_effectif_negatif_a_partir_de_zero(): void
    {
        $r = $this->calculer(['morts' => [5, 5, 5]], [0, 0, 0], 0);

        $this->assertSame([0, 0, 0], $r['par_categorie']);
        $this->assertSame(0, $r['effectif_total']);
        $this->assertSame(0.0, $r['taux_mortalite']);
    }

    public function test_une_mortalite_totale_ramene_a_zero_avec_un_taux_de_100(): void
    {
        $r = $this->calculer(['morts' => [40, 30, 24]]);

        $this->assertSame([0, 0, 0], $r['par_categorie']);
        $this->assertSame(0, $r['effectif_total']);
        $this->assertSame(100.0, $r['taux_mortalite']);
    }

    public function test_une_vente_superieure_au_stock_est_bornee_a_zero(): void
    {
        $r = $this->calculer(['vente' => 999]);

        $this->assertSame(0, $r['par_categorie'][1]);
        $this->assertSame(0, $r['effectif_total']);
    }

    public function test_une_journee_sans_mouvement_laisse_tout_inchange(): void
    {
        $r = $this->calculer([]);

        $this->assertSame([40, 30, 24], $r['par_categorie']);
        $this->assertSame(94, $r['effectif_total']);
        $this->assertSame(0.0, $r['taux_mortalite']);
    }

    public function test_le_plafond_est_999999(): void
    {
        $r = $this->calculer(['achat' => 2_000_000]);

        $this->assertSame(999999, $r['par_categorie'][0]);
        $this->assertSame(999999, $r['effectif_total']);
    }

    public function test_taux_de_mortalite_du_jour(): void
    {
        $this->assertSame(5.0, CalculFicheJournaliere::tauxMortaliteJour(5, 100));
        $this->assertSame(0.0, CalculFicheJournaliere::tauxMortaliteJour(0, 94));
        $this->assertSame(0.0, CalculFicheJournaliere::tauxMortaliteJour(3, 0));
    }

    public function test_pondeuses_la_vente_sort_de_la_categorie_pondeuse_et_les_achats_vont_aux_poussins_ponte(): void
    {
        $r = $this->calculer(['achat' => 10, 'vente' => 4], [20, 10, 10, 30], 70, 'pondeuses');

        $this->assertSame([30, 10, 10, 26], $r['par_categorie']);
        $this->assertSame(76, $r['effectif_total']);
    }

    public function test_stock_d_oeufs(): void
    {
        // SRH 40 ; (100 - 10) + 40 = 130 ; sorties 2 plateaux x 30 = 60 ; final 70.
        $this->assertSame(
            ['srh' => 40, 'total_stock' => 130, 'sorties_oeufs' => 60, 'stock_final' => 70],
            CalculFicheJournaliere::stockOeufs(40, 100, 10, 2),
        );
        // Le stock final ne devient jamais negatif.
        $this->assertSame(0, CalculFicheJournaliere::stockOeufs(0, 10, 0, 5)['stock_final']);
    }

    public function test_poids_moyen(): void
    {
        $this->assertSame(333, CalculFicheJournaliere::poidsMoyenGrammes(1000, 3));
        $this->assertSame(0, CalculFicheJournaliere::poidsMoyenGrammes(1000, 0));
    }

    public function test_decoupage_hebdomadaire(): void
    {
        $this->assertSame([[1, 7], [8, 14], [15, 21], [22, 28]], AgregationHebdomadaire::decouper(28));
        $this->assertSame([22, 31], AgregationHebdomadaire::decouper(31)[3]);
    }

    public function test_agregation_hebdomadaire_cumule_et_reprend_la_veille_de_la_semaine(): void
    {
        $jour = fn (int $achat, int $morts, int $effectif) => [
            'achat' => $achat, 'ne' => 0, 'vente' => 0, 'morts' => [$morts, 0, 0], 'effectif' => $effectif, 'is_recorded' => true,
        ];
        $semaines = AgregationHebdomadaire::calculer(30, [3 => $jour(10, 1, 9), 7 => $jour(0, 2, 7), 9 => $jour(0, 1, 6)], 0);

        $this->assertSame(10, $semaines[0]['cumul_achats']);
        $this->assertSame(3, $semaines[0]['cumul_morts']);
        $this->assertSame(7, $semaines[0]['effectif_fin']);
        // La semaine 2 part de l'effectif du 7 ; sa mortalite = 1 / 7.
        $this->assertSame(7, $semaines[1]['effectif_debut']);
        $this->assertEqualsWithDelta(1 / 7 * 100, $semaines[1]['taux_mortalite'], 0.0001);
        $this->assertFalse($semaines[2]['a_des_journees_saisies']);
        $this->assertNull(AgregationHebdomadaire::calculer(30, [], 0)[0]['taux_mortalite'], 'sans effectif de depart : pas de taux');
    }
}
