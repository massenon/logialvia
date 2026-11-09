<?php

namespace Tests\Feature\Web;

use App\Livewire\TableauDeBord;
use App\Models\Achat;
use App\Models\Client;
use App\Models\Fournisseur;
use App\Models\LigneVente;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Models\Vente;
use Carbon\CarbonImmutable;
use Database\Seeders\ModulesActifsSeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\TestCase;

/**
 * Ecran web « Tableau de Bord » : lecture seule, chiffres calcules comme le Dart
 * (`tableau_bord_repository_drift.dart`) sur les seules tables du serveur ; le reste est grise.
 *
 * « Maintenant » est fige au 18/11/2026 10:00 (Africa/Porto-Novo = UTC+1, sans heure d'ete) :
 * les bornes de dates se verifient a la microseconde, en heure LOCALE (les colonnes sont en UTC).
 */
class TableauDeBordWebTest extends TestCase
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

    private function utilisateur(string $role, string $username = 'u'): User
    {
        $u = User::query()->where('username', $username)->first();
        if ($u === null) {
            $u = User::factory()->create(['username' => $username, 'name' => ucfirst($username)]);
            $u->assignRole($role);
        }

        return $u;
    }

    /** Instant LOCAL (Porto-Novo) -> UTC, tel qu'il est range en base. */
    private function loc(string $instant): CarbonImmutable
    {
        return CarbonImmutable::parse($instant, 'Africa/Porto-Novo')->utc();
    }

    private function produit(string $nom = 'Poulet', string $cat = 'Volaille'): ProduitVendable
    {
        return ProduitVendable::query()->create([
            'id' => (string) Str::uuid(), 'name' => $nom, 'cat' => $cat, 'price' => 1000, 'unit' => 'pièce',
            'icon' => 'category', 'saisi_le' => now(),
        ]);
    }

    private function vente(array $surcharge = []): Vente
    {
        static $n = 0;
        $n++;
        $v = (new Vente)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => "V-P1-2026-$n",
            'portee_reference' => '', 'client' => 'Amina Bako', 'client_id' => null,
            'date_vente' => $this->loc('2026-11-10 12:00:00'), 'mode' => 'Espèces', 'status' => 'Payée',
            'total' => 0, 'paye' => 0, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $v->save();

        return $v;
    }

    private function ligne(Vente $vente, ProduitVendable $produit, float $qte, float $pu, ?string $nom = null): void
    {
        (new LigneVente)->forceFill([
            'id' => (string) Str::uuid(), 'vente_id' => $vente->id, 'produit_id' => $produit->id,
            'name' => $nom ?? $produit->name, 'qte' => $qte, 'pu' => $pu,
        ])->save();
    }

    /** Vente d'une ligne : le CA de la periode = qte x pu. */
    private function venteLigne(string $quand, ProduitVendable $p, float $qte, float $pu, array $surcharge = []): Vente
    {
        // `+` : la surcharge de l'appelant gagne sur les valeurs par defaut.
        $v = $this->vente($surcharge + ['date_vente' => $this->loc($quand), 'total' => $qte * $pu, 'paye' => $qte * $pu]);
        $this->ligne($v, $p, $qte, $pu);

        return $v;
    }

    private function client(string $nom, array $surcharge = []): Client
    {
        $c = (new Client)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => $nom, 'telephone' => null,
            'date_naissance' => null, 'dernier_contact' => null, 'solde_creance' => 0,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $surcharge));
        $c->save();

        return $c;
    }

    private function achat(string $statut, float $total, float $paye, string $quand = '2026-11-05 09:00:00'): Achat
    {
        $f = Fournisseur::query()->first();
        if ($f === null) {
            $f = (new Fournisseur)->forceFill([
                'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => 'Provenderie du Nord',
                'updated_at' => now(), 'serveur_modifie_le' => now(),
            ]);
            $f->save();
        }
        static $n = 0;
        $n++;
        $a = (new Achat)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => "ACH-P1-2026-$n",
            'portee_reference' => '', 'fournisseur_id' => $f->id, 'date_achat' => $this->loc($quand), 'statut' => $statut,
            'total' => $total, 'paye' => $paye, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);
        $a->save();

        return $a;
    }

    private function tableau(string $role = 'admin')
    {
        return Livewire::actingAs($this->utilisateur($role, $role))->test(TableauDeBord::class);
    }

    // ------------------------------------------------------------------- Acces

    public function test_visiteur_redirige_et_tout_compte_connecte_ouvre_le_tableau(): void
    {
        $this->get('/dashboard')->assertRedirect(route('login'));

        foreach (['admin', 'comptable', 'caissier', 'animalier'] as $role) {
            $this->actingAs($this->utilisateur($role, $role))->get('/dashboard')->assertOk()
                ->assertSee('Bienvenue, '.ucfirst($role))->assertDontSee('arrive bientôt')
                ->assertSee('Rapport généré le 18/11/2026 à 10:00');
        }
    }

    // --------------------------------------------------------- Chiffre d'affaires

    public function test_le_ca_de_la_periode_est_ventile_par_categorie_sans_les_ventes_annulees(): void
    {
        $volaille = $this->produit('Poulet', 'Volaille');
        $annexe = $this->produit('Riz', 'Commerce Annexe');

        $v1 = $this->vente(['date_vente' => $this->loc('2026-11-10 12:00:00')]);
        $this->ligne($v1, $volaille, 2, 1500);   // 3 000 avicole
        $this->ligne($v1, $annexe, 3, 500);      // 1 500 commerce
        $this->venteLigne('2026-11-12 08:00:00', $volaille, 1, 2500);          // 2 500 avicole
        $this->venteLigne('2026-11-11 08:00:00', $volaille, 10, 1000, ['status' => 'Annulée']); // exclue
        $this->venteLigne('2026-10-15 08:00:00', $volaille, 4, 1000);          // hors periode
        $this->venteLigne('2026-11-14 08:00:00', $annexe, 1, 200, ['status' => 'Avance', 'paye' => 0]); // avance comptee (200)

        $this->tableau()
            ->assertSeeHtml('data-kpi="ca">7 200 ')
            ->assertSeeHtml('data-kpi="ca-avicole">5 500<')
            ->assertSeeHtml('data-kpi="ca-commerce">1 700<');
    }

    public function test_le_ca_est_une_somme_de_quantite_fois_prix_et_non_le_total_de_la_vente(): void
    {
        $p = $this->produit();
        // Le total de l'en-tete (ex. remise, livraison) n'est PAS le CA : seules les lignes comptent.
        $v = $this->vente(['total' => 99999, 'paye' => 99999]);
        $this->ligne($v, $p, 2.5, 1000);

        $this->tableau()->assertSeeHtml('data-kpi="ca">2 500 ');
    }

    public function test_les_bornes_de_la_periode_sont_incluses_a_la_microseconde_en_heure_locale(): void
    {
        $p = $this->produit();
        $this->venteLigne('2026-11-09 23:59:59.999999', $p, 1, 1);   // veille : exclue
        $this->venteLigne('2026-11-10 00:00:00', $p, 1, 10);         // 1ere microseconde : incluse
        $this->venteLigne('2026-11-10 23:59:59.999999', $p, 1, 100); // derniere : incluse
        $this->venteLigne('2026-11-11 00:00:00', $p, 1, 1000);       // lendemain : exclue

        $this->tableau()->set('debut', '2026-11-10')->set('fin', '2026-11-10')
            ->assertSeeHtml('data-kpi="ca">110 ');
    }

    public function test_la_periode_par_defaut_est_le_mois_en_cours_jusqu_a_aujourd_hui(): void
    {
        $p = $this->produit();
        $this->venteLigne('2026-10-31 23:59:59', $p, 1, 5);   // octobre
        $this->venteLigne('2026-11-01 00:00:00', $p, 1, 50);  // 1er novembre

        $t = $this->tableau();
        $t->assertSet('debut', '2026-11-01')->assertSet('fin', '2026-11-18')->assertSeeHtml('data-kpi="ca">50 ');
    }

    public function test_une_periode_invalide_retombe_sur_le_mois_en_cours_et_le_dit(): void
    {
        $p = $this->produit();
        $this->venteLigne('2026-11-05 10:00:00', $p, 1, 70);
        $this->venteLigne('2026-10-05 10:00:00', $p, 1, 3);

        $this->tableau()->set('debut', '2026-11-20')->set('fin', '2026-11-01')
            ->assertSeeHtml('data-alerte="periode"')->assertSeeHtml('data-kpi="ca">70 ');
        $this->tableau()->set('debut', 'n importe quoi')
            ->assertSeeHtml('data-alerte="periode"')->assertSeeHtml('data-kpi="ca">70 ');
        $this->tableau()->assertDontSeeHtml('data-alerte="periode"');
    }

    // --------------------------------------------------------- Soldes et clients

    public function test_soldes_restant_dus_sont_les_ventes_avance_sans_filtre_de_date(): void
    {
        $this->vente(['status' => 'Avance', 'total' => 10000, 'paye' => 4000]);
        $this->vente(['status' => 'Avance', 'total' => 5000, 'paye' => 0, 'date_vente' => $this->loc('2026-03-01 08:00:00')]);
        $this->vente(['status' => 'Payée', 'total' => 7000, 'paye' => 1000]);
        $this->vente(['status' => 'Annulée', 'total' => 9000, 'paye' => 0]);

        $this->tableau()
            ->assertSeeHtml('data-kpi="encours">11 000 ')
            ->assertSeeHtml('data-detail="encours">2 vente(s) en avance non soldée(s)<');
    }

    public function test_sans_avance_le_detail_le_dit(): void
    {
        $this->tableau()->assertSeeHtml('data-kpi="encours">0 ')->assertSee('Aucune vente en avance non soldée');
    }

    public function test_clients_enregistres_exclut_les_clients_supprimes(): void
    {
        $this->client('Amina');
        $this->client('Kofi');
        $this->client('Parti', ['supprime_le' => now()]);

        $this->tableau()->assertSeeHtml('data-kpi="clients">2<');
    }

    // ---------------------------------------------------------- Dettes fournisseurs

    public function test_dettes_fournisseurs_sont_les_achats_non_annules_non_soldes(): void
    {
        $this->achat('Commandé', 8000, 3000);                       // 5 000
        $this->achat('Livré', 4000, 1000, '2026-02-01 09:00:00');   // 3 000 (sans filtre de date)
        $this->achat('Livré', 2000, 2000);                          // solde : exclu
        $this->achat('Annulé', 9000, 0);                            // annule : exclu

        $this->tableau()
            ->assertSeeHtml('data-kpi="dettes">8 000 ')
            ->assertSeeHtml('data-detail="dettes">2 commande(s) non soldée(s)<');
    }

    public function test_sans_dette_le_detail_le_dit(): void
    {
        $this->tableau()->assertSeeHtml('data-kpi="dettes">0 ')->assertSee('Aucune commande non soldée');
    }

    // ------------------------------------------------------------------- Graphique

    public function test_la_courbe_donne_le_ca_des_six_derniers_mois_civils_locaux(): void
    {
        $p = $this->produit();
        $this->venteLigne('2026-11-17 10:00:00', $p, 1, 400);             // nov
        $this->venteLigne('2026-10-31 23:59:59.999999', $p, 1, 5000);     // oct (derniere microseconde locale)
        $this->venteLigne('2026-11-01 00:00:00', $p, 1, 100);             // nov (1ere microseconde locale)
        $this->venteLigne('2026-06-01 00:00:00', $p, 1, 1000);            // juin : 6e mois, inclus
        $this->venteLigne('2026-05-31 23:59:59.999999', $p, 1, 9999);     // mai : trop ancien
        $this->venteLigne('2026-09-10 10:00:00', $p, 3, 100, ['status' => 'Annulée']); // annulee : 0

        $this->tableau()
            ->assertSeeHtml('data-mois="2026-06" data-ca="1000"')
            ->assertSeeHtml('data-mois="2026-09" data-ca="0"')
            ->assertSeeHtml('data-mois="2026-10" data-ca="5000"')
            ->assertSeeHtml('data-mois="2026-11" data-ca="500"')
            ->assertDontSeeHtml('data-mois="2026-05"')
            ->assertSeeHtmlInOrder(['>Jun<', '>Jul<', '>Aoû<', '>Sep<', '>Oct<', '>Nov<'])
            ->assertSee('Les dépenses ne sont pas connues du serveur');
    }

    public function test_la_courbe_ignore_le_filtre_de_periode(): void
    {
        $p = $this->produit();
        $this->venteLigne('2026-10-10 10:00:00', $p, 1, 5000);

        $this->tableau()->set('debut', '2026-11-01')->assertSeeHtml('data-mois="2026-10" data-ca="5000"')
            ->assertSeeHtml('data-kpi="ca">0 ');
    }

    // ---------------------------------------------------- Meilleures ventes, recentes

    public function test_meilleures_ventes_cumulent_par_produit_et_se_limitent_a_cinq(): void
    {
        $p = $this->produit();
        $annexe = $this->produit('Riz', 'Commerce Annexe');
        $this->venteLigne('2026-11-02 08:00:00', $p, 1, 1000);
        $this->venteLigne('2026-11-03 08:00:00', $p, 2, 1000);          // Poulet : 3 000, qte 3
        $this->venteLigne('2026-11-03 09:00:00', $annexe, 1, 9000);     // Riz : 9 000
        foreach ([['A', 100], ['B', 200], ['C', 300], ['D', 400]] as [$nom, $prix]) {
            $this->venteLigne('2026-11-04 08:00:00', $this->produit($nom), 1, $prix);
        }
        $this->venteLigne('2026-11-04 10:00:00', $this->produit('Z'), 1, 50);        // 6e : coupe
        $this->venteLigne('2026-11-04 11:00:00', $p, 5, 10000, ['status' => 'Annulée']); // annulee : ignoree
        $this->venteLigne('2026-09-04 11:00:00', $p, 5, 10000);                      // hors periode

        $this->tableau()
            ->assertSeeHtmlInOrder(['data-meilleure="Riz"', 'data-meilleure="Poulet"', 'data-meilleure="D"', 'data-meilleure="C"', 'data-meilleure="B"'])
            ->assertDontSeeHtml('data-meilleure="A"')->assertDontSeeHtml('data-meilleure="Z"')
            ->assertSeeInOrder(['Riz', 'Commerce', '9 000 F', 'Poulet', 'Avicole', '3', '3 000 F']);
    }

    public function test_transactions_recentes_les_trois_dernieres_avance_montre_le_paye(): void
    {
        $p = $this->produit();
        $this->venteLigne('2026-11-01 08:00:00', $p, 1, 100, ['reference' => 'V-ANCIENNE']);
        $this->venteLigne('2026-11-02 08:00:00', $p, 1, 200, ['reference' => 'V-DEUX']);
        $this->venteLigne('2026-11-03 08:00:00', $p, 1, 300, ['reference' => 'V-TROIS', 'status' => 'Avance', 'total' => 3000, 'paye' => 300]);
        $this->venteLigne('2026-11-04 08:00:00', $p, 1, 400, ['reference' => 'V-QUATRE']);

        $this->tableau()
            ->assertSeeHtmlInOrder(['data-recente="V-QUATRE"', 'data-recente="V-TROIS"', 'data-recente="V-DEUX"'])
            ->assertDontSeeHtml('data-recente="V-ANCIENNE"')
            ->assertSeeInOrder(['V-TROIS', '300 F (avance)']);
    }

    public function test_revenu_de_la_semaine_est_glissant_sur_sept_jours_sans_les_annulees(): void
    {
        $p = $this->produit();
        $this->venteLigne('2026-11-11 10:00:01', $p, 1, 10);                      // dans les 7 jours
        $this->venteLigne('2026-11-11 09:59:59', $p, 1, 1000);                    // trop ancien
        $this->venteLigne('2026-11-17 10:00:00', $p, 1, 100, ['status' => 'Annulée']);

        $this->tableau()->assertSeeHtml('data-kpi="semaine">10 F<');
    }

    // ---------------------------------------------------------------- Droits

    public function test_un_animalier_ne_voit_aucune_donnee_de_vente_ni_d_achat(): void
    {
        $p = $this->produit('Poulet secret');
        $this->venteLigne('2026-11-10 10:00:00', $p, 1, 4321, ['reference' => 'V-SECRETE']);
        $this->vente(['status' => 'Avance', 'total' => 777000, 'paye' => 0]);
        $this->client('Client secret');
        $this->achat('Commandé', 654000, 0);

        $this->tableau('animalier')
            ->assertDontSeeHtml('data-carte="ca"')->assertDontSeeHtml('data-carte="encours"')
            ->assertDontSeeHtml('data-carte="clients"')->assertDontSeeHtml('data-carte="dettes"')
            ->assertDontSeeHtml('data-bloc="courbe"')->assertDontSeeHtml('data-bloc="meilleures"')
            ->assertDontSeeHtml('data-bloc="recentes"')
            ->assertDontSee('V-SECRETE')->assertDontSee('4 321')->assertDontSee('777 000')
            ->assertDontSee('654 000')->assertDontSee('Poulet secret')->assertDontSee('Client secret')
            ->assertDontSee('Période invalide')->assertDontSee('Enregistrer une Vente')
            ->assertSeeHtml('data-carte-poste="Effectif Cheptel"')
            ->assertSeeHtml('data-carte-poste="Cycles Couveuse en Cours"')
            ->assertDontSeeHtml('data-carte-poste="Trésorerie"')
            ->assertDontSeeHtml('data-carte-poste="Dépenses"')
            ->assertDontSeeHtml('data-carte-poste="Stock Critique"')
            ->assertSee('Dashboard Élevage');
    }

    public function test_un_caissier_voit_les_ventes_mais_pas_les_dettes_ni_les_cartes_des_autres_modules(): void
    {
        $this->achat('Commandé', 654000, 0);

        $this->tableau('caissier')
            ->assertSeeHtml('data-carte="ca"')->assertSeeHtml('data-carte="encours"')->assertSeeHtml('data-carte="clients"')
            ->assertSeeHtml('data-bloc="courbe"')
            ->assertDontSeeHtml('data-carte="dettes"')->assertDontSee('654 000')
            ->assertDontSeeHtml('data-carte-poste=')
            ->assertSee('Enregistrer une Vente')->assertDontSee('Dashboard Élevage');
    }

    public function test_un_comptable_voit_ventes_dettes_et_les_cartes_comptables_grisees(): void
    {
        $this->tableau('comptable')
            ->assertSeeHtml('data-carte="ca"')->assertSeeHtml('data-carte="dettes"')
            ->assertSeeHtml('data-carte-poste="Trésorerie"')->assertSeeHtml('data-carte-poste="Dépenses"')
            ->assertSeeHtml('data-carte-poste="Résultat Net"')
            ->assertDontSeeHtml('data-carte-poste="Stock Critique"')
            ->assertDontSeeHtml('data-carte-poste="Effectif Cheptel"')
            ->assertDontSeeHtml('data-carte-poste="Cycles Couveuse en Cours"');
    }

    public function test_l_administrateur_voit_toutes_les_cartes(): void
    {
        $t = $this->tableau('admin');
        foreach (['ca', 'encours', 'clients', 'dettes'] as $carte) {
            $t->assertSeeHtml('data-carte="'.$carte.'"');
        }
        foreach (['Trésorerie', 'Dépenses', 'Résultat Net', 'Stock Critique', 'Effectif Cheptel', 'Cycles Couveuse en Cours'] as $carte) {
            $t->assertSeeHtml('data-carte-poste="'.$carte.'"');
        }
    }

    // --------------------------------------------------------- Cartes « sur le poste »

    public function test_les_cartes_absentes_du_serveur_sont_grisees_sans_aucun_chiffre(): void
    {
        $html = $this->tableau('admin')->html();

        $this->assertSame(6, substr_count($html, 'data-carte-poste='));
        $this->assertSame(6, substr_count($html, 'Disponible sur le poste</p>'));
        preg_match_all('#data-carte-poste="[^"]+".*?</div>#s', $html, $cartes);
        $this->assertCount(6, $cartes[0]);
        foreach ($cartes[0] as $carte) {
            $this->assertStringContainsString('>—</p>', $carte);
            $this->assertDoesNotMatchRegularExpression('/\d/', html_entity_decode(strip_tags(preg_replace('/data-carte-poste="[^"]*"/', '', $carte))));
        }
        $this->assertSame(6, substr_count($html, 'border-outline-variant bg-surface-zebra p-md text-outline" data-carte-poste='));
    }

    public function test_l_ecran_declare_ses_ecarts_avec_le_poste(): void
    {
        $this->tableau('admin')
            ->assertSeeHtml('data-bloc="ecarts"')
            ->assertSee('Restent au poste')
            ->assertSee('cycles de couveuse')->assertSee('rappels de prophylaxie')->assertSee('export d\'état', false);
    }

    public function test_l_ecran_est_en_lecture_seule(): void
    {
        $this->assertSame(
            ['mount', 'render'],
            array_values(array_diff(
                array_map(fn ($m) => $m->getName(), (new \ReflectionClass(TableauDeBord::class))->getMethods(\ReflectionMethod::IS_PUBLIC)),
                array_map(fn ($m) => $m->getName(), (new \ReflectionClass(\Livewire\Component::class))->getMethods()),
            )),
        );
        $this->assertSame(0, Vente::query()->count() + Achat::query()->count());
        $this->tableau('admin');
        $this->assertSame(0, Vente::query()->count() + Achat::query()->count());
    }
}
