<?php

namespace Tests\Feature\Sync;

use App\Livewire\Catalogue;
use App\Models\Facture;
use App\Sync\Tables\FacturesTable;
use Carbon\CarbonImmutable;
use Database\Seeders\GroupesTaxeSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * `47a2_` — facture émise au WEB : n'importe quel poste appairé (droit `manage-facturation`) peut la
 * transmettre, après l'avoir RÉSERVÉE ; un seul poste à la fois ; seul le détenteur envoie le statut.
 */
class FacturesWebTransmissionTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
        $this->seed(GroupesTaxeSeeder::class);
    }

    /** Une facture émise par le web, comme le fera le composant. */
    private function factureWeb(array $surcharge = []): Facture
    {
        $ligne = $this->ligneFacture(array_merge(['reference' => 'FV-WEB-2026-001'], $surcharge));
        $this->assertNull((new FacturesTable)->absorber(Catalogue::POSTE_WEB, $ligne));

        return Facture::query()->findOrFail($ligne['id']);
    }

    private function reserver(array $poste, string $factureId, ?string $device = null)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/factures/reserver', [
            'device_id' => $device ?? $poste['device'],
            'facture_id' => $factureId,
        ]);
    }

    private function pousser(array $poste, array $factures)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => 'initiale',
            'tables' => ['factures' => $factures],
        ]);
    }

    private function normalisee(Facture $f, array $surcharge = []): array
    {
        return $this->ligneFactureNormalisee(array_merge([
            'id' => $f->id,
            'reference' => $f->reference,
            'lignes' => $f->lignes->map(fn ($l) => $l->attributesToArray())->all(),
            'updated_at' => now()->addMinute()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge));
    }

    private function comptable(string $nom = 'compta'): array
    {
        return $this->poste('comptable', $nom);
    }

    // ------------------------------------------------------------- Émission web

    public function test_une_reference_web_est_valide_et_globale(): void
    {
        $f = $this->factureWeb();
        $this->assertSame(Catalogue::POSTE_WEB, $f->device_id);
        $this->assertSame('', $f->portee_reference);
        $this->assertSame('a_transmettre', $f->statut);
        // Globale : un poste ne peut pas reprendre la même référence.
        $a = $this->comptable();
        $bilan = $this->pousser($a, [$this->ligneFacture(['reference' => 'FV-WEB-2026-001'])])->assertOk()->json('factures');
        $this->assertSame(FacturesTable::MOTIF_REFERENCE, $bilan['rejected'][0]['motif']);
    }

    public function test_avoir_web_sur_une_facture_web_et_regex_stricte(): void
    {
        $f = $this->factureWeb();
        $avoir = $this->ligneFacture(['reference' => 'FA-WEB-2026-001', 'type' => 'FA', 'origine_ref' => $f->reference, 'motif' => 'Retour']);
        $this->assertNull((new FacturesTable)->absorber(Catalogue::POSTE_WEB, $avoir));
        $this->assertNotNull((new FacturesTable)->absorber(Catalogue::POSTE_WEB, $this->ligneFacture(['reference' => 'FV-WEBX-2026-001'])));
        $this->assertNotNull((new FacturesTable)->absorber(Catalogue::POSTE_WEB, $this->ligneFacture(['reference' => 'FV-WEB-26-001'])));
    }

    public function test_les_colonnes_du_verrou_ne_sont_jamais_servies(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable();
        $this->reserver($a, $f->id)->assertOk();
        $recue = collect($this->avecJeton($a['jeton'])->getJson('/api/sync/pull')->json('tables.factures'))->firstWhere('id', $f->id);
        $this->assertArrayNotHasKey('transmission_poste', $recue);
        $this->assertArrayNotHasKey('transmission_reservee_jusqua', $recue);
        $this->assertSame(Catalogue::POSTE_WEB, $recue['device_id']);
    }

    // -------------------------------------------------------------- Réservation

    public function test_un_poste_avec_manage_facturation_reserve(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable();
        $r = $this->reserver($a, $f->id)->assertOk();
        $this->assertSame('Transmission réservée.', $r->json('message'));
        $f->refresh();
        $this->assertSame($a['device'], $f->transmission_poste);
        $this->assertTrue($f->transmission_reservee_jusqua->greaterThan(now()->addMinutes(FacturesTable::DUREE_RESERVATION_MINUTES - 1)));
        $this->assertTrue($f->transmission_reservee_jusqua->lessThanOrEqualTo(now()->addMinutes(FacturesTable::DUREE_RESERVATION_MINUTES + 1)));
        $this->assertSame('a_transmettre', $f->statut, 'réserver ne change aucun statut');
    }

    public function test_sans_manage_facturation_pas_de_reservation(): void
    {
        $f = $this->factureWeb();
        $caissier = $this->poste('caissier', 'caisse');      // view-facturation seulement
        $this->reserver($caissier, $f->id)->assertForbidden();
        $animalier = $this->poste('animalier', 'ferme');
        $this->reserver($animalier, $f->id)->assertForbidden();
        $this->assertNull($f->fresh()->transmission_poste);
    }

    public function test_un_second_poste_est_refuse_tant_que_la_reservation_court(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable('compta1');
        $b = $this->comptable('compta2');
        $this->reserver($a, $f->id)->assertOk();

        $r = $this->reserver($b, $f->id)->assertStatus(409);
        $this->assertStringContainsString('en cours de transmission', $r->json('message'));
        $this->assertSame($a['device'], $f->fresh()->transmission_poste, 'le détenteur ne change pas');
    }

    public function test_le_detenteur_peut_reserver_de_nouveau(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable();
        $this->reserver($a, $f->id)->assertOk();
        $this->reserver($a, $f->id)->assertOk();
    }

    public function test_une_reservation_expiree_peut_etre_reprise(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable('compta1');
        $b = $this->comptable('compta2');
        $this->reserver($a, $f->id)->assertOk();
        Facture::query()->whereKey($f->id)->update(['transmission_reservee_jusqua' => now()->subMinute()->format('Y-m-d H:i:s.u')]);

        $this->reserver($b, $f->id)->assertOk();
        $this->assertSame($b['device'], $f->fresh()->transmission_poste);
        // L'ancien détenteur n'a plus la main.
        $bilan = $this->pousser($a, [$this->normalisee($f)])->assertOk()->json('factures');
        $this->assertSame(FacturesTable::MOTIF_RESERVATION, $bilan['rejected'][0]['motif']);
    }

    public function test_une_facture_emise_par_un_poste_ne_se_reserve_pas(): void
    {
        $a = $this->comptable('compta1');
        $b = $this->comptable('compta2');
        $f = $this->ligneFacture();
        $this->pousser($a, [$f])->assertOk();
        $this->reserver($b, $f['id'])->assertStatus(422);
        $this->assertNull(Facture::query()->find($f['id'])->transmission_poste);
    }

    public function test_une_facture_normalisee_ne_se_reserve_plus_et_une_inconnue_est_404(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable();
        $this->reserver($a, $f->id)->assertOk();
        $this->pousser($a, [$this->normalisee($f)])->assertOk();

        $this->assertStringContainsString('déjà normalisée', $this->reserver($this->comptable('compta2'), $f->id)->assertStatus(409)->json('message'));
        $this->reserver($a, (string) Str::uuid())->assertNotFound();
    }

    public function test_validation_et_poste_du_jeton(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable();
        $this->avecJeton($a['jeton'])->postJson('/api/sync/factures/reserver', ['device_id' => $a['device'], 'facture_id' => 'x'])->assertStatus(422);
        $this->avecJeton($a['jeton'])->postJson('/api/sync/factures/reserver', ['device_id' => $a['device']])->assertStatus(422);
        // Un poste ne réserve pas au nom d'un autre.
        $this->reserver($a, $f->id, (string) Str::uuid())->assertForbidden();
        $this->assertNull($f->fresh()->transmission_poste);
        // Sans jeton.
        $this->app['auth']->forgetGuards();
        $this->flushHeaders();
        $this->postJson('/api/sync/factures/reserver', ['device_id' => $a['device'], 'facture_id' => $f->id])->assertUnauthorized();
    }

    // ------------------------------------------------- Envoi du statut (le verrou)

    public function test_sans_reservation_la_normalisation_est_refusee(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable();
        $bilan = $this->pousser($a, [$this->normalisee($f)])->assertOk()->json('factures');

        $this->assertSame(FacturesTable::MOTIF_RESERVATION, $bilan['rejected'][0]['motif']);
        $this->assertSame('a_transmettre', $f->fresh()->statut);
        $this->assertNull($f->fresh()->code_mecef);
    }

    public function test_le_detenteur_envoie_sa_normalisation_l_emetteur_reste_le_web(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable();
        $this->reserver($a, $f->id)->assertOk();
        $bilan = $this->pousser($a, [$this->normalisee($f, ['code_mecef' => 'CODE-WEB'])])->assertOk()->json('factures');

        $this->assertSame([$f->id], $bilan['accepted']);
        $f->refresh();
        $this->assertSame('normalisee', $f->statut);
        $this->assertSame('CODE-WEB', $f->code_mecef);
        $this->assertSame(Catalogue::POSTE_WEB, $f->device_id);
    }

    public function test_un_autre_poste_ne_peut_pas_envoyer_pendant_la_reservation(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable('compta1');
        $b = $this->comptable('compta2');
        $this->reserver($a, $f->id)->assertOk();
        $bilan = $this->pousser($b, [$this->normalisee($f)])->assertOk()->json('factures');
        $this->assertSame(FacturesTable::MOTIF_RESERVATION, $bilan['rejected'][0]['motif']);
        $this->assertSame('a_transmettre', $f->fresh()->statut);
    }

    public function test_un_rejet_libere_la_reservation_un_autre_poste_peut_retransmettre(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable('compta1');
        $b = $this->comptable('compta2');
        $this->reserver($a, $f->id)->assertOk();
        $rejet = $this->ligneFacture([
            'id' => $f->id, 'reference' => $f->reference, 'statut' => 'rejetee', 'erreur_transmission' => 'IFU invalide',
            'lignes' => $f->lignes->map(fn ($l) => $l->attributesToArray())->all(),
            'updated_at' => now()->addMinute()->format('Y-m-d\TH:i:s.u\Z'),
        ]);
        $this->assertSame([$f->id], $this->pousser($a, [$rejet])->assertOk()->json('factures.accepted'));
        $this->assertNull($f->fresh()->transmission_poste);

        $this->reserver($b, $f->id)->assertOk();
        $this->assertSame($b['device'], $f->fresh()->transmission_poste);
    }

    public function test_la_double_normalisation_reste_refusee_meme_du_detenteur(): void
    {
        $f = $this->factureWeb();
        $a = $this->comptable();
        $this->reserver($a, $f->id)->assertOk();
        $this->pousser($a, [$this->normalisee($f, ['code_mecef' => 'CODE-1'])])->assertOk();
        $bilan = $this->pousser($a, [$this->normalisee($f, ['code_mecef' => 'CODE-2'])])->assertOk()->json('factures');
        $this->assertStringContainsString('déjà normalisée', $bilan['rejected'][0]['motif']);
        $this->assertSame('CODE-1', $f->fresh()->code_mecef);
    }

    public function test_une_facture_de_poste_n_est_pas_soumise_au_verrou(): void
    {
        $a = $this->comptable();
        $f = $this->ligneFacture();
        $this->pousser($a, [$f])->assertOk();
        $this->pousser($a, [$this->ligneFactureNormalisee(['id' => $f['id'], 'lignes' => $f['lignes'], 'updated_at' => now()->addMinute()->format('Y-m-d\TH:i:s.u\Z')])])->assertOk();
        $this->assertSame('normalisee', Facture::query()->find($f['id'])->statut);
    }

    // ------------------------------------------------------ Une facture par vente

    public function test_une_facture_web_et_une_facture_de_poste_ne_facturent_pas_deux_fois_la_meme_vente(): void
    {
        $this->assertNull((new FacturesTable)->absorber(Catalogue::POSTE_WEB, $this->ligneFacture([
            'reference' => 'FV-WEB-2026-001', 'vente_ref' => 'V-P1-2026-001',
        ])));
        $a = $this->comptable();
        $bilan = $this->pousser($a, [$this->ligneFacture(['reference' => 'FV-P1-2026-001', 'vente_ref' => 'V-P1-2026-001'])])->assertOk()->json('factures');
        $this->assertStringContainsString('porte déjà la facture FV-WEB-2026-001', $bilan['rejected'][0]['motif']);
    }

    public function test_vente_sans_code_de_poste_la_facture_web_bloque_la_facture_du_poste(): void
    {
        $this->assertNull((new FacturesTable)->absorber(Catalogue::POSTE_WEB, $this->ligneFacture([
            'reference' => 'FV-WEB-2026-001', 'vente_ref' => 'V-2026-001',
        ])));
        $a = $this->comptable();
        $bilan = $this->pousser($a, [$this->ligneFacture(['reference' => 'FV-2026-001', 'vente_ref' => 'V-2026-001'])])->assertOk()->json('factures');
        $this->assertStringContainsString('porte déjà la facture FV-WEB-2026-001', $bilan['rejected'][0]['motif']);
    }

    // ------------------------------------------------------------------ Secrets

    public function test_le_serveur_ne_contacte_jamais_la_dgi_meme_pour_une_reservation(): void
    {
        Http::fake();
        $f = $this->factureWeb();
        $a = $this->comptable();
        $this->reserver($a, $f->id)->assertOk();
        $this->pousser($a, [$this->normalisee($f)])->assertOk();
        Http::assertNothingSent();
        $this->assertInstanceOf(CarbonImmutable::class, CarbonImmutable::now());
    }
}
