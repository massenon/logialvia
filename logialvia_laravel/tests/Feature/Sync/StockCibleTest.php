<?php

namespace Tests\Feature\Sync;

use App\Livewire\Catalogue;
use App\Models\Achat;
use App\Models\EffetStock;
use App\Models\MouvementIntrant;
use App\Models\MouvementProduit;
use App\Models\Poste;
use App\Models\Vente;
use App\Services\PosteDeStock;
use App\Support\UuidDeterministe;
use App\Sync\Tables\AchatsTable;
use App\Sync\Tables\MouvementsIntrantTable;
use App\Sync\Tables\MouvementsProduitTable;
use App\Sync\Tables\VentesTable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * `47s_` — le serveur transporte `poste_cible` : colonne, validation (« poste inconnu ou révoqué »),
 * immutabilité, droits, redistribution aux postes, trace des effets (`effets_stock`).
 * Le serveur n'applique AUCUN stock : il l'enregistre et le redistribue.
 */
class StockCibleTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    private const WEB = Catalogue::POSTE_WEB;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function pousser(array $poste, array $tables)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'], 'reset_mark' => 'initiale', 'tables' => $tables,
        ]);
    }

    /** Un poste synchronisé au moins une fois. */
    private function posteSynchronise(string $role = 'admin', ?string $nom = null): array
    {
        $p = $this->poste($role, $nom);
        Poste::query()->where('device_id', $p['device'])->update(['curseur_tirage' => now('UTC')]);

        return $p;
    }

    /** @return array{0: string, 1: string} [fournisseur, code d'intrant] connus du serveur, via un poste émetteur. */
    private function socle(array $emetteur): string
    {
        $this->intrantConnu($emetteur);
        $f = $this->ligneFournisseur();
        $this->pousser($emetteur, ['fournisseurs' => [$f]])->assertOk()->assertJsonPath('fournisseurs.rejected', []);

        return $f['id'];
    }

    private function achatWeb(string $fournisseur, ?string $cible, array $surcharge = []): array
    {
        return $this->ligneAchat($fournisseur, array_merge(['reference' => 'ACH-WEB-2026-001', 'poste_cible' => $cible], $surcharge));
    }

    // ------------------------------------------------------------- schéma

    public function test_les_colonnes_et_les_tables_du_stock_cible_existent(): void
    {
        foreach (['achats', 'ventes', 'mouvements_intrant', 'mouvements_produit'] as $table) {
            $this->assertTrue(Schema::hasColumn($table, 'poste_cible'), $table);
        }
        $this->assertTrue(Schema::hasTable('effets_stock'));
        $this->assertTrue(Schema::hasTable('postes_stock_defauts'));
    }

    // ------------------------------------------------- qui peut désigner

    public function test_un_poste_ne_peut_pas_designer_un_poste_seul_le_web_le_fait(): void
    {
        $a = $this->posteSynchronise();
        $b = $this->posteSynchronise();
        $f = $this->socle($a);
        $produit = $this->produitConnu($a);

        $r = $this->pousser($a, [
            'achats' => [$this->ligneAchat($f, ['poste_cible' => $b['device']])],
            'ventes' => [$this->ligneVente($produit, ['poste_cible' => $b['device']])],
            'mouvements_produit' => [$this->ligneMouvementProduit($produit, ['poste_cible' => $b['device']])],
            'mouvements_intrant' => [$this->ligneMouvement('INT-001', ['poste_cible' => $b['device']])],
        ])->assertOk();

        foreach (['achats', 'ventes', 'mouvements_produit', 'mouvements_intrant'] as $table) {
            $this->assertSame(PosteDeStock::MOTIF_SEUL_LE_WEB, $r->json("$table.rejected.0.motif"), $table);
        }
        $this->assertSame(0, Achat::query()->count() + Vente::query()->count() + MouvementProduit::query()->count() + MouvementIntrant::query()->count());
    }

    public function test_le_web_designe_un_poste_valide_et_le_fait_le_porte_et_le_redistribue(): void
    {
        $emetteur = $this->posteSynchronise();
        $cible = $this->posteSynchronise('admin', 'cible');
        $autre = $this->posteSynchronise('admin', 'autre');
        $f = $this->socle($emetteur);
        $ligne = $this->achatWeb($f, $cible['device'], ['statut' => 'Livré']);

        $this->assertNull((new AchatsTable)->absorber(self::WEB, $ligne));

        $this->assertSame($cible['device'], Achat::query()->firstOrFail()->poste_cible);
        // Tous les postes le reçoivent, avec son poste cible : à eux de savoir s'ils sont concernés.
        foreach ([$cible, $autre] as $poste) {
            $recu = collect($this->avecJeton($poste['jeton'])->getJson('/api/sync/pull')->json('tables.achats'))->firstWhere('id', $ligne['id']);
            $this->assertSame($cible['device'], $recu['poste_cible']);
        }
    }

    public function test_poste_inconnu_revoque_ou_jamais_synchronise_est_refuse_pour_chaque_fait(): void
    {
        $emetteur = $this->posteSynchronise();
        $revoque = $this->posteSynchronise('admin', 'revoque');
        app(\App\Services\PostesService::class)->revoquer($revoque['device'], $emetteur['utilisateur']);
        $jamais = $this->poste('admin', 'jamais'); // curseur_tirage vide
        $f = $this->socle($emetteur);
        $produit = $this->produitConnu($emetteur);

        foreach ([$revoque['device'] => PosteDeStock::MOTIF_INCONNU, (string) Str::uuid() => PosteDeStock::MOTIF_INCONNU, $jamais['device'] => PosteDeStock::MOTIF_JAMAIS_SYNCHRONISE] as $cible => $motif) {
            $this->assertSame($motif, (new AchatsTable)->absorber(self::WEB, $this->achatWeb($f, $cible, ['id' => (string) Str::uuid()])));
            $this->assertSame($motif, (new VentesTable)->absorber(self::WEB, $this->ligneVente($produit, ['reference' => 'V-WEB-2026-001', 'poste_cible' => $cible])));
            $this->assertSame($motif, (new MouvementsProduitTable)->absorber(self::WEB, $this->ligneMouvementProduit($produit, ['poste_cible' => $cible])));
        }
        $this->assertSame(0, Achat::query()->count() + Vente::query()->count() + MouvementProduit::query()->count());
    }

    public function test_un_poste_dont_le_compte_ne_lit_pas_les_achats_ne_peut_pas_etre_designe_pour_une_reception(): void
    {
        $emetteur = $this->posteSynchronise();
        $caissier = $this->posteSynchronise('caissier', 'caisse'); // lit les ventes, pas les achats
        $f = $this->socle($emetteur);
        $produit = $this->produitConnu($emetteur);

        $this->assertStringContainsString('pas le droit de lire', (string) (new AchatsTable)->absorber(self::WEB, $this->achatWeb($f, $caissier['device'])));
        $this->assertNull((new VentesTable)->absorber(self::WEB, $this->ligneVente($produit, ['reference' => 'V-WEB-2026-001', 'poste_cible' => $caissier['device']])));
    }

    public function test_un_uuid_invalide_est_refuse_avec_un_message(): void
    {
        $emetteur = $this->posteSynchronise();
        $f = $this->socle($emetteur);

        $this->assertSame('Le poste de stock doit être un identifiant de poste valide.', (new AchatsTable)->absorber(self::WEB, $this->achatWeb($f, 'P2')));
    }

    // ----------------------------------------------------- immutabilité

    public function test_le_poste_d_un_achat_ne_change_plus_et_son_absence_ne_l_efface_pas(): void
    {
        $emetteur = $this->posteSynchronise();
        $p1 = $this->posteSynchronise('admin', 'un');
        $p2 = $this->posteSynchronise('admin', 'deux');
        $f = $this->socle($emetteur);
        $ligne = $this->achatWeb($f, $p1['device']);
        $this->assertNull((new AchatsTable)->absorber(self::WEB, $ligne));

        $plusTard = fn (array $s) => array_merge($ligne, $s, ['updated_at' => now()->addMinutes(5)->format('Y-m-d\TH:i:s.u\Z')]);

        $this->assertSame(PosteDeStock::MOTIF_LIEN, (new AchatsTable)->absorber(self::WEB, $plusTard(['poste_cible' => $p2['device'], 'statut' => 'Livré'])));
        $this->assertSame('Commandé', Achat::query()->firstOrFail()->statut, 'le refus ne change rien');

        // Un envoi sans poste (ancien poste, aller-retour) ne l'efface pas.
        $sans = $plusTard(['statut' => 'Livré']);
        unset($sans['poste_cible']);
        $this->assertNull((new AchatsTable)->absorber(self::WEB, $sans));
        $this->assertSame($p1['device'], Achat::query()->firstOrFail()->poste_cible);
        $this->assertSame('Livré', Achat::query()->firstOrFail()->statut);
    }

    public function test_une_commande_sans_poste_peut_en_recevoir_un_une_fois_tant_qu_elle_est_commandee(): void
    {
        $emetteur = $this->posteSynchronise();
        $p1 = $this->posteSynchronise('admin', 'un');
        $f = $this->socle($emetteur);
        // Commande saisie par un poste (aucun poste cible), puis livrée au web pour p1.
        $ligne = $this->ligneAchat($f, ['reference' => 'ACH-P1-2026-001']);
        $this->pousser($emetteur, ['achats' => [$ligne]])->assertOk()->assertJsonPath('achats.rejected', []);

        $livree = array_merge($ligne, ['statut' => 'Livré', 'poste_cible' => $p1['device'], 'updated_at' => now()->addMinute()->format('Y-m-d\TH:i:s.u\Z')]);
        $this->assertNull((new AchatsTable)->absorber(self::WEB, $livree));
        $this->assertSame($p1['device'], Achat::query()->firstOrFail()->poste_cible);

        // Une commande déjà livrée ne peut plus désigner de poste.
        $deja = $this->ligneAchat($f, ['reference' => 'ACH-P1-2026-002', 'statut' => 'Livré']);
        $this->pousser($emetteur, ['achats' => [$deja]])->assertOk();
        $tard = array_merge($deja, ['poste_cible' => $p1['device'], 'updated_at' => now()->addMinute()->format('Y-m-d\TH:i:s.u\Z')]);
        $this->assertStringContainsString('déjà livrée ou annulée', (string) (new AchatsTable)->absorber(self::WEB, $tard));
    }

    public function test_le_poste_d_une_vente_ne_change_plus_et_une_vente_sans_poste_n_en_recoit_pas(): void
    {
        $emetteur = $this->posteSynchronise();
        $p1 = $this->posteSynchronise('admin', 'un');
        $p2 = $this->posteSynchronise('admin', 'deux');
        $produit = $this->produitConnu($emetteur);
        $ligne = $this->ligneVente($produit, ['reference' => 'V-WEB-2026-001', 'poste_cible' => $p1['device']]);
        $this->assertNull((new VentesTable)->absorber(self::WEB, $ligne));
        $plusTard = fn (array $s) => array_merge($ligne, $s, ['updated_at' => now()->addMinutes(5)->format('Y-m-d\TH:i:s.u\Z')]);

        $this->assertSame(PosteDeStock::MOTIF_LIEN, (new VentesTable)->absorber(self::WEB, $plusTard(['poste_cible' => $p2['device'], 'status' => 'Annulée'])));
        $this->assertSame('Payée', Vente::query()->firstOrFail()->status);

        $annulee = $plusTard(['status' => 'Annulée']);
        unset($annulee['poste_cible']);
        $this->assertNull((new VentesTable)->absorber(self::WEB, $annulee));
        $this->assertSame($p1['device'], Vente::query()->firstOrFail()->poste_cible);

        // Vente de poste (sans poste cible) : le web ne peut pas lui en greffer un après coup.
        $de_poste = $this->ligneVente($produit, ['reference' => 'V-P1-2026-009']);
        $this->pousser($emetteur, ['ventes' => [$de_poste]])->assertOk()->assertJsonPath('ventes.rejected', []);
        $this->assertStringContainsString('ne peut plus en désigner un', (string) (new VentesTable)->absorber(self::WEB, array_merge($de_poste, [
            'poste_cible' => $p1['device'], 'updated_at' => now()->addMinute()->format('Y-m-d\TH:i:s.u\Z'),
        ])));
    }

    public function test_les_lignes_du_journal_d_intrants_portent_le_poste_sans_controle_de_revocation(): void
    {
        $emetteur = $this->posteSynchronise();
        $p1 = $this->posteSynchronise('admin', 'un');
        $this->intrantConnu($emetteur);
        app(\App\Services\PostesService::class)->revoquer($p1['device'], $emetteur['utilisateur']);

        // Annuler une commande dont le poste a été révoqué reste possible : le journal l'enregistre.
        $m = $this->ligneMouvement('INT-001', ['poste_cible' => $p1['device'], 'type' => 'Sortie', 'quantite' => -5]);
        $this->assertNull((new MouvementsIntrantTable)->absorber(self::WEB, $m));
        $this->assertSame($p1['device'], MouvementIntrant::query()->firstOrFail()->poste_cible);
    }

    // ------------------------------------------------------- effets_stock

    private function ligneEffet(string $faitId, string $nature = 'vente', array $surcharge = []): array
    {
        return array_merge([
            'id' => UuidDeterministe::effetStock($faitId, $nature), 'fait_type' => 'vente', 'fait_id' => $faitId, 'nature' => $nature,
            'reference' => 'V-WEB-2026-001', 'libelle' => 'Vente V-WEB-2026-001 reçue du web : Goliath −3 (stock 7)', 'etat' => 'applique',
            'avertissement' => null, 'applique_le' => now('UTC')->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    public function test_le_poste_designe_remonte_sa_trace_et_les_autres_postes_la_recoivent(): void
    {
        $cible = $this->posteSynchronise('caissier', 'caisse');
        $autre = $this->posteSynchronise('admin', 'autre');
        $fait = (string) Str::uuid();
        $effet = $this->ligneEffet($fait, 'vente', ['etat' => 'avertissement', 'avertissement' => 'Stock insuffisant au poste P1 : « Goliath » — 3 demandés, 1 disponibles ; stock ramené à 0']);

        // Écriture ouverte à tout compte : un caissier (view/manage-ventes, sans manage-stocks) remonte sa trace.
        $this->pousser($cible, ['effets_stock' => [$effet]])->assertOk()->assertJsonPath('effets_stock.accepted.0', $effet['id'])->assertJsonPath('effets_stock.rejected', []);
        $this->pousser($cible, ['effets_stock' => [$effet]])->assertOk()->assertJsonPath('effets_stock.rejected', []); // rejeu

        $this->assertSame(1, EffetStock::query()->count());
        $recu = collect($this->avecJeton($autre['jeton'])->getJson('/api/sync/pull')->json('tables.effets_stock'))->firstWhere('id', $effet['id']);
        $this->assertSame($cible['device'], $recu['device_id']);
        $this->assertSame('avertissement', $recu['etat']);
        $this->assertStringContainsString('Stock insuffisant', $recu['avertissement']);
    }

    public function test_une_trace_forgee_ou_incoherente_est_refusee_avec_son_motif(): void
    {
        $p = $this->posteSynchronise();
        $fait = (string) Str::uuid();

        $r = $this->pousser($p, ['effets_stock' => [
            $this->ligneEffet($fait, 'vente', ['id' => (string) Str::uuid()]),
            $this->ligneEffet($fait, 'vente', ['nature' => 'magie']),
            $this->ligneEffet($fait, 'vente', ['etat' => 'peut-etre']),
            $this->ligneEffet($fait, 'vente', ['fait_type' => 'devis']),
        ]])->assertOk();

        $this->assertCount(4, $r->json('effets_stock.rejected'));
        $this->assertSame(0, EffetStock::query()->count());
    }

    public function test_la_remise_a_zero_efface_aussi_les_traces_d_effets(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $admin = $this->posteSynchronise('admin', 'gerante');
        $this->pousser($admin, ['effets_stock' => [$this->ligneEffet((string) Str::uuid())]])->assertOk();
        $this->assertSame(1, EffetStock::query()->count());

        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/remise-a-zero', ['confirmation' => 'REMETTRE A ZERO'])->assertOk();

        $this->assertSame(0, EffetStock::query()->count());
    }

    public function test_un_poste_sans_droit_de_lecture_ne_recoit_pas_les_traces(): void
    {
        $animalier = $this->posteSynchronise('animalier', 'eleveur'); // ni ventes, ni achats, ni stocks
        $admin = $this->posteSynchronise('admin', 'gerante');
        $this->pousser($admin, ['effets_stock' => [$this->ligneEffet((string) Str::uuid())]])->assertOk();

        $tables = $this->avecJeton($animalier['jeton'])->getJson('/api/sync/pull')->json('tables');
        $this->assertArrayNotHasKey('effets_stock', $tables);
    }
}
