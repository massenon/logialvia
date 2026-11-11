<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\CorbeilleWeb;
use App\Livewire\ParametresGeneraux;
use App\Models\AuditLog;
use App\Models\BaremeRation;
use App\Models\Client;
use App\Models\CycleCouveuse;
use App\Models\EcheanceProphylaxie;
use App\Models\Fournisseur;
use App\Models\MachineIncubateur;
use App\Models\ProduitVendable;
use App\Models\TauxRationPoids;
use App\Models\User;
use App\Models\Vente;
use App\Services\CorbeilleService;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Concerns\LitXlsx;
use Tests\TestCase;

/** Corbeille web : pierres tombales du serveur, restauration par les chemins du poste, purge des comptes (doc 47u §3). */
class CorbeilleWebTest extends TestCase
{
    use LitXlsx, RefreshDatabase;

    private const ANCIEN = '2026-10-01 08:00:00';

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
    }

    private function compte(string $role, string $username): User
    {
        $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
        $u->assignRole($role);

        return $u;
    }

    private function admin(): User
    {
        return $this->compte('admin', 'gerante');
    }

    /** Un compte qui voit les parametres avec un droit d'ecriture precis. */
    private function gestionnaire(string ...$droits): User
    {
        $u = $this->compte('comptable', 'gest'.Str::random(4));
        $u->givePermissionTo('view-parametres', ...$droits);

        return $u;
    }

    private function client(array $s = []): Client
    {
        $c = (new Client)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => 'Amina Bako', 'telephone' => '97000000',
            'solde_creance' => 0, 'updated_at' => self::ANCIEN, 'serveur_modifie_le' => self::ANCIEN, 'supprime_le' => self::ANCIEN,
        ], $s));
        $c->save();

        return $c;
    }

    private function fournisseur(array $s = []): Fournisseur
    {
        $f = (new Fournisseur)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => 'Provenderie Sud', 'telephone' => '97111111',
            'updated_at' => self::ANCIEN, 'serveur_modifie_le' => self::ANCIEN, 'supprime_le' => self::ANCIEN,
        ], $s));
        $f->save();

        return $f;
    }

    private function produit(array $s = []): ProduitVendable
    {
        $p = (new ProduitVendable)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'sku' => 'GOL-1', 'name' => 'Goliath adulte', 'cat' => 'Avicole', 'price' => 5000, 'unit' => 'tête',
            'icon' => 'egg', 'groupe_taxe' => 'A', 'threshold' => 2, 'saisi_le' => self::ANCIEN, 'archive_le' => self::ANCIEN,
        ], $s));
        $p->save();

        return $p;
    }

    private function machine(array $s = []): MachineIncubateur
    {
        $m = (new MachineIncubateur)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'code' => 'INC-01', 'libelle' => 'Incubateur 1', 'capacite_oeufs' => 100,
            'active' => true, 'updated_at' => self::ANCIEN, 'serveur_modifie_le' => self::ANCIEN, 'supprime_le' => null,
        ], $s));
        $m->save();

        return $m;
    }

    private function lot(MachineIncubateur $machine, array $s = []): CycleCouveuse
    {
        $l = (new CycleCouveuse)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'code_incubation' => 'C-P1-2026-001', 'portee_code' => '',
            'espece' => 'goliath', 'date_incubation' => '2026-09-01', 'oeufs_couves' => 50, 'statut' => 'En Incubation', 'machine_id' => $machine->id,
            'updated_at' => self::ANCIEN, 'serveur_modifie_le' => self::ANCIEN, 'supprime_le' => self::ANCIEN,
        ], $s));
        $l->save();

        return $l;
    }

    private function bareme(): BaremeRation
    {
        $b = (new BaremeRation)->forceFill([
            'id' => (string) Str::uuid(), 'espece' => 'Goliath', 'stade' => 'Démarrage', 'ration_grammes_par_jour' => 40, 'confirme' => true,
            'saisi_le' => self::ANCIEN, 'archive_le' => self::ANCIEN,
        ]);
        $b->save();

        return $b;
    }

    private function composant(User $u)
    {
        return Livewire::actingAs($u)->test(CorbeilleWeb::class);
    }

    private function audit(string $action): ?AuditLog
    {
        return AuditLog::query()->where('action', $action)->latest('created_at')->first();
    }

    // ------------------------------------------------------------------- Acces

    public function test_l_onglet_corbeille_est_celui_du_web_et_non_plus_un_renvoi_au_poste(): void
    {
        Livewire::actingAs($this->admin())->test(ParametresGeneraux::class)->call('choisirOnglet', 6)
            ->assertSeeHtml('data-onglet="corbeille"')->assertDontSeeHtml('data-ecart="au-poste"');
    }

    public function test_seul_celui_qui_voit_les_parametres_ouvre_la_corbeille(): void
    {
        foreach (['caissier', 'animalier', 'comptable'] as $i => $role) {
            Livewire::actingAs($this->compte($role, "u$i"))->test(CorbeilleWeb::class)->assertForbidden();
        }
        $this->composant($this->gestionnaire())->assertOk()->assertSee('Corbeille (0)');
    }

    // ----------------------------------------------------------------- Contenu

    public function test_la_liste_montre_tout_ce_qui_porte_une_pierre_tombale_et_rien_d_autre(): void
    {
        $this->client();
        $this->fournisseur();
        $this->produit();
        $this->bareme();
        $machine = $this->machine(); // vivante : pas dans la corbeille
        $this->lot($machine);
        $this->client(['nom' => 'Vivant', 'supprime_le' => null]);
        $supprime = $this->compte('caissier', 'ancien');
        $supprime->delete();

        $c = $this->composant($this->admin())->assertSee('Corbeille (6)')
            ->assertSee('Amina Bako')->assertSee('Provenderie Sud')->assertSee('Goliath adulte')->assertSee('Goliath — Démarrage')
            ->assertSee('C-P1-2026-001 — 50 œufs')->assertSee('Ancien (ancien)')
            ->assertSee('Produit du catalogue')->assertSee('Lot d\'incubation')->assertSee('Barème de rationnement')
            ->assertDontSee('Vivant')->assertDontSee('INC-01');
        $this->assertCount(6, $c->viewData('elements'));
    }

    public function test_la_liste_est_triee_du_plus_recent_au_plus_ancien_et_filtrable(): void
    {
        $this->client(['nom' => 'Vieux', 'supprime_le' => '2026-09-01 08:00:00']);
        $this->client(['nom' => 'Recent', 'supprime_le' => '2026-10-20 08:00:00']);
        $this->fournisseur(['nom' => 'Autre', 'supprime_le' => '2026-10-10 08:00:00']);

        $c = $this->composant($this->admin())->assertSeeInOrder(['Recent', 'Autre', 'Vieux']);
        $c->set('type', 'clients')->assertSee('Vieux')->assertDontSee('Autre');
        $c->set('type', '')->set('recherche', 'auTRE')->assertSee('Autre')->assertDontSee('Vieux');
    }

    public function test_l_origine_est_le_poste_ou_le_web(): void
    {
        $poste = \App\Models\Poste::query()->create(['device_id' => ($device = (string) Str::uuid()), 'code' => 'P2']);
        $this->client(['device_id' => $device, 'nom' => 'Du poste']);
        $this->client(['device_id' => Catalogue::POSTE_WEB, 'nom' => 'Du web']);

        $html = $this->composant($this->admin())->html();
        $this->assertMatchesRegularExpression('/Du poste.*?P2/s', $html);
        $this->assertMatchesRegularExpression('/Du web.*?Web/s', $html);
        $this->assertNotNull($poste);
    }

    public function test_corbeille_vide(): void
    {
        $this->composant($this->admin())->assertSee('La corbeille est vide.');
    }

    // ------------------------------------------------------------ Restauration

    public function test_restaurer_un_client_leve_la_pierre_tombale_et_redescend_aux_postes(): void
    {
        $admin = $this->admin();
        $client = $this->client();

        $this->composant($admin)->call('restaurer', 'clients', $client->id)->assertSet('erreur', null)->assertSee('Élément restauré')
            ->assertDontSee('Amina Bako');

        $c = $client->fresh();
        $this->assertNull($c->supprime_le);
        $this->assertSame(Catalogue::POSTE_WEB, $c->device_id);
        $this->assertTrue($c->serveur_modifie_le->greaterThan(\Carbon\Carbon::parse(self::ANCIEN)), 'le curseur de tirage avance');
        $this->assertSame('Amina Bako', $c->nom);
        $audit = $this->audit('corbeille.restaure');
        $this->assertSame(['type' => 'clients', 'id' => $client->id, 'designation' => 'Amina Bako'], $audit->detail);
    }

    public function test_restaurer_un_fournisseur_un_lot_un_produit_et_un_bareme(): void
    {
        $admin = $this->admin();
        $four = $this->fournisseur();
        $lot = $this->lot($this->machine());
        $produit = $this->produit();
        $bareme = $this->bareme();

        $c = $this->composant($admin);
        foreach ([['fournisseurs', $four->id], ['lots', $lot->id], ['produits', $produit->id], ['baremes', $bareme->id]] as [$type, $id]) {
            $c->call('restaurer', $type, $id)->assertSet('erreur', null);
        }

        $this->assertNull($four->fresh()->supprime_le);
        $this->assertNull($lot->fresh()->supprime_le);
        $this->assertSame(50, $lot->fresh()->oeufs_couves);
        $this->assertNull($produit->fresh()->archive_le);
        $this->assertSame(5000.0, $produit->fresh()->price);
        $this->assertTrue($produit->fresh()->saisi_le->greaterThan(\Carbon\Carbon::parse(self::ANCIEN)));
        $this->assertNull($bareme->fresh()->archive_le);
        $this->assertSame(40, $bareme->fresh()->ration_grammes_par_jour);
    }

    public function test_restaurer_un_taux_et_une_echeance(): void
    {
        $taux = (new TauxRationPoids)->forceFill([
            'id' => (string) Str::uuid(), 'espece' => 'Ovins', 'poids_min_g' => 0, 'poids_max_g' => 100000, 'taux_pourcent' => 2.5, 'confirme' => false,
            'saisi_le' => self::ANCIEN, 'archive_le' => self::ANCIEN,
        ]);
        $taux->save();
        $echeance = (new EcheanceProphylaxie)->forceFill([
            'id' => (string) Str::uuid(), 'espece' => 'Goliath', 'jour_cycle' => 7, 'traitement' => 'Vaccin', 'produit' => 'Newcastle', 'remanence_jours' => 0,
            'dose' => null, 'saisi_le' => self::ANCIEN, 'archive_le' => self::ANCIEN,
        ]);
        $echeance->save();

        $c = $this->composant($this->admin())->assertSee('Ovins — à partir de 0 g')->assertSee('Goliath — J7 Vaccin');
        $c->call('restaurer', 'taux', $taux->id)->assertSet('erreur', null);
        $c->call('restaurer', 'echeances', $echeance->id)->assertSet('erreur', null);
        $this->assertNull($taux->fresh()->archive_le);
        $this->assertNull($echeance->fresh()->archive_le);
    }

    public function test_une_pierre_tombale_datee_dans_le_futur_se_restaure_quand_meme(): void
    {
        $client = $this->client(['updated_at' => now()->addDay()->format('Y-m-d H:i:s.u'), 'supprime_le' => now()->addDay()]);

        $this->composant($this->admin())->call('restaurer', 'clients', $client->id)->assertSet('erreur', null);
        $this->assertNull($client->fresh()->supprime_le, 'poste en avance sur l\'horloge : l\'ecriture passe apres la pierre tombale');
    }

    public function test_la_restauration_applique_la_validation_du_serveur_et_dit_pourquoi(): void
    {
        $machine = $this->machine();
        $lot = $this->lot($machine);
        $machine->delete(); // incubateur disparu : le lot ne peut pas revenir (meme regle que pour un poste)

        $this->composant($this->admin())->call('restaurer', 'lots', $lot->id)->assertSet('erreur', \App\Sync\Tables\CyclesCouveuseTable::MOTIF_MACHINE);
        $this->assertNotNull($lot->fresh()->supprime_le);
        $this->assertNull($this->audit('corbeille.restaure'));
    }

    public function test_restaurer_un_element_deja_revenu_ou_inconnu_est_refuse(): void
    {
        $c = $this->composant($this->admin());
        $client = $this->client(['supprime_le' => null]);
        $c->call('restaurer', 'clients', $client->id)->assertSet('erreur', 'Cet élément n\'est plus en corbeille.');
        $c->call('restaurer', 'clients', (string) Str::uuid())->assertSet('erreur', 'Cet élément n\'est plus en corbeille.');
        $c->call('restaurer', 'tables_secretes', $client->id)->assertSet('erreur', 'Type d\'élément inconnu : tables_secretes.');
    }

    public function test_restaurer_un_compte_est_reserve_a_l_administrateur(): void
    {
        $cible = $this->compte('caissier', 'ancien');
        $cible->delete();
        $gest = $this->gestionnaire('manage-users');

        $this->composant($gest)->assertSee('Administrateur seul')->assertDontSeeHtml("restaurer('utilisateurs'");
        $this->composant($gest)->call('restaurer', 'utilisateurs', $cible->id)
            ->assertSet('erreur', 'Seul un administrateur peut restaurer un élément de type « Utilisateur ».');
        $this->assertNull(User::query()->find($cible->id));

        $this->composant($this->admin())->call('restaurer', 'utilisateurs', $cible->id)->assertSet('erreur', null);
        $this->assertNotNull(User::query()->find($cible->id));
    }

    public function test_le_droit_d_ecriture_de_l_element_est_exige_pour_restaurer(): void
    {
        $client = $this->client();
        $four = $this->fournisseur();
        $produit = $this->produit();
        $lot = $this->lot($this->machine());
        $bareme = $this->bareme();
        $lecteur = $this->gestionnaire(); // voit la corbeille, n'ecrit nulle part
        $admin = $this->admin();

        $c = $this->composant($lecteur)->assertDontSeeHtml("restaurer('");
        foreach ([['clients', $client->id], ['fournisseurs', $four->id], ['produits', $produit->id], ['lots', $lot->id], ['baremes', $bareme->id]] as [$type, $id]) {
            $neuf = Livewire::actingAs($admin)->test(CorbeilleWeb::class);
            $this->actingAs($lecteur);
            $neuf->call('restaurer', $type, $id)->assertForbidden();
        }
        $this->assertNotNull($client->fresh()->supprime_le);
        $this->assertNotNull($four->fresh()->supprime_le);
        $this->assertNotNull($produit->fresh()->archive_le);
        $this->assertNotNull($lot->fresh()->supprime_le);
        $this->assertNotNull($bareme->fresh()->archive_le);

        // Chaque droit ouvre SON type : manage-ventes -> client et produit, manage-achats -> fournisseur, manage-elevage -> lot et bareme.
        $vendeur = $this->gestionnaire('manage-ventes');
        $this->composant($vendeur)->call('restaurer', 'clients', $client->id)->assertSet('erreur', null);
        $this->composant($vendeur)->call('restaurer', 'produits', $produit->id)->assertSet('erreur', null);
        $this->composant($this->gestionnaire('manage-achats'))->call('restaurer', 'fournisseurs', $four->id)->assertSet('erreur', null);
        $eleveur = $this->gestionnaire('manage-elevage');
        $this->composant($eleveur)->call('restaurer', 'lots', $lot->id)->assertSet('erreur', null);
        $this->composant($eleveur)->call('restaurer', 'baremes', $bareme->id)->assertSet('erreur', null);
        $this->assertNotNull($c);
    }

    public function test_le_service_reverifie_le_droit_sans_passer_par_le_composant(): void
    {
        $client = $this->client();
        $sansRien = $this->compte('caissier', 'caisse');
        $service = app(CorbeilleService::class);

        foreach ([fn () => $service->restaurer($sansRien, 'clients', $client->id), fn () => $service->purger($sansRien, 'utilisateurs', 'x')] as $appel) {
            try {
                $appel();
                $this->fail('403 attendu');
            } catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) {
                $this->assertSame(403, $e->getStatusCode());
            }
        }
        $this->assertNotNull($client->fresh()->supprime_le);
    }

    // -------------------------------------------------------------------- Purge

    public function test_purger_un_compte_archive_est_reserve_a_l_administrateur_et_se_confirme(): void
    {
        $cible = $this->compte('caissier', 'ancien');
        $cible->delete();
        $admin = $this->admin();

        $c = $this->composant($admin)->call('demanderPurge', 'utilisateurs', $cible->id)->assertSee('Effacer définitivement ?');
        $this->assertNotNull(User::onlyTrashed()->find($cible->id), 'rien n\'est efface avant la confirmation');
        $c->call('annuler')->assertSet('purgeAConfirmer', null)->assertDontSee('Effacer définitivement ?');
        $c->call('demanderPurge', 'utilisateurs', $cible->id)->call('confirmerPurge')->assertSet('erreur', null)->assertSee('effacé définitivement');
        $this->assertNull(User::withTrashed()->find($cible->id));
        $this->assertNotNull($this->audit('utilisateur.purge'));

        // Un gestionnaire non administrateur n'a pas le bouton et le service refuse.
        $autre = $this->compte('caissier', 'autre');
        $autre->delete();
        $gest = $this->gestionnaire('manage-users');
        $this->composant($gest)->assertDontSee('Effacer')
            ->call('demanderPurge', 'utilisateurs', $autre->id)->call('confirmerPurge')->assertSet('erreur', 'Seul un administrateur peut vider la corbeille.');
        $this->assertNotNull(User::onlyTrashed()->find($autre->id));
    }

    public function test_les_autres_pierres_tombales_ne_s_effacent_jamais(): void
    {
        $client = $this->client();
        $admin = $this->admin();

        $c = $this->composant($admin)->assertDontSeeHtml("demanderPurge('clients'");
        $c->call('demanderPurge', 'clients', $client->id)->call('confirmerPurge')
            ->assertSet('erreur', 'Un élément de type « Client » ne s\'efface jamais définitivement au serveur : sa pierre tombale empêche un poste hors ligne de le ressusciter.');
        $this->assertNotNull(Client::query()->find($client->id));
    }

    public function test_les_ventes_gardent_leur_client_apres_restauration(): void
    {
        $client = $this->client();
        $vente = (new Vente)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => 'V-P1-2026-001', 'portee_reference' => '',
            'client' => $client->nom, 'client_id' => $client->id, 'date_vente' => now(), 'mode' => 'Espèces', 'status' => 'Payée',
            'total' => 1000, 'paye' => 1000, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $vente->save();

        $this->composant($this->admin())->call('restaurer', 'clients', $client->id);
        $this->assertSame($client->id, $vente->fresh()->client_id);
    }

    // ------------------------------------------------------------------- Export

    public function test_l_export_xlsx_reprend_l_ecran_filtre_et_exige_le_droit(): void
    {
        $this->client(['nom' => '=1+1']);
        $this->fournisseur();
        $admin = $this->admin();

        $c = $this->composant($admin)->set('type', 'clients')->call('exporter');
        $c->assertFileDownloaded('corbeille.xlsx', null, \App\Support\ExportXlsx::TYPE);
        $lignes = $this->lignesXlsx(base64_decode($c->effects['download']['content']));
        $this->assertSame(['Module', 'Type', 'Désignation', 'Archivé le (UTC)', 'Origine'], $lignes[0]);
        $this->assertCount(2, $lignes, 'titre + le seul client (filtre de type)');
        $this->assertSame(['Commercial', 'Client', '=1+1', '2026-10-01 08:00:00'], array_slice($lignes[1], 0, 4), 'jamais evalue comme formule');

        $neuf = Livewire::actingAs($admin)->test(CorbeilleWeb::class);
        $this->actingAs($this->compte('caissier', 'caisse'));
        $neuf->call('exporter')->assertForbidden();
    }

    public function test_les_methodes_d_ecriture_reverifient_le_droit(): void
    {
        $client = $this->client();
        $admin = $this->admin();
        $intrus = $this->compte('caissier', 'caisse');

        foreach ([['restaurer', ['clients', $client->id]], ['demanderPurge', ['utilisateurs', 'x']], ['confirmerPurge', []], ['annuler', []]] as [$methode, $args]) {
            $neuf = Livewire::actingAs($admin)->test(CorbeilleWeb::class);
            $this->actingAs($intrus);
            $neuf->call($methode, ...$args)->assertForbidden();
        }
        $this->assertNotNull($client->fresh()->supprime_le);
    }
}
