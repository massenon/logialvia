<?php

namespace Tests\Feature\Sync;

use App\Models\Bande;
use App\Models\FicheJournee;
use App\Models\FicheVentesJour;
use App\Models\ParametresEntreprise;
use App\Support\UuidDeterministe;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * Elevage, palier 7a (`46a_`) : fiches journalieres (dernier ecrivain gagne, ligne entiere),
 * compteurs de ventes du jour (une ligne par poste) et bandes (code unique par filiere).
 */
class ElevageFichesTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function pousser(array $poste, string $table, array $lignes)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => ParametresEntreprise::courant()->fresh()->marque_remise_a_zero,
            'tables' => [$table => $lignes],
        ]);
    }

    private function bilan(array $poste, string $table, array $lignes): array
    {
        return $this->pousser($poste, $table, $lignes)->assertOk()->json($table);
    }

    private function tirer(array $poste): array
    {
        return $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->assertOk()->json('tables');
    }

    private function instant(string $quand): string
    {
        return \Carbon\CarbonImmutable::parse($quand)->format('Y-m-d\TH:i:s.u\Z');
    }

    // ------------------------------------------------------------ Identifiants

    public function test_l_uuid_deterministe_est_celui_du_poste(): void
    {
        // Vecteurs calcules par `identifiantFicheJournee` & co du Dart (SHA-1, UUID v5).
        $this->assertSame('d6e0e8af-68bb-5633-bf62-a227fa96bf4c', UuidDeterministe::ficheJournee('goliaths', '2026-11-05'));
        $this->assertSame('ac5be3cd-0a21-5596-9de2-5ce5bff8fb22', UuidDeterministe::ventesJour('pondeuses', '2026-11-05', 'poste-1'));
        $this->assertSame('fd86dea5-5061-50b7-8c71-f20f85c5b371', UuidDeterministe::de('bande:x'));
    }

    // ----------------------------------------------------------- Fiches : push

    public function test_une_fiche_est_enregistree_en_ligne_entiere_avec_son_poste_et_redescend(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $ligne = $this->ligneFicheJournee('pondeuses', '2026-11-05', [
            'mort_cat4' => 2, 'effectif' => 40, 'oeufs_pondus' => 30, 'oeufs_casses' => 1,
            'sorties_plateaux' => 1, 'stock_final_oeufs' => 4, 'traitement_obs' => 'RAS', 'traitement_valide' => true,
            'poids_general_g' => 1800,
        ]);

        $this->assertSame([$ligne['id']], $this->bilan($a, 'fiche_journee', [$ligne])['accepted']);

        $f = FicheJournee::query()->find($ligne['id']);
        $this->assertSame($a['device'], $f->device_id);
        $this->assertSame('2026-11-05', $f->date);
        $this->assertSame('pondeuses', $f->espece);
        $this->assertSame(2, $f->mort_cat4);
        $this->assertSame(40, $f->effectif);
        $this->assertTrue($f->traitement_valide);
        $this->assertSame('RAS', $f->traitement_obs);

        $recue = collect($this->tirer($b)['fiche_journee'])->firstWhere('id', $ligne['id']);
        $this->assertSame('2026-11-05', $recue['date']);
        $this->assertSame(40, $recue['effectif']);
        $this->assertTrue($recue['traitement_valide']);
        $this->assertNull($recue['eff_cat4_day']);
    }

    public function test_un_rejeu_est_accepte_sans_rien_changer_ni_toucher_au_curseur(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $ligne = $this->ligneFicheJournee();
        $this->bilan($a, 'fiche_journee', [$ligne]);
        $recu = FicheJournee::query()->find($ligne['id'])->serveur_modifie_le;

        $bilan = $this->bilan($a, 'fiche_journee', [$ligne]);

        $this->assertSame([$ligne['id']], $bilan['accepted']);
        $this->assertSame(1, FicheJournee::query()->count());
        $this->assertEquals($recu, FicheJournee::query()->find($ligne['id'])->serveur_modifie_le);
    }

    public function test_deux_postes_meme_jour_une_seule_ligne_la_plus_recente_gagne_en_bloc(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('animalier', 'bako');
        $ancienne = $this->ligneFicheJournee('goliaths', '2026-11-05', [
            'updated_at' => $this->instant('2026-11-05 10:00:00'), 'achat' => 10, 'effectif' => 10,
            'poids_general_g' => 1500, 'traitement_obs' => 'saisie de A',
        ]);
        $recente = $this->ligneFicheJournee('goliaths', '2026-11-05', [
            'updated_at' => $this->instant('2026-11-05 11:00:00'), 'achat' => 25, 'effectif' => 25,
            'poids_general_g' => null, 'traitement_obs' => null,
        ]);

        $this->bilan($a, 'fiche_journee', [$ancienne]);
        $this->bilan($b, 'fiche_journee', [$recente]);

        $this->assertSame(1, FicheJournee::query()->count());
        $f = FicheJournee::query()->first();
        $this->assertSame(25, $f->effectif);
        $this->assertNull($f->poids_general_g, 'ligne ENTIERE : le poids de A ne survit pas à la saisie de B');
        $this->assertNull($f->traitement_obs);
        $this->assertSame($b['device'], $f->device_id);
    }

    public function test_une_saisie_plus_ancienne_arrivee_en_retard_ou_egale_ne_change_rien(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('animalier', 'bako');
        $recente = $this->ligneFicheJournee('goliaths', '2026-11-05', ['updated_at' => $this->instant('2026-11-05 11:00:00'), 'effectif' => 25]);
        $this->bilan($a, 'fiche_journee', [$recente]);

        $enRetard = $this->ligneFicheJournee('goliaths', '2026-11-05', ['updated_at' => $this->instant('2026-11-05 10:00:00'), 'effectif' => 10]);
        $egale = $this->ligneFicheJournee('goliaths', '2026-11-05', ['updated_at' => $this->instant('2026-11-05 11:00:00'), 'effectif' => 99]);
        $this->assertSame([$enRetard['id']], $this->bilan($b, 'fiche_journee', [$enRetard])['accepted']);
        $this->bilan($b, 'fiche_journee', [$egale]);

        $f = FicheJournee::query()->first();
        $this->assertSame(25, $f->effectif);
        $this->assertSame($a['device'], $f->device_id);
    }

    public function test_une_colonne_facultative_absente_est_ecrite_a_null_jamais_conservee(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $this->bilan($a, 'fiche_journee', [$this->ligneFicheJournee('goliaths', '2026-11-05', [
            'updated_at' => $this->instant('2026-11-05 10:00:00'), 'poids_general_g' => 1500,
        ])]);
        $suivante = $this->ligneFicheJournee('goliaths', '2026-11-05', ['updated_at' => $this->instant('2026-11-05 11:00:00')]);
        unset($suivante['poids_general_g']);

        $this->bilan($a, 'fiche_journee', [$suivante]);

        $this->assertNull(FicheJournee::query()->first()->poids_general_g);
    }

    public static function fichesInvalides(): array
    {
        return [
            'UUID invalide' => [['id' => 'pas-un-uuid'], "L'identifiant de la fiche doit être un UUID."],
            'filière inconnue' => [['espece' => 'dragons'], 'La filière « dragons » est inconnue.'],
            'filière absente' => [['espece' => null], 'La filière de la fiche est obligatoire.'],
            'date invalide' => [['date' => '2026-02-31'], 'La date de la fiche est invalide.'],
            'date avec heure' => [['date' => '2026-11-05T10:00:00Z'], 'La date de la fiche est invalide.'],
            'date absente' => [['date' => null], 'La date de la fiche est obligatoire.'],
            'effectif négatif' => [['effectif' => -3], 'La valeur de « effectif » doit être un entier positif ou nul.'],
            'achat en texte' => [['achat' => '5'], 'La valeur de « achat » doit être un entier positif ou nul.'],
            'mortalité décimale' => [['mort_cat2' => 1.5], 'La valeur de « mort_cat2 » doit être un entier positif ou nul.'],
            'obligatoire absent' => [['ne' => null], 'La valeur de « ne » est obligatoire.'],
            'facultatif négatif' => [['mort_cat4' => -1], 'La valeur de « mort_cat4 » doit être un entier positif ou nul.'],
            'booléen en nombre' => [['is_recorded' => 1], "L'indicateur « is_recorded » doit être vrai ou faux."],
            'traitement validé en texte' => [['traitement_valide' => 'oui'], "L'indicateur « traitement_valide » doit être vrai ou faux."],
            'saisie sans instant' => [['updated_at' => 'hier'], 'La date de saisie de la ligne est invalide.'],
        ];
    }

    /** @dataProvider fichesInvalides */
    public function test_une_fiche_invalide_est_refusee_avec_un_motif_francais_et_rien_n_est_ecrit(array $surcharge, string $motif): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $ligne = $this->ligneFicheJournee('goliaths', '2026-11-05', $surcharge);
        // Une identité qui reste calculable : on teste la règle, pas l'identité.
        if (! array_key_exists('id', $surcharge) && is_string($ligne['espece']) && is_string($ligne['date'])
            && \App\Support\FilieresElevage::existe($ligne['espece'])
            && \DateTime::createFromFormat('!Y-m-d', $ligne['date']) !== false) {
            $ligne['id'] = UuidDeterministe::ficheJournee($ligne['espece'], $ligne['date']);
        }

        $bilan = $this->bilan($a, 'fiche_journee', [$ligne]);

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, FicheJournee::query()->count());
    }

    public function test_un_uuid_qui_n_est_pas_celui_de_la_cle_est_refuse(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $ligne = $this->ligneFicheJournee('goliaths', '2026-11-05', ['id' => (string) Str::uuid()]);

        $bilan = $this->bilan($a, 'fiche_journee', [$ligne]);

        $this->assertSame("L'identifiant de la fiche ne correspond pas à sa filière et à sa date.", $bilan['rejected'][0]['motif']);
        $this->assertSame(0, FicheJournee::query()->count());
    }

    public function test_les_droits_de_la_matrice_s_appliquent_aux_fiches(): void
    {
        $ligne = $this->ligneFicheJournee();
        $animalier = $this->poste('animalier', 'eleveur');
        $caissier = $this->poste('caissier', 'amina');
        $comptable = $this->poste('comptable', 'compta');

        foreach ([$caissier, $comptable] as $sansDroit) {
            $bilan = $this->bilan($sansDroit, 'fiche_journee', [$ligne]);
            $this->assertSame('Droit insuffisant pour écrire dans « fiche_journee ».', $bilan['rejected'][0]['motif']);
        }
        $this->assertSame(0, FicheJournee::query()->count());
        $this->assertSame([$ligne['id']], $this->bilan($animalier, 'fiche_journee', [$ligne])['accepted']);

        $this->assertArrayNotHasKey('fiche_journee', $this->tirer($caissier));
        $this->assertArrayNotHasKey('fiche_journee', $this->tirer($comptable));
        $this->assertArrayNotHasKey('bandes', $this->tirer($caissier));
        $this->assertArrayHasKey('fiche_journee', $this->tirer($animalier));
        $this->assertArrayHasKey('bandes', $this->tirer($animalier));
    }

    // ------------------------------------------------- Compteur des ventes du jour

    public function test_deux_postes_ont_chacun_leur_ligne_et_la_somme_est_celle_des_deux(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('animalier', 'eleveur');
        $this->bilan($a, 'fiche_ventes_jour', [$this->ligneVentesJour($a['device'], 'goliaths', '2026-11-05', ['qte' => 2])]);
        $this->bilan($b, 'fiche_ventes_jour', [$this->ligneVentesJour($b['device'], 'goliaths', '2026-11-05', ['qte' => 3])]);

        $this->assertSame(2, FicheVentesJour::query()->count());
        $this->assertSame(5, (int) FicheVentesJour::query()->where('espece', 'goliaths')->where('date', '2026-11-05')->sum('qte'));
        $recu = collect($this->tirer($b)['fiche_ventes_jour']);
        $this->assertEqualsCanonicalizing([$a['device'], $b['device']], $recu->pluck('device_id')->all());
    }

    public function test_un_poste_ne_peut_pas_ecrire_le_compteur_d_un_autre(): void
    {
        $a = $this->poste('caissier', 'amina');
        $b = $this->poste('caissier', 'binta');
        $celuiDeB = $this->ligneVentesJour($b['device']);

        $bilan = $this->bilan($a, 'fiche_ventes_jour', [$celuiDeB]);

        $this->assertSame("L'identifiant du compteur ne correspond pas à sa filière, à sa date et à son poste.", $bilan['rejected'][0]['motif']);
        $this->assertSame(0, FicheVentesJour::query()->count());
    }

    public function test_le_compteur_d_un_poste_est_a_dernier_ecrivain_gagne_et_un_rejeu_ne_double_pas(): void
    {
        $a = $this->poste('caissier', 'amina');
        $deux = $this->ligneVentesJour($a['device'], 'goliaths', '2026-11-05', ['qte' => 2, 'updated_at' => $this->instant('2026-11-05 10:00:00')]);
        $quatre = $this->ligneVentesJour($a['device'], 'goliaths', '2026-11-05', ['qte' => 4, 'updated_at' => $this->instant('2026-11-05 11:00:00')]);

        $this->bilan($a, 'fiche_ventes_jour', [$deux]);
        $this->bilan($a, 'fiche_ventes_jour', [$quatre]);
        $this->bilan($a, 'fiche_ventes_jour', [$quatre]); // rejeu
        $this->bilan($a, 'fiche_ventes_jour', [$deux]);   // ancien arrivé en retard

        $this->assertSame(1, FicheVentesJour::query()->count());
        $this->assertSame(4, FicheVentesJour::query()->first()->qte, 'remplacé, jamais additionné');
    }

    public static function compteursInvalides(): array
    {
        return [
            'UUID invalide' => [['id' => 'x'], "L'identifiant du compteur doit être un UUID."],
            'filière inconnue' => [['espece' => 'dragons'], 'La filière « dragons » est inconnue.'],
            'date invalide' => [['date' => '2026-13-01'], 'La date du compteur est invalide.'],
            'quantité négative' => [['qte' => -1], 'La quantité vendue doit être un entier positif ou nul.'],
            'quantité décimale' => [['qte' => 1.5], 'La quantité vendue doit être un entier positif ou nul.'],
            'quantité absente' => [['qte' => null], 'La quantité vendue est obligatoire.'],
        ];
    }

    /** @dataProvider compteursInvalides */
    public function test_un_compteur_invalide_est_refuse_avec_un_motif_francais(array $surcharge, string $motif): void
    {
        $a = $this->poste('caissier', 'amina');
        $ligne = $this->ligneVentesJour($a['device'], 'goliaths', '2026-11-05', $surcharge);
        if (! array_key_exists('id', $surcharge) && is_string($ligne['espece']) && is_string($ligne['date'])
            && \App\Support\FilieresElevage::existe($ligne['espece'])
            && \DateTime::createFromFormat('!Y-m-d', $ligne['date']) !== false) {
            $ligne['id'] = UuidDeterministe::ventesJour($ligne['espece'], $ligne['date'], $a['device']);
        }

        $bilan = $this->bilan($a, 'fiche_ventes_jour', [$ligne]);

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, FicheVentesJour::query()->count());
    }

    public function test_la_caisse_l_elevage_et_l_administrateur_ecrivent_le_compteur_pas_le_comptable(): void
    {
        $caissier = $this->poste('caissier', 'amina');
        $animalier = $this->poste('animalier', 'eleveur');
        $admin = $this->poste('admin', 'gerante');
        $comptable = $this->poste('comptable', 'compta');

        foreach ([$caissier, $animalier, $admin] as $poste) {
            $ligne = $this->ligneVentesJour($poste['device']);
            $this->assertSame([$ligne['id']], $this->bilan($poste, 'fiche_ventes_jour', [$ligne])['accepted']);
        }
        $refus = $this->bilan($comptable, 'fiche_ventes_jour', [$this->ligneVentesJour($comptable['device'])]);
        $this->assertSame('Droit insuffisant pour écrire dans « fiche_ventes_jour ».', $refus['rejected'][0]['motif']);

        // Lecture : élevage ET vente ; le comptable (view-ventes) lit aussi.
        $this->assertArrayHasKey('fiche_ventes_jour', $this->tirer($caissier));
        $this->assertArrayHasKey('fiche_ventes_jour', $this->tirer($animalier));
        $this->assertArrayHasKey('fiche_ventes_jour', $this->tirer($comptable));
    }

    // ------------------------------------------------------------------- Bandes

    public function test_une_bande_est_enregistree_redescend_et_sa_cloture_la_remplace(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $ligne = $this->ligneBande('B1', ['updated_at' => $this->instant('2026-10-01 08:00:00'), 'observations' => 'Lot 1']);

        $this->assertSame([$ligne['id']], $this->bilan($a, 'bandes', [$ligne])['accepted']);
        $recue = collect($this->tirer($b)['bandes'])->firstWhere('id', $ligne['id']);
        $this->assertSame('B1', $recue['code']);
        $this->assertSame('2026-10-01', $recue['date_mise_en_bande']);
        $this->assertSame(100, $recue['effectif_initial']);

        $cloture = $ligne['date_cloture'] = '2026-11-01';
        $ligne['updated_at'] = $this->instant('2026-11-01 08:00:00');
        $this->bilan($b, 'bandes', [$ligne]);

        $this->assertSame($cloture, Bande::query()->find($ligne['id'])->date_cloture);
        $this->assertSame(1, Bande::query()->count());
    }

    public function test_le_meme_code_sous_un_autre_uuid_est_refuse_sans_rien_fusionner(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('animalier', 'bako');
        $premiere = $this->ligneBande('B2', ['date_mise_en_bande' => '2026-10-01']);
        $seconde = $this->ligneBande('B2', ['date_mise_en_bande' => '2026-10-20']);
        $this->bilan($a, 'bandes', [$premiere]);

        $bilan = $this->bilan($b, 'bandes', [$seconde]);

        $this->assertSame('Ce code de bande est déjà utilisé pour cette filière.', $bilan['rejected'][0]['motif']);
        $this->assertSame(1, Bande::query()->count());
        $this->assertSame('2026-10-01', Bande::query()->first()->date_mise_en_bande);
    }

    public function test_un_code_est_unique_par_filiere_pas_globalement_et_espaces_ignores(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $this->bilan($a, 'bandes', [$this->ligneBande('B1')]);

        $autreFiliere = $this->ligneBande('B1', ['espece' => 'pintades']);
        $this->assertSame([$autreFiliere['id']], $this->bilan($a, 'bandes', [$autreFiliere])['accepted']);

        $avecEspaces = $this->ligneBande('  B1  ');
        $this->assertSame(
            'Ce code de bande est déjà utilisé pour cette filière.',
            $this->bilan($a, 'bandes', [$avecEspaces])['rejected'][0]['motif'],
        );
        $this->assertSame(2, Bande::query()->count());
    }

    public function test_le_code_est_rogne_par_la_table_meme_hors_requete_http(): void
    {
        // Le web et les jeux d'essai appellent `absorber` sans passer par le middleware qui rogne les textes.
        $a = $this->poste('animalier', 'eleveur');
        $this->assertNull((new \App\Sync\Tables\BandesTable)->absorber($a['device'], $this->ligneBande('B1')));

        $motif = (new \App\Sync\Tables\BandesTable)->absorber($a['device'], $this->ligneBande('  B1  '));

        $this->assertSame('Ce code de bande est déjà utilisé pour cette filière.', $motif);
        $this->assertSame(1, Bande::query()->count());
        $this->assertNull((new \App\Sync\Tables\BandesTable)->absorber($a['device'], $this->ligneBande('  B9  ')));
        $this->assertSame(1, Bande::query()->where('code', 'B9')->count(), 'enregistre rogne');
    }

    public function test_recoder_une_bande_vers_un_code_pris_est_refuse(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b1 = $this->ligneBande('B1');
        $b2 = $this->ligneBande('B2');
        $this->bilan($a, 'bandes', [$b1, $b2]);

        $recodee = $b2 + [];
        $recodee['code'] = 'B1';
        $recodee['updated_at'] = $this->instant(now()->addMinute()->format('Y-m-d H:i:s'));

        $this->assertSame(
            'Ce code de bande est déjà utilisé pour cette filière.',
            $this->bilan($a, 'bandes', [$recodee])['rejected'][0]['motif'],
        );
        $this->assertSame('B2', Bande::query()->find($b2['id'])->code);
    }

    public static function bandesInvalides(): array
    {
        return [
            'UUID invalide' => [['id' => 'x'], "L'identifiant de la bande doit être un UUID."],
            'filière inconnue' => [['espece' => 'dragons'], 'La filière « dragons » est inconnue.'],
            'code vide' => [['code' => '  '], 'Le code de la bande est obligatoire.'],
            'mise en place invalide' => [['date_mise_en_bande' => '2026-13-01'], 'La date de mise en place de la bande est invalide.'],
            'clôture avant la mise en place' => [['date_cloture' => '2026-09-30'], 'La clôture ne peut pas précéder la mise en place de la bande.'],
            'clôture invalide' => [['date_cloture' => 'bientôt'], 'La date de clôture de la bande est invalide.'],
            'effectif négatif' => [['effectif_initial' => -5], "L'effectif mis en place ne peut pas être négatif."],
            'effectif en texte' => [['effectif_initial' => 'beaucoup'], "L'effectif mis en place doit être un entier positif ou nul."],
            'saisie sans instant' => [['updated_at' => 'hier'], 'La date de saisie de la ligne est invalide.'],
        ];
    }

    /** @dataProvider bandesInvalides */
    public function test_une_bande_invalide_est_refusee_avec_un_motif_francais(array $surcharge, string $motif): void
    {
        $a = $this->poste('animalier', 'eleveur');

        $bilan = $this->bilan($a, 'bandes', [$this->ligneBande('B1', $surcharge)]);

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, Bande::query()->count());
    }

    public function test_la_cloture_le_jour_de_la_mise_en_place_est_acceptee(): void
    {
        $a = $this->poste('animalier', 'eleveur');

        $bilan = $this->bilan($a, 'bandes', [$this->ligneBande('B1', ['date_cloture' => '2026-10-01'])]);

        $this->assertSame([], $bilan['rejected']);
    }

    public function test_l_effectif_reel_n_existe_ni_en_colonne_ni_dans_la_ligne_servie(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $this->bilan($a, 'bandes', [$this->ligneBande('B1')]);

        $colonnes = Schema::getColumnListing('bandes');
        $this->assertContains('effectif_initial', $colonnes);
        $this->assertNotContains('effectif', $colonnes);
        $this->assertNotContains('effectif_reel', $colonnes);
        $recue = $this->tirer($a)['bandes'][0];
        $this->assertArrayNotHasKey('effectif', $recue);
        $this->assertArrayNotHasKey('effectif_reel', $recue);
    }

    public function test_une_bande_poussee_avec_un_effectif_reel_ne_le_stocke_pas(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $ligne = $this->ligneBande('B1', ['effectif' => 9999, 'effectif_reel' => 9999]);

        $this->bilan($a, 'bandes', [$ligne]);

        $this->assertArrayNotHasKey('effectif', Bande::query()->first()->getAttributes());
    }

    // --------------------------------------------------------- Remise à zéro

    public function test_la_remise_a_zero_efface_fiches_compteurs_et_bandes(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $admin = $this->poste('admin', 'gerante');
        $this->bilan($admin, 'fiche_journee', [$this->ligneFicheJournee()]);
        $this->bilan($admin, 'fiche_ventes_jour', [$this->ligneVentesJour($admin['device'])]);
        $this->bilan($admin, 'bandes', [$this->ligneBande('B1')]);

        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/remise-a-zero', ['confirmation' => 'REMETTRE A ZERO'])->assertOk();

        $this->assertSame(0, FicheJournee::query()->count());
        $this->assertSame(0, FicheVentesJour::query()->count());
        $this->assertSame(0, Bande::query()->count());
    }

    public function test_apres_la_remise_a_zero_l_ancienne_marque_est_refusee(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $admin = $this->poste('admin', 'gerante');
        $ancienne = ParametresEntreprise::courant()->fresh()->marque_remise_a_zero;
        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/remise-a-zero', ['confirmation' => 'REMETTRE A ZERO'])->assertOk();

        $this->avecJeton($admin['jeton'])->postJson('/api/sync/push', [
            'device_id' => $admin['device'], 'reset_mark' => $ancienne,
            'tables' => ['fiche_journee' => [$this->ligneFicheJournee()]],
        ])->assertStatus(409);
        $this->assertSame(0, FicheJournee::query()->count());
    }

    // ---------------------------------------------------------- Deux postes

    public function test_deux_postes_convergent_vers_la_meme_fiche_quel_que_soit_l_ordre_d_arrivee(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('animalier', 'bako');
        $deA = $this->ligneFicheJournee('goliaths', '2026-11-05', ['updated_at' => $this->instant('2026-11-05 10:00:00'), 'effectif' => 10]);
        $deB = $this->ligneFicheJournee('goliaths', '2026-11-05', ['updated_at' => $this->instant('2026-11-05 11:00:00'), 'effectif' => 25]);

        foreach ([[$a, $deA, $b, $deB], [$b, $deB, $a, $deA]] as [$p1, $l1, $p2, $l2]) {
            FicheJournee::query()->delete();
            $this->bilan($p1, 'fiche_journee', [$l1]);
            $this->bilan($p2, 'fiche_journee', [$l2]);
            $this->assertSame(25, FicheJournee::query()->sole()->effectif);
        }
    }
}
