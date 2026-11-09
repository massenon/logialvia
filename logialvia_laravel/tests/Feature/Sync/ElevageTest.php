<?php

namespace Tests\Feature\Sync;

use App\Models\BaremeRation;
use App\Models\EcheanceProphylaxie;
use App\Models\EntreeInfirmerie;
use App\Models\SoinCalendrier;
use App\Models\TauxRationPoids;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Spatie\Permission\Models\Role;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * P7c — Elevage : soins et infirmerie (FAITS), baremes, taux par classe de poids et
 * calendrier de prophylaxie (REFERENTIELS). Voir `docs/logialvia/46c_SYNC_ELEVAGE_SOINS.md`.
 */
class ElevageTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    private const MOTIF_PLUS_RECENTE = 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.';

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    // ------------------------------------------------------------------ outils

    private function demander(array $poste, string $type, array $donnees, ?string $saisi = null)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $poste['device'],
            'demandes' => [[
                'id' => (string) Str::uuid(),
                'type' => $type,
                'saisi_le' => $saisi ?? now()->format('Y-m-d\TH:i:s.u\Z'),
                'donnees' => $donnees,
            ]],
        ]);
    }

    private function pousser(array $poste, string $table, array $lignes)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'], 'reset_mark' => 'initiale',
            'tables' => [$table => $lignes],
        ]);
    }

    private function bilan(array $poste, string $table, array $lignes): array
    {
        return $this->pousser($poste, $table, $lignes)->assertOk()->json($table);
    }

    private function tirer(array $poste, string $table): array
    {
        return $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->json("tables.$table");
    }

    private function ligneBareme(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(), 'espece' => 'goliaths', 'stade' => 'Mature',
            'ration_grammes_par_jour' => 110, 'confirme' => false,
        ], $surcharge);
    }

    private function ligneTaux(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(), 'espece' => 'bovins', 'poids_min_g' => 0, 'poids_max_g' => 150000,
            'taux_pourcent' => 3.5, 'confirme' => false,
        ], $surcharge);
    }

    private function ligneEcheance(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(), 'espece' => 'goliaths', 'jour_cycle' => 15, 'traitement' => 'Gumboro',
            'produit' => 'Bursine', 'remanence_jours' => 3, 'dose' => '1 dose par sujet',
        ], $surcharge);
    }

    private function ligneSoin(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(), 'espece' => 'goliaths', 'date_prevue' => '2026-11-05',
            'type_soin' => 'Vaccination', 'statut' => 'Planifié', 'observations' => null,
            'produit' => 'ND-Lasota', 'dose' => '1 goutte', 'remanence_jours' => 0, 'veterinaire' => null,
            'symptomes' => null, 'cout_fcfa' => 1500, 'echeance_prophylaxie_id' => null,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    private function ligneEntree(array $surcharge = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(), 'date_entree' => '2026-11-01', 'sujet' => 'Goliath #G-014',
            'motif' => 'Boiterie', 'niveau_isolement' => 'Infirmerie', 'statut' => 'En cours',
            'date_sortie' => null, 'espece' => 'goliaths', 'categorie_mortalite' => null,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    // ============================================================ REFERENTIELS

    public function test_un_bareme_propose_est_cree_puis_redescend(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('animalier', 'eleveur');
        $bareme = $this->ligneBareme();

        $this->demander($a, 'bareme_ration', $bareme)->assertJsonPath('rejected', []);

        $row = BaremeRation::query()->find($bareme['id']);
        $this->assertSame(110, $row->ration_grammes_par_jour);
        $this->assertNull($row->archive_le);
        $recu = collect($this->tirer($b, 'baremes_ration'))->firstWhere('id', $bareme['id']);
        $this->assertSame('Mature', $recu['stade']);
        $this->assertFalse($recu['confirme']);
        $this->assertArrayHasKey('saisi_le', $recu);
        $this->assertArrayHasKey('archive_le', $recu);
    }

    public function test_un_taux_et_une_echeance_proposes_redescendent_avec_leurs_champs(): void
    {
        $a = $this->poste('admin', 'gerante');
        $taux = $this->ligneTaux();
        $echeance = $this->ligneEcheance();

        $this->demander($a, 'taux_ration_poids', $taux)->assertJsonPath('rejected', []);
        $this->demander($a, 'echeance_prophylaxie', $echeance)->assertJsonPath('rejected', []);

        $t = collect($this->tirer($a, 'taux_ration_poids'))->firstWhere('id', $taux['id']);
        $this->assertSame(3.5, $t['taux_pourcent']);
        $this->assertSame(150000, $t['poids_max_g']);
        $e = collect($this->tirer($a, 'calendrier_prophylaxie'))->firstWhere('id', $echeance['id']);
        $this->assertSame('Gumboro', $e['traitement']);
        $this->assertSame('1 dose par sujet', $e['dose']);
        $this->assertSame(3, $e['remanence_jours']);
    }

    public static function parametresInvalides(): array
    {
        return [
            'barème sans stade' => ['bareme_ration', ['stade' => ''], 'Le stade du barème est obligatoire.'],
            'barème sans espèce' => ['bareme_ration', ['espece' => ''], "L'espèce est obligatoire."],
            'ration nulle' => ['bareme_ration', ['ration_grammes_par_jour' => 0], 'La ration doit être comprise entre 1 et 20 000 g par jour.'],
            'ration invraisemblable' => ['bareme_ration', ['ration_grammes_par_jour' => 20001], 'La ration doit être comprise entre 1 et 20 000 g par jour.'],
            'barème sans statut' => ['bareme_ration', ['confirme' => null], 'Le statut du barème est invalide.'],
            'identifiant non UUID' => ['bareme_ration', ['id' => '42'], "L'identifiant de la ligne doit être un UUID."],
            'poids min négatif' => ['taux_ration_poids', ['poids_min_g' => -1], 'Le poids minimal est invalide.'],
            'poids max <= min' => ['taux_ration_poids', ['poids_max_g' => 0], 'Le poids maximal doit dépasser le poids minimal.'],
            'taux nul' => ['taux_ration_poids', ['taux_pourcent' => 0], 'Le taux doit être compris entre 0 et 25 % du poids vif par jour.'],
            'taux > 25' => ['taux_ration_poids', ['taux_pourcent' => 26], 'Le taux doit être compris entre 0 et 25 % du poids vif par jour.'],
            'jour 0' => ['echeance_prophylaxie', ['jour_cycle' => 0], 'Le jour du cycle doit être compris entre 1 et 365.'],
            'jour 366' => ['echeance_prophylaxie', ['jour_cycle' => 366], 'Le jour du cycle doit être compris entre 1 et 365.'],
            'sans traitement' => ['echeance_prophylaxie', ['traitement' => ''], 'Le traitement et le produit sont obligatoires.'],
            'rémanence négative' => ['echeance_prophylaxie', ['remanence_jours' => -1], 'La rémanence ne peut pas être négative.'],
        ];
    }

    /** @dataProvider parametresInvalides */
    public function test_une_demande_invalide_est_refusee_avec_un_motif_francais(string $type, array $surcharge, string $motif): void
    {
        $a = $this->poste('admin', 'gerante');
        $ligne = match ($type) {
            'bareme_ration' => $this->ligneBareme($surcharge),
            'taux_ration_poids' => $this->ligneTaux($surcharge),
            default => $this->ligneEcheance($surcharge),
        };

        $this->demander($a, $type, $ligne)->assertJsonPath('rejected.0.motif', $motif);

        $this->assertSame(0, BaremeRation::query()->count() + TauxRationPoids::query()->count() + EcheanceProphylaxie::query()->count());
    }

    public function test_les_droits_des_demandes_d_elevage(): void
    {
        $caissier = $this->poste('caissier', 'amina');
        $comptable = $this->poste('comptable');
        $animalier = $this->poste('animalier', 'eleveur');

        $this->demander($caissier, 'bareme_ration', $this->ligneBareme())
            ->assertJsonPath('rejected.0.motif', 'Droit insuffisant pour modifier les paramètres d\'élevage.');
        $this->demander($comptable, 'echeance_prophylaxie', $this->ligneEcheance())
            ->assertJsonPath('rejected.0.motif', 'Droit insuffisant pour modifier les paramètres d\'élevage.');
        $this->assertSame(0, BaremeRation::query()->count() + EcheanceProphylaxie::query()->count());

        $this->demander($animalier, 'bareme_ration', $this->ligneBareme())->assertJsonPath('rejected', []);
    }

    public function test_la_suppression_exige_le_droit_d_archiver(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $bareme = $this->ligneBareme();
        $this->demander($admin, 'bareme_ration', $bareme, '2026-11-01T10:00:00.000000Z')->assertOk();
        // Un compte qui peut gerer mais pas archiver (role cree pour l'essai).
        Role::findOrCreate('gestionnaire-sans-archive', 'web')
            ->givePermissionTo(['view-elevage', 'manage-elevage']);
        $gestionnaire = $this->poste('gestionnaire-sans-archive', 'gestio');

        $this->demander($gestionnaire, 'bareme_ration', $bareme + ['archive' => true], '2026-11-02T10:00:00.000000Z')
            ->assertJsonPath('rejected.0.motif', 'Droit insuffisant pour supprimer un paramètre d\'élevage.');
        $this->assertNull(BaremeRation::query()->find($bareme['id'])->archive_le);

        $this->demander($admin, 'bareme_ration', $bareme + ['archive' => true], '2026-11-02T10:00:00.000000Z')
            ->assertJsonPath('rejected', []);
        $this->assertNotNull(BaremeRation::query()->find($bareme['id'])->archive_le);
    }

    public function test_une_ligne_supprimee_est_une_pierre_tombale_redistribuee_puis_levee_par_la_restauration(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('animalier', 'eleveur');
        $e = $this->ligneEcheance();
        $this->demander($a, 'echeance_prophylaxie', $e, '2026-11-01T10:00:00.000000Z')->assertOk();

        $this->demander($a, 'echeance_prophylaxie', $e + ['archive' => true], '2026-11-02T10:00:00.000000Z')
            ->assertJsonPath('rejected', []);

        $this->assertSame(1, EcheanceProphylaxie::query()->count(), 'jamais effacée');
        $recu = collect($this->tirer($b, 'calendrier_prophylaxie'))->firstWhere('id', $e['id']);
        $this->assertNotNull($recu['archive_le']);

        $this->demander($a, 'echeance_prophylaxie', $e, '2026-11-03T10:00:00.000000Z')->assertJsonPath('rejected', []);
        $this->assertNull(EcheanceProphylaxie::query()->find($e['id'])->archive_le);
    }

    public function test_une_suppression_d_une_ligne_inconnue_du_serveur_cree_la_pierre_tombale(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('animalier', 'eleveur');
        $t = $this->ligneTaux();

        $this->demander($a, 'taux_ration_poids', $t + ['archive' => true])->assertJsonPath('rejected', []);

        $this->assertNotNull(TauxRationPoids::query()->find($t['id'])->archive_le);
        $recu = collect($this->tirer($b, 'taux_ration_poids'))->firstWhere('id', $t['id']);
        $this->assertNotNull($recu['archive_le'], 'les autres postes apprennent la suppression');
    }

    public function test_deux_postes_semes_des_memes_lignes_ne_se_contredisent_pas(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $bareme = $this->ligneBareme();
        $this->demander($a, 'bareme_ration', $bareme, '2026-11-01T10:00:00.000000Z')->assertJsonPath('rejected', []);

        $this->demander($b, 'bareme_ration', $bareme, '2026-11-01T09:00:00.000000Z')->assertJsonPath('rejected', []);

        $this->assertSame(1, BaremeRation::query()->count());
    }

    public function test_une_modification_plus_ancienne_est_refusee_une_plus_recente_gagne(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $bareme = $this->ligneBareme();
        $this->demander($a, 'bareme_ration', $bareme, '2026-11-01T10:00:00.000000Z')->assertOk();

        $this->demander($b, 'bareme_ration', ['ration_grammes_par_jour' => 90] + $bareme, '2026-11-01T09:00:00.000000Z')
            ->assertJsonPath('rejected.0.motif', self::MOTIF_PLUS_RECENTE);
        $this->assertSame(110, BaremeRation::query()->find($bareme['id'])->ration_grammes_par_jour);

        $this->demander($b, 'bareme_ration', ['ration_grammes_par_jour' => 90, 'confirme' => true] + $bareme, '2026-11-01T11:00:00.000000Z')
            ->assertJsonPath('rejected', []);
        $row = BaremeRation::query()->find($bareme['id']);
        $this->assertSame(90, $row->ration_grammes_par_jour);
        $this->assertTrue($row->confirme);
    }

    public function test_un_instant_egal_est_refuse_quand_le_contenu_differe(): void
    {
        $a = $this->poste('admin', 'gerante');
        $bareme = $this->ligneBareme();
        $this->demander($a, 'bareme_ration', $bareme, '2026-11-01T10:00:00.000000Z')->assertOk();

        $this->demander($a, 'bareme_ration', ['ration_grammes_par_jour' => 90] + $bareme, '2026-11-01T10:00:00.000000Z')
            ->assertJsonPath('rejected.0.motif', self::MOTIF_PLUS_RECENTE);
    }

    public function test_la_cle_naturelle_ne_peut_etre_portee_que_par_un_identifiant(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->demander($a, 'bareme_ration', $this->ligneBareme())->assertOk();
        $this->demander($a, 'taux_ration_poids', $this->ligneTaux())->assertOk();

        $this->demander($a, 'bareme_ration', $this->ligneBareme())
            ->assertJsonPath('rejected.0.motif', 'Un barème existe déjà pour ce stade.');
        $this->demander($a, 'taux_ration_poids', $this->ligneTaux(['poids_max_g' => null]))
            ->assertJsonPath('rejected.0.motif', 'Une classe de poids existe déjà avec ce poids minimal.');
        $this->assertSame(1, BaremeRation::query()->count());
        $this->assertSame(1, TauxRationPoids::query()->count());
    }

    public function test_deux_echeances_au_meme_contenu_mais_d_identifiants_distincts_coexistent(): void
    {
        $a = $this->poste('admin', 'gerante');

        $this->demander($a, 'echeance_prophylaxie', $this->ligneEcheance())->assertJsonPath('rejected', []);
        $this->demander($a, 'echeance_prophylaxie', $this->ligneEcheance())->assertJsonPath('rejected', []);

        $this->assertSame(2, EcheanceProphylaxie::query()->count());
    }

    public function test_une_demande_rejouee_rend_la_meme_issue(): void
    {
        $a = $this->poste('admin', 'gerante');
        $demande = [
            'id' => (string) Str::uuid(), 'type' => 'bareme_ration',
            'saisi_le' => '2026-11-01T10:00:00.000000Z', 'donnees' => $this->ligneBareme(),
        ];
        for ($i = 0; $i < 2; $i++) {
            $this->avecJeton($a['jeton'])->postJson('/api/sync/demandes', [
                'device_id' => $a['device'], 'demandes' => [$demande],
            ])->assertJsonPath('rejected', [])->assertJsonPath('accepted.0', $demande['id']);
        }
        $this->assertSame(1, BaremeRation::query()->count());
    }

    public function test_un_envoi_direct_d_un_referentiel_est_ignore(): void
    {
        $a = $this->poste('admin', 'gerante');

        $r = $this->bilan($a, 'baremes_ration', [$this->ligneBareme()]);

        $this->assertCount(1, $r['ignored']);
        $this->assertSame(0, BaremeRation::query()->count());
    }

    public function test_les_referentiels_d_elevage_ne_sont_servis_qu_a_qui_peut_lire_l_elevage(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->demander($a, 'bareme_ration', $this->ligneBareme())->assertOk();
        $caissier = $this->poste('caissier', 'amina');
        $comptable = $this->poste('comptable');

        foreach (['baremes_ration', 'taux_ration_poids', 'calendrier_prophylaxie', 'soins_calendrier', 'infirmerie'] as $table) {
            $this->assertArrayHasKey($table, $this->avecJeton($a['jeton'])->getJson('/api/sync/pull')->json('tables'));
            $this->assertArrayNotHasKey($table, $this->avecJeton($caissier['jeton'])->getJson('/api/sync/pull')->json('tables'));
            $this->assertArrayNotHasKey($table, $this->avecJeton($comptable['jeton'])->getJson('/api/sync/pull')->json('tables'));
        }
    }

    // ================================================================== SOINS

    public function test_un_soin_est_enregistre_redistribue_et_ne_touche_rien_d_autre(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $s = $this->ligneSoin();

        $this->assertSame([$s['id']], $this->bilan($a, 'soins_calendrier', [$s])['accepted']);

        $row = SoinCalendrier::query()->find($s['id']);
        $this->assertSame($a['device'], $row->device_id);
        $this->assertSame('2026-11-05', $row->date_prevue->format('Y-m-d'));
        $this->assertSame(1500, $row->cout_fcfa);
        $recu = collect($this->tirer($b, 'soins_calendrier'))->firstWhere('id', $s['id']);
        $this->assertSame('Vaccination', $recu['type_soin']);
        $this->assertSame('2026-11-05', $recu['date_prevue']);
        $this->assertArrayNotHasKey('bande_id', $recu);
    }

    public static function soinsInvalides(): array
    {
        return [
            'espèce vide' => [['espece' => ''], "L'espèce du soin est obligatoire."],
            'date invalide' => [['date_prevue' => 'demain'], 'La date prévue du soin est invalide.'],
            'type d\'action vide' => [['type_soin' => ''], "Le type d'action est obligatoire."],
            'statut inconnu' => [['statut' => 'Peut-être'], 'Le statut du soin est invalide.'],
            'rémanence négative' => [['remanence_jours' => -1], 'La rémanence ne peut pas être négative.'],
            'coût négatif' => [['cout_fcfa' => -5], 'Le coût ne peut pas être négatif.'],
            'échéance non UUID' => [['echeance_prophylaxie_id' => 'abc'], "L'identifiant de l'échéance doit être un UUID."],
            'échéance inconnue' => [['echeance_prophylaxie_id' => '99999999-9999-4999-8999-999999999999'], 'Échéance de prophylaxie inconnue du serveur.'],
            'identifiant non UUID' => [['id' => 'abc'], "L'identifiant de la ligne doit être un UUID."],
            'instant illisible' => [['updated_at' => 'hier'], 'La date de saisie de la ligne est invalide.'],
        ];
    }

    /** @dataProvider soinsInvalides */
    public function test_un_soin_invalide_est_refuse_avec_un_motif_francais(array $surcharge, string $motif): void
    {
        $a = $this->poste('animalier', 'eleveur');

        $bilan = $this->bilan($a, 'soins_calendrier', [$this->ligneSoin($surcharge)]);

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, SoinCalendrier::query()->count());
    }

    public function test_un_soin_issu_du_calendrier_est_accepte_quand_l_echeance_est_connue(): void
    {
        $a = $this->poste('admin', 'gerante');
        $e = $this->ligneEcheance();
        $this->demander($a, 'echeance_prophylaxie', $e)->assertOk();
        $s = $this->ligneSoin(['echeance_prophylaxie_id' => $e['id']]);

        $this->assertSame([$s['id']], $this->bilan($a, 'soins_calendrier', [$s])['accepted']);
        $this->assertSame($e['id'], SoinCalendrier::query()->find($s['id'])->echeance_prophylaxie_id);
    }

    public function test_le_type_d_action_est_un_texte_libre_comme_dans_planifier_une_intervention(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $s = $this->ligneSoin(['type_soin' => 'Vaccin Newcastle (Rappel)', 'statut' => 'Planifié']);

        $this->assertSame([$s['id']], $this->bilan($a, 'soins_calendrier', [$s])['accepted']);
        $this->assertSame('Vaccin Newcastle (Rappel)', SoinCalendrier::query()->find($s['id'])->type_soin);
    }

    public function test_deux_postes_qui_saisissent_hors_ligne_convergent_apres_un_tirage_mutuel(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $sa = $this->ligneSoin(['espece' => 'goliaths']);
        $sb = $this->ligneSoin(['espece' => 'lapins', 'type_soin' => 'Vermifuge']);
        $ea = $this->ligneEntree(['sujet' => 'Goliath #G-1']);
        $this->bilan($a, 'soins_calendrier', [$sa]);
        $this->bilan($b, 'soins_calendrier', [$sb]);
        $this->bilan($a, 'infirmerie', [$ea]);

        $versA = collect($this->tirer($a, 'soins_calendrier'))->pluck('id')->sort()->values()->all();
        $versB = collect($this->tirer($b, 'soins_calendrier'))->pluck('id')->sort()->values()->all();

        $this->assertSame(collect([$sa['id'], $sb['id']])->sort()->values()->all(), $versA);
        $this->assertSame($versA, $versB);
        $this->assertSame([$ea['id']], array_column($this->tirer($b, 'infirmerie'), 'id'));
    }

    public function test_dernier_ecrivain_gagne_strictement_et_un_rejeu_ne_change_rien(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $s = $this->ligneSoin(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->bilan($a, 'soins_calendrier', [$s]);
        $recu = SoinCalendrier::query()->find($s['id'])->serveur_modifie_le;

        // plus ancien : accepté sans rien changer
        $this->bilan($b, 'soins_calendrier', [['statut' => 'En retard', 'updated_at' => '2026-11-01T09:00:00.000000Z'] + $s]);
        $this->assertSame('Planifié', SoinCalendrier::query()->find($s['id'])->statut);
        // égal : idem (strictement supérieur seulement)
        $this->bilan($b, 'soins_calendrier', [['statut' => 'En retard'] + $s]);
        $this->assertSame('Planifié', SoinCalendrier::query()->find($s['id'])->statut);
        $this->assertTrue(SoinCalendrier::query()->find($s['id'])->serveur_modifie_le->equalTo($recu), 'un rejeu ne touche pas l\'instant de réception');

        // plus récent : gagne
        $this->bilan($b, 'soins_calendrier', [['statut' => 'Effectué', 'updated_at' => '2026-11-01T11:00:00.000000Z'] + $s]);
        $row = SoinCalendrier::query()->find($s['id']);
        $this->assertSame('Effectué', $row->statut);
        $this->assertSame($b['device'], $row->device_id);
    }

    public function test_les_droits_des_soins(): void
    {
        $caissier = $this->poste('caissier', 'amina');
        $comptable = $this->poste('comptable');

        foreach ([$caissier, $comptable] as $poste) {
            $bilan = $this->bilan($poste, 'soins_calendrier', [$this->ligneSoin()]);
            $this->assertSame([], $bilan['accepted']);
            $this->assertCount(1, $bilan['rejected']);
        }
        $this->assertSame(0, SoinCalendrier::query()->count());
    }

    public function test_un_soin_saisi_hors_ligne_atteint_un_poste_deja_a_jour(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $premier = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json();

        // saisie ancienne (3 jours) arrivée en retard
        $ancien = $this->ligneSoin(['updated_at' => now()->subDays(3)->format('Y-m-d\TH:i:s.u\Z')]);
        $this->bilan($a, 'soins_calendrier', [$ancien]);

        $suite = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull?since='.urlencode($premier['server_time']))->json('tables.soins_calendrier');
        $this->assertSame([$ancien['id']], array_column($suite, 'id'));
    }

    // ============================================================= INFIRMERIE

    public function test_une_entree_est_enregistree_et_redistribuee(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $e = $this->ligneEntree();

        $this->assertSame([$e['id']], $this->bilan($a, 'infirmerie', [$e])['accepted']);

        $row = EntreeInfirmerie::query()->find($e['id']);
        $this->assertSame('Infirmerie', $row->niveau_isolement);
        $recu = collect($this->tirer($b, 'infirmerie'))->firstWhere('id', $e['id']);
        $this->assertSame('2026-11-01', $recu['date_entree']);
        $this->assertNull($recu['date_sortie']);
    }

    public static function entreesInvalides(): array
    {
        return [
            'statut inconnu' => [['statut' => 'Envolé'], "Le statut de l'entrée est invalide."],
            'niveau inconnu' => [['niveau_isolement' => 'Villégiature'], "Ce niveau d'isolement n'existe pas."],
            'sujet vide' => [['sujet' => ''], 'Le sujet est obligatoire.'],
            'motif vide' => [['motif' => ''], 'Le motif est obligatoire.'],
            'date d\'entrée invalide' => [['date_entree' => '??'], "La date d'entrée est invalide."],
            'date de sortie invalide' => [['date_sortie' => '??'], 'La date de sortie est invalide.'],
            'sortie avant l\'entrée' => [['statut' => 'Réintégré', 'date_sortie' => '2026-10-01'], "La sortie ne peut précéder l'entrée."],
            'clôturée sans sortie' => [['statut' => 'Réintégré'], 'Une entrée clôturée doit avoir une date de sortie.'],
            'en cours avec sortie' => [['date_sortie' => '2026-11-03'], "Une entrée en cours n'a pas de date de sortie."],
            'mortalité sur un sujet vivant' => [['categorie_mortalite' => 2], 'La marque de mortalité ne vaut que pour un sujet décédé.'],
        ];
    }

    /** @dataProvider entreesInvalides */
    public function test_une_entree_invalide_est_refusee_avec_un_motif_francais(array $surcharge, string $motif): void
    {
        $a = $this->poste('animalier', 'eleveur');

        $bilan = $this->bilan($a, 'infirmerie', [$this->ligneEntree($surcharge)]);

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, EntreeInfirmerie::query()->count());
    }

    public function test_un_deces_conserve_sa_marque_de_mortalite_sans_effet_de_bord(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $e = $this->ligneEntree([
            'statut' => 'Décédé', 'date_sortie' => '2026-11-03', 'categorie_mortalite' => 1,
        ]);

        $this->assertSame([$e['id']], $this->bilan($a, 'infirmerie', [$e])['accepted']);

        $row = EntreeInfirmerie::query()->find($e['id']);
        $this->assertSame(1, $row->categorie_mortalite);
        $recu = collect($this->tirer($a, 'infirmerie'))->firstWhere('id', $e['id']);
        $this->assertSame(1, $recu['categorie_mortalite']);
    }

    public function test_la_cloture_d_une_entree_gagne_si_elle_est_plus_recente(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $e = $this->ligneEntree(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->bilan($a, 'infirmerie', [$e]);

        $this->bilan($a, 'infirmerie', [[
            'statut' => 'Réintégré', 'date_sortie' => '2026-11-04', 'updated_at' => '2026-11-04T10:00:00.000000Z',
        ] + $e]);

        $row = EntreeInfirmerie::query()->find($e['id']);
        $this->assertSame('Réintégré', $row->statut);
        $this->assertSame('2026-11-04', $row->date_sortie->format('Y-m-d'));
    }

    public function test_les_droits_de_l_infirmerie(): void
    {
        $caissier = $this->poste('caissier', 'amina');

        $bilan = $this->bilan($caissier, 'infirmerie', [$this->ligneEntree()]);

        $this->assertSame([], $bilan['accepted']);
        $this->assertSame(0, EntreeInfirmerie::query()->count());
    }

    // ================================================================= LOT

    public function test_un_lot_melange_est_traite_dans_l_ordre_des_dependances_et_un_refus_n_arrete_pas_les_autres(): void
    {
        $a = $this->poste('admin', 'gerante');
        $e = $this->ligneEcheance();
        $this->demander($a, 'echeance_prophylaxie', $e)->assertOk();

        $r = $this->avecJeton($a['jeton'])->postJson('/api/sync/push', [
            'device_id' => $a['device'], 'reset_mark' => 'initiale',
            'tables' => [
                'infirmerie' => [$this->ligneEntree(), $this->ligneEntree(['statut' => 'Envolé'])],
                'soins_calendrier' => [$this->ligneSoin(['echeance_prophylaxie_id' => $e['id']])],
            ],
        ])->assertOk();

        $this->assertCount(1, $r->json('infirmerie.accepted'));
        $this->assertCount(1, $r->json('infirmerie.rejected'));
        $this->assertCount(1, $r->json('soins_calendrier.accepted'));
        $this->assertSame(1, EntreeInfirmerie::query()->count());
        $this->assertSame(1, SoinCalendrier::query()->count());
    }
}
