<?php

namespace Tests\Feature\Sync;

use App\Models\ModuleActif;
use App\Models\ParametresEntreprise;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** `POST /api/sync/demandes` : le poste propose, le serveur decide. */
class DemandesReferentielTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
        // Les lignes de semis sont creees ICI ; une demande doit tomber apres.
        $this->travel(5)->seconds();
    }

    private function demande(string $type, array $donnees, ?string $saisi = null, ?string $id = null): array
    {
        return [
            'id' => $id ?? (string) Str::uuid(),
            'type' => $type,
            'saisi_le' => $saisi ?? now()->format('Y-m-d\TH:i:s.u\Z'),
            'donnees' => $donnees,
        ];
    }

    private function envoyer(array $poste, array $demandes)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $poste['device'],
            'demandes' => $demandes,
        ]);
    }

    public function test_un_module_propose_par_un_administrateur_est_applique_et_decide(): void
    {
        $poste = $this->poste('admin', 'gerante');
        $d = $this->demande('module_actif', ['module_id' => 'ovins', 'is_actif' => true]);

        $this->envoyer($poste, [$d])->assertOk()->assertJson(['accepted' => [$d['id']], 'rejected' => []]);

        $module = ModuleActif::query()->where('module_id', 'ovins')->first();
        $this->assertTrue($module->is_actif);
        $this->assertTrue($module->updated_at->greaterThan($module->created_at), 'la ligne est DECIDEE : elle ne passe plus pour du semis');
        $this->assertDatabaseHas('audit_logs', ['action' => 'sync.demandes']);
    }

    public function test_une_valeur_identique_a_celle_du_semis_decide_quand_meme_la_ligne(): void
    {
        // Le poste confirme « ovins = inactif », ce que le semis du serveur dit deja :
        // la ligne doit quand meme cesser d'etre une valeur de semis.
        $poste = $this->poste('admin', 'gerante');
        $d = $this->demande('module_actif', ['module_id' => 'ovins', 'is_actif' => false]);

        $this->envoyer($poste, [$d])->assertJson(['accepted' => [$d['id']]]);

        $module = ModuleActif::query()->where('module_id', 'ovins')->first();
        $this->assertTrue($module->updated_at->greaterThan($module->created_at));
    }

    public function test_sans_le_droit_la_demande_est_refusee_avec_son_motif(): void
    {
        $poste = $this->poste('caissier');
        $d = $this->demande('module_actif', ['module_id' => 'ovins', 'is_actif' => true]);

        $this->envoyer($poste, [$d])->assertOk()
            ->assertJson(['accepted' => [], 'rejected' => [['id' => $d['id'], 'motif' => 'Droit insuffisant pour modifier les modules actifs.']]]);

        $this->assertFalse(ModuleActif::query()->where('module_id', 'ovins')->value('is_actif'));
    }

    public function test_un_module_inconnu_est_refuse(): void
    {
        $poste = $this->poste('admin', 'gerante');
        $d = $this->demande('module_actif', ['module_id' => 'astrologie', 'is_actif' => true]);

        $this->envoyer($poste, [$d])->assertJsonPath('rejected.0.motif', 'Module inconnu du serveur : « astrologie ».');
        $this->assertDatabaseMissing('modules_actifs', ['module_id' => 'astrologie']);
    }

    public function test_des_parametres_proposes_sont_appliques_sans_effacer_par_du_vide(): void
    {
        $poste = $this->poste('admin', 'gerante');
        ParametresEntreprise::courant()->forceFill(['ifu' => 'IFU-SERVEUR'])->save();
        $d = $this->demande('parametres_entreprise', [
            'raison_sociale' => 'ALLMANY SARL', 'prefixe_bac' => 'BC', 'smtp_port' => 587, 'ifu' => null, 'telephone' => '',
        ]);

        $this->envoyer($poste, [$d])->assertJson(['accepted' => [$d['id']]]);

        $p = ParametresEntreprise::courant()->fresh();
        $this->assertSame('ALLMANY SARL', $p->raison_sociale);
        $this->assertSame('BC', $p->prefixe_bac);
        $this->assertSame(587, $p->smtp_port);
        $this->assertSame('IFU-SERVEUR', $p->ifu, 'une valeur vide n\'efface jamais celle du serveur');
        $this->assertTrue($p->updated_at->greaterThan($p->created_at));
    }

    public function test_les_champs_propres_a_une_machine_ou_de_securite_ne_sont_jamais_acceptes(): void
    {
        $poste = $this->poste('admin', 'gerante');
        foreach (['chemin_logo' => 'C:\\logo.png', 'mode_donnees_test' => true, 'marque_remise_a_zero' => 'pirate', 'id' => 'x'] as $champ => $valeur) {
            $d = $this->demande('parametres_entreprise', ['raison_sociale' => 'Pirate', $champ => $valeur]);
            $this->envoyer($poste, [$d])->assertJsonPath('rejected.0.id', $d['id']);
        }

        $p = ParametresEntreprise::courant()->fresh();
        $this->assertSame('ALLMANY ET COMPAGNIE', $p->raison_sociale, 'rien n\'est ecrit quand un champ interdit accompagne la demande');
        $this->assertFalse($p->mode_donnees_test);
        $this->assertSame('initiale', $p->marque_remise_a_zero);
        $this->assertNull($p->chemin_logo);
    }

    public function test_un_prefixe_invalide_est_refuse_avec_un_message_francais(): void
    {
        $poste = $this->poste('admin', 'gerante');
        $d = $this->demande('parametres_entreprise', ['prefixe_cage' => 'TROPLONG']);

        $this->envoyer($poste, [$d])->assertJsonPath('rejected.0.motif', 'Un préfixe compte 4 caractères au plus.');
        $this->assertSame('C', ParametresEntreprise::courant()->fresh()->prefixe_cage);
    }

    public function test_seul_un_gestionnaire_modifie_les_parametres(): void
    {
        $poste = $this->poste('comptable');
        $d = $this->demande('parametres_entreprise', ['raison_sociale' => 'Autre']);

        $this->envoyer($poste, [$d])->assertJsonPath('rejected.0.motif', 'Droit insuffisant pour modifier les paramètres de l\'entreprise.');
    }

    public function test_une_demande_rejouee_rend_la_meme_issue_sans_rien_reappliquer(): void
    {
        $poste = $this->poste('admin', 'gerante');
        $d = $this->demande('module_actif', ['module_id' => 'ovins', 'is_actif' => true]);
        $this->envoyer($poste, [$d])->assertJson(['accepted' => [$d['id']]]);

        // Le serveur change ensuite ; rejouer la demande ne doit PAS ecraser ce choix.
        $this->travel(5)->seconds();
        ModuleActif::query()->where('module_id', 'ovins')->update(['is_actif' => false]);

        $this->envoyer($poste, [$d])->assertJson(['accepted' => [$d['id']], 'rejected' => []]);
        $this->assertFalse(ModuleActif::query()->where('module_id', 'ovins')->value('is_actif'));
        $this->assertDatabaseCount('demandes_referentiel', 1);
    }

    public function test_un_refus_rejoue_rend_le_meme_motif(): void
    {
        // Refus DEFINITIF (module inconnu) : memorise. Un refus pour droit ne l'est pas (`47g_`).
        $poste = $this->poste('admin', 'gerante');
        $d = $this->demande('module_actif', ['module_id' => 'dragons', 'is_actif' => true]);
        $premier = $this->envoyer($poste, [$d])->json('rejected.0.motif');

        $this->envoyer($poste, [$d])->assertJsonPath('rejected.0.motif', $premier);
        $this->assertDatabaseCount('demandes_referentiel', 1);
    }

    public function test_une_demande_plus_ancienne_que_la_decision_du_serveur_est_refusee(): void
    {
        $poste = $this->poste('admin', 'gerante');
        // Le serveur a DECIDE (modification faite au web, apres le semis).
        $this->travel(60)->seconds();
        $decision = now();
        ModuleActif::query()->where('module_id', 'ovins')->update(['is_actif' => true]);
        $ancienne = $this->demande('module_actif', ['module_id' => 'ovins', 'is_actif' => false], $decision->copy()->subMinutes(10)->format('Y-m-d\TH:i:s.u\Z'));

        $this->envoyer($poste, [$ancienne])->assertJsonPath('rejected.0.motif', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.');
        $this->assertTrue(ModuleActif::query()->where('module_id', 'ovins')->value('is_actif'));

        $recente = $this->demande('module_actif', ['module_id' => 'ovins', 'is_actif' => false], $decision->copy()->addMinute()->format('Y-m-d\TH:i:s.u\Z'));
        $this->envoyer($poste, [$recente])->assertJson(['accepted' => [$recente['id']]]);
        $this->assertFalse(ModuleActif::query()->where('module_id', 'ovins')->value('is_actif'));
    }

    public function test_une_ligne_de_semis_accepte_toute_saisie_meme_ancienne(): void
    {
        $poste = $this->poste('admin', 'gerante');
        $d = $this->demande('module_actif', ['module_id' => 'ovins', 'is_actif' => true], now()->subDays(30)->format('Y-m-d\TH:i:s.u\Z'));

        $this->envoyer($poste, [$d])->assertJson(['accepted' => [$d['id']]]);
    }

    public function test_une_demande_acceptee_redescend_vers_les_autres_postes(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('caissier', 'bako');
        $this->envoyer($a, [$this->demande('module_actif', ['module_id' => 'ovins', 'is_actif' => true])])->assertOk();

        $ligne = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.modules_actifs'))
            ->firstWhere('module_id', 'ovins');

        $this->assertTrue($ligne['is_actif']);
        $this->assertGreaterThan(strtotime($ligne['created_at']), strtotime($ligne['updated_at']), 'le poste le recoit comme une decision');
    }

    public function test_les_demandes_invalides_sont_refusees_une_par_une(): void
    {
        $poste = $this->poste('admin', 'gerante');
        $bonne = $this->demande('module_actif', ['module_id' => 'ovins', 'is_actif' => true]);
        $sansId = ['type' => 'module_actif', 'saisi_le' => now()->toIso8601String(), 'donnees' => []];
        $typeInconnu = $this->demande('astrologie', ['x' => 1]);

        $r = $this->envoyer($poste, [$sansId, $typeInconnu, $bonne])->assertOk()->json();

        $this->assertSame([$bonne['id']], $r['accepted']);
        $this->assertCount(2, $r['rejected']);
        $this->assertSame("Type de demande inconnu du serveur : « astrologie ».", $r['rejected'][1]['motif']);
    }

    public function test_un_poste_ne_signe_pas_au_nom_d_un_autre(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');

        $this->avecJeton($b['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $a['device'], 'demandes' => [$this->demande('module_actif', ['module_id' => 'ovins', 'is_actif' => true])],
        ])->assertStatus(403);
        $this->assertDatabaseCount('demandes_referentiel', 0);
    }

    public function test_un_poste_revoque_ne_peut_plus_rien_proposer(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        app(\App\Services\PostesService::class)->revoquer($b['device'], $admin['utilisateur']);

        $this->envoyer($b, [])->assertStatus(401);
    }

    public function test_une_liste_vide_est_acceptee_et_n_ecrit_rien(): void
    {
        $poste = $this->poste('admin', 'gerante');
        $this->envoyer($poste, [])->assertOk()->assertJson(['accepted' => [], 'rejected' => []]);
        $this->assertDatabaseMissing('audit_logs', ['action' => 'sync.demandes']);
    }
}
