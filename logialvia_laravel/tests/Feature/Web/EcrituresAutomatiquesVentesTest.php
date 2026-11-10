<?php

namespace Tests\Feature\Web;

use App\Models\EcritureComptable;
use App\Models\PieceComptable;
use App\Models\ProduitVendable;
use App\Services\Commerce\VentesWeb;
use App\Services\Comptabilite\EcrituresAutomatiquesVentes as Ecritures;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\JeuComptable;
use Tests\TestCase;

/**
 * Jeu d'ecritures de VENTE chiffre a la main, IDENTIQUE a celui du poste
 * (`logialvia_app/test/commercial/ecritures_ventes_commun_test.dart`) : memes cas A a F, memes lignes.
 * Si le web et le poste s'ecartent, l'un des deux tests rougit.
 */
class EcrituresAutomatiquesVentesTest extends TestCase
{
    use JeuComptable, RefreshDatabase;

    private VentesWeb $caisse;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerPourLesEcrans();
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-11-09 12:00:00', config('logialvia.fuseau')));
        $this->caisse = new VentesWeb($this->utilisateurAvecRole('caissier', 'amina'));
    }

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function produit(string $nom, string $cat, ?string $espece): ProduitVendable
    {
        return ProduitVendable::query()->firstOrCreate(['name' => $nom], [
            'cat' => $cat, 'price' => 1000, 'unit' => 'u', 'icon' => 'egg', 'espece' => $espece, 'saisi_le' => now(),
        ]);
    }

    private function goliath(): ProduitVendable
    {
        return $this->produit('Goliath mature', 'Avicole', 'goliaths');
    }

    private function pintade(): ProduitVendable
    {
        return $this->produit('Pintade mature', 'Avicole', 'pintades');
    }

    private function teeShirt(): ProduitVendable
    {
        return $this->produit('Tee-shirt enfant', 'Commerce Annexe', null);
    }

    private function ligne(ProduitVendable $p, int $qte, float $montant): array
    {
        return ['produit_id' => $p->id, 'qte' => $qte, 'montant' => $montant];
    }

    /** Lignes d'une piece triees comme le test Dart : debit decroissant, compte, credit decroissant. */
    private function piece(string $numero): array
    {
        $p = PieceComptable::query()->with('lignes')->where('numero_piece', $numero)->sole();
        $lignes = $p->lignes->map(fn (EcritureComptable $l) => [$l->numero_compte, $l->debit, $l->credit, $l->axe_analytique])->all();
        usort($lignes, fn ($a, $b) => [$b[1], strcmp($a[0], $b[0]), $b[2]] <=> [$a[1], 0, $a[2]]);

        return $lignes;
    }

    private function solde(string $compte): float
    {
        return (float) EcritureComptable::query()->where('numero_compte', $compte)->selectRaw('COALESCE(SUM(debit - credit), 0) as s')->value('s');
    }

    private function ecart(string $numero): float
    {
        $p = PieceComptable::query()->where('numero_piece', $numero)->sole();

        return (float) $p->lignes()->selectRaw('COALESCE(SUM(debit), 0) - COALESCE(SUM(credit), 0) as e')->value('e');
    }

    private function vendre(array $d): string
    {
        $r = $this->caisse->encaisser($d + ['client' => 'Client Comptant', 'condition' => VentesWeb::COMPTANT]);
        $this->assertNull($r['motif'], (string) $r['motif']);

        return $r['vente']->reference;
    }

    private function avanceB(): string
    {
        return $this->vendre([
            'client' => 'AGOSSOU Prudence', 'mode' => 'Mobile Money', 'condition' => VentesWeb::AVANCE, 'montant_recu' => 4000,
            'lignes' => [$this->ligne($this->goliath(), 1, 6000), $this->ligne($this->pintade(), 1, 6500), $this->ligne($this->teeShirt(), 3, 3000)],
        ]);
    }

    private function parametrerMobileMoney(): void
    {
        \App\Models\ParametresEntreprise::courant()->update(['telephone' => '+229 97 00 00 00']);
    }

    public function test_A_comptant_en_especes(): void
    {
        $ref = $this->vendre(['mode' => 'Espèces', 'montant_recu' => 12000, 'lignes' => [$this->ligne($this->goliath(), 2, 12000)]]);

        $this->assertSame([['571', 12000.0, 0.0, null], ['702', 0.0, 12000.0, 'Goliaths']], $this->piece($ref));
    }

    public function test_B_avance_en_mobile_money_sur_trois_centres(): void
    {
        $this->parametrerMobileMoney();
        $ref = $this->avanceB();

        $this->assertSame([
            ['411', 11500.0, 0.0, null],
            ['552', 4000.0, 0.0, null],
            ['701', 0.0, 3000.0, 'Commerce Annexe'],
            ['702', 0.0, 6500.0, 'Pintades'],
            ['702', 0.0, 6000.0, 'Goliaths'],
        ], $this->piece($ref));
    }

    public function test_C_livraison_facturee_les_frais_sont_un_produit_et_la_piece_est_equilibree(): void
    {
        $ref = $this->vendre([
            'mode' => 'Espèces', 'montant_recu' => 7500, 'lignes' => [$this->ligne($this->goliath(), 1, 6000)],
            'livraison' => ['mode' => 'facturee', 'frais' => 1500],
        ]);

        $this->assertEqualsWithDelta(0, $this->ecart($ref), 0.001);
        $this->assertSame([['571', 7500.0, 0.0, null], ['702', 0.0, 6000.0, 'Goliaths'], ['7071', 0.0, 1500.0, null]], $this->piece($ref));
    }

    public function test_D_un_recouvrement_superieur_au_reste_du_est_refuse(): void
    {
        $ref = $this->vendre([
            'client' => 'AGOSSOU Prudence', 'mode' => 'Espèces', 'condition' => VentesWeb::AVANCE, 'montant_recu' => 3500,
            'lignes' => [$this->ligne($this->goliath(), 2, 12000)],
        ]);
        $id = \App\Models\Vente::query()->where('reference', $ref)->value('id');

        // Le poste borne a 8 500 ; le web REFUSE (motif), et ne passe aucune piece.
        $this->assertSame('Le montant dépasse le reste dû (8 500 FCFA).', $this->caisse->recouvrer($id, 999999, 'Espèces'));
        $this->assertSame(0, PieceComptable::query()->where('numero_piece', 'REG-'.$ref)->count());

        $this->assertNull($this->caisse->recouvrer($id, 8500, 'Espèces'));
        $this->assertSame([['571', 8500.0, 0.0, null], ['411', 0.0, 8500.0, null]], $this->piece('REG-'.$ref));
        $this->assertEqualsWithDelta(0, $this->solde('411'), 0.001);
    }

    public function test_E_recouvrement_partiel_puis_annulation_tout_est_contrepasse(): void
    {
        $this->parametrerMobileMoney();
        $ref = $this->avanceB();
        $id = \App\Models\Vente::query()->where('reference', $ref)->value('id');
        $this->assertNull($this->caisse->recouvrer($id, 2000, 'Mobile Money'));
        $this->assertNull($this->caisse->annuler($id, 'Client non honoré'));

        $this->assertSame([
            ['702', 6500.0, 0.0, 'Pintades'],
            ['702', 6000.0, 0.0, 'Goliaths'],
            ['701', 3000.0, 0.0, 'Commerce Annexe'],
            ['411', 0.0, 9500.0, null],
            ['552', 0.0, 6000.0, null],
        ], $this->piece('ANN-'.$ref));
        foreach (['411', '552', '702', '701'] as $compte) {
            $this->assertEqualsWithDelta(0, $this->solde($compte), 0.001, "compte $compte solde");
        }
    }

    public function test_F_annulation_d_une_vente_avec_livraison_facturee_reprend_les_frais(): void
    {
        $ref = $this->vendre([
            'mode' => 'Espèces', 'montant_recu' => 7500, 'lignes' => [$this->ligne($this->goliath(), 1, 6000)],
            'livraison' => ['mode' => 'facturee', 'frais' => 1500],
        ]);
        $this->assertNull($this->caisse->annuler(\App\Models\Vente::query()->where('reference', $ref)->value('id'), 'Erreur de saisie'));

        $this->assertEqualsWithDelta(0, $this->ecart('ANN-'.$ref), 0.001);
        foreach (['571', '702', '701'] as $compte) {
            $this->assertEqualsWithDelta(0, $this->solde($compte), 0.001, "compte $compte solde");
        }
    }

    // --------------------------------------------------- Ecart voulu avec le poste (D du doc 47a)

    public function test_une_categorie_de_produit_modifiee_apres_la_vente_ne_change_pas_les_comptes_de_l_annulation(): void
    {
        $g = $this->goliath();
        $ref = $this->vendre(['mode' => 'Espèces', 'montant_recu' => 6000, 'lignes' => [$this->ligne($g, 1, 6000)]]);
        // Le produit change de categorie : le poste recalculerait 707 ; le web contrepasse CE QUI A ETE ECRIT.
        $g->update(['cat' => 'Commerce Annexe']);

        $this->assertNull($this->caisse->annuler(\App\Models\Vente::query()->where('reference', $ref)->value('id'), 'Autre'));
        $this->assertEqualsWithDelta(0, $this->solde('702'), 0.001);
        $this->assertEqualsWithDelta(0, $this->solde('701'), 0.001);
    }

    public function test_le_recouvrement_par_un_autre_moyen_que_la_vente_ne_fausse_pas_la_tresorerie_a_l_annulation(): void
    {
        $this->parametrerMobileMoney();
        $ref = $this->vendre([
            'mode' => 'Espèces', 'condition' => VentesWeb::AVANCE, 'montant_recu' => 1000, 'client' => 'Kofi',
            'lignes' => [$this->ligne($this->goliath(), 1, 6000)],
        ]);
        $id = \App\Models\Vente::query()->where('reference', $ref)->value('id');
        $this->assertNull($this->caisse->recouvrer($id, 2000, 'Mobile Money')); // paye en Mobile Money
        $this->assertNull($this->caisse->annuler($id, 'Autre'));

        $this->assertEqualsWithDelta(0, $this->solde('571'), 0.001);
        $this->assertEqualsWithDelta(0, $this->solde('552'), 0.001);
    }

    // ------------------------------------------------------------- Constructeurs purs

    public function test_les_constructeurs_purs_sont_ceux_du_dart(): void
    {
        $this->assertSame('552', Ecritures::tresoreriePour('Mobile Money'));
        $this->assertSame('571', Ecritures::tresoreriePour('Espèces'));
        $this->assertSame('571', Ecritures::tresoreriePour('Non précisé'));
        $this->assertSame([], Ecritures::lignesVente('V', 'Espèces', 0, 0, []));
        $this->assertSame([], Ecritures::lignesReglement('V', 'Espèces', 0));
        // paye > total : jamais de creance negative.
        $l = Ecritures::lignesVente('V', 'Espèces', 1000, 1500, [['compte' => '702', 'axe' => null, 'taux' => 0.0, 'montant' => 1000.0]]);
        $this->assertSame(['571', '702'], array_column($l, 'compte'));
        // Un paye negatif (donnee corrompue) ne debite jamais 411 de plus que le total.
        $l = Ecritures::lignesVente('V', 'Espèces', 1000, -100, [['compte' => '702', 'axe' => null, 'taux' => 0.0, 'montant' => 1000.0]]);
        $this->assertSame(1000.0, collect($l)->firstWhere('compte', '411')['debit']);
        // Un centre inconnu ne rattache rien (jamais arbitrairement).
        $this->assertSame(['702', null, 0.0], Ecritures::cleDeVentilation(new ProduitVendable(['cat' => 'Avicole', 'espece' => 'dragons'])));
        $this->assertSame(['702', null, 0.0], Ecritures::cleDeVentilation(null));
        $this->assertSame(['701', 'Commerce Annexe', 0.0], Ecritures::cleDeVentilation(new ProduitVendable(['cat' => 'Commerce Annexe', 'espece' => 'goliaths'])));
        foreach (['goliaths' => 'Goliaths', 'pintades' => 'Pintades', 'lapins' => 'Lapins', 'escargots' => 'Escargots', 'bovins' => 'Bovins',
            'poissons-chats' => 'Poissons-Chats', 'poulets' => 'Poulets', 'pondeuses' => 'Pondeuses'] as $espece => $centre) {
            $this->assertSame(['702', $centre, 0.0], Ecritures::cleDeVentilation(new ProduitVendable(['cat' => 'Avicole', 'espece' => $espece])));
        }
    }

    // ----------------------------------------------------------------------- TVA ventilee (`47p_` §6)
    //
    // Memes jeux, memes montants que `ecritures_ventes_commun_test.dart` (G, H, I, J, K) : les prix du catalogue sont
    // TTC, la TVA s'en extrait au taux du groupe de taxe du produit (A exonere, B 18 %), arrondie au franc.

    private function taxer(ProduitVendable $p, string $groupe): void
    {
        \App\Models\GroupeTaxe::query()->firstOrCreate(['code' => 'A'], ['libelle' => 'Exonéré', 'taux' => 0, 'ordre' => 1]);
        \App\Models\GroupeTaxe::query()->firstOrCreate(['code' => 'B'], ['libelle' => 'Taux normal 18 %', 'taux' => 18, 'ordre' => 2]);
        $p->forceFill(['groupe_taxe' => $groupe])->save();
    }

    public function test_G_produit_taxable_a_18_pour_cent_11800_ttc_egale_10000_ht_et_1800_de_tva_collectee(): void
    {
        $this->taxer($this->teeShirt(), 'B');
        $ref = $this->vendre(['mode' => 'Espèces', 'montant_recu' => 11800, 'lignes' => [$this->ligne($this->teeShirt(), 2, 11800)]]);

        $this->assertSame([['571', 11800.0, 0.0, null], ['4431', 0.0, 1800.0, null], ['701', 0.0, 10000.0, 'Commerce Annexe']], $this->piece($ref));
        $this->assertEqualsWithDelta(0, $this->ecart($ref), 0.001);
    }

    public function test_H_livraison_facturee_au_taux_unique_du_panier_taxable_4431_et_4432(): void
    {
        $this->taxer($this->teeShirt(), 'B');
        $ref = $this->vendre([
            'mode' => 'Espèces', 'montant_recu' => 12980, 'lignes' => [$this->ligne($this->teeShirt(), 2, 11800)],
            'livraison' => ['mode' => 'facturee', 'frais' => 1180],
        ]);

        $this->assertSame([
            ['571', 12980.0, 0.0, null], ['4431', 0.0, 1800.0, null], ['4432', 0.0, 180.0, null],
            ['701', 0.0, 10000.0, 'Commerce Annexe'], ['7071', 0.0, 1000.0, null],
        ], $this->piece($ref));
    }

    public function test_I_panier_mixte_la_livraison_est_exoneree_et_la_tva_ne_porte_que_sur_la_ligne_taxable(): void
    {
        $this->taxer($this->teeShirt(), 'B');
        $ref = $this->vendre([
            'mode' => 'Espèces', 'montant_recu' => 19300,
            'lignes' => [$this->ligne($this->goliath(), 1, 6000), $this->ligne($this->teeShirt(), 2, 11800)],
            'livraison' => ['mode' => 'facturee', 'frais' => 1500],
        ]);

        $this->assertSame([
            ['571', 19300.0, 0.0, null], ['4431', 0.0, 1800.0, null], ['701', 0.0, 10000.0, 'Commerce Annexe'],
            ['702', 0.0, 6000.0, 'Goliaths'], ['7071', 0.0, 1500.0, null],
        ], $this->piece($ref));
    }

    public function test_J_annulation_d_une_vente_taxable_reprend_la_tva_collectee(): void
    {
        $this->taxer($this->teeShirt(), 'B');
        $ref = $this->vendre(['mode' => 'Espèces', 'montant_recu' => 11800, 'lignes' => [$this->ligne($this->teeShirt(), 2, 11800)]]);
        $this->assertEqualsWithDelta(-1800, $this->solde('4431'), 0.001);
        $id = \App\Models\Vente::query()->where('reference', $ref)->value('id');

        $this->assertNull($this->caisse->annuler($id, 'Erreur'));

        $this->assertEqualsWithDelta(0, $this->ecart('ANN-'.$ref), 0.001);
        foreach (['571', '701', '4431'] as $compte) {
            $this->assertEqualsWithDelta(0, $this->solde($compte), 0.001, "compte $compte solde");
        }
    }

    public function test_K_creance_taxable_le_recouvrement_ne_touche_pas_a_la_tva(): void
    {
        $this->taxer($this->teeShirt(), 'B');
        $ref = $this->vendre([
            'client' => 'AGOSSOU Prudence', 'mode' => 'Espèces', 'condition' => VentesWeb::AVANCE, 'montant_recu' => 3800,
            'lignes' => [$this->ligne($this->teeShirt(), 2, 11800)],
        ]);
        $this->assertSame([['411', 8000.0, 0.0, null], ['571', 3800.0, 0.0, null], ['4431', 0.0, 1800.0, null], ['701', 0.0, 10000.0, 'Commerce Annexe']], $this->piece($ref));
        $id = \App\Models\Vente::query()->where('reference', $ref)->value('id');

        $this->assertNull($this->caisse->recouvrer($id, 8000, 'Espèces'));

        $this->assertEqualsWithDelta(0, $this->solde('411'), 0.001);
        $this->assertEqualsWithDelta(-1800, $this->solde('4431'), 0.001);
    }

    public function test_la_tva_est_arrondie_au_franc_comme_le_poste(): void
    {
        $this->assertSame(1800.0, \App\Support\PlanSyscohada::tvaDuTtc(11800, 18));
        $this->assertSame(180.0, \App\Support\PlanSyscohada::tvaDuTtc(1180, 18));
        $this->assertSame(153.0, \App\Support\PlanSyscohada::tvaDuTtc(1000, 18)); // 152,54
        $this->assertSame(763.0, \App\Support\PlanSyscohada::tvaDuTtc(5000, 18)); // 762,71
        $this->assertSame(0.0, \App\Support\PlanSyscohada::tvaDuTtc(6000, 0));
    }
}
