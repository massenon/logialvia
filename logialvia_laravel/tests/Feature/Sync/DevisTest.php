<?php

namespace Tests\Feature\Sync;

use App\Livewire\Catalogue;
use App\Models\Devis;
use App\Sync\Tables\DevisTable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** `47a2_` — devis de prestations : référence officielle, devis accepté figé, pierre tombale, droits. */
class DevisTest extends TestCase
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
            'id' => (string) Str::uuid(),
            'reference' => 'DV-P1-2026-001',
            'client' => 'DOSSOU',
            'objet' => 'Construction d\'un poulailler',
            'montant_estime' => 150000,
            'validite_jours' => 15,
            'date_emission' => '2026-11-09T08:00:00.000000Z',
            'statut' => 'emis',
            'supprime_le' => null,
            'updated_at' => '2026-11-09T09:00:00.000000Z',
        ], $s);
    }

    private function pousser(array $poste, array $lignes)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => 'initiale',
            'tables' => ['devis' => $lignes],
        ]);
    }

    private function bilan($reponse): array
    {
        return $reponse->assertOk()->json('devis');
    }

    private function ecrivain(): array
    {
        return $this->poste('caissier', 'caisse'.Str::random(3));
    }

    public function test_un_devis_est_enregistre_avec_son_poste_et_servi_aux_autres(): void
    {
        $a = $this->ecrivain();
        $b = $this->poste('comptable', 'compta');
        $l = $this->ligne();

        $this->assertSame([$l['id']], $this->bilan($this->pousser($a, [$l]))['accepted']);
        $d = Devis::query()->find($l['id']);
        $this->assertSame($a['device'], $d->device_id);
        $this->assertSame('DV-P1-2026-001', $d->reference);
        $this->assertSame(150000.0, $d->montant_estime);

        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.devis'))->firstWhere('id', $l['id']);
        $this->assertEqualsCanonicalizing([
            'id', 'device_id', 'reference', 'client', 'objet', 'montant_estime', 'validite_jours', 'date_emission',
            'statut', 'supprime_le', 'updated_at', 'serveur_modifie_le',
        ], array_keys($recu), 'colonnes servies : liste fermée, pas de portee_reference');
    }

    public function test_un_rejeu_est_accepte_sans_rien_changer(): void
    {
        $a = $this->ecrivain();
        $l = $this->ligne();
        $this->pousser($a, [$l])->assertOk();
        $avant = Devis::query()->find($l['id'])->serveur_modifie_le;

        $this->assertSame([$l['id']], $this->bilan($this->pousser($a, [$l]))['accepted']);
        $this->assertEquals($avant, Devis::query()->find($l['id'])->serveur_modifie_le);
        $this->assertSame(1, Devis::query()->count());
    }

    public function test_dernier_ecrivain_gagne_une_saisie_plus_ancienne_est_sans_effet(): void
    {
        $a = $this->ecrivain();
        $l = $this->ligne();
        $this->pousser($a, [$l])->assertOk();

        $this->pousser($a, [array_merge($l, ['client' => 'ANCIEN', 'updated_at' => '2026-11-09T07:00:00.000000Z'])])->assertOk();
        $this->assertSame('DOSSOU', Devis::query()->find($l['id'])->client);

        $this->pousser($a, [array_merge($l, ['client' => 'RECENT', 'updated_at' => '2026-11-09T10:00:00.000000Z'])])->assertOk();
        $this->assertSame('RECENT', Devis::query()->find($l['id'])->client);
    }

    public function test_la_reference_est_unique_globalement_quand_elle_porte_un_code(): void
    {
        $a = $this->ecrivain();
        $b = $this->ecrivain();
        $this->pousser($a, [$this->ligne()])->assertOk();

        $bilan = $this->bilan($this->pousser($b, [$this->ligne()]));
        $this->assertSame(DevisTable::MOTIF_REFERENCE, $bilan['rejected'][0]['motif']);
        $this->assertSame(1, Devis::query()->count());

        $web = $this->ligne(['reference' => 'DV-WEB-2026-001']);
        $this->assertCount(1, $this->bilan($this->pousser($a, [$web]))['accepted']);
        $this->assertCount(1, $this->bilan($this->pousser($b, [$this->ligne(['reference' => 'DV-WEB-2026-001'])]))['rejected']);
    }

    public function test_une_reference_sans_code_est_propre_a_chaque_poste(): void
    {
        $a = $this->ecrivain();
        $b = $this->ecrivain();
        $this->assertCount(1, $this->bilan($this->pousser($a, [$this->ligne(['reference' => 'DV-2026-001'])]))['accepted']);
        $this->assertCount(1, $this->bilan($this->pousser($b, [$this->ligne(['reference' => 'DV-2026-001'])]))['accepted']);
        $this->assertCount(1, $this->bilan($this->pousser($a, [$this->ligne(['reference' => 'DV-2026-001'])]))['rejected']);
        $this->assertSame(2, Devis::query()->count());
    }

    public function test_la_reference_d_un_devis_ne_change_jamais(): void
    {
        $a = $this->ecrivain();
        $l = $this->ligne();
        $this->pousser($a, [$l])->assertOk();

        $bilan = $this->bilan($this->pousser($a, [array_merge($l, ['reference' => 'DV-P1-2026-002', 'updated_at' => '2026-11-09T11:00:00.000000Z'])]));
        $this->assertStringContainsString('ne change jamais', $bilan['rejected'][0]['motif']);
        $this->assertSame('DV-P1-2026-001', Devis::query()->find($l['id'])->reference);
    }

    public function test_un_devis_accepte_est_fige_mais_son_statut_se_corrige(): void
    {
        $a = $this->ecrivain();
        $l = $this->ligne();
        $this->pousser($a, [$l])->assertOk();
        $this->pousser($a, [array_merge($l, ['statut' => 'accepte', 'updated_at' => '2026-11-09T10:00:00.000000Z'])])->assertOk();

        // Contenu modifié : refusé.
        $bilan = $this->bilan($this->pousser($a, [array_merge($l, ['statut' => 'accepte', 'montant_estime' => 1, 'updated_at' => '2026-11-09T11:00:00.000000Z'])]));
        $this->assertSame(DevisTable::MOTIF_FIGE, $bilan['rejected'][0]['motif']);
        // Supprimé : refusé.
        $bilan = $this->bilan($this->pousser($a, [array_merge($l, ['statut' => 'accepte', 'supprime_le' => '2026-11-09T11:00:00.000000Z', 'updated_at' => '2026-11-09T11:00:00.000000Z'])]));
        $this->assertSame(DevisTable::MOTIF_FIGE, $bilan['rejected'][0]['motif']);
        $d = Devis::query()->find($l['id']);
        $this->assertSame(150000.0, $d->montant_estime);
        $this->assertNull($d->supprime_le);

        // Statut seul : corrigé.
        $this->pousser($a, [array_merge($l, ['statut' => 'refuse', 'updated_at' => '2026-11-09T12:00:00.000000Z'])])->assertOk();
        $this->assertSame('refuse', Devis::query()->find($l['id'])->statut);
    }

    public function test_la_pierre_tombale_cache_le_devis_mais_garde_la_ligne_et_le_numero(): void
    {
        $a = $this->ecrivain();
        $l = $this->ligne();
        $this->pousser($a, [$l])->assertOk();
        $this->pousser($a, [array_merge($l, ['supprime_le' => '2026-11-09T11:00:00.000000Z', 'updated_at' => '2026-11-09T11:00:00.000000Z'])])->assertOk();

        $this->assertNotNull(Devis::query()->find($l['id'])->supprime_le);
        $recu = collect($this->avecJeton($a['jeton'])->getJson('/api/sync/pull')->json('tables.devis'))->firstWhere('id', $l['id']);
        $this->assertNotNull($recu['supprime_le'], 'la pierre tombale se propage');
        // Le numéro reste pris.
        $b = $this->ecrivain();
        $this->assertCount(1, $this->bilan($this->pousser($b, [$this->ligne()]))['rejected']);
    }

    public function test_validation_stricte_chaque_regle_refuse_avec_son_motif(): void
    {
        $a = $this->ecrivain();
        $cas = [
            'reference' => [['reference' => 'DV-2026'], 'référence'],
            'type de pièce' => [['reference' => 'FV-P1-2026-001'], 'référence'],
            'client' => [['client' => ''], 'client'],
            'objet' => [['objet' => ''], 'objet'],
            'montant nul' => [['montant_estime' => 0], 'supérieur à 0'],
            'montant négatif' => [['montant_estime' => -5], 'supérieur à 0'],
            'montant texte' => [['montant_estime' => 'beaucoup'], 'montant'],
            'validité 0' => [['validite_jours' => 0], 'au moins 1 jour'],
            'validité décimale' => [['validite_jours' => 1.5], 'entier'],
            'validité énorme' => [['validite_jours' => 99999], '3650'],
            'date' => [['date_emission' => 'demain-ish'], 'date'],
            'statut' => [['statut' => 'expire'], 'statut'],
            'id' => [['id' => 'pas-un-uuid'], 'UUID'],
        ];
        foreach ($cas as $nom => [$surcharge, $extrait]) {
            $bilan = $this->bilan($this->pousser($a, [$this->ligne($surcharge)]));
            $this->assertCount(1, $bilan['rejected'], $nom);
            $this->assertStringContainsStringIgnoringCase($extrait, $bilan['rejected'][0]['motif'], $nom);
        }
        $this->assertSame(0, Devis::query()->count());
    }

    public function test_les_droits_lecture_view_ventes_ecriture_manage_ventes(): void
    {
        $animalier = $this->poste('animalier', 'ferme');
        $this->pousser($animalier, [$this->ligne()])->assertOk();
        $this->assertSame(0, Devis::query()->count(), 'sans manage-ventes, rien n\'est écrit');
        $lu = $this->avecJeton($animalier['jeton'])->getJson('/api/sync/pull')->json('tables');
        $this->assertArrayNotHasKey('devis', $lu, 'sans view-ventes, rien n\'est servi');

        $caissier = $this->ecrivain();
        $this->assertCount(1, $this->bilan($this->pousser($caissier, [$this->ligne()]))['accepted']);
        $comptable = $this->poste('comptable', 'compta');
        $this->assertArrayHasKey('devis', $this->avecJeton($comptable['jeton'])->getJson('/api/sync/pull')->json('tables'));
        // Le comptable lit (view-ventes) mais n'écrit pas (pas de manage-ventes).
        $bilan = $this->bilan($this->pousser($comptable, [$this->ligne(['reference' => 'DV-P3-2026-001'])]));
        $this->assertSame([], $bilan['accepted']);
    }

    public function test_un_devis_web_est_ecrit_par_le_poste_web_et_sa_portee_est_globale(): void
    {
        $motif = (new DevisTable)->absorber(Catalogue::POSTE_WEB, $this->ligne(['reference' => 'DV-WEB-2026-001']));
        $this->assertNull($motif);
        $d = Devis::query()->firstOrFail();
        $this->assertSame(Catalogue::POSTE_WEB, $d->device_id);
        $this->assertSame('', $d->portee_reference);
    }
}
