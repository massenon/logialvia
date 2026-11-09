<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\SoinsCalendrier;
use App\Models\EntreeInfirmerie;
use App\Models\ModuleActif;
use App\Models\SoinCalendrier;
use App\Models\User;
use App\Support\Ecrans;
use Carbon\CarbonImmutable;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ecran web « Soins & Calendrier » : deux FAITS (soins, infirmerie), ecrits par
 * `TableSync::absorber` avec le device web, memes regles que pour un poste.
 */
class SoinsCalendrierWebTest extends TestCase
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

    private function aujourdhui(): CarbonImmutable
    {
        return CarbonImmutable::now(config('logialvia.fuseau'));
    }

    private function soin(array $surcharge = []): SoinCalendrier
    {
        $s = (new SoinCalendrier)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'espece' => 'goliaths',
            'date_prevue' => $this->aujourdhui()->format('Y-m-d'), 'type_soin' => 'Vaccination',
            'statut' => 'Planifié', 'produit' => 'ND-Lasota', 'dose' => '1 goutte', 'remanence_jours' => 0,
            'cout_fcfa' => 0, 'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ], $surcharge));
        $s->save();

        return $s;
    }

    private function entree(array $surcharge = []): EntreeInfirmerie
    {
        $e = (new EntreeInfirmerie)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'date_entree' => $this->aujourdhui()->format('Y-m-d'),
            'sujet' => 'Goliath #G-014', 'motif' => 'Boiterie', 'niveau_isolement' => 'Infirmerie',
            'statut' => 'En cours', 'espece' => 'goliaths',
            'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ], $surcharge));
        $e->save();

        return $e;
    }

    // ------------------------------------------------------------------- Acces

    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/elevage/soins')->assertRedirect(route('login'));
    }

    public function test_seuls_ceux_qui_voient_l_elevage_ouvrent_la_page(): void
    {
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get('/elevage/soins')->assertForbidden();
        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/elevage/soins')->assertForbidden();
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/elevage/soins')->assertOk()->assertSee('Soins &amp; Calendrier', false);
        $this->actingAs($this->admin())->get('/elevage/soins')->assertOk();
    }

    public function test_la_page_est_bien_l_ecran_converti_et_non_la_page_bientot(): void
    {
        $this->actingAs($this->admin())->get('/elevage/soins')->assertDontSee('arrive bientôt');
        $this->assertContains('/elevage/soins', Ecrans::declarees());
    }

    // ----------------------------------------------------------------- Lecture

    public function test_les_quatre_kpi_suivent_les_formules_du_poste(): void
    {
        $debutMois = $this->aujourdhui()->startOfMonth()->format('Y-m-d');
        $hier = $this->aujourdhui()->subDay()->format('Y-m-d');
        $demain = $this->aujourdhui()->addDay()->format('Y-m-d');
        $avantMois = $this->aujourdhui()->startOfMonth()->subDay()->format('Y-m-d');

        $this->soin(['statut' => 'Effectué', 'date_prevue' => $debutMois, 'cout_fcfa' => 2500]);   // dose + coût
        $this->soin(['statut' => 'Effectué', 'date_prevue' => $avantMois, 'cout_fcfa' => 9999]);   // hors mois
        $this->soin(['statut' => 'Planifié', 'date_prevue' => $demain, 'cout_fcfa' => 1000]);      // à venir + coût
        $this->soin(['statut' => 'Planifié', 'date_prevue' => $this->aujourdhui()->format('Y-m-d')]); // aujourd'hui compte (>=)
        $this->soin(['statut' => 'Planifié', 'date_prevue' => $hier]);                             // passé non effectué
        $this->soin(['statut' => 'Traitement en cours', 'date_prevue' => $avantMois]);             // quarantaine/traitement
        $this->entree();                                                                           // en cours
        $this->entree(['statut' => 'Réintégré', 'date_sortie' => $this->aujourdhui()->format('Y-m-d')]);

        $admin = $this->admin();
        Livewire::actingAs($admin)->test(SoinsCalendrier::class)
            ->assertSee('Doses Administrées (Mois)')->assertSee('Planifiées à Venir')
            ->assertSee('En Quarantaine / Traitement')->assertSee('Coût Vétérinaire (Mois)')
            ->assertSeeHtml('data-kpi="doses">1<')
            ->assertSeeHtml('data-kpi="planifiees">2<')
            ->assertSeeHtml('data-kpi="quarantaine">2<');

        // coût du mois = 2 500 + 1 000 + 0 (le soin de « hier » compte aussi s'il est dans le mois)
        $attendu = 2500 + 1000;
        Livewire::actingAs($admin)->test(SoinsCalendrier::class)
            ->assertSeeHtml('data-kpi="cout">'.number_format($attendu, 0, ',', ' '));
    }

    public function test_le_registre_les_filtres_et_le_libelle_administre(): void
    {
        $this->soin(['type_soin' => 'Vaccination', 'espece' => 'goliaths', 'statut' => 'Effectué']);
        $this->soin(['type_soin' => 'Vermifuge', 'espece' => 'pintades', 'produit' => 'Ivermectine']);

        Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)
            ->assertSee('Vaccination')->assertSee('Vermifuge')->assertSee('Administré')
            ->set('filtreType', 'Vermifuge')->assertSee('Ivermectine')->assertDontSee('ND-Lasota')
            ->set('filtreType', '')->set('filtreEspece', 'goliaths')->assertSee('ND-Lasota')->assertDontSee('Ivermectine');
    }

    public function test_le_registre_vide_affiche_le_message_du_poste(): void
    {
        Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)
            ->assertSee('Aucun soin enregistré. Utilisez « Nouveau Soin »');
    }

    public function test_la_banniere_de_remanence_n_apparait_que_pour_un_delai_en_cours(): void
    {
        $this->soin(['statut' => 'Effectué', 'date_prevue' => $this->aujourdhui()->format('Y-m-d'), 'remanence_jours' => 5, 'produit' => 'Antcox']);
        $this->soin(['statut' => 'Effectué', 'date_prevue' => $this->aujourdhui()->subDays(10)->format('Y-m-d'), 'remanence_jours' => 5, 'produit' => 'Vieux']);
        $this->soin(['statut' => 'Planifié', 'date_prevue' => $this->aujourdhui()->format('Y-m-d'), 'remanence_jours' => 5, 'produit' => 'Pasfait']);
        // Le délai se termine AUJOURD'HUI (date + 5 jours = aujourd'hui) : il n'est plus en cours.
        $this->soin(['statut' => 'Effectué', 'date_prevue' => $this->aujourdhui()->subDays(5)->format('Y-m-d'), 'remanence_jours' => 5, 'produit' => 'Limite']);

        $c = Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)
            ->assertSee('1 délai(s) d\'attente en cours — produits non commercialisables', false)
            ->assertSee('(Antcox)')->assertDontSee('(Vieux)')->assertDontSee('(Pasfait)')->assertDontSee('(Limite)');
        $this->assertStringContainsString($this->aujourdhui()->addDays(5)->format('d/m/Y'), $c->html());
    }

    public function test_le_calendrier_des_doses_montre_le_mois_courant_par_espece(): void
    {
        $this->soin(['espece' => 'goliaths', 'date_prevue' => $this->aujourdhui()->startOfMonth()->addDays(2)->format('Y-m-d'), 'statut' => 'En retard']);
        $this->soin(['espece' => 'pintades', 'date_prevue' => $this->aujourdhui()->startOfMonth()->subMonth()->format('Y-m-d')]);

        Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)->call('choisirOnglet', 'calendrier')
            ->assertSee('Calendrier des Doses — '.$this->aujourdhui()->format('m/Y'))
            ->assertSeeHtml('data-ligne-espece="goliaths"')->assertDontSeeHtml('data-ligne-espece="pintades"')
            ->assertSeeHtml('data-jour="3"')->assertSee('Planifier une Intervention');
    }

    public function test_le_calendrier_vide_affiche_le_message_du_poste(): void
    {
        Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)->call('choisirOnglet', 'calendrier')
            ->assertSee('Aucune intervention programmée ce mois-ci.');
    }

    public function test_l_infirmerie_liste_les_entrees_et_la_mortalite_non_reportee(): void
    {
        $this->entree(['sujet' => 'Pintade #P-003', 'statut' => 'Décédé', 'date_sortie' => $this->aujourdhui()->format('Y-m-d')]);
        $this->entree(['sujet' => 'Lapin #L-1', 'statut' => 'Décédé', 'date_sortie' => $this->aujourdhui()->format('Y-m-d'), 'categorie_mortalite' => 1]);

        Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)->call('choisirOnglet', 'infirmerie')
            ->assertSee('Suivi Infirmerie')->assertSee('Pintade #P-003')->assertSee('Mortalité non reportée')
            ->assertSee('Mortalité portée sur la fiche')->assertSee('Date d\'Entrée', false);
    }

    public function test_l_infirmerie_vide_affiche_le_message_du_poste(): void
    {
        Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)->call('choisirOnglet', 'infirmerie')
            ->assertSee('Aucun sujet en infirmerie.');
    }

    // ---------------------------------------------------------------- Ecriture

    public function test_un_soin_enregistre_part_en_base_avec_le_device_web_et_avance_le_curseur(): void
    {
        $this->travelTo(now()->startOfSecond());
        Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)
            ->call('nouveauSoin')
            ->set('espece', 'goliaths')->set('dateSoin', '2026-11-05')->set('typeSoin', 'Vaccination')
            ->set('produit', 'ND-Lasota')->set('dose', '1 goutte')->set('remanence', '3')->set('cout', '1500')
            ->set('dejaEffectue', true)
            ->call('enregistrer'.'Soin')
            ->assertSet('erreur', null)->assertSet('modale', null)->assertSee('Soin enregistré avec succès.');

        $s = SoinCalendrier::query()->firstOrFail();
        $this->assertSame(Catalogue::POSTE_WEB, $s->device_id);
        $this->assertSame('Effectué', $s->statut);
        $this->assertSame(3, $s->remanence_jours);
        $this->assertSame(1500, $s->cout_fcfa);
        $this->assertSame('2026-11-05', $s->date_prevue->format('Y-m-d'));
        $this->assertNull($s->echeance_prophylaxie_id);
        $this->assertTrue($s->serveur_modifie_le->greaterThanOrEqualTo(now()->subSeconds(2)), 'le curseur de tirage avance : les postes la recevront');
    }

    public function test_sans_la_case_le_soin_est_planifie(): void
    {
        Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)->call('nouveauSoin')
            ->set('espece', 'goliaths')->set('typeSoin', 'Vermifuge')->call('enregistrerSoin');

        $this->assertSame('Planifié', SoinCalendrier::query()->firstOrFail()->statut);
    }

    public function test_les_controles_du_poste_s_appliquent_dans_le_meme_ordre(): void
    {
        $c = Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)->call('nouveauSoin');

        $c->call('enregistrerSoin')->assertSet('erreur', 'Le lot / la bande est obligatoire.');
        $c->set('espece', 'goliaths')->set('dateSoin', '')->call('enregistrerSoin')
            ->assertSet('erreur', 'La date du soin est obligatoire.');
        $c->set('dateSoin', '2026-11-05')->call('enregistrerSoin')
            ->assertSet('erreur', 'Le type d\'action est obligatoire.');
        $c->set('typeSoin', 'Vermifuge')->set('remanence', '-2')->call('enregistrerSoin')
            ->assertSet('erreur', 'Le délai d\'attente ne peut être négatif.');
        $c->set('remanence', '0')->set('cout', '-5')->call('enregistrerSoin')
            ->assertSet('erreur', 'Le coût ne peut être négatif.');
        $c->set('espece', 'dragons')->set('cout', '0')->call('enregistrerSoin')
            ->assertSet('erreur', 'Le lot / la bande est obligatoire.');

        $this->assertSame(0, SoinCalendrier::query()->count(), 'rien n\'est écrit sur un refus');
    }

    public function test_planifier_une_intervention_accepte_un_libelle_libre(): void
    {
        $c = Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)->call('nouvelleIntervention');

        $c->call('enregistrerIntervention')->assertSet('erreur', 'L\'intervention est obligatoire.');
        $c->set('intervention', 'Vaccin Newcastle (Rappel)')->set('espece', 'goliaths')->set('dateSoin', '2026-11-20')
            ->call('enregistrerIntervention')->assertSet('erreur', null)
            ->assertSee('Intervention « Vaccin Newcastle (Rappel) » planifiée pour le 20/11/2026.');

        $s = SoinCalendrier::query()->firstOrFail();
        $this->assertSame('Vaccin Newcastle (Rappel)', $s->type_soin);
        $this->assertSame('Planifié', $s->statut);
        $this->assertSame(0, $s->cout_fcfa);
    }

    public function test_confirmer_l_administration_ecrit_un_instant_posterieur_meme_a_un_poste_en_avance(): void
    {
        $futur = now()->addHours(2);
        $s = $this->soin(['updated_at' => $futur, 'serveur_modifie_le' => now()->subDay()]);

        Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)
            ->call('confirmerAdministration', $s->id)->assertSee('Administration confirmée.');

        $s->refresh();
        $this->assertSame('Effectué', $s->statut);
        $this->assertTrue($s->updated_at->greaterThan($futur), 'dernier écrivain gagne : le web ne perd pas contre une horloge en avance');
        $this->assertTrue($s->serveur_modifie_le->greaterThan(now()->subMinute()));
        $this->assertSame(Catalogue::POSTE_WEB, $s->device_id);
    }

    public function test_confirmer_un_soin_deja_effectue_ne_change_rien(): void
    {
        $s = $this->soin(['statut' => 'Effectué']);
        $avant = $s->updated_at;

        Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)
            ->call('confirmerAdministration', $s->id)->assertSee('Ce soin est déjà marqué comme effectué.');

        $this->assertTrue($s->fresh()->updated_at->equalTo($avant));
    }

    public function test_une_entree_d_infirmerie_est_enregistree_en_cours_avec_la_date_du_jour(): void
    {
        $c = Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)->call('nouvelleEntree');

        $c->call('enregistrerEntree')->assertSet('erreur', 'Le lot / sujet est obligatoire.');
        $c->set('sujet', 'Goliath #G-014')->call('enregistrerEntree')->assertSet('erreur', 'Le motif est obligatoire.');
        $c->set('motif', 'Suspicion Newcastle')->set('niveau', 'Quarantaine stricte')->set('espece', 'goliaths')
            ->call('enregistrerEntree')->assertSet('erreur', null)->assertSee('Entrée d\'infirmerie enregistrée.');

        $e = EntreeInfirmerie::query()->firstOrFail();
        $this->assertSame('En cours', $e->statut);
        $this->assertSame($this->aujourdhui()->format('Y-m-d'), $e->date_entree->format('Y-m-d'));
        $this->assertSame('Quarantaine stricte', $e->niveau_isolement);
        $this->assertNull($e->date_sortie);
        $this->assertNull($e->categorie_mortalite);
        $this->assertSame(Catalogue::POSTE_WEB, $e->device_id);
    }

    public function test_reintegrer_cloture_l_entree_et_le_deces_n_existe_pas_au_web(): void
    {
        $e = $this->entree();

        $c = Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)->call('choisirOnglet', 'infirmerie')
            ->assertSee('Réintégrer')->assertDontSee('Décès');
        $c->call('reintegrer', $e->id)->assertSee('Entrée clôturée : réintégré.');

        $e->refresh();
        $this->assertSame('Réintégré', $e->statut);
        $this->assertSame($this->aujourdhui()->format('Y-m-d'), $e->date_sortie->format('Y-m-d'));
        $this->assertNull($e->categorie_mortalite);

        $c->call('reintegrer', $e->id)->assertSee('Cette entrée est déjà clôturée.');
    }

    public function test_un_deces_declare_au_poste_garde_sa_marque_apres_un_geste_du_web(): void
    {
        $e = $this->entree(['statut' => 'Décédé', 'date_sortie' => $this->aujourdhui()->format('Y-m-d'), 'categorie_mortalite' => 2]);

        Livewire::actingAs($this->admin())->test(SoinsCalendrier::class)->call('reintegrer', $e->id)
            ->assertSee('Cette entrée est déjà clôturée.');

        $this->assertSame('Décédé', $e->fresh()->statut);
        $this->assertSame(2, $e->fresh()->categorie_mortalite);
    }

    public function test_les_filieres_proposees_sont_les_filieres_actives(): void
    {
        $admin = $this->admin();
        // Onglet « Calendrier » : aucun filtre, seule la modale propose des filieres.
        $c = Livewire::actingAs($admin)->test(SoinsCalendrier::class)->call('choisirOnglet', 'calendrier')->call('nouveauSoin');
        $c->assertSeeHtml('<option value="goliaths">')->assertSeeHtml('<option value="pintades">')
            ->assertDontSeeHtml('<option value="bovins">')->assertDontSeeHtml('<option value="lapins">');

        ModuleActif::query()->where('module_id', 'bovins')->update(['is_actif' => true]);
        Livewire::actingAs($admin)->test(SoinsCalendrier::class)->call('choisirOnglet', 'calendrier')->call('nouveauSoin')
            ->assertSeeHtml('<option value="bovins">');
    }

    // ------------------------------------------------------------------- Droits

    public function test_en_lecture_seule_aucun_bouton_et_les_methodes_sont_interdites(): void
    {
        $s = $this->soin();
        $e = $this->entree();
        $lecteur = $this->utilisateur('comptable', 'compta');
        $lecteur->givePermissionTo('view-elevage');

        Livewire::actingAs($lecteur)->test(SoinsCalendrier::class)
            ->assertSee('Vaccination')
            ->assertDontSee('Nouveau Soin')->assertDontSee('Confirmer')
            ->call('choisirOnglet', 'calendrier')->assertDontSee('Planifier une Intervention')
            ->call('choisirOnglet', 'infirmerie')->assertDontSee('Nouvelle Entrée')->assertDontSee('Réintégrer');

        // Un 403 ferme le composant : chaque appel interdit repart d'un composant neuf.
        $appel = fn (string $methode, array $args = []) => Livewire::actingAs($lecteur)->test(SoinsCalendrier::class)
            ->call($methode, ...$args)->assertForbidden();
        $appel('nouveauSoin');
        $appel('nouvelleIntervention');
        $appel('nouvelleEntree');
        $appel('enregistrerSoin');
        $appel('enregistrerIntervention');
        $appel('enregistrerEntree');
        $appel('confirmerAdministration', [$s->id]);
        $appel('reintegrer', [$e->id]);
        $this->assertSame('Planifié', $s->fresh()->statut);
        $this->assertSame('En cours', $e->fresh()->statut);
    }
}
