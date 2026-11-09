<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\Devis;
use App\Models\Devis as DevisModele;
use App\Models\User;
use App\Support\ExportXlsx;
use Carbon\CarbonImmutable;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Concerns\LitXlsx;
use Tests\TestCase;

/** `47a2_` — écran web « Devis Prestations » : CRUD par `DevisTable::absorber`, droits, XLSX. */
class DevisWebTest extends TestCase
{
    use LitXlsx, RefreshDatabase;

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

    private function devis(array $surcharge = []): DevisModele
    {
        $d = (new DevisModele)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => 'DV-P1-2026-001',
            'portee_reference' => '', 'client' => 'DOSSOU', 'objet' => 'Poulailler', 'montant_estime' => 150000,
            'validite_jours' => 15, 'date_emission' => now()->subDay(), 'statut' => 'emis', 'supprime_le' => null,
            'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ], $surcharge));
        $d->save();

        return $d;
    }

    private function annee(): string
    {
        return CarbonImmutable::now(config('logialvia.fuseau'))->format('Y');
    }

    private function caisse()
    {
        return Livewire::actingAs($this->utilisateur('caissier', 'caisse'))->test(Devis::class);
    }

    private function creer($c, string $client = 'Mama Rita', string $objet = 'Formation', string $montant = '25000', string $validite = '15')
    {
        return $c->call('nouveau')->set('client', $client)->set('objet', $objet)->set('montant', $montant)->set('validite', $validite)->call('enregistrer');
    }

    // ------------------------------------------------------------------- Accès

    public function test_acces_visiteur_animalier_et_roles_de_vente(): void
    {
        $this->get('/ventes/devis')->assertRedirect(route('login'));
        $this->actingAs($this->utilisateur('animalier', 'eleveur'))->get('/ventes/devis')->assertForbidden();
        $this->actingAs($this->utilisateur('caissier', 'amina'))->get('/ventes/devis')->assertOk()
            ->assertSee('Devis Prestations')->assertDontSee('arrive bientôt');
        $this->actingAs($this->utilisateur('comptable', 'compta'))->get('/ventes/devis')->assertOk();
    }

    public function test_le_lien_depuis_la_page_ventes_n_est_rendu_qu_avec_view_ventes(): void
    {
        $this->actingAs($this->utilisateur('caissier', 'amina'));
        $this->assertStringContainsString('href="/ventes/devis"', view('partiels.lien-devis')->render());
        $this->actingAs($this->utilisateur('animalier', 'eleveur'));
        $this->assertStringNotContainsString('/ventes/devis', view('partiels.lien-devis')->render());
    }

    public function test_la_route_n_est_pas_dans_la_matrice_des_droits_du_poste(): void
    {
        $this->assertArrayNotHasKey('/ventes/devis', config('logialvia.routes'));
    }

    // ------------------------------------------------------------- Création

    public function test_creation_numero_web_poste_web_et_pas_d_effet_de_bord(): void
    {
        $c = $this->caisse();
        $this->creer($c, 'Mama Rita', 'Formation', '25 000,5', '30')->assertSet('formulaire', false)->assertSet('erreur', null);

        $d = DevisModele::query()->firstOrFail();
        $this->assertSame('DV-WEB-'.$this->annee().'-001', $d->reference);
        $this->assertSame(Catalogue::POSTE_WEB, $d->device_id);
        $this->assertSame('', $d->portee_reference);
        $this->assertSame(25000.5, $d->montant_estime);
        $this->assertSame(30, $d->validite_jours);
        $this->assertSame('emis', $d->statut);
        $this->assertNull($d->supprime_le);
        $this->assertSame(0, \App\Models\Vente::query()->count());
        $this->assertSame(0, \App\Models\EcritureComptable::query()->count());

        $this->creer($c);
        $this->assertSame('DV-WEB-'.$this->annee().'-002', DevisModele::query()->orderByDesc('reference')->value('reference'));
    }

    public function test_numerotation_maximum_numerique_supprimes_compris_jamais_renumerote(): void
    {
        $a = $this->annee();
        $this->devis(['reference' => "DV-WEB-$a-999", 'device_id' => Catalogue::POSTE_WEB]);
        $this->devis(['reference' => "DV-WEB-$a-007", 'device_id' => Catalogue::POSTE_WEB, 'supprime_le' => now()]);
        $this->devis(['reference' => "DV-P1-$a-500"]);
        $this->devis(['reference' => "DV-WEB-2020-800", 'device_id' => Catalogue::POSTE_WEB]);

        $c = $this->caisse();
        $this->creer($c);
        $this->assertTrue(DevisModele::query()->where('reference', "DV-WEB-$a-1000")->exists(), '1000 suit 999 (pas de tri textuel)');

        // Le dernier numéro est supprimé : il n'est pas réutilisé.
        $id = DevisModele::query()->where('reference', "DV-WEB-$a-1000")->value('id');
        $c->call('demanderSuppression', $id)->call('confirmerSuppression');
        $this->creer($c);
        $this->assertTrue(DevisModele::query()->where('reference', "DV-WEB-$a-1001")->exists());
        $this->assertSame(1, DevisModele::query()->where('reference', "DV-WEB-$a-1000")->count());
    }

    public function test_validations_du_formulaire(): void
    {
        $c = $this->caisse();
        $cas = [
            ['', 'Formation', '100', '15', 'client'],
            ['X', '  ', '100', '15', 'objet'],
            ['X', 'Y', '0', '15', 'supérieur à 0'],
            ['X', 'Y', '-4', '15', 'supérieur à 0'],
            ['X', 'Y', 'abc', '15', 'supérieur à 0'],
            ['X', 'Y', '100', '0', 'au moins 1 jour'],
            ['X', 'Y', '100', '1.5', 'au moins 1 jour'],
            ['X', 'Y', '100', '99999', '3650'],
        ];
        foreach ($cas as [$client, $objet, $montant, $validite, $extrait]) {
            $this->creer($c, $client, $objet, $montant, $validite)->assertSet('formulaire', true);
            $this->assertStringContainsStringIgnoringCase($extrait, (string) $c->get('erreur'), "$client|$objet|$montant|$validite");
        }
        $this->assertSame(0, DevisModele::query()->count());
    }

    public function test_validite_vide_vaut_quinze_jours(): void
    {
        $this->creer($this->caisse(), 'X', 'Y', '100', '');
        $this->assertSame(15, DevisModele::query()->firstOrFail()->validite_jours);
    }

    // ------------------------------------------------------------ Modification

    public function test_modifier_un_devis_emis_garde_reference_et_emission(): void
    {
        $d = $this->devis(['reference' => 'DV-WEB-2026-004', 'device_id' => Catalogue::POSTE_WEB]);
        $emission = $d->date_emission->format('Y-m-d H:i:s');
        $c = $this->caisse();
        $c->call('modifier', $d->id)->assertSet('formulaire', true)->assertSet('client', 'DOSSOU')->assertSet('montant', '150000')
            ->set('client', 'NOUVEAU')->set('montant', '99')->set('validite', '7')->call('enregistrer')->assertSet('erreur', null);

        $d->refresh();
        $this->assertSame('DV-WEB-2026-004', $d->reference);
        $this->assertSame($emission, $d->date_emission->format('Y-m-d H:i:s'));
        $this->assertSame('NOUVEAU', $d->client);
        $this->assertSame(99.0, $d->montant_estime);
        $this->assertSame(7, $d->validite_jours);
        $this->assertTrue($d->updated_at->greaterThan(now()->subMinute()), 'saisie datée de maintenant : le poste la reprend');
        $this->assertTrue($d->serveur_modifie_le->greaterThan(now()->subMinute()), 'curseur de tirage avancé');
    }

    public function test_un_devis_accepte_ou_refuse_ne_se_modifie_plus(): void
    {
        $c = $this->caisse();
        foreach (['accepte', 'refuse'] as $statut) {
            $d = $this->devis(['reference' => "DV-P1-2026-0$statut", 'statut' => $statut]);
            $c->call('modifier', $d->id)->assertSet('formulaire', false);
            $this->assertStringContainsString('ne se modifie plus', (string) $c->get('message'));
            $this->assertSame('DOSSOU', $d->fresh()->client);
        }
    }

    public function test_modifier_un_devis_inexistant_ou_supprime_ne_fait_rien(): void
    {
        $d = $this->devis(['supprime_le' => now()]);
        $c = $this->caisse();
        $c->call('modifier', $d->id)->assertSet('formulaire', false);
        $c->call('modifier', (string) Str::uuid())->assertSet('formulaire', false);
    }

    // ------------------------------------------------------------------ Statut

    public function test_changer_le_statut(): void
    {
        $d = $this->devis();
        $c = $this->caisse();
        $c->call('changerStatut', $d->id, 'accepte');
        $this->assertSame('accepte', $d->fresh()->statut);
        $c->call('changerStatut', $d->id, 'refuse');
        $this->assertSame('refuse', $d->fresh()->statut, 'le client change d\'avis : le statut se corrige');
        $c->call('changerStatut', $d->id, 'expire');
        $this->assertSame('refuse', $d->fresh()->statut, 'expiré se déduit, il ne se pose pas');
        $this->assertSame('DOSSOU', $d->fresh()->client, 'le contenu n\'a pas bougé');
    }

    // ------------------------------------------------------------- Duplication

    public function test_dupliquer_cree_un_devis_neuf_emis_au_meme_contenu(): void
    {
        $d = $this->devis(['statut' => 'accepte', 'montant_estime' => 777, 'validite_jours' => 9]);
        $this->caisse()->call('dupliquer', $d->id);

        $copie = DevisModele::query()->where('id', '!=', $d->id)->firstOrFail();
        $this->assertSame('DV-WEB-'.$this->annee().'-001', $copie->reference);
        $this->assertSame('emis', $copie->statut);
        $this->assertSame(777.0, $copie->montant_estime);
        $this->assertSame(9, $copie->validite_jours);
        $this->assertSame('DOSSOU', $copie->client);
        $this->assertSame('accepte', $d->fresh()->statut, 'l\'original n\'est pas touché');
    }

    // ------------------------------------------------------------- Suppression

    public function test_supprimer_pose_une_pierre_tombale_et_cache_le_devis(): void
    {
        $d = $this->devis(['statut' => 'refuse']);
        $c = $this->caisse();
        $c->call('demanderSuppression', $d->id)->assertSet('aSupprimer', $d->id)->assertSee('Supprimer ce devis ?');
        $c->call('annuler')->assertSet('aSupprimer', null);
        $this->assertNull($d->fresh()->supprime_le, 'annuler ne supprime rien');

        $c->call('demanderSuppression', $d->id)->call('confirmerSuppression');
        $d->refresh();
        $this->assertNotNull($d->supprime_le, 'la ligne reste : pierre tombale');
        $c->assertDontSeeHtml('data-devis="DV-P1-2026-001"');
    }

    public function test_un_devis_accepte_ne_se_supprime_pas(): void
    {
        $d = $this->devis(['statut' => 'accepte']);
        $c = $this->caisse();
        $c->call('demanderSuppression', $d->id)->assertSet('aSupprimer', null);
        $this->assertStringContainsString('ne se supprime pas', (string) $c->get('message'));
        // Même en forçant l'état : refus (composant et serveur).
        $c->set('aSupprimer', $d->id)->call('confirmerSuppression');
        $this->assertNull($d->fresh()->supprime_le);
        $this->assertStringContainsString('est accepté', (string) $c->get('message'));
    }

    // ------------------------------------------------------------------ Droits

    public function test_aucune_ecriture_sans_manage_ventes_chaque_methode_est_gardee(): void
    {
        $d = $this->devis(['statut' => 'refuse']);
        $comptable = $this->utilisateur('comptable', 'compta');
        $neuf = fn () => Livewire::actingAs($comptable)->test(Devis::class);
        $neuf()->assertDontSee('Générer un Devis')->assertDontSee('Dupliquer')->assertDontSee('Exporter (XLSX)');

        // Un composant NEUF par appel interdit (un 403 invalide l'instance).
        $neuf()->call('nouveau')->assertForbidden();
        $neuf()->call('modifier', $d->id)->assertForbidden();
        $neuf()->call('enregistrer')->assertForbidden();
        $neuf()->call('dupliquer', $d->id)->assertForbidden();
        $neuf()->call('changerStatut', $d->id, 'accepte')->assertForbidden();
        $neuf()->call('demanderSuppression', $d->id)->assertForbidden();
        $neuf()->call('confirmerSuppression')->assertForbidden();
        $neuf()->call('exporter')->assertForbidden();

        $this->assertSame(1, DevisModele::query()->count());
        $this->assertSame('refuse', $d->fresh()->statut);
        $this->assertNull($d->fresh()->supprime_le);
    }

    public function test_les_ecritures_passent_par_la_table_de_synchronisation_pas_par_un_update_direct(): void
    {
        // Un devis ACCEPTE est figé par DevisTable : un client forcé n'y changerait rien.
        $d = $this->devis(['statut' => 'accepte']);
        $c = $this->caisse();
        $c->set('devisId', $d->id)->set('client', 'PIRATE')->set('objet', 'o')->set('montant', '1')->call('enregistrer');
        $this->assertSame('DOSSOU', $d->fresh()->client);
        $this->assertNotNull($c->get('erreur'));
    }

    public function test_un_devis_refuse_ne_s_enregistre_pas_meme_en_forcant_l_etat(): void
    {
        $d = $this->devis(['statut' => 'refuse']);
        $c = $this->caisse();
        $c->set('devisId', $d->id)->set('client', 'PIRATE')->set('objet', 'o')->set('montant', '1')->call('enregistrer');
        $this->assertSame('DOSSOU', $d->fresh()->client);
        $this->assertStringContainsString('ne se modifie plus', (string) $c->get('erreur'));
    }

    // ------------------------------------------------------ Lecture et filtres

    public function test_kpis_filtres_recherche_et_expiration(): void
    {
        $this->devis(['reference' => 'DV-P1-2026-001', 'client' => 'Amina', 'montant_estime' => 1000]);
        $this->devis(['reference' => 'DV-P1-2026-002', 'client' => 'Kofi', 'statut' => 'accepte', 'montant_estime' => 5000]);
        $this->devis(['reference' => 'DV-P1-2026-003', 'client' => 'Zoé', 'statut' => 'refuse', 'montant_estime' => 700]);
        $this->devis(['reference' => 'DV-P1-2026-004', 'client' => 'Vieux', 'date_emission' => now()->subDays(40), 'validite_jours' => 15]);
        $this->devis(['reference' => 'DV-P1-2026-005', 'client' => 'Effacé', 'supprime_le' => now()]);

        $c = Livewire::actingAs($this->utilisateur('caissier', 'amina'))->test(Devis::class);
        $c->assertSeeHtml('data-kpi="nombre">4<')->assertSeeHtml('data-kpi="en-attente">1<')->assertSee('5 000')
            ->assertDontSee('Effacé');
        $c->assertSee('Expiré');

        $c->call('filtrer', 'accepte')->assertSee('Kofi')->assertDontSee('Amina');
        $c->call('filtrer', 'refuse')->assertSee('Zoé')->assertDontSee('Kofi');
        $c->call('filtrer', 'expire')->assertSee('Vieux')->assertDontSee('Amina');
        $c->call('filtrer', 'emis')->assertSee('Amina')->assertDontSee('Vieux');
        $c->call('filtrer', 'nimporte')->assertSet('filtre', '')->assertSee('Kofi');

        $c->set('recherche', 'kof')->assertSee('Kofi')->assertDontSee('Amina');
        $c->set('recherche', '%')->assertSee('Aucun devis ne correspond');
        $c->set('recherche', '2026-003')->assertSee('Zoé');
    }

    public function test_les_dates_sont_dans_le_fuseau_de_l_entreprise(): void
    {
        $this->devis(['date_emission' => CarbonImmutable::parse('2026-11-01 23:30:00', 'UTC'), 'validite_jours' => 10]);
        // 23:30 UTC = 00:30 le 2 novembre au Bénin (UTC+1) ; +10 j = 12/11/2026.
        $this->caisse()->assertSee('12/11/2026');
    }

    public function test_aucune_methode_de_vente_ni_de_comptabilite_dans_le_composant(): void
    {
        $source = file_get_contents(app_path('Livewire/Devis.php'));
        foreach (['EcritureComptable', 'Vente::', 'MouvementProduit', 'Facture'] as $interdit) {
            $this->assertStringNotContainsString($interdit, $source);
        }
    }

    // ------------------------------------------------------------------- XLSX

    public function test_export_xlsx_meme_contenu_que_l_ecran_filtres_compris(): void
    {
        $this->devis(['reference' => 'DV-P1-2026-001', 'client' => 'Amina', 'objet' => 'Puits', 'montant_estime' => 1500.4, 'date_emission' => CarbonImmutable::parse('2026-10-01 23:30:00', 'UTC'), 'validite_jours' => 10]);
        $this->devis(['reference' => 'DV-P1-2026-002', 'client' => 'Kofi', 'statut' => 'accepte', 'montant_estime' => 5000, 'date_emission' => now()]);
        $this->devis(['reference' => 'DV-P1-2026-003', 'client' => 'Caché', 'supprime_le' => now()]);

        $c = $this->caisse();
        $c->call('filtrer', 'accepte')->call('exporter');
        $c->assertFileDownloaded('devis-prestations.xlsx', null, ExportXlsx::TYPE);
        $lignes = $this->lignesXlsx(base64_decode($c->effects['download']['content']));
        $this->assertSame(['Référence', 'Client', 'Objet', 'Montant estimé (FCFA)', 'Émis le', 'Expire le', 'Statut'], $lignes[0]);
        $this->assertCount(2, $lignes, 'le filtre de l\'écran s\'applique, pas les supprimés');
        $this->assertSame(['DV-P1-2026-002', 'Kofi', 'Poulailler', '5000'], array_slice($lignes[1], 0, 4));
        $this->assertSame('Accepté', $lignes[1][6]);

        $c->call('filtrer', '')->call('exporter');
        $lignes = $this->lignesXlsx(base64_decode($c->effects['download']['content']));
        $this->assertCount(3, $lignes);
        $amina = collect($lignes)->firstWhere(0, 'DV-P1-2026-001');
        $this->assertSame('02/10/2026', $amina[4], 'fuseau de l\'entreprise');
        $this->assertSame('12/10/2026', $amina[5]);
        $this->assertSame('Expiré', $amina[6]);
        $this->assertSame('1500', $amina[3], 'montant en cellule numérique entière');
    }

    public function test_export_un_texte_saisi_commencant_par_egal_reste_du_texte(): void
    {
        $this->devis(['client' => '=HYPERLINK("http://x")', 'objet' => '+cmd']);
        $c = $this->caisse();
        $c->call('exporter');
        $lignes = $this->lignesXlsx(base64_decode($c->effects['download']['content']));
        $this->assertSame('=HYPERLINK("http://x")', $lignes[1][1]);
    }
}
