<?php

namespace Tests\Feature\Web;

use App\Models\ExerciceComptable;
use App\Services\Comptabilite\LivreComptable;
use App\Services\Comptabilite\MoteurComptable;
use App\Services\Comptabilite\RenumerotationPlan;
use App\Services\Comptabilite\Soldes;
use App\Support\PlanSyscohada;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Migration du serveur vers le plan SYSCOHADA (`47p_` §8) : MEME jeu chiffre a la main que le poste
 * (`migration_v48_plan_syscohada_test.dart`), ecritures de l'ANCIEN plan. Risques couverts : le croisement
 * 601↔602 et 613→622, les frais de livraison (707 sans centre → 7071) distincts des marchandises (707 → 701),
 * les sous-comptes (6011 → 6021), le rejeu, l'interruption, l'equilibre, les libelles et les etats financiers.
 */
class MigrationPlanSyscohadaTest extends TestCase
{
    use RefreshDatabase;

    private const ANCIEN_PLAN = [
        ['31', 'Stocks de Marchandises (Commerce Annexe)', '3'], ['32', 'Stocks de Matières (Intrants Provende)', '3'],
        ['401', 'Fournisseurs', '4'], ['411', 'Clients', '4'], ['419', 'Clients — Avances Reçues', '4'],
        ['512', 'Banques — Mobile Money', '5'], ['531', 'Caisse', '5'],
        ['601', 'Achats de Matières (Intrants Provende)', '6'], ['602', 'Achats de Marchandises (Commerce Annexe)', '6'],
        ['622', 'Frais Vétérinaires', '6'], ['701', 'Ventes de Produits Avicoles', '7'],
        ['707', 'Ventes de Marchandises (Commerce Annexe)', '7'], ['101', 'Capital Social', '1'],
        ['121', 'Report à Nouveau', '1'], ['131', 'Résultat de l\'Exercice', '1'], ['613', 'Locations', '6'],
        ['616', 'Assurances', '6'], ['624', 'Transports', '6'], ['628', 'Charges Diverses de Gestion', '6'],
        ['111', 'Réserve Légale', '1'], ['118', 'Autres Réserves', '1'], ['129', 'Report à Nouveau — Solde Débiteur', '1'],
        ['139', 'Résultat Net : Perte', '1'], ['465', 'Associés — Dividendes à Payer', '4'],
        ['6011', 'Aliment démarrage', '6'], ['6021', 'Marchandises revente', '6'],
    ];

    /** [piece, journal, vente_ref, [[compte, debit, credit, axe]]] — numerotation de l'ANCIEN plan. */
    private const PIECES = [
        ['P1', 'OD', null, [['531', 1000000, 0, null], ['101', 0, 1000000, null]]],
        ['P2', 'VT', 'V1', [['531', 600000, 0, null], ['701', 0, 600000, 'Goliaths']]],
        ['P3', 'VT', 'V2', [['512', 90000, 0, null], ['707', 0, 90000, 'Commerce Annexe']]],
        ['P4', 'VT', 'V3', [['531', 7500, 0, null], ['701', 0, 6000, 'Pintades'], ['707', 0, 1500, null]]],
        ['P5', 'AC', null, [['601', 250000, 0, null], ['401', 0, 250000, null]]],
        ['P6', 'AC', null, [['602', 40000, 0, null], ['401', 0, 40000, null]]],
        ['P7', 'AC', null, [['622', 10000, 0, null], ['531', 0, 10000, null]]],
        ['P8', 'CA', null, [['613', 20000, 0, null], ['616', 5000, 0, null], ['624', 3000, 0, null], ['628', 2000, 0, null], ['531', 0, 30000, null]]],
        ['P9', 'AN', null, [['531', 100, 0, null], ['101', 0, 100, null]]],
        ['P10', 'AC', null, [['6011', 8000, 0, null], ['6021', 2000, 0, null], ['401', 0, 10000, null]]],
    ];

    /** Soldes (debit, credit) attendus par compte NOUVEAU — ecrits a la main. */
    private const ATTENDU = [
        '571' => [1607600, 40000], '552' => [90000, 0], '702' => [0, 606000], '701' => [0, 90000], '7071' => [0, 1500],
        '602' => [250000, 0], '601' => [40000, 0], '604' => [10000, 0], '622' => [20000, 0], '625' => [5000, 0],
        '618' => [3000, 0], '658' => [2000, 0], '6021' => [8000, 0], '6011' => [2000, 0], '401' => [0, 300000], '101' => [0, 1000100],
    ];

    protected function poserAncienneBase(): void
    {
        DB::table('plan_comptable')->delete();
        $maintenant = now()->format('Y-m-d H:i:s.u');
        foreach (self::ANCIEN_PLAN as [$n, $l, $c]) {
            DB::table('plan_comptable')->insert([
                'numero_compte' => $n, 'libelle' => $l, 'classe' => $c, 'archive' => false,
                'plan_version' => 1, 'created_at' => $maintenant, 'updated_at' => $maintenant,
            ]);
        }
        $annee = (int) now(config('logialvia.fuseau'))->year;
        ExerciceComptable::query()->firstOrCreate(['annee' => $annee], ['is_cloture' => false]);
        foreach (self::PIECES as [$numero, $journal, $vente, $lignes]) {
            $id = (string) Str::uuid();
            DB::table('pieces_comptables')->insert([
                'id' => $id, 'device_id' => '11111111-1111-4111-8111-111111111111', 'numero_piece' => $numero,
                'date_ecriture' => $maintenant, 'exercice_annee' => $annee, 'journal_code' => $journal,
                'vente_ref' => $vente, 'achat_ref' => null, 'contrepasse_de' => null,
                'updated_at' => $maintenant, 'serveur_modifie_le' => $maintenant,
            ]);
            foreach ($lignes as [$compte, $d, $c, $axe]) {
                DB::table('ecritures_comptables')->insert([
                    'id' => (string) Str::uuid(), 'piece_id' => $id, 'numero_compte' => $compte,
                    'debit' => $d, 'credit' => $c, 'libelle' => 'Ligne '.$numero, 'axe_analytique' => $axe,
                ]);
            }
        }
    }

    protected function soldes(): array
    {
        return DB::table('ecritures_comptables')->selectRaw('numero_compte as c, SUM(debit) as d, SUM(credit) as k')
            ->groupBy('numero_compte')->get()->mapWithKeys(fn ($l) => [$l->c => [(float) $l->d, (float) $l->k]])->all();
    }

    private function plan(): array
    {
        return DB::table('plan_comptable')->pluck('libelle', 'numero_compte')->all();
    }

    public function test_la_balance_est_identique_a_l_ancien_numero_pres_et_equilibree(): void
    {
        $this->poserAncienneBase();
        $this->assertNotNull(RenumerotationPlan::executer());

        $s = $this->soldes();
        ksort($s);
        $attendu = array_map(fn ($x) => array_map('floatval', $x), self::ATTENDU);
        ksort($attendu);
        $this->assertEquals($attendu, $s);
        $this->assertEquals(2037600.0, array_sum(array_column($s, 0)));
        $this->assertEquals(2037600.0, array_sum(array_column($s, 1)));
        $this->assertSame(25, DB::table('ecritures_comptables')->count(), 'aucune ligne perdue ni ajoutee');
    }

    public function test_le_plan_comptes_anciens_retires_officiel_seme_et_croisements(): void
    {
        $this->poserAncienneBase();
        RenumerotationPlan::executer();
        $plan = $this->plan();

        foreach (['531', '512', '613', '616'] as $ancien) {
            $this->assertArrayNotHasKey($ancien, $plan, "$ancien n'existe plus");
        }
        $this->assertSame('Entretien, réparations et maintenance', $plan['624']);
        $this->assertSame('Frais de télécommunications', $plan['628']);
        $this->assertSame('Achats de marchandises', $plan['601']);
        $this->assertSame('Achats de matières premières et fournitures liées', $plan['602']);
        $this->assertSame('Locations et charges locatives', $plan['622']);
        $this->assertSame('Achats stockés de matières et fournitures consommables', $plan['604']);
        // Libelles PERSONNALISES des sous-comptes : ils suivent le compte, pas le numero.
        $this->assertSame('Aliment démarrage', $plan['6021']);
        $this->assertSame('Marchandises revente', $plan['6011']);
        foreach (PlanSyscohada::COMPTES as [$n, $l]) {
            $this->assertSame($l, $plan[$n], "compte $n officiel");
        }
        $this->assertSame([PlanSyscohada::VERSION], DB::table('plan_comptable')->pluck('plan_version')->unique()->values()->all());
    }

    public function test_les_frais_de_livraison_deviennent_7071_et_les_marchandises_701(): void
    {
        $this->poserAncienneBase();
        RenumerotationPlan::executer();

        $l = DB::table('ecritures_comptables as e')->join('pieces_comptables as p', 'p.id', '=', 'e.piece_id')
            ->whereIn('p.numero_piece', ['P3', 'P4'])->whereIn('e.numero_compte', ['701', '7071'])
            ->get(['e.numero_compte', 'e.axe_analytique'])->map(fn ($x) => $x->numero_compte.'|'.($x->axe_analytique ?? 'null'))->sort()->values()->all();
        $this->assertSame(['701|Commerce Annexe', '7071|null'], $l);
    }

    public function test_rejouable_un_second_appel_ne_re_croise_pas_601_602(): void
    {
        $this->poserAncienneBase();
        RenumerotationPlan::executer();
        $apres = $this->soldes();

        $this->assertNull(RenumerotationPlan::executer());
        $this->assertSame($apres, $this->soldes());
        $this->assertEquals([250000.0, 0.0], $this->soldes()['602']);
    }

    public function test_interruption_la_transaction_annule_tout_puis_la_migration_aboutit(): void
    {
        $this->poserAncienneBase();
        $avant = $this->soldes();

        // Coupure au milieu : apres la 20e mise a jour d'ecritures (phase A achevee, phase B entamee).
        $n = 0;
        DB::listen(function ($q) use (&$n) {
            // Guillemets (SQLite/PostgreSQL) ou accents graves (MySQL/MariaDB) : le test vaut sur tout moteur.
            if (preg_match('/^update\s+[`"]ecritures_comptables[`"]/i', $q->sql) && ++$n === 20) {
                throw new \RuntimeException('coupure de courant');
            }
        });
        $coupe = false;
        try {
            RenumerotationPlan::executer();
        } catch (\RuntimeException $e) {
            $coupe = $e->getMessage() === 'coupure de courant';
        }
        $this->assertTrue($coupe, 'la migration a ete interrompue');

        $this->assertSame($avant, $this->soldes(), 'rien n\'a bouge apres l\'echec');
        $this->assertSame(1, DB::table('plan_comptable')->where('numero_compte', '531')->count());
        $this->assertSame(0, DB::table('plan_comptable')->where('numero_compte', 'like', '~M%')->count());

        $this->assertNotNull(RenumerotationPlan::executer());
        $this->assertEquals([1607600.0, 40000.0], $this->soldes()['571']);
    }

    public function test_etats_financiers_apres_migration_memes_montants_que_le_calcul_a_la_main(): void
    {
        $this->poserAncienneBase();
        RenumerotationPlan::executer();
        $s = Soldes::depuis(LivreComptable::toutes());

        // Produits : 606 000 + 90 000 + 1 500 = 697 500 ; charges : 340 000 → resultat 357 500.
        $this->assertEquals(357500.0, MoteurComptable::resultatNet($s));
        $cr = collect(MoteurComptable::compteResultat($s)['postes'])->pluck('montant', 'libelle');
        $this->assertEquals(90000.0, $cr['Ventes de Marchandises']);
        $this->assertEquals(-42000.0, $cr['Achats de Marchandises Consommés']);
        $this->assertEquals(48000.0, $cr['MARGE COMMERCIALE']);
        $this->assertEquals(606000.0, $cr['Ventes de Produits Avicoles']);
        $bilan = MoteurComptable::bilan($s);
        $this->assertTrue($bilan['equilibre']);
        $this->assertEquals(1657600.0, $bilan['total_actif']);
    }

    public function test_la_correspondance_pure_numero_par_numero(): void
    {
        $attendu = ['531' => '571', '512' => '552', '601' => '602', '602' => '601', '622' => '604', '613' => '622', '616' => '625',
            '624' => '618', '628' => '658', '701' => '702', '707' => '701'];
        foreach ($attendu as $ancien => $nouveau) {
            $this->assertSame($nouveau, PlanSyscohada::nouveauNumero($ancien, 'X', 'V'), "ancien $ancien");
        }
        $this->assertSame('7071', PlanSyscohada::nouveauNumero('707', null, 'V'));
        $this->assertSame('701', PlanSyscohada::nouveauNumero('707', null, null), 'OD manuelle sur 707 sans piece de vente');
        $this->assertSame('6021', PlanSyscohada::nouveauNumero('6011'));
        $this->assertSame('6011', PlanSyscohada::nouveauNumero('6021'));
        $this->assertSame('5711', PlanSyscohada::nouveauNumero('5311'));
        $this->assertSame('6181', PlanSyscohada::nouveauNumero('6241'));
        $this->assertSame('7011', PlanSyscohada::nouveauNumero('7071', null, 'V'));
        foreach (['31', '32', '401', '411', '419', '101', '111', '118', '121', '129', '131', '139', '465', '231'] as $inchange) {
            $this->assertSame($inchange, PlanSyscohada::nouveauNumero($inchange));
        }
    }

    public function test_une_base_neuve_sans_ancien_compte_n_a_rien_a_migrer(): void
    {
        $this->assertNull(RenumerotationPlan::executer());
    }
}
