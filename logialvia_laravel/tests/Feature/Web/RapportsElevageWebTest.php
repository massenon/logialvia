<?php

namespace Tests\Feature\Web;

use App\Livewire\Rapports;
use App\Models\BaremeRation;
use App\Models\CycleCouveuse;
use App\Models\EntreeInfirmerie;
use App\Models\FicheJournee;
use App\Models\SoinCalendrier;
use App\Models\TauxRationPoids;
use App\Services\Rapports\RapportElevage;
use App\Support\FilieresElevage;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Concerns\JeuRapports;
use Tests\TestCase;

/**
 * Rapports & Etats, onglet « Rapport Élevage » (Dart : `_recensement`, `_mouvementsElevage`, `_couvoir`,
 * `CalculFicheJournaliere.provendeTotaleGrammes`). Periode par defaut du 01/11 au 18/11/2026.
 *
 * Jeu construit a la main (voir `poserLeJeu()`), chiffres attendus ecrits a l'avance.
 */
class RapportsElevageWebTest extends TestCase
{
    use JeuRapports, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerRapports();
    }

    private function rapport(): \Livewire\Features\SupportTesting\Testable
    {
        $this->actingAs($this->utilisateurRapports('comptable', 'paul'));

        return Livewire::test(Rapports::class)->set('onglet', 'elevage');
    }

    /** @param list<int> $cats */
    private function fiche(string $espece, string $date, int $effectif, array $cats, array $plus = []): void
    {
        (new FicheJournee)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'espece' => $espece, 'date' => $date, 'effectif' => $effectif,
            'eff_cat1_day' => $cats[0] ?? 0, 'eff_cat2_day' => $cats[1] ?? 0, 'eff_cat3_day' => $cats[2] ?? 0, 'eff_cat4_day' => $cats[3] ?? null,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $plus))->save();
    }

    private function infirmerie(string $date, ?string $espece, string $motif, string $statut): void
    {
        (new EntreeInfirmerie)->forceFill([
            'id' => (string) Str::uuid(), 'date_entree' => $date, 'sujet' => 'Sujet', 'motif' => $motif,
            'niveau_isolement' => 'Infirmerie', 'statut' => $statut, 'espece' => $espece,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ])->save();
    }

    private function soin(string $espece, string $date, string $type, string $statut, ?string $produit = null, array $plus = []): void
    {
        (new SoinCalendrier)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'espece' => $espece, 'date_prevue' => $date, 'type_soin' => $type, 'statut' => $statut,
            'produit' => $produit, 'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $plus))->save();
    }

    private function cycle(string $code, string $espece, string $date, int $oeufs, ?int $nes, string $statut, array $plus = []): void
    {
        (new CycleCouveuse)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'code_incubation' => $code, 'portee_code' => '', 'espece' => $espece,
            'date_incubation' => $date, 'oeufs_couves' => $oeufs, 'poussins_nes' => $nes, 'statut' => $statut,
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ], $plus))->save();
    }

    private function bareme(string $espece, string $stade, int $ration, ?string $archive = null): void
    {
        (new BaremeRation)->forceFill([
            'id' => (string) Str::uuid(), 'espece' => $espece, 'stade' => $stade, 'ration_grammes_par_jour' => $ration,
            'confirme' => true, 'saisi_le' => now(), 'archive_le' => $archive,
        ])->save();
    }

    private function taux(string $espece, int $min, ?int $max, float $pourcent, ?string $archive = null): void
    {
        (new TauxRationPoids)->forceFill([
            'id' => (string) Str::uuid(), 'espece' => $espece, 'poids_min_g' => $min, 'poids_max_g' => $max,
            'taux_pourcent' => $pourcent, 'confirme' => true, 'saisi_le' => now(), 'archive_le' => $archive,
        ])->save();
    }

    private function poserLeJeu(): void
    {
        // Goliaths : 3 categories (Poussins, Goliathau, Mature). La derniere journee DE LA PERIODE est celle du 10/11.
        $this->fiche('goliaths', '2026-10-31', 999, [9, 9, 9], ['vente' => 50]);
        $this->fiche('goliaths', '2026-11-02', 100, [40, 30, 30], ['mort_cat1' => 1, 'mort_cat2' => 0, 'mort_cat3' => 2, 'don_cat2' => 1, 'vente' => 3]);
        $this->fiche('goliaths', '2026-11-10', 95, [35, 30, 30], ['mort_cat1' => 2, 'mort_cat2' => 1, 'don_cat3' => 3, 'vente' => 2]);
        $this->fiche('goliaths', '2026-11-19', 80, [30, 25, 25]);   // apres la periode : compte dans l'effectif total, pas dans le recensement

        // Pondeuses : 4 categories (le `4` existe).
        $this->fiche('pondeuses', '2026-11-05', 100, [10, 20, 30, 40], ['mort_cat1' => 1, 'mort_cat2' => 1, 'mort_cat3' => 1, 'mort_cat4' => 2, 'don_cat4' => 1]);

        // Bovins rationnes sur le poids vif : 2 500 kg pour 10 tetes = 250 kg en moyenne.
        $this->fiche('bovins', '2026-11-12', 10, [2, 3, 5], ['poids_general_g' => 2500000]);
        $this->taux('bovins', 0, 200000, 3.0);
        $this->taux('bovins', 200000, null, 2.5);
        $this->taux('bovins', 150000, null, 99.0, '2026-11-01 00:00:00');   // archive : ignore (sinon il passerait devant la 2e classe)

        // Poissons-chats rationnes sur le poids vif mais SANS pesee : repli par tete.
        $this->fiche('poissons-chats', '2026-11-03', 1000, [500, 300, 200]);

        // Baremes : Poulette 100 g (actif) ; Pondeuse 999 g (archive : le defaut 110 reste) ; un autre espece n'a pas d'effet.
        $this->bareme('pondeuses', 'Poulette', 100);
        $this->bareme('pondeuses', 'Pondeuse', 999, '2026-11-01 00:00:00');
        $this->bareme('goliaths', 'Mature', 999, '2026-11-01 00:00:00');
        // Actifs mais d'une AUTRE espece : ni le stade « Poulette » ni la classe 0+ des goliaths ne touchent les pondeuses et les bovins.
        $this->bareme('goliaths', 'Poulette', 999);
        $this->taux('goliaths', 0, null, 50.0);

        // Infirmerie.
        $this->infirmerie('2026-11-03', 'goliaths', 'Fièvre', 'En cours');
        $this->infirmerie('2026-11-09', 'goliaths', 'Boiterie', 'Réintégré');
        $this->infirmerie('2026-11-10', 'goliaths', 'Diarrhée', 'Décédé');
        $this->infirmerie('2026-10-30', 'goliaths', 'Toux', 'En cours');
        $this->infirmerie('2026-10-20', 'pondeuses', 'Coryza', 'En cours');
        $this->infirmerie('2026-11-04', null, 'Fièvre', 'En cours');

        // Soins.
        $this->soin('goliaths', '2026-10-31', 'Antibiotique', 'Effectué', 'Oxytet');
        $this->soin('goliaths', '2026-11-05', 'Vaccination', 'Effectué', 'Newcastle');
        $this->soin('goliaths', '2026-11-12', 'Vermifuge', 'Effectué', null);
        $this->soin('goliaths', '2026-11-15', 'Déparasitage', 'Planifié', 'Ivermectine');
        $this->soin('pondeuses', '2026-11-06', 'Vaccination', 'Effectué', 'Gumboro', ['updated_at' => now()]);
        // Meme jour que la precedente, saisi AVANT, identifiant le plus petit : ne doit pas passer devant.
        $this->soin('pondeuses', '2026-11-06', 'Complément', 'Effectué', '', ['id' => '00000000-0000-4000-8000-000000000000', 'updated_at' => now()->subHour()]);

        // Ventes d'une espece : montant REEL des lignes (qte x pu), annulees et hors periode exclues.
        $v = $this->vente(['date_vente' => $this->loc('2026-11-03 12:00:00')]);
        $this->ligneVente($v, 2, 6000, 'goliaths');                        // 12 000
        $v = $this->vente(['date_vente' => $this->loc('2026-11-18 23:59:59')]);
        $this->ligneVente($v, 1, 5000, 'goliaths');                        // 5 000 (dernier instant inclus)
        $v = $this->vente(['date_vente' => $this->loc('2026-11-01 00:00:00')]);
        $this->ligneVente($v, 3, 1000, 'goliaths');                        // 3 000 (premier instant inclus)
        $v = $this->vente(['date_vente' => $this->loc('2026-11-19 00:00:00')]);
        $this->ligneVente($v, 1, 100000, 'goliaths');                      // apres
        $v = $this->vente(['date_vente' => $this->loc('2026-10-31 23:59:59')]);
        $this->ligneVente($v, 1, 40000, 'goliaths');                       // avant
        $v = $this->vente(['date_vente' => $this->loc('2026-11-04 12:00:00'), 'status' => 'Annulée']);
        $this->ligneVente($v, 1, 9999, 'goliaths');                        // annulee
        $v = $this->vente(['date_vente' => $this->loc('2026-11-03 12:00:00')]);
        $this->ligneVente($v, 1, 7777, 'pintades');                        // autre espece
        $v = $this->vente(['date_vente' => $this->loc('2026-11-03 13:00:00')]);
        $this->ligneVente($v, 1, 8888);                                    // sans espece

        // Couvoir.
        $this->cycle('LOT-A', 'goliath', '2026-10-01', 100, 80, 'Éclosion Effectuée');
        $this->cycle('LOT-B', 'pintade', '2026-11-02', 50, null, 'En Incubation');
        $this->cycle('LOT-C', 'goliath', '2026-09-01', 60, 30, 'Remplacé');
        $this->cycle('LOT-D', 'goliath', '2026-11-01', 1000, 1, 'Éclosion Effectuée', ['supprime_le' => now()]);   // pierre tombale
    }

    public function test_kpi_de_l_elevage(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport();

        // Derniere fiche de CHAQUE filiere, hors periode comprise : 80 (goliaths 19/11) + 100 + 10 + 1 000.
        $this->assertSame('1190', $this->nombre($c, 'effectif-total'));
        // Infirmerie « En cours » seulement : 3 goliaths/pondeuses + 1 sans espece ; le reintegre et le decede n'en sont plus.
        $this->assertSame('4', $this->nombre($c, 'sujets-malades'));
        // (80 + 30) / (100 + 60) = 68,75 % -> 68,8 % ; le cycle supprime (1/1 000) ne compte pas.
        $this->assertSame('68,8 %', $this->nombre($c, 'taux-eclosion'));
        $this->assertSame('1', $this->nombre($c, 'cycles-en-cours'));
        $c->assertSee('Sur les cycles éclos');
    }

    public function test_recensement_et_structure_du_cheptel(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport();

        // Ordre des filieres du Dart ; derniere journee de la periode ; geniteurs = derniere categorie ; jeunes = les autres.
        $this->assertSame([
            ['Goliaths', '95', '30', '65', '6', '4', '2'],
            ['Bovins', '10', '5', '5', '0', '0', '0'],
            ['Poissons-Chats', '1000', '200', '800', '0', '0', '0'],
            ['Pondeuses', '100', '40', '60', '5', '1', '1'],
        ], $this->lignes($c, "//table[@data-table='recensement']/tbody/tr"));
    }

    public function test_mouvements_traitements_et_ventes(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport();

        $this->assertSame([
            ['Goliaths', '5', '20 000', '95', 'Vermifuge', '3 sujet(s) — Diarrhée, Boiterie, Fièvre', '6 150'],
            ['Bovins', '0', '—', '10', 'Aucun traitement administré', 'Aucun signe observé', '62 500'],
            ['Poissons-Chats', '0', '—', '1000', 'Aucun traitement administré', 'Aucun signe observé', '3 000'],
            ['Pondeuses', '0', '—', '100', 'Vaccination (Gumboro)', 'Aucun signe observé', '8 900'],
        ], $this->lignes($c, "//table[@data-table='mouvements']/tbody/tr"));
    }

    public function test_le_couvoir_calcule_eclosion_taux_et_morts(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport();

        // Du plus recent au plus ancien ; la pintade incube 28 jours, le goliath 21 ; le cycle supprime est absent.
        $this->assertSame([
            ['LOT-B', '02/11/2026', '30/11/2026', '50', '—', '—', '—', 'En Incubation'],
            ['LOT-A', '01/10/2026', '22/10/2026', '100', '80', '80,0 %', '20', 'Éclosion Effectuée'],
            ['LOT-C', '01/09/2026', '22/09/2026', '60', '30', '50,0 %', '30', 'Remplacé'],
        ], $this->lignes($c, "//table[@data-table='couvoir']/tbody/tr"));
        // Seul « Éclosion Effectuée » est vert (le poste testait « Éclos », libelle qu'aucun cycle ne porte).
        $this->assertCount(1, $this->textes($c, "//tr[@data-cycle='LOT-A']//span[contains(@class,'bg-success-container')]"));
        $this->assertSame([], $this->textes($c, "//tr[@data-cycle='LOT-C']//span[contains(@class,'bg-success-container')]"));
    }

    public function test_la_periode_borne_le_recensement_mais_pas_le_couvoir_ni_les_kpi_globaux(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport()->set('debut', '2026-11-02')->set('fin', '2026-11-02');

        // Seule la journee du 02/11 des goliaths : effectif 100, morts 3, dons 1, vendus 3 ; les autres filieres n'ont rien ce jour-la.
        $this->assertSame([['Goliaths', '100', '30', '70', '3', '1', '2']], $this->lignes($c, "//table[@data-table='recensement']/tbody/tr"));
        $mouvements = $this->lignes($c, "//table[@data-table='mouvements']/tbody/tr");
        $this->assertSame(['Goliaths', '3', '—', '100', 'Aucun traitement administré', 'Aucun signe observé'], array_slice($mouvements[0], 0, 6));
        $this->assertSame('1190', $this->nombre($c, 'effectif-total'));
        $this->assertCount(3, $this->lignes($c, "//table[@data-table='couvoir']/tbody/tr"));
        // Rations par defaut (le bareme Goliaths « Mature » est archive) : 40 x 30 + 30 x 60 + 30 x 110 = 1 200 + 1 800 + 3 300.
        $this->assertSame('6 300', $mouvements[0][6]);
    }

    public function test_sans_donnee_chaque_tableau_dit_pourquoi_il_est_vide(): void
    {
        $c = $this->rapport();

        $c->assertSeeHtml('data-vide="recensement"')->assertSee('Aucune journée d\'élevage saisie sur la période.', false);
        $c->assertSeeHtml('data-vide="mouvements"')->assertSee('Aucun mouvement d\'élevage sur la période sélectionnée.', false);
        $c->assertSeeHtml('data-vide="couvoir"')->assertSee('Aucun cycle d\'incubation enregistré.', false);
        $this->assertSame('—', $this->nombre($c, 'taux-eclosion'));
        $c->assertSee('Aucun cycle éclos à ce jour');
        $this->assertSame('0', $this->nombre($c, 'effectif-total'));
    }

    public function test_aucun_taux_d_eclosion_sans_oeuf_couve(): void
    {
        $this->cycle('LOT-Z', 'goliath', '2026-10-01', 0, 0, 'Éclosion Effectuée');
        $c = $this->rapport();

        $this->assertSame('—', $this->nombre($c, 'taux-eclosion'));   // division par zero evitee
        $this->assertSame(['—'], $this->textes($c, "//tr[@data-cycle='LOT-Z']/td[@data-taux]"));
    }

    public function test_les_trois_tableaux_ont_une_vue_cartes(): void
    {
        $this->poserLeJeu();
        $c = $this->rapport();

        $c->assertSeeHtml('hidden overflow-x-auto sm:block')->assertSeeHtml('data-vue="cartes"');
        $this->assertCount(4 + 4 + 3, $this->textes($c, "//*[@data-vue='cartes']/article"));
    }

    // ----------------------------------------------------------------- Provende (calcul pur)

    private function categories(string $espece): array
    {
        return FilieresElevage::configuration($espece)['categories'];
    }

    private function classe(int $min, ?int $max, float $taux): TauxRationPoids
    {
        return (new TauxRationPoids)->forceFill(['poids_min_g' => $min, 'poids_max_g' => $max, 'taux_pourcent' => $taux]);
    }

    public function test_provende_par_tete_avec_baremes_et_repli(): void
    {
        $cat = $this->categories('goliaths');
        // Par defaut 30 / 60 / 110 g : 10 x 30 + 10 x 60 + 10 x 110.
        $this->assertSame(2000, RapportElevage::provende('goliaths', $cat, [10, 10, 10], null, [], []));
        // Un bareme remplace la ration de SON stade (par libelle), pas celle des autres.
        $this->assertSame(2000 - 600 + 500, RapportElevage::provende('goliaths', $cat, [10, 10, 10], null, ['Goliathau' => 50], []));
        // Filiere non rationnee au poids : la pesee et les classes sont ignorees.
        $this->assertSame(2000, RapportElevage::provende('goliaths', $cat, [10, 10, 10], 9999999, [], [$this->classe(0, null, 50.0)]));
    }

    public function test_provende_sur_le_poids_vif_bornes_des_classes_et_replis(): void
    {
        $cat = $this->categories('bovins');   // 1 500 / 7 000 / 9 000 g par tete
        $taux = [$this->classe(0, 200000, 3.0), $this->classe(200000, null, 2.5)];
        $parTete = 2 * 1500 + 3 * 7000 + 5 * 9000;   // 69 000

        // 250 kg de moyenne : 2e classe a 2,5 % de la pesee.
        $this->assertSame(62500, RapportElevage::provende('bovins', $cat, [2, 3, 5], 2500000, [], $taux));
        // Moyenne EXACTEMENT 200 kg : minimum inclus, maximum exclu -> 2e classe (2,5 %).
        $this->assertSame(50000, RapportElevage::provende('bovins', $cat, [2, 3, 5], 2000000, [], $taux));
        // Juste en dessous : 1re classe a 3 % (59 999,97 arrondi).
        $this->assertSame(60000, RapportElevage::provende('bovins', $cat, [2, 3, 5], 1999999, [], $taux));
        // Replis par tete : pas de pesee, pesee nulle, effectif nul, aucune classe pour ce poids moyen.
        $this->assertSame($parTete, RapportElevage::provende('bovins', $cat, [2, 3, 5], null, [], $taux));
        $this->assertSame($parTete, RapportElevage::provende('bovins', $cat, [2, 3, 5], 0, [], $taux));
        $this->assertSame(0, RapportElevage::provende('bovins', $cat, [0, 0, 0], 100000, [], $taux));
        $this->assertSame($parTete, RapportElevage::provende('bovins', $cat, [2, 3, 5], 2500000, [], [$this->classe(0, 100000, 3.0)]));
        // Arrondi a l'entier comme le Dart (2,5 -> 3).
        $this->assertSame(3, RapportElevage::provende('bovins', $cat, [1, 0, 0], 100, [], [$this->classe(0, null, 2.5)]));
    }

    public function test_ordre_des_filieres_du_dart_pour_le_rapport(): void
    {
        $this->assertSame(['goliaths', 'pintades', 'lapins', 'escargots', 'bovins', 'poissons-chats', 'poulets', 'pondeuses'], RapportElevage::ORDRE);
        $this->assertEqualsCanonicalizing(FilieresElevage::identifiants(), RapportElevage::ORDRE);
    }
}
