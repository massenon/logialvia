<?php

namespace Tests\Feature\Sync;

use App\Models\Client;
use App\Models\CycleCouveuse;
use App\Models\MachineIncubateur;
use App\Models\ParametresEntreprise;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * Couveuse (7b, `46b_`) : incubateurs et lots d'incubation avec leurs mirages. Faits saisis
 * au poste, dernier ecrivain gagne par UUID, suppression par pierre tombale, aucun effet de
 * bord (ni naissances, ni stock, ni ecriture).
 */
class CouveuseTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function pousser(array $poste, array $tables, string $marque = 'initiale')
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => $marque,
            'tables' => $tables,
        ]);
    }

    private function bilanLots(array $poste, array $lots): array
    {
        return $this->pousser($poste, ['cycle_couveuse' => $lots])->assertOk()->json('cycle_couveuse');
    }

    private function bilanMachines(array $poste, array $machines): array
    {
        return $this->pousser($poste, ['machines_incubateur' => $machines])->assertOk()->json('machines_incubateur');
    }

    private function machineConnue(array $poste, array $surcharge = []): string
    {
        $m = $this->ligneMachine($surcharge);
        $this->assertSame([$m['id']], $this->bilanMachines($poste, [$m])['accepted']);

        return $m['id'];
    }

    private function instant(string $horodatage): string
    {
        return $horodatage;
    }

    // ------------------------------------------------------------ Incubateurs

    public function test_un_incubateur_est_enregistre_et_redescend_vers_un_autre_poste(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('animalier', 'bako');
        $id = $this->machineConnue($a);

        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.machines_incubateur'))->firstWhere('id', $id);

        $this->assertSame('INC-01', $recu['code']);
        $this->assertSame(528, $recu['capacite_oeufs']);
        $this->assertTrue($recu['active']);
        $this->assertSame($a['device'], $recu['device_id']);
    }

    public static function machinesInvalides(): array
    {
        return [
            'code vide' => [['code' => ' '], "Le code de l'incubateur est obligatoire."],
            'code trop long' => [['code' => str_repeat('X', 41)], "Le code de l'incubateur est trop long."],
            'libellé vide' => [['libelle' => ''], "Le libellé de l'incubateur est obligatoire."],
            'capacité nulle' => [['capacite_oeufs' => 0], 'La capacité doit être supérieure à 0.'],
            'capacité en texte' => [['capacite_oeufs' => '500'], 'La capacité doit être supérieure à 0.'],
            'état numérique' => [['active' => 1], "L'état de l'incubateur est invalide."],
            'identifiant invalide' => [['id' => 'pas-un-uuid'], "L'identifiant de la ligne doit être un UUID."],
            'sans date de saisie' => [['updated_at' => null], 'La date de saisie de la ligne est obligatoire.'],
        ];
    }

    /** @dataProvider machinesInvalides */
    public function test_un_incubateur_invalide_est_refuse_avec_un_motif_francais(array $surcharge, string $motif): void
    {
        $a = $this->poste('admin', 'gerante');

        $bilan = $this->bilanMachines($a, [$this->ligneMachine($surcharge)]);

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, MachineIncubateur::query()->count());
    }

    public function test_une_capacite_inconnue_est_acceptee(): void
    {
        $a = $this->poste('admin', 'gerante');

        $bilan = $this->bilanMachines($a, [$this->ligneMachine(['capacite_oeufs' => null])]);

        $this->assertSame([], $bilan['rejected']);
        $this->assertNull(MachineIncubateur::query()->first()->capacite_oeufs);
    }

    public function test_un_autre_incubateur_qui_porte_le_meme_code_est_refuse_jamais_fusionne(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $this->machineConnue($a, ['code' => 'INC-01']);

        $bilan = $this->bilanMachines($b, [$this->ligneMachine(['code' => 'inc-01'])]);

        $this->assertSame('Un incubateur porte déjà le code inc-01.', $bilan['rejected'][0]['motif']);
        $this->assertSame(1, MachineIncubateur::query()->count());
    }

    public function test_le_meme_incubateur_renvoye_par_deux_postes_n_en_fait_qu_un(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $m = $this->ligneMachine();

        $this->assertSame([$m['id']], $this->bilanMachines($a, [$m])['accepted']);
        $this->assertSame([$m['id']], $this->bilanMachines($b, [$m])['accepted'], 'rejeu : accepté sans effet');

        $this->assertSame(1, MachineIncubateur::query()->count());
    }

    public function test_un_incubateur_suit_le_dernier_ecrivain(): void
    {
        $a = $this->poste('admin', 'gerante');
        $m = $this->ligneMachine(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->bilanMachines($a, [$m]);

        $this->bilanMachines($a, [array_merge($m, ['libelle' => 'Couveuse neuve', 'capacite_oeufs' => 700, 'active' => false, 'updated_at' => '2026-11-01T11:00:00.000000Z'])]);
        $row = MachineIncubateur::query()->find($m['id']);
        $this->assertSame('Couveuse neuve', $row->libelle);
        $this->assertSame(700, $row->capacite_oeufs);
        $this->assertFalse($row->active);

        $this->bilanMachines($a, [array_merge($m, ['libelle' => 'Trop ancienne', 'updated_at' => '2026-11-01T09:00:00.000000Z'])]);
        $this->assertSame('Couveuse neuve', MachineIncubateur::query()->find($m['id'])->libelle, 'saisie plus ancienne : sans effet');
    }

    // ------------------------------------------------------------------- Lots

    public function test_un_lot_est_enregistre_avec_son_incubateur_et_redescend(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('animalier', 'bako');
        $machine = $this->machineConnue($a);
        $lot = $this->ligneCycle(['machine_id' => $machine]);

        $bilan = $this->bilanLots($a, [$lot]);

        $this->assertSame([$lot['id']], $bilan['accepted']);
        $row = CycleCouveuse::query()->find($lot['id']);
        $this->assertSame('C-P1-2026-001', $row->code_incubation);
        $this->assertSame('2026-08-01', $row->date_incubation->format('Y-m-d'));
        $this->assertSame($a['device'], $row->device_id);
        $this->assertNull($row->oeufs_blancs_j7, 'pas encore miré : null, pas zéro');

        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.cycle_couveuse'))->firstWhere('id', $lot['id']);
        $this->assertSame('2026-08-01', $recu['date_incubation']);
        $this->assertSame($machine, $recu['machine_id']);
        $this->assertArrayNotHasKey('portee_code', $recu);
        $this->assertNull($recu['supprime_le']);
    }

    public function test_les_mirages_sont_des_modifications_du_lot_saisies_dans_le_temps(): void
    {
        $a = $this->poste('admin', 'gerante');
        $lot = $this->ligneCycle(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->bilanLots($a, [$lot]);

        $this->bilanLots($a, [array_merge($lot, ['oeufs_blancs_j7' => 22, 'updated_at' => '2026-11-08T10:00:00.000000Z'])]);
        $this->assertSame(22, CycleCouveuse::query()->find($lot['id'])->oeufs_blancs_j7);
        $this->assertNull(CycleCouveuse::query()->find($lot['id'])->oeufs_gates_j14);

        $this->bilanLots($a, [array_merge($lot, ['oeufs_blancs_j7' => 22, 'oeufs_gates_j14' => 0, 'updated_at' => '2026-11-15T10:00:00.000000Z'])]);
        $row = CycleCouveuse::query()->find($lot['id']);
        $this->assertSame(0, $row->oeufs_gates_j14, 'mirage fait, zéro œuf gâté : distinct de « pas miré »');

        $this->bilanLots($a, [array_merge($lot, ['oeufs_blancs_j7' => 99, 'updated_at' => '2026-11-05T10:00:00.000000Z'])]);
        $this->assertSame(22, CycleCouveuse::query()->find($lot['id'])->oeufs_blancs_j7, 'saisie plus ancienne : sans effet');
    }

    public function test_une_eclosion_avec_remplacement_voyage_comme_deux_lots(): void
    {
        $a = $this->poste('admin', 'gerante');
        $parent = $this->ligneCycle();
        $enfant = $this->ligneCycle(['code_incubation' => 'C-P1-2026-002', 'lot_parent_id' => $parent['id']]);
        $parentEclos = array_merge($parent, ['poussins_nes' => 150, 'oeufs_perdus' => 10, 'statut' => 'Remplacé', 'updated_at' => now()->addSecond()->format('Y-m-d\TH:i:s.u\Z')]);

        $bilan = $this->bilanLots($a, [$parentEclos, $enfant]);

        $this->assertCount(2, $bilan['accepted']);
        $this->assertSame($parent['id'], CycleCouveuse::query()->find($enfant['id'])->lot_parent_id);
    }

    public static function lotsInvalides(): array
    {
        return [
            'code vide' => [['code_incubation' => ' '], 'Le code du lot est obligatoire.'],
            'code trop long' => [['code_incubation' => str_repeat('C', 41)], 'Le code du lot est trop long.'],
            'espèce inconnue' => [['espece' => 'autruche'], "L'espèce du lot est inconnue."],
            'statut inconnu' => [['statut' => 'Perdu'], 'Le statut du lot est inconnu.'],
            'date absente' => [['date_incubation' => null], 'La date de chargement est obligatoire.'],
            'date invalide' => [['date_incubation' => '01/08/2026'], 'La date de chargement est invalide.'],
            'zéro œuf chargé' => [['oeufs_couves' => 0], "Le nombre d'œufs chargés est obligatoire."],
            'œufs chargés en texte' => [['oeufs_couves' => '200'], "Le nombre d'œufs chargés est obligatoire."],
            'œufs chargés fractionnaires' => [['oeufs_couves' => 20.5], "Le nombre d'œufs chargés est obligatoire."],
            'clairs négatifs' => [['oeufs_blancs_j7' => -1], 'Les quantités ne peuvent être négatives.'],
            'perdus négatifs' => [['oeufs_perdus' => -2], 'Les quantités ne peuvent être négatives.'],
            'mirages qui retirent trop' => [['oeufs_couves' => 100, 'oeufs_blancs_j7' => 60, 'oeufs_gates_j14' => 50], "Les mirages retirent plus d'œufs que le lot n'en contient."],
            'éclos + perdus au-delà des retenus' => [['oeufs_couves' => 100, 'oeufs_blancs_j7' => 20, 'poussins_nes' => 70, 'oeufs_perdus' => 20], 'Poussins éclos + œufs perdus dépasse les œufs encore en incubation après les mirages.'],
            'lot qui se remplace lui-même' => [['lot_parent_id' => '@self'], 'Un lot ne peut pas se remplacer lui-même.'],
            'origine invalide' => [['lot_parent_id' => 'x'], "L'identifiant du lot d'origine est invalide."],
            'incubateur invalide' => [['machine_id' => 'x'], "L'identifiant de l'incubateur est invalide."],
            'incubateur inconnu' => [['machine_id' => 'cccccccc-0000-4000-8000-000000000001'], 'Incubateur inconnu du serveur.'],
            'identifiant invalide' => [['id' => 'nope'], "L'identifiant de la ligne doit être un UUID."],
        ];
    }

    /** @dataProvider lotsInvalides */
    public function test_un_lot_invalide_est_refuse_avec_un_motif_francais_rien_d_ecrit(array $surcharge, string $motif): void
    {
        $a = $this->poste('admin', 'gerante');
        $lot = $this->ligneCycle($surcharge);
        if (($lot['lot_parent_id'] ?? null) === '@self') {
            $lot['lot_parent_id'] = $lot['id'];
        }

        $bilan = $this->bilanLots($a, [$lot]);

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame([], $bilan['accepted']);
        $this->assertSame(0, CycleCouveuse::query()->count());
    }

    public function test_les_bornes_exactes_sont_acceptees(): void
    {
        $a = $this->poste('admin', 'gerante');
        // Tout retiré aux mirages, rien à faire éclore ; éclos + perdus = retenus.
        $vide = $this->ligneCycle(['oeufs_couves' => 100, 'oeufs_blancs_j7' => 60, 'oeufs_gates_j14' => 40]);
        $plein = $this->ligneCycle(['code_incubation' => 'C-P1-2026-002', 'oeufs_couves' => 100, 'oeufs_blancs_j7' => 20, 'poussins_nes' => 70, 'oeufs_perdus' => 10, 'statut' => 'Éclosion Effectuée']);

        $bilan = $this->bilanLots($a, [$vide, $plein]);

        $this->assertSame([], $bilan['rejected']);
    }

    public function test_un_lot_dont_l_origine_n_est_pas_encore_arrivee_est_accepte(): void
    {
        $a = $this->poste('admin', 'gerante');
        $enfant = $this->ligneCycle(['lot_parent_id' => (string) Str::uuid()]);

        $this->assertSame([], $this->bilanLots($a, [$enfant])['rejected']);
    }

    public function test_un_lot_est_accepte_avant_ou_apres_son_incubateur_dans_le_meme_envoi(): void
    {
        // Les tables sont traitees dans l'ordre de `sync.tables`, quel que soit l'ordre du lot.
        $a = $this->poste('admin', 'gerante');
        $m = $this->ligneMachine();
        $lot = $this->ligneCycle(['machine_id' => $m['id']]);

        $reponse = $this->pousser($a, ['cycle_couveuse' => [$lot], 'machines_incubateur' => [$m]])->assertOk();

        $reponse->assertJsonPath('cycle_couveuse.rejected', []);
        $reponse->assertJsonPath('machines_incubateur.rejected', []);
        $this->assertSame(1, CycleCouveuse::query()->count());
    }

    // ------------------------------------------------- Code du lot (unicite)

    public function test_un_code_a_poste_est_unique_pour_tous(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $this->bilanLots($a, [$this->ligneCycle(['code_incubation' => 'C-P2-2026-001'])]);

        $bilan = $this->bilanLots($b, [$this->ligneCycle(['code_incubation' => 'C-P2-2026-001'])]);

        $this->assertSame('Ce code est déjà utilisé par un autre lot.', $bilan['rejected'][0]['motif']);
        $this->assertSame(1, CycleCouveuse::query()->count());
    }

    public function test_deux_postes_peuvent_avoir_le_meme_ancien_code_sans_poste(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $la = $this->ligneCycle(['code_incubation' => 'C-2026-001']);
        $lb = $this->ligneCycle(['code_incubation' => 'C-2026-001']);

        $this->assertSame([$la['id']], $this->bilanLots($a, [$la])['accepted']);
        $this->assertSame([$lb['id']], $this->bilanLots($b, [$lb])['accepted']);
        $this->assertSame(2, CycleCouveuse::query()->count());
    }

    public function test_un_meme_poste_ne_reutilise_pas_un_ancien_code(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->bilanLots($a, [$this->ligneCycle(['code_incubation' => 'C-2026-001'])]);

        $bilan = $this->bilanLots($a, [$this->ligneCycle(['code_incubation' => 'C-2026-001'])]);

        $this->assertSame('Ce code est déjà utilisé par un autre lot.', $bilan['rejected'][0]['motif']);
    }

    public function test_le_code_d_un_lot_ne_change_jamais(): void
    {
        $a = $this->poste('admin', 'gerante');
        $lot = $this->ligneCycle(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->bilanLots($a, [$lot]);

        $bilan = $this->bilanLots($a, [array_merge($lot, ['code_incubation' => 'C-P1-2026-999', 'updated_at' => '2026-11-01T11:00:00.000000Z'])]);

        $this->assertSame("Le code d'un lot ne change jamais.", $bilan['rejected'][0]['motif']);
        $this->assertSame('C-P1-2026-001', CycleCouveuse::query()->find($lot['id'])->code_incubation);
    }

    public function test_un_lot_supprime_libere_son_code(): void
    {
        $a = $this->poste('admin', 'gerante');
        $lot = $this->ligneCycle(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->bilanLots($a, [$lot]);
        $this->bilanLots($a, [array_merge($lot, ['supprime_le' => '2026-11-01T11:00:00.000000Z', 'updated_at' => '2026-11-01T11:00:00.000000Z'])]);

        $bilan = $this->bilanLots($a, [$this->ligneCycle(['code_incubation' => 'C-P1-2026-001'])]);

        $this->assertSame([], $bilan['rejected'], 'le poste réutilise le numéro d\'un lot supprimé');
    }

    // ---------------------------------------------------- Pierre tombale

    public function test_la_suppression_est_une_pierre_tombale_redistribuee_aux_postes(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('animalier', 'bako');
        $lot = $this->ligneCycle(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->bilanLots($a, [$lot]);
        $curseur = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('server_time');
        $this->travel(5)->seconds();

        $this->bilanLots($a, [array_merge($lot, ['supprime_le' => '2026-11-01T11:00:00.000000Z', 'updated_at' => '2026-11-01T11:00:00.000000Z'])]);

        $this->assertNotNull(CycleCouveuse::query()->find($lot['id'])->supprime_le, 'jamais d\'effacement physique');
        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull?since='.urlencode($curseur))->json('tables.cycle_couveuse'))->firstWhere('id', $lot['id']);
        $this->assertNotNull($recu['supprime_le']);
    }

    public function test_une_saisie_plus_recente_leve_la_pierre_tombale_un_lot_restaure_revient(): void
    {
        $a = $this->poste('admin', 'gerante');
        $lot = $this->ligneCycle(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->bilanLots($a, [$lot]);
        $this->bilanLots($a, [array_merge($lot, ['supprime_le' => '2026-11-01T11:00:00.000000Z', 'updated_at' => '2026-11-01T11:00:00.000000Z'])]);

        $this->bilanLots($a, [array_merge($lot, ['supprime_le' => null, 'updated_at' => '2026-11-01T12:00:00.000000Z'])]);

        $this->assertNull(CycleCouveuse::query()->find($lot['id'])->supprime_le);
    }

    public function test_une_suppression_plus_ancienne_que_la_derniere_saisie_est_sans_effet(): void
    {
        $a = $this->poste('admin', 'gerante');
        $lot = $this->ligneCycle(['updated_at' => '2026-11-01T12:00:00.000000Z']);
        $this->bilanLots($a, [$lot]);

        $this->bilanLots($a, [array_merge($lot, ['supprime_le' => '2026-11-01T11:00:00.000000Z', 'updated_at' => '2026-11-01T11:00:00.000000Z'])]);

        $this->assertNull(CycleCouveuse::query()->find($lot['id'])->supprime_le);
    }

    public function test_une_pierre_tombale_pour_un_lot_inconnu_est_acceptee_sans_incubateur_ni_code_libre(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->bilanLots($a, [$this->ligneCycle(['code_incubation' => 'C-P1-2026-001'])]);
        $fantome = $this->ligneCycle([
            'code_incubation' => 'C-P1-2026-001', // déjà pris par un lot vivant
            'machine_id' => (string) Str::uuid(), // incubateur inconnu
            'supprime_le' => '2026-11-01T11:00:00.000000Z',
        ]);

        $bilan = $this->bilanLots($a, [$fantome]);

        $this->assertSame([$fantome['id']], $bilan['accepted']);
        $this->assertNotNull(CycleCouveuse::query()->find($fantome['id'])->supprime_le);
    }

    // ---------------------------------------------------------------- Droits

    public function test_les_droits_lecture_et_ecriture(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $machine = $this->machineConnue($admin);
        $this->bilanLots($admin, [$this->ligneCycle(['machine_id' => $machine])]);

        $animalier = $this->poste('animalier', 'bako');
        $ok = $this->bilanLots($animalier, [$this->ligneCycle(['code_incubation' => 'C-P2-2026-001'])]);
        $this->assertSame([], $ok['rejected'], "l'agent d'élevage écrit dans la couveuse");
        $tables = $this->avecJeton($animalier['jeton'])->getJson('/api/sync/pull')->json('tables');
        $this->assertArrayHasKey('cycle_couveuse', $tables);
        $this->assertArrayHasKey('machines_incubateur', $tables);

        foreach (['caissier' => 'amina', 'comptable' => 'cyrille'] as $role => $nom) {
            $poste = $this->poste($role, $nom);
            $refus = $this->bilanLots($poste, [$this->ligneCycle(['code_incubation' => 'C-P3-2026-001'])]);
            $this->assertSame('Droit insuffisant pour écrire dans « cycle_couveuse ».', $refus['rejected'][0]['motif'], $role);
            $refusMachine = $this->bilanMachines($poste, [$this->ligneMachine(['code' => 'INC-77'])]);
            $this->assertSame('Droit insuffisant pour écrire dans « machines_incubateur ».', $refusMachine['rejected'][0]['motif'], $role);
            $tables = $this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->json('tables');
            $this->assertArrayNotHasKey('cycle_couveuse', $tables, $role);
            $this->assertArrayNotHasKey('machines_incubateur', $tables, $role);
        }
        $this->assertSame(2, CycleCouveuse::query()->count());
    }

    // ------------------------------------------------------------ Deux postes

    public function test_un_lot_saisi_hors_ligne_atteint_un_poste_deja_a_jour(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('animalier', 'bako');
        $curseur = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('server_time');
        $this->travel(5)->seconds();
        $vieux = $this->ligneCycle([
            'updated_at' => now()->subDays(3)->format('Y-m-d\TH:i:s.u\Z'),
            'date_incubation' => now()->subDays(3)->format('Y-m-d'),
        ]);
        $this->bilanLots($a, [$vieux]);

        $recus = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull?since='.urlencode($curseur))->json('tables.cycle_couveuse');

        $this->assertSame([$vieux['id']], array_column($recus, 'id'));
    }

    public function test_deux_postes_qui_saisissent_des_mirages_differents_convergent_vers_le_dernier_ecrivain(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('animalier', 'bako');
        $lot = $this->ligneCycle(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->bilanLots($a, [$lot]);

        // Reconnexion dans le désordre : B (plus récent) d'abord, A ensuite.
        $this->bilanLots($b, [array_merge($lot, ['oeufs_blancs_j7' => 30, 'updated_at' => '2026-11-08T11:00:00.000000Z'])]);
        $this->bilanLots($a, [array_merge($lot, ['oeufs_blancs_j7' => 20, 'updated_at' => '2026-11-08T10:00:00.000000Z'])]);

        $row = CycleCouveuse::query()->find($lot['id']);
        $this->assertSame(30, $row->oeufs_blancs_j7);
        $this->assertSame($b['device'], $row->device_id);
    }

    public function test_un_rejeu_ne_duplique_rien_et_ne_touche_pas_l_instant_de_reception(): void
    {
        $a = $this->poste('admin', 'gerante');
        $lot = $this->ligneCycle();
        $this->bilanLots($a, [$lot]);
        $recu = CycleCouveuse::query()->find($lot['id'])->getRawOriginal('serveur_modifie_le');
        $this->travel(10)->seconds();

        $this->assertSame([$lot['id']], $this->bilanLots($a, [$lot])['accepted']);

        $this->assertSame(1, CycleCouveuse::query()->count());
        $this->assertSame($recu, CycleCouveuse::query()->find($lot['id'])->getRawOriginal('serveur_modifie_le'));
    }

    // ------------------------------------------- Aucun effet de bord, reset

    public function test_un_lot_n_a_aucun_effet_de_bord_sur_le_reste_du_serveur(): void
    {
        $a = $this->poste('admin', 'gerante');
        $machine = $this->machineConnue($a);
        $this->bilanLots($a, [$this->ligneCycle([
            'machine_id' => $machine, 'oeufs_couves' => 200, 'poussins_nes' => 150, 'oeufs_perdus' => 10, 'statut' => 'Éclosion Effectuée',
        ])]);

        $this->assertSame(0, Client::query()->count());
        $this->assertSame(0, \App\Models\Vente::query()->count());
        $this->assertSame(0, \App\Models\Intrant::query()->count());
        $this->assertSame(0, \App\Models\ProduitVendable::query()->count());
        $this->assertSame(0, \App\Models\MouvementProduit::query()->count());
    }

    public function test_la_remise_a_zero_efface_lots_et_incubateurs_sans_etre_bloquee(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $admin = $this->poste('admin', 'gerante');
        $machine = $this->machineConnue($admin);
        $this->bilanLots($admin, [$this->ligneCycle(['machine_id' => $machine])]);
        $avant = ParametresEntreprise::courant()->fresh()->marque_remise_a_zero;

        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/remise-a-zero', ['confirmation' => 'REMETTRE A ZERO'])->assertOk();

        $this->assertSame(0, CycleCouveuse::query()->count());
        $this->assertSame(0, MachineIncubateur::query()->count());
        $this->assertNotSame($avant, ParametresEntreprise::courant()->fresh()->marque_remise_a_zero);
    }

    public function test_un_poste_qui_ignore_la_remise_a_zero_est_refuse_en_409_et_rien_n_est_ecrit(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $admin = $this->poste('admin', 'gerante');
        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/remise-a-zero', ['confirmation' => 'REMETTRE A ZERO'])->assertOk();

        $this->pousser($admin, ['cycle_couveuse' => [$this->ligneCycle()]], 'initiale')->assertStatus(409);

        $this->assertSame(0, CycleCouveuse::query()->count());
    }
}
