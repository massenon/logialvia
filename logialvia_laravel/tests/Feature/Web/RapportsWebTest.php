<?php

namespace Tests\Feature\Web;

use App\Livewire\Rapports;
use App\Models\User;
use App\Support\Ecrans;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Features\SupportTesting\Testable;
use Livewire\Livewire;
use Tests\Concerns\JeuRapports;
use App\Support\ExportXlsx;
use Tests\Concerns\LitXlsx;
use Tests\TestCase;

/**
 * Ecran web « Rapports & États » : acces par role, onglets, periode, encart Stocks sans chiffre, export XLSX
 * protege par `export-rapports`, ecarts declares. Les chiffres de chaque rapport sont verifies dans
 * `RapportsFinancesWebTest`, `RapportsTiersWebTest` et `RapportsElevageWebTest`.
 */
class RapportsWebTest extends TestCase
{
    use JeuRapports, LitXlsx, RefreshDatabase;

    private const ONGLETS = ['recettes', 'tresorerie', 'creances', 'dettes', 'elevage', 'stocks'];

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerRapports();
    }

    private function rapport(string $role = 'comptable', string $onglet = 'recettes'): Testable
    {
        $this->actingAs($this->utilisateurRapports($role, $role));

        return Livewire::test(Rapports::class)->set('onglet', $onglet);
    }

    /** Classeur xlsx telecharge : lignes de cellules (nombre ou texte, en chaine). @return list<list<string>> */
    private function xlsx(Testable $c): array
    {
        return $this->lignesXlsx(base64_decode($c->effects['download']['content']));
    }

    // ------------------------------------------------------------------ Acces

    public function test_visiteur_caissier_et_animalier_n_ouvrent_pas_les_rapports(): void
    {
        $this->get('/rapports')->assertRedirect('/login');

        foreach (['caissier', 'animalier'] as $role) {
            $this->actingAs($this->utilisateurRapports($role, $role));
            $this->get('/rapports')->assertForbidden();
        }
    }

    public function test_le_comptable_et_l_administrateur_ouvrent_le_vrai_ecran(): void
    {
        foreach (['comptable', 'admin'] as $role) {
            $this->actingAs($this->utilisateurRapports($role, $role));
            $this->get('/rapports')->assertOk()->assertSee('Rapports &amp; États', false)->assertDontSee('Cet écran arrive bientôt');
        }
    }

    public function test_l_ecran_est_declare_au_registre_avec_son_droit(): void
    {
        $this->assertContains('/rapports', Ecrans::declarees());
        $route = collect(\Illuminate\Support\Facades\Route::getRoutes()->getRoutes())->first(fn ($r) => $r->uri() === 'rapports');
        $this->assertContains('can:view-rapports', $route->gatherMiddleware());
    }

    public function test_le_composant_refuse_aussi_un_compte_sans_droit_de_lecture(): void
    {
        // Chaque appel Livewire revalide : un composant neuf, sans passer par la route, est refuse.
        $this->actingAs($this->utilisateurRapports('caissier', 'caissier'));
        Livewire::test(Rapports::class)->assertForbidden();
    }

    public function test_un_compte_qui_ne_fait_que_lire_n_a_aucun_bouton_d_export(): void
    {
        $lecteur = User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-rapports');
        $this->actingAs($lecteur);

        foreach (self::ONGLETS as $onglet) {
            Livewire::test(Rapports::class)->set('onglet', $onglet)->assertOk()->assertDontSeeHtml('data-action="exporter"');
        }
        Livewire::test(Rapports::class)->assertSeeHtml('data-champ="debut"');
    }

    // ------------------------------------------------------------------ Coque et onglets

    public function test_les_six_onglets_ont_les_titres_du_poste_et_chacun_s_ouvre(): void
    {
        $c = $this->rapport();
        $this->assertSame(
            ['Recettes et Dépenses', 'État de Trésorerie', 'Créances Clients', 'Dettes Fournisseurs', 'Rapport Élevage', 'Rapport de Stocks'],
            $this->textes($c, "//*[@data-onglets]/button"),
        );

        foreach (self::ONGLETS as $onglet) {
            $c->call('choisirOnglet', $onglet)->assertSet('onglet', $onglet)->assertSeeHtml('data-onglet-actif="'.$onglet.'"');
        }
    }

    public function test_un_onglet_inconnu_retombe_sur_les_recettes(): void
    {
        $c = $this->rapport()->call('choisirOnglet', 'nimporte-quoi');
        $c->assertSet('onglet', 'recettes')->assertSeeHtml('data-onglet-actif="recettes"');

        $c = $this->rapport()->set('onglet', 'pirate');
        $c->assertSeeHtml('data-onglet-actif="recettes"');
    }

    public function test_le_poste_ouvre_le_mois_en_cours_et_la_periode_survit_au_changement_d_onglet(): void
    {
        $c = $this->rapport();
        $c->assertSet('debut', '2026-11-01')->assertSet('fin', '2026-11-18')->assertSee('États de synthèse, période du 01/11/2026 au 18/11/2026.');

        $c->set('debut', '2026-10-15')->call('choisirOnglet', 'tresorerie')->assertSet('debut', '2026-10-15')
            ->assertSee('période du 15/10/2026 au 18/11/2026');
    }

    // ------------------------------------------------------------------ Stocks

    public function test_l_onglet_stocks_est_un_encart_grise_sans_aucun_chiffre(): void
    {
        // Des produits existent au serveur (catalogue) : aucun n'est montre, ni valeur, ni quantite, ni PMP.
        $this->produit('Poulet vedette');
        $c = $this->rapport('comptable', 'stocks');

        $c->assertSeeHtml('data-encart="stocks"')->assertSee('Disponible sur le poste');
        $this->assertCount(3, $this->textes($c, "//*[@data-carte-poste]"));
        $this->assertSame(['Valeur Totale du Stock', 'Articles en Alerte', 'Références Actives'], $this->textes($c, "//*[@data-carte-poste]/p[1]"));
        $texte = $this->texte($c, "//*[@data-onglet-actif='stocks']");
        $this->assertSame(0, preg_match('/\d/', $texte), 'aucun chiffre dans l\'onglet Stocks : '.$texte);
        $this->assertStringNotContainsString('FCFA', $texte);
        $this->assertStringNotContainsString('Poulet vedette', $texte);
        $c->assertDontSeeHtml('data-action="exporter"');
        $this->assertCount(3, $this->textes($c, "//*[@data-carte-poste]/p[contains(@class,'text-kpi-value')][text()='—']"));
    }

    public function test_exporter_les_stocks_ne_produit_aucun_fichier(): void
    {
        $this->rapport('comptable', 'stocks')->call('exporter')->assertNoFileDownloaded();
    }

    // ------------------------------------------------------------------ Export XLSX

    private function poserPetitJeu(): void
    {
        $this->piece('2026-11-05 09:00:00', [['571', 1000, 0], ['702', 0, 1000]], 'V-1', ['vente_ref' => 'V-1']);
        $this->piece('2026-11-06 09:00:00', [['618', 400, 0], ['571', 0, 400]], 'D-1');
    }

    public function test_export_xlsx_des_recettes_avec_les_memes_chiffres_que_l_ecran(): void
    {
        $this->poserPetitJeu();
        $c = $this->rapport('comptable', 'recettes')->call('exporter');

        $c->assertFileDownloaded('rapport-recettes-20261101-20261118.xlsx', null, ExportXlsx::TYPE);
        $this->assertSame([
            ['Recettes et Dépenses'],
            ['Période', 'du 01/11/2026 au 18/11/2026'],
            [],
            ['Total Recettes', '1000'],
            ['Total Dépenses', '400'],
            ['Résultat Net', '600'],
            ['Taux de Marge Brute', '60,0 %'],
            [],
            ['Période', 'N° Pièce', 'Catégorie SYSCOHADA', 'Centre de Profit', 'Encaissement', 'Décaissement', 'Solde Cumulé'],
            ['Novembre 2026', 'D-1', '618 - Autres frais de transport', 'Charge Générale', '0', '400', '-400'],
            ['Novembre 2026', 'V-1', '702 - Ventes de produits finis', 'Aviculture', '1000', '0', '600'],
        ], $this->xlsx($c));
    }

    public function test_l_export_suit_les_filtres_et_la_periode_de_l_ecran(): void
    {
        $this->poserPetitJeu();
        $c = $this->rapport('comptable', 'recettes')->set('filtreCentre', 'Aviculture')->set('debut', '2026-11-05')->set('fin', '2026-11-05')->call('exporter');

        $c->assertFileDownloaded('rapport-recettes-20261105-20261105.xlsx');
        $lignes = $this->xlsx($c);
        $this->assertSame(['Total Recettes', '1000'], $lignes[3]);
        $this->assertSame(['Total Dépenses', '0'], $lignes[4]);
        // Une seule ligne de detail : le centre Aviculture ce jour-la.
        $this->assertSame(['Novembre 2026', 'V-1', '702 - Ventes de produits finis', 'Aviculture', '1000', '0', '1000'], $lignes[9]);
        $this->assertCount(10, $lignes);
    }

    public function test_export_xlsx_de_la_tresorerie(): void
    {
        $this->poserPetitJeu();
        $this->piece('2026-10-01 10:00:00', [['571', 5000, 0], ['101', 0, 5000]], 'OD-1');
        $c = $this->rapport('comptable', 'tresorerie')->call('exporter');

        $lignes = $this->xlsx($c);
        $this->assertSame(['État de Trésorerie'], $lignes[0]);
        $this->assertSame(['Mobile Money', '0'], $lignes[3]);
        $this->assertSame(['Caisse', '5600'], $lignes[4]);                 // 5 000 + 1 000 - 400
        $this->assertSame(['Trésorerie Nette', '5600'], $lignes[5]);
        $this->assertSame(['Date', 'Compte', "Type d'Opération", 'Libellé', 'Entrée', 'Sortie', 'Solde Progressif'], $lignes[7]);
        $this->assertSame(['01/11/2026', 'Mobile Money', "Solde d'Ouverture", '', '', '', '0'], $lignes[8]);
        $this->assertSame(['01/11/2026', 'Caisse', "Solde d'Ouverture", '', '', '', '5000'], $lignes[9]);
        $this->assertSame(['05/11/2026', 'Caisse', 'Vente POS', 'Libelle V-1', '1000', '0', '6000'], $lignes[10]);
        $this->assertSame(['06/11/2026', 'Caisse', 'Décaissement Divers', 'Libelle D-1', '0', '400', '5600'], $lignes[11]);
    }

    public function test_export_xlsx_des_creances_des_dettes_et_de_l_elevage(): void
    {
        $this->client('Amina Bako', 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');
        $this->vente(['reference' => 'V-C1', 'client' => 'Amina Bako', 'client_id' => 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa', 'status' => 'Avance',
            'date_vente' => $this->loc('2026-11-02 09:00:00'), 'total' => 50000, 'paye' => 20000, 'echeance' => $this->loc('2026-11-10 12:00:00')]);
        $f = $this->fournisseur('Provenderie', 'f1f1f1f1-1111-4111-8111-f1f1f1f1f1f1');
        $this->achat($f, ['reference' => 'A1', 'date_achat' => $this->loc('2026-11-02 09:00:00'), 'total' => 80000, 'paye' => 30000]);
        (new \App\Models\CycleCouveuse)->forceFill([
            'id' => (string) \Illuminate\Support\Str::uuid(), 'code_incubation' => 'LOT-A', 'portee_code' => '', 'espece' => 'pintade',
            'date_incubation' => '2026-11-01', 'oeufs_couves' => 40, 'poussins_nes' => 30, 'statut' => 'Éclosion Effectuée',
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ])->save();

        $creances = $this->xlsx($this->rapport('comptable', 'creances')->call('exporter'));
        $this->assertSame(['Créances En Cours', '30000'], $creances[3]);
        $this->assertSame(['Créances en Retard', '30000'], $creances[4]);
        $this->assertSame(['Taux de Recouvrement', '40,0 %'], $creances[6]);
        $this->assertSame(['CLI-AAAAAAAA', 'Amina Bako', 'V-C1', '02/11/2026', '10/11/2026', '50000', '20000', '30000', '8j', 'En Retard'], $creances[9]);

        $dettes = $this->xlsx($this->rapport('comptable', 'dettes')->call('exporter'));
        $this->assertSame(['Total Dettes Fournisseurs', '50000'], $dettes[3]);
        $this->assertSame(['FRN-F1F1F1F1', 'Provenderie', 'A1', '02/11/2026', '—', '80000', '30000', '50000', 'Sans échéance'], $dettes[8]);

        $elevage = $this->xlsx($this->rapport('comptable', 'elevage')->call('exporter'));
        $this->assertContains(['Taux Éclosion Moyen', '75,0 %'], $elevage);
        // Pintade : 01/11 + 28 jours = 29/11.
        $this->assertContains(['LOT-A', '01/11/2026', '29/11/2026', '40', '30', '75,0 %', '10', 'Éclosion Effectuée'], $elevage);
    }

    public function test_l_export_ne_produit_jamais_de_formule_de_tableur(): void
    {
        $this->vente(['reference' => 'V-F', 'client' => '=HYPERLINK("http://x")', 'status' => 'Avance', 'total' => 100, 'paye' => 0]);
        $this->vente(['reference' => 'V-G', 'client' => '-2+3', 'status' => 'Avance', 'total' => 100, 'paye' => 0, 'date_vente' => $this->loc('2026-11-11 10:00:00')]);
        $c = $this->rapport('comptable', 'creances')->call('exporter');
        $octets = base64_decode($c->effects['download']['content']);
        $lignes = $this->lignesXlsx($octets);

        // Texte INTACT (pas d'apostrophe) : une cellule texte n'est jamais evaluee.
        $clients = array_column(array_slice($lignes, 9), 1);
        $this->assertContains('=HYPERLINK("http://x")', $clients);
        $this->assertContains('-2+3', $clients);
        $ligne = array_search('=HYPERLINK("http://x")', array_column($lignes, 1), true);
        $this->assertSame('inlineStr', $this->natureCellule($octets, 'B'.($ligne + 1)));
        $zip = new \ZipArchive;
        $chemin = tempnam(sys_get_temp_dir(), 't');
        file_put_contents($chemin, $octets);
        $zip->open($chemin);
        $this->assertStringNotContainsString('<f>', (string) $zip->getFromName('xl/worksheets/sheet1.xml'));
        $zip->close();
        @unlink($chemin);

        // Les montants negatifs sont de vrais nombres.
        $this->piece('2026-11-05 09:00:00', [['618', 400, 0], ['571', 0, 400]], 'D-1');
        $recettes = $this->rapport('comptable', 'recettes')->call('exporter');
        $octetsR = base64_decode($recettes->effects['download']['content']);
        $this->assertContains('-400', $this->lignesXlsx($octetsR)[9]);
        $this->assertSame('n', $this->natureCellule($octetsR, 'G10'));
    }

    public function test_l_export_exige_le_droit_export_rapports_dans_la_methode(): void
    {
        // Voir sans exporter : composant neuf, appel direct de la methode -> 403.
        $lecteur = User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-rapports');
        $this->actingAs($lecteur);
        Livewire::test(Rapports::class)->call('exporter')->assertForbidden();
        foreach (self::ONGLETS as $onglet) {
            Livewire::test(Rapports::class)->set('onglet', $onglet)->call('exporter')->assertForbidden();
        }

        // Exporter sans voir : refuse aussi (l'export donne les memes donnees que la lecture).
        $exportateur = User::factory()->create(['username' => 'exportateur']);
        $exportateur->givePermissionTo('export-rapports');
        $this->actingAs($exportateur);
        Livewire::test(Rapports::class)->assertForbidden();

        // Meme chose pour un compte qui ne peut qu'exporter.
        $c = $this->rapport('admin', 'recettes');
        $this->actingAs($exportateur);
        $c->call('exporter')->assertForbidden();

        // Le droit est revalide a CHAQUE appel : un composant monte par un administrateur, repris par un compte sans droit.
        $c = $this->rapport('admin', 'recettes');
        $this->actingAs($this->utilisateurRapports('caissier', 'caissier'));
        $c->call('exporter')->assertForbidden();
    }

    public function test_une_periode_inversee_est_remise_d_aplomb_meme_sans_passer_par_les_crochets(): void
    {
        $this->actingAs($this->utilisateurRapports('comptable', 'paul'));
        $composant = new Rapports;
        $composant->debut = '2026-11-18';
        $composant->fin = '2026-11-01';
        $m = new \ReflectionMethod($composant, 'periode');
        [$d, $f, $valide] = $m->invoke($composant);

        $this->assertSame(['2026-11-01 00:00:00', '2026-11-18 23:59:59', true], [$d->format('Y-m-d H:i:s'), $f->format('Y-m-d H:i:s'), $valide]);
    }

    public function test_le_bouton_d_export_n_est_propose_qu_avec_le_droit(): void
    {
        $this->rapport('admin', 'recettes')->assertSeeHtml('data-action="exporter"');
        $this->rapport('comptable', 'dettes')->assertSeeHtml('data-action="exporter"');
    }

    // ------------------------------------------------------------------ Ecarts et design

    public function test_chaque_onglet_declare_ses_ecarts_avec_le_poste(): void
    {
        $attendus = [
            'recettes' => ['lecture', 'piece'],
            'tresorerie' => ['lecture', 'ordre'],
            'creances' => ['lecture', 'code', 'relance'],
            'dettes' => ['lecture', 'code', 'annules'],
            'elevage' => ['lecture', 'statuts', 'pintade', 'fiches'],
            'stocks' => ['lecture', 'stock'],
        ];
        foreach ($attendus as $onglet => $points) {
            $c = $this->rapport('comptable', $onglet)->assertSeeHtml('data-ecart="'.$onglet.'"');
            foreach ($points as $p) {
                $c->assertSeeHtml('data-ecart-point="'.$p.'"');
            }
        }
        $this->rapport('comptable', 'dettes')->assertSee('Annulé')->assertSee('correction à faire au poste');
        $this->rapport('comptable', 'recettes')->assertSee('XLSX')->assertDontSee('CSV')->assertSee('PDF');
    }

    public function test_les_vues_n_ont_aucune_couleur_en_dur_et_n_utilisent_que_les_jetons(): void
    {
        $tokens = ['brand-navy', 'brand-navy-dark', 'brand-gold', 'surface-card', 'surface-zebra', 'outline-variant', 'outline', 'on-surface',
            'error-deep', 'error-container', 'success-deep', 'success-container', 'info-blue', 'surface-bg', 'white', 'transparent'];
        foreach (glob(resource_path('views/livewire/rapports/*.blade.php')) as $fichier) {
            $source = preg_replace('/\{\{--.*?--\}\}/s', '', file_get_contents($fichier));
            $this->assertSame(0, preg_match('/#[0-9a-fA-F]{3,8}\b|rgb\(|style="[^"]*color/', $source), basename($fichier).' : couleur en dur');
            $this->assertSame(0, preg_match('/(?:bg|border)-\[|text-\[(?!\d+px\])/', $source), basename($fichier).' : valeur arbitraire');
            preg_match_all('/\b(?:bg|text|border)-(brand-[a-z-]+|surface-[a-z]+|outline(?:-variant)?|on-surface|error-[a-z]+|success-[a-z]+|info-blue|white|transparent)\b/', $source, $m);
            foreach (array_unique($m[1]) as $couleur) {
                $this->assertContains($couleur, $tokens, basename($fichier).' : jeton inconnu '.$couleur);
            }
        }
    }

    public function test_les_tableaux_sont_masques_sous_640_px_au_profit_des_cartes(): void
    {
        foreach (glob(resource_path('views/livewire/rapports/_*.blade.php')) as $fichier) {
            $source = file_get_contents($fichier);
            if (str_contains($source, '<table')) {
                $this->assertSame(substr_count($source, '<table'), substr_count($source, 'hidden overflow-x-auto sm:block'), basename($fichier).' : tableau sans bascule 640 px');
                $this->assertSame(substr_count($source, '<table'), substr_count($source, 'data-vue="cartes"'), basename($fichier).' : tableau sans cartes');
            }
        }
    }
}
