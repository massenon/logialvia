<?php

namespace Tests\Feature\Sync;

use App\Models\Achat;
use App\Sync\Tables\AchatsTable;
use App\Models\Fournisseur;
use App\Models\LigneAchat;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/** Fournisseurs et achats : un lot achat + lignes, une reference officielle, aucun stock ni PMP. */
class AchatsTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
    }

    private function pousser(array $poste, array $tables)
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => 'initiale',
            'tables' => $tables,
        ]);
    }

    private function fournisseurConnu(array $poste, array $surcharge = []): string
    {
        // Les intrants sont connus du serveur AVANT les achats qui les portent.
        $this->intrantConnu($poste);
        $this->intrantConnu($poste, ['code' => 'INT-002', 'name' => 'Soja']);
        $f = $this->ligneFournisseur($surcharge);
        $this->pousser($poste, ['fournisseurs' => [$f]])->assertOk()->assertJsonPath('fournisseurs.rejected', []);

        return $f['id'];
    }

    private function bilanAchats(array $poste, array $achats): array
    {
        return $this->pousser($poste, ['achats' => $achats])->assertOk()->json('achats');
    }

    // ------------------------------------------------------------ Fournisseurs

    public function test_un_fournisseur_est_enregistre_et_redescend_vers_un_autre_poste(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $id = $this->fournisseurConnu($a);

        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.fournisseurs'))->firstWhere('id', $id);

        $this->assertSame('Maïs Local', $recu['nom']);
        $this->assertSame($a['device'], $recu['device_id']);
    }

    public function test_un_fournisseur_sans_nom_est_refuse_avec_un_message_francais(): void
    {
        $a = $this->poste('admin', 'gerante');
        $f = $this->ligneFournisseur(['nom' => '']);

        $r = $this->pousser($a, ['fournisseurs' => [$f]])->json('fournisseurs');

        $this->assertSame('Le nom du fournisseur est obligatoire.', $r['rejected'][0]['motif']);
        $this->assertSame(0, Fournisseur::query()->count());
    }

    public function test_deux_fournisseurs_homonymes_restent_distincts(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $this->fournisseurConnu($a, ['nom' => 'Soja Bénin']);
        $this->fournisseurConnu($b, ['nom' => 'Soja Bénin']);

        $this->assertSame(2, Fournisseur::query()->where('nom', 'Soja Bénin')->count());
    }

    // ------------------------------------------------------------------ Achats

    public function test_un_achat_et_ses_lignes_sont_enregistres_ensemble_sans_aucun_effet_de_stock(): void
    {
        $a = $this->poste('admin', 'gerante');
        $f = $this->fournisseurConnu($a);
        $achat = $this->ligneAchat($f);

        $bilan = $this->bilanAchats($a, [$achat]);

        $this->assertSame([$achat['id']], $bilan['accepted']);
        $row = Achat::query()->find($achat['id']);
        $this->assertSame('ACH-P1-2026-001', $row->reference);
        $this->assertSame($a['device'], $row->device_id);
        $this->assertSame(1, LigneAchat::query()->where('achat_id', $achat['id'])->count());
        $this->assertSame('INT-001', LigneAchat::query()->first()->intrant_code);
    }

    public function test_les_lignes_voyagent_dans_leur_achat_au_tirage(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $f = $this->fournisseurConnu($a);
        $achat = $this->ligneAchat($f, ['lignes' => [
            ['id' => (string) Str::uuid(), 'intrant_code' => 'INT-001', 'nom' => 'Maïs', 'qte' => 10, 'pu_achat' => 300],
            ['id' => (string) Str::uuid(), 'intrant_code' => 'INT-002', 'nom' => 'Soja', 'qte' => 5, 'pu_achat' => 500],
        ], 'total' => 5500, 'paye' => 0]);
        $this->bilanAchats($a, [$achat]);

        $recu = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.achats'))->firstWhere('id', $achat['id']);

        $this->assertCount(2, $recu['lignes']);
        $this->assertArrayNotHasKey('portee_reference', $recu);
    }

    public function test_un_fournisseur_inconnu_fait_refuser_l_achat_en_entier(): void
    {
        $a = $this->poste('admin', 'gerante');
        $achat = $this->ligneAchat((string) Str::uuid());

        $bilan = $this->bilanAchats($a, [$achat]);

        $this->assertSame('Fournisseur inconnu du serveur.', $bilan['rejected'][0]['motif']);
        $this->assertSame(0, Achat::query()->count());
        $this->assertSame(0, LigneAchat::query()->count(), 'jamais de ligne sans son achat');
    }

    public function test_un_intrant_inconnu_du_serveur_fait_refuser_l_achat_en_entier(): void
    {
        $a = $this->poste('admin', 'gerante');
        $f = $this->fournisseurConnu($a);
        $achat = $this->ligneAchat($f);
        $achat['lignes'][0]['intrant_code'] = 'INT-FANTOME';

        $bilan = $this->bilanAchats($a, [$achat]);

        $this->assertSame('Intrant inconnu du serveur : « INT-FANTOME ».', $bilan['rejected'][0]['motif']);
        $this->assertSame(0, Achat::query()->count());
        $this->assertSame(0, LigneAchat::query()->count());
    }

    public function test_les_droits_lecture_et_ecriture(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $f = $this->fournisseurConnu($admin);
        $this->bilanAchats($admin, [$this->ligneAchat($f)]);

        $comptable = $this->poste('comptable');
        $refus = $this->bilanAchats($comptable, [$this->ligneAchat($f, ['reference' => 'ACH-P2-2026-001'])]);
        $this->assertSame('Droit insuffisant pour écrire dans « achats ».', $refus['rejected'][0]['motif']);
        $this->assertArrayHasKey('achats', $this->avecJeton($comptable['jeton'])->getJson('/api/sync/pull')->json('tables'), 'le comptable consulte');

        $caissier = $this->poste('caissier', 'amina');
        $tables = $this->avecJeton($caissier['jeton'])->getJson('/api/sync/pull')->json('tables');
        $this->assertArrayNotHasKey('achats', $tables);
        $this->assertArrayNotHasKey('fournisseurs', $tables);
    }

    // ---------------------------------------------------- Unicite des references

    public function test_une_reference_a_code_de_poste_est_unique_pour_tous(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $f = $this->fournisseurConnu($a);
        $this->bilanAchats($a, [$this->ligneAchat($f, ['reference' => 'ACH-P2-2026-001'])]);

        $bilan = $this->bilanAchats($b, [$this->ligneAchat($f, ['reference' => 'ACH-P2-2026-001'])]);

        $this->assertSame('Cette référence est déjà utilisée par un autre achat.', $bilan['rejected'][0]['motif']);
        $this->assertSame(1, Achat::query()->count());
    }

    public function test_deux_postes_peuvent_avoir_la_meme_ancienne_reference_sans_code(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $f = $this->fournisseurConnu($a);
        $va = $this->ligneAchat($f, ['reference' => 'ACH-2026-001']);
        $vb = $this->ligneAchat($f, ['reference' => 'ACH-2026-001']);

        $this->assertSame([$va['id']], $this->bilanAchats($a, [$va])['accepted']);
        $this->assertSame([$vb['id']], $this->bilanAchats($b, [$vb])['accepted']);
        $this->assertSame(2, Achat::query()->count());
    }

    public function test_un_meme_poste_ne_reutilise_pas_une_ancienne_reference(): void
    {
        $a = $this->poste('admin', 'gerante');
        $f = $this->fournisseurConnu($a);
        $this->bilanAchats($a, [$this->ligneAchat($f, ['reference' => 'ACH-2026-001'])]);

        $bilan = $this->bilanAchats($a, [$this->ligneAchat($f, ['reference' => 'ACH-2026-001'])]);

        $this->assertSame('Cette référence est déjà utilisée par un autre achat.', $bilan['rejected'][0]['motif']);
    }

    // ------------------------------------------------------------- Validation

    public static function achatsInvalides(): array
    {
        return [
            'référence invalide' => [['reference' => 'V-2026-001'], "La référence de l'achat est invalide (attendu : ACH-P2-2026-001 ou ACH-WEB-2026-001)."],
            'statut inconnu' => [['statut' => 'Perdu'], "Le statut de l'achat est inconnu."],
            'mode inconnu' => [['mode' => 'Troc'], 'Le mode de règlement est inconnu.'],
            'total négatif' => [['total' => -1], "Le total de l'achat ne peut pas être négatif."],
            'payé au-delà du total' => [['paye' => 99999], "Le montant payé dépasse le total de l'achat."],
            'aucune ligne' => [['lignes' => []], 'Un achat doit avoir au moins une ligne.'],
        ];
    }

    /** @dataProvider achatsInvalides */
    public function test_un_achat_invalide_est_refuse_avec_un_motif_francais(array $surcharge, string $motif): void
    {
        $a = $this->poste('admin', 'gerante');
        $f = $this->fournisseurConnu($a);

        $bilan = $this->bilanAchats($a, [$this->ligneAchat($f, $surcharge)]);

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, Achat::query()->count());
    }

    public function test_une_quantite_nulle_est_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');
        $f = $this->fournisseurConnu($a);
        $achat = $this->ligneAchat($f);
        $achat['lignes'][0]['qte'] = 0;

        $this->assertSame("La quantité d'une ligne doit être supérieure à 0.", $this->bilanAchats($a, [$achat])['rejected'][0]['motif']);
    }

    // ------------------------------------------ Dernier ecrivain, immutabilite

    public function test_un_rejeu_ne_duplique_rien(): void
    {
        $a = $this->poste('admin', 'gerante');
        $f = $this->fournisseurConnu($a);
        $achat = $this->ligneAchat($f);
        $this->bilanAchats($a, [$achat]);

        $this->assertSame([$achat['id']], $this->bilanAchats($a, [$achat])['accepted']);

        $this->assertSame(1, Achat::query()->count());
        $this->assertSame(1, LigneAchat::query()->count());
    }

    public function test_une_reference_web_et_le_mode_credit_sont_acceptes_et_la_reference_web_est_unique_pour_tous(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'autre');
        $f = $this->fournisseurConnu($a);
        $web = $this->ligneAchat($f, ['reference' => 'ACH-WEB-2026-001', 'mode' => 'Crédit']);

        $this->assertSame([$web['id']], $this->bilanAchats($a, [$web])['accepted']);
        $this->assertSame('Crédit', Achat::query()->find($web['id'])->mode);
        $this->assertSame('', Achat::query()->find($web['id'])->portee_reference, 'globale, comme un code de poste');

        $doublon = $this->ligneAchat($f, ['reference' => 'ACH-WEB-2026-001']);
        $this->assertSame(AchatsTable::MOTIF_REFERENCE, $this->bilanAchats($b, [$doublon])['rejected'][0]['motif']);
        $this->assertSame(1, Achat::query()->count());
    }

    public function test_l_entete_suit_le_dernier_ecrivain_les_lignes_et_la_reference_ne_bougent_jamais(): void
    {
        $a = $this->poste('admin', 'gerante');
        $f = $this->fournisseurConnu($a);
        $achat = $this->ligneAchat($f, ['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->bilanAchats($a, [$achat]);

        $livre = array_merge($achat, [
            'statut' => 'Livré', 'paye' => 30000, 'updated_at' => '2026-11-01T11:00:00.000000Z',
            'reference' => 'ACH-P1-2026-999',
            'lignes' => [['id' => (string) Str::uuid(), 'intrant_code' => 'INT-002', 'nom' => 'Autre', 'qte' => 9, 'pu_achat' => 1]],
        ]);
        $this->bilanAchats($a, [$livre]);

        $row = Achat::query()->find($achat['id']);
        $this->assertSame('Livré', $row->statut);
        $this->assertSame(30000.0, $row->paye);
        $this->assertSame('ACH-P1-2026-001', $row->reference, 'numéro officiel : jamais changé');
        // La commande etait « Commandé » : une saisie plus recente (modification) remplace ses lignes.
        $this->assertSame(9.0, $row->lignes()->first()->qte, 'commande modifiee : lignes remplacees');
        $this->assertSame(1, $row->lignes()->count());

        // Livree, ses lignes ne bougent plus (le stock des postes en depend).
        $apres = array_merge($livre, [
            'updated_at' => '2026-11-01T12:00:00.000000Z',
            'lignes' => [['id' => (string) Str::uuid(), 'intrant_code' => 'INT-002', 'nom' => 'Encore', 'qte' => 77, 'pu_achat' => 1]],
        ]);
        $this->bilanAchats($a, [$apres]);
        $this->assertSame(9.0, Achat::query()->find($achat['id'])->lignes()->first()->qte, 'lignes immuables des la livraison');

        $ancien = array_merge($achat, ['statut' => 'Annulé', 'updated_at' => '2026-11-01T09:00:00.000000Z']);
        $this->bilanAchats($a, [$ancien]);
        $this->assertSame('Livré', Achat::query()->find($achat['id'])->statut, 'saisie plus ancienne : sans effet');
    }

    public function test_un_achat_saisi_hors_ligne_atteint_un_poste_deja_a_jour(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('admin', 'bako');
        $f = $this->fournisseurConnu($a);
        $curseur = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('server_time');

        $this->travel(5)->seconds();
        $vieux = $this->ligneAchat($f, [
            'updated_at' => now()->subDays(3)->format('Y-m-d\TH:i:s.u\Z'),
            'date_achat' => now()->subDays(3)->format('Y-m-d\TH:i:s.u\Z'),
        ]);
        $this->bilanAchats($a, [$vieux]);

        $recus = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull?since='.urlencode($curseur))->json('tables.achats');

        $this->assertSame([$vieux['id']], array_column($recus, 'id'));
    }
}
