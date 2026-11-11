<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\GestionStocks;
use App\Models\DemandeReferentiel;
use App\Models\Intrant;
use App\Models\MouvementIntrant;
use App\Models\Poste;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ecran web « Gestion des Stocks » : intrants (referentiel, memes regles que pour un poste)
 * et journal partage en lecture. Jamais de stock, de PMP ni de valeur : propres a chaque poste.
 */
class GestionStocksWebTest extends TestCase
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

    private function admin(): User
    {
        return $this->utilisateur('admin', 'gerante');
    }

    /** Un compte qui ne fait que LIRE les stocks. */
    private function lecteur(): User
    {
        $u = $this->utilisateur('comptable', 'compta');
        $u->givePermissionTo('view-stocks');

        return $u;
    }

    private function intrant(array $surcharge = []): Intrant
    {
        $i = (new Intrant)->forceFill(array_merge([
            'code' => 'INT-001', 'name' => 'Maïs concassé', 'cat' => 'Intrants Provende',
            'unit' => 'kg', 'threshold' => 50, 'saisi_le' => now()->subDay(),
        ], $surcharge));
        $i->save();

        return $i;
    }

    private function mouvement(array $surcharge = []): MouvementIntrant
    {
        $m = (new MouvementIntrant)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(),
            'horodatage' => now()->subHour(), 'intrant_code' => 'INT-001', 'article' => 'Maïs concassé',
            'type' => 'Entrée', 'motif' => 'Réception de commande', 'quantite' => 120,
            'reference' => 'CMD-001', 'serveur_modifie_le' => now(),
        ], $surcharge));
        $m->save();

        return $m;
    }

    // ------------------------------------------------------------------- Acces

    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/stocks')->assertRedirect(route('login'));
    }

    public function test_seuls_ceux_qui_voient_les_stocks_ouvrent_la_page(): void
    {
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get('/stocks')->assertForbidden();
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/stocks')->assertForbidden();
        $this->actingAs($this->admin())->get('/stocks')->assertOk()->assertSee('Gestion des Stocks');
    }

    public function test_la_page_est_bien_l_ecran_converti_et_non_la_page_bientot(): void
    {
        $this->actingAs($this->admin())->get('/stocks')->assertDontSee('arrive bientôt');
        $this->assertContains('/stocks', \App\Support\Ecrans::declarees());
    }

    // ----------------------------------------------------------------- Lecture

    public function test_les_kpi_et_les_listes_viennent_de_la_base_sans_aucun_stock(): void
    {
        $this->intrant();
        $this->intrant(['code' => 'INT-002', 'name' => 'Vaccin Newcastle', 'cat' => 'Vétérinaire', 'unit' => 'dose', 'threshold' => 10]);
        $this->intrant(['code' => 'INT-003', 'name' => 'Sans seuil', 'threshold' => 0]);
        $this->mouvement();
        $this->mouvement(['horodatage' => now()->subDays(3), 'motif' => 'Ajustement ancien']);
        $this->mouvement(['horodatage' => now()->subDays(30), 'motif' => 'Très ancien']);

        Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->assertSeeHtml('data-kpi="articles">3<')
            ->assertSeeHtml('data-kpi="mouvements">2<')
            ->assertSee('Articles Suivis')->assertSee('Mouvements (7j)')
            ->assertSee('Maïs concassé')->assertSee('INT-002')->assertSee('Vétérinaire')->assertSee('Seuil Alerte')
            ->assertSee('Journal des Mouvements')->assertSee('Réception de commande')->assertSee('CMD-001')
            ->assertSee('+120')
            // Décision du client : rien de ce qui vit sur le poste.
            ->assertSeeHtml('data-carte-poste="Valeur Totale Stock"')->assertSeeHtml('data-carte-poste="Intrants Sous Seuil"')->assertDontSee('Prix Unitaire')
            ->assertDontSeeHtml('>Stock</th>')->assertDontSeeHtml('>Valeur</th>')->assertDontSeeHtml('>Statut</th>')
            ->assertDontSee('Critique')
            ->assertSee('propres à chaque poste');
    }

    public function test_les_ecrans_vides_disent_quoi_faire(): void
    {
        Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->assertSee('Aucun intrant ne correspond.')
            ->assertSee('Aucun mouvement enregistré. Les réceptions de commandes et les ajustements d\'inventaire apparaissent ici automatiquement.', false)
            ->assertSeeHtml('data-kpi="articles">0<')->assertSeeHtml('data-kpi="mouvements">0<');
    }

    public function test_la_recherche_et_le_filtre_de_categorie(): void
    {
        $this->intrant();
        $this->intrant(['code' => 'INT-002', 'name' => 'Vaccin Newcastle', 'cat' => 'Vétérinaire']);

        Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->set('recherche', 'vaccin')->assertSee('Vaccin Newcastle')->assertDontSeeHtml('data-intrant="INT-001"')
            ->set('recherche', 'INT-001')->assertSee('Maïs concassé')->assertDontSeeHtml('data-intrant="INT-002"')
            ->set('recherche', '')->set('categorie', 'Vétérinaire')->assertSeeHtml('data-intrant="INT-002"')->assertDontSeeHtml('data-intrant="INT-001"')
            ->set('categorie', '')->assertSeeHtml('data-intrant="INT-001"')->assertSeeHtml('data-intrant="INT-002"');
    }

    public function test_le_journal_affiche_le_poste_d_origine_et_les_quantites_negatives(): void
    {
        $this->intrant();
        $p2 = Poste::query()->create(['device_id' => (string) Str::uuid(), 'code' => 'P2']);
        $inconnu = (string) Str::uuid();
        $this->mouvement(['device_id' => $p2->device_id, 'motif' => 'Du poste deux', 'type' => 'Sortie', 'quantite' => -15.5]);
        $this->mouvement(['device_id' => Catalogue::POSTE_WEB, 'motif' => 'Du web']);
        $this->mouvement(['device_id' => $inconnu, 'motif' => 'Poste disparu']);

        $composant = Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->assertSee('Du poste deux')->assertSee('-15,5')
            ->assertSee('Poste '.substr($inconnu, 0, 8))
            ->assertSeeHtml('data-poste>P2<')->assertSeeHtml('data-poste>Web<');

        // Rouge pour une sortie, vert pour une entrée : dans le tableau ET dans la carte mobile.
        $this->assertSame(2, substr_count($composant->html(), 'text-error-deep">-15,5<'));
        $this->assertSame(4, substr_count($composant->html(), 'text-success-deep">+120<'));
    }

    public function test_le_journal_est_trie_du_plus_recent_au_plus_ancien_et_limite_a_cent(): void
    {
        $this->intrant();
        $ancien = $this->mouvement(['horodatage' => now()->subDays(2), 'motif' => 'Le plus ancien']);
        for ($n = 0; $n < GestionStocks::LIMITE_JOURNAL; $n++) {
            $this->mouvement(['horodatage' => now()->subMinutes($n + 1), 'motif' => 'Récent '.$n]);
        }

        $html = Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->assertDontSeeHtml('data-mouvement="'.$ancien->id.'"')
            ->assertSee('Récent 0')->assertSee('Récent 99')
            ->html();

        $this->assertLessThan(strpos($html, 'Récent 1<'), strpos($html, 'Récent 0<'), 'le plus récent d\'abord');
        $this->assertSame(GestionStocks::LIMITE_JOURNAL, substr_count($html, 'data-mouvement='));
    }

    public function test_le_journal_ne_change_aucun_stock_et_ne_se_modifie_pas(): void
    {
        $this->intrant();
        $m = $this->mouvement();
        $avant = $m->fresh()->toArray();

        $composant = Livewire::actingAs($this->admin())->test(GestionStocks::class);
        $this->assertSame($avant, $m->fresh()->toArray());
        $this->assertFalse(\Illuminate\Support\Facades\Schema::hasColumn('intrants', 'stock'));
        $this->assertFalse(method_exists($composant->instance(), 'supprimer'));
        $this->assertFalse(method_exists($composant->instance(), 'confirmerSuppression'));
        $composant->assertDontSee('Supprimer')->assertSeeHtml('data-action-poste="fabrication"')->assertDontSeeHtml('wire:click="fabriquer');
    }

    // ----------------------------------------------------------------- Ecriture

    public function test_un_intrant_ajoute_recoit_le_code_suivant_et_laisse_une_demande(): void
    {
        $this->intrant();
        $this->intrant(['code' => 'INT-007', 'name' => 'Sel']);

        Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->call('nouveau')->assertSet('unite', 'kg')->assertSet('seuil', '0')->assertSee('-- Sélectionner --')
            ->set('nom', '  Tourteau de soja ')->set('cat', 'Intrants Provende')->set('unite', ' sac ')->set('seuil', '25')
            ->call('enregistrer')
            ->assertSet('erreur', null)->assertSet('formulaire', false)
            ->assertSee('Intrant « Tourteau de soja » ajouté.')
            ->assertSeeHtml('data-intrant="INT-008"');

        $i = Intrant::query()->findOrFail('INT-008');
        $this->assertSame('Tourteau de soja', $i->name);
        $this->assertSame('Intrants Provende', $i->cat);
        $this->assertSame('sac', $i->unit);
        $this->assertSame(25, $i->threshold);
        $this->assertNotNull($i->saisi_le);

        $demande = DemandeReferentiel::query()->where('cle', 'INT-008')->firstOrFail();
        $this->assertSame(Catalogue::POSTE_WEB, $demande->device_id);
        $this->assertSame('intrant', $demande->type);
        $this->assertSame('acceptee', $demande->statut);
    }

    public function test_une_unite_vide_devient_u_et_un_seuil_vide_zero_comme_au_poste(): void
    {
        Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->call('nouveau')->set('nom', 'Sachet')->set('cat', 'Marchandises')->set('unite', '  ')->set('seuil', '')
            ->call('enregistrer')->assertSet('erreur', null);

        $i = Intrant::query()->where('name', 'Sachet')->firstOrFail();
        $this->assertSame('INT-001', $i->code);
        $this->assertSame('u', $i->unit);
        $this->assertSame(0, $i->threshold);
    }

    public function test_les_regles_du_serveur_s_appliquent_au_web_comme_au_poste(): void
    {
        $composant = Livewire::actingAs($this->admin())->test(GestionStocks::class)->call('nouveau');

        $composant->set('nom', '   ')->set('cat', 'Marchandises')->call('enregistrer')
            ->assertSet('erreur', "La désignation de l'intrant est obligatoire.")->assertSet('formulaire', true);

        $composant->set('nom', 'Sans catégorie')->set('cat', '')->call('enregistrer')
            ->assertSet('erreur', "La catégorie de l'intrant est obligatoire.");

        $composant->set('cat', 'Marchandises')->set('seuil', '-3')->call('enregistrer')
            ->assertSet('erreur', 'Le seuil d\'alerte ne peut être négatif.');

        $composant->set('seuil', '2,5')->call('enregistrer')
            ->assertSet('erreur', 'Le seuil d\'alerte doit être un nombre entier.');

        $composant->set('seuil', 'abc')->call('enregistrer')
            ->assertSet('erreur', 'Le seuil d\'alerte doit être un nombre entier.');

        $this->assertSame(0, Intrant::query()->count(), 'rien n\'est écrit sur un refus');
    }

    public function test_une_erreur_est_effacee_a_l_ouverture_suivante_et_annuler_ferme_sans_ecrire(): void
    {
        $this->intrant();

        Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->call('nouveau')->call('enregistrer')->assertSet('erreur', "La désignation de l'intrant est obligatoire.")
            ->call('annuler')->assertSet('formulaire', false)->assertSet('erreur', null)
            ->call('nouveau')->assertSet('erreur', null)->assertSet('nom', '')->assertSet('code', null);

        $this->assertSame(1, Intrant::query()->count());
    }

    public function test_ajouter_apres_avoir_modifie_cree_un_nouvel_intrant_au_lieu_d_ecraser(): void
    {
        $this->intrant();

        Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->call('modifier', 'INT-001')
            ->call('nouveau')->assertSet('code', null)->assertSet('nom', '')->assertSet('cat', '')
            ->set('nom', 'Nouveau')->set('cat', 'Marchandises')->call('enregistrer');

        $this->assertSame('Maïs concassé', Intrant::query()->find('INT-001')->name);
        $this->assertSame('Nouveau', Intrant::query()->find('INT-002')->name);
    }

    public function test_modifier_garde_le_code_et_recopie_les_champs(): void
    {
        $this->intrant();

        Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->call('modifier', 'INT-001')
            ->assertSet('nom', 'Maïs concassé')->assertSet('cat', 'Intrants Provende')->assertSet('unite', 'kg')->assertSet('seuil', '50')
            ->assertSee('Modifier Maïs concassé')
            ->set('seuil', '80')->set('nom', 'Maïs moulu')->call('enregistrer')
            ->assertSet('erreur', null)->assertSee('Intrant « Maïs moulu » modifié.');

        $i = Intrant::query()->findOrFail('INT-001');
        $this->assertSame(80, $i->threshold);
        $this->assertSame('Maïs moulu', $i->name);
        $this->assertSame(1, Intrant::query()->count());
    }

    public function test_modifier_un_intrant_inconnu_ne_fait_rien_et_un_intrant_disparu_est_signale(): void
    {
        $composant = Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->call('modifier', 'INT-999')->assertSet('formulaire', false);

        $this->intrant();
        $composant->call('modifier', 'INT-001');
        Intrant::query()->delete();
        $composant->call('enregistrer')->assertSet('erreur', 'Cet intrant n\'existe plus.');
        $this->assertSame(0, Intrant::query()->count());
    }

    public function test_une_modification_du_web_descend_vers_les_postes(): void
    {
        $this->intrant(['updated_at' => now()->subDay(), 'created_at' => now()->subDay()]);
        $avant = Intrant::query()->find('INT-001')->updated_at;
        $this->travel(5)->seconds();

        Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->call('modifier', 'INT-001')->set('seuil', '70')->call('enregistrer');

        $i = Intrant::query()->find('INT-001');
        $this->assertTrue($i->updated_at->greaterThan($avant), 'le curseur de tirage avance : les postes la recevront');
        $this->assertTrue($i->saisi_le->greaterThan(now()->subMinute()));
    }

    public function test_une_modification_sans_changement_est_acceptee_sans_rien_reecrire(): void
    {
        $i = $this->intrant();
        $saisie = $i->saisi_le;

        Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->call('modifier', 'INT-001')->call('enregistrer')
            ->assertSet('erreur', null)->assertSee('modifié');

        $this->assertEquals($saisie, Intrant::query()->find('INT-001')->saisi_le);
    }

    public function test_une_saisie_plus_ancienne_que_celle_du_serveur_est_refusee_avec_le_motif_du_serveur(): void
    {
        $this->intrant(['saisi_le' => now()->addMinutes(10)]);

        Livewire::actingAs($this->admin())->test(GestionStocks::class)
            ->call('modifier', 'INT-001')->set('seuil', '1')->call('enregistrer')
            ->assertSet('erreur', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.')
            ->assertSet('formulaire', true);

        $this->assertSame(50, Intrant::query()->find('INT-001')->threshold);
    }

    public function test_le_droit_d_ecrire_est_celui_des_stocks_ou_des_achats(): void
    {
        $achats = $this->lecteur();
        $achats->givePermissionTo('manage-achats');
        $stocks = $this->utilisateur('comptable', 'magasinier');
        $stocks->givePermissionTo('view-stocks', 'manage-stocks');

        foreach ([$achats, $stocks] as $u) {
            Livewire::actingAs($u)->test(GestionStocks::class)
                ->assertSee('Ajouter un Intrant')
                ->call('nouveau')->set('nom', 'Intrant de '.$u->username)->set('cat', 'Marchandises')
                ->call('enregistrer')->assertSet('erreur', null);
        }
        $this->assertSame(2, Intrant::query()->count());
    }

    // -------------------------------------------------------------------- Droits

    public function test_en_lecture_seule_aucun_bouton_et_les_methodes_sont_interdites(): void
    {
        $this->intrant();
        $lecteur = $this->lecteur();

        Livewire::actingAs($lecteur)->test(GestionStocks::class)
            ->assertSee('Maïs concassé')->assertSee('Journal des Mouvements')
            ->assertDontSee('Ajouter un Intrant')->assertDontSee('Modifier')->assertDontSee('Actions');

        // Un 403 ferme le composant : chaque appel interdit repart d'un composant neuf.
        $appel = fn (string $methode, array $args = []) => Livewire::actingAs($lecteur)->test(GestionStocks::class)
            ->call($methode, ...$args)->assertForbidden();
        $appel('nouveau');
        $appel('modifier', ['INT-001']);

        $forge = Livewire::actingAs($lecteur)->test(GestionStocks::class)
            ->set('nom', 'Pirate')->set('cat', 'Marchandises')->call('enregistrer')->assertForbidden();
        $this->assertSame(1, Intrant::query()->count());
        $this->assertSame(0, DemandeReferentiel::query()->count(), 'aucune demande n\'est posée');
    }

    public function test_le_journal_est_lisible_par_celui_qui_n_a_que_les_achats_ou_l_elevage_non(): void
    {
        // La route exige view-stocks : un compte « achats » seul n'ouvre pas l'écran.
        $achats = $this->utilisateur('comptable', 'achats');
        $achats->givePermissionTo('manage-achats');

        $this->actingAs($achats)->get('/stocks')->assertForbidden();
    }

    public function test_les_ecrans_convertis_ont_tous_une_vraie_route(): void
    {
        foreach (\App\Support\Ecrans::declarees() as $route) {
            $this->assertNotNull(
                collect(app('router')->getRoutes()->getRoutes())->first(fn ($r) => '/'.$r->uri() === $route && ! str_starts_with((string) $r->getName(), 'a-venir.')),
                "Écran déclaré converti sans route propre : $route",
            );
        }
    }
}
