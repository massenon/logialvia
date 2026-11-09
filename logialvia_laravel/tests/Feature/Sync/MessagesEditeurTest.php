<?php

namespace Tests\Feature\Sync;

use App\Models\MessageEditeur;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** Messages a l'editeur (doc 47u §4, poste v45) : fait ouvert a tout compte, pierre tombale, aucun effet de bord. */
class MessagesEditeurTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function ligne(array $s = []): array
    {
        return array_merge([
            'id' => (string) Str::uuid(), 'horodatage' => '2026-11-01T09:00:00.000000Z', 'type' => 'question', 'sujet' => 'Une question',
            'message' => 'Comment faire ?', 'etapes' => null, 'auteur' => 'Awa (awa) — Comptable', 'statut' => 'En attente',
            'supprime_le' => null, 'updated_at' => '2026-11-01T09:00:00.000000Z',
        ], $s);
    }

    private function bilan(array $poste, array $lignes): array
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'], 'reset_mark' => 'initiale', 'tables' => ['messages_editeur' => $lignes],
        ])->assertOk()->json('messages_editeur');
    }

    public function test_un_message_ecrit_au_poste_redescend_vers_tous_les_roles(): void
    {
        $a = $this->poste('comptable', 'awa');
        $ligne = $this->ligne();
        $this->assertSame([$ligne['id']], $this->bilan($a, [$ligne])['accepted']);

        foreach (['caissier', 'animalier', 'admin'] as $role) {
            $b = $this->poste($role, 'p'.$role);
            $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.messages_editeur'))->firstWhere('id', $ligne['id']);
            $this->assertSame('Une question', $recu['sujet'], "lisible par $role");
            $this->assertSame($a['device'], $recu['device_id']);
        }
    }

    public function test_un_caissier_peut_en_ecrire(): void
    {
        $a = $this->poste('caissier', 'caisse');
        $this->assertSame([], $this->bilan($a, [$this->ligne()])['rejected']);
        $this->assertSame(1, MessageEditeur::query()->count());
    }

    public static function lignesInvalides(): array
    {
        return [
            'sans objet' => [['sujet' => ' '], "L'objet est obligatoire."],
            'sans message' => [['message' => ''], 'Le message est obligatoire.'],
            'type inconnu' => [['type' => 'plainte'], 'Le type du message est inconnu (question ou problème).'],
            'statut inconnu' => [['statut' => 'Lu'], 'Le statut du message est inconnu.'],
            'sans date' => [['horodatage' => null], 'La date du message est obligatoire.'],
            'date invalide' => [['horodatage' => 'hier'], 'La date du message est invalide.'],
            'identifiant invalide' => [['id' => 'x'], "L'identifiant de la ligne doit être un UUID."],
            'sans instant de saisie' => [['updated_at' => null], 'La date de saisie de la ligne est obligatoire.'],
        ];
    }

    /** @dataProvider lignesInvalides */
    public function test_une_ligne_invalide_est_refusee_avec_son_motif(array $surcharge, string $motif): void
    {
        $a = $this->poste('comptable', 'awa');

        $bilan = $this->bilan($a, [$this->ligne($surcharge)]);

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, MessageEditeur::query()->count());
    }

    public function test_dernier_ecrivain_gagne_marquer_transmis_puis_un_rejeu_ancien(): void
    {
        $a = $this->poste('comptable', 'awa');
        $l = $this->ligne();
        $this->bilan($a, [$l]);
        $this->bilan($a, [array_merge($l, ['statut' => 'Transmis', 'updated_at' => '2026-11-02T09:00:00.000000Z'])]);
        $this->assertSame('Transmis', MessageEditeur::query()->first()->statut);

        // Un rejeu plus ancien est accepte sans rien changer.
        $this->assertSame([], $this->bilan($a, [$l])['rejected']);
        $this->assertSame('Transmis', MessageEditeur::query()->first()->statut);
    }

    public function test_la_suppression_est_une_pierre_tombale_redistribuee(): void
    {
        $a = $this->poste('comptable', 'awa');
        $b = $this->poste('admin', 'gerante');
        $l = $this->ligne();
        $this->bilan($a, [$l]);
        $this->bilan($a, [array_merge($l, ['supprime_le' => '2026-11-02T09:00:00.000000Z', 'updated_at' => '2026-11-02T09:00:00.000000Z'])]);

        $this->assertNotNull(MessageEditeur::query()->find($l['id'])->supprime_le, 'jamais d\'effacement');
        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.messages_editeur'))->firstWhere('id', $l['id']);
        $this->assertNotNull($recu['supprime_le']);
    }

    public function test_un_visiteur_sans_jeton_est_refuse(): void
    {
        $this->postJson('/api/sync/push', ['device_id' => (string) Str::uuid(), 'tables' => ['messages_editeur' => []]])->assertUnauthorized();
    }
}
