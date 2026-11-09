<?php

namespace Tests\Feature\Web;

use App\Livewire\Achats;
use App\Livewire\Catalogue;
use App\Livewire\Fournisseurs;
use App\Models\Achat;
use App\Models\EcritureComptable;
use App\Models\ExerciceComptable;
use App\Models\Fournisseur;
use App\Models\Intrant;
use App\Models\MouvementIntrant;
use App\Models\PieceComptable;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Concerns\JeuComptable;
use Tests\Concerns\LitXlsx;
use Tests\TestCase;

/**
 * Achats & Commandes, Fournisseurs : PARITE avec le poste (commande, modification, reception, reglement,
 * annulation) et ecritures SYSCOHADA chiffrees A LA MAIN.
 *
 * Jeu : 100 Maïs (Intrants Provende) × 300 = 30 000 ; 10 Vaccin (Vétérinaire) × 500 = 5 000 ;
 * 4 Sel (Marchandises) × 1 250 = 5 000. Total 40 000, 15 000 payes en Espèces.
 *   Piece d'achat : D 601 30 000, D 622 5 000, D 602 5 000 / C 531 15 000, C 401 25 000 (40 000 = 40 000).
 *   Reglement 10 000 Mobile Money : D 401 10 000 / C 512 10 000 → reste du 15 000 = solde 401.
 */
class AchatsOperationsWebTest extends TestCase
{
    use JeuComptable, LitXlsx, RefreshDatabase;

    private Fournisseur $fournisseur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerPourLesEcrans();
        foreach ([['INT-001', 'Maïs', 'Intrants Provende'], ['INT-002', 'Vaccin', 'Vétérinaire'], ['INT-003', 'Sel', 'Marchandises']] as [$code, $nom, $cat]) {
            (new Intrant)->forceFill(['code' => $code, 'name' => $nom, 'cat' => $cat, 'unit' => 'kg', 'threshold' => 10, 'saisi_le' => now()])->save();
        }
        $this->fournisseur = (new Fournisseur)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => 'Agri Plus',
            'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ]);
        $this->fournisseur->save();
    }

    private ?User $admin = null;

    private function admin(): User
    {
        return $this->admin ??= $this->utilisateurAvecRole('admin', 'gerante');
    }

    private function panier(): array
    {
        return [
            ['intrant_code' => 'INT-001', 'qte' => '100', 'pu' => '300'],
            ['intrant_code' => 'INT-002', 'qte' => '10', 'pu' => '500'],
            ['intrant_code' => 'INT-003', 'qte' => '4', 'pu' => '1250'],
        ];
    }

    /** Ouvre le formulaire, le remplit et valide. */
    private function commander(array $valeurs = [], ?User $u = null)
    {
        $valeurs = array_merge([
            'fournisseurId' => $this->fournisseur->id, 'mode' => 'Espèces', 'paye' => '15000', 'echeance' => '',
            'livree' => true, 'lignes' => $this->panier(),
        ], $valeurs);
        $c = Livewire::actingAs($u ?? $this->admin())->test(Achats::class)->call('nouveau');
        foreach ($valeurs as $champ => $valeur) {
            $c->set($champ, $valeur);
        }

        return $c->call('enregistrer');
    }

    /** Solde net (debit − credit) par compte des pieces VIVANTES d'un achat, annulations comprises. */
    private function net(string $reference): array
    {
        $net = [];
        $ids = PieceComptable::query()->where('achat_ref', $reference)->pluck('id');
        foreach (EcritureComptable::query()->whereIn('piece_id', $ids)->get() as $l) {
            $net[$l->numero_compte] = round(($net[$l->numero_compte] ?? 0) + $l->debit - $l->credit, 2);
        }

        return array_filter($net, fn ($v) => $v != 0);
    }

    private function achat(string $reference = null): Achat
    {
        return Achat::query()->with('lignes')->when($reference, fn ($q) => $q->where('reference', $reference))->firstOrFail();
    }

    private function reference(int $n = 1): string
    {
        return sprintf('ACH-WEB-%d-%03d', $this->annee(), $n);
    }

    // ----------------------------------------------------------------- Droits

    public function test_chaque_methode_d_ecriture_exige_manage_achats(): void
    {
        $this->commander();
        $a = $this->achat();
        $avant = [Achat::query()->count(), PieceComptable::query()->count(), MouvementIntrant::query()->count()];
        $comptable = $this->utilisateurAvecRole('comptable', 'paul');

        foreach ([
            'nouveau' => [], 'modifier' => [$a->id], 'ajouterIntrant' => [], 'retirerLigne' => [0], 'enregistrer' => [],
            'demanderReception' => [$a->id], 'confirmerReception' => [], 'demanderAnnulation' => [$a->id], 'confirmerAnnulation' => [],
            'demanderReglement' => [$a->id], 'confirmerReglement' => [],
        ] as $methode => $args) {
            Livewire::actingAs($comptable)->test(Achats::class)->call($methode, ...$args)->assertForbidden();
        }
        foreach (['demanderReglement' => [$a->id], 'confirmerReglement' => []] as $methode => $args) {
            Livewire::actingAs($comptable)->test(Fournisseurs::class)->call($methode, ...$args)->assertForbidden();
        }
        $this->assertSame($avant, [Achat::query()->count(), PieceComptable::query()->count(), MouvementIntrant::query()->count()]);
    }

    public function test_un_caissier_n_ouvre_aucune_page_ni_vue_imprimable(): void
    {
        $this->commander();
        $a = $this->achat();
        $caissier = $this->utilisateurAvecRole('caissier', 'amina');
        foreach (['/achats', '/achats/impression', '/achats/'.$a->id.'/bon', '/fournisseurs/'.$this->fournisseur->id.'/releve', '/fournisseurs/impression', '/stocks/impression', '/depenses/impression'] as $url) {
            $this->actingAs($caissier)->get($url)->assertForbidden();
        }
        auth()->logout();
        $this->get('/achats/'.$a->id.'/bon')->assertRedirect('/login');
    }

    // --------------------------------------------------------------- Validation

    public function test_chaque_regle_de_validation_a_son_message_et_n_ecrit_rien(): void
    {
        $cas = [
            'Le panier d\'achat est vide.' => ['lignes' => []],
            'Sélectionnez un fournisseur.' => ['fournisseurId' => ''],
            'Ce fournisseur n\'existe plus.' => ['fournisseurId' => (string) Str::uuid()],
            'Le montant réglé ne peut être négatif.' => ['paye' => '-1'],
            'Le mode de règlement est inconnu.' => ['mode' => 'Chèque'],
            'Chaque ligne doit avoir un prix unitaire positif.' => ['lignes' => [['intrant_code' => 'INT-001', 'qte' => '1', 'pu' => '0']]],
            'La quantité de chaque ligne doit être un entier supérieur à 0.' => ['lignes' => [['intrant_code' => 'INT-001', 'qte' => '2,5', 'pu' => '10']]],
            'Intrant inconnu : « INT-999 ».' => ['lignes' => [['intrant_code' => 'INT-999', 'qte' => '1', 'pu' => '10']]],
            'L\'intrant « Maïs » figure deux fois dans la commande.' => ['lignes' => [['intrant_code' => 'INT-001', 'qte' => '1', 'pu' => '10'], ['intrant_code' => 'INT-001', 'qte' => '1', 'pu' => '10']]],
            'La date d\'échéance est invalide.' => ['echeance' => '2026-13-45'],
            'L\'échéance ne peut précéder la date de la commande.' => ['echeance' => now()->subDay()->format('Y-m-d')],
        ];
        foreach ($cas as $message => $surcharge) {
            $this->commander($surcharge)->assertSet('erreur', $message)->assertSet('formulaire', true);
        }
        $this->assertSame(0, Achat::query()->count());
        $this->assertSame(0, PieceComptable::query()->where('numero_piece', 'like', 'ACH-WEB%')->count());
        $this->assertSame(0, MouvementIntrant::query()->count());
    }

    // ----------------------------------------------------------------- Commande

    public function test_une_commande_livree_ecrit_l_achat_ses_lignes_la_piece_et_le_journal(): void
    {
        $this->commander()->assertSet('formulaire', false)->assertSet('erreur', null)
            ->assertSee('Commande '.$this->reference().' enregistrée.')
            ->assertSee('le stock et le PMP restent propres à chaque poste');

        $a = $this->achat();
        $this->assertSame($this->reference(), $a->reference);
        $this->assertSame(Catalogue::POSTE_WEB, $a->device_id);
        $this->assertSame('', $a->portee_reference);
        $this->assertSame('Livré', $a->statut);
        $this->assertEquals(40000.0, $a->total);
        $this->assertEquals(15000.0, $a->paye);
        $this->assertSame('Espèces', $a->mode);
        $this->assertNotNull($a->serveur_modifie_le, 'les postes la recevront au prochain tirage');
        $this->assertCount(3, $a->lignes);

        // Piece d'achat : ventilation 601 / 622 / 602, tresorerie 531, dette 401 ; D = C = 40 000.
        $piece = PieceComptable::query()->with('lignes')->where('achat_ref', $this->reference())->sole();
        $this->assertSame('AC', $piece->journal_code);
        $this->assertSame($this->reference(), $piece->numero_piece);
        $this->assertSame(Catalogue::POSTE_WEB, $piece->device_id);
        $this->assertEqualsCanonicalizing(
            ['601:30000:0', '622:5000:0', '602:5000:0', '531:0:15000', '401:0:25000'],
            $piece->lignes->map(fn ($l) => $l->numero_compte.':'.(int) $l->debit.':'.(int) $l->credit)->all(),
        );
        $this->assertEquals(40000.0, $piece->lignes->sum('debit'));
        $this->assertEquals(40000.0, $piece->lignes->sum('credit'));
        $this->assertSame('Achat '.$this->reference(), $piece->lignes->firstWhere('numero_compte', '601')->libelle);
        $this->assertSame('Règlement achat '.$this->reference(), $piece->lignes->firstWhere('numero_compte', '531')->libelle);
        $this->assertSame('Dette fournisseur — achat '.$this->reference(), $piece->lignes->firstWhere('numero_compte', '401')->libelle);

        // Reception immediate : une Entree par ligne au journal partage, poste d'origine web.
        $mouvements = MouvementIntrant::query()->orderBy('intrant_code')->get();
        $this->assertCount(3, $mouvements);
        $this->assertSame(['Entrée', 'Entrée', 'Entrée'], $mouvements->pluck('type')->all());
        $this->assertEquals([100.0, 10.0, 4.0], $mouvements->pluck('quantite')->all());
        $this->assertSame(['Réception commande '.$this->reference()], $mouvements->pluck('motif')->unique()->all());
        $this->assertSame([Catalogue::POSTE_WEB], $mouvements->pluck('device_id')->unique()->all());
        $this->assertSame(1, PieceComptable::query()->where('achat_ref', $this->reference())->count(), 'la reception n\'ecrit aucune piece');
    }

    public function test_une_commande_en_attente_n_ecrit_pas_de_mouvement_mais_la_charge_est_constatee(): void
    {
        $this->commander(['livree' => false, 'paye' => ''])->assertSee('Commande '.$this->reference().' enregistrée.');

        $this->assertSame('Commandé', $this->achat()->statut);
        $this->assertSame(0, MouvementIntrant::query()->count());
        // Comme le poste : la charge est constatee a la commande. Rien paye : toute la dette en 401.
        $this->assertEquals(['401' => -40000.0, '602' => 5000.0, '601' => 30000.0, '622' => 5000.0], $this->net($this->reference()));
        $this->assertEquals(-40000.0, $this->net($this->reference())['401']);
        $this->assertArrayNotHasKey('531', $this->net($this->reference()));
    }

    public function test_les_references_web_se_suivent_et_ne_sont_jamais_reutilisees(): void
    {
        $this->commander();
        $this->commander();
        $this->assertEqualsCanonicalizing([$this->reference(1), $this->reference(2)], Achat::query()->pluck('reference')->all());
        // Annuler la 2e ne libere pas son numero.
        $b = $this->achat($this->reference(2));
        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderAnnulation', $b->id)->set('motifAnnulation', 'Erreur')->call('confirmerAnnulation');
        $this->commander();
        $this->assertContains($this->reference(3), Achat::query()->pluck('reference')->all());
    }

    public function test_le_mode_mobile_money_ecrit_le_compte_512_et_credit_le_531_comme_le_poste(): void
    {
        $this->commander(['mode' => 'Mobile Money', 'paye' => '40000']);
        $this->assertEquals(['601' => 30000.0, '622' => 5000.0, '602' => 5000.0, '512' => -40000.0], $this->net($this->reference()));

        $this->commander(['mode' => 'Crédit', 'paye' => '1000']);
        $this->assertEquals(-1000.0, $this->net($this->reference(2))['531'], 'Crédit : la part payee passe en caisse, comme le Dart');
        $this->assertSame('Crédit', $this->achat($this->reference(2))->mode);
    }

    public function test_un_montant_regle_superieur_au_total_est_borne_au_total(): void
    {
        $this->commander(['paye' => '99999999', 'livree' => false]);
        $this->assertEquals(40000.0, $this->achat()->paye);
        $this->assertArrayNotHasKey('401', $this->net($this->reference()));
    }

    public function test_une_echeance_est_enregistree_et_visible(): void
    {
        $echeance = now(config('logialvia.fuseau'))->addDays(30)->format('Y-m-d');
        $this->commander(['echeance' => $echeance, 'livree' => false]);

        $a = $this->achat();
        $this->assertSame($echeance, $a->echeance->timezone(config('logialvia.fuseau'))->format('Y-m-d'));
        Livewire::actingAs($this->admin())->test(Achats::class)->call('basculer', $a->id)
            ->assertSeeHtml('data-echeance')->assertSee('Échéance : '.now(config('logialvia.fuseau'))->addDays(30)->format('d/m/Y'));
    }

    public function test_le_prix_a_deux_decimales_ne_desequilibre_pas_la_piece(): void
    {
        $this->commander(['livree' => false, 'paye' => '0.1', 'lignes' => [['intrant_code' => 'INT-001', 'qte' => '3', 'pu' => '33.33']]])->assertSet('erreur', null);

        $this->assertEquals(99.99, $this->achat()->total);
        $this->assertEquals(['601' => 99.99, '401' => -99.89, '531' => -0.1], $this->net($this->reference()));
    }

    public function test_un_mois_cloture_refuse_la_commande_et_ne_laisse_aucune_trace(): void
    {
        ExerciceComptable::query()->firstOrCreate(['annee' => $this->annee()], ['is_cloture' => false]);
        ExerciceComptable::query()->whereKey($this->annee())->update(['is_cloture' => true]);

        $this->commander()->assertSet('formulaire', true)->assertSee('clôturé', false);

        $this->assertSame(0, Achat::query()->count(), 'l\'achat est annule avec la piece refusee');
        $this->assertSame(0, \App\Models\LigneAchat::query()->count());
        $this->assertSame(0, MouvementIntrant::query()->count());
    }

    // ---------------------------------------------------------------- Reception

    public function test_receptionner_une_commande_inscrit_les_entrees_sans_toucher_aux_ecritures(): void
    {
        $this->commander(['livree' => false]);
        $a = $this->achat();
        $pieces = PieceComptable::query()->count();

        Livewire::actingAs($this->admin())->test(Achats::class)
            ->call('demanderReception', $a->id)->assertSeeHtml('data-modale="reception"')->assertSee('Le stock et le PMP ne sont pas modifiés')
            ->call('confirmerReception')->assertSee('réceptionnée : entrées inscrites au journal');

        $this->assertSame('Livré', $this->achat()->statut);
        $this->assertSame(3, MouvementIntrant::query()->where('type', 'Entrée')->where('reference', $a->reference)->count());
        $this->assertSame($pieces, PieceComptable::query()->count());
        $this->assertTrue($this->achat()->updated_at->greaterThan($a->updated_at), 'saisie plus recente : le poste d\'origine la recevra');
    }

    public function test_une_commande_deja_livree_ou_annulee_ne_se_receptionne_pas_et_rien_n_est_ecrit_deux_fois(): void
    {
        $this->commander();
        $a = $this->achat();
        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderReception', $a->id)->call('confirmerReception')
            ->assertSet('erreur', 'Cette commande n\'est pas en attente de livraison.');
        $this->assertSame(3, MouvementIntrant::query()->count());
    }

    // ----------------------------------------------------------------- Reglement

    public function test_un_reglement_partiel_en_mobile_money_ecrit_401_contre_512(): void
    {
        $this->commander();
        $a = $this->achat();

        Livewire::actingAs($this->admin())->test(Achats::class)
            ->call('demanderReglement', $a->id)->assertSeeHtml('data-modale="reglement"')->assertSeeHtml('data-reste-du')->assertSee('25 000 FCFA')
            ->set('montantReglement', '10000')->set('modeReglement', 'Mobile Money')->call('confirmerReglement')
            ->assertSet('aRegler', null)->assertSee('Règlement de 10 000 FCFA enregistré');

        $this->assertEquals(25000.0, $this->achat()->paye);
        $piece = PieceComptable::query()->with('lignes')->where('numero_piece', 'REG-'.$a->reference)->sole();
        $this->assertSame('CA', $piece->journal_code);
        $this->assertSame($a->reference, $piece->achat_ref);
        $this->assertEqualsCanonicalizing(['401:10000:0', '512:0:10000'], $piece->lignes->map(fn ($l) => $l->numero_compte.':'.(int) $l->debit.':'.(int) $l->credit)->all());
        // Le solde 401 = la dette restante (15 000).
        $this->assertEquals(-15000.0, $this->net($a->reference)['401']);
    }

    public function test_un_versement_superieur_au_reste_du_est_borne_et_401_reste_a_zero(): void
    {
        $this->commander();
        $a = $this->achat();

        Livewire::actingAs($this->admin())->test(Achats::class)
            ->call('demanderReglement', $a->id)->set('montantReglement', '999 999')->set('modeReglement', 'Espèces')->call('confirmerReglement')
            ->assertSee('Règlement de 25 000 FCFA enregistré')->assertSee('La dette est soldée.');

        $this->assertEquals(40000.0, $this->achat()->paye);
        $this->assertArrayNotHasKey('401', $this->net($a->reference), '401 ne devient jamais debiteur (defaut du poste corrige)');
        $this->assertEquals(-40000.0, $this->net($a->reference)['531']);
    }

    public function test_les_refus_de_reglement(): void
    {
        $this->commander();
        $a = $this->achat();
        $c = Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderReglement', $a->id);
        $c->set('montantReglement', '')->call('confirmerReglement')->assertSet('erreurReglement', 'Le montant doit être supérieur à 0.');
        $c->set('montantReglement', '0')->call('confirmerReglement')->assertSet('erreurReglement', 'Le montant doit être supérieur à 0.');
        $c->set('montantReglement', 'abc')->call('confirmerReglement')->assertSet('erreurReglement', 'Le montant doit être supérieur à 0.');
        $c->set('montantReglement', '100')->set('modeReglement', 'Crédit')->call('confirmerReglement')
            ->assertSet('erreurReglement', 'Choisissez le mode du règlement (Espèces ou Mobile Money).');
        $this->assertEquals(15000.0, $this->achat()->paye);

        // Soldee, puis annulee : plus de reglement.
        $c->set('modeReglement', 'Espèces')->set('montantReglement', '25000')->call('confirmerReglement');
        $c->call('demanderReglement', $a->id)->set('montantReglement', '1')->call('confirmerReglement')
            ->assertSet('erreurReglement', 'Cette commande est déjà soldée.');
        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderAnnulation', $a->id)->set('motifAnnulation', 'x')->call('confirmerAnnulation');
        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderReglement', $a->id)->set('montantReglement', '1')->call('confirmerReglement')
            ->assertSet('erreurReglement', 'Cette commande est annulée.');
    }

    // -------------------------------------------------------------- Modification

    public function test_modifier_une_commande_extourne_la_piece_et_en_ecrit_une_neuve(): void
    {
        $this->commander(['livree' => false]);
        $a = $this->achat();
        $ancienne = PieceComptable::query()->where('achat_ref', $a->reference)->sole();

        // 50 Maïs × 300 = 15 000 ; les 15 000 deja payes couvrent tout : plus de dette.
        Livewire::actingAs($this->admin())->test(Achats::class)->call('modifier', $a->id)
            ->assertSet('achatId', $a->id)->assertSet('paye', '15000')->assertSet('lignes.0.qte', '100')
            ->set('lignes', [['intrant_code' => 'INT-001', 'qte' => '50', 'pu' => '300']])
            ->call('enregistrer')->assertSet('formulaire', false)->assertSee('modifiée (écritures extournées et réécrites)');

        $b = $this->achat();
        $this->assertSame($a->id, $b->id);
        $this->assertSame($a->reference, $b->reference, 'la reference ne change jamais');
        $this->assertEquals(15000.0, $b->total);
        $this->assertSame(['INT-001'], $b->lignes->pluck('intrant_code')->all(), 'les lignes sont remplacees');
        $this->assertSame('Commandé', $b->statut);
        $this->assertSame(3, PieceComptable::query()->where('achat_ref', $a->reference)->count());
        $inverse = PieceComptable::query()->where('contrepasse_de', $ancienne->id)->sole();
        $this->assertSame('ANN-'.$a->reference, $inverse->numero_piece);
        $this->assertSame('OD', $inverse->journal_code);
        $this->assertEquals(['601' => 15000.0, '531' => -15000.0], $this->net($a->reference));
    }

    public function test_les_refus_de_modification(): void
    {
        $this->commander(['livree' => false, 'paye' => '20000']);
        $a = $this->achat();
        $c = Livewire::actingAs($this->admin())->test(Achats::class)->call('modifier', $a->id);
        // Nouveau total 10 000 < 20 000 deja regles.
        $c->set('lignes', [['intrant_code' => 'INT-001', 'qte' => '10', 'pu' => '1000']])->call('enregistrer')
            ->assertSet('erreur', 'Le montant déjà réglé (20 000 FCFA) dépasse le nouveau total de la commande.');
        $this->assertEquals(40000.0, $this->achat()->total);
        $this->assertSame(1, PieceComptable::query()->where('achat_ref', $a->reference)->count(), 'rien n\'a ete extourne');

        // Livree : plus modifiable.
        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderReception', $a->id)->call('confirmerReception');
        Livewire::actingAs($this->admin())->test(Achats::class)->call('modifier', $a->id)
            ->assertSet('formulaire', false)->assertSet('erreur', 'Seule une commande en attente de livraison peut être modifiée.');
    }

    public function test_modifier_apres_un_reglement_reecrit_une_piece_unique_au_meme_solde(): void
    {
        $this->commander(['livree' => false]);
        $a = $this->achat();
        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderReglement', $a->id)->set('montantReglement', '10000')->call('confirmerReglement');
        $this->assertEquals(-15000.0, $this->net($a->reference)['401']);

        // On passe a 50 Maïs × 400 = 20 000 ; deja regle 25 000 > 20 000 → refus.
        Livewire::actingAs($this->admin())->test(Achats::class)->call('modifier', $a->id)
            ->set('lignes', [['intrant_code' => 'INT-001', 'qte' => '50', 'pu' => '400']])->call('enregistrer')
            ->assertSet('erreur', 'Le montant déjà réglé (25 000 FCFA) dépasse le nouveau total de la commande.');

        // 100 Maïs × 400 = 40 000 : reste du 15 000 apres les 25 000 regles ; 401 = 15 000, 531 = 25 000.
        Livewire::actingAs($this->admin())->test(Achats::class)->call('modifier', $a->id)
            ->set('lignes', [['intrant_code' => 'INT-001', 'qte' => '100', 'pu' => '400']])->call('enregistrer')->assertSet('erreur', null);
        $this->assertEquals(['601' => 40000.0, '531' => -25000.0, '401' => -15000.0], $this->net($a->reference));
    }

    // ----------------------------------------------------------------- Annulation

    public function test_annuler_une_commande_extourne_toutes_les_pieces_et_exige_un_motif(): void
    {
        $this->commander(['livree' => false]);
        $a = $this->achat();
        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderReglement', $a->id)->set('montantReglement', '10000')->set('modeReglement', 'Mobile Money')->call('confirmerReglement');

        $c = Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderAnnulation', $a->id)
            ->assertSeeHtml('data-modale="annulation"')->assertSee('le fournisseur les rembourse', false);
        $c->set('motifAnnulation', '   ')->call('confirmerAnnulation')
            ->assertSet('erreur', 'Le motif de l\'annulation est obligatoire.')->assertSet('aAnnuler', $a->id);
        $this->assertSame('Commandé', $this->achat()->statut);

        $c->set('motifAnnulation', 'Fournisseur en rupture')->call('confirmerAnnulation')
            ->assertSet('aAnnuler', null)->assertSee('annulée : écritures extournées');

        $this->assertSame('Annulé', $this->achat()->statut);
        $this->assertEquals([], $this->net($a->reference), 'chaque compte revient a zero');
        $this->assertSame(4, PieceComptable::query()->where('achat_ref', $a->reference)->count(), 'achat + reglement + leurs 2 inverses');
        $inverse = PieceComptable::query()->with('lignes')->where('numero_piece', 'ANN-REG-'.$a->reference)->sole();
        $this->assertStringContainsString('Fournisseur en rupture', $inverse->lignes->first()->libelle);
        $this->assertSame(0, MouvementIntrant::query()->count(), 'commande jamais livree : rien au journal');
        $this->assertDatabaseHas('audit_logs', ['action' => 'achats.annulation']);

        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderAnnulation', $a->id)->set('motifAnnulation', 'Encore')->call('confirmerAnnulation')
            ->assertSet('erreur', 'Cette commande est déjà annulée.');
    }

    public function test_annuler_une_commande_livree_inscrit_des_sorties_au_journal(): void
    {
        $this->commander();
        $a = $this->achat();

        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderAnnulation', $a->id)->set('motifAnnulation', 'Marchandise refusée')->call('confirmerAnnulation');

        $sorties = MouvementIntrant::query()->where('type', 'Sortie')->orderBy('intrant_code')->get();
        $this->assertEquals([-100.0, -10.0, -4.0], $sorties->pluck('quantite')->all());
        $this->assertStringContainsString('Annulation commande '.$a->reference.' — Marchandise refusée', $sorties->first()->motif);
        $this->assertEquals([], $this->net($a->reference));
    }

    public function test_une_annulation_refusee_par_la_periode_n_annule_rien(): void
    {
        $this->commander(['livree' => false]);
        $a = $this->achat();
        ExerciceComptable::query()->firstOrCreate(['annee' => $this->annee()], ['is_cloture' => false]);
        ExerciceComptable::query()->whereKey($this->annee())->update(['is_cloture' => true]);

        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderAnnulation', $a->id)->set('motifAnnulation', 'x')->call('confirmerAnnulation')
            ->assertSee('clôturé', false);

        $this->assertSame('Commandé', $this->achat()->statut);
        $this->assertSame(1, PieceComptable::query()->where('achat_ref', $a->reference)->count());
    }

    // ----------------------------------------------------------------- Fournisseurs

    public function test_regler_depuis_les_fournisseurs_et_la_suppression_reste_refusee_tant_que_la_dette_est_ouverte(): void
    {
        $this->commander();
        $a = $this->achat();
        $c = Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->assertSeeHtml('data-dette="'.$a->reference.'"')->assertSeeHtml('data-action="regler"')
            ->call('demanderSuppression', $this->fournisseur->id)->assertSee('a une dette ouverte')->assertSet('aSupprimer', null);

        $c->call('demanderReglement', $a->id)->set('montantReglement', '25000')->call('confirmerReglement')->assertSee('La dette est soldée.')
            ->call('demanderSuppression', $this->fournisseur->id)->assertSet('aSupprimer', $this->fournisseur->id);
    }

    public function test_la_coherence_achats_comptabilite_est_calculee_et_signale_l_ecart(): void
    {
        $this->commander();   // dette 25 000, 401 : 25 000
        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->assertSeeHtml('data-bloc="coherence"')
            ->assertSeeHtml('data-coherence="dettes">25 000 FCFA<')->assertSeeHtml('data-coherence="achats-401">25 000 FCFA<')
            ->assertSee('Aucun écart')->assertDontSeeHtml('data-coherence-avertissement');

        // Un achat d'un poste dont la piece n'est pas encore arrivee : ecart de 7 000.
        $f = $this->fournisseur;
        (new Achat)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'reference' => 'ACH-P1-'.$this->annee().'-001', 'portee_reference' => '',
            'fournisseur_id' => $f->id, 'date_achat' => now(), 'statut' => 'Livré', 'total' => 7000, 'paye' => 0, 'mode' => 'Espèces',
            'updated_at' => now(), 'serveur_modifie_le' => now(),
        ])->save();
        Livewire::actingAs($this->admin())->test(Fournisseurs::class)
            ->assertSeeHtml('data-coherence="dettes">32 000 FCFA<')->assertSeeHtml('data-coherence="ecart">-7 000 FCFA<')
            ->assertSeeHtml('data-coherence-avertissement');

        // Le comptable (view-comptabilite) la voit ; un simple lecteur d'achats non.
        $lecteur = User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-achats');
        Livewire::actingAs($lecteur)->test(Fournisseurs::class)->assertDontSeeHtml('data-bloc="coherence"');
    }

    // --------------------------------------------------------------- Imprimables

    public function test_le_bon_de_commande_porte_les_lignes_les_totaux_et_l_echeance(): void
    {
        $echeance = now(config('logialvia.fuseau'))->addDays(10);
        $this->commander(['echeance' => $echeance->format('Y-m-d'), 'livree' => false]);
        $a = $this->achat();

        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'))->get('/achats/'.$a->id.'/bon')->assertOk()
            ->assertSeeHtml('@media print')->assertSeeHtml('window.print()')->assertSee('Imprimer / PDF')
            ->assertSee('Bon de commande '.$a->reference)->assertSeeHtml('data-fournisseur>Agri Plus<')
            ->assertSeeHtmlInOrder(['data-ligne="INT-001"', 'Maïs', '100', '300', '30 000'])
            ->assertSeeHtml('data-ligne="INT-003"')
            ->assertSee('Échéance : '.$echeance->format('d/m/Y'))
            ->assertSeeHtmlInOrder(['data-total', '40 000', 'data-reste', '25 000']);
        $this->get('/achats/'.(string) Str::uuid().'/bon')->assertNotFound();
    }

    public function test_l_historique_imprimable_suit_les_filtres_et_exclut_les_annulees_des_totaux(): void
    {
        $this->commander();
        $this->commander(['paye' => '0']);
        $b = $this->achat($this->reference(2));
        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderAnnulation', $b->id)->set('motifAnnulation', 'x')->call('confirmerAnnulation');

        $page = $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'))->get('/achats/impression')->assertOk()
            ->assertSeeHtml('data-achat="'.$this->reference(1).'"')->assertSeeHtml('data-achat="'.$this->reference(2).'"')
            ->assertSee('1 annulée(s) non comptée(s)', false);
        $page->assertSeeHtmlInOrder(['data-totaux', '40 000', '15 000', '25 000']);

        $this->get('/achats/impression?statut=Annulé')->assertSeeHtml('data-achat="'.$this->reference(2).'"')
            ->assertDontSeeHtml('data-achat="'.$this->reference(1).'"')->assertSee('statut « Annulé »');
    }

    public function test_le_releve_fournisseur_liste_commandes_reglements_et_solde(): void
    {
        $this->commander();
        $a = $this->achat();
        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderReglement', $a->id)->set('montantReglement', '10000')->set('modeReglement', 'Mobile Money')->call('confirmerReglement');
        $this->commander(['paye' => '0', 'livree' => false, 'lignes' => [['intrant_code' => 'INT-001', 'qte' => '1', 'pu' => '1000']]]);
        $this->commander(['livree' => false, 'lignes' => [['intrant_code' => 'INT-001', 'qte' => '1', 'pu' => '500']], 'paye' => '0']);
        $c = $this->achat($this->reference(3));
        Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderAnnulation', $c->id)->set('motifAnnulation', 'x')->call('confirmerAnnulation');

        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'))->get('/fournisseurs/'.$this->fournisseur->id.'/releve')->assertOk()
            ->assertSeeHtml('data-fournisseur>Agri Plus<')
            // dettes : 15 000 (commande 1 apres reglement) + 1 000 (commande 2) ; la commande 3 annulee n'est pas comptee.
            ->assertSeeHtml('data-solde-du>16 000 FCFA<')->assertDontSeeHtml('data-achat="'.$this->reference(3).'"')
            ->assertSeeHtmlInOrder(['data-achat="'.$this->reference(1).'"', '40 000', '25 000', '15 000'])
            ->assertSeeHtmlInOrder(['data-reglement="'.$this->reference(1).'"', 'REG-'.$this->reference(1), '512', '10 000']);
    }

    public function test_fournisseurs_et_stocks_et_depenses_ont_leur_etat_imprimable(): void
    {
        $this->commander();
        $comptable = $this->utilisateurAvecRole('comptable', 'paul');

        $this->actingAs($comptable)->get('/fournisseurs/impression')->assertOk()->assertSee('Fournisseurs &amp; Dettes', false)
            ->assertSeeHtml('data-fournisseur="Agri Plus"')->assertSeeHtml('data-dette="'.$this->reference().'"')->assertSeeHtml('data-kpi="dette">25 000 FCFA<');
        // /stocks reste reserve a l'administrateur (view-stocks) : le comptable n'a pas l'impression non plus.
        $this->get('/stocks/impression')->assertForbidden();
        $this->actingAs($this->admin())->get('/stocks/impression')->assertOk()->assertSeeHtml('data-intrant="INT-001"')
            ->assertSeeHtml('data-mouvement="'.$this->reference().'"')->assertSeeHtml('data-ecart="stock-poste"')->assertDontSee('PMP :');
        $this->actingAs($comptable)->get('/depenses/impression')->assertOk()->assertSee('Saisie des Dépenses');
    }

    // ------------------------------------------------------------------- Exports

    public function test_l_export_des_achats_est_un_xlsx_filtre_et_exige_la_lecture(): void
    {
        $this->commander();
        $this->commander(['paye' => '0', 'livree' => false]);

        $c = Livewire::actingAs($this->utilisateurAvecRole('comptable', 'paul'))->test(Achats::class)->set('statut', 'Commandé')->call('exporter');
        $lignes = $this->lignesXlsx(base64_decode($c->effects['download']['content']));
        $this->assertSame('achats.xlsx', $c->effects['download']['name']);
        $this->assertSame(['Référence', 'Date', 'Fournisseur', 'Mode', 'Statut', 'Total', 'Payé', 'Reste dû', 'Échéance'], $lignes[0]);
        $this->assertCount(2, $lignes, 'un seul achat « Commandé »');
        $this->assertSame([$this->reference(2), '40000', '0'], [$lignes[1][0], $lignes[1][5], $lignes[1][6]]);
        $this->assertSame('Commandé', $lignes[1][4]);

        Livewire::actingAs($this->utilisateurAvecRole('caissier', 'amina'))->test(Achats::class)->call('exporter')->assertForbidden();
    }

    public function test_l_export_des_fournisseurs_et_dettes(): void
    {
        $this->commander();
        $c = Livewire::actingAs($this->admin())->test(Fournisseurs::class)->call('exporter');
        $lignes = $this->lignesXlsx(base64_decode($c->effects['download']['content']));
        $this->assertSame(['Fournisseurs & Dettes'], $lignes[0]);
        $this->assertSame(['Agri Plus', '', '', '', '1', '40000', '25000'], $lignes[2]);
        $this->assertContains('Dettes en cours', array_map(fn ($l) => $l[0] ?? '', $lignes));
        $this->assertContains($this->reference(), array_map(fn ($l) => $l[1] ?? '', $lignes));

        Livewire::actingAs($this->utilisateurAvecRole('caissier', 'amina'))->test(Fournisseurs::class)->call('exporter')->assertForbidden();
    }

    public function test_l_export_du_journal_des_mouvements_et_celui_des_depenses(): void
    {
        $this->commander();
        $c = Livewire::actingAs($this->admin())->test(\App\Livewire\GestionStocks::class)->call('exporter');
        $lignes = $this->lignesXlsx(base64_decode($c->effects['download']['content']));
        $this->assertSame(['Date / Heure', 'Poste', 'Référence', 'Article', 'Type', 'Motif', 'Quantité'], $lignes[0]);
        $this->assertCount(4, $lignes);
        $this->assertSame('Web', $lignes[1][1]);
        Livewire::actingAs($this->utilisateurAvecRole('caissier', 'amina2'))->test(\App\Livewire\GestionStocks::class)->call('exporter')->assertForbidden();

        $this->poserLeJeuCommun();
        $d = Livewire::actingAs($this->utilisateurAvecRole('comptable', 'paul'))->test(\App\Livewire\Depenses::class)->call('exporter');
        $lignes = $this->lignesXlsx(base64_decode($d->effects['download']['content']));
        // Titre, en-tete, une ligne par depense affichee, puis le total affiche.
        $this->assertStringStartsWith('Dépenses', $lignes[0][0]);
        $this->assertSame(['Date', 'Pièce', 'Libellé', 'Compte', 'Montant', 'Statut', 'Centre'], $lignes[1]);
        $this->assertCount(5, $lignes, 'deux depenses du jeu commun + titre, en-tete et total');
        Livewire::actingAs($this->utilisateurAvecRole('caissier', 'amina'))->test(\App\Livewire\Depenses::class)->call('exporter')->assertForbidden();
    }

    // ------------------------------------------------------- Depenses : correction

    public function test_corriger_une_depense_annule_l_ancienne_piece_et_passe_la_nouvelle_en_une_operation(): void
    {
        $this->poserLeJeuCommun();
        $n = $this->annee();
        $piece = PieceComptable::query()->where('numero_piece', 'DEP-P1-'.$n.'-0001')->sole();
        $paul = $this->utilisateurAvecRole('comptable', 'paul');

        Livewire::actingAs($paul)->test(\App\Livewire\Depenses::class)
            ->call('corriger', $piece->id)->assertSet('libelle', 'Libelle DEP-P1-'.$n.'-0001')->assertSet('categorie', '624')->assertSet('montant', '15000')->assertSet('centre', 'Pintades')
            ->set('montant', '18000')->call('enregistrer')->assertSet('corrigeDe', null)->assertSee('Dépense corrigée');

        $inverse = PieceComptable::query()->where('contrepasse_de', $piece->id)->sole();
        $this->assertSame('ANN-DEP-P1-'.$n.'-0001', $inverse->numero_piece);
        $neuve = PieceComptable::query()->with('lignes')->where('numero_piece', 'DEP-WEB-'.$n.'-0001')->sole();
        $this->assertEquals(18000.0, $neuve->lignes->sum('debit'));
        $this->assertSame('Pintades', $neuve->lignes->firstWhere('numero_compte', '624')->axe_analytique);
    }

    public function test_une_correction_refusee_n_annule_pas_l_ancienne_piece(): void
    {
        $this->poserLeJeuCommun();
        $n = $this->annee();
        $piece = PieceComptable::query()->where('numero_piece', 'DEP-P1-'.$n.'-0001')->sole();
        $paul = $this->utilisateurAvecRole('comptable', 'paul');

        $c = Livewire::actingAs($paul)->test(\App\Livewire\Depenses::class)->call('corriger', $piece->id)->set('reglement', '999');
        $c->call('enregistrer')->assertSee('Compte inconnu');
        $this->assertFalse(PieceComptable::query()->where('contrepasse_de', $piece->id)->exists());

        // Refus du serveur apres l'annulation (jour dans un exercice hors bornes) : tout est annule ensemble.
        $c->set('reglement', '531')->set('jour', '1999-01-01')->call('enregistrer');
        $this->assertFalse(PieceComptable::query()->where('contrepasse_de', $piece->id)->exists(), 'l\'annulation est annulee avec le refus');
        $this->assertFalse(PieceComptable::query()->where('numero_piece', 'like', 'DEP-WEB%')->exists());
    }

    public function test_corriger_exige_le_droit_et_une_depense_annulee_n_est_plus_corrigeable(): void
    {
        $this->poserLeJeuCommun();
        $piece = PieceComptable::query()->where('numero_piece', 'DEP-P1-'.$this->annee().'-0001')->sole();
        $lecteur = User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-achats');
        Livewire::actingAs($lecteur)->test(\App\Livewire\Depenses::class)->call('corriger', $piece->id)->assertForbidden();
        Livewire::actingAs($lecteur)->test(\App\Livewire\Depenses::class)->call('renoncerCorrection')->assertOk();

        $paul = $this->utilisateurAvecRole('comptable', 'paul');
        Livewire::actingAs($paul)->test(\App\Livewire\Depenses::class)->call('demanderAnnulation', $piece->id)->call('confirmerAnnulation');
        Livewire::actingAs($paul)->test(\App\Livewire\Depenses::class)->call('corriger', $piece->id)
            ->assertSet('corrigeDe', null)->assertSet('erreur', 'Cette dépense n\'existe plus ou est déjà annulée.');
    }
}
