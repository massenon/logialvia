<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\ParametresElevage;
use App\Models\BaremeRation;
use App\Models\DemandeReferentiel;
use App\Models\EcheanceProphylaxie;
use App\Models\Intrant;
use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\TauxRationPoids;
use App\Models\User;
use App\Support\Ecrans;
use App\Support\FilieresElevage;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

/**
 * Ecran web « Paramètres Élevage » : trois referentiels ecrits par demandes (memes regles
 * que pour un poste) et la numerotation.
 */
class ParametresElevageWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        ParametresEntreprise::courant();
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

    private function bareme(array $surcharge = []): BaremeRation
    {
        $b = (new BaremeRation)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'espece' => 'goliaths', 'stade' => 'Mature',
            'ration_grammes_par_jour' => 110, 'confirme' => false, 'saisi_le' => now()->subDay(),
        ], $surcharge));
        $b->save();

        return $b;
    }

    private function taux(array $surcharge = []): TauxRationPoids
    {
        $t = (new TauxRationPoids)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'espece' => 'poissons-chats', 'poids_min_g' => 0, 'poids_max_g' => 5,
            'taux_pourcent' => 15, 'confirme' => false, 'saisi_le' => now()->subDay(),
        ], $surcharge));
        $t->save();

        return $t;
    }

    private function echeance(array $surcharge = []): EcheanceProphylaxie
    {
        $e = (new EcheanceProphylaxie)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'espece' => 'goliaths', 'jour_cycle' => 15, 'traitement' => 'Gumboro',
            'produit' => 'Bursine', 'remanence_jours' => 3, 'dose' => '1 dose', 'saisi_le' => now()->subDay(),
        ], $surcharge));
        $e->save();

        return $e;
    }

    private function activer(string $module): void
    {
        ModuleActif::query()->where('module_id', $module)->update(['is_actif' => true]);
    }

    // ------------------------------------------------------------------- Acces

    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/parametres/elevage')->assertRedirect(route('login'));
    }

    public function test_seuls_ceux_qui_voient_l_elevage_ouvrent_la_page(): void
    {
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get('/parametres/elevage')->assertForbidden();
        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/parametres/elevage')->assertForbidden();
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/parametres/elevage')->assertOk()->assertSee('Paramètres Élevage');
        $this->actingAs($this->admin())->get('/parametres/elevage')->assertOk();
    }

    public function test_la_page_est_bien_l_ecran_converti_et_non_la_page_bientot(): void
    {
        $this->actingAs($this->admin())->get('/parametres/elevage')->assertDontSee('arrive bientôt');
        $this->assertContains('/parametres/elevage', Ecrans::declarees());
    }

    public function test_l_identifiant_deterministe_est_celui_du_poste(): void
    {
        // Valeurs calculees par `uuidDeterministe` du poste (Dart).
        $this->assertSame('f9bf68f2-fcd7-5a78-b691-c29668dee770', FilieresElevage::idBareme('goliaths', 'Mature'));
        $this->assertSame('1d035c6b-29b1-5434-aa9d-d11b89019cd7', FilieresElevage::idTaux('bovins', 150000));
        $this->assertSame('9506c65f-ebe3-56a3-a352-87c232d451ff', FilieresElevage::uuidDeterministe('echeance_prophylaxie:goliaths|15|Gumboro|Bursine'));
    }

    // ----------------------------------------------------------- Rationnement

    public function test_les_baremes_s_affichent_avec_leurs_badges_et_se_filtrent(): void
    {
        $this->bareme();
        $this->bareme(['espece' => 'lapins', 'stade' => 'Reproducteur', 'ration_grammes_par_jour' => 120, 'confirme' => true]);
        $this->bareme(['espece' => 'bovins', 'stade' => 'Veau', 'ration_grammes_par_jour' => 1500]);
        $this->bareme(['espece' => 'goliaths', 'stade' => 'Ancien', 'archive_le' => now()]);

        Livewire::actingAs($this->admin())->test(ParametresElevage::class)
            ->assertSee('3 barème(s)')->assertSee('Mature')->assertDontSee('Ancien')
            ->assertSee('Confirmé (Référence Cuniculture)')->assertSee('Repère à valider')
            ->assertSee('Générique (Aviculture, à confirmer)')
            ->set('rechercheRation', 'veau')->assertSee('1 barème(s)')->assertSee('1500 g/j')->assertDontSee('Mature')
            ->set('rechercheRation', '')->set('especeRation', 'lapins')->assertSee('1 barème(s)')->assertSee('Reproducteur');
    }

    public function test_aucun_bareme_affiche_le_message_du_poste(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresElevage::class)
            ->assertSee('Aucun barème ne correspond à ces filtres.');
    }

    public function test_ajouter_une_ration_utilise_l_identifiant_deterministe_et_laisse_une_demande(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresElevage::class)
            ->call('nouveauBareme')->set('espece', 'goliaths')->set('stade', 'Reproducteur')->set('ration', '120')
            ->call('enregistrerBareme')
            ->assertSet('erreur', null)->assertSet('formulaire', null)
            ->assertSee('Ration ajoutée pour Goliaths / Reproducteur.');

        $b = BaremeRation::query()->where('stade', 'Reproducteur')->firstOrFail();
        $this->assertSame(FilieresElevage::idBareme('goliaths', 'Reproducteur'), $b->id);
        $this->assertSame(120, $b->ration_grammes_par_jour);
        $this->assertFalse($b->confirme);
        $this->assertNull($b->archive_le);
        $this->assertSame(Catalogue::POSTE_WEB, DemandeReferentiel::query()->where('cle', $b->id)->value('device_id'));
    }

    public function test_une_modification_du_web_descend_vers_les_postes(): void
    {
        $b = $this->bareme(['updated_at' => now()->subDay(), 'created_at' => now()->subDay()]);
        $avant = $b->updated_at;
        $this->travel(5)->seconds();

        Livewire::actingAs($this->admin())->test(ParametresElevage::class)
            ->call('modifierBareme', $b->id)->set('ration', '90')->call('enregistrerBareme');

        $b->refresh();
        $this->assertTrue($b->updated_at->greaterThan($avant), 'le curseur de tirage avance : les postes la recevront');
        $this->assertTrue($b->saisi_le->greaterThan(now()->subMinute()));
    }

    public function test_ajouter_deux_fois_le_meme_stade_met_la_ration_a_jour(): void
    {
        $b = $this->bareme(['id' => FilieresElevage::idBareme('goliaths', 'Mature')]);
        $this->travel(5)->seconds();

        Livewire::actingAs($this->admin())->test(ParametresElevage::class)
            ->call('nouveauBareme')->set('espece', 'goliaths')->set('stade', 'Mature')->set('ration', '95')
            ->call('enregistrerBareme')->assertSet('erreur', null);

        $this->assertSame(1, BaremeRation::query()->count());
        $this->assertSame(95, $b->fresh()->ration_grammes_par_jour);
    }

    public function test_les_controles_du_poste_s_appliquent_a_l_ajout(): void
    {
        $c = Livewire::actingAs($this->admin())->test(ParametresElevage::class)->call('nouveauBareme');

        $c->set('stade', '')->set('ration', '100')->call('enregistrerBareme')
            ->assertSet('erreur', 'Veuillez renseigner le stade et la ration.');
        $c->set('stade', 'Adulte')->set('ration', '0')->call('enregistrerBareme')
            ->assertSet('erreur', 'Veuillez renseigner le stade et la ration.');
        $c->set('ration', '6000')->call('enregistrerBareme')
            ->assertSet('erreur', 'Une ration de plus de 5 000 g par tête et par jour est invraisemblable.');
        $c->set('espece', 'dragons')->set('ration', '100')->call('enregistrerBareme')
            ->assertSet('erreur', 'Cette filière n\'est pas active.');

        $this->assertSame(0, BaremeRation::query()->count(), 'rien n\'est écrit sur un refus');
    }

    public function test_le_plafond_d_un_bovin_est_de_20_kilos(): void
    {
        $this->activer('bovins');
        $c = Livewire::actingAs($this->admin())->test(ParametresElevage::class)->call('nouveauBareme');

        $c->set('espece', 'bovins')->set('stade', 'Embouche')->set('ration', '20001')->call('enregistrerBareme')
            ->assertSet('erreur', 'Une ration de plus de 20 000 g par tête et par jour est invraisemblable.');
        $c->set('ration', '20000')->call('enregistrerBareme')->assertSet('erreur', null);

        $this->assertSame(20000, BaremeRation::query()->where('stade', 'Embouche')->value('ration_grammes_par_jour'));
    }

    public function test_modifier_une_ration_repasse_a_valider_et_valider_confirme(): void
    {
        $b = $this->bareme(['confirme' => true]);
        $c = Livewire::actingAs($this->admin())->test(ParametresElevage::class);

        $c->call('modifierBareme', $b->id)->assertSet('ration', '110')->assertSee('Modifier — Goliaths / Mature')
            ->set('ration', '0')->call('enregistrerBareme')->assertSet('erreur', 'La ration doit être un nombre de grammes positif.');
        $c->set('ration', '6000')->call('enregistrerBareme')
            ->assertSet('erreur', 'Une ration de plus de 5 000 g par tête et par jour est invraisemblable.');

        $this->travel(2)->seconds();
        $c->set('ration', '130')->call('enregistrerBareme')->assertSee('Ration mise à jour : 130 g/j.');
        $b->refresh();
        $this->assertSame(130, $b->ration_grammes_par_jour);
        $this->assertFalse($b->confirme, 'la validation portait sur l\'ancienne valeur');

        $this->travel(2)->seconds();
        $c->call('modifierBareme', $b->id)->call('enregistrerBareme', true)->assertSee('Ration validée : 130 g/j.');
        $this->assertTrue($b->fresh()->confirme);

        $this->travel(2)->seconds();
        $c->call('modifierBareme', $b->id)->call('enregistrerBareme', false);
        $this->assertTrue($b->fresh()->confirme, 'valeur inchangée : le statut reste tel quel');
    }

    public function test_supprimer_un_bareme_passe_par_une_modale_et_pose_une_pierre_tombale(): void
    {
        $b = $this->bareme();
        $c = Livewire::actingAs($this->admin())->test(ParametresElevage::class);

        $c->call('demanderSuppression', 'bareme', $b->id)->assertSee('Confirmer la Suppression ?')->assertSee('« Mature »');
        $this->assertNull($b->fresh()->archive_le, 'rien tant que la modale n\'est pas confirmée');
        $c->call('annuler')->assertDontSee('Confirmer la Suppression ?');
        $this->assertNull($b->fresh()->archive_le);

        $c->call('demanderSuppression', 'bareme', $b->id)->call('confirmerSuppression')
            ->assertSee('Barème supprimé.')->assertDontSeeHtml('data-bareme="goliaths/Mature"');
        $this->assertNotNull($b->fresh()->archive_le, 'pierre tombale, jamais d\'effacement');
        $this->assertSame(1, BaremeRation::query()->count());
    }

    // -------------------------------------------------------------------- Taux

    public function test_les_classes_de_poids_s_affichent_pour_les_filieres_au_poids_vif(): void
    {
        $this->taux();
        $this->taux(['poids_min_g' => 5, 'poids_max_g' => null, 'taux_pourcent' => 7.5, 'confirme' => true]);

        $c = Livewire::actingAs($this->admin())->test(ParametresElevage::class)
            ->assertSee('Taux de ration par classe de poids')->assertSee('Moins de 5 g')->assertSee('5 g et plus')
            ->assertSee('15 %')->assertSee('7,5 %')->assertSee('Validé');
        $c->set('especeRation', 'goliaths')->assertDontSee('Taux de ration par classe de poids');
        $c->set('especeRation', 'poissons-chats')->assertSee('Taux de ration par classe de poids');
    }

    public function test_aucune_classe_affiche_le_message_du_poste(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresElevage::class)
            ->assertSee('Aucune classe de poids : la provende se calcule par tête.');
    }

    public function test_ajouter_une_classe_convertit_les_unites_et_utilise_la_cle_deterministe(): void
    {
        $this->activer('bovins');

        Livewire::actingAs($this->admin())->test(ParametresElevage::class)
            ->call('nouveauTaux')->set('espece', 'bovins')->set('poidsMin', '150')->set('poidsMax', '300')->set('taux', '3,5')
            ->call('enregistrerTaux')->assertSet('erreur', null)->assertSee('Classe de poids ajoutée.');

        $t = TauxRationPoids::query()->firstOrFail();
        $this->assertSame(FilieresElevage::idTaux('bovins', 150000), $t->id);
        $this->assertSame(150000, $t->poids_min_g);
        $this->assertSame(300000, $t->poids_max_g);
        $this->assertSame(3.5, $t->taux_pourcent);
        $this->assertFalse($t->confirme);
    }

    public function test_une_classe_de_poisson_se_saisit_en_grammes(): void
    {
        $this->activer('pisciculture');

        Livewire::actingAs($this->admin())->test(ParametresElevage::class)
            ->call('nouveauTaux')->set('espece', 'poissons-chats')->assertSee('Poids minimum (g, compris)')
            ->set('poidsMin', '20')->set('poidsMax', '100')->set('taux', '4')->call('enregistrerTaux');

        $this->assertSame(20, TauxRationPoids::query()->firstOrFail()->poids_min_g);
        $this->assertSame(100, TauxRationPoids::query()->firstOrFail()->poids_max_g);
    }

    public function test_les_controles_du_poste_s_appliquent_aux_classes(): void
    {
        $this->activer('bovins');
        $this->taux(['espece' => 'bovins', 'poids_min_g' => 0, 'poids_max_g' => 150000, 'taux_pourcent' => 3.5]);
        $c = Livewire::actingAs($this->admin())->test(ParametresElevage::class)->call('nouveauTaux')->set('espece', 'bovins');

        $c->set('poidsMin', '-1')->set('taux', '3')->call('enregistrerTaux')
            ->assertSet('erreur', 'Veuillez renseigner le poids minimum et le taux.');
        $c->set('poidsMin', '200')->set('poidsMax', 'beaucoup')->set('taux', '3')->call('enregistrerTaux')
            ->assertSet('erreur', 'Le poids maximum doit être un nombre de kilos.');
        $c->set('poidsMax', '100')->call('enregistrerTaux')
            ->assertSet('erreur', 'Le poids maximum doit dépasser le poids minimum.');
        $c->set('poidsMax', '300')->set('taux', '11')->call('enregistrerTaux')
            ->assertSet('erreur', 'Le taux doit être compris entre 0 et 10 % du poids vif (ou de la biomasse) par jour.');
        $c->set('poidsMin', '100')->set('taux', '3')->call('enregistrerTaux')
            ->assertSet('erreur', 'Cette classe chevauche « Moins de 150 kg » : un animal aurait deux taux.');
        $c->set('espece', 'goliaths')->call('enregistrerTaux')
            ->assertSet('erreur', 'Cette espèce n\'est pas rationnée sur le poids vif : le tableau ne s\'applique qu\'aux bovins et aux poissons-chats.');

        $this->assertSame(1, TauxRationPoids::query()->count());
    }

    public function test_modifier_une_classe_repasse_a_valider_et_valider_confirme(): void
    {
        $t = $this->taux(['confirme' => true]);
        $c = Livewire::actingAs($this->admin())->test(ParametresElevage::class);

        $c->call('modifierTaux', $t->id)->assertSet('poidsMin', '0')->assertSet('poidsMax', '5')->assertSet('taux', '15')
            ->set('taux', '12')->call('enregistrerTaux')->assertSee('Classe de poids mise à jour.');
        $this->assertFalse($t->fresh()->confirme);

        $this->travel(2)->seconds();
        $c->call('modifierTaux', $t->id)->call('enregistrerTaux', true)->assertSee('Classe de poids validée.');
        $this->assertTrue($t->fresh()->confirme);
        $this->assertSame(12.0, $t->fresh()->taux_pourcent);
    }

    public function test_supprimer_une_classe_pose_une_pierre_tombale(): void
    {
        $t = $this->taux();

        Livewire::actingAs($this->admin())->test(ParametresElevage::class)
            ->call('demanderSuppression', 'taux', $t->id)->assertSee('La classe « Moins de 5 g »')
            ->call('confirmerSuppression')->assertSee('Classe de poids supprimée.');

        $this->assertNotNull($t->fresh()->archive_le);
    }

    // ------------------------------------------------------------- Prophylaxie

    public function test_le_calendrier_d_une_espece_s_affiche_avec_recherche_et_dose_manquante(): void
    {
        $this->echeance();
        $this->echeance(['jour_cycle' => 5, 'traitement' => 'Anti-coccidien', 'produit' => 'Amprolium', 'dose' => null, 'remanence_jours' => 0]);
        $this->echeance(['espece' => 'pintades', 'traitement' => 'Newcastle pintade']);
        $this->echeance(['traitement' => 'Archivée', 'archive_le' => now()]);

        $c = Livewire::actingAs($this->admin())->test(ParametresElevage::class)->call('choisirOnglet', 'prophylaxie')
            ->assertSee('Calendrier — Goliaths')->assertSee('J15')->assertSee('J5')->assertSee('3j')
            ->assertSee('Dose non renseignée')->assertDontSee('Newcastle pintade')->assertDontSee('Archivée');
        $c->set('rechercheProphylaxie', 'amprol')->assertSee('Anti-coccidien')->assertDontSee('Gumboro');
        $c->set('rechercheProphylaxie', 'zzz')->assertSee('Aucune échéance ne correspond à ces filtres.');
        $c->set('rechercheProphylaxie', '')->set('especeProphylaxie', 'pintades')->assertSee('Newcastle pintade')->assertDontSee('Gumboro');
    }

    public function test_ajouter_une_echeance_cree_un_uuid_et_une_demande(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresElevage::class)->call('choisirOnglet', 'prophylaxie')
            ->call('nouvelleEcheance')->assertSee('Espèce : Goliaths')
            ->set('jour', '40')->set('traitement', 'Rappel Gumboro')->set('produit', 'Bursine')->set('dose', '1 dose par sujet')->set('remanence', '3')
            ->call('enregistrerEcheance')->assertSet('erreur', null)
            ->assertSee('Échéance ajoutée au calendrier de prophylaxie.');

        $e = EcheanceProphylaxie::query()->firstOrFail();
        $this->assertSame('goliaths', $e->espece);
        $this->assertSame(40, $e->jour_cycle);
        $this->assertSame('1 dose par sujet', $e->dose);
        $this->assertSame(3, $e->remanence_jours);
        $this->assertTrue(Str::isUuid($e->id));
        $this->assertSame(Catalogue::POSTE_WEB, DemandeReferentiel::query()->where('cle', $e->id)->value('device_id'));
    }

    public function test_les_controles_du_poste_s_appliquent_aux_echeances(): void
    {
        $c = Livewire::actingAs($this->admin())->test(ParametresElevage::class)->call('nouvelleEcheance');

        $c->call('enregistrerEcheance')->assertSet('erreur', 'Veuillez renseigner le jour, le traitement et le produit.');
        $c->set('jour', '5')->set('traitement', 'X')->set('produit', '')->call('enregistrerEcheance')
            ->assertSet('erreur', 'Veuillez renseigner le jour, le traitement et le produit.');
        $c->set('produit', 'Y')->set('jour', '0')->call('enregistrerEcheance')
            ->assertSet('erreur', 'Le jour du cycle doit être compris entre 1 et 365.');
        $c->set('jour', '366')->call('enregistrerEcheance')
            ->assertSet('erreur', 'Le jour du cycle doit être compris entre 1 et 365.');
        $c->set('jour', '365')->set('remanence', '-1')->call('enregistrerEcheance')
            ->assertSet('erreur', 'La rémanence ne peut pas être négative.');

        $this->assertSame(0, EcheanceProphylaxie::query()->count());
    }

    public function test_editer_une_echeance_garde_son_identifiant(): void
    {
        $e = $this->echeance();
        $this->travel(2)->seconds();

        Livewire::actingAs($this->admin())->test(ParametresElevage::class)->call('choisirOnglet', 'prophylaxie')
            ->call('modifierEcheance', $e->id)->assertSet('traitement', 'Gumboro')->assertSet('remanence', '3')
            ->set('dose', '2 doses')->call('enregistrerEcheance')->assertSee('Échéance de prophylaxie modifiée.');

        $this->assertSame(1, EcheanceProphylaxie::query()->count());
        $this->assertSame('2 doses', $e->fresh()->dose);
    }

    public function test_supprimer_une_echeance_pose_une_pierre_tombale(): void
    {
        $e = $this->echeance();

        Livewire::actingAs($this->admin())->test(ParametresElevage::class)->call('choisirOnglet', 'prophylaxie')
            ->call('demanderSuppression', 'echeance', $e->id)->assertSee('L\'échéance « Gumboro » (J15)', false)
            ->call('confirmerSuppression')->assertSee('Échéance de prophylaxie supprimée.');

        $this->assertNotNull($e->fresh()->archive_le);
    }

    // ---------------------------------------------------------------- Provende

    public function test_les_intrants_de_provende_sont_en_lecture_seule_sans_stock(): void
    {
        foreach ([['INT-001', 'Maïs', 'Intrants Provende'], ['INT-002', 'Soja', 'Intrants Provende'], ['INT-010', 'Seringues', 'Divers']] as [$code, $nom, $cat]) {
            (new Intrant)->forceFill(['code' => $code, 'name' => $nom, 'cat' => $cat, 'unit' => 'kg', 'threshold' => 25, 'saisi_le' => now()])->save();
        }

        $c = Livewire::actingAs($this->admin())->test(ParametresElevage::class)->call('choisirOnglet', 'provende')
            ->assertSee('2 intrant(s) de provende')->assertSee('Maïs')->assertSee('Soja')->assertDontSee('Seringues')
            ->assertSee('25 kg')->assertDontSee('Stock actuel')->assertDontSee('Prix indicatif')
            ->assertSee('propres à chaque poste')->assertDontSee('Ajouter');
        $c->set('rechercheProvende', 'soj')->assertSee('1 intrant(s) de provende')->assertDontSee('Maïs');
    }

    // ------------------------------------------------------------ Numerotation

    public function test_la_numerotation_affiche_les_formats_courants_et_les_apercus(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresElevage::class)->call('choisirOnglet', 'numerotation')
            ->assertSee('Préfixe Enclos')->assertSee('Préfixe Cage')->assertSee('Préfixe Bande')
            ->assertSee('Préfixe Bassin')->assertSee('Préfixe Bac')->assertSee('Préfixe Parc')
            ->assertSee('Aperçu : E1, E2, E3')->assertSee('Aperçu : PARC1, PARC2, PARC3')
            ->set('formats.enclos', 'ENC')->assertSee('Aperçu : ENC1, ENC2, ENC3');
    }

    public function test_enregistrer_la_numerotation_passe_par_une_demande_de_parametres(): void
    {
        $admin = $this->admin();
        Livewire::actingAs($admin)->test(ParametresElevage::class)->call('choisirOnglet', 'numerotation')
            ->set('formats.enclos', 'ENC')->set('formats.bac', 'CAISSE')
            ->call('enregistrerNumerotation')
            ->assertSet('erreur', 'Un préfixe compte 4 caractères au plus.');
        $this->assertSame('E', ParametresEntreprise::courant()->prefixe_enclos, 'refus du serveur : rien d\'écrit');

        $this->travel(2)->seconds();
        Livewire::actingAs($admin)->test(ParametresElevage::class)->call('choisirOnglet', 'numerotation')
            ->set('formats.enclos', 'ENC')->set('formats.bac', 'CAIS')
            ->call('enregistrerNumerotation')->assertSet('erreur', null)->assertSee('Formats enregistrés');

        $p = ParametresEntreprise::courant();
        $this->assertSame('ENC', $p->prefixe_enclos);
        $this->assertSame('CAIS', $p->prefixe_bac);
        $this->assertSame('PARC', $p->prefixe_parc);
        $this->assertSame(Catalogue::POSTE_WEB, DemandeReferentiel::query()->where('type', 'parametres_entreprise')->value('device_id'));
    }

    public function test_un_prefixe_vide_est_refuse_avec_le_message_du_poste(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresElevage::class)->call('choisirOnglet', 'numerotation')
            ->set('formats.cage', ' ')->set('formats.parc', '')
            ->call('enregistrerNumerotation')
            ->assertSet('erreur', 'Préfixe manquant : Cage, Parc. Un préfixe vide rendrait les identifiants indistinguables d\'une filière à l\'autre.');

        $this->assertSame('C', ParametresEntreprise::courant()->prefixe_cage);
    }

    public function test_la_numerotation_est_en_lecture_seule_sans_le_droit_parametres(): void
    {
        $animalier = $this->utilisateur('animalier', 'eleveur');

        Livewire::actingAs($animalier)->test(ParametresElevage::class)->call('choisirOnglet', 'numerotation')
            ->assertSee('Préfixe Enclos')->assertSeeHtml('data-section="lecture-seule"')
            ->assertDontSee('Enregistrer Tous les Formats de Numérotation');
        Livewire::actingAs($animalier)->test(ParametresElevage::class)->call('enregistrerNumerotation')->assertForbidden();
    }

    // ---------------------------------------------------------------- Filieres

    public function test_les_filieres_proposees_a_la_creation_sont_les_filieres_actives(): void
    {
        $admin = $this->admin();
        // Onglet « Prophylaxie » : la liste d'especes ne montre que les filieres actives.
        Livewire::actingAs($admin)->test(ParametresElevage::class)->call('choisirOnglet', 'prophylaxie')
            ->assertSeeHtml('<option value="goliaths">')->assertSeeHtml('<option value="pintades">')
            ->assertDontSeeHtml('<option value="bovins">')->assertDontSeeHtml('<option value="lapins">');

        $this->activer('bovins');
        $this->activer('cuniculture');
        Livewire::actingAs($admin)->test(ParametresElevage::class)->call('choisirOnglet', 'prophylaxie')
            ->assertSeeHtml('<option value="bovins">')->assertSeeHtml('<option value="lapins">');
    }

    public function test_une_filiere_inactive_ne_recoit_pas_de_nouvelle_ligne_mais_ses_lignes_restent_visibles(): void
    {
        $this->bareme(['espece' => 'bovins', 'stade' => 'Veau']);

        $c = Livewire::actingAs($this->admin())->test(ParametresElevage::class)->assertSee('Veau');
        $c->call('nouvelleEcheance')->set('espece', 'bovins')->set('jour', '5')->set('traitement', 'X')->set('produit', 'Y')
            ->call('enregistrerEcheance')->assertSet('erreur', 'Cette filière n\'est pas active.');
        $this->assertSame(0, EcheanceProphylaxie::query()->count());
    }

    // ------------------------------------------------------------------- Droits

    public function test_en_lecture_seule_aucun_bouton_et_les_methodes_sont_interdites(): void
    {
        $b = $this->bareme();
        $t = $this->taux();
        $e = $this->echeance();
        $lecteur = $this->utilisateur('comptable', 'compta');
        $lecteur->givePermissionTo('view-elevage');

        Livewire::actingAs($lecteur)->test(ParametresElevage::class)
            ->assertSee('Mature')
            ->assertDontSee('Ajouter')->assertDontSee('Modifier la ration')->assertDontSee('Supprimer')
            ->call('choisirOnglet', 'prophylaxie')->assertSee('Gumboro')->assertDontSee('Ajouter une Échéance')->assertDontSee('Éditer');

        // Un 403 ferme le composant : chaque appel interdit repart d'un composant neuf.
        $appel = fn (string $methode, array $args = []) => Livewire::actingAs($lecteur)->test(ParametresElevage::class)
            ->call($methode, ...$args)->assertForbidden();
        $appel('nouveauBareme');
        $appel('modifierBareme', [$b->id]);
        $appel('enregistrerBareme');
        $appel('nouveauTaux');
        $appel('modifierTaux', [$t->id]);
        $appel('enregistrerTaux');
        $appel('nouvelleEcheance');
        $appel('modifierEcheance', [$e->id]);
        $appel('enregistrerEcheance');
        $appel('demanderSuppression', ['bareme', $b->id]);
        $appel('confirmerSuppression');
        $appel('enregistrerNumerotation');
        $this->assertNull($b->fresh()->archive_le);
        $this->assertNull($e->fresh()->archive_le);
    }

    public function test_gerer_ne_suffit_pas_pour_supprimer(): void
    {
        $b = $this->bareme();
        Role::findOrCreate('gestionnaire-sans-archive', 'web')->givePermissionTo(['view-elevage', 'manage-elevage']);
        $gestionnaire = $this->utilisateur('gestionnaire-sans-archive', 'gestio');

        Livewire::actingAs($gestionnaire)->test(ParametresElevage::class)
            ->assertSee('Modifier la ration')->assertDontSee('Supprimer')
            ->call('nouveauBareme')->assertOk();
        Livewire::actingAs($gestionnaire)->test(ParametresElevage::class)->call('demanderSuppression', 'bareme', $b->id)->assertForbidden();
        Livewire::actingAs($gestionnaire)->test(ParametresElevage::class)->call('confirmerSuppression')->assertForbidden();
        $this->assertNull($b->fresh()->archive_le);
    }
}
