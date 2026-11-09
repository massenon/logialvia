<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\ParametresGeneraux;
use App\Models\DemandeReferentiel;
use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use App\Models\User;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\TestCase;

/** Ecran web « Paramètres Généraux » : referentiel, memes regles que pour un poste, aucun secret. */
class ParametresGenerauxWebTest extends TestCase
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

    /** Un compte qui VOIT les parametres sans pouvoir les modifier. */
    private function lecteur(): User
    {
        $u = $this->utilisateur('comptable', 'lecteur');
        $u->givePermissionTo('view-parametres');

        return $u;
    }

    private function parametres(array $valeurs = []): ParametresEntreprise
    {
        $p = ParametresEntreprise::courant();
        $p->forceFill(array_merge(['updated_at' => now()->subDay(), 'created_at' => now()->subDay()], $valeurs))->save();

        return $p;
    }

    /** Remplit le formulaire avec un jeu valide (surcharge possible). */
    private function remplir($composant, array $surcharge = [])
    {
        $valeurs = array_merge([
            'raisonSociale' => 'ALLMANY ET COMPAGNIE', 'nomPromoteur' => 'Mme Allmany', 'adresseSiege' => 'Parakou',
            'telephone' => '+229 01 00 00 00 00', 'email' => 'contact@allmany.bj', 'delaiPaiement' => '30',
            'ifu' => '3201234567890', 'rccm' => 'RB/PKO/20 B 123', 'smtpServeur' => 'smtp.exemple.bj', 'smtpPort' => '587',
            'smtpSecurite' => 'TLS',
        ], $surcharge);
        foreach ($valeurs as $propriete => $valeur) {
            $composant->set($propriete, $valeur);
        }

        return $composant;
    }

    // ------------------------------------------------------------------- Acces

    public function test_un_visiteur_est_renvoye_vers_la_connexion(): void
    {
        $this->get('/parametres/generaux')->assertRedirect(route('login'));
    }

    public function test_seul_celui_qui_voit_les_parametres_ouvre_la_page(): void
    {
        foreach (['caissier', 'animalier', 'comptable'] as $i => $role) {
            $this->actingAs($this->utilisateur($role, "u$i"))->get('/parametres/generaux')->assertForbidden();
        }
        $this->actingAs($this->admin())->get('/parametres/generaux')->assertOk()->assertSee('Paramètres Généraux');
        $this->actingAs($this->lecteur())->get('/parametres/generaux')->assertOk();
    }

    public function test_la_page_est_bien_l_ecran_converti_et_non_la_page_bientot(): void
    {
        $this->actingAs($this->admin())->get('/parametres/generaux')->assertDontSee('arrive bientôt');
    }

    public function test_les_huit_onglets_du_poste_sont_la_dans_l_ordre(): void
    {
        $this->actingAs($this->admin());
        $page = $this->get('/parametres/generaux')->assertOk();
        $page->assertSeeInOrder([
            'Modules Actifs', 'Données de l&#039;Entreprise', 'Gestion Utilisateurs', 'Modes de Paiement',
            'Appairage', 'Sauvegardes', 'Corbeille', 'Données de Test',
        ], false);
    }

    public function test_un_lien_mene_a_postes_et_appairage_et_retour(): void
    {
        $admin = $this->admin();
        $this->actingAs($admin)->get('/parametres/generaux')->assertSee(route('postes'), false);
        $this->actingAs($admin)->get('/parametres/postes')->assertSee('href="/parametres/generaux"', false);
    }

    // ----------------------------------------------------------------- Modules

    public function test_les_modules_montrent_leur_etat_et_les_deux_filieres_fixes(): void
    {
        ModuleActif::query()->where('module_id', 'bovins')->update(['is_actif' => true]);

        Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)
            ->assertSee('Goliaths')->assertSee('Pintades')->assertSee('toujours actif')
            ->assertSeeHtml('data-module="bovins"')->assertSee('Poulets / Pondeuses')
            ->assertSeeHtml('data-module-fixe="Goliaths"')
            ->assertSee('Mode « Données de Test »')->assertSee('Désactivé — l\'onglet Données de Test est verrouillé');
    }

    public function test_activer_un_module_passe_par_une_demande_du_poste_web(): void
    {
        $module = ModuleActif::query()->where('module_id', 'cuniculture')->firstOrFail();
        $module->forceFill(['updated_at' => now()->subDay()])->save();
        $avant = $module->fresh()->updated_at;
        $this->travel(5)->seconds();

        Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)
            ->call('basculerModule', 'cuniculture', true)
            ->assertSet('erreur', null)
            ->assertSee('Lapins (Cuniculture) activée — sa fiche apparaît dans le menu latéral.');

        $this->assertTrue($module->fresh()->is_actif);
        $this->assertTrue($module->fresh()->updated_at->greaterThan($avant), 'le curseur de tirage avance : les postes la recevront');
        $demande = DemandeReferentiel::query()->where('cle', 'cuniculture')->firstOrFail();
        $this->assertSame(Catalogue::POSTE_WEB, $demande->device_id);
        $this->assertSame('module_actif', $demande->type);
        $this->assertSame('acceptee', $demande->statut);
    }

    public function test_desactiver_un_module_conserve_les_donnees_et_le_dit(): void
    {
        ModuleActif::query()->where('module_id', 'bovins')->update(['is_actif' => true]);
        $this->travel(5)->seconds();

        Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)
            ->call('basculerModule', 'bovins', false)
            ->assertSee('Bovins désactivée. Les données historiques sont conservées.');

        $this->assertFalse(ModuleActif::query()->where('module_id', 'bovins')->value('is_actif'));
    }

    public function test_un_module_inconnu_n_ecrit_rien(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('basculerModule', 'goliaths', false);

        $this->assertSame(0, DemandeReferentiel::query()->count());
    }

    public function test_un_module_active_ouvre_sa_fiche_dans_la_barre_laterale(): void
    {
        $admin = $this->admin();
        $this->actingAs($admin)->get('/elevage/lapins')->assertNotFound();

        $this->travel(5)->seconds();
        Livewire::actingAs($admin)->test(ParametresGeneraux::class)->call('basculerModule', 'cuniculture', true);

        $this->actingAs($admin)->get('/elevage/lapins')->assertOk();
    }

    public function test_une_modification_plus_recente_du_serveur_est_refusee_avec_le_message_du_serveur(): void
    {
        // Le serveur a decide dans le futur proche : la saisie web (maintenant) est plus ancienne.
        ModuleActif::query()->where('module_id', 'bovins')->get()->each(fn ($m) => $m->forceFill(['updated_at' => now()->addHour()])->save());

        Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)
            ->call('basculerModule', 'bovins', true)
            ->assertSet('erreur', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.')
            ->assertDontSee('activée — sa fiche');

        $this->assertFalse(ModuleActif::query()->where('module_id', 'bovins')->value('is_actif'));
    }

    public function test_sans_manage_modules_les_interrupteurs_sont_absents(): void
    {
        $this->parametres();
        $u = $this->lecteur();
        $u->givePermissionTo('manage-parametres'); // les parametres oui, les modules non

        Livewire::actingAs($u)->test(ParametresGeneraux::class)
            ->assertDontSeeHtml('role="switch"')->assertSee('Lecture seule : seul l\'administrateur peut activer', false);
        Livewire::actingAs($u)->test(ParametresGeneraux::class)->call('basculerModule', 'bovins', true)->assertForbidden();
        $this->assertSame(0, DemandeReferentiel::query()->count());
    }

    // -------------------------------------------------------------- Entreprise

    public function test_la_fiche_entreprise_montre_les_valeurs_du_serveur(): void
    {
        $this->parametres(['nom_promoteur' => 'Mme Allmany', 'adresse_siege' => 'Parakou', 'ifu' => '3201234567890',
            'rccm' => 'RB/PKO/20 B 123', 'delai_paiement_jours' => 15, 'smtp_serveur' => 'smtp.exemple.bj', 'smtp_port' => 465, 'smtp_securite' => 'SSL']);

        Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1)
            ->assertSet('raisonSociale', 'ALLMANY ET COMPAGNIE')->assertSet('nomPromoteur', 'Mme Allmany')
            ->assertSet('adresseSiege', 'Parakou')->assertSet('ifu', '3201234567890')->assertSet('rccm', 'RB/PKO/20 B 123')
            ->assertSet('delaiPaiement', '15')->assertSet('smtpServeur', 'smtp.exemple.bj')->assertSet('smtpPort', '465')
            ->assertSet('smtpSecurite', 'SSL')
            ->assertSee('Informations Générales')->assertSee('Conditions de Vente')
            ->assertSee('Informations Légales & Fiscales')->assertSee('Configuration Email (SMTP)')
            ->assertSee('Enregistrer les Modifications');
    }

    public function test_sans_delai_le_dart_previent_que_rien_n_est_en_retard(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1)
            ->assertSee('Aucun délai n\'est fixé', false)
            ->set('delaiPaiement', '30')->assertDontSee('Aucun délai n\'est fixé', false);
    }

    public function test_enregistrer_ecrit_par_une_demande_et_avance_le_curseur(): void
    {
        $p = $this->parametres();
        $avant = $p->fresh()->updated_at;
        $this->travel(5)->seconds();

        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1);
        $this->remplir($composant, ['raisonSociale' => '  ALLMANY SARL  '])->call('enregistrer')
            ->assertSet('erreur', null)->assertSee('Paramètres enregistrés.');

        $p = $p->fresh();
        $this->assertSame('ALLMANY SARL', $p->raison_sociale);
        $this->assertSame('Mme Allmany', $p->nom_promoteur);
        $this->assertSame('Parakou', $p->adresse_siege);
        $this->assertSame('+229 01 00 00 00 00', $p->telephone);
        $this->assertSame('contact@allmany.bj', $p->email);
        $this->assertSame('3201234567890', $p->ifu);
        $this->assertSame('RB/PKO/20 B 123', $p->rccm);
        $this->assertSame(30, $p->delai_paiement_jours);
        $this->assertSame('smtp.exemple.bj', $p->smtp_serveur);
        $this->assertSame(587, $p->smtp_port);
        $this->assertSame('TLS', $p->smtp_securite);
        $this->assertTrue($p->updated_at->greaterThan($avant), 'les postes recevront la fiche au prochain tirage');
        $demande = DemandeReferentiel::query()->where('type', 'parametres_entreprise')->firstOrFail();
        $this->assertSame(Catalogue::POSTE_WEB, $demande->device_id);
        $this->assertSame('acceptee', $demande->statut);
    }

    public function test_la_demande_ne_porte_que_des_champs_autorises_et_aucun_secret(): void
    {
        $this->parametres();
        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1);
        $this->remplir($composant)->call('enregistrer');

        $donnees = DemandeReferentiel::query()->where('type', 'parametres_entreprise')->firstOrFail()->donnees;
        $this->assertSame([], array_diff(array_keys($donnees), \App\Sync\DemandesReferentiel::CHAMPS_PARAMETRES));
        foreach (array_keys($donnees) as $cle) {
            $this->assertDoesNotMatchRegularExpression('/jeton|token|password|mot_de_passe|secret/i', $cle);
        }
        $this->assertArrayNotHasKey('mode_donnees_test', $donnees);
    }

    public function test_un_champ_vide_n_efface_pas_la_valeur_du_serveur(): void
    {
        $this->parametres(['nom_promoteur' => 'Mme Allmany']);
        $this->travel(5)->seconds();

        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1);
        $this->remplir($composant, ['nomPromoteur' => ''])->call('enregistrer')->assertSet('erreur', null);

        $this->assertSame('Mme Allmany', ParametresEntreprise::courant()->nom_promoteur);
    }

    public function test_la_raison_sociale_est_obligatoire(): void
    {
        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1);
        $this->remplir($composant, ['raisonSociale' => '   '])->call('enregistrer')
            ->assertSet('erreur', 'La raison sociale est obligatoire.')->assertSee('La raison sociale est obligatoire.');

        $this->assertSame(0, DemandeReferentiel::query()->count());
    }

    public function test_l_ifu_est_obligatoire_et_numerique(): void
    {
        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1);

        $this->remplir($composant, ['ifu' => ''])->call('enregistrer')
            ->assertSet('erreur', 'L\'Identifiant Fiscal Unique (IFU) est obligatoire.');
        $this->remplir($composant, ['ifu' => '32A12'])->call('enregistrer')
            ->assertSet('erreur', 'L\'IFU ne doit contenir que des chiffres.');
        $this->remplir($composant, ['ifu' => '-12'])->call('enregistrer')
            ->assertSet('erreur', 'L\'IFU ne doit contenir que des chiffres.');

        $this->assertSame(0, DemandeReferentiel::query()->count());
    }

    public function test_le_format_de_l_email_est_controle(): void
    {
        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1);

        $this->remplir($composant, ['email' => 'pas-un-email'])->call('enregistrer')
            ->assertSet('erreur', 'Le format de l\'adresse e-mail est invalide.');
        $this->remplir($composant, ['email' => 'a@b'])->call('enregistrer')
            ->assertSet('erreur', 'Le format de l\'adresse e-mail est invalide.');
        $this->remplir($composant, ['email' => ''])->call('enregistrer')->assertSet('erreur', null);
    }

    public function test_le_delai_de_paiement_illisible_ou_nul_vaut_non_fixe_et_le_trop_long_est_refuse(): void
    {
        $this->parametres(['delai_paiement_jours' => 15]);
        $this->travel(5)->seconds();
        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1);

        $this->remplir($composant, ['delaiPaiement' => '4000'])->call('enregistrer')
            ->assertSet('erreur', 'Le délai de paiement ne peut pas dépasser 3 650 jours.');
        $this->assertSame(15, ParametresEntreprise::courant()->delai_paiement_jours);

        $this->remplir($composant, ['delaiPaiement' => '3650'])->call('enregistrer')->assertSet('erreur', null);
        $this->assertSame(3650, ParametresEntreprise::courant()->delai_paiement_jours);

        // « non fixe » : le serveur ignore une valeur vide, l'ancien delai reste (ecart declare).
        $this->travel(5)->seconds();
        $this->remplir($composant, ['delaiPaiement' => 'abc'])->call('enregistrer')->assertSet('erreur', null)
            ->assertSet('delaiPaiement', '3650'); // le formulaire est relu : il montre ce que le serveur a retenu
        $this->assertSame(3650, ParametresEntreprise::courant()->delai_paiement_jours);
    }

    public function test_les_refus_du_serveur_sont_affiches_avec_son_message(): void
    {
        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1);

        $this->remplir($composant, ['raisonSociale' => str_repeat('A', 256)])->call('enregistrer')
            ->assertSet('erreur', 'La raison sociale est trop longue.');
        $this->remplir($composant, ['smtpPort' => 'abc'])->call('enregistrer')
            ->assertSet('erreur', 'Le port SMTP doit être un nombre entier.');
        $this->remplir($composant, ['smtpPort' => '70000'])->call('enregistrer')
            ->assertSet('erreur', 'Le port SMTP est invalide.');

        $demandes = DemandeReferentiel::query()->where('type', 'parametres_entreprise')->get();
        $this->assertCount(3, $demandes);
        $this->assertSame(['refusee'], $demandes->pluck('statut')->unique()->all());
        $this->assertNotSame(str_repeat('A', 256), ParametresEntreprise::courant()->raison_sociale);
    }

    public function test_une_modification_plus_recente_du_serveur_est_refusee_pour_les_parametres(): void
    {
        $p = ParametresEntreprise::courant();
        $p->forceFill(['updated_at' => now()->addHour()])->save();

        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1);
        $this->remplir($composant, ['raisonSociale' => 'AUTRE'])->call('enregistrer')
            ->assertSet('erreur', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.');
        $this->assertSame('ALLMANY ET COMPAGNIE', $p->fresh()->raison_sociale);
    }

    // -------------------------------------------------------------------- MeCeF

    public function test_mecef_exige_l_ifu_et_le_rccm_avant_d_etre_active(): void
    {
        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1)
            ->set('ifu', '123')->set('rccm', '');

        $composant->call('basculerMecef')
            ->assertSet('mecefActif', false)
            ->assertSet('erreur', 'Renseignez l\'IFU et le RCCM avant d\'activer le module MeCeF.')
            ->assertSee('BR-ADM-004 : renseignez l\'IFU et le RCCM pour pouvoir l\'activer.')
            ->assertDontSeeHtml('data-mecef-champs');

        $composant->set('rccm', 'RB/1')->call('basculerMecef')
            ->assertSet('mecefActif', true)->assertSet('erreur', null)
            ->assertSee('IFU et RCCM renseignés — activable.')
            ->assertSeeHtml('data-mecef-champs')->assertSee('URL du service e-MECeF')->assertSee('NIM (Numéro d\'Identification de la Machine)', false);
    }

    public function test_un_formulaire_trafique_ne_contourne_pas_la_regle_mecef(): void
    {
        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1);
        $this->remplir($composant, ['rccm' => ''])->set('mecefActif', true)->call('enregistrer')
            ->assertSet('erreur', 'Renseignez l\'IFU et le RCCM avant d\'activer le module MeCeF.');

        $this->assertSame(0, DemandeReferentiel::query()->count());
        $this->assertFalse((bool) ParametresEntreprise::courant()->mecef_actif);
    }

    public function test_l_activation_mecef_s_enregistre_avec_url_et_nim_et_ouvre_la_facturation(): void
    {
        $admin = $this->admin();
        $this->actingAs($admin)->get('/factures-mecef')->assertNotFound();
        $this->travel(5)->seconds();

        $composant = Livewire::actingAs($admin)->test(ParametresGeneraux::class)->call('choisirOnglet', 1);
        $this->remplir($composant)->call('basculerMecef')->set('mecefUrl', 'https://sygmef.impots.bj')->set('mecefNim', 'EJ0000001')
            ->call('enregistrer')->assertSet('erreur', null);

        $p = ParametresEntreprise::courant();
        $this->assertTrue($p->mecef_actif);
        $this->assertSame('https://sygmef.impots.bj', $p->mecef_url);
        $this->assertSame('EJ0000001', $p->mecef_nim);
        $this->actingAs($admin)->get('/factures-mecef')->assertOk();
    }

    public function test_le_jeton_mecef_n_est_ni_saisi_ni_affiche_ici(): void
    {
        $this->parametres(['ifu' => '123', 'rccm' => 'RB', 'mecef_actif' => true]);

        $composant = Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 1);
        $composant->assertSeeHtml('data-jeton-poste')->assertSee('uniquement sur le poste')
            ->assertDontSeeHtml('type="password"')->assertDontSee('Coller le jeton')->assertDontSee('Enregistrer le jeton');
        $this->assertStringNotContainsStringIgnoringCase('mot de passe smtp :', $composant->html());
    }

    // ---------------------------------------------------------- Autres onglets

    public function test_les_utilisateurs_du_serveur_se_gerent_sans_aucun_secret(): void
    {
        $this->utilisateur('caissier', 'amina');
        $admin = $this->admin();
        $admin->forceFill(['password' => 'Secret-Tres-Long-1'])->save();

        $composant = Livewire::actingAs($admin)->test(ParametresGeneraux::class)->call('choisirOnglet', 2)
            ->assertSee('Gestion des Utilisateurs')->assertSeeHtml('data-compte="amina"')->assertSee('Agent de Vente')
            ->assertSee('Administrateur')->assertSeeHtml('data-ecart="utilisateurs"')->assertSee('Ajouter un Utilisateur');
        $this->assertStringNotContainsString($admin->password, $composant->html());
        $this->assertStringNotContainsString('Secret-Tres-Long-1', $composant->html());
    }

    public function test_les_comptes_ne_sont_pas_listes_sans_manage_users(): void
    {
        $this->utilisateur('caissier', 'amina');

        Livewire::actingAs($this->lecteur())->test(ParametresGeneraux::class)->call('choisirOnglet', 2)
            ->assertDontSeeHtml('data-compte="amina"')->assertDontSee('Ajouter un Utilisateur')->assertSeeHtml('data-ecart="utilisateurs"');
    }

    public function test_les_modes_de_paiement_reprennent_le_texte_du_poste(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 3)
            ->assertSee('Espèces')->assertSee('Mobile Money')->assertSee('Comptant')->assertSee('Avance')
            ->assertSee('Conformément au CDCT, seuls 2 modes de règlement sont retenus')
            ->assertSee('Vente à crédit — suivie dans Clients & Créances');
    }

    public function test_l_appairage_renvoie_vers_la_page_des_postes(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 4)
            ->assertSee('Ouvrir Postes & Appairage')->assertSee(route('postes'), false);
        Livewire::actingAs($this->lecteur())->test(ParametresGeneraux::class)->call('choisirOnglet', 4)
            ->assertDontSee('Ouvrir Postes & Appairage')->assertSee('réservée à l\'administrateur', false);
    }

    public function test_sauvegardes_corbeille_donnees_de_test_se_gerent_sur_le_poste(): void
    {
        $admin = $this->admin();
        foreach ([5 => 'Sauvegardes', 6 => 'Corbeille', 7 => 'Données de Test'] as $index => $titre) {
            Livewire::actingAs($admin)->test(ParametresGeneraux::class)->call('choisirOnglet', $index)
                ->assertSeeHtml('data-ecart="au-poste"')->assertSee($titre)->assertSee('se gère sur le poste')
                ->assertDontSee('REMETTRE A ZERO')->assertDontSeeHtml('<button type="submit"');
        }
    }

    public function test_un_onglet_hors_liste_retombe_sur_les_modules(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 99)
            ->assertSet('onglet', 0)->assertSeeHtml('data-onglet="modules"');
    }

    // -------------------------------------------------------------------- Droits

    public function test_en_lecture_seule_formulaire_desactive_sans_bouton_d_enregistrement(): void
    {
        $this->parametres(['ifu' => '123', 'rccm' => 'RB']);

        Livewire::actingAs($this->lecteur())->test(ParametresGeneraux::class)->call('choisirOnglet', 1)
            ->assertSee('Lecture seule : seul l\'administrateur peut modifier', false)
            ->assertDontSee('Enregistrer les Modifications')->assertSeeHtml('<fieldset disabled');
    }

    public function test_enregistrer_et_basculer_mecef_sont_interdits_sans_manage_parametres(): void
    {
        $this->parametres(['ifu' => '123', 'rccm' => 'RB']);
        $lecteur = $this->lecteur();

        $appel = fn (string $methode, array $args = []) => Livewire::actingAs($lecteur)->test(ParametresGeneraux::class)
            ->call($methode, ...$args)->assertForbidden();

        $appel('enregistrer');
        $appel('basculerMecef');
        $appel('basculerModule', ['bovins', true]);

        $this->assertSame(0, DemandeReferentiel::query()->count());
        $this->assertSame('ALLMANY ET COMPAGNIE', ParametresEntreprise::courant()->raison_sociale);
    }

    public function test_les_droits_sont_separes_parametres_d_un_cote_modules_de_l_autre(): void
    {
        // manage-modules sans manage-parametres : peut basculer une filiere, pas enregistrer la fiche.
        $u = $this->lecteur();
        $u->givePermissionTo('manage-modules');
        $this->travel(5)->seconds();

        Livewire::actingAs($u)->test(ParametresGeneraux::class)->call('basculerModule', 'bovins', true)->assertSet('erreur', null);
        $this->assertTrue(ModuleActif::query()->where('module_id', 'bovins')->value('is_actif'));
        Livewire::actingAs($u)->test(ParametresGeneraux::class)->call('enregistrer')->assertForbidden();
    }
}
