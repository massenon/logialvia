<?php

namespace Tests\Unit;

use App\Models\CycleCouveuse;
use App\Support\SuiviIncubation;
use Carbon\CarbonImmutable;
use Illuminate\Support\Str;
use PHPUnit\Framework\TestCase;

/**
 * Port des calculs du poste : memes valeurs que `suivi_incubation_test.dart`,
 * `statistiques_mirages_test.dart` et `cycle_couveuse_test.dart`.
 */
class SuiviIncubationTest extends TestCase
{
    private function lot(array $s = []): CycleCouveuse
    {
        return (new CycleCouveuse)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'code_incubation' => 'C-2026-001', 'espece' => 'goliath',
            'date_incubation' => '2026-08-01', 'oeufs_couves' => 100, 'poussins_nes' => null, 'oeufs_perdus' => null,
            'statut' => 'En Incubation', 'machine_id' => null, 'oeufs_blancs_j7' => null,
            'oeufs_gates_j14' => null, 'lot_parent_id' => null,
        ], $s));
    }

    private function jour(string $date): CarbonImmutable
    {
        return CarbonImmutable::parse($date, 'UTC');
    }

    public function test_le_goliath_incube_21_jours_la_pintade_28(): void
    {
        $this->assertSame(21, SuiviIncubation::duree('goliath'));
        $this->assertSame(28, SuiviIncubation::duree('pintade'), 'pas 27 : corrigé par la Gérante');
        $this->assertSame(21, SuiviIncubation::duree('autruche'), 'espèce inconnue : Goliath, comme le poste');
        $this->assertSame('2026-08-22', SuiviIncubation::dateEclosionPrevue($this->lot())->format('Y-m-d'));
        $this->assertSame('2026-08-29', SuiviIncubation::dateEclosionPrevue($this->lot(['espece' => 'pintade']))->format('Y-m-d'));
        $this->assertSame('2026-08-08', SuiviIncubation::dateMirage1($this->lot())->format('Y-m-d'));
        $this->assertSame('2026-08-15', SuiviIncubation::dateMirage2($this->lot())->format('Y-m-d'));
    }

    public function test_le_ter_est_rapporte_aux_oeufs_retenus_et_le_brut_aux_oeufs_charges(): void
    {
        $lot = $this->lot(['oeufs_couves' => 100, 'oeufs_blancs_j7' => 10, 'oeufs_gates_j14' => 10, 'poussins_nes' => 64]);

        $this->assertSame(80, SuiviIncubation::retenus($lot));
        $this->assertEqualsWithDelta(80.0, SuiviIncubation::ter($lot), 0.001);
        $this->assertEqualsWithDelta(64.0, SuiviIncubation::tauxBrut($lot), 0.001);
    }

    public function test_sans_eclosion_ou_sans_oeuf_retenu_il_n_y_a_pas_de_taux(): void
    {
        $this->assertNull(SuiviIncubation::ter($this->lot()));
        $this->assertNull(SuiviIncubation::tauxBrut($this->lot()));
        $vide = $this->lot(['oeufs_blancs_j7' => 60, 'oeufs_gates_j14' => 40, 'poussins_nes' => 0]);
        $this->assertNull(SuiviIncubation::ter($vide), 'un lot vidé aux mirages n\'a pas de taux : pas 0 %');
    }

    public function test_pourcentage_a_la_francaise(): void
    {
        $this->assertSame('85,0 %', SuiviIncubation::pourcentage(85.0));
        $this->assertSame('88,2 %', SuiviIncubation::pourcentage(88.235));
        $this->assertSame('—', SuiviIncubation::pourcentage(null));
    }

    public function test_les_alertes_sont_dues_tant_que_le_mirage_n_est_pas_saisi_le_plus_en_retard_d_abord(): void
    {
        $lots = collect([$this->lot(['oeufs_blancs_j7' => 10])]);

        $this->assertSame([], SuiviIncubation::alertes($lots, $this->jour('2026-08-05')));
        $a = SuiviIncubation::alertes(collect([$this->lot()]), $this->jour('2026-08-18'));
        $this->assertSame(['mirage1', 'mirage2'], array_column($a, 'type'));
        $this->assertSame([10, 3], array_column($a, 'ecart'), 'le plus en retard d\'abord');
        $aujourdhui = SuiviIncubation::alertes(collect([$this->lot()]), $this->jour('2026-08-08'));
        $this->assertSame(0, $aujourdhui[0]['ecart']);
    }

    public function test_un_lot_clos_n_alerte_plus(): void
    {
        $lots = collect([$this->lot(['statut' => 'Éclosion Effectuée', 'poussins_nes' => 80])]);

        $this->assertSame([], SuiviIncubation::alertes($lots, $this->jour('2026-09-30')));
        $this->assertSame([], SuiviIncubation::aVenir($lots, $this->jour('2026-08-20')));
    }

    public function test_la_pintade_n_est_pas_alertee_avec_le_goliath(): void
    {
        $lots = collect([$this->lot(['code_incubation' => 'G']), $this->lot(['code_incubation' => 'P', 'espece' => 'pintade'])]);

        $eclosions = array_filter(SuiviIncubation::alertes($lots, $this->jour('2026-08-22')), fn ($a) => $a['type'] === 'eclosion');

        $this->assertSame(['G'], array_values(array_map(fn ($a) => $a['lot']->code_incubation, $eclosions)));
    }

    public function test_les_echeances_a_venir_couvrent_les_3_prochains_jours_sans_inclure_aujourd_hui(): void
    {
        $lots = collect([$this->lot(['oeufs_blancs_j7' => 5])]);

        $aVenir = SuiviIncubation::aVenir($lots, $this->jour('2026-08-12'));
        $this->assertSame(['mirage2'], array_column($aVenir, 'type'));      // le 15/08, dans 3 jours
        $this->assertSame([-3], array_column($aVenir, 'ecart'));
        $this->assertSame([], SuiviIncubation::aVenir($lots, $this->jour('2026-08-15')), 'le jour même relève des alertes');
        $this->assertSame([], SuiviIncubation::aVenir($lots, $this->jour('2026-08-11')), 'dans 4 jours : trop tôt');
    }

    public function test_le_ter_moyen_est_pondere_par_les_oeufs_retenus(): void
    {
        // 300 retenus -> 270 éclos, 12 retenus -> 0 éclos : pondéré = 270 / 312, pas (90 + 0) / 2.
        $lots = collect([
            $this->lot(['oeufs_couves' => 300, 'poussins_nes' => 270, 'statut' => 'Éclosion Effectuée']),
            $this->lot(['oeufs_couves' => 12, 'poussins_nes' => 0, 'statut' => 'Éclosion Effectuée']),
        ]);

        $this->assertEqualsWithDelta(270 / 312 * 100, SuiviIncubation::terMoyen($lots, $this->jour('2026-09-30')), 0.001);
        $this->assertNull(SuiviIncubation::terMoyen($lots, $this->jour('2026-08-10')), 'à cette date, aucune éclosion prévue n\'est échue');
        $this->assertNull(SuiviIncubation::terMoyen(collect([$this->lot()]), $this->jour('2026-09-30')));
    }

    public function test_le_taux_brut_moyen_est_la_moyenne_des_taux_et_les_poussins_attendus_en_decoulent(): void
    {
        $lots = collect([
            $this->lot(['oeufs_couves' => 100, 'poussins_nes' => 80, 'statut' => 'Éclosion Effectuée']),
            $this->lot(['oeufs_couves' => 100, 'poussins_nes' => 60, 'statut' => 'Éclosion Effectuée']),
            $this->lot(['oeufs_couves' => 200]),
        ]);

        $this->assertEqualsWithDelta(70.0, SuiviIncubation::tauxBrutMoyen($lots), 0.001);
        $this->assertSame(140, SuiviIncubation::poussinsAttendus($lots), '200 œufs en cours × 70 %');
        $this->assertSame(0, SuiviIncubation::poussinsAttendus(collect([$this->lot()])), 'sans historique : aucune projection');
        $this->assertNull(SuiviIncubation::tauxBrutMoyen(collect([$this->lot()])));
    }

    public function test_l_occupation_ne_compte_que_les_lots_en_incubation_et_les_oeufs_retenus(): void
    {
        $lots = collect([
            $this->lot(['machine_id' => 'm1', 'oeufs_couves' => 100, 'oeufs_blancs_j7' => 10]),
            $this->lot(['machine_id' => 'm1', 'oeufs_couves' => 50, 'statut' => 'Éclosion Effectuée', 'poussins_nes' => 40]),
            $this->lot(['machine_id' => 'm2', 'oeufs_couves' => 200]),
        ]);

        $this->assertSame(90, SuiviIncubation::occupation($lots, 'm1'));
        $this->assertSame(200, SuiviIncubation::occupation($lots, 'm2'));
        $this->assertSame(0, SuiviIncubation::occupation($lots, 'm3'));
        $this->assertSame(290, SuiviIncubation::oeufsEnIncubation($lots));
    }

    public function test_les_statistiques_de_mirage_d_un_lot(): void
    {
        $lot = $this->lot(['oeufs_couves' => 200, 'oeufs_blancs_j7' => 20, 'oeufs_gates_j14' => 18, 'poussins_nes' => 120]);

        $this->assertEqualsWithDelta(10.0, SuiviIncubation::tauxInfertilite($lot), 0.001);
        $this->assertEqualsWithDelta(10.0, SuiviIncubation::mortaliteEmbryonnaire($lot), 0.001, 'gâtés / œufs présents au 2e mirage (180)');
        $this->assertEqualsWithDelta(40.0, SuiviIncubation::tauxPerteLot($lot), 0.001);
        $this->assertNull(SuiviIncubation::tauxInfertilite($this->lot()));
        $this->assertNull(SuiviIncubation::mortaliteEmbryonnaire($this->lot(['oeufs_blancs_j7' => 5])));
        $this->assertNull(SuiviIncubation::tauxPerteLot($this->lot()), 'un lot encore en machine n\'a rien perdu');
    }

    public function test_les_taux_agreges_ne_comptent_que_les_lots_mires(): void
    {
        $lots = collect([
            $this->lot(['oeufs_couves' => 200, 'oeufs_blancs_j7' => 20, 'oeufs_gates_j14' => 10, 'poussins_nes' => 150, 'statut' => 'Éclosion Effectuée']),
            $this->lot(['oeufs_couves' => 100, 'oeufs_blancs_j7' => 10]),
            $this->lot(['oeufs_couves' => 50]),   // jamais miré : ne dilue pas l'infertilité
        ]);

        $a = SuiviIncubation::agregat($lots);

        $this->assertEqualsWithDelta(10.0, $a['infertilite'], 0.001, '30 / 300');
        $this->assertEqualsWithDelta(10 / 180 * 100, $a['mortalite'], 0.001);
        $this->assertEqualsWithDelta(150 / 170 * 100, $a['ter'], 0.001);
        $this->assertEqualsWithDelta(25.0, $a['perte'], 0.001);
        $this->assertSame(310, $a['retenus']);
    }

    public function test_les_mirages_manquants_ne_concernent_que_les_lots_en_cours_dont_l_echeance_est_passee(): void
    {
        $lots = collect([
            $this->lot(['code_incubation' => 'A']),                                        // mirage 1 dû
            $this->lot(['code_incubation' => 'B', 'oeufs_blancs_j7' => 3, 'oeufs_gates_j14' => 2]), // tout fait
            $this->lot(['code_incubation' => 'C', 'date_incubation' => '2026-08-10']),    // pas encore dû
            $this->lot(['code_incubation' => 'D', 'statut' => 'Éclosion Effectuée', 'poussins_nes' => 5]),
        ]);

        $this->assertSame(['A'], SuiviIncubation::miragesManquants($lots, $this->jour('2026-08-09'))->pluck('code_incubation')->all());
    }

    public function test_l_age_et_la_date_sont_des_jours_civils_insensibles_au_fuseau(): void
    {
        $lot = $this->lot();

        $this->assertSame(7, SuiviIncubation::age($lot, CarbonImmutable::parse('2026-08-08 23:59', 'Africa/Porto-Novo')));
        $this->assertSame(0, SuiviIncubation::age($lot, CarbonImmutable::parse('2026-08-01 00:00', 'Africa/Porto-Novo')));
        $this->assertSame('2026-08-01', SuiviIncubation::jour(CarbonImmutable::parse('2026-08-01 23:30', 'Africa/Porto-Novo'))->format('Y-m-d'));
    }
}
