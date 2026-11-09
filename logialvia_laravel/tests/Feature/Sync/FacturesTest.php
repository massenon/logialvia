<?php

namespace Tests\Feature\Sync;

use App\Models\Facture;
use App\Models\GroupeTaxe;
use App\Models\LigneFacture;
use Database\Seeders\GroupesTaxeSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * P9 — factures e-MECeF : un lot facture + lignes, une référence officielle, un contenu immuable,
 * un statut qui ne régresse jamais, une normalisation qui ne change pas, aucune transmission à la DGI.
 */
class FacturesTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
        $this->seed(GroupesTaxeSeeder::class);
    }

    private function pousser(array $poste, array $factures, array $extra = [])
    {
        return $this->avecJeton($poste['jeton'])->postJson('/api/sync/push', [
            'device_id' => $poste['device'],
            'reset_mark' => 'initiale',
            'tables' => array_merge(['factures' => $factures], $extra),
        ]);
    }

    private function bilan($reponse): array
    {
        return $reponse->assertOk()->json('factures');
    }

    /** Un poste qui peut écrire des factures (le comptable a `manage-facturation`). */
    private function emetteur(string $nom = 'compta'): array
    {
        return $this->poste('comptable', $nom);
    }

    // ------------------------------------------------------------ Enregistrement

    public function test_une_facture_et_ses_lignes_sont_enregistrees_ensemble(): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFacture();

        $bilan = $this->bilan($this->pousser($a, [$f]));

        $this->assertSame([$f['id']], $bilan['accepted']);
        $facture = Facture::query()->find($f['id']);
        $this->assertSame('FV-P1-2026-001', $facture->reference);
        $this->assertSame($a['device'], $facture->device_id);
        $this->assertSame(11800.0, $facture->total_ttc);
        $this->assertSame('a_transmettre', $facture->statut);
        $this->assertSame(1, LigneFacture::query()->where('facture_id', $f['id'])->count());
    }

    public function test_les_lignes_voyagent_dans_leur_facture_au_tirage_d_un_autre_poste(): void
    {
        $a = $this->emetteur();
        $b = $this->poste('caissier', 'bako');
        $f = $this->ligneFacture(['lignes' => [
            ['id' => (string) Str::uuid(), 'designation' => 'Goliath', 'quantite' => 1, 'unite' => 'u', 'prix_unitaire_ht' => 10000, 'groupe_taxe' => 'B', 'taux_taxe' => 18, 'montant_ht' => 10000, 'montant_taxe' => 1800],
            ['id' => (string) Str::uuid(), 'designation' => 'Oeufs', 'quantite' => 5, 'unite' => 'plateau', 'prix_unitaire_ht' => 1000, 'groupe_taxe' => 'A', 'taux_taxe' => 0, 'montant_ht' => 5000, 'montant_taxe' => 0],
        ], 'total_ht' => 15000, 'total_taxe' => 1800, 'total_ttc' => 16800]);
        $this->pousser($a, [$f])->assertOk();

        $recue = collect($this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.factures'))->firstWhere('id', $f['id']);

        $this->assertCount(2, $recue['lignes']);
        $this->assertSame($a['device'], $recue['device_id']);
        $this->assertArrayNotHasKey('portee_reference', $recue, 'détail d\'implémentation du serveur');
    }

    public function test_aucun_secret_ni_url_e_mecef_ne_transite_ni_ne_se_stocke(): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFactureNormalisee();
        $f['jeton'] = 'jeton-secret';
        $f['url'] = 'https://mecef.dgi.example/secret-url';
        $this->pousser($a, [$f])->assertOk();

        $recue = collect($this->avecJeton($a['jeton'])->getJson('/api/sync/pull')->json('tables.factures'))->firstWhere('id', $f['id']);

        $this->assertEqualsCanonicalizing([
            'id', 'device_id', 'reference', 'type', 'vente_ref', 'origine_ref', 'date_facture', 'client', 'client_ifu',
            'client_adresse', 'total_ht', 'total_taxe', 'total_ttc', 'motif', 'statut', 'code_mecef', 'nim', 'compteur',
            'lien_verification', 'date_normalisation', 'erreur_transmission', 'updated_at', 'serveur_modifie_le', 'lignes',
        ], array_keys($recue), 'la liste des colonnes servies est fermée : ni jeton ni URL du service');
        $this->assertStringNotContainsString('jeton-secret', json_encode($recue));
        $this->assertStringNotContainsString('secret-url', json_encode($recue));
        $this->assertStringNotContainsString('secret-url', json_encode(Facture::query()->find($f['id'])->getAttributes()));
    }

    public function test_le_serveur_ne_transmet_jamais_a_la_dgi(): void
    {
        Http::fake();
        $a = $this->emetteur();

        $this->pousser($a, [$this->ligneFacture(), $this->ligneFactureNormalisee(['reference' => 'FV-P1-2026-002'])])->assertOk();
        $this->avecJeton($a['jeton'])->getJson('/api/sync/pull')->assertOk();

        Http::assertNothingSent();
    }

    // ---------------------------------------------------------------- Validation

    public static function facturesInvalides(): array
    {
        return [
            'référence invalide' => [['reference' => 'FACTURE-1'], 'La référence de la facture est invalide (attendu : FV-P2-2026-001).'],
            'référence qui ne correspond pas au type' => [['reference' => 'FA-P1-2026-001'], 'La référence ne correspond pas au type de la facture.'],
            'type inconnu' => [['type' => 'XX'], 'Le type de la facture est inconnu (FV ou FA).'],
            'statut inconnu' => [['statut' => 'payee'], 'Le statut de la facture est inconnu.'],
            'client vide' => [['client' => ''], 'Le client de la facture est obligatoire.'],
            'total négatif' => [['total_ht' => -1], 'Le total hors taxe ne peut pas être négatif.'],
            'aucune ligne' => [['lignes' => []], 'Une facture doit avoir au moins une ligne.'],
            'ttc qui n\'est pas ht + taxe' => [['total_ttc' => 1], 'Les totaux de la facture ne sont pas ceux de ses lignes.'],
            'totaux qui ne sont pas ceux des lignes' => [['total_ht' => 12345, 'total_taxe' => 0, 'total_ttc' => 12345], 'Les totaux de la facture ne sont pas ceux de ses lignes.'],
            'HT qui n\'est pas celui des lignes (taxe cohérente)' => [['total_ht' => 12345, 'total_taxe' => 1800, 'total_ttc' => 14145], 'Les totaux de la facture ne sont pas ceux de ses lignes.'],
            'taxe qui n\'est pas celle des lignes (HT cohérent)' => [['total_ht' => 10000, 'total_taxe' => 0, 'total_ttc' => 10000], 'Les totaux de la facture ne sont pas ceux de ses lignes.'],
            'facture de vente qui désigne une origine' => [['origine_ref' => 'FV-P1-2026-009'], "Une facture de vente ne désigne aucune facture d'origine."],
            'normalisée sans code' => [['statut' => 'normalisee', 'nim' => 'N', 'date_normalisation' => '2026-11-02T09:00:00.000000Z'], 'Une facture normalisée porte un code de normalisation, un NIM et sa date.'],
            'normalisée sans NIM' => [['statut' => 'normalisee', 'code_mecef' => 'C', 'date_normalisation' => '2026-11-02T09:00:00.000000Z'], 'Une facture normalisée porte un code de normalisation, un NIM et sa date.'],
            'code sans normalisation' => [['code_mecef' => 'C'], 'Une facture non normalisée ne porte ni code de normalisation ni NIM.'],
            'NIM sans normalisation' => [['statut' => 'rejetee', 'nim' => 'N'], 'Une facture non normalisée ne porte ni code de normalisation ni NIM.'],
            'référence de vente invalide' => [['vente_ref' => 'VENTE'], 'La référence de la vente est invalide.'],
        ];
    }

    /** @dataProvider facturesInvalides */
    public function test_une_facture_invalide_est_refusee_avec_un_motif_francais(array $surcharge, string $motif): void
    {
        $a = $this->emetteur();

        $bilan = $this->bilan($this->pousser($a, [$this->ligneFacture($surcharge)]));

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, Facture::query()->count());
    }

    public static function lignesInvalides(): array
    {
        return [
            'quantité nulle' => ['quantite', 0, "La quantité d'une ligne doit être supérieure à 0."],
            'groupe invalide' => ['groupe_taxe', 'ab', 'Le groupe de taxe est une lettre majuscule (A, B…).'],
            'taux au-dessus de 100' => ['taux_taxe', 150, 'Le taux de taxe ne peut pas dépasser 100 %.'],
        ];
    }

    /** @dataProvider lignesInvalides */
    public function test_une_ligne_invalide_refuse_toute_la_facture(string $champ, mixed $valeur, string $motif): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFacture();
        $f['lignes'][0][$champ] = $valeur;

        $bilan = $this->bilan($this->pousser($a, [$f]));

        $this->assertSame($motif, $bilan['rejected'][0]['motif']);
        $this->assertSame(0, Facture::query()->count());
        $this->assertSame(0, LigneFacture::query()->count(), 'jamais une ligne sans sa facture');
    }

    public function test_un_avoir_sans_origine_ou_sans_motif_est_refuse(): void
    {
        $a = $this->emetteur();
        $sansOrigine = $this->ligneFacture(['type' => 'FA', 'reference' => 'FA-P1-2026-001', 'motif' => 'Retour']);
        $sansMotif = $this->ligneFacture(['type' => 'FA', 'reference' => 'FA-P1-2026-002', 'origine_ref' => 'FV-P1-2026-001']);

        $bilan = $this->bilan($this->pousser($a, [$sansOrigine, $sansMotif]));

        $this->assertSame("Un avoir désigne la facture qu'il corrige et en donne le motif.", $bilan['rejected'][0]['motif']);
        $this->assertSame("Un avoir désigne la facture qu'il corrige et en donne le motif.", $bilan['rejected'][1]['motif']);
    }

    // ------------------------------------------------------------------ Avoirs

    public function test_un_avoir_doit_viser_une_facture_de_vente_connue(): void
    {
        $a = $this->emetteur();
        $avoir = $this->ligneFacture(['type' => 'FA', 'reference' => 'FA-P1-2026-001', 'origine_ref' => 'FV-P1-2026-001', 'motif' => 'Retour']);

        $bilan = $this->bilan($this->pousser($a, [$avoir]));

        $this->assertSame("La facture d'origine est inconnue du serveur.", $bilan['rejected'][0]['motif']);
    }

    public function test_une_facture_et_son_avoir_dans_le_meme_lot_sont_acceptes_dans_l_ordre(): void
    {
        $a = $this->emetteur();
        $fv = $this->ligneFacture();
        $fa = $this->ligneFacture(['type' => 'FA', 'reference' => 'FA-P1-2026-001', 'origine_ref' => $fv['reference'], 'motif' => 'Retour']);

        $bilan = $this->bilan($this->pousser($a, [$fv, $fa]));

        $this->assertSame([$fv['id'], $fa['id']], $bilan['accepted']);
        $this->assertSame('FV-P1-2026-001', Facture::query()->find($fa['id'])->origine_ref);
    }

    public function test_un_avoir_ne_vise_pas_la_facture_d_un_autre_poste_sans_code(): void
    {
        $a = $this->emetteur('compta-a');
        $b = $this->emetteur('compta-b');
        $this->pousser($a, [$this->ligneFacture(['reference' => 'FV-2026-001'])])->assertOk();
        $avoir = $this->ligneFacture(['type' => 'FA', 'reference' => 'FA-2026-001', 'origine_ref' => 'FV-2026-001', 'motif' => 'Retour']);

        $bilan = $this->bilan($this->pousser($b, [$avoir]));

        $this->assertSame("La facture d'origine est inconnue du serveur.", $bilan['rejected'][0]['motif']);
    }

    // ----------------------------------------------------------------- Références

    public function test_une_reference_a_code_de_poste_est_unique_pour_tous(): void
    {
        $a = $this->emetteur('compta-a');
        $b = $this->emetteur('compta-b');
        $this->pousser($a, [$this->ligneFacture(['reference' => 'FV-P2-2026-001'])])->assertOk();

        $bilan = $this->bilan($this->pousser($b, [$this->ligneFacture(['reference' => 'FV-P2-2026-001'])]));

        $this->assertSame('Cette référence est déjà utilisée par une autre facture.', $bilan['rejected'][0]['motif']);
        $this->assertSame(1, Facture::query()->count());
    }

    public function test_deux_postes_peuvent_avoir_chacun_la_meme_ancienne_reference_sans_code(): void
    {
        $a = $this->emetteur('compta-a');
        $b = $this->emetteur('compta-b');
        $fa = $this->ligneFacture(['reference' => 'FV-2026-001']);
        $fb = $this->ligneFacture(['reference' => 'FV-2026-001']);

        $this->assertSame([$fa['id']], $this->bilan($this->pousser($a, [$fa]))['accepted']);
        $this->assertSame([$fb['id']], $this->bilan($this->pousser($b, [$fb]))['accepted']);
        $this->assertSame(2, Facture::query()->count());
    }

    public function test_un_meme_poste_ne_reutilise_pas_une_ancienne_reference(): void
    {
        $a = $this->emetteur();
        $this->pousser($a, [$this->ligneFacture(['reference' => 'FV-2026-001'])])->assertOk();

        $bilan = $this->bilan($this->pousser($a, [$this->ligneFacture(['reference' => 'FV-2026-001'])]));

        $this->assertSame('Cette référence est déjà utilisée par une autre facture.', $bilan['rejected'][0]['motif']);
    }

    public function test_une_facture_et_un_avoir_ont_chacun_leur_sequence(): void
    {
        $a = $this->emetteur();
        $fv = $this->ligneFacture(['reference' => 'FV-P1-2026-001']);
        $fa = $this->ligneFacture(['type' => 'FA', 'reference' => 'FA-P1-2026-001', 'origine_ref' => 'FV-P1-2026-001', 'motif' => 'Retour']);

        $this->assertCount(2, $this->bilan($this->pousser($a, [$fv, $fa]))['accepted']);
    }

    // --------------------------------------------------------- Une facture par vente

    public function test_deux_postes_qui_facturent_la_meme_vente_ne_la_facturent_pas_deux_fois(): void
    {
        $a = $this->emetteur('compta-a');
        $b = $this->emetteur('compta-b');
        $this->pousser($a, [$this->ligneFacture(['reference' => 'FV-P1-2026-001', 'vente_ref' => 'V-P1-2026-004'])])->assertOk();

        $bilan = $this->bilan($this->pousser($b, [$this->ligneFacture(['reference' => 'FV-P2-2026-001', 'vente_ref' => 'V-P1-2026-004'])]));

        $this->assertSame('Cette vente porte déjà la facture FV-P1-2026-001.', $bilan['rejected'][0]['motif']);
        $this->assertSame(1, Facture::query()->count());
    }

    public function test_une_ancienne_reference_de_vente_est_propre_a_son_poste(): void
    {
        $a = $this->emetteur('compta-a');
        $b = $this->emetteur('compta-b');
        $this->pousser($a, [$this->ligneFacture(['reference' => 'FV-2026-001', 'vente_ref' => 'V-2026-004'])])->assertOk();

        $autrePoste = $this->ligneFacture(['reference' => 'FV-2026-001', 'vente_ref' => 'V-2026-004']);
        $this->assertSame([$autrePoste['id']], $this->bilan($this->pousser($b, [$autrePoste]))['accepted']);

        $memePoste = $this->ligneFacture(['reference' => 'FV-2026-002', 'vente_ref' => 'V-2026-004']);
        $this->assertStringStartsWith('Cette vente porte déjà la facture', $this->bilan($this->pousser($a, [$memePoste]))['rejected'][0]['motif']);
    }

    public function test_un_avoir_n_est_pas_une_seconde_facture_de_la_vente(): void
    {
        $a = $this->emetteur();
        $fv = $this->ligneFacture(['vente_ref' => 'V-P1-2026-004']);
        $this->pousser($a, [$fv])->assertOk();
        $fa = $this->ligneFacture(['type' => 'FA', 'reference' => 'FA-P1-2026-001', 'origine_ref' => $fv['reference'], 'motif' => 'Retour']);

        $this->assertCount(1, $this->bilan($this->pousser($a, [$fa]))['accepted']);
    }

    // ------------------------------------------------ Contenu immuable, rejeu

    public function test_un_rejeu_est_accepte_sans_rien_dupliquer_ni_toucher(): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFacture();
        $this->pousser($a, [$f])->assertOk();
        $avant = Facture::query()->find($f['id'])->serveur_modifie_le;
        $this->travel(5)->seconds();

        $this->assertSame([$f['id']], $this->bilan($this->pousser($a, [$f]))['accepted']);

        $this->assertSame(1, Facture::query()->count());
        $this->assertSame(1, LigneFacture::query()->count());
        $this->assertEquals($avant, Facture::query()->find($f['id'])->serveur_modifie_le, 'un rejeu ne relance pas le tirage des autres postes');
    }

    public function test_le_contenu_d_une_facture_emise_ne_change_jamais(): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFacture(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->pousser($a, [$f])->assertOk();

        $autre = array_merge($f, ['client' => 'Quelqu\'un d\'autre', 'updated_at' => '2026-11-01T11:00:00.000000Z']);
        $nouveauTotal = array_merge($f, ['total_ht' => 20000, 'total_taxe' => 3600, 'total_ttc' => 23600, 'updated_at' => '2026-11-01T11:00:00.000000Z']);
        $nouveauTotal['lignes'][0]['montant_ht'] = 20000;
        $nouveauTotal['lignes'][0]['montant_taxe'] = 3600;
        $autresLignes = array_merge($f, ['updated_at' => '2026-11-01T11:00:00.000000Z']);
        $autresLignes['lignes'][0]['id'] = (string) Str::uuid();

        foreach ([$autre, $nouveauTotal, $autresLignes] as $tentative) {
            $bilan = $this->bilan($this->pousser($a, [$tentative]));
            $this->assertSame('Une facture émise ne se modifie pas : émettez un avoir.', $bilan['rejected'][0]['motif']);
        }

        $facture = Facture::query()->find($f['id']);
        $this->assertSame('DOSSOU Félicité', $facture->client);
        $this->assertSame(11800.0, $facture->total_ttc);
        $this->assertSame(10000.0, $facture->lignes()->first()->montant_ht);
    }

    public function test_la_reference_d_une_facture_ne_change_jamais(): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFacture();
        $this->pousser($a, [$f])->assertOk();

        $renumerotee = array_merge($f, ['reference' => 'FV-P1-2026-777', 'updated_at' => now()->addMinute()->format('Y-m-d\TH:i:s.u\Z')]);

        $this->assertSame('Une facture émise ne se modifie pas : émettez un avoir.', $this->bilan($this->pousser($a, [$renumerotee]))['rejected'][0]['motif']);
        $this->assertSame('FV-P1-2026-001', Facture::query()->find($f['id'])->reference);
    }

    // ------------------------------------------------- Statut : la machine à états

    private function normaliser(array $f, array $surcharge = []): array
    {
        return array_merge($f, [
            'statut' => 'normalisee',
            'code_mecef' => 'CODE-A',
            'nim' => 'NIM-1',
            'compteur' => '12/50',
            'lien_verification' => 'https://dgi.example/v/1',
            'date_normalisation' => '2026-11-02T09:00:00.000000Z',
            'updated_at' => '2026-11-02T09:00:00.000000Z',
        ], $surcharge);
    }

    public function test_une_facture_a_transmettre_devient_normalisee(): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFacture(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->pousser($a, [$f])->assertOk();

        $this->assertSame([$f['id']], $this->bilan($this->pousser($a, [$this->normaliser($f)]))['accepted']);

        $facture = Facture::query()->find($f['id']);
        $this->assertSame('normalisee', $facture->statut);
        $this->assertSame('CODE-A', $facture->code_mecef);
        $this->assertSame('NIM-1', $facture->nim);
        $this->assertSame('12/50', $facture->compteur);
    }

    public function test_une_facture_rejetee_peut_etre_retransmise_puis_normalisee(): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFacture(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->pousser($a, [$f])->assertOk();

        $rejetee = array_merge($f, ['statut' => 'rejetee', 'erreur_transmission' => 'Réseau coupé', 'updated_at' => '2026-11-01T11:00:00.000000Z']);
        $this->assertCount(1, $this->bilan($this->pousser($a, [$rejetee]))['accepted']);
        $this->assertSame('rejetee', Facture::query()->find($f['id'])->statut);
        $this->assertSame('Réseau coupé', Facture::query()->find($f['id'])->erreur_transmission);

        $this->assertCount(1, $this->bilan($this->pousser($a, [$this->normaliser($f, ['erreur_transmission' => null])]))['accepted']);
        $facture = Facture::query()->find($f['id']);
        $this->assertSame('normalisee', $facture->statut);
        $this->assertNull($facture->erreur_transmission);
    }

    public static function regressions(): array
    {
        return [
            'normalisée → à transmettre' => ['normalisee', ['statut' => 'a_transmettre'], 'Normalisée'],
            'normalisée → rejetée' => ['normalisee', ['statut' => 'rejetee', 'erreur_transmission' => 'x'], 'Normalisée'],
            'rejetée → à transmettre' => ['rejetee', ['statut' => 'a_transmettre'], 'Rejetée'],
        ];
    }

    /** @dataProvider regressions */
    public function test_un_statut_ne_regresse_jamais_meme_avec_une_saisie_plus_recente(string $actuel, array $tentative, string $libelle): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFacture(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->pousser($a, [$f])->assertOk();
        $etat = $actuel === 'normalisee'
            ? $this->normaliser($f)
            : array_merge($f, ['statut' => 'rejetee', 'erreur_transmission' => 'Réseau coupé', 'updated_at' => '2026-11-02T09:00:00.000000Z']);
        $this->pousser($a, [$etat])->assertOk();

        // Saisie PLUS RECENTE que l'etat du serveur : l'horloge ne decide pas, le rang decide.
        $bilan = $this->bilan($this->pousser($a, [array_merge($f, $tentative, ['updated_at' => '2999-01-01T00:00:00.000000Z'])]));

        $this->assertSame("La facture est déjà « $libelle » sur le serveur : un statut ne régresse jamais.", $bilan['rejected'][0]['motif']);
        $this->assertSame($actuel, Facture::query()->find($f['id'])->statut);
    }

    public function test_une_facture_normalisee_est_immuable_un_second_code_est_refuse(): void
    {
        $a = $this->emetteur('compta-a');
        $b = $this->emetteur('compta-b');
        $f = $this->ligneFacture(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->pousser($a, [$f])->assertOk();
        $this->pousser($a, [$this->normaliser($f)])->assertOk();

        $double = $this->normaliser($f, ['code_mecef' => 'CODE-B', 'nim' => 'NIM-B', 'updated_at' => '2999-01-01T00:00:00.000000Z']);
        $bilan = $this->bilan($this->pousser($b, [$double]));

        $this->assertSame('Cette facture est déjà normalisée sous un autre code (CODE-A) : une normalisation ne change pas.', $bilan['rejected'][0]['motif']);
        $facture = Facture::query()->find($f['id']);
        $this->assertSame('CODE-A', $facture->code_mecef, 'la première normalisation reçue est conservée');
        $this->assertSame('NIM-1', $facture->nim);
    }

    public function test_un_nim_different_avec_le_meme_code_est_aussi_refuse(): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFacture(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->pousser($a, [$f])->assertOk();
        $this->pousser($a, [$this->normaliser($f)])->assertOk();

        $bilan = $this->bilan($this->pousser($a, [$this->normaliser($f, ['nim' => 'NIM-2'])]));

        $this->assertCount(1, $bilan['rejected']);
        $this->assertSame('NIM-1', Facture::query()->find($f['id'])->nim);
    }

    public function test_le_rejeu_d_une_normalisation_identique_est_accepte_sans_effet(): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFacture(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->pousser($a, [$f])->assertOk();
        $n = $this->normaliser($f);
        $this->pousser($a, [$n])->assertOk();
        $avant = Facture::query()->find($f['id'])->serveur_modifie_le;
        $this->travel(5)->seconds();

        $this->assertSame([$f['id']], $this->bilan($this->pousser($a, [$n]))['accepted']);
        $this->assertEquals($avant, Facture::query()->find($f['id'])->serveur_modifie_le);
    }

    public function test_deux_rejets_le_plus_recent_gagne_un_rejet_plus_ancien_est_sans_effet(): void
    {
        $a = $this->emetteur();
        $f = $this->ligneFacture(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->pousser($a, [$f])->assertOk();
        $rejet = fn (string $erreur, string $instant) => array_merge($f, ['statut' => 'rejetee', 'erreur_transmission' => $erreur, 'updated_at' => $instant]);

        $this->pousser($a, [$rejet('Deuxième', '2026-11-01T12:00:00.000000Z')])->assertOk();
        $this->assertSame('Deuxième', Facture::query()->find($f['id'])->erreur_transmission);

        $this->assertCount(1, $this->bilan($this->pousser($a, [$rejet('Première', '2026-11-01T11:00:00.000000Z')]))['accepted']);
        $this->assertSame('Deuxième', Facture::query()->find($f['id'])->erreur_transmission, 'un rejet plus ancien arrivé en retard est sans effet');

        $this->pousser($a, [$rejet('Troisième', '2026-11-01T13:00:00.000000Z')])->assertOk();
        $this->assertSame('Troisième', Facture::query()->find($f['id'])->erreur_transmission);
    }

    public function test_une_normalisation_redescend_vers_les_autres_postes(): void
    {
        $a = $this->emetteur('compta-a');
        $b = $this->poste('caissier', 'bako');
        $f = $this->ligneFacture(['updated_at' => '2026-11-01T10:00:00.000000Z']);
        $this->pousser($a, [$f])->assertOk();
        $premierTirage = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->assertOk();
        $curseur = $premierTirage->json('server_time');
        $this->travel(5)->seconds();
        $this->pousser($a, [$this->normaliser($f)])->assertOk();

        $tirage = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull?since='.urlencode($curseur))->assertOk();

        $recue = collect($tirage->json('tables.factures'))->firstWhere('id', $f['id']);
        $this->assertSame('normalisee', $recue['statut']);
        $this->assertSame('CODE-A', $recue['code_mecef']);
    }

    // --------------------------------------------------------------------- Droits

    public function test_sans_le_droit_d_ecriture_toutes_les_factures_sont_refusees(): void
    {
        // DV-06 : le caissier consulte et réimprime, sans créer ni transmettre.
        $caissier = $this->poste('caissier', 'amina');

        $bilan = $this->bilan($this->pousser($caissier, [$this->ligneFacture()]));

        $this->assertSame('Droit insuffisant pour écrire dans « factures ».', $bilan['rejected'][0]['motif']);
        $this->assertSame(0, Facture::query()->count());
    }

    public function test_le_caissier_lit_les_factures_l_animalier_ne_les_voit_pas(): void
    {
        $a = $this->emetteur();
        $this->pousser($a, [$this->ligneFacture()])->assertOk();
        $caissier = $this->poste('caissier', 'amina');
        $animalier = $this->poste('animalier', 'eleveur');

        $this->assertCount(1, $this->avecJeton($caissier['jeton'])->getJson('/api/sync/pull')->json('tables.factures'));
        $tables = $this->avecJeton($animalier['jeton'])->getJson('/api/sync/pull')->json('tables');

        $this->assertArrayNotHasKey('factures', $tables);
        $this->assertArrayNotHasKey('groupes_taxe', $tables);
    }

    // ------------------------------------------------------------ Remise à zéro

    public function test_la_remise_a_zero_vide_les_factures_et_leurs_lignes_et_preserve_la_grille(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $admin = $this->poste('admin', 'gerante');
        $this->pousser($admin, [$this->ligneFacture()])->assertOk();
        $this->assertSame(1, LigneFacture::query()->count());

        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/remise-a-zero', ['confirmation' => 'REMETTRE A ZERO'])->assertOk();

        $this->assertSame(0, Facture::query()->count());
        $this->assertSame(0, LigneFacture::query()->count(), 'les lignes partent avec leur facture');
        $this->assertSame(2, GroupeTaxe::query()->count(), 'la grille de taxation (référentiel) est préservée');
    }
}
