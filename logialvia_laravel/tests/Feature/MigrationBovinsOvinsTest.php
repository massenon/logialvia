<?php

namespace Tests\Feature;

use App\Support\FilieresElevage;
use App\Support\UuidDeterministe;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Migration 2026_11_11 (DV-22) : la filiere Bovins devient Ovins sur le serveur, comme au poste
 * (schema v51). Renommage de toutes les tables, identifiants deterministes recalcules, valeurs
 * d'ouverture reecrites, SANS doublon, rejouable.
 */
class MigrationBovinsOvinsTest extends TestCase
{
    use RefreshDatabase;

    private const FICHIER = 'database/migrations/2026_11_11_090000_renomme_bovins_en_ovins.php';

    private const JOUR = '2026-11-05';

    private string $poste;

    private string $echeanceAncienne;

    private function migrer(): void
    {
        (require base_path(self::FICHIER))->up();
    }

    private function maintenant(): string
    {
        return now('UTC')->format('Y-m-d H:i:s.u');
    }

    /** Un serveur d'hier : des lignes `bovins` dans toutes les tables. */
    private function serveurDHier(bool $ovinsDejaLa = false): void
    {
        $maj = '2026-11-01 08:00:00.000000';
        $this->poste = (string) Str::uuid();
        $fiche = [
            'achat' => 0, 'ne' => 0, 'vente' => 0, 'mort_cat1' => 0, 'mort_cat2' => 0, 'mort_cat3' => 0,
            'don_cat1' => 0, 'don_cat2' => 0, 'don_cat3' => 0, 'effectif' => 10,
            'eff_cat1_day' => 4, 'eff_cat2_day' => 3, 'eff_cat3_day' => 3,
            'traitement_valide' => false, 'is_recorded' => true,
        ];

        DB::table('modules_actifs')->where('module_id', 'ovins')->delete();
        DB::table('modules_actifs')->insert([
            'id' => (string) Str::uuid(), 'module_id' => 'bovins', 'is_actif' => true, 'espece' => 'bovins',
            'created_at' => $maj, 'updated_at' => $maj,
        ]);
        DB::table('fiche_journee')->insert($fiche + [
            'id' => UuidDeterministe::ficheJournee('bovins', self::JOUR), 'espece' => 'bovins', 'date' => self::JOUR,
            'device_id' => $this->poste, 'updated_at' => $maj, 'serveur_modifie_le' => $maj,
        ]);
        DB::table('fiche_ventes_jour')->insert([
            'id' => UuidDeterministe::ventesJour('bovins', self::JOUR, $this->poste), 'device_id' => $this->poste,
            'espece' => 'bovins', 'date' => self::JOUR, 'qte' => 3, 'updated_at' => $maj, 'serveur_modifie_le' => $maj,
        ]);
        foreach ([['Veau', 1500, false], ['Embouche', 7000, false], ['Reproducteur', 9000, false], ['Taurillon', 4000, true]] as [$stade, $ration, $confirme]) {
            DB::table('baremes_ration')->insert([
                'id' => $stade === 'Taurillon' ? 'aaaaaaaa-0000-4000-8000-000000000001' : FilieresElevage::idBareme('bovins', $stade),
                'espece' => 'bovins', 'stade' => $stade, 'ration_grammes_par_jour' => $ration, 'confirme' => $confirme,
                'saisi_le' => $maj, 'created_at' => $maj, 'updated_at' => $maj,
            ]);
        }
        foreach ([[0, 150000, 3.5], [150000, 300000, 3.0], [300000, null, 2.5]] as [$min, $max, $taux]) {
            DB::table('taux_ration_poids')->insert([
                'id' => FilieresElevage::idTaux('bovins', $min), 'espece' => 'bovins', 'poids_min_g' => $min,
                'poids_max_g' => $max, 'taux_pourcent' => $taux, 'confirme' => false,
                'saisi_le' => $maj, 'created_at' => $maj, 'updated_at' => $maj,
            ]);
        }
        $traitement = 'Vaccin péripneumonie contagieuse bovine (PPCB)';
        $this->echeanceAncienne = FilieresElevage::idEcheance('bovins', 15, $traitement, 'Vaccin T1/44');
        DB::table('calendrier_prophylaxie')->insert([
            'id' => $this->echeanceAncienne, 'espece' => 'bovins', 'jour_cycle' => 15, 'traitement' => $traitement,
            'produit' => 'Vaccin T1/44', 'remanence_jours' => 0, 'dose' => '1 dose',
            'saisi_le' => $maj, 'created_at' => $maj, 'updated_at' => $maj,
        ]);
        DB::table('bandes')->insert([
            'id' => 'bbbbbbbb-0000-4000-8000-000000000001', 'espece' => 'bovins', 'code' => 'PARC1',
            'date_mise_en_bande' => '2026-10-01', 'updated_at' => $maj, 'serveur_modifie_le' => $maj,
        ]);
        DB::table('soins_calendrier')->insert([
            'id' => 'cccccccc-0000-4000-8000-000000000001', 'espece' => 'bovins', 'date_prevue' => self::JOUR,
            'type_soin' => 'Vaccination', 'statut' => 'Planifié', 'echeance_prophylaxie_id' => $this->echeanceAncienne,
            'updated_at' => $maj, 'serveur_modifie_le' => $maj,
        ]);
        DB::table('infirmerie')->insert([
            'id' => 'dddddddd-0000-4000-8000-000000000001', 'date_entree' => '2026-11-01', 'sujet' => 'Brebis 3',
            'motif' => 'Boiterie', 'niveau_isolement' => 'Infirmerie', 'statut' => 'En cours', 'espece' => 'bovins',
            'updated_at' => $maj, 'serveur_modifie_le' => $maj,
        ]);
        DB::table('produits_vendables')->insert([
            'id' => 'eeeeeeee-0000-4000-8000-000000000001', 'name' => 'Animal d\'embouche', 'cat' => 'Élevage bovin',
            'price' => 150000, 'unit' => 'u', 'icon' => 'grass', 'espece' => 'bovins',
            'saisi_le' => $maj, 'created_at' => $maj, 'updated_at' => $maj,
        ]);

        if ($ovinsDejaLa) {
            DB::table('modules_actifs')->insert([
                'id' => (string) Str::uuid(), 'module_id' => 'ovins', 'is_actif' => false, 'espece' => 'ovins',
                'created_at' => $maj, 'updated_at' => $maj,
            ]);
            DB::table('baremes_ration')->insert([
                'id' => FilieresElevage::idBareme('ovins', 'Embouche'), 'espece' => 'ovins', 'stade' => 'Embouche',
                'ration_grammes_par_jour' => 650, 'confirme' => true, 'saisi_le' => $maj, 'created_at' => $maj, 'updated_at' => $maj,
            ]);
        }
    }

    private function restantsBovins(): int
    {
        $total = 0;
        foreach (Schema::getTables() as $table) {
            foreach (['espece', 'module_id'] as $colonne) {
                if (Schema::hasColumn($table['name'], $colonne)) {
                    $total += DB::table($table['name'])->where($colonne, 'bovins')->count();
                }
            }
        }

        return $total;
    }

    public function test_toutes_les_lignes_bovins_passent_a_ovins(): void
    {
        $this->serveurDHier();

        $this->migrer();

        // Les baremes archives mis a part, plus rien ne porte l'ancien nom.
        $this->assertSame(0, $this->restantsBovins());
        $this->assertSame(['ovins'], DB::table('modules_actifs')->where('espece', 'ovins')->pluck('module_id')->all());
        $this->assertTrue((bool) DB::table('modules_actifs')->where('module_id', 'ovins')->value('is_actif'));

        $this->assertSame(UuidDeterministe::ficheJournee('ovins', self::JOUR), DB::table('fiche_journee')->sole()->id);
        $this->assertSame(UuidDeterministe::ventesJour('ovins', self::JOUR, $this->poste), DB::table('fiche_ventes_jour')->sole()->id);
        $this->assertSame(3, (int) DB::table('fiche_ventes_jour')->sole()->qte);

        // Les faits renommes redescendent : leur curseur avance, leur instant de saisie reste.
        $this->assertGreaterThan('2026-11-01 08:00:00', DB::table('fiche_journee')->sole()->serveur_modifie_le);
        $this->assertSame('2026-11-01 08:00:00.000000', substr(DB::table('fiche_journee')->sole()->updated_at, 0, 26));

        $baremes = DB::table('baremes_ration')->where('espece', 'ovins')->orderBy('stade')->get();
        $this->assertSame([['Agneau', 300], ['Embouche', 600], ['Reproducteur', 800], ['Taurillon', 4000]],
            $baremes->map(fn ($b) => [$b->stade, (int) $b->ration_grammes_par_jour])->all());
        $this->assertSame(FilieresElevage::idBareme('ovins', 'Agneau'), $baremes[0]->id);
        $this->assertSame('aaaaaaaa-0000-4000-8000-000000000001', $baremes[3]->id);

        $taux = DB::table('taux_ration_poids')->where('espece', 'ovins')->orderBy('poids_min_g')->get();
        $this->assertSame([[0, 15000, 4.0], [15000, 30000, 3.5], [30000, null, 3.0]],
            $taux->map(fn ($t) => [(int) $t->poids_min_g, $t->poids_max_g === null ? null : (int) $t->poids_max_g, (float) $t->taux_pourcent])->all());
        $this->assertSame(FilieresElevage::idTaux('ovins', 15000), $taux[1]->id);

        $echeance = DB::table('calendrier_prophylaxie')->sole();
        $this->assertSame('Vaccin peste des petits ruminants (PPR)', $echeance->traitement);
        $this->assertSame(FilieresElevage::idEcheance('ovins', 15, $echeance->traitement, $echeance->produit), $echeance->id);
        $this->assertSame($echeance->id, DB::table('soins_calendrier')->sole()->echeance_prophylaxie_id);

        $this->assertSame('ovins', DB::table('bandes')->sole()->espece);
        $this->assertSame('ovins', DB::table('infirmerie')->sole()->espece);
        $produit = DB::table('produits_vendables')->sole();
        $this->assertSame(['Élevage ovin', 'ovins'], [$produit->cat, $produit->espece]);
    }

    public function test_rejouee_elle_ne_change_plus_rien(): void
    {
        $this->serveurDHier();
        $this->migrer();
        $avant = [];
        foreach (['modules_actifs', 'fiche_journee', 'fiche_ventes_jour', 'baremes_ration', 'taux_ration_poids',
            'calendrier_prophylaxie', 'bandes', 'soins_calendrier', 'infirmerie', 'produits_vendables'] as $table) {
            $avant[$table] = DB::table($table)->orderBy('id')->get()->all();
        }

        $this->migrer();
        $this->migrer();

        foreach ($avant as $table => $lignes) {
            $this->assertEquals($lignes, DB::table($table)->orderBy('id')->get()->all(), $table);
        }
    }

    public function test_la_ligne_ovins_existante_l_emporte_sans_doublon(): void
    {
        $this->serveurDHier(ovinsDejaLa: true);

        $this->migrer();

        $this->assertSame(0, $this->restantsBovins() - DB::table('baremes_ration')->where('espece', 'bovins')->count());
        $this->assertSame(1, DB::table('modules_actifs')->whereIn('module_id', ['ovins', 'bovins'])->count());
        $this->assertFalse((bool) DB::table('modules_actifs')->where('module_id', 'ovins')->value('is_actif'));
        // « Embouche » ovin deja la (650, confirme) : sa valeur reste ; la ligne bovine est ARCHIVEE, pas effacee.
        $embouche = DB::table('baremes_ration')->where('espece', 'ovins')->where('stade', 'Embouche')->sole();
        $this->assertSame([650, 1], [(int) $embouche->ration_grammes_par_jour, (int) $embouche->confirme]);
        $this->assertNull($embouche->archive_le);
        $bovine = DB::table('baremes_ration')->where('espece', 'bovins')->sole();
        $this->assertNotNull($bovine->archive_le);
    }
}
