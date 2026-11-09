<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\Fournisseurs;
use App\Models\Achat;
use App\Models\Fournisseur;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Fournisseurs » : faits (dernier ecrivain gagne), agregats recalcules depuis les achats. */
class FournisseursWebTest extends TestCase
{
    use RefreshDatabase;

    private int $sequence = 0;

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
        return $this->utilisateur('admin', 'chef');
    }

    private function fournisseur(array $surcharge = []): Fournisseur
    {
        $f = (new Fournisseur)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => 'Agri Plus',
            'telephone' => '97000000', 'adresse' => 'Cotonou', 'fournit' => 'Maïs, Soja',
            'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ], $surcharge));
        $f->save();

        return $f;
    }

    private function achat(Fournisseur $f, array $surcharge = []): Achat
    {
        $this->sequence++;
        $a = (new Achat)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(),
            'reference' => sprintf('ACH-P1-2026-%03d', $this->sequence), 'portee_reference' => '',
            'fournisseur_id' => $f->id, 'date_achat' => now(), 'statut' => 'Livré',
            'total' => 10000, 'paye' => 4000, 'mode' => 'Espèces',
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $a->save();

        return $a;
    }

    // ------------------------------------------------------------------- Acces

    public function test_visiteur_et_animalier_n_ouvrent_pas_la_page(): void
    {
        $this->get('/fournisseurs')->assertRedirect(route('login'));
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/fournisseurs')->assertForbidden();
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get('/fournisseurs')->assertForbidden();
    }

    public function test_l_admin_et_le_comptable_l_ouvrent_et_c_est_bien_l_ecran_converti(): void
    {
        $this->actingAs($this->admin())->get('/fournisseurs')->assertOk()
            ->assertSee('Fournisseurs')->assertSee('Ajouter un Fournisseur')->assertDontSee('arrive bientôt');
        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/fournisseurs')->assertOk()
            ->assertDontSee('Ajouter un Fournisseur');
    }

    // ----------------------------------------------------------------- Lecture

    public function test_les_kpis_viennent_des_achats(): void
    {
        $a = $this->fournisseur(['nom' => 'Agri Plus']);
        $b = $this->fournisseur(['nom' => 'Provende SA']);
        $this->fournisseur(['nom' => 'Disparu', 'supprime_le' => now()]);

        $this->achat($a);                                                                   // du : 6000, ce mois
        $this->achat($a, ['total' => 5000, 'paye' => 5000]);                                // solde, ce mois
        $this->achat($a, ['total' => 9000, 'paye' => 0, 'date_achat' => now()->subMonths(2)]); // du : 9000, ancien
        $this->achat($b, ['total' => 7000, 'paye' => 0, 'statut' => 'Annulé']);             // ignore partout
        $this->achat($b, ['total' => 2000, 'paye' => 0, 'statut' => 'Commandé']);           // du : 2000, ce mois
        $this->achat($b, ['total' => 0, 'paye' => 0]);                                      // total nul : jamais « solde »

        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->assertSeeHtml('data-kpi="actifs">2<')
            ->assertSeeHtml('data-kpi="dette">17 000 ')       // 6000 + 9000 + 2000
            ->assertSeeHtml('data-kpi="achats-mois">17 000 ') // 10000 + 5000 + 2000 (annule et ancien exclus)
            ->assertSeeHtml('data-kpi="soldees-mois">1<')
            ->assertDontSee('Disparu');
    }

    public function test_la_liste_montre_les_agregats_recalcules_et_ignore_les_achats_annules(): void
    {
        $a = $this->fournisseur(['nom' => 'Agri Plus']);
        $this->achat($a);
        $this->achat($a, ['total' => 5000, 'paye' => 5000]);
        $this->achat($a, ['total' => 7000, 'paye' => 0, 'statut' => 'Annulé']);
        $this->fournisseur(['nom' => 'Sans achat', 'telephone' => null, 'fournit' => null]);

        $c = Livewire::actingAs($this->admin())->test(Fournisseurs::class);
        $c->assertSeeHtmlInOrder(['data-fournisseur="Agri Plus"', 'Maïs, Soja', '>2<', '15 000', '6 000'])
            ->assertSeeHtml('data-fournisseur="Sans achat"')
            ->assertSeeHtml('font-bold text-error-deep">6 000<')
            ->assertSeeHtml('font-bold text-success-deep">0<');
    }

    public function test_les_dettes_listent_les_achats_non_soldes_avec_leur_anciennete(): void
    {
        $a = $this->fournisseur();
        $this->achat($a, ['reference' => 'ACH-P1-2026-100', 'date_achat' => now()->subDays(15)]);
        $this->achat($a, ['reference' => 'ACH-P1-2026-101', 'total' => 5000, 'paye' => 5000]);
        $this->achat($a, ['reference' => 'ACH-P1-2026-104', 'date_achat' => now()->subDays(2)]);
        $this->achat($a, ['reference' => 'ACH-P1-2026-102', 'statut' => 'Annulé', 'paye' => 0]);
        $ancien = $this->fournisseur(['nom' => 'Disparu', 'supprime_le' => now()]);
        $this->achat($ancien, ['reference' => 'ACH-P1-2026-103', 'paye' => 0]);

        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->assertSeeHtml('data-dette="ACH-P1-2026-100"')
            ->assertSeeHtmlInOrder(['data-dette="ACH-P1-2026-100"', 'Agri Plus', '10 000', '4 000', '6 000', '15 j'])
            ->assertSeeHtml('bg-error-container text-error-deep">15 j<')
            ->assertSeeHtml('bg-surface-zebra text-outline">2 j<')
            ->assertDontSeeHtml('data-dette="ACH-P1-2026-101"')
            ->assertDontSeeHtml('data-dette="ACH-P1-2026-102"')
            ->assertDontSeeHtml('data-dette="ACH-P1-2026-103"');
    }

    public function test_la_recherche_filtre_par_nom_telephone_ou_produit(): void
    {
        $this->fournisseur(['nom' => 'Agri Plus', 'telephone' => '97000000', 'fournit' => 'Maïs']);
        $this->fournisseur(['nom' => 'Provende SA', 'telephone' => '96111111', 'fournit' => 'Soja']);

        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->set('recherche', 'prov')->assertSeeHtml('data-fournisseur="Provende SA"')->assertDontSeeHtml('data-fournisseur="Agri Plus"')
            ->set('recherche', '9700')->assertSeeHtml('data-fournisseur="Agri Plus"')->assertDontSeeHtml('data-fournisseur="Provende SA"')
            ->set('recherche', 'soja')->assertSeeHtml('data-fournisseur="Provende SA"')->assertDontSeeHtml('data-fournisseur="Agri Plus"')
            ->set('recherche', 'zzz')->assertSee('Aucun fournisseur ne correspond.');
    }

    public function test_sans_fournisseur_l_etat_vide_du_poste_est_affiche(): void
    {
        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->assertSee('Aucun fournisseur enregistré. Il en faut au moins un pour pouvoir passer une commande.')
            ->assertSee('Aucune dette ouverte.');
    }

    // ----------------------------------------------------------------- Ecriture

    public function test_un_fournisseur_ajoute_est_ecrit_comme_par_un_poste(): void
    {
        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->call('nouveau')->set('nom', ' Agri Plus ')->set('telephone', '95000000')
            ->set('adresse', ' Parakou ')->set('fournit', 'Maïs')
            ->call('enregistrer')
            ->assertSet('erreur', null)->assertSet('formulaire', false)->assertSee('Fournisseur enregistré.');

        $f = Fournisseur::query()->where('nom', 'Agri Plus')->firstOrFail();
        $this->assertSame(Catalogue::POSTE_WEB, $f->device_id);
        $this->assertSame('95000000', $f->telephone);
        $this->assertSame('Parakou', $f->adresse);
        $this->assertSame('Maïs', $f->fournit);
        $this->assertTrue(Str::isUuid($f->id));
        $this->assertTrue($f->serveur_modifie_le->greaterThan(now()->subMinute()));
        $this->assertNull($f->supprime_le);
    }

    public function test_les_champs_facultatifs_vides_sont_enregistres_a_null(): void
    {
        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->call('nouveau')->set('nom', 'Seul')->call('enregistrer')->assertSet('erreur', null);

        $f = Fournisseur::query()->where('nom', 'Seul')->firstOrFail();
        $this->assertNull($f->telephone);
        $this->assertNull($f->adresse);
        $this->assertNull($f->fournit);
    }

    public function test_un_nom_vide_ou_un_champ_trop_long_est_refuse_avec_le_message_du_serveur(): void
    {
        $c = Livewire::actingAs($this->admin())->test(Fournisseurs::class)->call('nouveau');

        $c->set('nom', '  ')->call('enregistrer')
            ->assertSet('erreur', 'Le nom du fournisseur est obligatoire.')->assertSet('formulaire', true);
        $c->set('nom', str_repeat('x', 256))->call('enregistrer')
            ->assertSet('erreur', 'Le nom du fournisseur est trop long.');
        $c->set('nom', 'Ok')->set('telephone', str_repeat('9', 41))->call('enregistrer')
            ->assertSet('formulaire', true);
        $this->assertNotNull($c->get('erreur'));

        $this->assertSame(0, Fournisseur::query()->count());
    }

    public function test_un_nom_deja_pris_est_refuse_sans_tenir_compte_de_la_casse(): void
    {
        $this->fournisseur(['nom' => 'Agri Plus']);
        $this->fournisseur(['nom' => 'Ancien nom', 'supprime_le' => now()]);

        $c = Livewire::actingAs($this->admin())->test(Fournisseurs::class)->call('nouveau');
        $c->set('nom', ' AGRI plus ')->call('enregistrer')
            ->assertSet('erreur', 'Un fournisseur porte déjà ce nom.')->assertSet('formulaire', true);
        $this->assertSame(2, Fournisseur::query()->count());

        // Le nom d'un fournisseur supprime est de nouveau libre.
        $c->set('nom', 'Ancien nom')->call('enregistrer')->assertSet('erreur', null);
        $this->assertSame(3, Fournisseur::query()->count());
    }

    public function test_modifier_garde_son_propre_nom_et_fait_avancer_le_curseur_des_postes(): void
    {
        $f = $this->fournisseur();
        $avant = $f->serveur_modifie_le;

        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->call('modifier', $f->id)->assertSet('nom', 'Agri Plus')->assertSet('fournit', 'Maïs, Soja')
            ->set('telephone', '98000000')->set('adresse', '')->call('enregistrer')
            ->assertSet('erreur', null)->assertSee('Fournisseur modifié.');

        $f->refresh();
        $this->assertSame('98000000', $f->telephone);
        $this->assertNull($f->adresse);
        $this->assertSame('Maïs, Soja', $f->fournit);
        $this->assertTrue($f->serveur_modifie_le->greaterThan($avant), 'les postes la recevront au prochain tirage');
        $this->assertSame(1, Fournisseur::query()->count());
    }

    public function test_renommer_vers_le_nom_d_un_autre_fournisseur_est_refuse(): void
    {
        $this->fournisseur(['nom' => 'Agri Plus']);
        $b = $this->fournisseur(['nom' => 'Provende SA']);

        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->call('modifier', $b->id)->set('nom', 'agri plus')->call('enregistrer')
            ->assertSet('erreur', 'Un fournisseur porte déjà ce nom.');

        $this->assertSame('Provende SA', $b->fresh()->nom);
    }

    public function test_une_ecriture_du_web_l_emporte_sur_une_saisie_plus_ancienne_d_un_poste(): void
    {
        $f = $this->fournisseur(['updated_at' => now()->subHours(2)]);

        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->call('modifier', $f->id)->set('nom', 'Nom du web')->call('enregistrer');

        $this->assertSame('Nom du web', $f->fresh()->nom);
    }

    public function test_modifier_un_fournisseur_supprime_entre_temps_est_refuse(): void
    {
        $f = $this->fournisseur();
        $c = Livewire::actingAs($this->admin())->test(Fournisseurs::class)->call('modifier', $f->id);
        $f->forceFill(['supprime_le' => now()])->save();

        $c->call('enregistrer')->assertSet('erreur', 'Ce fournisseur n\'existe plus.');
        $this->assertSame('Agri Plus', $f->fresh()->nom);
    }

    public function test_modifier_un_fournisseur_supprime_n_ouvre_pas_le_formulaire(): void
    {
        $f = $this->fournisseur(['supprime_le' => now()]);

        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->call('modifier', $f->id)->assertSet('formulaire', false)->assertSet('fournisseurId', null);
    }

    public function test_la_suppression_est_douce_et_les_achats_gardent_leur_fournisseur(): void
    {
        $f = $this->fournisseur();
        $a = $this->achat($f, ['total' => 5000, 'paye' => 5000]);
        $c = Livewire::actingAs($this->admin())->test(Fournisseurs::class);

        $c->call('demanderSuppression', $f->id)->assertSee('Supprimer ce fournisseur ?');
        $this->assertNull($f->fresh()->supprime_le, 'rien tant que la modale n\'est pas confirmee');
        $c->call('annuler')->assertDontSee('Supprimer ce fournisseur ?');

        $c->call('demanderSuppression', $f->id)->call('confirmerSuppression')
            ->assertSee('supprimé')->assertDontSeeHtml('data-fournisseur="Agri Plus"');

        $this->assertNotNull($f->fresh()->supprime_le);
        $this->assertSame('Agri Plus', $f->fresh()->nom);
        $this->assertSame($f->id, $a->fresh()->fournisseur_id);
        $this->assertSame(1, Fournisseur::query()->count());
    }

    public function test_un_fournisseur_avec_une_dette_ouverte_ne_se_supprime_pas(): void
    {
        $f = $this->fournisseur();
        $this->achat($f); // 6000 restent dus
        $c = Livewire::actingAs($this->admin())->test(Fournisseurs::class);

        $c->call('demanderSuppression', $f->id)
            ->assertSet('aSupprimer', null)->assertDontSee('Supprimer ce fournisseur ?')
            ->assertSee('a une dette ouverte');
        $this->assertNull($f->fresh()->supprime_le);

        // Meme si la dette apparait entre la demande et la confirmation.
        $g = $this->fournisseur(['nom' => 'Autre']);
        $c->call('demanderSuppression', $g->id)->assertSet('aSupprimer', $g->id);
        $this->achat($g);
        $c->call('confirmerSuppression')->assertSee('a une dette ouverte');
        $this->assertNull($g->fresh()->supprime_le);
    }

    public function test_un_achat_annule_ou_solde_n_empeche_pas_la_suppression(): void
    {
        $f = $this->fournisseur();
        $this->achat($f, ['statut' => 'Annulé', 'paye' => 0]);
        $this->achat($f, ['total' => 5000, 'paye' => 5000]);

        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->call('demanderSuppression', $f->id)->assertSet('aSupprimer', $f->id)
            ->call('confirmerSuppression');

        $this->assertNotNull($f->fresh()->supprime_le);
    }

    // -------------------------------------------------------------------- Droits

    public function test_le_comptable_consulte_sans_pouvoir_ecrire(): void
    {
        $f = $this->fournisseur();
        $comptable = $this->utilisateur('comptable', 'compta');

        Livewire::actingAs($comptable)->test(Fournisseurs::class)
            ->assertSee('Agri Plus')
            ->assertDontSee('Ajouter un Fournisseur')->assertDontSee('Modifier')->assertDontSee('Supprimer');

        $appel = fn (string $methode, array $args = []) => Livewire::actingAs($comptable)->test(Fournisseurs::class)
            ->call($methode, ...$args)->assertForbidden();
        $appel('nouveau');
        $appel('modifier', [$f->id]);
        $appel('enregistrer');
        $appel('demanderSuppression', [$f->id]);
        $appel('confirmerSuppression');
        $this->assertNull($f->fresh()->supprime_le);
        $this->assertSame(1, Fournisseur::query()->count());
    }

    public function test_confirmer_une_suppression_deja_demandee_exige_le_droit(): void
    {
        $f = $this->fournisseur();
        $admin = $this->admin();
        $comptable = $this->utilisateur('comptable', 'compta');

        // Etat Livewire forge : la demande a ete posee par un compte qui avait le droit.
        $c = Livewire::actingAs($admin)->test(Fournisseurs::class)->call('demanderSuppression', $f->id);
        $this->assertSame($f->id, $c->get('aSupprimer'));

        Livewire::actingAs($comptable)->test(Fournisseurs::class)->set('aSupprimer', $f->id)
            ->call('confirmerSuppression')->assertForbidden();
        $this->assertNull($f->fresh()->supprime_le);
    }
}
