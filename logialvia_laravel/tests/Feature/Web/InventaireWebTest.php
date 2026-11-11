<?php

namespace Tests\Feature\Web;

use App\Livewire\Catalogue;
use App\Livewire\Inventaire;
use App\Models\Achat;
use App\Models\CycleCouveuse;
use App\Models\FicheJournee;
use App\Models\Fournisseur;
use App\Models\Intrant;
use App\Models\LigneAchat;
use App\Models\LigneVente;
use App\Models\MouvementIntrant;
use App\Models\MouvementProduit;
use App\Models\Poste;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Models\Vente;
use Carbon\CarbonImmutable;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Spatie\Permission\PermissionRegistrar;
use Tests\TestCase;

/**
 * Ecran web « Inventaire » : LECTURE SEULE, chiffres deduits des seuls FAITS synchronises de la periode
 * (`inventaire_repository_drift.dart`). Jamais de stock, de PMP ni de valeur : « Disponible sur le poste ».
 *
 * « Maintenant » est fige au mercredi 18/11/2026 10:00 (Africa/Porto-Novo = UTC+1, sans heure d'ete) :
 * les bornes se verifient a la microseconde, en heure LOCALE (les colonnes sont en UTC).
 */
class InventaireWebTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withoutVite();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(ModulesActifsSeeder::class);
        $this->travelTo(CarbonImmutable::parse('2026-11-18 10:00:00', 'Africa/Porto-Novo'));
    }

    // ------------------------------------------------------------------ outils

    private function utilisateur(string $role, string $username = 'u'): User
    {
        $u = User::query()->where('username', $username)->first();
        if ($u === null) {
            $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
            $u->assignRole($role);
        }

        return $u;
    }

    private function admin(): User
    {
        return $this->utilisateur('admin', 'gerante');
    }

    /** Instant LOCAL (Porto-Novo) -> UTC, tel qu'il est range en base. */
    private function loc(string $instant): CarbonImmutable
    {
        return CarbonImmutable::parse($instant, 'Africa/Porto-Novo')->utc();
    }

    private function ecran(?User $u = null)
    {
        return Livewire::actingAs($u ?? $this->admin())->test(Inventaire::class);
    }

    private function intrant(string $code = 'INT-001', string $nom = 'Maïs concassé', string $cat = 'Intrants Provende', string $unite = 'kg'): Intrant
    {
        $i = (new Intrant)->forceFill([
            'code' => $code, 'name' => $nom, 'cat' => $cat, 'unit' => $unite, 'threshold' => 50, 'saisi_le' => now()->subDay(),
        ]);
        $i->save();

        return $i;
    }

    private function mouvement(string $quand, float $quantite, array $surcharge = []): MouvementIntrant
    {
        $m = (new MouvementIntrant)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'horodatage' => $this->loc($quand),
            'intrant_code' => 'INT-001', 'article' => 'Maïs concassé', 'type' => $quantite >= 0 ? 'Entrée' : 'Sortie',
            'motif' => 'Mouvement de test', 'quantite' => $quantite, 'reference' => null, 'serveur_modifie_le' => now(),
        ], $surcharge));
        $m->save();

        return $m;
    }

    private function produit(string $nom = 'Poulet', array $surcharge = []): ProduitVendable
    {
        static $n = 0;
        $n++;

        return ProduitVendable::query()->create(array_merge([
            'id' => (string) Str::uuid(), 'sku' => "SKU-$n", 'name' => $nom, 'cat' => 'Volaille', 'price' => 1000, 'unit' => 'pièce',
            'icon' => 'category', 'saisi_le' => now(),
        ], $surcharge));
    }

    private function vente(string $quand, string $statut = 'Payée'): Vente
    {
        static $n = 0;
        $n++;
        $v = (new Vente)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => "V-P1-2026-$n",
            'portee_reference' => '', 'client' => 'Amina Bako', 'client_id' => null,
            'date_vente' => $this->loc($quand), 'mode' => 'Espèces', 'status' => $statut,
            'total' => 0, 'paye' => 0, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $v->save();

        return $v;
    }

    private function vendre(string $quand, ProduitVendable $p, float $qte, string $statut = 'Payée'): void
    {
        $v = $this->vente($quand, $statut);
        (new LigneVente)->forceFill([
            'id' => (string) Str::uuid(), 'vente_id' => $v->id, 'produit_id' => $p->id, 'name' => $p->name, 'qte' => $qte, 'pu' => 1000,
        ])->save();
    }

    private function correction(string $quand, ProduitVendable $p, float $quantite, array $surcharge = []): MouvementProduit
    {
        $m = (new MouvementProduit)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'horodatage' => $this->loc($quand),
            'produit_id' => $p->id, 'article' => $p->name, 'motif' => 'Casse constatée', 'quantite' => $quantite,
            'serveur_modifie_le' => now(),
        ], $surcharge));
        $m->save();

        return $m;
    }

    private function acheter(string $quand, string $statut, string $code, float $qte): void
    {
        static $n = 0;
        $n++;
        $f = Fournisseur::query()->first();
        if ($f === null) {
            $f = (new Fournisseur)->forceFill([
                'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => 'Provenderie du Nord',
                'updated_at' => now(), 'serveur_modifie_le' => now(),
            ]);
            $f->save();
        }
        $a = (new Achat)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => "ACH-P1-2026-$n",
            'portee_reference' => '', 'fournisseur_id' => $f->id, 'date_achat' => $this->loc($quand), 'statut' => $statut,
            'total' => 0, 'paye' => 0, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $a->save();
        (new LigneAchat)->forceFill([
            'id' => (string) Str::uuid(), 'achat_id' => $a->id, 'intrant_code' => $code, 'nom' => 'Ligne', 'qte' => $qte, 'pu_achat' => 100,
        ])->save();
    }

    private function fiche(string $espece, string $date, int $effectif, bool $saisie = true): void
    {
        (new FicheJournee)->forceFill([
            'id' => (string) Str::uuid(), 'espece' => $espece, 'date' => $date, 'effectif' => $effectif,
            'is_recorded' => $saisie, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ])->save();
    }

    private function lot(string $date, int $couves, string $statut = 'En Incubation', array $surcharge = []): void
    {
        static $n = 0;
        $n++;
        (new CycleCouveuse)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'code_incubation' => "C-2026-$n", 'espece' => 'pintades', 'date_incubation' => $date,
            'oeufs_couves' => $couves, 'statut' => $statut, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge))->save();
    }

    /** Texte d'une cellule `data-col` de la ligne marquee par `$ligne` (ex. `data-intrant="INT-001"`). */
    private function cellule(string $html, string $ligne, string $col): string
    {
        $this->assertSame(1, preg_match('/'.preg_quote($ligne, '/').'.*?data-col="'.$col.'">(.*?)<\/td>/s', $html, $m), "Cellule $col introuvable pour $ligne");

        return trim(html_entity_decode($m[1]));
    }

    private function texte(string $html): string
    {
        return html_entity_decode(strip_tags($html));
    }

    // ------------------------------------------------------------------- Acces

    public function test_visiteur_redirige_vers_la_connexion(): void
    {
        $this->get('/inventaire')->assertRedirect(route('login'));
    }

    public function test_les_roles_sans_view_stocks_sont_refuses_et_l_administrateur_admis(): void
    {
        // Matrice `config/logialvia.php` : seul `admin` a `view-stocks`.
        foreach (['comptable', 'caissier', 'animalier'] as $role) {
            $this->actingAs($this->utilisateur($role, $role))->get('/inventaire')->assertForbidden();
        }

        $this->actingAs($this->admin())->get('/inventaire')->assertOk()->assertSee('Inventaire')->assertDontSee('arrive bientôt');
    }

    public function test_un_compte_avec_la_seule_permission_de_lecture_est_admis(): void
    {
        $u = $this->utilisateur('comptable', 'lecteur');
        $u->givePermissionTo('view-stocks');

        $this->actingAs($u)->get('/inventaire')->assertOk();
    }

    public function test_le_composant_refuse_un_compte_sans_droit_meme_hors_route(): void
    {
        Livewire::actingAs($this->utilisateur('caissier', 'amina'))->test(Inventaire::class)->assertForbidden();
    }

    public function test_un_droit_retire_apres_l_ouverture_ferme_les_appels_suivants(): void
    {
        $u = $this->utilisateur('comptable', 'lecteur');
        $u->givePermissionTo('view-stocks');
        $composant = Livewire::actingAs($u)->test(Inventaire::class)->assertOk();

        $u->revokePermissionTo('view-stocks');
        app(PermissionRegistrar::class)->forgetCachedPermissions();
        $u->unsetRelation('permissions')->unsetRelation('roles');

        $composant->call('changerPeriode', 'mois')->assertForbidden();
    }

    // ------------------------------------------------------- Aucun stock, jamais

    public function test_aucun_stock_ni_pmp_ni_valeur_n_est_affiche_et_les_encarts_sont_grises(): void
    {
        $this->intrant();
        // Poste connu (« Web ») : un poste inconnu s'afficherait sous un prefixe d'identifiant aleatoire.
        $this->mouvement('2026-11-18 08:00:00', 130, ['device_id' => Catalogue::POSTE_WEB]);
        $this->mouvement('2026-11-18 09:00:00', -41, ['device_id' => Catalogue::POSTE_WEB]);
        $p = $this->produit('Poulet');
        $this->vendre('2026-11-18 09:00:00', $p, 7);

        $html = $this->ecran()->html();

        // Le stock deduit (130 - 41 = 89) ne doit apparaitre nulle part.
        $this->assertStringNotContainsString('89', $this->texte($html));
        foreach (['Stock initial', 'Stock final', 'STOCK INITIAL', 'STOCK FINAL', 'TOTAL INTRANTS', 'TOTAL PRODUITS FINIS', 'Valeur du stock'] as $interdit) {
            $this->assertStringNotContainsString($interdit, $html);
        }
        // Aucune colonne de stock, de PMP ni de valeur : en-tetes EXACTS des deux tableaux de periode.
        preg_match_all('/<th(?:\s[^>]*)?>(.*?)<\/th>/s', $html, $m);
        $entetes = array_map(fn ($t) => trim(html_entity_decode($t)), $m[1]);
        $this->assertSame(
            ['Article', 'Catégorie', 'Entrées', 'Sorties', 'Dont ajustements', 'Achats livrés', 'Postes',
                'Produit', 'Catégorie', 'Sorties (ventes)', 'Corrections', 'Coût de revient',
                'Filière', 'Effectif', 'Dernière saisie',
                'Date / Heure', 'Référence', 'Article', 'Type', 'Motif', 'Poste', 'Quantité',
                'Date / Heure', 'Produit', 'Motif', 'Poste', 'Variation'],
            $entetes,
        );
        // Les produits n'ont de cout de revient que celui du catalogue : jamais de montant sans lui.
        $this->assertStringNotContainsString('FCFA', $html);
    }

    public function test_chaque_bloc_dependant_du_stock_est_un_encart_grise_disponible_sur_le_poste(): void
    {
        $html = $this->ecran()->html();

        foreach (['Valeur Totale du Stock', 'Dont Intrants', 'Dont Produits Finis'] as $kpi) {
            $this->assertSame(1, preg_match('/<div[^>]*data-carte-poste="'.preg_quote($kpi, '/').'".*?<\/div>/s', $html, $m), $kpi);
            $this->assertStringContainsString('bg-surface-zebra', $m[0]);
            $this->assertStringContainsString('Disponible sur le poste', $m[0]);
            $this->assertStringContainsString('text-kpi-value font-bold">—<', $m[0]);
        }
        foreach (['equilibre', 'intrants', 'produits'] as $bloc) {
            $this->assertSame(1, preg_match('/<div[^>]*data-carte-poste="'.$bloc.'".*?<\/div>/s', $html, $m), $bloc);
            $this->assertStringContainsString('Disponible sur le poste', $m[0]);
            $this->assertStringContainsString('bg-surface-zebra', $m[0]);
        }
        // 3 KPI + equilibre + 2 tableaux = 6 encarts, pas un de plus ni de moins.
        $this->assertSame(6, substr_count($html, 'data-carte-poste="'));
    }

    // ------------------------------------------------------ Intrants : le journal

    public function test_entrees_sorties_et_ajustements_viennent_du_journal_de_tous_les_postes(): void
    {
        $this->intrant();
        $this->intrant('INT-002', 'Son de blé', 'Intrants Provende', 'sac');
        $this->intrant('INT-003', 'Vaccin', 'Vétérinaire', 'dose');
        $p1 = Poste::query()->create(['device_id' => (string) Str::uuid(), 'code' => 'P1']);
        $p2 = Poste::query()->create(['device_id' => (string) Str::uuid(), 'code' => 'P2']);

        $this->mouvement('2026-11-18 08:00:00', 100, ['device_id' => $p1->device_id]);
        $this->mouvement('2026-11-18 08:30:00', 2.5, ['device_id' => $p2->device_id, 'type' => 'Ajustement']);
        $this->mouvement('2026-11-18 09:00:00', -30, ['device_id' => $p1->device_id]);
        $this->mouvement('2026-11-18 09:30:00', -5, ['device_id' => $p2->device_id, 'type' => 'Ajustement']);
        $this->mouvement('2026-11-18 09:45:00', 12, ['device_id' => Catalogue::POSTE_WEB]);
        // Un autre intrant ne se mele pas au premier.
        $this->mouvement('2026-11-18 09:50:00', 9, ['intrant_code' => 'INT-002', 'article' => 'Son de blé', 'device_id' => $p1->device_id]);

        $html = $this->ecran()->html();
        $l = 'data-intrant="INT-001"';
        $this->assertSame('+ 114,5', $this->cellule($html, $l, 'entrees'));   // 100 + 2,5 + 12 (le signe fait foi, comme le Dart)
        $this->assertSame('− 35', $this->cellule($html, $l, 'sorties'));      // 30 + 5, affichee positive
        $this->assertSame('− 2,5', $this->cellule($html, $l, 'ajustements')); // +2,5 - 5 : seuls les mouvements « Ajustement »
        $this->assertSame('P1, P2, Web', $this->cellule($html, $l, 'postes'));
        $this->assertSame('+ 9', $this->cellule($html, 'data-intrant="INT-002"', 'entrees'));
        $this->assertSame('—', $this->cellule($html, 'data-intrant="INT-002"', 'sorties'));
        $this->assertSame('P1', $this->cellule($html, 'data-intrant="INT-002"', 'postes'));
        // Sans mouvement : des tirets, jamais un zero invente.
        foreach (['entrees', 'sorties', 'ajustements', 'achetes', 'postes'] as $col) {
            $this->assertSame('—', $this->cellule($html, 'data-intrant="INT-003"', $col));
        }
    }

    public function test_les_intrants_sont_tries_par_nom_comme_le_dart(): void
    {
        $this->intrant('INT-001', 'Zinc');
        $this->intrant('INT-002', 'Avoine');
        $this->intrant('INT-003', 'Maïs');

        $this->ecran()->assertSeeInOrder(['data-intrant="INT-002"', 'data-intrant="INT-003"', 'data-intrant="INT-001"'], false);
    }

    public function test_bornes_du_jour_a_la_microseconde_en_heure_locale(): void
    {
        $this->intrant();
        // Jour = 18/11 : de 00:00:00.000000 (inclus) a 19/11 00:00:00.000000 (exclu), heure de Porto-Novo.
        $this->mouvement('2026-11-17 23:59:59.999999', 1);  // veille : exclu
        $this->mouvement('2026-11-18 00:00:00.000000', 2);  // debut exact : inclus
        $this->mouvement('2026-11-18 23:59:59.999999', 4);  // derniere microseconde : inclus
        $this->mouvement('2026-11-19 00:00:00.000000', 8);  // lendemain exact : exclu
        $this->mouvement('2026-11-18 00:00:00.000000', -16);
        $this->mouvement('2026-11-19 00:00:00.000000', -32);

        $html = $this->ecran()->html();
        $this->assertSame('+ 6', $this->cellule($html, 'data-intrant="INT-001"', 'entrees'));
        $this->assertSame('− 16', $this->cellule($html, 'data-intrant="INT-001"', 'sorties'));
    }

    public function test_les_bornes_sont_celles_de_porto_novo_et_non_celles_d_utc(): void
    {
        $this->intrant();
        // 17/11 23:30 UTC = 18/11 00:30 local : DANS le jour local (hors du jour UTC).
        $this->mouvement('2026-11-18 00:30:00', 5);
        // 18/11 23:30 UTC = 19/11 00:30 local : HORS du jour local (dans le jour UTC).
        $this->mouvement('2026-11-19 00:30:00', 7);

        $this->assertSame('+ 5', $this->cellule($this->ecran()->html(), 'data-intrant="INT-001"', 'entrees'));
    }

    public function test_la_fin_de_la_plage_est_incluse_toute_la_journee(): void
    {
        $this->intrant();
        $this->mouvement('2026-11-14 23:59:59.999999', 1);
        $this->mouvement('2026-11-15 00:00:00', 2);
        $this->mouvement('2026-11-17 23:59:59.999999', 4);
        $this->mouvement('2026-11-18 00:00:00', 8);

        $html = $this->ecran()->set('debut', '2026-11-15')->set('fin', '2026-11-17')->html();
        $this->assertSame('+ 6', $this->cellule($html, 'data-intrant="INT-001"', 'entrees'));
    }

    public function test_les_quantites_decimales_ne_sont_pas_arrondies(): void
    {
        $this->intrant();
        $this->mouvement('2026-11-18 08:00:00', 0.4);
        $this->mouvement('2026-11-18 08:10:00', -1234.567);

        $html = $this->ecran()->html();
        $this->assertSame('+ 0,4', $this->cellule($html, 'data-intrant="INT-001"', 'entrees'));
        $this->assertSame('− 1 234,567', $this->cellule($html, 'data-intrant="INT-001"', 'sorties'));
    }

    // ---------------------------------------------------------- Achats livres

    public function test_les_achats_livres_sont_cumules_par_intrant_sur_la_periode(): void
    {
        $this->intrant();
        $this->intrant('INT-002', 'Son de blé');
        $this->acheter('2026-11-18 08:00:00', 'Livré', 'INT-001', 20);
        $this->acheter('2026-11-18 09:00:00', 'Livré', 'INT-001', 5.5);
        $this->acheter('2026-11-18 09:30:00', 'Commandé', 'INT-001', 1000);   // pas livre
        $this->acheter('2026-11-18 09:40:00', 'Annulé', 'INT-001', 2000);     // annule
        $this->acheter('2026-11-17 23:59:59.999999', 'Livré', 'INT-001', 4000); // veille
        $this->acheter('2026-11-19 00:00:00', 'Livré', 'INT-001', 8000);        // lendemain
        $this->acheter('2026-11-18 10:00:00', 'Livré', 'INT-002', 3);

        $html = $this->ecran()->html();
        $this->assertSame('25,5', $this->cellule($html, 'data-intrant="INT-001"', 'achetes'));
        $this->assertSame('3', $this->cellule($html, 'data-intrant="INT-002"', 'achetes'));
    }

    public function test_les_bornes_des_achats_sont_a_la_microseconde(): void
    {
        $this->intrant();
        $this->acheter('2026-11-18 00:00:00.000000', 'Livré', 'INT-001', 2);
        $this->acheter('2026-11-18 23:59:59.999999', 'Livré', 'INT-001', 4);

        $this->assertSame('6', $this->cellule($this->ecran()->html(), 'data-intrant="INT-001"', 'achetes'));
    }

    // ---------------------------------------------------------------- Produits

    public function test_les_sorties_sont_les_lignes_des_ventes_non_annulees_de_la_periode(): void
    {
        $poulet = $this->produit('Poulet');
        $oeuf = $this->produit('Œufs');
        $this->vendre('2026-11-18 08:00:00', $poulet, 3);
        $this->vendre('2026-11-18 09:00:00', $poulet, 1.5, 'Avance');           // une avance est une vente
        $this->vendre('2026-11-18 09:30:00', $poulet, 100, 'Annulée');           // annulee : exclue
        $this->vendre('2026-11-17 23:59:59.999999', $poulet, 1000);             // veille
        $this->vendre('2026-11-19 00:00:00', $poulet, 10000);                   // lendemain
        $this->vendre('2026-11-18 00:00:00.000000', $oeuf, 30);                 // debut exact : inclus
        $this->vendre('2026-11-18 23:59:59.999999', $oeuf, 60);                 // derniere microseconde : incluse

        $html = $this->ecran()->html();
        $this->assertSame('− 4,5', $this->cellule($html, 'data-produit="'.$poulet->sku.'"', 'vendu'));
        $this->assertSame('− 90', $this->cellule($html, 'data-produit="'.$oeuf->sku.'"', 'vendu'));
    }

    public function test_un_produit_sans_vente_affiche_un_tiret_et_les_produits_sont_tries_par_nom(): void
    {
        $zebre = $this->produit('Zèbre');
        $abeille = $this->produit('Abeille');

        $composant = $this->ecran();
        $this->assertSame('—', $this->cellule($composant->html(), 'data-produit="'.$zebre->sku.'"', 'vendu'));
        $this->assertSame('—', $this->cellule($composant->html(), 'data-produit="'.$zebre->sku.'"', 'corrections'));
        $composant->assertSeeInOrder(['data-produit="'.$abeille->sku.'"', 'data-produit="'.$zebre->sku.'"'], false);
    }

    public function test_les_corrections_de_stock_sont_la_somme_signee_du_journal_des_produits(): void
    {
        $p = $this->produit('Poulet');
        $autre = $this->produit('Œufs');
        $p2 = Poste::query()->create(['device_id' => (string) Str::uuid(), 'code' => 'P2']);

        $this->correction('2026-11-18 08:00:00', $p, 10);
        $this->correction('2026-11-18 09:00:00', $p, -3.5, ['device_id' => $p2->device_id, 'motif' => 'Animal mort']);
        $this->correction('2026-11-17 23:59:59.999999', $p, 1000);   // veille
        $this->correction('2026-11-19 00:00:00', $p, 2000);          // lendemain
        $this->correction('2026-11-18 09:00:00', $autre, -2);
        // Deux corrections qui s'annulent : « 0 » (il y en a eu), pas un tiret (aucune).
        $this->correction('2026-11-18 09:10:00', $autre, 4);
        $this->correction('2026-11-18 09:20:00', $autre, -4);

        $html = $this->ecran()->html();
        $this->assertSame('+ 6,5', $this->cellule($html, 'data-produit="'.$p->sku.'"', 'corrections'));
        $this->assertSame('− 2', $this->cellule($html, 'data-produit="'.$autre->sku.'"', 'corrections'));

        $this->ecran()->assertSee('Animal mort')->assertSeeHtml('data-poste>P2<');
    }

    public function test_les_corrections_qui_s_annulent_affichent_zero(): void
    {
        $p = $this->produit('Poulet');
        $this->correction('2026-11-18 09:10:00', $p, 4);
        $this->correction('2026-11-18 09:20:00', $p, -4);

        $this->assertSame('0', $this->cellule($this->ecran()->html(), 'data-produit="'.$p->sku.'"', 'corrections'));
    }

    public function test_les_bornes_des_corrections_sont_a_la_microseconde(): void
    {
        $p = $this->produit('Poulet');
        $this->correction('2026-11-17 23:59:59.999999', $p, 1);
        $this->correction('2026-11-18 00:00:00.000000', $p, 2);
        $this->correction('2026-11-18 23:59:59.999999', $p, 4);
        $this->correction('2026-11-19 00:00:00.000000', $p, 8);

        $html = $this->ecran()->html();
        $this->assertSame('+ 6', $this->cellule($html, 'data-produit="'.$p->sku.'"', 'corrections'));
        $this->assertSame(2, substr_count($html, 'data-correction="'));
    }

    public function test_le_cout_de_revient_est_celui_du_catalogue_ou_non_renseigne(): void
    {
        $avec = $this->produit('Poulet', ['cout_revient' => 1500]);
        $sans = $this->produit('Œufs');

        $html = $this->ecran()->html();
        $this->assertSame('1 500 FCFA', $this->cellule($html, 'data-produit="'.$avec->sku.'"', 'cout'));
        $this->assertSame('Non renseigné', $this->cellule($html, 'data-produit="'.$sans->sku.'"', 'cout'));
    }

    public function test_un_produit_archive_n_apparait_que_s_il_a_bouge_sur_la_periode(): void
    {
        $dormant = $this->produit('Dormant', ['archive_le' => now()]);
        $actif = $this->produit('Actif', ['archive_le' => now()]);
        $this->vendre('2026-11-18 09:00:00', $actif, 2);

        $html = $this->ecran()->html();
        $this->assertStringNotContainsString('data-produit="'.$dormant->sku.'"', $html);
        $this->assertStringContainsString('data-produit="'.$actif->sku.'"', $html);
        $this->assertStringContainsString('(archivé)', $html);

        // Une correction suffit aussi.
        $this->correction('2026-11-18 09:00:00', $dormant, 1);
        $this->assertStringContainsString('data-produit="'.$dormant->sku.'"', $this->ecran()->html());
    }

    // ----------------------------------------------------------- Animaux sur pied

    public function test_l_effectif_est_la_derniere_journee_reellement_saisie_jusqu_a_la_fin(): void
    {
        $this->fiche('goliaths', '2026-11-10', 100);
        $this->fiche('goliaths', '2026-11-18', 120);                // le jour de fin compte
        $this->fiche('goliaths', '2026-11-19', 999);                // apres la fin : ignore
        $this->fiche('pintades', '2026-11-12', 40);
        $this->fiche('pintades', '2026-11-16', 7777, false);        // journee projetee : ne temoigne d'aucun comptage
        $this->fiche('lapins', '2026-11-19', 55);                   // tout est apres la fin : jamais saisie

        $html = $this->ecran()->html();
        $this->assertSame('120', $this->cellule($html, 'data-effectif="goliaths"', 'effectif'));
        $this->assertSame('18/11/2026', $this->cellule($html, 'data-effectif="goliaths"', 'saisie'));
        $this->assertSame('40', $this->cellule($html, 'data-effectif="pintades"', 'effectif'));
        $this->assertSame('12/11/2026', $this->cellule($html, 'data-effectif="pintades"', 'saisie'));
        $this->assertSame('0', $this->cellule($html, 'data-effectif="lapins"', 'effectif'));
        $this->assertSame('Jamais saisie', $this->cellule($html, 'data-effectif="lapins"', 'saisie'));
        $this->assertStringContainsString('data-col="total-effectif">160<', $html);
        $this->assertMatchesRegularExpression('/data-kpi="animaux".*?text-kpi-value font-bold">160</s', $html);
    }

    public function test_le_total_et_le_kpi_des_animaux_additionnent_les_huit_filieres(): void
    {
        foreach (['goliaths', 'pintades', 'lapins', 'poissons-chats', 'poulets', 'pondeuses', 'escargots', 'ovins'] as $i => $espece) {
            $this->fiche($espece, '2026-11-10', 10 * ($i + 1));
        }

        $composant = $this->ecran();
        $html = $composant->html();
        $this->assertSame(8, substr_count($html, 'data-effectif="'));
        $this->assertSame('10', $this->cellule($html, 'data-effectif="goliaths"', 'effectif'));
        $this->assertSame('80', $this->cellule($html, 'data-effectif="ovins"', 'effectif'));
        $this->assertMatchesRegularExpression('/data-kpi="animaux".*?text-kpi-value font-bold">360</s', $html);
        $this->assertStringContainsString('data-col="total-effectif">360<', $html);
    }

    public function test_l_effectif_suit_la_fin_de_la_periode_choisie(): void
    {
        $this->fiche('goliaths', '2026-11-10', 100);
        $this->fiche('goliaths', '2026-11-15', 150);

        $html = $this->ecran()->set('debut', '2026-11-01')->set('fin', '2026-11-14')->html();
        $this->assertSame('100', $this->cellule($html, 'data-effectif="goliaths"', 'effectif'));
    }

    public function test_les_oeufs_en_incubation_retirent_les_mirages_et_les_lots_clos_ou_supprimes(): void
    {
        $this->lot('2026-11-10', 100, 'En Incubation', ['oeufs_blancs_j7' => 8, 'oeufs_gates_j14' => 2]);   // 90
        $this->lot('2026-11-18', 50);                                                                      // jour de fin : 50
        $this->lot('2026-11-19', 1000);                                                                    // apres la fin
        $this->lot('2026-11-05', 2000, 'Éclosion Effectuée');                                              // clos
        $this->lot('2026-11-05', 4000, 'En Incubation', ['supprime_le' => now()]);                         // supprime
        $this->lot('2026-11-06', 30, 'En Incubation', ['oeufs_blancs_j7' => 5]);                           // 25 (J14 non saisi)

        $this->ecran()->assertSeeHtml('data-oeufs>Œufs en incubation à la fin de la période : <span class="font-bold">165</span>');
    }

    // ---------------------------------------------------------------- Periodes

    public function test_la_periode_par_defaut_est_le_jour(): void
    {
        $this->ecran()
            ->assertSet('periode', 'jour')->assertSet('debut', '2026-11-18')->assertSet('fin', '2026-11-18')
            ->assertSee('Situation au 18/11/2026');
    }

    public function test_hebdomadaire_va_du_lundi_au_jour_et_mensuel_du_premier_au_jour(): void
    {
        $this->ecran()->call('changerPeriode', 'semaine')
            ->assertSet('periode', 'semaine')->assertSet('debut', '2026-11-16')->assertSet('fin', '2026-11-18')
            ->assertSee('Du 16/11/2026 au 18/11/2026')
            ->call('changerPeriode', 'mois')
            ->assertSet('periode', 'mois')->assertSet('debut', '2026-11-01')->assertSet('fin', '2026-11-18')
            ->assertSee('Du 01/11/2026 au 18/11/2026')
            ->call('changerPeriode', 'jour')
            ->assertSet('debut', '2026-11-18')->assertSee('Situation au 18/11/2026');
    }

    public function test_la_semaine_d_un_dimanche_remonte_au_lundi_precedent_et_celle_d_un_lundi_commence_ce_jour(): void
    {
        $this->travelTo(CarbonImmutable::parse('2026-11-22 10:00:00', 'Africa/Porto-Novo'));   // dimanche
        $this->ecran()->call('changerPeriode', 'semaine')->assertSet('debut', '2026-11-16')->assertSet('fin', '2026-11-22');

        $this->travelTo(CarbonImmutable::parse('2026-11-16 10:00:00', 'Africa/Porto-Novo'));   // lundi
        $this->ecran()->call('changerPeriode', 'semaine')->assertSet('debut', '2026-11-16')->assertSet('fin', '2026-11-16');
    }

    public function test_la_semaine_inclut_le_lundi_a_minuit_et_exclut_la_veille(): void
    {
        $this->intrant();
        $this->mouvement('2026-11-15 23:59:59.999999', 1);   // dimanche : hors semaine
        $this->mouvement('2026-11-16 00:00:00.000000', 2);   // lundi minuit : dans la semaine
        $this->mouvement('2026-11-18 20:00:00', 4);          // aujourd'hui : dans la semaine
        $this->mouvement('2026-11-19 00:00:00', 8);          // demain : hors semaine

        $html = $this->ecran()->call('changerPeriode', 'semaine')->html();
        $this->assertSame('+ 6', $this->cellule($html, 'data-intrant="INT-001"', 'entrees'));
    }

    public function test_le_mois_inclut_le_premier_a_minuit_et_exclut_la_fin_du_mois_precedent(): void
    {
        $this->intrant();
        $this->mouvement('2026-10-31 23:59:59.999999', 1);
        $this->mouvement('2026-11-01 00:00:00.000000', 2);
        $this->mouvement('2026-11-18 09:00:00', 4);

        $html = $this->ecran()->call('changerPeriode', 'mois')->html();
        $this->assertSame('+ 6', $this->cellule($html, 'data-intrant="INT-001"', 'entrees'));
    }

    public function test_la_plage_personnalisee_n_est_pas_cliquable_et_s_active_en_choisissant_une_date(): void
    {
        $composant = $this->ecran()->call('changerPeriode', 'plage')->assertSet('periode', 'jour');
        $this->assertStringNotContainsString('wire:click="changerPeriode(\'plage\')"', $composant->html());

        $composant->set('debut', '2026-11-10')->assertSet('periode', 'plage')->assertSet('fin', '2026-11-18')
            ->assertSee('Du 10/11/2026 au 18/11/2026');
        $this->assertMatchesRegularExpression('/data-periode="plage"\s+aria-current="true"/', $composant->html());
    }

    public function test_une_periode_inconnue_est_ignoree(): void
    {
        $this->ecran()->call('changerPeriode', 'annee')->assertSet('periode', 'jour')->assertSet('debut', '2026-11-18');
    }

    public function test_la_derniere_borne_choisie_fait_foi_et_entraine_l_autre(): void
    {
        // Debut apres la fin : la fin suit (« je commence le 20 », pas « je finis le 20 »).
        $this->ecran()->set('fin', '2026-11-12')->set('debut', '2026-11-20')
            ->assertSet('debut', '2026-11-20')->assertSet('fin', '2026-11-20');
        // Fin avant le debut : le debut suit.
        $this->ecran()->set('debut', '2026-11-15')->set('fin', '2026-11-10')
            ->assertSet('debut', '2026-11-10')->assertSet('fin', '2026-11-10');
        // Cas normal : rien n'est touche.
        $this->ecran()->set('fin', '2026-11-25')->set('debut', '2026-11-05')
            ->assertSet('debut', '2026-11-05')->assertSet('fin', '2026-11-25');
    }

    public function test_une_date_invalide_retombe_sur_le_jour_et_le_dit(): void
    {
        $this->intrant();
        $this->mouvement('2026-11-18 09:00:00', 5);
        $this->mouvement('2026-11-10 09:00:00', 1000);

        foreach (['2026-13-45', 'abc', '', '2026-02-30'] as $mauvaise) {
            $composant = $this->ecran()->set('debut', '2026-11-01')->set('fin', $mauvaise);
            $composant->assertSeeHtml('data-alerte="periode"')->assertSee('le jour en cours est affiché');
            $this->assertSame('+ 5', $this->cellule($composant->html(), 'data-intrant="INT-001"', 'entrees'));
        }

        // Periode valide : pas d'alerte.
        $this->ecran()->assertDontSeeHtml('data-alerte="periode"');
    }

    // ---------------------------------------------------------------- Recherche

    public function test_la_recherche_filtre_intrants_et_produits_sans_casse(): void
    {
        $this->intrant('INT-001', 'Maïs concassé', 'Intrants Provende');
        $this->intrant('INT-002', 'Vaccin Newcastle', 'Vétérinaire');
        $poulet = $this->produit('Poulet fermier', ['sku' => 'PF-01', 'cat' => 'Volaille']);
        $oeuf = $this->produit('Œufs frais', ['sku' => 'OE-02', 'cat' => 'Produits Dérivés']);

        $composant = $this->ecran();
        // Par nom, par code, par categorie ; majuscules et espaces autour ignores (`trim().toLowerCase()`).
        $composant->set('recherche', '  MAÏS ')->assertSeeHtml('data-intrant="INT-001"')->assertDontSeeHtml('data-intrant="INT-002"');
        $composant->set('recherche', 'int-002')->assertSeeHtml('data-intrant="INT-002"')->assertDontSeeHtml('data-intrant="INT-001"');
        $composant->set('recherche', 'vétérinaire')->assertSeeHtml('data-intrant="INT-002"')->assertDontSeeHtml('data-intrant="INT-001"');
        // Produits : nom, sku, categorie.
        $composant->set('recherche', 'fermier')->assertSeeHtml('data-produit="PF-01"')->assertDontSeeHtml('data-produit="OE-02"');
        $composant->set('recherche', 'oe-02')->assertSeeHtml('data-produit="OE-02"')->assertDontSeeHtml('data-produit="PF-01"');
        $composant->set('recherche', 'dérivés')->assertSeeHtml('data-produit="OE-02"')->assertDontSeeHtml('data-produit="PF-01"');
        // Rien ne correspond : le message du Dart.
        $composant->set('recherche', 'zzz')
            ->assertSee('Aucun intrant ne correspond à ces filtres.')->assertSee('Aucun produit ne correspond à ces filtres.');
        // Vide : tout revient.
        $composant->set('recherche', '')->assertSeeHtml('data-intrant="INT-001"')->assertSeeHtml('data-produit="OE-02"');
    }

    public function test_la_recherche_ne_touche_ni_les_animaux_ni_le_calcul(): void
    {
        $this->intrant();
        $this->mouvement('2026-11-18 09:00:00', 5);
        $this->fiche('goliaths', '2026-11-10', 100);

        $html = $this->ecran()->set('recherche', 'zzz')->html();
        $this->assertSame('100', $this->cellule($html, 'data-effectif="goliaths"', 'effectif'));
    }

    // ----------------------------------------------------------------- Journaux

    public function test_le_journal_montre_le_poste_d_origine_l_heure_locale_et_le_signe(): void
    {
        $this->intrant();
        $p2 = Poste::query()->create(['device_id' => (string) Str::uuid(), 'code' => 'P2']);
        $inconnu = (string) Str::uuid();
        // Heures saisies en LOCAL (stockees en UTC) : l'ecran les rend en heure de Porto-Novo.
        $this->mouvement('2026-11-18 08:15:00', 12, ['device_id' => $p2->device_id, 'motif' => 'Du poste deux', 'reference' => 'CMD-007']);
        $this->mouvement('2026-11-18 12:40:00', -3.5, ['device_id' => Catalogue::POSTE_WEB, 'motif' => 'Du web']);
        $this->mouvement('2026-11-18 14:50:00', 1, ['device_id' => $inconnu, 'motif' => 'Poste disparu']);

        $composant = $this->ecran();
        // Heure LOCALE (08:15), jamais l'heure UTC stockee (07:15, 11:40, 13:50).
        $composant->assertSee('08:15')->assertSee('12:40')->assertSee('14:50')
            ->assertDontSee('07:15')->assertDontSee('11:40')->assertDontSee('13:50');
        $composant->assertSee('Du poste deux')->assertSee('CMD-007')
            ->assertSeeHtml('data-poste>P2<')->assertSeeHtml('data-poste>Web<')
            ->assertSee('Poste '.substr($inconnu, 0, 8))
            ->assertSee('− 3,5');
        // Plus recent d'abord.
        $composant->assertSeeInOrder(['Poste disparu', 'Du web', 'Du poste deux']);
        // Vert pour une entree, rouge pour une sortie : tableau ET carte mobile.
        $this->assertSame(1, preg_match('/data-section="journal-intrants".*?data-section="journal-produits"/s', $composant->html(), $section));
        $this->assertSame(2, substr_count($section[0], 'text-error-deep">− 3,5<'));
        $this->assertSame(2, substr_count($section[0], 'text-success-deep">+ 12<'));
    }

    public function test_le_journal_ne_montre_que_la_periode_et_se_limite_a_deux_cents_lignes(): void
    {
        $this->intrant();
        $this->mouvement('2026-11-17 12:00:00', 1, ['motif' => 'Hier']);
        for ($i = 0; $i < 201; $i++) {
            $this->mouvement('2026-11-18 08:00:00', 1, ['motif' => $i === 0 ? 'Le plus ancien' : 'Courant']);
        }
        // Le plus recent doit toujours rester dans les 200 lignes.
        $this->mouvement('2026-11-18 09:00:00', 1, ['motif' => 'Le plus récent']);

        $composant = $this->ecran();
        $html = $composant->html();
        $composant->assertSee('Le plus récent')->assertDontSee('Hier');
        $this->assertSame(Inventaire::LIMITE_JOURNAL, substr_count($html, 'data-mouvement="'));
        $composant->assertSee('Les 200 plus récents sur 202.');

        // Sous la limite : pas de message de troncature.
        MouvementIntrant::query()->whereIn('id', MouvementIntrant::query()->where('motif', 'Courant')->limit(150)->pluck('id'))->delete();
        $this->ecran()->assertDontSeeHtml('data-troncature');
    }

    public function test_le_journal_des_corrections_de_produits_porte_le_poste_et_le_motif(): void
    {
        $p = $this->produit('Poulet');
        $p3 = Poste::query()->create(['device_id' => (string) Str::uuid(), 'code' => 'P3']);
        $this->correction('2026-11-18 08:00:00', $p, -2, ['device_id' => $p3->device_id, 'motif' => 'Casse constatée']);
        $this->correction('2026-11-17 08:00:00', $p, 50, ['motif' => 'Hier']);

        $this->ecran()->assertSee('Casse constatée')->assertSeeHtml('data-poste>P3<')->assertSee('− 2')->assertDontSee('Hier')
            ->assertSee('Corrections de stock des produits de la période');
    }

    public function test_les_journaux_vides_disent_qu_il_n_y_a_rien(): void
    {
        $this->ecran()->assertSee('Aucun mouvement d\'intrant sur cette période.', false)->assertSee('Aucune correction de stock sur cette période.');
    }

    public function test_les_bornes_du_journal_des_intrants_sont_a_la_microseconde(): void
    {
        $this->intrant();
        $this->mouvement('2026-11-17 23:59:59.999999', 1, ['motif' => 'Veille']);
        $this->mouvement('2026-11-18 00:00:00.000000', 2, ['motif' => 'Debut exact']);
        $this->mouvement('2026-11-18 23:59:59.999999', 4, ['motif' => 'Derniere microseconde']);
        $this->mouvement('2026-11-19 00:00:00.000000', 8, ['motif' => 'Lendemain exact']);

        $html = $this->ecran()->html();
        $this->assertSame(2, substr_count($html, 'data-mouvement="'));
        $this->assertStringContainsString('Debut exact', $html);
        $this->assertStringContainsString('Derniere microseconde', $html);
        $this->assertStringNotContainsString('Veille', $html);
        $this->assertStringNotContainsString('Lendemain exact', $html);
    }

    public function test_le_journal_des_corrections_est_trie_du_plus_recent_au_plus_ancien(): void
    {
        $p = $this->produit('Poulet');
        $this->correction('2026-11-18 08:00:00', $p, 1, ['motif' => 'Premiere']);
        $this->correction('2026-11-18 12:00:00', $p, 1, ['motif' => 'Troisieme']);
        $this->correction('2026-11-18 10:00:00', $p, 1, ['motif' => 'Deuxieme']);

        $this->ecran()->assertSeeInOrder(['Troisieme', 'Deuxieme', 'Premiere']);
    }

    public function test_les_postes_d_un_article_sont_uniques_et_tries(): void
    {
        $this->intrant();
        $a = Poste::query()->create(['device_id' => (string) Str::uuid(), 'code' => 'P1']);
        $c = Poste::query()->create(['device_id' => (string) Str::uuid(), 'code' => 'P2']);
        // Ordre d'insertion volontairement desordonne : Web, P2, P1, P1 (meme poste deux fois).
        $this->mouvement('2026-11-18 08:00:00', 1, ['device_id' => Catalogue::POSTE_WEB]);
        $this->mouvement('2026-11-18 08:01:00', 1, ['device_id' => $c->device_id]);
        $this->mouvement('2026-11-18 08:02:00', 1, ['device_id' => $a->device_id]);
        $this->mouvement('2026-11-18 08:03:00', 1, ['device_id' => $a->device_id]);   // meme poste : une seule mention

        $this->assertSame('P1, P2, Web', $this->cellule($this->ecran()->html(), 'data-intrant="INT-001"', 'postes'));
    }

    public function test_choisir_la_fin_bascule_en_plage_personnalisee(): void
    {
        $this->ecran()->set('fin', '2026-11-20')->assertSet('periode', 'plage')->assertSee('Du 18/11/2026 au 20/11/2026');
    }

    public function test_des_bornes_forgees_dont_le_debut_suit_la_fin_retombent_sur_le_jour(): void
    {
        $this->intrant();
        $this->mouvement('2026-11-18 09:00:00', 5);
        $this->mouvement('2026-11-12 09:00:00', 1000);

        // Les hooks de l'ecran empechent cet etat ; un appel forge pourrait l'atteindre : on le rend directement.
        $composant = $this->ecran();
        $composant->instance()->debut = '2026-11-20';
        $composant->instance()->fin = '2026-11-10';
        $vue = $composant->instance()->render();

        $this->assertFalse($vue->getData()['periodeValide']);
        $this->assertSame('Situation au 18/11/2026', $vue->getData()['libellePeriode']);
        $this->assertSame(5.0, $vue->getData()['intrants'][0]['entrees']);
    }

    // ------------------------------------------------------- Ecarts et lecture seule

    public function test_les_ecarts_sont_declares_dans_l_ecran_sans_bouton_d_export(): void
    {
        $composant = $this->ecran();
        $composant->assertSee('Écarts avec le poste')->assertSee('Export PDF')->assertSee('tous les postes')
            ->assertSee('Porto-Novo')->assertSee('En incubation');
        foreach (['Exporter', 'Imprimer', 'Télécharger'] as $verbe) {
            $composant->assertDontSee($verbe);
        }
        $composant->assertDontSeeHtml('<a href="/inventaire/pdf');
    }

    public function test_aucun_formulaire_ni_ecriture_et_la_base_reste_intacte(): void
    {
        $this->intrant();
        $this->mouvement('2026-11-18 09:00:00', 5);
        $p = $this->produit('Poulet');
        $this->vendre('2026-11-18 09:00:00', $p, 1);
        $this->fiche('goliaths', '2026-11-10', 100);

        $tables = ['intrants', 'mouvements_intrant', 'mouvements_produit', 'produits_vendables', 'ventes', 'lignes_vente',
            'achats', 'lignes_achat', 'fiche_journee', 'cycle_couveuse', 'audit_logs', 'demandes_referentiel', 'postes'];
        $avant = array_map(fn ($t) => DB::table($t)->count(), $tables);
        $empreinte = DB::table('mouvements_intrant')->get()->toJson().DB::table('intrants')->get()->toJson();

        $composant = $this->ecran();
        $composant->call('changerPeriode', 'mois')->set('debut', '2026-11-02')->set('fin', '2026-11-20')->set('recherche', 'a');
        $html = $composant->html();

        $this->assertSame($avant, array_map(fn ($t) => DB::table($t)->count(), $tables));
        $this->assertSame($empreinte, DB::table('mouvements_intrant')->get()->toJson().DB::table('intrants')->get()->toJson());
        // Aucun bouton d'ecriture : les seuls wire:click sont les trois periodes.
        $this->assertSame(0, preg_match('/wire:submit|<form|type="submit"/', $html));
        preg_match_all('/wire:click="([^"]+)"/', $html, $m);
        $this->assertEqualsCanonicalizing(["changerPeriode('jour')", "changerPeriode('semaine')", "changerPeriode('mois')"], $m[1]);
        $methodes = array_map(fn ($r) => $r->name, (new \ReflectionClass(Inventaire::class))->getMethods(\ReflectionMethod::IS_PUBLIC));
        foreach (['enregistrer', 'supprimer', 'modifier', 'annuler', 'nouveau', 'ajuster'] as $ecriture) {
            $this->assertNotContains($ecriture, $methodes);
        }
    }

    // ------------------------------------------------------------------ Design

    public function test_tableaux_des_640px_cartes_en_dessous_et_jetons_du_dart(): void
    {
        $this->intrant();
        $this->mouvement('2026-11-18 09:00:00', 5);
        $p = $this->produit('Poulet');
        $this->correction('2026-11-18 09:00:00', $p, 1);

        $html = $this->ecran()->html();
        // Tableau visible a partir de `sm` (640 px), cartes cachees a partir de `sm`.
        $this->assertSame(5, substr_count($html, 'hidden overflow-x-auto'));
        $this->assertSame(5, substr_count($html, 'sm:block'));
        foreach (['cartes-intrants', 'cartes-produits', 'cartes-effectifs', 'cartes-journal-intrants', 'cartes-journal-produits'] as $vue) {
            $this->assertMatchesRegularExpression('/data-vue="'.$vue.'"/', $html);
            $this->assertMatchesRegularExpression('/class="[^"]*sm:hidden[^"]*" data-vue="'.$vue.'"/', $html);
        }
        $this->assertStringContainsString('data-carte-intrant="INT-001"', $html);
        // Jetons seulement : aucune couleur ni taille en dur.
        $this->assertSame(0, preg_match('/style="|#[0-9a-fA-F]{3,6}\b|\[\#|text-\[|bg-\[/', $html));
        $this->assertStringContainsString('text-page-title', $html);
        $this->assertStringContainsString('bg-surface-zebra', $html);
        $this->assertStringContainsString('border-brand-navy', $html);
    }

    public function test_la_page_est_servie_par_la_route_et_non_par_la_page_bientot(): void
    {
        $this->actingAs($this->admin())->get('/inventaire')
            ->assertOk()->assertSeeLivewire(Inventaire::class)->assertSee('Écarts avec le poste');
    }
}
