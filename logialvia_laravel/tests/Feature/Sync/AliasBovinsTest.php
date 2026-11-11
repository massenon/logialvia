<?php

namespace Tests\Feature\Sync;

use App\Models\Bande;
use App\Models\BaremeRation;
use App\Models\FicheJournee;
use App\Models\FicheVentesJour;
use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\ProduitVendable;
use App\Models\SoinCalendrier;
use App\Support\FilieresElevage;
use App\Support\UuidDeterministe;
use App\Sync\AliasHerites;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * DV-22 : la filiere Bovins est remplacee par Ovins. Un poste ANCIEN (schema v50) peut encore envoyer
 * `bovins` : le serveur l'accepte comme ALIAS herite et le normalise en `ovins` a l'entree ; il n'ecrit
 * jamais `bovins`, et la route `/elevage/bovins` n'existe plus.
 */
class AliasBovinsTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
        $this->travel(5)->seconds();
    }

    private function pousser(array $poste, string $table, array $lignes)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => ParametresEntreprise::courant()->fresh()->marque_remise_a_zero,
            'tables' => [$table => $lignes],
        ]);
    }

    private function bilan(array $poste, string $table, array $lignes): array
    {
        return $this->pousser($poste, $table, $lignes)->assertOk()->json($table);
    }

    private function demander(array $poste, string $type, array $donnees)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $poste['device'],
            'demandes' => [[
                'id' => (string) Str::uuid(), 'type' => $type,
                'saisi_le' => now()->format('Y-m-d\TH:i:s.u\Z'), 'donnees' => $donnees,
            ]],
        ]);
    }

    public function test_la_filiere_ovins_existe_et_bovins_n_existe_plus(): void
    {
        $this->assertContains('ovins', FilieresElevage::identifiants());
        $this->assertNotContains('bovins', FilieresElevage::identifiants());
        $this->assertTrue(FilieresElevage::existe('ovins'));
        $this->assertFalse(FilieresElevage::existe('bovins'));
        $this->assertSame('Ovins', FilieresElevage::libelle('ovins'));
        $this->assertSame('/elevage/ovins', FilieresElevage::configuration('ovins')['route']);
        $this->assertSame(['Agneau', 'Embouche', 'Reproducteur'], array_column(FilieresElevage::configuration('ovins')['categories'], 0));
        $this->assertArrayHasKey('ovins', config('logialvia.modules'));
        $this->assertArrayNotHasKey('bovins', config('logialvia.modules'));
        $this->assertArrayHasKey('/elevage/ovins', config('logialvia.routes'));
        $this->assertArrayNotHasKey('/elevage/bovins', config('logialvia.routes'));
    }

    public function test_la_route_elevage_bovins_n_existe_plus(): void
    {
        $admin = $this->compteAvecRole('admin', 'gerante');
        ModuleActif::query()->where('module_id', 'ovins')->update(['is_actif' => true]);

        $this->actingAs($admin)->get('/elevage/ovins')->assertOk();
        $this->actingAs($admin)->get('/elevage/bovins')->assertNotFound();
    }

    public function test_l_alias_normalise_l_espece_et_rien_d_autre(): void
    {
        $this->assertSame('ovins', AliasHerites::espece('bovins'));
        $this->assertSame('ovins', FilieresElevage::normaliser('bovins'));
        $this->assertSame('goliaths', AliasHerites::espece('goliaths'));
        $this->assertNull(AliasHerites::espece(null));
        $this->assertSame(['x'], AliasHerites::espece(['x']));
    }

    public function test_une_fiche_envoyee_sous_bovins_est_acceptee_et_rangee_sous_ovins(): void
    {
        $poste = $this->poste('animalier', 'eleveur');
        // Ce que le poste ancien envoie : filiere `bovins`, UUID calcule AVEC `bovins`.
        $ligne = $this->ligneFicheJournee('bovins', '2026-11-05');

        $bilan = $this->bilan($poste, 'fiche_journee', [$ligne]);

        // L'accuse reprend l'identifiant ENVOYE.
        $this->assertSame([$ligne['id']], $bilan['accepted']);
        $this->assertSame([], $bilan['rejected']);
        $this->assertSame(0, FicheJournee::query()->where('espece', 'bovins')->count());
        $fiche = FicheJournee::query()->sole();
        $this->assertSame('ovins', $fiche->espece);
        $this->assertSame(UuidDeterministe::ficheJournee('ovins', '2026-11-05'), $fiche->id);
    }

    public function test_un_identifiant_qui_n_est_pas_celui_de_sa_cle_reste_refuse(): void
    {
        $poste = $this->poste('animalier', 'eleveur');
        $ligne = $this->ligneFicheJournee('bovins', '2026-11-05', ['id' => (string) Str::uuid()]);

        $bilan = $this->bilan($poste, 'fiche_journee', [$ligne]);

        $this->assertSame([], $bilan['accepted']);
        $this->assertCount(1, $bilan['rejected']);
        $this->assertSame(0, FicheJournee::query()->count());
    }

    public function test_un_compteur_de_ventes_sous_bovins_est_normalise_avec_l_uuid_du_poste(): void
    {
        $poste = $this->poste('animalier', 'eleveur');
        $ligne = $this->ligneVentesJour($poste['device'], 'bovins', '2026-11-05', ['qte' => 3]);

        $this->assertSame([$ligne['id']], $this->bilan($poste, 'fiche_ventes_jour', [$ligne])['accepted']);

        $compteur = FicheVentesJour::query()->sole();
        $this->assertSame('ovins', $compteur->espece);
        $this->assertSame(UuidDeterministe::ventesJour('ovins', '2026-11-05', $poste['device']), $compteur->id);
        $this->assertSame(3, $compteur->qte);
    }

    public function test_une_bande_et_un_soin_sous_bovins_sont_ranges_sous_ovins(): void
    {
        $poste = $this->poste('animalier', 'eleveur');
        $bande = $this->ligneBande('PARC1', ['espece' => 'bovins']);
        $this->assertSame([$bande['id']], $this->bilan($poste, 'bandes', [$bande])['accepted']);
        $this->assertSame('ovins', Bande::query()->sole()->espece);

        $soin = [
            'id' => (string) Str::uuid(), 'espece' => 'bovins', 'date_prevue' => '2026-11-05',
            'type_soin' => 'Vaccination', 'statut' => 'Planifié', 'observations' => null,
            'produit' => 'Vaccin PPR', 'dose' => '1 dose', 'remanence_jours' => 0, 'veterinaire' => null,
            'symptomes' => null, 'cout_fcfa' => 0, 'echeance_prophylaxie_id' => null,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ];
        $this->assertSame([$soin['id']], $this->bilan($poste, 'soins_calendrier', [$soin])['accepted']);
        $this->assertSame('ovins', SoinCalendrier::query()->sole()->espece);
    }

    public function test_une_demande_de_module_bovins_active_le_module_ovins(): void
    {
        $poste = $this->poste('admin', 'gerante');

        $this->demander($poste, 'module_actif', ['module_id' => 'bovins', 'is_actif' => true])
            ->assertOk()->assertJsonCount(1, 'accepted');

        $this->assertTrue(ModuleActif::query()->where('module_id', 'ovins')->firstOrFail()->is_actif);
        $this->assertSame(0, ModuleActif::query()->where('module_id', 'bovins')->count());
    }

    public function test_un_bareme_bovins_devient_un_bareme_ovins_stade_jeune_compris(): void
    {
        $poste = $this->poste('admin', 'gerante');
        $ancienId = FilieresElevage::idBareme('bovins', 'Veau');

        $this->demander($poste, 'bareme_ration', [
            'id' => $ancienId, 'espece' => 'bovins', 'stade' => 'Veau',
            'ration_grammes_par_jour' => 1500, 'confirme' => false,
        ])->assertOk()->assertJsonCount(1, 'accepted');

        $bareme = BaremeRation::query()->sole();
        $this->assertSame('ovins', $bareme->espece);
        $this->assertSame('Agneau', $bareme->stade);
        $this->assertSame(FilieresElevage::idBareme('ovins', 'Agneau'), $bareme->id);
    }

    public function test_un_produit_de_la_categorie_elevage_bovin_passe_en_elevage_ovin(): void
    {
        $poste = $this->poste('admin', 'gerante');

        $this->demander($poste, 'produit_vendable', [
            'id' => (string) Str::uuid(), 'name' => 'Animal d\'embouche', 'cat' => 'Élevage bovin',
            'price' => 50000, 'unit' => 'u', 'icon' => 'grass', 'espece' => 'bovins',
        ])->assertOk()->assertJsonCount(1, 'accepted');

        $produit = ProduitVendable::query()->sole();
        $this->assertSame('Élevage ovin', $produit->cat);
        $this->assertSame('ovins', $produit->espece);
    }
}
