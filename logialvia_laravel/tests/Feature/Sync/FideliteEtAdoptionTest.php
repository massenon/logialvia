<?php

namespace Tests\Feature\Sync;

use App\Models\Bande;
use App\Models\Intrant;
use App\Models\NoteAnnexe;
use App\Models\PieceComptable;
use App\Models\ProduitVendable;
use App\Support\UuidDeterministe;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * 47h — trouvailles de l'essai contre le VRAI serveur.
 *
 *  D1 : l'adoption initiale (instant ancien) ne remplace jamais une decision ;
 *  D2 : ce que le poste envoie est conserve OCTET POUR OCTET (ni rognage, ni « vide = null ») ;
 *  D3 : le contrat de l'equilibre d'une piece de vente a livraison facturee.
 */
class FideliteEtAdoptionTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    private const ADOPTION = '2000-01-01T00:00:00.000Z';

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
        $this->amorcerComptabilite();
    }

    private function demander(array $poste, string $type, array $donnees, string $saisi)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/demandes', [
            'device_id' => $poste['device'],
            'demandes' => [[
                'id' => (string) Str::uuid(),
                'type' => $type,
                'saisi_le' => $saisi,
                'donnees' => $donnees,
            ]],
        ]);
    }

    // ------------------------------------------------------------------ D1

    public function test_l_adoption_d_un_produit_deja_decide_ne_change_rien_et_n_ecrase_pas_la_decision(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'seconde');
        $produit = $this->ligneProduit(['price' => 25000]);
        $this->demander($a, 'produit_vendable', $produit, '2026-11-01T10:00:00.000Z')->assertJsonPath('rejected', []);
        $this->demander($a, 'produit_vendable', array_merge($produit, ['price' => 27000]), '2026-11-05T10:00:00.000Z')
            ->assertJsonPath('rejected', []);

        // Le semis du second poste (prix d'origine) arrive daté de l'adoption : refusé, pas appliqué.
        $this->demander($b, 'produit_vendable', $produit, self::ADOPTION)
            ->assertJsonPath('rejected.0.motif', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.');

        $this->assertSame(27000.0, ProduitVendable::query()->find($produit['id'])->price);
    }

    public function test_l_adoption_d_une_ligne_inconnue_la_cree_puis_une_vraie_decision_la_modifie(): void
    {
        $a = $this->poste('admin', 'gerante');
        $produit = $this->ligneProduit(['price' => 25000]);

        $this->demander($a, 'produit_vendable', $produit, self::ADOPTION)->assertJsonPath('rejected', []);
        $this->assertSame(25000.0, ProduitVendable::query()->find($produit['id'])->price);

        $this->demander($a, 'produit_vendable', array_merge($produit, ['price' => 26000]), now()->format('Y-m-d\TH:i:s.u\Z'))
            ->assertJsonPath('rejected', []);
        $this->assertSame(26000.0, ProduitVendable::query()->find($produit['id'])->price);
    }

    public function test_l_adoption_d_un_intrant_deja_modifie_est_refusee_sans_rien_changer(): void
    {
        $a = $this->poste('admin', 'gerante');
        $intrant = ['code' => 'INT-001', 'name' => 'Maïs', 'cat' => 'Intrants Provende', 'unit' => 'kg', 'threshold' => 20];
        $this->demander($a, 'intrant', $intrant, self::ADOPTION)->assertJsonPath('rejected', []);
        $this->demander($a, 'intrant', array_merge($intrant, ['threshold' => 45]), now()->format('Y-m-d\TH:i:s.u\Z'))
            ->assertJsonPath('rejected', []);

        $this->demander($a, 'intrant', $intrant, self::ADOPTION)
            ->assertJsonPath('rejected.0.motif', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.');

        $this->assertSame(45, Intrant::query()->find('INT-001')->threshold);
    }

    public function test_l_adoption_d_un_bareme_deja_corrige_est_refusee_sans_rien_changer(): void
    {
        $a = $this->poste('admin', 'gerante');
        $id = UuidDeterministe::de('bareme:goliaths|Mature');
        $bareme = ['id' => $id, 'espece' => 'goliaths', 'stade' => 'Mature', 'ration_grammes_par_jour' => 110, 'confirme' => false];
        $this->demander($a, 'bareme_ration', $bareme, self::ADOPTION)->assertJsonPath('rejected', []);
        $this->demander($a, 'bareme_ration', array_merge($bareme, ['ration_grammes_par_jour' => 140]), now()->format('Y-m-d\TH:i:s.u\Z'))
            ->assertJsonPath('rejected', []);

        $this->demander($a, 'bareme_ration', $bareme, self::ADOPTION)
            ->assertJsonPath('rejected.0.motif', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.');

        $this->assertSame(
            140,
            \App\Models\BaremeRation::query()->find($id)->ration_grammes_par_jour,
        );
    }

    // ------------------------------------------------------------------ D4

    private function intrantDemande(): array
    {
        return ['code' => 'INT-009', 'name' => 'Son de blé', 'cat' => 'Intrants Provende', 'unit' => 'kg', 'threshold' => 3];
    }

    public function test_la_suppression_d_un_intrant_l_archive_sans_l_effacer_et_il_redescend_archive(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'seconde');
        $intrant = $this->intrantDemande();
        $this->demander($a, 'intrant', $intrant, '2026-11-01T10:00:00.000Z')->assertJsonPath('rejected', []);

        $this->demander($a, 'intrant', $intrant + ['archive' => true], '2026-11-02T10:00:00.000Z')
            ->assertJsonPath('rejected', []);

        $this->assertNull(Intrant::query()->find('INT-009'), 'invisible des ecrans');
        $ligne = Intrant::withoutGlobalScopes()->find('INT-009');
        $this->assertNotNull($ligne->archive_le);
        $servi = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->assertOk()->json('tables.intrants'))
            ->firstWhere('code', 'INT-009');
        $this->assertNotNull($servi['archive_le'], 'la pierre tombale descend vers les postes');
    }

    public function test_une_restauration_plus_recente_leve_l_archivage_une_plus_ancienne_est_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');
        $intrant = $this->intrantDemande();
        $this->demander($a, 'intrant', $intrant, '2026-11-01T10:00:00.000Z');
        $this->demander($a, 'intrant', $intrant + ['archive' => true], '2026-11-03T10:00:00.000Z');

        $this->demander($a, 'intrant', $intrant, '2026-11-02T10:00:00.000Z')
            ->assertJsonPath('rejected.0.motif', 'Une modification plus récente existe sur le serveur : elle vous sera envoyée.');
        $this->assertNotNull(Intrant::withoutGlobalScopes()->find('INT-009')->archive_le);

        $this->demander($a, 'intrant', $intrant, '2026-11-04T10:00:00.000Z')->assertJsonPath('rejected', []);
        $this->assertNull(Intrant::withoutGlobalScopes()->find('INT-009')->archive_le);
    }

    public function test_un_mouvement_d_un_intrant_archive_reste_accepte_l_historique_l_exige(): void
    {
        $a = $this->poste('admin', 'gerante');
        $intrant = $this->intrantDemande();
        $this->demander($a, 'intrant', $intrant + ['archive' => true], '2026-11-02T10:00:00.000Z');

        $bilan = $this->pousserTable($a, 'mouvements_intrant', [[
            'id' => (string) Str::uuid(),
            'horodatage' => '2026-11-01T09:00:00.000Z',
            'intrant_code' => 'INT-009',
            'article' => 'Son de blé',
            'type' => 'Entrée',
            'motif' => 'Avant suppression',
            'quantite' => 5,
            'reference' => null,
            'updated_at' => '2026-11-01T09:00:00.000Z',
        ]]);

        $this->assertSame([], $bilan['rejected']);
        $this->assertCount(1, $bilan['accepted']);
    }

    public function test_le_drapeau_d_archivage_d_un_intrant_invalide_est_refuse(): void
    {
        $a = $this->poste('admin', 'gerante');

        $this->demander($a, 'intrant', $this->intrantDemande() + ['archive' => 'peut-etre'], '2026-11-02T10:00:00.000Z')
            ->assertJsonPath('rejected.0.motif', 'Le drapeau d\'archivage de l\'intrant est invalide.');
    }

    // ------------------------------------------------------------------ D2

    public function test_un_texte_libre_est_conserve_octet_pour_octet(): void
    {
        $a = $this->poste('admin', 'gerante');
        $accents = "Éléphant « à l'œuf » — 5 000 F ≠ 5000 🐔\nDeuxième ligne\n";
        $bande = $this->ligneBande('FID-1', ['observations' => $accents]);
        $note = [
            'id' => UuidDeterministe::note($this->anneeComptable(), 1),
            'exercice_annee' => $this->anneeComptable(),
            'numero_note' => 1,
            'titre' => 'Méthodes Comptables',
            'contenu' => "  Retour à la ligne final\n\n",
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ];

        $this->assertCount(1, $this->pousserTable($a, 'bandes', [$bande])['accepted']);
        $this->assertCount(1, $this->pousserTable($a, 'notes_annexes', [$note])['accepted']);

        $this->assertSame($accents, Bande::query()->find($bande['id'])->observations);
        $this->assertSame("  Retour à la ligne final\n\n", NoteAnnexe::query()->first()->contenu);
    }

    public function test_une_chaine_vide_reste_vide_et_ne_devient_pas_null(): void
    {
        $a = $this->poste('admin', 'gerante');
        $bande = $this->ligneBande('FID-2', ['observations' => '']);

        $this->pousserTable($a, 'bandes', [$bande]);

        $this->assertSame('', Bande::query()->find($bande['id'])->observations);
    }

    public function test_une_designation_faite_d_espaces_reste_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');

        $bilan = $this->pousserTable($a, 'clients', [$this->ligneClient(['nom' => '   '])]);

        $this->assertSame('Le nom du client est obligatoire.', $bilan['rejected'][0]['motif']);
    }

    // ------------------------------------------------------------------ D3

    public function test_une_piece_de_vente_dont_les_frais_de_livraison_ne_sont_pas_credites_est_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');
        $sans = $this->pieceComptable([
            'journal_code' => 'VT',
            'numero_piece' => 'V-P1-'.$this->anneeComptable().'-001',
            'vente_ref' => 'V-P1-'.$this->anneeComptable().'-001',
            'lignes' => [
                $this->ligneEcriture('531', 19500, 0),
                $this->ligneEcriture('701', 0, 18000),
            ],
        ]);

        $bilan = $this->pousserTable($a, 'ecriture_comptable', [$sans]);

        $this->assertSame('Pièce déséquilibrée : débit 19 500 ≠ crédit 18 000.', $bilan['rejected'][0]['motif']);
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_la_meme_piece_avec_les_frais_credites_sans_centre_analytique_est_acceptee(): void
    {
        $a = $this->poste('admin', 'gerante');
        $avec = $this->pieceComptable([
            'journal_code' => 'VT',
            'numero_piece' => 'V-P1-'.$this->anneeComptable().'-002',
            'vente_ref' => 'V-P1-'.$this->anneeComptable().'-002',
            'lignes' => [
                $this->ligneEcriture('531', 19500.5, 0),
                $this->ligneEcriture('701', 0, 18000, ['axe_analytique' => 'Goliaths']),
                $this->ligneEcriture('701', 0, 1500.5),
            ],
        ]);

        $bilan = $this->pousserTable($a, 'ecriture_comptable', [$avec]);

        $this->assertSame([$avec['id']], $bilan['accepted']);
        $this->assertSame([], $bilan['rejected']);
    }
}
