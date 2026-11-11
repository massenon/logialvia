<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Models\DemandeReferentiel;
use App\Models\ProduitVendable;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Catalogue & Seuils » : referentiel, memes regles que pour un poste, jamais de stock. */
class CatalogueWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
    }

    private function utilisateur(string $role, string $username = 'u'): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    private function produit(array $surcharge = []): ProduitVendable
    {
        $produit = (new ProduitVendable)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'sku' => 'PRD-001', 'name' => 'Goliath mature', 'cat' => 'Avicole',
            'price' => 6000, 'price_max' => 8500, 'unit' => 'sujet(s)', 'icon' => 'pets',
            'cout_revient' => 4000, 'groupe_taxe' => 'A', 'threshold' => 5, 'saisi_le' => now()->subDay(),
        ], $surcharge));
        $produit->save();

        return $produit;
    }

    // ------------------------------------------------------------------- Acces

    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/catalogue')->assertRedirect(route('login'));
    }

    public function test_seuls_ceux_qui_voient_les_stocks_ouvrent_la_page(): void
    {
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get('/catalogue')->assertForbidden();
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/catalogue')->assertForbidden();
        $this->actingAs($this->utilisateur('admin', 'gerante'))->get('/catalogue')->assertOk()->assertSee('Catalogue &amp; Seuils', false);
    }

    public function test_la_page_est_bien_l_ecran_converti_et_non_la_page_bientot(): void
    {
        $this->actingAs($this->utilisateur('admin', 'gerante'));

        $this->get('/catalogue')->assertDontSee('arrive bientôt');
    }

    // ----------------------------------------------------------------- Lecture

    public function test_la_liste_et_les_compteurs_viennent_de_la_base_sans_aucun_stock(): void
    {
        $this->produit();
        $this->produit(['sku' => 'PRD-002', 'name' => 'Lapin vif', 'cat' => 'Cuniculture']);
        $this->produit(['sku' => 'PRD-003', 'name' => 'Ancien', 'archive_le' => now()]);

        Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(Catalogue::class)
            ->assertSee('Goliath mature')->assertSee('Lapin vif')
            ->assertDontSee('Ancien')
            ->assertSeeHtml('data-kpi="produits">2<')
            ->assertSeeHtml('data-kpi="categories">2<')
            ->assertDontSee('Valeur')
            ->assertSee('propre à chaque poste');
    }

    public function test_la_recherche_et_le_filtre_de_categorie(): void
    {
        $this->produit();
        $this->produit(['sku' => 'PRD-002', 'name' => 'Lapin vif', 'cat' => 'Cuniculture']);

        Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(Catalogue::class)
            ->set('recherche', 'lapin')->assertSee('Lapin vif')->assertDontSee('Goliath')
            ->set('recherche', 'PRD-001')->assertSee('Goliath')->assertDontSee('Lapin vif')
            ->set('recherche', '')->set('categorie', 'Cuniculture')->assertSee('Lapin vif')->assertDontSee('Goliath');
    }

    // ----------------------------------------------------------------- Ecriture

    public function test_un_produit_ajoute_recoit_le_sku_suivant_et_laisse_une_demande(): void
    {
        $this->produit();

        Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(Catalogue::class)
            ->call('nouveau')
            ->set('nom', 'Poulet de chair')->set('cat', 'Avicole')->set('prix', '3 200')->set('prixMax', '')
            ->set('unite', 'sujet(s)')->set('coutRevient', '2000,5')->set('seuil', '10')
            ->call('enregistrer')
            ->assertSet('erreur', null)->assertSet('formulaire', false)
            ->assertSee('Produit « Poulet de chair » ajouté.');

        $p = ProduitVendable::query()->where('name', 'Poulet de chair')->firstOrFail();
        $this->assertSame('PRD-002', $p->sku);
        $this->assertSame(3200.0, $p->price);
        $this->assertSame(2000.5, $p->cout_revient);
        $this->assertSame(10, $p->threshold);
        $this->assertNull($p->archive_le);
        $this->assertNotNull($p->saisi_le);
        $this->assertSame(Catalogue::POSTE_WEB, DemandeReferentiel::query()->where('cle', $p->id)->value('device_id'));
    }

    public function test_les_regles_du_serveur_s_appliquent_au_web_comme_au_poste(): void
    {
        $composant = Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(Catalogue::class)->call('nouveau');

        $composant->set('nom', 'Sans tarif')->call('enregistrer')
            ->assertSet('erreur', 'Le tarif du produit est obligatoire.')->assertSet('formulaire', true);

        $composant->set('nom', 'A perte')->set('prix', '1000')->set('coutRevient', '1500')->call('enregistrer')
            ->assertSet('erreur', 'Le coût de revient dépasse le tarif indicatif : chaque vente serait à perte.');

        $composant->set('nom', 'Fourchette')->set('prix', '1000')->set('coutRevient', '')->set('prixMax', '900')->call('enregistrer')
            ->assertSet('erreur', 'Le prix haut de fourchette ne peut être inférieur au prix bas.');

        $this->assertSame(0, ProduitVendable::query()->count(), 'rien n\'est écrit sur un refus');
    }

    public function test_modifier_garde_le_sku_et_l_icone(): void
    {
        $p = $this->produit();

        Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(Catalogue::class)
            ->call('modifier', $p->id)
            ->assertSet('nom', 'Goliath mature')->assertSet('prix', '6000')
            ->set('prix', '6500')->call('enregistrer')->assertSet('erreur', null);

        $p->refresh();
        $this->assertSame(6500.0, $p->price);
        $this->assertSame('PRD-001', $p->sku);
        $this->assertSame('pets', $p->icon);
    }

    public function test_une_modification_du_web_descend_vers_les_postes(): void
    {
        $p = $this->produit(['updated_at' => now()->subDay(), 'created_at' => now()->subDay()]);
        $avant = $p->updated_at;
        $this->travel(5)->seconds();

        Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(Catalogue::class)
            ->call('modifier', $p->id)->set('prix', '7000')->call('enregistrer');

        $p->refresh();
        $this->assertTrue($p->updated_at->greaterThan($avant), 'le curseur de tirage avance : les postes la recevront');
        $this->assertTrue($p->saisi_le->greaterThan(now()->subMinute()));
    }

    // -------------------------------------------------------------- Suppression

    public function test_la_suppression_passe_par_une_modale_et_n_efface_jamais(): void
    {
        $p = $this->produit();
        $composant = Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(Catalogue::class);

        $composant->call('demanderSuppression', $p->id)->assertSee('Supprimer ce produit ?');
        $this->assertNull($p->fresh()->archive_le, 'rien tant que la modale n\'est pas confirmée');

        $composant->call('annuler')->assertDontSee('Supprimer ce produit ?');
        $this->assertNull($p->fresh()->archive_le);

        $composant->call('demanderSuppression', $p->id)->call('confirmerSuppression')
            ->assertSee('supprimé du catalogue')->assertDontSeeHtml('data-produit="PRD-001"');
        $this->assertNotNull($p->fresh()->archive_le, 'pierre tombale, jamais d\'effacement');
        $this->assertSame(1, ProduitVendable::query()->count());
    }

    // -------------------------------------------------------------------- Droits

    public function test_en_lecture_seule_aucun_bouton_et_les_methodes_sont_interdites(): void
    {
        $p = $this->produit();
        $lecteur = $this->utilisateur('comptable', 'compta');
        $lecteur->givePermissionTo('view-stocks');

        Livewire::actingAs($lecteur)->test(Catalogue::class)
            ->assertSee('Goliath mature')
            ->assertDontSee('Ajouter un Produit')->assertDontSee('Modifier')->assertDontSee('Supprimer');

        // Un 403 ferme le composant : chaque appel interdit repart d'un composant neuf.
        $appel = fn (string $methode, array $args = []) => Livewire::actingAs($lecteur)->test(Catalogue::class)
            ->call($methode, ...$args)->assertForbidden();
        $appel('nouveau');
        $appel('modifier', [$p->id]);
        $appel('demanderSuppression', [$p->id]);
        $appel('confirmerSuppression');
        $this->assertNull($p->fresh()->archive_le);
    }

    public function test_les_ecrans_convertis_ont_tous_une_vraie_route(): void
    {
        $this->assertContains('/catalogue', \App\Support\Ecrans::declarees());
        foreach (\App\Support\Ecrans::declarees() as $route) {
            $this->assertNotNull(
                collect(app('router')->getRoutes()->getRoutes())->first(fn ($r) => '/'.$r->uri() === $route && ! str_starts_with((string) $r->getName(), 'a-venir.')),
                "Écran déclaré converti sans route propre : $route",
            );
        }
    }

    public function test_la_filiere_se_choisit_et_l_onglet_seuils_modifie_le_seuil(): void
    {
        $c = Livewire::actingAs($this->utilisateur('admin', 'gerante'))->test(Catalogue::class)
            ->assertSee("Seuils d'Alerte")
            ->call('nouveau')->assertSeeHtml('data-champ="espece"')->assertSee('Ovins')->set('nom', 'Agneau 6 mois')->set('cat', 'Élevage ovin')->set('prix', '40000')->set('unite', 'sujet')->set('espece', 'ovins')
            ->call('enregistrer')->assertSet('erreur', null)->assertSee('Sur le poste')->assertSee('Agneau 6 mois');

        $produit = \App\Models\ProduitVendable::query()->where('name', 'Agneau 6 mois')->firstOrFail();
        $this->assertSame('ovins', $produit->espece);

        $c->call('majSeuil', $produit->id, '7')->assertSet('erreur', null);
        $this->assertSame(7, (int) $produit->fresh()->threshold);
        $c->call('majSeuil', $produit->id, '-3')->assertNotSet('erreur', null);
        $this->assertSame(7, (int) $produit->fresh()->threshold);
    }
}
