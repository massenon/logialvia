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
        usort($lignes, fn ($a, $b) => [$b[1], $a[0], $b[2]] <=> [$a[1], $b[0], $a[2]]);

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

        $this->assertSame([['531', 12000.0, 0.0, null], ['701', 0.0, 12000.0, 'Goliaths']], $this->piece($ref));
    }

    public function test_B_avance_en_mobile_money_sur_trois_centres(): void
    {
        $this->parametrerMobileMoney();
        $ref = $this->avanceB();

        $this->assertSame([
            ['411', 11500.0, 0.0, null],
            ['512', 4000.0, 0.0, null],
            ['701', 0.0, 6500.0, 'Pintades'],
            ['701', 0.0, 6000.0, 'Goliaths'],
            ['707', 0.0, 3000.0, 'Commerce Annexe'],
        ], $this->piece($ref));
    }

    public function test_C_livraison_facturee_les_frais_sont_un_produit_et_la_piece_est_equilibree(): void
    {
        $ref = $this->vendre([
            'mode' => 'Espèces', 'montant_recu' => 7500, 'lignes' => [$this->ligne($this->goliath(), 1, 6000)],
            'livraison' => ['mode' => 'facturee', 'frais' => 1500],
        ]);

        $this->assertEqualsWithDelta(0, $this->ecart($ref), 0.001);
        $this->assertSame([['531', 7500.0, 0.0, null], ['701', 0.0, 6000.0, 'Goliaths'], ['707', 0.0, 1500.0, null]], $this->piece($ref));
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
        $this->assertSame([['531', 8500.0, 0.0, null], ['411', 0.0, 8500.0, null]], $this->piece('REG-'.$ref));
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
            ['701', 6500.0, 0.0, 'Pintades'],
            ['701', 6000.0, 0.0, 'Goliaths'],
            ['707', 3000.0, 0.0, 'Commerce Annexe'],
            ['411', 0.0, 9500.0, null],
            ['512', 0.0, 6000.0, null],
        ], $this->piece('ANN-'.$ref));
        foreach (['411', '512', '701', '707'] as $compte) {
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
        foreach (['531', '701', '707'] as $compte) {
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
        $this->assertEqualsWithDelta(0, $this->solde('701'), 0.001);
        $this->assertEqualsWithDelta(0, $this->solde('707'), 0.001);
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

        $this->assertEqualsWithDelta(0, $this->solde('531'), 0.001);
        $this->assertEqualsWithDelta(0, $this->solde('512'), 0.001);
    }

    // ------------------------------------------------------------- Constructeurs purs

    public function test_les_constructeurs_purs_sont_ceux_du_dart(): void
    {
        $this->assertSame('512', Ecritures::tresoreriePour('Mobile Money'));
        $this->assertSame('531', Ecritures::tresoreriePour('Espèces'));
        $this->assertSame('531', Ecritures::tresoreriePour('Non précisé'));
        $this->assertSame([], Ecritures::lignesVente('V', 'Espèces', 0, 0, []));
        $this->assertSame([], Ecritures::lignesReglement('V', 'Espèces', 0));
        // paye > total : jamais de creance negative.
        $l = Ecritures::lignesVente('V', 'Espèces', 1000, 1500, [['compte' => '701', 'axe' => null, 'montant' => 1000.0]]);
        $this->assertSame(['531', '701'], array_column($l, 'compte'));
        // Un paye negatif (donnee corrompue) ne debite jamais 411 de plus que le total.
        $l = Ecritures::lignesVente('V', 'Espèces', 1000, -100, [['compte' => '701', 'axe' => null, 'montant' => 1000.0]]);
        $this->assertSame(1000.0, collect($l)->firstWhere('compte', '411')['debit']);
        // Un centre inconnu ne rattache rien (jamais arbitrairement).
        $this->assertSame(['701', null], Ecritures::cleDeVentilation(new ProduitVendable(['cat' => 'Avicole', 'espece' => 'dragons'])));
        $this->assertSame(['701', null], Ecritures::cleDeVentilation(null));
        $this->assertSame(['707', 'Commerce Annexe'], Ecritures::cleDeVentilation(new ProduitVendable(['cat' => 'Commerce Annexe', 'espece' => 'goliaths'])));
        foreach (['goliaths' => 'Goliaths', 'pintades' => 'Pintades', 'lapins' => 'Lapins', 'escargots' => 'Escargots', 'bovins' => 'Bovins',
            'poissons-chats' => 'Poissons-Chats', 'poulets' => 'Poulets', 'pondeuses' => 'Pondeuses'] as $espece => $centre) {
            $this->assertSame(['701', $centre], Ecritures::cleDeVentilation(new ProduitVendable(['cat' => 'Avicole', 'espece' => $espece])));
        }
    }
}
