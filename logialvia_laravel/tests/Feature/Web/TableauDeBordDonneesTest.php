<?php

namespace Tests\Feature\Web;

use App\Livewire\TableauDeBord;
use App\Models\Achat;
use App\Models\AuditLog;
use App\Models\Bande;
use App\Models\Client;
use App\Models\CycleCouveuse;
use App\Models\EcheanceProphylaxie;
use App\Models\FicheJournee;
use App\Models\Fournisseur;
use App\Models\LigneVente;
use App\Models\ModuleActif;
use App\Models\ProduitVendable;
use App\Models\SoinCalendrier;
use App\Models\User;
use App\Models\Vente;
use App\Support\UuidDeterministe;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Concerns\JeuComptable;
use Tests\TestCase;

/**
 * DONNEES du Tableau de Bord (cles de `render()` ajoutees a la suite de la synchronisation de la
 * comptabilite, de l'elevage, de la couveuse et des soins) : valeurs exactes, `null` sans droit,
 * filieres inactives exclues, periode respectee, et un cas de PARITE chiffree avec le Dart
 * (`jeu_commun_chiffres_test.dart` : resultat net 133 000, tresorerie 545 000).
 *
 * « Maintenant » est fige au 18/11/2026 10:00 (Africa/Porto-Novo = UTC+1).
 */
class TableauDeBordDonneesTest extends TestCase
{
    use JeuComptable;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerPourLesEcrans();
        $this->travelTo(CarbonImmutable::parse('2026-11-18 10:00:00', 'Africa/Porto-Novo'));
    }

    private function tableau(string $role = 'admin')
    {
        $u = User::query()->where('username', $role)->first() ?? $this->utilisateurAvecRole($role, $role);

        return Livewire::actingAs($u)->test(TableauDeBord::class);
    }

    private function loc(string $instant): CarbonImmutable
    {
        return CarbonImmutable::parse($instant, 'Africa/Porto-Novo')->utc();
    }

    private function produit(string $cat = 'Volaille'): ProduitVendable
    {
        return (new ProduitVendable)->forceFill([
            'id' => (string) Str::uuid(), 'sku' => 'S'.Str::random(5), 'name' => 'P'.Str::random(4), 'cat' => $cat,
            'price' => 1000, 'unit' => 'u', 'icon' => 'egg', 'groupe_taxe' => 'A', 'threshold' => 0,
            'saisi_le' => now(), 'created_at' => now(), 'updated_at' => now(),
        ]);
    }

    /** Vente d'une ligne : CA = qte x pu. */
    private function vente(string $quand, float $qte, float $pu, string $statut = 'Payée', array $surcharge = []): Vente
    {
        static $n = 0;
        $n++;
        $produit = $this->produit();
        $produit->save();
        $v = (new Vente)->forceFill($surcharge + [
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => "V-P1-2026-D$n",
            'portee_reference' => '', 'client' => 'Amina Bako', 'date_vente' => $this->loc($quand), 'mode' => 'Espèces',
            'status' => $statut, 'total' => $qte * $pu, 'paye' => $qte * $pu,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $v->save();
        (new LigneVente)->forceFill([
            'id' => (string) Str::uuid(), 'vente_id' => $v->id, 'produit_id' => $produit->id, 'name' => $produit->name,
            'qte' => $qte, 'pu' => $pu,
        ])->save();

        return $v;
    }

    private function achat(string $quand, float $total, string $statut = 'Reçu'): Achat
    {
        static $n = 0;
        $n++;
        $f = Fournisseur::query()->first();
        if ($f === null) {
            $f = (new Fournisseur)->forceFill([
                'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => 'Provenderie du Nord',
                'updated_at' => now(), 'serveur_modifie_le' => now(),
            ]);
            $f->save();
        }
        $a = (new Achat)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => "ACH-P1-2026-D$n",
            'portee_reference' => '', 'fournisseur_id' => $f->id, 'date_achat' => $this->loc($quand), 'statut' => $statut,
            'total' => $total, 'paye' => 0, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $a->save();

        return $a;
    }

    private function journee(string $espece, string $jour, array $surcharge = []): void
    {
        (new FicheJournee)->forceFill(array_merge([
            'id' => UuidDeterministe::ficheJournee($espece, $jour), 'device_id' => (string) Str::uuid(),
            'espece' => $espece, 'date' => $jour,
            'achat' => 0, 'ne' => 0, 'vente' => 0,
            'mort_cat1' => 0, 'mort_cat2' => 0, 'mort_cat3' => 0, 'mort_cat4' => null,
            'don_cat1' => 0, 'don_cat2' => 0, 'don_cat3' => 0, 'don_cat4' => null,
            'effectif' => 0, 'eff_cat1_day' => 0, 'eff_cat2_day' => 0, 'eff_cat3_day' => 0, 'eff_cat4_day' => null,
            'traitement_valide' => false, 'is_recorded' => true,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge))->save();
    }

    private function lot(string $code, array $surcharge = []): CycleCouveuse
    {
        $l = (new CycleCouveuse)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'code_incubation' => $code,
            'portee_code' => '', 'espece' => 'goliath', 'date_incubation' => '2026-11-10',
            'oeufs_couves' => 100, 'poussins_nes' => null, 'oeufs_perdus' => null, 'statut' => 'En Incubation',
            'machine_id' => null, 'oeufs_blancs_j7' => null, 'oeufs_gates_j14' => null, 'lot_parent_id' => null,
            'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ], $surcharge));
        $l->save();

        return $l;
    }

    private function bande(string $espece = 'goliaths', string $debut = '2026-11-10', string $code = 'B-1'): Bande
    {
        $b = (new Bande)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'espece' => $espece, 'code' => $code,
            'date_mise_en_bande' => $debut, 'effectif_initial' => 100, 'date_cloture' => null, 'observations' => null,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $b->save();

        return $b;
    }

    private function echeance(int $jour, string $espece = 'goliaths'): EcheanceProphylaxie
    {
        return EcheanceProphylaxie::query()->create([
            'id' => (string) Str::uuid(), 'espece' => $espece, 'jour_cycle' => $jour, 'traitement' => "Cure J$jour",
            'produit' => 'ND-Lasota', 'remanence_jours' => 0, 'dose' => '1 goutte', 'saisi_le' => now(),
        ]);
    }

    private function soin(array $surcharge = []): SoinCalendrier
    {
        $s = (new SoinCalendrier)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'espece' => 'goliaths',
            'date_prevue' => '2026-11-18', 'type_soin' => 'Vaccination', 'statut' => 'Planifié', 'produit' => 'ND-Lasota',
            'dose' => '1 goutte', 'remanence_jours' => 0, 'cout_fcfa' => 0,
            'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ], $surcharge));
        $s->save();

        return $s;
    }

    private function client(string $nom, ?string $naissance): Client
    {
        $c = (new Client)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => $nom, 'telephone' => null,
            'date_naissance' => $naissance, 'dernier_contact' => null, 'solde_creance' => 0,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $c->save();

        return $c;
    }

    private function periode($composant, string $debut, string $fin)
    {
        return $composant->set('debut', $debut)->set('fin', $fin);
    }

    // ------------------------------------------------------- Parite chiffree avec le Dart

    public function test_parite_dart_le_jeu_commun_donne_545000_de_tresorerie_et_133000_de_resultat(): void
    {
        $this->poserLeJeuCommun();
        // Dart (`jeu_commun_chiffres_test.dart`) : produits 200 000 (702 : 120 000 + 701 : 80 000), charges 67 000
        // (602 : 40 000 + 618 : 15 000 + 625 : 12 000), resultat 133 000, tresorerie (571 + ouverture) 545 000.
        $this->vente('2026-06-01 09:00:00', 4, 50000);

        $t = $this->periode($this->tableau(), '2026-01-01', '2026-12-31');

        $this->assertEquals(['total' => 545000.0, 'especes' => 545000.0, 'mobile' => 0.0], $t->viewData('tresorerie'));
        $this->assertEquals(['total' => 67000.0, 'intrants' => 40000.0], $t->viewData('depenses'));
        // CA des ventes de la periode = 200 000 : marge = 133 000 / 200 000.
        $this->assertEqualsWithDelta(133000.0, $t->viewData('resultatNet')['montant'], 0.001);
        $this->assertEqualsWithDelta(66.5, $t->viewData('resultatNet')['marge'], 0.0001);
    }

    public function test_la_tresorerie_se_ventile_entre_caisse_et_mobile_money(): void
    {
        $this->poserLeJeuCommun();
        $this->poserPiece('OD-P1-2026-0003', 2026, 8, 1, 'OD', [['552', 25000, 0, null], ['571', 0, 25000, null]]);

        $t = $this->tableau();

        $this->assertEquals(['total' => 545000.0, 'especes' => 520000.0, 'mobile' => 25000.0], $t->viewData('tresorerie'));
    }

    public function test_un_compte_de_tresorerie_a_decouvert_n_entre_pas_dans_la_tresorerie_disponible(): void
    {
        $this->poserPiece('OD-P1-2026-0001', 2026, 1, 2, 'OD', [['571', 80000, 0, null], ['101', 0, 80000, null]]);
        $this->poserPiece('OD-P1-2026-0002', 2026, 1, 3, 'OD', [['571', 30000, 0, null], ['552', 0, 30000, null]]);

        // 571 = 110 000 debiteur ; 552 = -30 000 (decouvert) : `debiteursParClasse('5')` ne retient que le debiteur.
        $this->assertEquals(['total' => 110000.0, 'especes' => 110000.0, 'mobile' => 0.0], $this->tableau()->viewData('tresorerie'));
    }

    // ------------------------------------------------------------ Depenses et resultat net

    public function test_la_periode_du_filtre_borne_les_depenses_et_le_resultat(): void
    {
        $this->poserLeJeuCommun();

        $avril = $this->periode($this->tableau(), '2026-04-01', '2026-04-30');
        $this->assertEquals(['total' => 40000.0, 'intrants' => 40000.0], $avril->viewData('depenses'));
        $this->assertEqualsWithDelta(-40000.0, $avril->viewData('resultatNet')['montant'], 0.001);

        $mai = $this->periode($this->tableau(), '2026-05-01', '2026-05-31');
        $this->assertEquals(['total' => 27000.0, 'intrants' => 0.0], $mai->viewData('depenses'));
        $this->assertEqualsWithDelta(-27000.0, $mai->viewData('resultatNet')['montant'], 0.001);

        // Bornes incluses a la journee : le 20/05 (piece de 12 000) est dans [20/05, 20/05].
        $jour = $this->periode($this->tableau(), '2026-05-20', '2026-05-20');
        $this->assertEquals(['total' => 12000.0, 'intrants' => 0.0], $jour->viewData('depenses'));

        // Sans aucune ecriture dans la periode : zero honnete, pas null.
        $vide = $this->periode($this->tableau(), '2026-09-01', '2026-09-30');
        $this->assertEquals(['total' => 0.0, 'intrants' => 0.0], $vide->viewData('depenses'));
        $this->assertEqualsWithDelta(0.0, $vide->viewData('resultatNet')['montant'], 0.001);
    }

    public function test_la_marge_est_indefinie_sans_chiffre_d_affaires(): void
    {
        $this->poserLeJeuCommun();

        $t = $this->periode($this->tableau(), '2026-01-01', '2026-12-31');

        $this->assertEqualsWithDelta(133000.0, $t->viewData('resultatNet')['montant'], 0.001);
        $this->assertNull($t->viewData('resultatNet')['marge']);
    }

    public function test_les_ecritures_d_a_nouveau_et_de_cloture_ne_sont_pas_des_charges_ni_des_produits(): void
    {
        $this->poserPiece('CL-P1-2026-0001', 2026, 11, 10, 'CL', [['131', 0, 90000, null], ['602', 0, 90000, null]]);
        $this->poserPiece('AN-P1-2026-0001', 2026, 11, 11, 'AN', [['571', 10000, 0, null], ['101', 0, 10000, null]]);

        $t = $this->periode($this->tableau(), '2026-11-01', '2026-11-30');

        $this->assertEquals(['total' => 0.0, 'intrants' => 0.0], $t->viewData('depenses'));
        $this->assertEqualsWithDelta(0.0, $t->viewData('resultatNet')['montant'], 0.001);
    }

    public function test_une_periode_invalide_retombe_sur_le_mois_en_cours(): void
    {
        $this->poserPiece('DEP-P1-2026-0001', 2026, 11, 5, 'CA', [['618', 9000, 0, null], ['571', 0, 9000, null]]);
        $this->poserPiece('DEP-P1-2026-0002', 2026, 10, 5, 'CA', [['618', 4000, 0, null], ['571', 0, 4000, null]]);

        $t = $this->periode($this->tableau(), 'n-importe-quoi', '2026-11-30');

        $this->assertEquals(['total' => 9000.0, 'intrants' => 0.0], $t->viewData('depenses'));
    }

    public function test_depenses_par_mois_alignees_sur_les_six_mois_du_ca(): void
    {
        $this->poserLeJeuCommun();
        $this->poserPiece('DEP-P1-2026-0009', 2026, 11, 16, 'CA', [['618', 7000, 0, null], ['571', 0, 7000, null]]);

        $t = $this->tableau();

        $cles = array_column($t->viewData('mois'), 'cle');
        $this->assertSame(['2026-06', '2026-07', '2026-08', '2026-09', '2026-10', '2026-11'], $cles);
        $this->assertSame($cles, array_column($t->viewData('moisDepenses'), 'cle'));
        $this->assertEquals([0.0, 0.0, 0.0, 0.0, 0.0, 7000.0], array_column($t->viewData('moisDepenses'), 'depenses'));
    }

    public function test_les_six_derniers_jours_portent_le_ca_et_les_depenses_du_jour(): void
    {
        $this->vente('2026-11-18 08:00:00', 1, 5000);
        $this->vente('2026-11-16 12:00:00', 1, 3000);
        $this->vente('2026-11-16 15:00:00', 1, 2000, 'Annulée');
        $this->vente('2026-11-12 12:00:00', 1, 9999);
        $this->poserPiece('DEP-P1-2026-0001', 2026, 11, 16, 'CA', [['618', 7000, 0, null], ['571', 0, 7000, null]]);
        $this->poserPiece('DEP-P1-2026-0002', 2026, 11, 12, 'CA', [['618', 1111, 0, null], ['571', 0, 1111, null]]);

        $jours = $this->tableau()->viewData('jours');

        $this->assertSame(['13/11', '14/11', '15/11', '16/11', '17/11', '18/11'], array_column($jours, 'libelle'));
        $this->assertEquals([0.0, 0.0, 0.0, 3000.0, 0.0, 5000.0], array_column($jours, 'ca'));
        $this->assertEquals([0.0, 0.0, 0.0, 7000.0, 0.0, 0.0], array_column($jours, 'depenses'));
    }

    public function test_un_jour_tombe_dans_le_fuseau_metier_pas_en_utc(): void
    {
        // 18/11 00:30 heure locale = 17/11 23:30 UTC : la vente est du 18, pas du 17.
        $this->vente('2026-11-18 00:30:00', 1, 4000);

        $jours = $this->tableau()->viewData('jours');

        $this->assertEquals(0.0, $jours[4]['ca']);
        $this->assertEquals(4000.0, $jours[5]['ca']);
    }

    // ---------------------------------------------------------------------- Droits (null)

    public function test_le_caissier_ne_voit_ni_comptabilite_ni_elevage_ni_journal(): void
    {
        $this->poserLeJeuCommun();
        $t = $this->tableau('caissier');

        foreach (['tresorerie', 'depenses', 'resultatNet', 'moisDepenses', 'cheptel', 'couveuse', 'filieres', 'activites', 'stockCritique'] as $cle) {
            $this->assertNull($t->viewData($cle), $cle);
        }
        $this->assertIsArray($t->viewData('jours'));
        $this->assertNull($t->viewData('jours')[0]['depenses']);
        $this->assertIsArray($t->viewData('alertes'));
        $this->assertSame([], $t->viewData('transactions')['achats']);
        $this->assertSame([], $t->viewData('transactions')['depenses']);
    }

    public function test_l_animalier_ne_voit_que_l_elevage(): void
    {
        $this->poserLeJeuCommun();
        $this->vente('2026-11-10 09:00:00', 1, 5000, 'Avance', ['total' => 5000, 'paye' => 1000]);
        $this->client('Awa', '1990-11-18');
        $t = $this->tableau('animalier');

        foreach (['tresorerie', 'depenses', 'resultatNet', 'moisDepenses', 'jours', 'transactions', 'activites', 'stockCritique'] as $cle) {
            $this->assertNull($t->viewData($cle), $cle);
        }
        $this->assertNotNull($t->viewData('cheptel'));
        $this->assertNotNull($t->viewData('couveuse'));
        $this->assertSame(['goliaths', 'pintades'], array_column($t->viewData('filieres'), 'code'));
        // Ni soldes (ventes) ni anniversaires (clients) dans les alertes d'un compte sans `view-ventes`.
        $this->assertSame([], $t->viewData('alertes'));
    }

    public function test_le_comptable_voit_la_comptabilite_mais_pas_l_elevage_ni_le_journal(): void
    {
        $this->poserLeJeuCommun();
        $t = $this->tableau('comptable');

        $this->assertEquals(545000.0, $t->viewData('tresorerie')['total']);
        $this->assertNotNull($t->viewData('depenses'));
        foreach (['cheptel', 'couveuse', 'filieres', 'activites', 'stockCritique'] as $cle) {
            $this->assertNull($t->viewData($cle), $cle);
        }
    }

    public function test_le_stock_critique_reste_null_meme_pour_l_administrateur(): void
    {
        // Le stock d'un intrant est propre a chaque poste (jamais synchronise) : rien a calculer.
        $this->assertNull($this->tableau()->viewData('stockCritique'));
    }

    // ------------------------------------------------------------------ Cheptel et filieres

    public function test_les_filieres_inactives_sont_exclues_du_cheptel(): void
    {
        $this->journee('goliaths', '2026-11-05', ['effectif' => 110, 'mort_cat1' => 2]);
        $this->journee('goliaths', '2026-11-10', ['effectif' => 100, 'eff_cat2_day' => 30, 'eff_cat3_day' => 40]);
        $this->journee('pintades', '2026-11-12', ['effectif' => 40]);
        $this->journee('lapins', '2026-11-12', ['effectif' => 30]);
        $this->journee('poulets', '2026-11-12', ['effectif' => 500]);

        $t = $this->tableau();

        $this->assertSame(['goliaths', 'pintades'], array_column($t->viewData('filieres'), 'code'));
        $this->assertEquals(['effectif' => 140, 'libelle' => 'Filières actives, tous stades'], $t->viewData('cheptel'));

        $goliaths = $t->viewData('filieres')[0];
        $this->assertSame('Goliaths', $goliaths['nom']);
        $this->assertSame('/elevage/goliaths', $goliaths['route']);
        $this->assertSame(100, $goliaths['effectif']);
        $this->assertSame(40, $goliaths['matures']);
        $this->assertSame(30, $goliaths['jeunes']);
        $this->assertSame('Goliathaux', $goliaths['libelleJeunes']);
        // 1er jour saisi du mois : 110 - 0 - 0 + 2 morts = 112 exposes ; 2 morts => 2 / 112.
        $this->assertEqualsWithDelta(2 / 112 * 100, $goliaths['mortalite'], 0.0001);
    }

    public function test_activer_un_module_ajoute_sa_filiere_dans_l_ordre_du_poste(): void
    {
        $this->journee('lapins', '2026-11-12', ['effectif' => 30, 'eff_cat3_day' => 12, 'eff_cat2_day' => 18]);
        $this->journee('poulets', '2026-11-12', ['effectif' => 500]);
        ModuleActif::query()->whereIn('module_id', ['cuniculture', 'aviculture_classique'])->update(['is_actif' => true]);

        $t = $this->tableau();

        // Dart : `{goliaths, pintades, …pisciculture, cuniculture, aviculture_classique (poulets), …}`.
        $this->assertSame(['goliaths', 'pintades', 'lapins', 'poulets'], array_column($t->viewData('filieres'), 'code'));
        $this->assertSame(530, $t->viewData('cheptel')['effectif']);
        $lapins = $t->viewData('filieres')[2];
        $this->assertSame('Lapereaux', $lapins['libelleJeunes']);
        $this->assertSame('/elevage/lapins', $lapins['route']);
        $this->assertSame('/elevage/poulets-pondeuses', $t->viewData('filieres')[3]['route']);
    }

    public function test_sans_journee_saisie_effectif_zero_libelle_du_dart_et_mortalite_inconnue(): void
    {
        $t = $this->tableau();

        $this->assertEquals(['effectif' => 0, 'libelle' => "Aucune journée d'élevage encore saisie"], $t->viewData('cheptel'));
        foreach ($t->viewData('filieres') as $f) {
            $this->assertSame(0, $f['effectif']);
            $this->assertNull($f['mortalite']);
        }
    }

    public function test_une_journee_non_enregistree_ne_compte_pas(): void
    {
        $this->journee('goliaths', '2026-11-05', ['effectif' => 90]);
        $this->journee('goliaths', '2026-11-10', ['effectif' => 999, 'is_recorded' => false]);

        $this->assertSame(90, $this->tableau()->viewData('cheptel')['effectif']);
    }

    // -------------------------------------------------------------------------- Couveuse

    public function test_statistiques_de_la_couveuse(): void
    {
        $this->lot('C-A', ['espece' => 'goliath', 'date_incubation' => '2026-11-10', 'oeufs_couves' => 100]);
        // Pintade : 28 jours, chargee le 21/10 => eclosion prevue le 18/11 = aujourd'hui.
        $this->lot('C-B', ['espece' => 'pintade', 'date_incubation' => '2026-10-21', 'oeufs_couves' => 50]);
        $this->lot('C-C', ['statut' => 'Éclosion Effectuée', 'oeufs_couves' => 100, 'poussins_nes' => 80, 'date_incubation' => '2026-09-01']);
        $this->lot('C-D', ['statut' => 'Remplacé', 'oeufs_couves' => 100, 'poussins_nes' => 60, 'date_incubation' => '2026-09-02']);
        $this->lot('C-E', ['oeufs_couves' => 500, 'supprime_le' => now()]);

        $c = $this->tableau()->viewData('couveuse');

        $this->assertSame(2, $c['cycles']);
        $this->assertSame(150, $c['oeufs']);
        $this->assertEqualsWithDelta(70.0, $c['eclosionMoy'], 0.0001);
        $this->assertEqualsWithDelta(30.0, $c['perteMoy'], 0.0001);
        $this->assertSame('C-B', $c['eclosionProchaine']);
    }

    public function test_sans_eclosion_enregistree_les_taux_sont_null_et_pas_zero(): void
    {
        $this->lot('C-A', ['date_incubation' => '2026-11-10']);

        $c = $this->tableau()->viewData('couveuse');

        $this->assertSame(1, $c['cycles']);
        $this->assertNull($c['eclosionMoy']);
        $this->assertNull($c['perteMoy']);
        $this->assertNull($c['eclosionProchaine']);
    }

    public function test_l_eclosion_n_est_imminente_que_dans_les_trois_jours_et_pas_apres_la_date(): void
    {
        // Goliath 21 j : charge le 28/10 => 18/11 (aujourd'hui) ; le 31/10 => 21/11 (J+3) ; le 01/11 => 22/11 (J+4) ; le 27/10 => 17/11 (hier).
        $this->lot('C-HIER', ['date_incubation' => '2026-10-27']);
        $this->assertNull($this->tableau()->viewData('couveuse')['eclosionProchaine']);

        $this->lot('C-J4', ['date_incubation' => '2026-11-01']);
        $this->assertNull($this->tableau()->viewData('couveuse')['eclosionProchaine']);

        $this->lot('C-J3', ['date_incubation' => '2026-10-31']);
        $this->assertSame('C-J3', $this->tableau()->viewData('couveuse')['eclosionProchaine']);
    }

    // ------------------------------------------------------------------------- Alertes

    public function test_toutes_les_alertes_dans_l_ordre_et_avec_les_messages_du_dart(): void
    {
        // Eclosion imminente (goliath charge le 30/10 => 20/11).
        $this->lot('C-P1-2026-001', ['date_incubation' => '2026-10-30']);
        // Soldes restant dus.
        $this->vente('2026-11-10 09:00:00', 1, 10000, 'Avance', ['paye' => 4000]);
        // Prophylaxie : bande du 10/11, J5 = 14/11 (4 jours de retard), J20 = 29/11 (pas encore due).
        $this->bande();
        $this->echeance(5);
        $this->echeance(20);
        // Soin en retard : « Planifié » dont la date est passee ; un soin effectue et un soin du jour n'en sont pas.
        $this->soin(['date_prevue' => '2026-11-10']);
        $this->soin(['date_prevue' => '2026-11-01', 'statut' => 'Effectué']);
        $this->soin(['date_prevue' => '2026-11-18']);
        // Anniversaires dans la fenetre de 7 jours.
        $this->client('Koffi', '1990-11-20');
        $this->client('Awa', '1985-11-18');
        $this->client('Lointain', '1980-12-30');

        $alertes = $this->tableau()->viewData('alertes');

        $this->assertSame([
            ['niveau' => 'critique', 'icone' => 'eclosion', 'texte' => 'Éclosion imminente — Cycle C-P1-2026-001, sous 3 jours.'],
            ['niveau' => 'attention', 'icone' => 'solde', 'texte' => 'Soldes restant dus — 1 vente(s) en avance non soldée(s).'],
            ['niveau' => 'critique', 'icone' => 'soin', 'texte' => '1 échéance(s) de prophylaxie non planifiée(s) sur 1 filière(s), dont 1 en retard.'],
            ['niveau' => 'critique', 'icone' => 'soin', 'texte' => '1 soin(s) vétérinaire(s) en retard.'],
            ['niveau' => 'attention', 'icone' => 'anniversaire', 'texte' => "Anniversaire client — Awa (aujourd'hui), Koffi (dans 2 j)."],
        ], $alertes);
    }

    public function test_une_echeance_deja_planifiee_ou_une_bande_cloturee_ne_declenche_pas_de_rappel(): void
    {
        $bande = $this->bande();
        $echeance = $this->echeance(5);
        $this->soin(['bande_id' => $bande->id, 'echeance_prophylaxie_id' => $echeance->id, 'date_prevue' => '2026-11-14', 'statut' => 'Effectué']);
        $cloturee = $this->bande('pintades', '2026-10-01', 'B-2');
        $cloturee->forceFill(['date_cloture' => '2026-10-20'])->save();
        $this->echeance(3, 'pintades');

        $this->assertSame([], $this->tableau()->viewData('alertes'));
    }

    public function test_sans_rien_a_signaler_la_liste_est_vide_et_pas_null(): void
    {
        $this->assertSame([], $this->tableau()->viewData('alertes'));
    }

    // ------------------------------------------------------------------------ Activites

    public function test_fil_d_activite_du_jour_dix_au_plus_du_plus_recent_au_plus_ancien(): void
    {
        $gerante = $this->utilisateurAvecRole('admin', 'gerante');
        $log = function (string $action, string $quand, ?string $auteur = null, ?string $identifiant = null): void {
            (new AuditLog)->forceFill([
                'action' => $action, 'utilisateur_id' => $auteur, 'identifiant' => $identifiant, 'detail' => null, 'ip' => null,
                'created_at' => $this->loc($quand),
            ])->save();
        };
        $log('web.login', '2026-11-17 23:59:00', $gerante->id);     // hier : exclu
        $log('web.login', '2026-11-18 07:05:00', $gerante->id);
        $log('login.failed', '2026-11-18 08:30:00', null, 'inconnu');
        for ($i = 0; $i < 11; $i++) {
            $log('sync.push', sprintf('2026-11-18 09:%02d:00', $i), null);
        }

        $a = Livewire::actingAs($gerante)->test(TableauDeBord::class)->viewData('activites');

        $this->assertCount(10, $a);
        $this->assertSame(['heure' => '09:10', 'texte' => "Synchronisation : envoi d'un poste", 'auteur' => null], $a[0]);
        $this->assertSame('09:01', $a[9]['heure']);
    }

    public function test_activites_auteur_par_nom_ou_identifiant_et_reservees_a_la_gestion_des_comptes(): void
    {
        $gerante = $this->utilisateurAvecRole('admin', 'gerante');
        (new AuditLog)->forceFill(['action' => 'web.login', 'utilisateur_id' => $gerante->id, 'identifiant' => 'gerante', 'created_at' => $this->loc('2026-11-18 07:05:00')])->save();
        (new AuditLog)->forceFill(['action' => 'login.failed', 'utilisateur_id' => null, 'identifiant' => 'inconnu', 'created_at' => $this->loc('2026-11-18 08:30:00')])->save();

        $a = Livewire::actingAs($gerante)->test(TableauDeBord::class)->viewData('activites');

        $this->assertSame([
            ['heure' => '08:30', 'texte' => 'Connexion refusée (identifiants)', 'auteur' => 'inconnu'],
            ['heure' => '07:05', 'texte' => 'Connexion web', 'auteur' => 'Gerante'],
        ], $a);
        $this->assertNull($this->tableau('comptable')->viewData('activites'));
        $this->assertNull($this->tableau('caissier')->viewData('activites'));
    }

    // --------------------------------------------------------------------- Transactions

    public function test_les_trois_dernieres_transactions_de_chaque_onglet(): void
    {
        $this->vente('2026-11-01 09:00:00', 1, 1000);
        $this->vente('2026-11-02 09:00:00', 1, 2000);
        $this->vente('2026-11-03 09:00:00', 1, 3000);
        $this->vente('2026-11-04 09:00:00', 1, 8000, 'Avance', ['paye' => 2500, 'client' => 'Awa']);

        $this->achat('2026-11-01 09:00:00', 100);
        $this->achat('2026-11-02 09:00:00', 200);
        $this->achat('2026-11-03 09:00:00', 300);
        $this->achat('2026-11-04 09:00:00', 400, 'Commandé');

        $this->poserPiece('DEP-P1-2026-0001', 2026, 11, 1, 'CA', [['618', 1000, 0, null], ['571', 0, 1000, null]]);
        $this->poserPiece('DEP-P1-2026-0002', 2026, 11, 2, 'CA', [['625', 2000, 0, null], ['401', 0, 2000, null]]);
        $this->poserPiece('DEP-P1-2026-0003', 2026, 11, 3, 'CA', [['618', 3000, 0, null], ['571', 0, 3000, null]]);
        $this->poserPiece('DEP-P1-2026-0004', 2026, 11, 4, 'CA', [['618', 4000, 0, null], ['571', 0, 4000, null]]);
        // Une ecriture d'achat (602, `achat_ref`) n'est pas une depense saisie.
        $this->poserPiece('ACH-P1-2026-0001', 2026, 11, 5, 'AC', [['602', 9999, 0, null], ['401', 0, 9999, null]], ['achat_ref' => 'ACH-P1-2026-0001']);

        $tr = $this->tableau()->viewData('transactions');

        $this->assertCount(3, $tr['ventes']);
        // « Avance » : on montre l'encaisse (Dart : `v.status == 'Avance' ? v.paye : v.total`).
        $this->assertStringStartsWith('V-P1-2026-D', $tr['ventes'][0]['ref']);
        $this->assertSame('Awa', $tr['ventes'][0]['libelle']);
        $this->assertSame(2500.0, $tr['ventes'][0]['montant']);
        $this->assertSame('Avance', $tr['ventes'][0]['statut']);
        $this->assertSame([3000.0, 2000.0], [$tr['ventes'][1]['montant'], $tr['ventes'][2]['montant']]);
        $this->assertSame('Payée', $tr['ventes'][1]['statut']);

        $this->assertSame([400.0, 300.0, 200.0], array_column($tr['achats'], 'montant'));
        $this->assertSame('Commandé', $tr['achats'][0]['statut']);
        $this->assertStringStartsWith('ACH-P1-2026-D', $tr['achats'][0]['ref']);
        $this->assertSame('Provenderie du Nord', $tr['achats'][0]['libelle']);

        $this->assertSame([4000.0, 3000.0, 2000.0], array_column($tr['depenses'], 'montant'));
        $this->assertSame('DEP-P1-2026-0004', $tr['depenses'][0]['ref']);
        $this->assertSame('Libelle DEP-P1-2026-0004', $tr['depenses'][0]['libelle']);
        $this->assertSame('Payée', $tr['depenses'][0]['statut']);
        $this->assertSame('En attente', $tr['depenses'][2]['statut']);
    }

    public function test_une_depense_annulee_par_contrepassation_n_est_plus_une_transaction(): void
    {
        $origine = $this->poserPiece('DEP-P1-2026-0001', 2026, 11, 1, 'CA', [['618', 1000, 0, null], ['571', 0, 1000, null]]);
        $this->poserPiece('ANN-P1-2026-0001', 2026, 11, 2, 'CA', [['571', 1000, 0, null], ['618', 0, 1000, null]], ['contrepasse_de' => $origine->id]);
        $this->poserPiece('DEP-P1-2026-0002', 2026, 11, 3, 'CA', [['618', 2000, 0, null], ['571', 0, 2000, null]]);

        $this->assertSame([2000.0], array_column($this->tableau()->viewData('transactions')['depenses'], 'montant'));
    }

    public function test_sans_aucune_donnee_les_listes_sont_vides_et_les_totaux_nuls(): void
    {
        $t = $this->tableau();

        $this->assertSame(['ventes' => [], 'achats' => [], 'depenses' => []], $t->viewData('transactions'));
        $this->assertEquals(['total' => 0.0, 'especes' => 0.0, 'mobile' => 0.0], $t->viewData('tresorerie'));
        $this->assertSame([], $t->viewData('activites'));
        $this->assertSame(6, count($t->viewData('jours')));
    }

    public function test_les_cles_existantes_sont_conservees(): void
    {
        $t = $this->tableau();

        foreach (['ca', 'meilleures', 'clients', 'encours', 'encoursNombre', 'semaine', 'mois', 'recentes', 'dettes', 'dettesNombre',
            'voirVentes', 'voirAchats', 'voirComptabilite', 'voirStocks', 'voirElevage'] as $cle) {
            $t->assertViewHas($cle);
        }
    }
}
