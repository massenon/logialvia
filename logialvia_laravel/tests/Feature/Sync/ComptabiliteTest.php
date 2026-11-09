<?php

namespace Tests\Feature\Sync;

use App\Models\CloturePeriodique;
use App\Models\ClotureExercice;
use App\Models\EcritureComptable;
use App\Models\ExerciceComptable;
use App\Models\NoteAnnexe;
use App\Models\PieceComptable;
use App\Support\UuidDeterministe;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\PostesDeTest;
use Tests\TestCase;

/**
 * P8 — comptabilite : des FAITS IMMUABLES (pieces equilibrees), verifies par le serveur.
 * Equilibre, double verrouillage, droits, contrepassation, clotures, notes.
 */
class ComptabiliteTest extends TestCase
{
    use PostesDeTest, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerSocle();
        $this->amorcerComptabilite();
        config(['logialvia.sync.recouvrement_secondes' => 0]);
    }

    private function pieces(array $poste, array $pieces): array
    {
        return $this->pousserTable($poste, 'ecriture_comptable', $pieces);
    }

    private function une(array $poste, array $piece): array
    {
        return $this->pieces($poste, [$piece]);
    }

    private function motif(array $bilan): ?string
    {
        return $bilan['rejected'][0]['motif'] ?? null;
    }

    private function date(int $mois, int $jour = 15): string
    {
        return now(config('logialvia.fuseau'))->setDate($this->anneeComptable(), $mois, $jour)
            ->setTime(10, 0)->utc()->format('Y-m-d\TH:i:s.u\Z');
    }

    // ----------------------------------------------------------- Une piece

    public function test_une_piece_equilibree_est_acceptee_avec_ses_lignes(): void
    {
        $a = $this->poste('admin', 'gerante');
        $piece = $this->pieceComptable();

        $bilan = $this->une($a, $piece);

        $this->assertSame([$piece['id']], $bilan['accepted']);
        $this->assertSame([], $bilan['rejected']);
        $p = PieceComptable::query()->with('lignes')->find($piece['id']);
        $this->assertSame($a['device'], $p->device_id);
        $this->assertSame('DEP-P1-'.$this->anneeComptable().'-0001', $p->numero_piece);
        $this->assertCount(2, $p->lignes);
        $this->assertSame(3500.0, $p->lignes->sum('debit'));
        $this->assertSame(3500.0, $p->lignes->sum('credit'));
    }

    public function test_une_piece_deja_connue_est_acceptee_sans_rien_changer(): void
    {
        $a = $this->poste('admin', 'gerante');
        $piece = $this->pieceComptable();
        $this->une($a, $piece);
        $avant = PieceComptable::query()->find($piece['id'])->serveur_modifie_le;

        // Rejeu, meme avec un contenu DIFFERENT : un fait accepte est immuable.
        $rejeu = $piece;
        $rejeu['lignes'] = [$this->ligneEcriture('624', 99, 0), $this->ligneEcriture('531', 0, 99)];
        $bilan = $this->une($a, $rejeu);

        $this->assertSame([$piece['id']], $bilan['accepted']);
        $this->assertSame(1, PieceComptable::query()->count());
        $this->assertSame(2, EcritureComptable::query()->count());
        $this->assertSame(3500.0, EcritureComptable::query()->sum('debit'));
        $this->assertEquals($avant, PieceComptable::query()->find($piece['id'])->serveur_modifie_le);
    }

    public function test_une_piece_desequilibree_est_refusee_entiere_avec_son_motif(): void
    {
        $a = $this->poste('admin', 'gerante');
        $piece = $this->pieceComptable(['lignes' => [
            $this->ligneEcriture('624', 3500, 0), $this->ligneEcriture('531', 0, 3000),
        ]]);

        $bilan = $this->une($a, $piece);

        $this->assertSame([], $bilan['accepted']);
        $this->assertSame('Pièce déséquilibrée : débit 3 500 ≠ crédit 3 000.', $this->motif($bilan));
        $this->assertSame(0, PieceComptable::query()->count());
        $this->assertSame(0, EcritureComptable::query()->count(), 'aucune ligne orpheline');
    }

    public function test_la_tolerance_d_arrondi_est_de_un_centime(): void
    {
        $a = $this->poste('admin', 'gerante');

        $ok = $this->une($a, $this->pieceComptable(['lignes' => [
            $this->ligneEcriture('624', 100.004, 0), $this->ligneEcriture('531', 0, 100),
        ]]));
        $ko = $this->une($a, $this->pieceComptable(['lignes' => [
            $this->ligneEcriture('624', 100.5, 0), $this->ligneEcriture('531', 0, 100),
        ]]));

        $this->assertCount(1, $ok['accepted']);
        $this->assertCount(1, $ko['rejected']);
    }

    public function test_une_ligne_porte_un_debit_ou_un_credit_jamais_les_deux_ni_aucun(): void
    {
        $a = $this->poste('admin', 'gerante');

        $les_deux = $this->une($a, $this->pieceComptable(['lignes' => [
            $this->ligneEcriture('624', 100, 100), $this->ligneEcriture('531', 0, 0),
        ]]));
        $aucun = $this->une($a, $this->pieceComptable(['lignes' => [
            $this->ligneEcriture('624', 100, 0), $this->ligneEcriture('531', 0, 100), $this->ligneEcriture('531', 0, 0),
        ]]));

        $this->assertSame('Une écriture porte un débit OU un crédit, jamais les deux.', $this->motif($les_deux));
        $this->assertSame('Saisissez un montant au débit ou au crédit.', $this->motif($aucun));
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_un_montant_negatif_est_refuse(): void
    {
        $a = $this->poste('admin', 'gerante');

        $bilan = $this->une($a, $this->pieceComptable(['lignes' => [
            $this->ligneEcriture('624', -100, 0), $this->ligneEcriture('531', 0, -100),
        ]]));

        $this->assertSame('Les montants ne peuvent être négatifs.', $this->motif($bilan));
    }

    public function test_un_compte_inconnu_ou_une_piece_a_une_seule_ligne_est_refuse(): void
    {
        $a = $this->poste('admin', 'gerante');

        $inconnu = $this->une($a, $this->pieceComptable(['lignes' => [
            $this->ligneEcriture('624', 100, 0), $this->ligneEcriture('999', 0, 100),
        ]]));
        $seule = $this->une($a, $this->pieceComptable(['lignes' => [$this->ligneEcriture('624', 100, 0)]]));

        $this->assertSame('Compte inconnu du serveur : « 999 ».', $this->motif($inconnu));
        $this->assertSame('Une pièce comptable doit avoir au moins deux lignes.', $this->motif($seule));
    }

    public function test_champs_obligatoires_et_journal_inconnu(): void
    {
        $a = $this->poste('admin', 'gerante');

        $journal = $this->une($a, $this->pieceComptable(['journal_code' => 'ZZ']));
        $libelle = $this->une($a, $this->pieceComptable(['lignes' => [
            $this->ligneEcriture('624', 100, 0, ['libelle' => '']), $this->ligneEcriture('531', 0, 100),
        ]]));
        $id = $this->une($a, $this->pieceComptable(['id' => 'pas-un-uuid']));

        $this->assertSame('Le code journal est inconnu (VT, AC, CA ou OD).', $this->motif($journal));
        $this->assertSame('Le libellé est obligatoire.', $this->motif($libelle));
        $this->assertSame("L'identifiant de la pièce doit être un UUID.", $this->motif($id));
    }

    // ---------------------------------------------------------- Verrouillage

    public function test_une_piece_dans_un_exercice_cloture_est_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');
        ExerciceComptable::query()->whereKey($this->anneeComptable())->update(['is_cloture' => true]);

        $bilan = $this->une($a, $this->pieceComptable());

        $this->assertSame(
            "L'exercice {$this->anneeComptable()} est clôturé : aucune écriture ne peut y être ajoutée ni modifiée (BR-CPT-001).",
            $this->motif($bilan),
        );
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_une_piece_dans_un_mois_cloture_est_refusee_pas_dans_un_autre(): void
    {
        $a = $this->poste('admin', 'gerante');
        $annee = $this->anneeComptable();
        CloturePeriodique::query()->create([
            'id' => UuidDeterministe::cloturePeriodique($annee, 3), 'device_id' => $a['device'],
            'annee' => $annee, 'mois' => 3, 'is_cloture' => true, 'date_cloture' => now(),
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ]);

        $mars = $this->une($a, $this->pieceComptable(['date_ecriture' => $this->date(3, 10)]));
        $avril = $this->une($a, $this->pieceComptable(['date_ecriture' => $this->date(4, 10)]));

        $this->assertStringStartsWith("Le mois 3/$annee est clôturé.", $this->motif($mars));
        $this->assertCount(1, $avril['accepted']);
    }

    public function test_l_exercice_s_entend_dans_le_fuseau_de_l_exploitation(): void
    {
        $a = $this->poste('admin', 'gerante');
        $annee = $this->anneeComptable();
        // 31 decembre 23h30 UTC = 1er janvier 00h30 a Natitingou (UTC+1) : exercice annee+1.
        $instant = sprintf('%d-12-31T23:30:00.000000Z', $annee);

        $bonne = $this->une($a, $this->pieceComptable(['date_ecriture' => $instant, 'exercice_annee' => $annee + 1]));
        $fausse = $this->une($a, $this->pieceComptable(['date_ecriture' => $instant, 'exercice_annee' => $annee]));

        $this->assertCount(1, $bonne['accepted']);
        $this->assertSame(
            "L'exercice de la pièce ($annee) ne correspond pas à sa date (".($annee + 1).').',
            $this->motif($fausse),
        );
        $this->assertTrue(ExerciceComptable::query()->whereKey($annee + 1)->exists(), 'exercice ouvert a la premiere ecriture');
    }

    public function test_une_annee_hors_des_bornes_est_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');

        $bilan = $this->une($a, $this->pieceComptable([
            'date_ecriture' => '1990-06-15T10:00:00.000000Z', 'exercice_annee' => 1990,
        ]));

        $this->assertSame('Exercice 1990 hors des bornes acceptées.', $this->motif($bilan));
    }

    // ----------------------------------------------------------------- Droits

    public function test_une_ecriture_manuelle_exige_de_gerer_la_comptabilite(): void
    {
        $caissier = $this->poste('caissier');
        $comptable = $this->poste('comptable');
        $animalier = $this->poste('animalier');

        $manuelle = $this->pieceComptable(['journal_code' => 'OD']);

        $this->assertSame(
            'Droit insuffisant : une écriture manuelle exige de gérer la comptabilité.',
            $this->motif($this->une($caissier, $manuelle)),
        );
        $this->assertCount(1, $this->une($comptable, $this->pieceComptable())['accepted']);
        $this->assertSame(
            "Droit insuffisant pour écrire dans « ecriture_comptable ».",
            $this->motif($this->une($animalier, $this->pieceComptable())),
        );
    }

    public function test_une_ecriture_automatique_est_acceptee_de_celui_qui_vend_ou_achete(): void
    {
        $caissier = $this->poste('caissier');

        $vente = $this->pieceComptable(['journal_code' => 'VT', 'vente_ref' => 'V-P1-2026-001', 'numero_piece' => 'V-P1-2026-001']);
        $achat = $this->pieceComptable(['journal_code' => 'AC', 'achat_ref' => 'ACH-P1-2026-001']);

        $this->assertCount(1, $this->une($caissier, $vente)['accepted']);
        // Le caissier ne gere pas les achats.
        $this->assertSame('Droit insuffisant pour enregistrer cette écriture.', $this->motif($this->une($caissier, $achat)));
    }

    public function test_seuls_les_comptes_qui_voient_la_comptabilite_la_lisent(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->une($a, $this->pieceComptable());
        $caissier = $this->poste('caissier');
        $comptable = $this->poste('comptable');

        $this->avecJeton($caissier['jeton'])->getJson('/api/sync/pull')
            ->assertOk()->assertJsonMissingPath('tables.ecriture_comptable')
            ->assertJsonMissingPath('tables.plan_comptable');
        $r = $this->avecJeton($comptable['jeton'])->getJson('/api/sync/pull')->assertOk();

        $this->assertCount(1, $r->json('tables.ecriture_comptable'));
        $this->assertCount(2, $r->json('tables.ecriture_comptable.0.lignes'));
        $this->assertCount(24, $r->json('tables.plan_comptable'));
        $this->assertNotEmpty($r->json('tables.exercice_comptable'));
    }

    // ---------------------------------------------------------- Contrepassation

    private function inverse(array $originale, array $surcharge = []): array
    {
        return $this->pieceComptable(array_merge([
            'numero_piece' => 'ANN-'.$originale['numero_piece'],
            'journal_code' => 'OD',
            'contrepasse_de' => $originale['id'],
            'lignes' => [
                $this->ligneEcriture('624', 0, 3500),
                $this->ligneEcriture('531', 3500, 0),
            ],
        ], $surcharge));
    }

    public function test_une_contrepassation_reprend_la_piece_ligne_pour_ligne(): void
    {
        $a = $this->poste('admin', 'gerante');
        $originale = $this->pieceComptable();
        $this->une($a, $originale);

        $bilan = $this->une($a, $this->inverse($originale));

        $this->assertCount(1, $bilan['accepted']);
        $this->assertSame(0.0, round(EcritureComptable::query()->sum('debit') - EcritureComptable::query()->sum('credit'), 2));
    }

    public function test_une_contrepassation_qui_ne_reprend_pas_la_piece_est_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');
        $originale = $this->pieceComptable();
        $this->une($a, $originale);

        $autre = $this->une($a, $this->inverse($originale, ['lignes' => [
            $this->ligneEcriture('622', 0, 3500), $this->ligneEcriture('531', 3500, 0),
        ]]));
        $montant = $this->une($a, $this->inverse($originale, ['lignes' => [
            $this->ligneEcriture('624', 0, 3000), $this->ligneEcriture('531', 3000, 0),
        ]]));

        $m = "L'écriture d'annulation ne reprend pas la pièce annulée, ligne pour ligne.";
        $this->assertSame($m, $this->motif($autre));
        $this->assertSame($m, $this->motif($montant));
    }

    public function test_on_n_annule_qu_une_fois_et_une_annulation_ne_s_annule_pas(): void
    {
        $a = $this->poste('admin', 'gerante');
        $originale = $this->pieceComptable();
        $this->une($a, $originale);
        $annulation = $this->inverse($originale);
        $this->une($a, $annulation);

        $deux = $this->une($a, $this->inverse($originale, ['numero_piece' => 'ANN-bis']));
        $sur = $this->une($a, $this->pieceComptable([
            'contrepasse_de' => $annulation['id'],
            'lignes' => [$this->ligneEcriture('624', 3500, 0), $this->ligneEcriture('531', 0, 3500)],
        ]));

        $this->assertSame('Cette pièce est déjà annulée.', $this->motif($deux));
        $this->assertSame("Une écriture d'annulation ne s'annule pas : saisissez une nouvelle écriture.", $this->motif($sur));
    }

    public function test_annuler_une_piece_inconnue_est_refuse(): void
    {
        $a = $this->poste('admin', 'gerante');

        $bilan = $this->une($a, $this->inverse(['id' => (string) Str::uuid(), 'numero_piece' => 'X']));

        $this->assertSame("Pièce annulée inconnue du serveur : elle doit être transmise d'abord.", $this->motif($bilan));
    }

    // ------------------------------------------------- Aucun effet comptable cache

    public function test_le_serveur_n_engendre_aucune_ecriture_a_partir_d_une_vente(): void
    {
        $poste = $this->poste('admin', 'gerante');
        $produit = $this->produitConnu($poste);

        $bilan = $this->pousserTable($poste, 'ventes', [$this->ligneVente($produit)]);

        $this->assertCount(1, $bilan['accepted']);
        $this->assertSame(0, PieceComptable::query()->count(), 'la piece de la vente arrive comme SON propre fait');
        $this->assertSame(0, EcritureComptable::query()->count());
    }

    // --------------------------------------------------------- Clotures mensuelles

    private function cloture(int $mois, bool $clos = true, array $surcharge = []): array
    {
        $annee = $this->anneeComptable();

        return array_merge([
            'id' => UuidDeterministe::cloturePeriodique($annee, $mois),
            'annee' => $annee,
            'mois' => $mois,
            'is_cloture' => $clos,
            'date_cloture' => $clos ? now()->format('Y-m-d\TH:i:s.u\Z') : null,
            'decloture_par' => $clos ? null : 'gerante',
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    public function test_cloturer_un_mois_verrouille_les_ecritures_de_ce_mois_pour_tous(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('comptable');

        $bilan = $this->pousserTable($a, 'clotures_periodiques', [$this->cloture(3)]);
        $refus = $this->une($b, $this->pieceComptable(['date_ecriture' => $this->date(3, 20)]));

        $this->assertCount(1, $bilan['accepted']);
        $this->assertStringContainsString('est clôturé', $this->motif($refus));
    }

    public function test_declôturer_est_reserve_a_l_administratrice(): void
    {
        $admin = $this->poste('admin', 'gerante');
        $comptable = $this->poste('comptable');
        $this->pousserTable($comptable, 'clotures_periodiques', [$this->cloture(3)]);

        $refus = $this->pousserTable($comptable, 'clotures_periodiques', [
            $this->cloture(3, false, ['updated_at' => now()->addSecond()->format('Y-m-d\TH:i:s.u\Z')]),
        ]);
        $this->assertSame('Seule une administratrice peut déclôturer un mois (BR-CPT-006).', $this->motif($refus));
        $this->assertTrue(CloturePeriodique::query()->first()->is_cloture);

        $ok = $this->pousserTable($admin, 'clotures_periodiques', [
            $this->cloture(3, false, ['updated_at' => now()->addSeconds(2)->format('Y-m-d\TH:i:s.u\Z')]),
        ]);
        $this->assertCount(1, $ok['accepted']);
        $this->assertFalse(CloturePeriodique::query()->first()->is_cloture);
    }

    public function test_une_cloture_plus_ancienne_est_acceptee_sans_rien_changer(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->pousserTable($a, 'clotures_periodiques', [$this->cloture(3)]);

        $bilan = $this->pousserTable($a, 'clotures_periodiques', [
            $this->cloture(3, false, ['updated_at' => now()->subDay()->format('Y-m-d\TH:i:s.u\Z')]),
        ]);

        $this->assertCount(1, $bilan['accepted']);
        $this->assertTrue(CloturePeriodique::query()->first()->is_cloture);
    }

    public function test_une_cloture_dont_l_identifiant_ne_designe_pas_le_mois_est_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');

        $bilan = $this->pousserTable($a, 'clotures_periodiques', [
            $this->cloture(3, true, ['id' => (string) Str::uuid()]),
        ]);

        $this->assertSame("L'identifiant de la clôture ne désigne pas le mois 3/{$this->anneeComptable()}.", $this->motif($bilan));
    }

    public function test_une_cloture_exige_une_date_et_un_mois_valide(): void
    {
        $a = $this->poste('admin', 'gerante');

        $sans_date = $this->pousserTable($a, 'clotures_periodiques', [$this->cloture(3, true, ['date_cloture' => null])]);
        $mois = $this->pousserTable($a, 'clotures_periodiques', [$this->cloture(13)]);

        $this->assertSame('La date de clôture est obligatoire.', $this->motif($sans_date));
        $this->assertSame('Le mois va de 1 à 12.', $this->motif($mois));
    }

    public function test_une_cloture_sur_balance_desequilibree_est_refusee(): void
    {
        $a = $this->poste('admin', 'gerante');
        $piece = $this->pieceComptable();
        $this->une($a, $piece);
        // Corruption directe (impossible par le fil) : le serveur contrôle quand même.
        EcritureComptable::query()->where('numero_compte', '531')->update(['credit' => 10]);

        $bilan = $this->pousserTable($a, 'clotures_periodiques', [$this->cloture(3)]);

        $this->assertStringStartsWith('Balance déséquilibrée', $this->motif($bilan));
        $this->assertSame(0, CloturePeriodique::query()->count());
    }

    public function test_un_mois_d_un_exercice_cloture_ne_bouge_plus(): void
    {
        $a = $this->poste('admin', 'gerante');
        ExerciceComptable::query()->whereKey($this->anneeComptable())->update(['is_cloture' => true]);

        $bilan = $this->pousserTable($a, 'clotures_periodiques', [$this->cloture(3)]);

        $this->assertStringContainsString('ses mois ne bougent plus', $this->motif($bilan));
    }

    // ---------------------------------------------------------- Cloture annuelle

    private function clotureExercice(array $surcharge = []): array
    {
        return array_merge([
            'id' => UuidDeterministe::clotureExercice($this->anneeComptable()),
            'annee' => $this->anneeComptable(),
            'date_cloture' => now()->format('Y-m-d\TH:i:s.u\Z'),
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    public function test_l_administratrice_cloture_l_exercice_qui_ouvre_le_suivant(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->une($a, $this->pieceComptable());
        $annee = $this->anneeComptable();

        $bilan = $this->pousserTable($a, 'clotures_exercice', [$this->clotureExercice()]);

        $this->assertCount(1, $bilan['accepted']);
        $e = ExerciceComptable::query()->find($annee);
        $this->assertTrue($e->is_cloture);
        $this->assertSame($a['utilisateur']->getKey(), $e->cloture_par);
        $this->assertFalse(ExerciceComptable::query()->find($annee + 1)->is_cloture);
        $fait = ClotureExercice::query()->find(UuidDeterministe::clotureExercice($annee));
        $this->assertSame($a['device'], $fait->device_id);
        $this->assertDatabaseHas('audit_logs', ['action' => 'comptabilite.cloture_exercice']);
    }

    public function test_la_cloture_d_un_poste_fait_engendrer_cl_et_an_par_le_serveur_et_les_sert_aux_autres(): void
    {
        $a = $this->poste('admin', 'gerante');
        $annee = $this->anneeComptable();
        $this->une($a, $this->pieceComptable(['lignes' => [$this->ligneEcriture('531', 1000, 0), $this->ligneEcriture('701', 0, 1000)]]));

        $fait = $this->clotureExercice(['affectation' => ['reserve_legale' => 100, 'dividendes' => 400, 'autres_reserves' => 0]]);
        $this->assertCount(1, $this->pousserTable($a, 'clotures_exercice', [$fait])['accepted']);

        // Resultat 1 000 : reserve 100, dividendes 400, report a nouveau 500. A-nouveaux : 531 D 1 000 = 111 100 + 465 400 + 121 500.
        $an = EcritureComptable::query()->whereHas('piece', fn ($q) => $q->where('journal_code', 'AN'))->get();
        $this->assertEqualsCanonicalizing(['531', '111', '465', '121'], $an->pluck('numero_compte')->all());
        $this->assertEquals(1000.0, (float) $an->sum('debit'));
        $this->assertEquals(1000.0, (float) $an->sum('credit'));
        $this->assertSame(['reserve_legale' => 100, 'autres_reserves' => 0, 'dividendes' => 400], json_decode(ExerciceComptable::query()->find($annee)->affectation, true));

        // Un autre poste les recoit, avec l'exercice clos : jamais ecrites par lui, servies par le serveur.
        $comptable = $this->poste('comptable');
        $r = $this->avecJeton($comptable['jeton'])->getJson('/api/sync/pull')->assertOk();
        $journaux = collect($r->json('tables.ecriture_comptable'))->pluck('journal_code')->unique()->all();
        $this->assertEqualsCanonicalizing(['AN', 'CA', 'CL'], $journaux);

        // Reouverture par le web : l'exercice est servi ouvert, DATE (`rouvert_le`), sans CL ni AN.
        $motif = (new \App\Sync\Tables\ClotureExerciceTable)->pourUtilisateur($a['utilisateur'])->rouvrir($annee);
        $this->assertNull($motif);
        $r = $this->avecJeton($comptable['jeton'])->getJson('/api/sync/pull?complet=1')->assertOk();
        $exercice = collect($r->json('tables.exercice_comptable'))->firstWhere('annee', $annee);
        $this->assertFalse($exercice['is_cloture']);
        $this->assertNotNull($exercice['rouvert_le']);
        $this->assertSame([], collect($r->json('tables.ecriture_comptable'))->whereIn('journal_code', ['CL', 'AN'])->all());
    }

    public function test_seule_l_administratrice_cloture_un_exercice(): void
    {
        $comptable = $this->poste('comptable');
        $caissier = $this->poste('caissier');

        $c = $this->pousserTable($comptable, 'clotures_exercice', [$this->clotureExercice()]);
        $k = $this->pousserTable($caissier, 'clotures_exercice', [$this->clotureExercice()]);

        $this->assertSame('Droit insuffisant pour écrire dans « clotures_exercice ».', $this->motif($c));
        $this->assertSame('Droit insuffisant pour écrire dans « clotures_exercice ».', $this->motif($k));
        $this->assertFalse(ExerciceComptable::query()->find($this->anneeComptable())->is_cloture);
    }

    public function test_une_cloture_sur_balance_desequilibree_est_refusee_et_l_exercice_reste_ouvert(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->une($a, $this->pieceComptable());
        EcritureComptable::query()->where('numero_compte', '531')->update(['credit' => 3000]);

        $bilan = $this->pousserTable($a, 'clotures_exercice', [$this->clotureExercice()]);

        $this->assertStringStartsWith('Balance déséquilibrée de 500 FCFA', $this->motif($bilan));
        $this->assertFalse(ExerciceComptable::query()->find($this->anneeComptable())->is_cloture);
        $this->assertSame(0, ClotureExercice::query()->count());
    }

    public function test_cloturer_deux_fois_est_accepte_sans_rien_changer(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->pousserTable($a, 'clotures_exercice', [$this->clotureExercice()]);
        $date = ExerciceComptable::query()->find($this->anneeComptable())->date_cloture;

        $bilan = $this->pousserTable($a, 'clotures_exercice', [
            $this->clotureExercice(['date_cloture' => now()->addDay()->format('Y-m-d\TH:i:s.u\Z')]),
        ]);

        $this->assertCount(1, $bilan['accepted']);
        $this->assertEquals($date, ExerciceComptable::query()->find($this->anneeComptable())->date_cloture);
        $this->assertSame(1, ClotureExercice::query()->count());
    }

    public function test_apres_la_cloture_une_ecriture_hors_ligne_de_cet_exercice_est_refusee_avec_son_motif(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('comptable');
        $this->pousserTable($a, 'clotures_exercice', [$this->clotureExercice()]);

        $bilan = $this->une($b, $this->pieceComptable());

        $this->assertStringContainsString('est clôturé', $this->motif($bilan));
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_les_pieces_sont_recues_avant_la_cloture_quel_que_soit_l_ordre_du_lot(): void
    {
        $a = $this->poste('admin', 'gerante');
        $piece = $this->pieceComptable();

        // La cloture est ECRITE AVANT les pieces dans le lot ; le serveur suit l'ordre des tables.
        $reponse = $this->avecJeton($a['jeton'])->postJson('/api/sync/push', [
            'device_id' => $a['device'],
            'reset_mark' => 'initiale',
            'tables' => [
                'clotures_exercice' => [$this->clotureExercice()],
                'ecriture_comptable' => [$piece],
            ],
        ])->assertOk();

        $this->assertSame([$piece['id']], $reponse->json('ecriture_comptable.accepted'));
        $this->assertCount(1, $reponse->json('clotures_exercice.accepted'));
        $this->assertTrue(ExerciceComptable::query()->find($this->anneeComptable())->is_cloture);
    }

    public function test_la_cloture_n_est_jamais_servie_comme_un_fait_mais_l_exercice_clos_oui(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->pousserTable($a, 'clotures_exercice', [$this->clotureExercice()]);

        $r = $this->avecJeton($a['jeton'])->getJson('/api/sync/pull')->assertOk();

        $r->assertJsonMissingPath('tables.clotures_exercice');
        $exercices = collect($r->json('tables.exercice_comptable'))->keyBy('annee');
        $this->assertTrue($exercices[$this->anneeComptable()]['is_cloture']);
        $this->assertArrayNotHasKey('cloture_par', $exercices[$this->anneeComptable()]);
        $this->assertFalse($exercices[$this->anneeComptable() + 1]['is_cloture']);
    }

    public function test_un_poste_ne_peut_pas_ecrire_un_exercice_comme_un_referentiel(): void
    {
        $a = $this->poste('admin', 'gerante');

        $bilan = $this->pousserTable($a, 'exercice_comptable', [[
            'annee' => $this->anneeComptable(), 'is_cloture' => true,
        ]]);

        $this->assertSame([], $bilan['accepted']);
        $this->assertCount(1, $bilan['ignored']);
        $this->assertFalse(ExerciceComptable::query()->find($this->anneeComptable())->is_cloture);
    }

    // ----------------------------------------------------------------- Notes

    private function note(int $numero = 1, string $contenu = 'Coût historique', array $surcharge = []): array
    {
        $annee = $this->anneeComptable();

        return array_merge([
            'id' => UuidDeterministe::note($annee, $numero),
            'exercice_annee' => $annee,
            'numero_note' => $numero,
            'titre' => 'Méthodes Comptables',
            'contenu' => $contenu,
            'updated_at' => now()->format('Y-m-d\TH:i:s.u\Z'),
        ], $surcharge);
    }

    public function test_une_note_est_creee_puis_la_plus_recente_gagne(): void
    {
        $a = $this->poste('admin', 'gerante');
        $this->pousserTable($a, 'notes_annexes', [$this->note(1, 'Version A')]);

        $recente = $this->pousserTable($a, 'notes_annexes', [
            $this->note(1, 'Version B', ['updated_at' => now()->addSecond()->format('Y-m-d\TH:i:s.u\Z')]),
        ]);
        $ancienne = $this->pousserTable($a, 'notes_annexes', [
            $this->note(1, 'Version C', ['updated_at' => now()->subDay()->format('Y-m-d\TH:i:s.u\Z')]),
        ]);

        $this->assertCount(1, $recente['accepted']);
        $this->assertCount(1, $ancienne['accepted'], 'une saisie plus ancienne est acceptee sans rien changer');
        $this->assertSame(1, NoteAnnexe::query()->count());
        $this->assertSame('Version B', NoteAnnexe::query()->first()->contenu);
    }

    public function test_une_note_a_un_identifiant_deterministe_et_un_numero_de_1_a_5(): void
    {
        $a = $this->poste('admin', 'gerante');

        $id = $this->pousserTable($a, 'notes_annexes', [$this->note(1, 'x', ['id' => (string) Str::uuid()])]);
        $numero = $this->pousserTable($a, 'notes_annexes', [$this->note(6)]);
        $titre = $this->pousserTable($a, 'notes_annexes', [$this->note(2, 'x', ['titre' => ''])]);

        $this->assertStringStartsWith("L'identifiant de la note ne désigne pas la note 1", $this->motif($id));
        $this->assertSame('Le numéro de note va de 1 à 5.', $this->motif($numero));
        $this->assertSame('Le titre de la note est obligatoire.', $this->motif($titre));
    }

    public function test_une_note_peut_avoir_un_contenu_vide(): void
    {
        $a = $this->poste('admin', 'gerante');

        $bilan = $this->pousserTable($a, 'notes_annexes', [$this->note(3, '')]);

        $this->assertCount(1, $bilan['accepted']);
        $this->assertSame('', NoteAnnexe::query()->first()->contenu);
    }

    public function test_les_notes_exigent_le_droit_de_gerer_la_comptabilite(): void
    {
        $caissier = $this->poste('caissier');

        $bilan = $this->pousserTable($caissier, 'notes_annexes', [$this->note()]);

        $this->assertSame('Droit insuffisant pour écrire dans « notes_annexes ».', $this->motif($bilan));
    }

    // -------------------------------------------------------- Deux postes

    public function test_deux_postes_voient_les_memes_faits_et_les_memes_totaux(): void
    {
        $a = $this->poste('admin', 'gerante');
        $b = $this->poste('comptable');
        $pa = $this->pieceComptable([], 3500);
        $pb = $this->pieceComptable(['numero_piece' => 'DEP-P2-'.$this->anneeComptable().'-0001'], 1200);
        $this->une($a, $pa);
        $this->une($b, $pb);

        $ra = $this->avecJeton($a['jeton'])->getJson('/api/sync/pull')->json('tables.ecriture_comptable');
        $rb = $this->avecJeton($b['jeton'])->getJson('/api/sync/pull')->json('tables.ecriture_comptable');

        $this->assertEqualsCanonicalizing(array_column($ra, 'id'), array_column($rb, 'id'));
        $this->assertCount(2, $ra);
        $devices = collect($ra)->pluck('device_id', 'id');
        $this->assertSame($a['device'], $devices[$pa['id']]);
        $this->assertSame($b['device'], $devices[$pb['id']]);
        $total = collect($ra)->flatMap(fn ($p) => $p['lignes'])->sum('debit');
        $this->assertSame(4700.0, (float) $total);
    }

    public function test_remise_a_zero_efface_ecritures_notes_clotures_rouvre_les_exercices_garde_le_plan(): void
    {
        config(['logialvia.remise_a_zero.activee' => true]);
        $admin = $this->poste('admin', 'gerante');
        $this->une($admin, $this->pieceComptable());
        $this->pousserTable($admin, 'notes_annexes', [$this->note()]);
        $this->pousserTable($admin, 'clotures_periodiques', [$this->cloture(2)]);
        $this->pousserTable($admin, 'clotures_exercice', [$this->clotureExercice()]);
        $this->assertTrue(ExerciceComptable::query()->find($this->anneeComptable())->is_cloture);

        $this->avecJeton($admin['jeton'])->postJson('/api/parametres/remise-a-zero', ['confirmation' => 'REMETTRE A ZERO'])->assertOk();

        $this->assertSame(0, PieceComptable::query()->count());
        $this->assertSame(0, EcritureComptable::query()->count());
        $this->assertSame(0, NoteAnnexe::query()->count());
        $this->assertSame(0, CloturePeriodique::query()->count());
        $this->assertSame(0, ClotureExercice::query()->count());
        $this->assertFalse(ExerciceComptable::query()->find($this->anneeComptable())->is_cloture);
        $this->assertSame(24, \App\Models\PlanComptable::query()->count());
    }
}
