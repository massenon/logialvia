<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\FacturesMecef;
use App\Models\EcritureComptable;
use App\Models\Facture;
use App\Models\LigneFacture;
use App\Models\LigneVente;
use App\Models\ParametresEntreprise;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Models\Vente;
use App\Support\ExportXlsx;
use Carbon\CarbonImmutable;
use Database\Seeders\GroupesTaxeSeeder;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Concerns\LitXlsx;
use Tests\TestCase;

/**
 * `47a2_` — émission web d'une facture de vente et d'un avoir, vue imprimable, export XLSX.
 *
 * Les valeurs numériques ci-dessous sont celles que CALCULE LE POSTE (Dart, mêmes opérations, IEEE 754) : le web doit
 * produire les mêmes nombres, pas des nombres « presque pareils ».
 */
class FacturesMecefEmissionWebTest extends TestCase
{
    use LitXlsx, RefreshDatabase;

    private int $n = 0;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        $this->seed(GroupesTaxeSeeder::class);
        ParametresEntreprise::courant()->forceFill(['mecef_actif' => true, 'raison_sociale' => 'ALLMANY ET COMPAGNIE', 'ifu' => '3201234567890'])->save();
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-11-09 12:00:00', config('logialvia.fuseau')));
    }

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private function utilisateur(string $role, string $username = 'u'): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    private ?User $comptable = null;

    /** Un composant NEUF pour la même comptable (un seul compte par test). */
    private function compta()
    {
        $this->comptable ??= $this->utilisateur('comptable', 'compta');

        return Livewire::actingAs($this->comptable)->test(FacturesMecef::class);
    }

    private function produit(string $nom, string $groupe, string $unite = 'u'): ProduitVendable
    {
        $p = (new ProduitVendable)->forceFill([
            'id' => (string) Str::uuid(), 'name' => $nom, 'cat' => 'Goliaths', 'price' => 1000, 'unit' => $unite, 'icon' => 'x',
            'groupe_taxe' => $groupe, 'threshold' => 0, 'saisi_le' => now(),
        ]);
        $p->save();

        return $p;
    }

    /** @param list<array{0: ProduitVendable, 1: float, 2: float}> $lignes produit, qte, pu (TTC) */
    private function vente(array $lignes, array $surcharge = []): Vente
    {
        $this->n++;
        $v = (new Vente)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => sprintf('V-P1-2026-%03d', $this->n),
            'portee_reference' => '', 'client' => 'DOSSOU Félicité', 'date_vente' => CarbonImmutable::parse('2026-11-05 10:00:00', 'UTC'),
            'mode' => 'Espèces', 'status' => 'Payée', 'total' => 0, 'paye' => 0, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $v->save();
        foreach ($lignes as [$produit, $qte, $pu]) {
            (new LigneVente)->forceFill(['id' => (string) Str::uuid(), 'vente_id' => $v->id, 'produit_id' => $produit->id,
                'name' => $produit->name, 'qte' => $qte, 'pu' => $pu])->save();
        }

        return $v;
    }

    private function emettre($c, Vente $v, string $ifu = '', string $adresse = '')
    {
        return $c->call('ouvrirEmission')->set('venteId', $v->id)->set('ifu', $ifu)->set('adresse', $adresse)->call('emettre');
    }

    private function laFacture(string $prefixe = 'FV-WEB'): Facture
    {
        return Facture::query()->where('reference', 'like', "$prefixe-%")->orderByDesc('reference')->firstOrFail();
    }

    private function factureEmise(): Facture
    {
        $v = $this->vente([[$this->produit('Goliath', 'B'), 2, 11800], [$this->produit('Oeufs', 'A', 'plateau'), 5, 1000]]);
        $this->emettre($this->compta(), $v, '3201111111111', 'Natitingou');

        return $this->laFacture();
    }

    // ------------------------------------------------------------------ Émission

    public function test_emission_depuis_une_vente_calcule_ht_taxe_ttc_par_groupe_comme_le_poste(): void
    {
        $v = $this->vente([[$this->produit('Goliath', 'B'), 2, 11800], [$this->produit('Oeufs', 'A', 'plateau'), 5, 1000]]);
        $this->emettre($this->compta(), $v, '3201111111111', 'Natitingou')->assertSet('erreur', null)->assertSet('emission', false);

        $f = $this->laFacture();
        $this->assertSame('FV-WEB-2026-001', $f->reference);
        $this->assertSame('FV', $f->type);
        $this->assertSame(Catalogue::POSTE_WEB, $f->device_id);
        $this->assertSame('', $f->portee_reference);
        $this->assertSame('a_transmettre', $f->statut);
        $this->assertSame($v->reference, $f->vente_ref);
        $this->assertNull($f->origine_ref);
        $this->assertSame('DOSSOU Félicité', $f->client);
        $this->assertSame('3201111111111', $f->client_ifu);
        $this->assertSame('Natitingou', $f->client_adresse);
        $this->assertSame('2026-11-05', $f->date_facture->utc()->format('Y-m-d'), 'la date de la facture est celle de la vente (comme le poste)');
        $this->assertNull($f->code_mecef);
        $this->assertNull($f->nim);
        // 2 × 11 800 TTC à 18 % : HT 20 000, taxe 3 600 ; 5 × 1 000 exonérés : HT 5 000.
        $this->assertSame(25000.0, $f->total_ht);
        $this->assertSame(3600.0, $f->total_taxe);
        $this->assertSame(28600.0, $f->total_ttc);
        $lignes = $f->lignes()->reorder('designation')->get();
        $this->assertCount(2, $lignes);
        $this->assertSame(['B', 18.0, 10000.0, 20000.0, 3600.0], [$lignes[0]->groupe_taxe, $lignes[0]->taux_taxe, $lignes[0]->prix_unitaire_ht, $lignes[0]->montant_ht, $lignes[0]->montant_taxe]);
        $this->assertSame(['A', 0.0, 1000.0, 5000.0, 0.0, 'plateau'], [$lignes[1]->groupe_taxe, $lignes[1]->taux_taxe, $lignes[1]->prix_unitaire_ht, $lignes[1]->montant_ht, $lignes[1]->montant_taxe, $lignes[1]->unite]);
    }

    public function test_les_nombres_sont_ceux_du_dart_au_dernier_chiffre_aucun_arrondi_stocke(): void
    {
        // Valeurs produites par le Dart (`dart run` des mêmes opérations) : voir 47a2_ §4.
        $v = $this->vente([[$this->produit('Aliment', 'B'), 3, 3333], [$this->produit('Provende', 'B'), 7, 1234.5]]);
        $this->emettre($this->compta(), $v);

        $f = $this->laFacture();
        $l = $f->lignes()->reorder('designation')->get();
        $this->assertEqualsWithDelta(2824.576271186441, $l[0]->prix_unitaire_ht, 1e-8);
        $this->assertEqualsWithDelta(8473.728813559323, $l[0]->montant_ht, 1e-8);
        $this->assertEqualsWithDelta(1525.271186440678, $l[0]->montant_taxe, 1e-8);
        $this->assertEqualsWithDelta(1046.1864406779662, $l[1]->prix_unitaire_ht, 1e-8);
        $this->assertEqualsWithDelta(7323.305084745763, $l[1]->montant_ht, 1e-8);
        $this->assertEqualsWithDelta(1318.1949152542375, $l[1]->montant_taxe, 1e-8);
        $this->assertEqualsWithDelta(15797.033898305086, $f->total_ht, 1e-8);
        $this->assertEqualsWithDelta(2843.466101694916, $f->total_taxe, 1e-8);
        $this->assertSame(18640.5, $f->total_ttc);
        // Le TTC de la facture est celui que le client a réglé (9 999 + 8 641,5).
        $this->assertEqualsWithDelta(3 * 3333 + 7 * 1234.5, $f->total_ttc, 1e-9);
    }

    public function test_quantite_decimale_et_groupe_inconnu_retombe_sur_exonere(): void
    {
        $v = $this->vente([[$this->produit('Poisson', 'B', 'kg'), 2.5, 777], [$this->produit('Divers', 'Z'), 1, 500]]);
        $this->emettre($this->compta(), $v);
        $l = $this->laFacture()->lignes()->reorder('designation')->get();
        $this->assertSame(['Divers', 'A', 0.0, 500.0], [$l[0]->designation, $l[0]->groupe_taxe, $l[0]->taux_taxe, $l[0]->montant_ht], 'groupe absent de la grille : exonéré');
        $this->assertEqualsWithDelta(1646.1864406779662, $l[1]->montant_ht, 1e-8);
        $this->assertEqualsWithDelta(296.3135593220339, $l[1]->montant_taxe, 1e-8);
        $this->assertSame(2.5, $l[1]->quantite);
    }

    public function test_aucun_effet_de_bord_ni_ecriture_comptable_ni_stock_ni_vente_modifiee_ni_reseau(): void
    {
        Http::fake();
        $v = $this->vente([[$this->produit('Goliath', 'B'), 1, 11800]], ['total' => 11800, 'paye' => 11800]);
        $avant = Vente::query()->find($v->id)->toArray();

        $this->emettre($this->compta(), $v);

        $this->assertSame(0, EcritureComptable::query()->count(), 'la vente a déjà fait son écriture : la facture n\'en génère aucune');
        $this->assertSame($avant, Vente::query()->find($v->id)->toArray());
        $this->assertSame(1, LigneVente::query()->count());
        Http::assertNothingSent();
    }

    public function test_une_seule_facture_de_vente_par_vente(): void
    {
        $v = $this->vente([[$this->produit('Goliath', 'B'), 1, 11800]]);
        $c = $this->compta();
        $this->emettre($c, $v)->assertSet('erreur', null);
        $premiere = $this->laFacture()->id;

        $c->call('ouvrirEmission')->set('venteId', $v->id)->call('emettre')->assertSet('emission', true);
        $this->assertStringContainsString("porte déjà la facture FV-WEB-2026-001", (string) $c->get('erreur'));
        $this->assertSame(1, Facture::query()->count());
        $this->assertSame($premiere, $this->laFacture()->id);

        // Et la vente facturée disparaît de la liste des ventes à facturer.
        $c->call('ouvrirEmission')->assertDontSeeHtml('value="'.$v->id.'"');
    }

    public function test_une_vente_deja_facturee_par_un_poste_ne_se_refacture_pas_au_web(): void
    {
        $v = $this->vente([[$this->produit('Goliath', 'B'), 1, 11800]]);
        $f = (new Facture)->forceFill(['id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => 'FV-P1-2026-001',
            'portee_reference' => '', 'type' => 'FV', 'vente_ref' => $v->reference, 'date_facture' => now(), 'client' => 'X',
            'total_ht' => 1, 'total_taxe' => 0, 'total_ttc' => 1, 'statut' => 'normalisee', 'code_mecef' => 'C', 'nim' => 'N',
            'date_normalisation' => now(), 'updated_at' => now(), 'serveur_modifie_le' => now()]);
        $f->save();

        $c = $this->compta();
        $this->emettre($c, $v)->assertSet('emission', true);
        $this->assertStringContainsString('porte déjà la facture FV-P1-2026-001', (string) $c->get('erreur'));
        $this->assertSame(1, Facture::query()->count());
    }

    public function test_vente_sans_code_de_poste_la_facture_d_un_autre_poste_ne_bloque_pas(): void
    {
        $v = $this->vente([[$this->produit('Goliath', 'B'), 1, 11800]], ['reference' => 'V-2026-001']);
        // Même texte de référence, mais pour la vente d'un AUTRE poste.
        (new Facture)->forceFill(['id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => 'FV-2026-001',
            'portee_reference' => (string) Str::uuid(), 'type' => 'FV', 'vente_ref' => 'V-2026-001', 'date_facture' => now(), 'client' => 'X',
            'total_ht' => 1, 'total_taxe' => 0, 'total_ttc' => 1, 'statut' => 'a_transmettre',
            'updated_at' => now(), 'serveur_modifie_le' => now()])->save();

        $this->emettre($this->compta(), $v)->assertSet('erreur', null)->assertSet('emission', false);
        $this->assertSame(2, Facture::query()->count());
        // La facture d'un poste émise pour cette vente-ci (même poste que la vente) bloque, elle.
        $w = $this->vente([[$this->produit('Oeufs', 'A'), 1, 1000]], ['reference' => 'V-2026-002']);
        (new Facture)->forceFill(['id' => (string) Str::uuid(), 'device_id' => $w->device_id, 'reference' => 'FV-2026-002',
            'portee_reference' => $w->device_id, 'type' => 'FV', 'vente_ref' => 'V-2026-002', 'date_facture' => now(), 'client' => 'X',
            'total_ht' => 1, 'total_taxe' => 0, 'total_ttc' => 1, 'statut' => 'a_transmettre',
            'updated_at' => now(), 'serveur_modifie_le' => now()])->save();
        $c = $this->compta();
        $this->emettre($c, $w)->assertSet('emission', true);
        $this->assertStringContainsString('porte déjà la facture FV-2026-002', (string) $c->get('erreur'));
    }

    public function test_refus_vente_annulee_sans_ligne_inconnue_ou_non_choisie(): void
    {
        $c = $this->compta();
        $annulee = $this->vente([[$this->produit('Goliath', 'B'), 1, 11800]], ['status' => 'Annulée']);
        $this->emettre($c, $annulee);
        $this->assertStringContainsString('est annulée', (string) $c->get('erreur'));

        $vide = $this->vente([]);
        $this->emettre($c, $vide);
        $this->assertStringContainsString('sans ligne', (string) $c->get('erreur'));

        $nulle = $this->vente([[$this->produit('Goliath', 'B'), 0, 1000]]);
        $this->emettre($c, $nulle);
        $this->assertStringContainsString('quantité nulle', (string) $c->get('erreur'));

        $c->call('ouvrirEmission')->set('venteId', (string) Str::uuid())->call('emettre');
        $this->assertStringContainsString('Choisissez la vente', (string) $c->get('erreur'));
        $c->call('ouvrirEmission')->call('emettre');
        $this->assertStringContainsString('Choisissez la vente', (string) $c->get('erreur'));

        $ok = $this->vente([[$this->produit('Goliath', 'B'), 1, 11800]]);
        $c->call('ouvrirEmission')->set('venteId', $ok->id)->set('ifu', str_repeat('9', 41))->call('emettre');
        $this->assertStringContainsString('trop long', (string) $c->get('erreur'));
        $this->assertSame(0, Facture::query()->count());
    }

    public function test_la_liste_des_ventes_a_facturer_exclut_les_annulees_et_les_facturees(): void
    {
        $p = $this->produit('Goliath', 'B');
        $a = $this->vente([[$p, 1, 11800]], ['client' => 'Client Libre']);
        $this->vente([[$p, 1, 11800]], ['client' => 'Client Annulé', 'status' => 'Annulée']);
        $this->compta()->call('ouvrirEmission')->assertSee('Client Libre')->assertDontSee('Client Annulé')->assertSeeHtml('value="'.$a->id.'"');
    }

    // --------------------------------------------------------------- Numérotation

    public function test_numerotation_maximum_numerique_annee_de_la_vente_sequences_par_type(): void
    {
        $this->vente([]);
        foreach (['FV-WEB-2026-999', 'FV-WEB-2025-040', 'FV-P1-2026-500', 'FA-WEB-2026-007', 'FV-WEB-2026-1000'] as $i => $ref) {
            (new Facture)->forceFill(['id' => (string) Str::uuid(), 'device_id' => Catalogue::POSTE_WEB, 'reference' => $ref,
                'portee_reference' => '', 'type' => substr($ref, 0, 2), 'origine_ref' => str_starts_with($ref, 'FA') ? 'FV-WEB-2026-999' : null,
                'motif' => str_starts_with($ref, 'FA') ? 'x' : null, 'date_facture' => now(), 'client' => 'X', 'total_ht' => 1, 'total_taxe' => 0,
                'total_ttc' => 1, 'statut' => 'a_transmettre', 'updated_at' => now(), 'serveur_modifie_le' => now()])->save();
        }
        $p = $this->produit('Goliath', 'B');
        $c = $this->compta();
        $this->emettre($c, $this->vente([[$p, 1, 11800]]));
        $this->assertTrue(Facture::query()->where('reference', 'FV-WEB-2026-1001')->exists(), '1001 suit 999 et 1000 : maximum numérique, pas le dernier lu ni un tri textuel');

        // La vente est de l'an dernier : le numéro porte l'année de la vente (comme le poste).
        $this->emettre($c, $this->vente([[$p, 1, 11800]], ['date_vente' => CarbonImmutable::parse('2025-03-01 10:00:00', 'UTC')]));
        $this->assertTrue(Facture::query()->where('reference', 'FV-WEB-2025-041')->exists());
    }

    // ---------------------------------------------------------------------- Droits

    public function test_sans_manage_facturation_aucune_ecriture_chaque_methode_est_gardee(): void
    {
        $f = $this->factureEmise();
        $caissier = $this->utilisateur('caissier', 'amina');
        $neuf = fn () => Livewire::actingAs($caissier)->test(FacturesMecef::class);

        $neuf()->assertDontSee('Émettre une Facture');
        $neuf()->call('ouvrirEmission')->assertForbidden();
        $neuf()->call('emettre')->assertForbidden();
        $neuf()->call('ouvrirAvoir', $f->id)->assertForbidden();
        $neuf()->call('emettreAvoir')->assertForbidden();
        $this->assertSame(1, Facture::query()->count());
        // Lecture et export : permis avec view-facturation.
        $neuf()->call('exporter')->assertOk();
    }

    public function test_l_export_exige_view_facturation_dans_la_methode(): void
    {
        $this->factureEmise();
        $animalier = $this->utilisateur('animalier', 'ferme');
        Livewire::actingAs($animalier)->test(FacturesMecef::class)->call('exporter')->assertForbidden();
    }

    public function test_l_admin_emet_aussi(): void
    {
        $v = $this->vente([[$this->produit('Goliath', 'B'), 1, 11800]]);
        $this->emettre(Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(FacturesMecef::class), $v);
        $this->assertSame(1, Facture::query()->count());
    }

    // ----------------------------------------------------------------------- Avoirs

    private function avoir($c, Facture $f, string $motif = 'Retour de marchandise', bool $total = true, array $quantites = [])
    {
        $c->call('ouvrirAvoir', $f->id)->set('avoirMotif', $motif)->set('avoirTotal', $total);
        foreach ($quantites as $ligneId => $q) {
            $c->set("avoirQuantites.$ligneId", $q);
        }

        return $c->call('emettreAvoir');
    }

    public function test_avoir_total_reprend_la_facture_et_la_contrepasse(): void
    {
        $f = $this->factureEmise();
        $c = $this->compta();
        $this->avoir($c, $f)->assertSet('erreur', null)->assertSet('avoirSur', null);

        $a = $this->laFacture('FA-WEB');
        $this->assertSame('FA-WEB-2026-001', $a->reference);
        $this->assertSame('FA', $a->type);
        $this->assertSame($f->reference, $a->origine_ref);
        $this->assertSame('Retour de marchandise', $a->motif);
        $this->assertNull($a->vente_ref);
        $this->assertSame('a_transmettre', $a->statut);
        $this->assertSame(Catalogue::POSTE_WEB, $a->device_id);
        $this->assertSame($f->client, $a->client);
        $this->assertSame('3201111111111', $a->client_ifu);
        $this->assertSame('Natitingou', $a->client_adresse);
        $this->assertSame([$f->total_ht, $f->total_taxe, $f->total_ttc], [$a->total_ht, $a->total_taxe, $a->total_ttc]);
        $this->assertSame($f->lignes()->count(), $a->lignes()->count());
        $this->assertEqualsCanonicalizing(
            $f->lignes->map(fn ($l) => [$l->designation, $l->quantite, $l->prix_unitaire_ht, $l->groupe_taxe, $l->montant_ht, $l->montant_taxe])->all(),
            $a->lignes->map(fn ($l) => [$l->designation, $l->quantite, $l->prix_unitaire_ht, $l->groupe_taxe, $l->montant_ht, $l->montant_taxe])->all(),
        );
        $this->assertEmpty($a->lignes->pluck('id')->intersect($f->lignes->pluck('id')), 'lignes neuves, jamais celles de la facture');
        $this->assertSame('a_transmettre', $f->fresh()->statut, 'la facture d\'origine n\'est jamais modifiée');
        $this->assertSame(0, EcritureComptable::query()->count());
    }

    public function test_un_second_avoir_total_est_refuse_avoir_au_plus_la_facture(): void
    {
        $f = $this->factureEmise();
        $c = $this->compta();
        $this->avoir($c, $f)->assertSet('erreur', null);
        $this->avoir($c, $f, 'Encore');
        $this->assertStringContainsString('dépasseraient la facture', (string) $c->get('erreur'));
        $this->assertStringContainsString('28 600', (string) $c->get('erreur'));
        $this->assertSame(1, Facture::query()->where('type', 'FA')->count());
    }

    public function test_avoir_partiel_ligne_a_ligne_les_avoirs_se_cumulent_jusqu_au_total(): void
    {
        $v = $this->vente([[$this->produit('Aliment', 'B'), 4, 2950]]); // 4 × 2 950 TTC = 11 800 : HT 10 000
        $this->emettre($this->compta(), $v);
        $f = $this->laFacture();
        $ligne = $f->lignes->first()->id;

        $c = $this->compta();
        $this->avoir($c, $f, 'Un', false, [$ligne => '1'])->assertSet('erreur', null);
        $a1 = $this->laFacture('FA-WEB');
        $this->assertSame(2500.0, $a1->total_ht);
        $this->assertSame(450.0, $a1->total_taxe);
        $this->assertSame(2950.0, $a1->total_ttc);
        $this->assertSame(1.0, $a1->lignes->first()->quantite);

        $this->avoir($c, $f, 'Deux', false, [$ligne => '2,5'])->assertSet('erreur', null);
        $this->avoir($c, $f, 'Trop', false, [$ligne => '1']);
        $this->assertStringContainsString('dépasseraient', (string) $c->get('erreur'), '1 + 2,5 + 1 > 4');
        $this->avoir($c, $f, 'Reste', false, [$ligne => '0,5'])->assertSet('erreur', null);
        $this->assertSame(3, Facture::query()->where('type', 'FA')->count());
        $this->assertEqualsWithDelta(11800, (float) Facture::query()->where('type', 'FA')->sum('total_ttc'), 0.01);
        $this->avoir($c, $f, 'Plus rien', false, [$ligne => '0,01']);
        $this->assertStringContainsString('dépasseraient', (string) $c->get('erreur'));
    }

    public function test_le_plafond_d_un_avoir_ne_compte_que_les_avoirs_de_sa_facture(): void
    {
        $f1 = $this->factureEmise();
        $v = $this->vente([[$this->produit('Aliment', 'B'), 1, 11800]]);
        $this->emettre($this->compta(), $v);
        $f2 = Facture::query()->where('reference', 'FV-WEB-2026-002')->firstOrFail();

        $this->avoir($this->compta(), $f1)->assertSet('erreur', null);
        // L'avoir total de f1 (28 600) ne doit pas compter contre f2 (11 800).
        $this->avoir($this->compta(), $f2)->assertSet('erreur', null);
        $this->assertSame(2, Facture::query()->where('type', 'FA')->count());
    }

    public function test_avoir_quantite_superieure_a_la_ligne_invalide_ou_vide_refusee(): void
    {
        $v = $this->vente([[$this->produit('Aliment', 'B'), 4, 2950]]);
        $this->emettre($this->compta(), $v);
        $f = $this->laFacture();
        $ligne = $f->lignes->first()->id;
        $c = $this->compta();

        $this->avoir($c, $f, 'x', false, [$ligne => '5']);
        $this->assertStringContainsString('dépasse celle de la facture', (string) $c->get('erreur'));
        $this->avoir($c, $f, 'x', false, [$ligne => 'abc']);
        $this->assertStringContainsString('invalide', (string) $c->get('erreur'));
        $this->avoir($c, $f, 'x', false, [$ligne => '-1']);
        $this->assertStringContainsString('invalide', (string) $c->get('erreur'));
        $this->avoir($c, $f, 'x', false, [$ligne => '0']);
        $this->assertStringContainsString('sans ligne', (string) $c->get('erreur'));
        $this->avoir($c, $f, 'x', false, []);
        $this->assertStringContainsString('sans ligne', (string) $c->get('erreur'));
        $this->assertSame(0, Facture::query()->where('type', 'FA')->count());
    }

    public function test_avoir_sans_motif_refuse_et_motif_trop_long(): void
    {
        $f = $this->factureEmise();
        $c = $this->compta();
        $this->avoir($c, $f, '   ');
        $this->assertStringContainsString('motif requis', (string) $c->get('erreur'));
        $this->avoir($c, $f, str_repeat('m', 256));
        $this->assertStringContainsString('trop long', (string) $c->get('erreur'));
        $this->assertSame(0, Facture::query()->where('type', 'FA')->count());
    }

    public function test_un_avoir_ne_se_fait_que_sur_une_facture_de_vente_connue(): void
    {
        $f = $this->factureEmise();
        $c = $this->compta();
        $this->avoir($c, $f)->assertSet('erreur', null);
        $a = $this->laFacture('FA-WEB');

        $c2 = $this->compta();
        $this->avoir($c2, $a, 'sur un avoir');
        $this->assertStringContainsString('ne se fait que sur une facture de vente', (string) $c2->get('erreur'));
        $c3 = $this->compta();
        $c3->call('ouvrirAvoir', (string) Str::uuid())->call('emettreAvoir');
        $this->assertStringContainsString('introuvable', (string) $c3->get('erreur'));
        $this->assertSame(1, Facture::query()->where('type', 'FA')->count());
    }

    public function test_avoir_sur_une_facture_de_poste_a_code_ok_sans_code_refuse(): void
    {
        $v = $this->vente([[$this->produit('Goliath', 'B'), 1, 11800]]);
        $faire = function (string $ref, string $portee) use ($v) {
            $f = (new Facture)->forceFill(['id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => $ref,
                'portee_reference' => $portee, 'type' => 'FV', 'vente_ref' => $v->reference.$ref, 'date_facture' => now(), 'client' => 'X',
                'total_ht' => 10000, 'total_taxe' => 1800, 'total_ttc' => 11800, 'statut' => 'normalisee', 'code_mecef' => 'C', 'nim' => 'N',
                'date_normalisation' => now(), 'updated_at' => now(), 'serveur_modifie_le' => now()]);
            $f->save();
            (new LigneFacture)->forceFill(['id' => (string) Str::uuid(), 'facture_id' => $f->id, 'designation' => 'Goliath', 'quantite' => 1,
                'prix_unitaire_ht' => 10000, 'groupe_taxe' => 'B', 'taux_taxe' => 18, 'montant_ht' => 10000, 'montant_taxe' => 1800])->save();

            return $f;
        };

        $codee = $faire('FV-P4-2026-001', '');
        $this->avoir($this->compta(), $codee)->assertSet('erreur', null);
        $this->assertTrue(Facture::query()->where('origine_ref', 'FV-P4-2026-001')->exists());

        $sansCode = $faire('FV-2026-001', (string) Str::uuid());
        $c = $this->compta();
        $this->avoir($c, $sansCode);
        $this->assertStringContainsString("n'a pas de numéro de poste", (string) $c->get('erreur'));
        $this->assertFalse(Facture::query()->where('origine_ref', 'FV-2026-001')->exists());
    }

    public function test_une_facture_est_immuable_aucune_methode_ne_la_modifie(): void
    {
        $f = $this->factureEmise();
        $avant = Facture::query()->find($f->id)->toArray();
        $lignes = LigneFacture::query()->orderBy('id')->get()->toArray();

        $c = $this->compta();
        $this->avoir($c, $f);
        $c->call('ouvrir', $f->id)->call('fermer')->call('filtrer', 'normalisee')->set('recherche', 'x');

        $this->assertSame($avant, Facture::query()->find($f->id)->toArray());
        $this->assertSame($lignes, LigneFacture::query()->whereIn('facture_id', [$f->id])->orderBy('id')->get()->toArray());
    }

    // ---------------------------------------------------------- Affichage et détail

    public function test_le_detail_d_une_facture_web_dit_emise_sur_web_et_propose_imprimer_et_avoir(): void
    {
        $f = $this->factureEmise();
        $this->compta()->call('ouvrir', $f->id)
            ->assertSee('Émise sur')->assertSee('Web')->assertSeeHtml('data-info="transmission-web"')
            ->assertSeeHtml('data-action="imprimer"')->assertSeeHtml('data-action="avoir"')
            ->assertSee(route('factures-mecef.imprimer', $f->id));
    }

    public function test_apres_emission_la_facture_s_ouvre_et_le_message_est_affiche(): void
    {
        $v = $this->vente([[$this->produit('Goliath', 'B'), 1, 11800]]);
        $this->emettre($this->compta(), $v)->assertSee('Facture FV-WEB-2026-001 émise')->assertSeeHtml('data-detail="FV-WEB-2026-001"');
    }

    public function test_une_facture_web_est_servie_aux_postes_avec_ses_lignes_et_sans_colonne_interne(): void
    {
        $f = $this->factureEmise();
        $poste = $this->utilisateur('comptable', 'posteur');
        $device = (string) Str::uuid();
        $jeton = app(\App\Services\PostesService::class)->appairer($poste, $device)['jeton'];

        $this->app['auth']->forgetGuards();
        $recue = collect($this->withToken($jeton)->getJson('/api/sync/pull')->assertOk()->json('tables.factures'))->firstWhere('id', $f->id);
        $this->assertSame(Catalogue::POSTE_WEB, $recue['device_id']);
        $this->assertSame('FV-WEB-2026-001', $recue['reference']);
        $this->assertCount(2, $recue['lignes']);
        $this->assertSame('a_transmettre', $recue['statut']);
        $this->assertArrayNotHasKey('transmission_poste', $recue);
    }

    // ------------------------------------------------------------- Vue imprimable

    public function test_la_vue_imprimable_exige_connexion_droit_et_module(): void
    {
        $f = $this->factureEmise();
        $url = route('factures-mecef.imprimer', $f->id);

        auth()->logout();
        $this->get($url)->assertRedirect(route('login'));
        $this->actingAs($this->utilisateur('animalier', 'ferme'))->get($url)->assertForbidden();
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get($url)->assertOk();
        $this->actingAs($this->utilisateur('comptable', 'compta2'))->get($url)->assertOk();
        $this->actingAs($this->utilisateur('admin', 'gerante'))->get(route('factures-mecef.imprimer', (string) Str::uuid()))->assertNotFound();

        ParametresEntreprise::courant()->forceFill(['mecef_actif' => false])->save();
        $this->actingAs($this->utilisateur('admin', 'gerante2'))->get($url)->assertNotFound();
    }

    public function test_la_vue_imprimable_d_une_facture_non_normalisee_le_dit_en_toutes_lettres(): void
    {
        $f = $this->factureEmise();
        $r = $this->actingAs($this->utilisateur('caissier', 'amina'))->get(route('factures-mecef.imprimer', $f->id))->assertOk();

        $r->assertSee('Facture de vente — FV-WEB-2026-001')
            ->assertSeeHtml('data-mention="non-normalisee"')->assertDontSeeHtml('data-mention="normalisee"')
            ->assertSee('FACTURE NON NORMALISÉE')->assertSee('ne vaut pas facture normalisée')
            ->assertDontSee('Code MeCeF/DGI')
            ->assertSee('ALLMANY ET COMPAGNIE')->assertSee('3201234567890')
            ->assertSee('IFU du client : 3201111111111')->assertSee('Adresse : Natitingou')
            ->assertSee('Vente d\'origine : '.$f->vente_ref, false)
            ->assertSee('Exonéré')->assertSee('18 %')
            ->assertSee('Imprimer / PDF')->assertSee('@media print')->assertSee('window.print()')
            ->assertSee('Émise depuis le web');
        $r->assertSeeHtml('data-total="ht">25 000 FCFA<')->assertSeeHtml('data-total="taxe">3 600 FCFA<')->assertSeeHtml('data-total="net">28 600 FCFA<');
        $r->assertSeeHtml('data-groupe="A"')->assertSeeHtml('data-groupe="B"');
        $this->assertStringNotContainsString('QR', $r->getContent(), 'aucun QR fabriqué localement');
    }

    public function test_la_vue_imprimable_d_une_facture_normalisee_porte_code_nim_compteur_et_lien(): void
    {
        $f = $this->factureEmise();
        Facture::query()->whereKey($f->id)->update([
            'statut' => 'normalisee', 'code_mecef' => 'CODE-DGI-9', 'nim' => 'NIM-77', 'compteur' => '12/50',
            'lien_verification' => 'https://dgi.example/v/9', 'date_normalisation' => '2026-11-06 09:00:00.000000',
        ]);
        $r = $this->actingAs($this->utilisateur('caissier', 'amina'))->get(route('factures-mecef.imprimer', $f->id))->assertOk();

        $r->assertSeeHtml('data-mention="normalisee"')->assertDontSeeHtml('data-mention="non-normalisee"')
            ->assertSee('Code MeCeF/DGI : CODE-DGI-9')->assertSee('NIM : NIM-77')->assertSee('Compteur : 12/50')
            ->assertSee('Normalisée le 06/11/2026')->assertSee('Vérification : https://dgi.example/v/9')
            ->assertDontSee('FACTURE NON NORMALISÉE');
    }

    public function test_une_facture_dite_normalisee_sans_code_s_imprime_comme_non_normalisee(): void
    {
        $f = $this->factureEmise();
        Facture::query()->whereKey($f->id)->update(['statut' => 'normalisee', 'code_mecef' => '']);
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get(route('factures-mecef.imprimer', $f->id))
            ->assertSeeHtml('data-mention="non-normalisee"');
    }

    public function test_la_vue_imprimable_d_une_facture_rejetee_montre_le_dernier_refus(): void
    {
        $f = $this->factureEmise();
        Facture::query()->whereKey($f->id)->update(['statut' => 'rejetee', 'erreur_transmission' => 'IFU invalide']);
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get(route('factures-mecef.imprimer', $f->id))
            ->assertSee('Dernier refus : IFU invalide')->assertSeeHtml('data-mention="non-normalisee"');
    }

    public function test_la_vue_imprimable_d_un_avoir_est_en_negatif_et_nomme_la_facture_corrigee(): void
    {
        $f = $this->factureEmise();
        $this->avoir($this->compta(), $f, 'Retour de poulets');
        $a = $this->laFacture('FA-WEB');
        $r = $this->actingAs($this->utilisateur('caissier', 'amina'))->get(route('factures-mecef.imprimer', $a->id))->assertOk();

        $r->assertSee("Facture d'avoir — FA-WEB-2026-001")
            ->assertSee('Avoir sur la facture FV-WEB-2026-001 — Retour de poulets.')
            ->assertSeeHtml('data-total="ttc">-28 600 FCFA<')->assertSeeHtml('data-total="net">-28 600 FCFA<')
            ->assertSeeHtml('data-total="ht">-25 000 FCFA<')->assertSeeHtml('data-total="taxe">-3 600 FCFA<');
    }

    public function test_la_vue_imprimable_ne_contient_ni_jeton_ni_url_e_mecef(): void
    {
        $f = $this->factureEmise();
        ParametresEntreprise::courant()->forceFill(['mecef_url' => 'https://mecef.secret.example', 'mecef_nim' => 'NIM-SECRET'])->save();
        $html = $this->actingAs($this->utilisateur('caissier', 'amina'))->get(route('factures-mecef.imprimer', $f->id))->getContent();
        $this->assertStringNotContainsString('secret', strtolower($html));
        $this->assertStringNotContainsString('NIM-SECRET', $html);
    }

    // ----------------------------------------------------------------------- XLSX

    public function test_export_xlsx_meme_contenu_que_l_ecran_filtres_compris_avoir_en_negatif(): void
    {
        $f = $this->factureEmise();
        $this->avoir($this->compta(), $f, 'Retour');
        $c = $this->compta();

        $c->call('exporter');
        $c->assertFileDownloaded('factures-mecef.xlsx', null, ExportXlsx::TYPE);
        $lignes = $this->lignesXlsx(base64_decode($c->effects['download']['content']));
        $this->assertSame(['Référence', 'Date', 'Client', 'Facture corrigée', 'Total TTC (FCFA)', 'Statut'], $lignes[0]);
        $this->assertCount(3, $lignes);
        $fv = collect($lignes)->firstWhere(0, 'FV-WEB-2026-001');
        $fa = collect($lignes)->firstWhere(0, 'FA-WEB-2026-001');
        $this->assertSame('28600', $fv[4]);
        $this->assertSame('-28600', $fa[4], 'l\'avoir est en négatif, comme à l\'écran');
        $this->assertSame('FV-WEB-2026-001', $fa[3]);
        $this->assertSame('À transmettre', $fa[5]);

        $c->set('recherche', 'FA-WEB')->call('exporter');
        $this->assertCount(2, $this->lignesXlsx(base64_decode($c->effects['download']['content'])), 'le filtre de l\'écran s\'applique');
    }
}
