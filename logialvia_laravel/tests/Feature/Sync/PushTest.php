<?php

namespace Tests\Feature\Sync;

use App\Models\AuditLog;
use App\Models\Client;
use App\Models\ModuleActif;
use App\Sync\Tables\ClientsTable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** Envoi (push) : idempotent par UUID, dernier ecrivain gagne, refus motives, atomique. */
class PushTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function envoyer(array $poste, array $tables, string $marque = 'initiale')
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => $marque,
            'tables' => $tables,
        ]);
    }

    public function test_un_client_envoye_est_ecrit_en_base_avec_sa_provenance(): void
    {
        $poste = $this->poste();
        $ligne = $this->ligneClient(['nom' => 'Aïssatou', 'telephone' => '97000000', 'updated_at' => '2026-11-01T09:15:30.123456Z']);

        $this->envoyer($poste, ['clients' => [$ligne]])->assertOk()
            ->assertJsonPath('clients.accepted.0', $ligne['id'])
            ->assertJsonPath('clients.rejected', []);

        $client = Client::query()->findOrFail($ligne['id']);
        $this->assertSame('Aïssatou', $client->nom);
        $this->assertSame($poste['device'], $client->device_id, 'La provenance est le poste, pas le compte.');
        $this->assertSame('2026-11-01 09:15:30.123456', $client->getRawOriginal('updated_at'), "L'instant de saisie est conserve, microseconde comprise.");
        $this->assertTrue($client->serveur_modifie_le->greaterThan(now()->subMinute()), "L'instant de reception est celui du serveur.");
    }

    public function test_renvoyer_le_meme_lot_ne_cree_rien_de_plus(): void
    {
        $poste = $this->poste();
        $lot = ['clients' => [$this->ligneClient(), $this->ligneClient()]];

        $premier = $this->envoyer($poste, $lot)->assertOk()->json('clients.accepted');
        $second = $this->envoyer($poste, $lot)->assertOk()->json('clients.accepted');

        // Une reponse perdue apres traitement est un cas NORMAL : le rejeu est accepte.
        $this->assertSame($premier, $second);
        $this->assertSame(2, Client::query()->count());
    }

    public function test_le_rejeu_ne_change_pas_l_instant_de_reception(): void
    {
        $poste = $this->poste();
        $ligne = $this->ligneClient();

        $this->envoyer($poste, ['clients' => [$ligne]]);
        $premier = Client::query()->find($ligne['id'])->getRawOriginal('serveur_modifie_le');
        $this->travel(10)->seconds();
        $this->envoyer($poste, ['clients' => [$ligne]]);

        $this->assertSame($premier, Client::query()->find($ligne['id'])->getRawOriginal('serveur_modifie_le'),
            "Un rejeu n'est pas une modification : il ne doit pas relancer le tirage des autres postes.");
    }

    // ------------------------------------------------------ Dernier ecrivain gagne

    public function test_une_saisie_plus_recente_remplace_la_precedente(): void
    {
        $poste = $this->poste();
        $id = (string) Str::uuid();

        $this->envoyer($poste, ['clients' => [$this->ligneClient(['id' => $id, 'nom' => 'Avant', 'updated_at' => '2026-11-01T10:00:00.000000Z'])]]);
        $this->envoyer($poste, ['clients' => [$this->ligneClient(['id' => $id, 'nom' => 'Après', 'updated_at' => '2026-11-01T10:05:00.000000Z'])]]);

        $this->assertSame('Après', Client::query()->find($id)->nom);
        $this->assertSame(1, Client::query()->count());
    }

    public function test_une_saisie_plus_ancienne_arrivee_apres_est_acceptee_sans_rien_changer(): void
    {
        $poste = $this->poste();
        $id = (string) Str::uuid();

        $this->envoyer($poste, ['clients' => [$this->ligneClient(['id' => $id, 'nom' => 'Récent', 'updated_at' => '2026-11-01T10:05:00.000000Z'])]]);
        // Un poste hors ligne envoie enfin sa saisie, plus ANCIENNE que celle deja recue.
        $this->envoyer($poste, ['clients' => [$this->ligneClient(['id' => $id, 'nom' => 'Ancien', 'updated_at' => '2026-11-01T10:00:00.000000Z'])]])
            ->assertOk()->assertJsonPath('clients.accepted.0', $id);

        $this->assertSame('Récent', Client::query()->find($id)->nom);
    }

    public function test_deux_clients_de_meme_nom_restent_deux_lignes(): void
    {
        $poste = $this->poste();

        $this->envoyer($poste, ['clients' => [$this->ligneClient(['nom' => 'Doublon']), $this->ligneClient(['nom' => 'Doublon'])]]);

        // Jamais fusionnes en silence : deux UUID = deux faits.
        $this->assertSame(2, Client::query()->where('nom', 'Doublon')->count());
    }

    // ------------------------------------------------------------------ Refus

    public function test_une_ligne_invalide_est_refusee_avec_son_motif_sans_bloquer_les_autres(): void
    {
        $poste = $this->poste();
        $bonne = $this->ligneClient(['nom' => 'Valide']);
        $sansNom = $this->ligneClient(['nom' => '']);
        $mauvaisId = $this->ligneClient(['id' => 'pas-un-uuid']);

        $reponse = $this->envoyer($poste, ['clients' => [$bonne, $sansNom, $mauvaisId]])->assertOk();

        $reponse->assertJsonPath('clients.accepted', [$bonne['id']]);
        $motifs = collect($reponse->json('clients.rejected'))->pluck('motif', 'id');
        $this->assertSame('Le nom du client est obligatoire.', $motifs[$sansNom['id']]);
        $this->assertSame("L'identifiant de la ligne doit être un UUID.", $motifs['pas-un-uuid']);
        $this->assertSame(1, Client::query()->count());
    }

    public function test_une_ligne_sans_date_de_saisie_est_refusee(): void
    {
        $ligne = $this->ligneClient();
        unset($ligne['updated_at']);

        $this->envoyer($this->poste(), ['clients' => [$ligne]])->assertOk()
            ->assertJsonPath('clients.rejected.0.motif', 'La date de saisie de la ligne est obligatoire.');
        $this->assertSame(0, Client::query()->count());
    }

    public function test_une_table_inconnue_est_refusee_ligne_par_ligne(): void
    {
        $id = (string) Str::uuid();

        $this->envoyer($this->poste(), ['licornes' => [['id' => $id]]])->assertOk()
            ->assertJsonPath('licornes.rejected.0.id', $id)
            ->assertJsonPath('licornes.rejected.0.motif', 'Table inconnue du serveur : « licornes ».');
    }

    public function test_un_referentiel_envoye_par_un_poste_est_ignore_et_journalise(): void
    {
        $poste = $this->poste();
        $module = ModuleActif::query()->where('module_id', 'bovins')->firstOrFail();

        $this->envoyer($poste, ['modules_actifs' => [['id' => $module->id, 'module_id' => 'bovins', 'is_actif' => true]]])
            ->assertOk()
            ->assertJsonPath('modules_actifs.accepted', [])
            ->assertJsonPath('modules_actifs.ignored.0.id', $module->id);

        $this->assertFalse($module->fresh()->is_actif, 'Le serveur fait foi : rien ne change.');
        $trace = AuditLog::query()->where('action', 'sync.push')->sole();
        $this->assertSame(1, $trace->detail['tables']['modules_actifs']['ignorees']);
    }

    public function test_sans_le_droit_d_ecriture_aucune_ligne_n_est_ecrite(): void
    {
        $animalier = $this->poste('animalier');
        $ligne = $this->ligneClient();

        $this->envoyer($animalier, ['clients' => [$ligne]])->assertOk()
            ->assertJsonPath('clients.accepted', [])
            ->assertJsonPath('clients.rejected.0.motif', 'Droit insuffisant pour écrire dans « clients ».');

        $this->assertSame(0, Client::query()->count());
    }

    public function test_le_solde_de_creance_est_derive_et_jamais_accepte_d_un_poste(): void
    {
        $ligne = $this->ligneClient(['solde_creance' => 999999]);

        $this->envoyer($this->poste(), ['clients' => [$ligne]])->assertOk();

        $this->assertSame(0.0, Client::query()->find($ligne['id'])->solde_creance, 'Le serveur le calcule a partir des ventes.');
    }

    public function test_une_suppression_logique_est_enregistree(): void
    {
        $poste = $this->poste();
        $id = (string) Str::uuid();
        $this->envoyer($poste, ['clients' => [$this->ligneClient(['id' => $id, 'updated_at' => '2026-11-01T10:00:00.000000Z'])]]);

        $this->envoyer($poste, ['clients' => [$this->ligneClient(['id' => $id, 'updated_at' => '2026-11-01T11:00:00.000000Z', 'supprime_le' => '2026-11-01T11:00:00.000000Z'])]]);

        $this->assertNotNull(Client::query()->find($id)->supprime_le);
        $this->assertSame(1, Client::query()->count(), 'Une pierre tombale, pas un effacement.');
    }

    // ----------------------------------------------------------- Remise a zero

    public function test_une_marque_de_remise_a_zero_inconnue_donne_409_sans_rien_ecrire(): void
    {
        $ligne = $this->ligneClient();

        $this->envoyer($this->poste(), ['clients' => [$ligne]], 'marque-d-avant')
            ->assertStatus(409)
            ->assertJsonPath('code', 'remise_a_zero_inconnue')
            ->assertJsonPath('reset_mark', 'initiale');

        $this->assertSame(0, Client::query()->count());
    }

    // ------------------------------------------------------------- Forme du lot

    public function test_un_lot_mal_forme_est_refuse_en_francais(): void
    {
        $poste = $this->poste();

        $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', ['device_id' => $poste['device'], 'reset_mark' => 'initiale'])
            ->assertStatus(422)->assertJsonValidationErrors('tables');
        $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', ['device_id' => $poste['device'], 'tables' => []])
            ->assertStatus(422)->assertJsonValidationErrors('reset_mark');
    }

    // ---------------------------------------------------------- Transaction

    public function test_une_panne_en_cours_de_lot_n_ecrit_rien_du_tout(): void
    {
        // Seconde table dont le traitement echoue APRES que les clients ont ete ecrits.
        config(['logialvia.sync.tables' => [ClientsTable::class, TableQuiEchoue::class]]);
        $poste = $this->poste();

        // Le poste recoit une erreur serveur (il renverra le lot plus tard : c'est idempotent).
        $this->envoyer($poste, [
            'clients' => [$this->ligneClient()],
            'faux' => [$this->ligneClient()],
        ])->assertStatus(500);

        $this->assertSame(0, Client::query()->count(), 'Tout le lot dans UNE transaction : rien ne reste a moitie ecrit.');
    }

    // ---------------------------------------------------------------- Journal

    public function test_un_lot_vide_ne_laisse_aucune_trace_un_lot_plein_en_laisse_une(): void
    {
        $poste = $this->poste();

        $this->envoyer($poste, [])->assertOk();
        $this->assertSame(0, AuditLog::query()->where('action', 'sync.push')->count());

        $this->envoyer($poste, ['clients' => [$this->ligneClient(), $this->ligneClient(['nom' => ''])]])->assertOk();
        $trace = AuditLog::query()->where('action', 'sync.push')->sole();
        $this->assertSame(['acceptees' => 1, 'refusees' => 1, 'ignorees' => 0], $trace->detail['tables']['clients']);
        $this->assertSame($poste['device'], $trace->detail['device_id']);
    }
}

/** Table de test : echoue apres que `clients` a ete ecrit. */
class TableQuiEchoue extends ClientsTable
{
    public function nom(): string
    {
        return 'faux';
    }

    public function regles(): array
    {
        throw new \RuntimeException('panne simulee');
    }
}
