<?php

namespace Tests\Feature\Sync;

use App\Models\Bande;
use App\Models\FicheJournee;
use App\Models\ParametresEntreprise;
use App\Models\SoinCalendrier;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * Elevage expert (`47e_`) : le lien soin -> bande voyage ; une fiche saisie par deux postes
 * qui ne se sont pas vus n'est JAMAIS perdue en silence (variantes conservees, resolution
 * explicite).
 */
class ElevageExpertTest extends TestCase
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

    private function tirer(array $poste, string $table): array
    {
        return $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->assertOk()->json('tables.'.$table);
    }

    private function instant(string $quand): string
    {
        return CarbonImmutable::parse($quand)->format('Y-m-d\TH:i:s.u\Z');
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

    private function fiche(string $obs, string $quand, array $surcharge = []): array
    {
        return $this->ligneFicheJournee('goliaths', '2026-11-05', array_merge([
            'traitement_obs' => $obs,
            'updated_at' => $this->instant($quand),
        ], $surcharge));
    }

    // ===================================================== soin -> bande

    public function test_le_lien_soin_bande_voyage_et_est_redistribue(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $bande = $this->ligneBande('B1');
        $this->bilan($a, 'bandes', [$bande]);
        $soin = $this->ligneSoin(['bande_id' => $bande['id']]);

        $this->assertSame([$soin['id']], $this->bilan($a, 'soins_calendrier', [$soin])['accepted']);

        $this->assertSame($bande['id'], SoinCalendrier::query()->find($soin['id'])->bande_id);
        $recu = collect($this->tirer($b, 'soins_calendrier'))->firstWhere('id', $soin['id']);
        $this->assertSame($bande['id'], $recu['bande_id']);
    }

    public function test_une_bande_inconnue_du_serveur_est_refusee_avec_son_motif(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $soin = $this->ligneSoin(['bande_id' => (string) Str::uuid()]);

        $bilan = $this->bilan($a, 'soins_calendrier', [$soin]);

        $this->assertSame([], $bilan['accepted']);
        $this->assertSame('Bande inconnue du serveur.', $bilan['rejected'][0]['motif']);
        $this->assertNull(SoinCalendrier::query()->find($soin['id']));
    }

    public function test_un_identifiant_de_bande_invalide_est_refuse(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $bilan = $this->bilan($a, 'soins_calendrier', [$this->ligneSoin(['bande_id' => 'B1'])]);
        $this->assertSame("L'identifiant de la bande doit être un UUID.", $bilan['rejected'][0]['motif']);
    }

    public function test_un_soin_libre_garde_une_bande_nulle(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $soin = $this->ligneSoin();
        $this->bilan($a, 'soins_calendrier', [$soin]);
        $this->assertNull(SoinCalendrier::query()->find($soin['id'])->bande_id);
    }

    // ============================================================ divergence

    public function test_une_suite_normale_du_meme_poste_ne_diverge_pas(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $v1 = $this->fiche('v1', '2026-11-05 10:00:00');
        $this->bilan($a, 'fiche_journee', [$v1]);
        $v2 = $this->fiche('v2', '2026-11-05 11:00:00', ['base_updated_at' => $v1['updated_at']]);
        $this->bilan($a, 'fiche_journee', [$v2]);

        $fiche = FicheJournee::query()->find($v1['id']);
        $this->assertSame('v2', $fiche->traitement_obs);
        $this->assertEmpty($fiche->variantes ?? []);
    }

    public function test_le_meme_poste_sans_base_ne_diverge_pas_avec_lui_meme(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $this->bilan($a, 'fiche_journee', [$this->fiche('v1', '2026-11-05 10:00:00')]);
        // Meme appareil, sans base (restauration d'une sauvegarde) : ce n'est pas un autre poste.
        $this->bilan($a, 'fiche_journee', [$this->fiche('v2', '2026-11-05 11:00:00')]);

        $this->assertEmpty(FicheJournee::query()->first()->variantes ?? []);
        $this->assertSame('v2', FicheJournee::query()->first()->traitement_obs);
    }

    public function test_un_autre_poste_qui_avait_vu_la_version_courante_ne_diverge_pas(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $v1 = $this->fiche('v1', '2026-11-05 10:00:00');
        $this->bilan($a, 'fiche_journee', [$v1]);
        $v2 = $this->fiche('v2', '2026-11-05 11:00:00', ['base_updated_at' => $v1['updated_at']]);
        $this->bilan($b, 'fiche_journee', [$v2]);

        $this->assertEmpty(FicheJournee::query()->find($v1['id'])->variantes ?? []);
        $this->assertSame('v2', FicheJournee::query()->find($v1['id'])->traitement_obs);
    }

    public function test_deux_postes_sans_se_voir_la_plus_recente_est_courante_et_l_autre_conservee(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $this->bilan($a, 'fiche_journee', [$this->fiche('A recente', '2026-11-05 12:00:00', ['achat' => 10])]);
        // B saisit plus tot, sans avoir vu A (pas de base).
        $this->bilan($b, 'fiche_journee', [$this->fiche('B ancienne', '2026-11-05 09:00:00', ['achat' => 25])]);

        $fiche = FicheJournee::query()->first();
        $this->assertSame('A recente', $fiche->traitement_obs);
        $this->assertCount(1, $fiche->variantes);
        $this->assertSame($b['device'], $fiche->variantes[0]['device_id']);
        $this->assertSame('B ancienne', $fiche->variantes[0]['contenu']['traitement_obs']);
        $this->assertSame(25, $fiche->variantes[0]['contenu']['achat']);
    }

    public function test_si_la_nouvelle_est_plus_recente_l_ancienne_courante_devient_variante(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $this->bilan($a, 'fiche_journee', [$this->fiche('A ancienne', '2026-11-05 09:00:00')]);
        $this->bilan($b, 'fiche_journee', [$this->fiche('B recente', '2026-11-05 12:00:00')]);

        $fiche = FicheJournee::query()->first();
        $this->assertSame('B recente', $fiche->traitement_obs);
        $this->assertSame('A ancienne', $fiche->variantes[0]['contenu']['traitement_obs']);
        $this->assertSame($a['device'], $fiche->variantes[0]['device_id']);
    }

    public function test_deux_saisies_identiques_ne_divergent_pas(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $this->bilan($a, 'fiche_journee', [$this->fiche('pareil', '2026-11-05 09:00:00')]);
        $this->bilan($b, 'fiche_journee', [$this->fiche('pareil', '2026-11-05 12:00:00')]);

        $this->assertEmpty(FicheJournee::query()->first()->variantes ?? []);
    }

    public function test_un_rejeu_de_la_perdante_ne_duplique_pas_la_variante(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $this->bilan($a, 'fiche_journee', [$this->fiche('A', '2026-11-05 12:00:00')]);
        $perdante = $this->fiche('B', '2026-11-05 09:00:00');
        $this->bilan($b, 'fiche_journee', [$perdante]);
        $this->bilan($b, 'fiche_journee', [$perdante]);

        $this->assertCount(1, FicheJournee::query()->first()->variantes);
    }

    public function test_une_troisieme_version_s_ajoute_sans_ecarter_la_premiere(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $c = $this->poste('admin', 'autre');
        $this->bilan($a, 'fiche_journee', [$this->fiche('A', '2026-11-05 12:00:00')]);
        $this->bilan($b, 'fiche_journee', [$this->fiche('B', '2026-11-05 09:00:00')]);
        $this->bilan($c, 'fiche_journee', [$this->fiche('C', '2026-11-05 10:00:00')]);

        $obs = collect(FicheJournee::query()->first()->variantes)->pluck('contenu.traitement_obs')->sort()->values()->all();
        $this->assertSame(['B', 'C'], $obs);
    }

    public function test_la_divergence_est_redistribuee_aux_postes(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $this->bilan($a, 'fiche_journee', [$this->fiche('A', '2026-11-05 12:00:00')]);
        $this->bilan($b, 'fiche_journee', [$this->fiche('B', '2026-11-05 09:00:00')]);

        $recu = collect($this->tirer($a, 'fiche_journee'))->first();
        $this->assertCount(1, $recu['variantes']);
        $this->assertSame('B', $recu['variantes'][0]['contenu']['traitement_obs']);
    }

    public function test_choisir_efface_les_variantes_et_applique_la_version_choisie(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $fiche = $this->fiche('A', '2026-11-05 12:00:00');
        $this->bilan($a, 'fiche_journee', [$fiche]);
        $this->bilan($b, 'fiche_journee', [$this->fiche('B', '2026-11-05 09:00:00')]);
        $this->assertNotEmpty(FicheJournee::query()->first()->variantes);

        // A choisit la version de B : ecriture plus recente, `resolution`.
        $this->bilan($a, 'fiche_journee', [$this->fiche('B', '2026-11-05 13:00:00', ['resolution' => true])]);

        $f = FicheJournee::query()->first();
        $this->assertSame('B', $f->traitement_obs);
        $this->assertEmpty($f->variantes ?? []);
    }

    public function test_une_resolution_plus_ancienne_que_la_courante_ne_change_rien(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $this->bilan($a, 'fiche_journee', [$this->fiche('A', '2026-11-05 12:00:00')]);
        $this->bilan($b, 'fiche_journee', [$this->fiche('B', '2026-11-05 09:00:00')]);

        $this->bilan($b, 'fiche_journee', [$this->fiche('B', '2026-11-05 10:00:00', ['resolution' => true])]);

        $f = FicheJournee::query()->first();
        $this->assertSame('A', $f->traitement_obs);
        $this->assertNotEmpty($f->variantes);
    }

    public function test_une_ecriture_normale_pendant_la_divergence_garde_les_variantes(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $b = $this->poste('admin', 'gerante');
        $v1 = $this->fiche('A', '2026-11-05 12:00:00');
        $this->bilan($a, 'fiche_journee', [$v1]);
        $this->bilan($b, 'fiche_journee', [$this->fiche('B', '2026-11-05 09:00:00')]);

        $this->bilan($a, 'fiche_journee', [$this->fiche('A2', '2026-11-05 14:00:00', ['base_updated_at' => $v1['updated_at']])]);

        $f = FicheJournee::query()->first();
        $this->assertSame('A2', $f->traitement_obs);
        $this->assertCount(1, $f->variantes, 'rien n\'est perdu tant que personne n\'a tranche');
    }

    public function test_un_poste_ne_peut_pas_ecrire_les_variantes(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $ligne = $this->fiche('A', '2026-11-05 12:00:00', ['variantes' => [['device_id' => 'x', 'updated_at' => 'x', 'contenu' => []]]]);
        $this->bilan($a, 'fiche_journee', [$ligne]);

        $this->assertEmpty(FicheJournee::query()->first()->variantes ?? []);
    }

    public function test_base_et_resolution_invalides_sont_refuses_avec_leur_motif(): void
    {
        $a = $this->poste('animalier', 'eleveur');
        $bilan = $this->bilan($a, 'fiche_journee', [$this->fiche('A', '2026-11-05 12:00:00', ['base_updated_at' => 'pas une date'])]);
        $this->assertSame('La version de départ de la fiche est invalide.', $bilan['rejected'][0]['motif']);
        $bilan = $this->bilan($a, 'fiche_journee', [$this->fiche('A', '2026-11-05 12:00:00', ['resolution' => 'oui'])]);
        $this->assertSame("L'indicateur « resolution » doit être vrai ou faux.", $bilan['rejected'][0]['motif']);
    }
}
