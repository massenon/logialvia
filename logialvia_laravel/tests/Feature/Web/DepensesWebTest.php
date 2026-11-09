<?php

namespace Tests\Feature\Web;

use App\Livewire\Depenses;
use App\Models\EcritureComptable;
use App\Models\ExerciceComptable;
use App\Models\PieceComptable;
use App\Models\PlanComptable;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\Concerns\JeuComptable;
use Tests\TestCase;

/**
 * Saisie des Depenses (web). Une depense est une PIECE de 2 lignes (charge au debit, tresorerie ou
 * fournisseur au credit) ecrite par `EcrituresTable::absorber` ; elle est un fait immuable : elle
 * s'annule par contrepassation.
 */
class DepensesWebTest extends TestCase
{
    use JeuComptable, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerPourLesEcrans();
    }

    private function formulaire($composant, array $valeurs = [])
    {
        $valeurs = array_merge([
            'jour' => now(config('logialvia.fuseau'))->format('Y-m-d'), 'libelle' => 'Transport du maïs',
            'categorie' => '618', 'montant' => '12000', 'reglement' => '571', 'centre' => '',
        ], $valeurs);
        foreach ($valeurs as $champ => $valeur) {
            $composant->set($champ, $valeur);
        }

        return $composant;
    }

    // ------------------------------------------------------------------ Acces

    public function test_acces_selon_le_droit_de_la_route(): void
    {
        $this->get('/depenses')->assertRedirect('/login');
        $this->actingAs($this->utilisateurAvecRole('caissier', 'amina'))->get('/depenses')->assertForbidden();
        $this->actingAs($this->utilisateurAvecRole('animalier', 'koffi'))->get('/depenses')->assertForbidden();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'))->get('/depenses')->assertOk()
            ->assertSee('Saisie des Dépenses')->assertDontSee('Cet écran arrive bientôt');
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'))->get('/depenses')->assertOk();
    }

    public function test_qui_ne_fait_que_consulter_n_a_ni_formulaire_ni_bouton(): void
    {
        $this->poserLeJeuCommun();
        $lecteur = User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-achats');
        $this->actingAs($lecteur);

        Livewire::test(Depenses::class)->assertSeeHtml('data-depense="DEP-P1-'.$this->annee().'-0001"')
            ->assertDontSeeHtml('data-formulaire="depense"')->assertDontSeeHtml('data-action="annuler-depense"');
        foreach (['enregistrer' => [], 'demanderAnnulation' => ['x'], 'confirmerAnnulation' => []] as $methode => $args) {
            Livewire::test(Depenses::class)->call($methode, ...$args)->assertForbidden();
        }
        $this->assertSame(0, PieceComptable::query()->where('numero_piece', 'like', '%WEB%')->count());
    }

    // ------------------------------------------------------------------ Liste

    public function test_la_liste_est_reconstruite_depuis_les_ecritures_hors_achats_et_ventes(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $n = $this->annee();

        Livewire::test(Depenses::class)
            ->assertSeeHtmlInOrder(['data-depense="DEP-P1-'.$n.'-0002"', '625 - Primes d\'assurance', '12 000 FCFA', 'En attente'])   // credit 401 : elle reste due
            ->assertSeeHtmlInOrder(['data-depense="DEP-P1-'.$n.'-0001"', '618 - Autres frais de transport', '15 000 FCFA', 'Payée'])
            ->assertDontSeeHtml('data-depense="ACH-P1-'.$n.'-001"')                           // achat d'intrants : autre ecran
            ->assertDontSeeHtml('data-depense="V-P1-'.$n.'-001"')
            ->assertSeeHtmlInOrder(['data-total', 'TOTAL AFFICHÉ (2 dépenses)', '27 000 FCFA']);
    }

    public function test_les_kpi_fixes_et_variables_suivent_les_comptes_622_et_625(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Depenses::class)
            ->assertSeeHtmlInOrder(['data-kpi="fixes"', '12 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="variables"', '15 000 FCFA']);
    }

    public function test_depenses_du_mois_ne_compte_que_le_mois_civil_en_cours(): void
    {
        $this->poserLeJeuCommun();
        $m = now(config('logialvia.fuseau'));
        $this->poserPiece('DEP-P1-'.$m->year.'-0099', (int) $m->year, (int) $m->month, 1, 'CA', [['658', 7777, 0, null], ['571', 0, 7777, null]]);
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $attendu = 7777
            + ((int) $m->year === $this->annee() && (int) $m->month === 5 ? 27000 : 0);
        Livewire::test(Depenses::class)->assertSeeHtmlInOrder(['data-kpi="mois"', number_format($attendu, 0, ',', ' ').' FCFA']);
    }

    public function test_une_liste_vide_l_explique(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Depenses::class)->assertSee('Aucune dépense enregistrée sur l\'exercice '.$this->annee().'.')
            ->assertSee('l\'écriture correspondante partira automatiquement au Journal');
    }

    public function test_filtres_statut_recherche_et_reinitialisation(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $n = $this->annee();

        $c = Livewire::test(Depenses::class)->set('statut', 'payee')
            ->assertSeeHtml('data-depense="DEP-P1-'.$n.'-0001"')->assertDontSeeHtml('data-depense="DEP-P1-'.$n.'-0002"');
        $c->set('statut', 'attente')
            ->assertSeeHtml('data-depense="DEP-P1-'.$n.'-0002"')->assertDontSeeHtml('data-depense="DEP-P1-'.$n.'-0001"');
        $c->set('statut', '')->set('recherche', 'assur')->assertSeeHtml('data-depense="DEP-P1-'.$n.'-0002"')->assertDontSeeHtml('data-depense="DEP-P1-'.$n.'-0001"');
        $c->set('recherche', 'zzz')->assertSee('Aucune dépense ne correspond à ces filtres.');
        $c->call('reinitialiserFiltres')->assertSet('recherche', '')->assertSet('statut', '')->assertSeeHtml('data-depense="DEP-P1-'.$n.'-0001"');
    }

    public function test_les_jokers_de_la_recherche_sont_litteraux(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Depenses::class)->set('recherche', '%')->assertSee('Aucune dépense ne correspond à ces filtres.');
    }

    // ----------------------------------------------------------------- Saisie

    public function test_une_depense_devient_une_piece_de_deux_lignes_ecrite_par_le_serveur(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $c = $this->formulaire(Livewire::test(Depenses::class), ['centre' => 'Pintades'])->call('enregistrer')
            ->assertSet('erreur', null)
            ->assertSee('Dépense DEP-WEB-'.$this->annee().'-0001 enregistrée — 12 000 FCFA imputés au compte 618.');

        $piece = PieceComptable::query()->with('lignes')->firstOrFail();
        $this->assertSame('CA', $piece->journal_code);
        $this->assertSame('00000000-0000-0000-0000-000000000000', $piece->device_id);
        $this->assertCount(2, $piece->lignes);
        $charge = $piece->lignes->firstWhere('numero_compte', '618');
        $this->assertSame(12000.0, $charge->debit);
        $this->assertSame('Pintades', $charge->axe_analytique, 'le centre est porte par la ligne de charge');
        $tresorerie = $piece->lignes->firstWhere('numero_compte', '571');
        $this->assertSame(12000.0, $tresorerie->credit);
        $this->assertNull($tresorerie->axe_analytique, 'la contrepartie n\'appartient a aucune filiere');
        // Comme au poste : le formulaire est reinitialise, l'ecran enchaine les saisies.
        $c->assertSet('libelle', '')->assertSet('montant', '')->assertSet('categorie', '');
        $c->assertSeeHtml('data-depense="DEP-WEB-'.$this->annee().'-0001"');
    }

    public function test_une_depense_a_credit_reste_en_attente(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $c = $this->formulaire(Livewire::test(Depenses::class), ['reglement' => '401', 'categorie' => '625'])->call('enregistrer')->assertSet('erreur', null);

        $c->assertSeeHtmlInOrder(['data-depense="DEP-WEB-'.$this->annee().'-0001"', 'En attente']);
        $this->assertSame(12000.0, EcritureComptable::query()->where('numero_compte', '401')->first()->credit);
    }

    public function test_la_sequence_des_numeros_continue_et_ne_se_melange_pas_avec_celle_des_postes(): void
    {
        $this->poserLeJeuCommun();     // DEP-P1-N-0001 et 0002 existent deja
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $c = Livewire::test(Depenses::class);

        $this->formulaire($c)->call('enregistrer');
        $this->formulaire($c, ['libelle' => 'Autre'])->call('enregistrer');

        $this->assertEqualsCanonicalizing(
            ['DEP-WEB-'.$this->annee().'-0001', 'DEP-WEB-'.$this->annee().'-0002'],
            PieceComptable::query()->where('numero_piece', 'like', 'DEP-WEB-%')->pluck('numero_piece')->all(),
        );
    }

    public function test_les_champs_obligatoires_sont_signales_champ_par_champ(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $c = $this->formulaire(Livewire::test(Depenses::class), ['libelle' => '', 'montant' => '', 'categorie' => '', 'reglement' => ''])->call('enregistrer');

        $c->assertSet('erreur', 'Veuillez compléter les champs obligatoires.')
            ->assertSeeHtml('data-erreur-champ="libelle"')->assertSeeHtml('data-erreur-champ="categorie"')->assertSeeHtml('data-erreur-champ="reglement"')
            ->assertSee('Montant obligatoire, supérieur à zéro.');
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_un_montant_nul_negatif_ou_illisible_est_refuse(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $c = Livewire::test(Depenses::class);

        foreach (['0', '-5', 'abc'] as $montant) {
            $this->formulaire($c, ['montant' => $montant])->call('enregistrer')->assertSee('Montant obligatoire, supérieur à zéro.');
        }
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_un_montant_a_virgule_decimale_est_accepte(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $this->formulaire(Livewire::test(Depenses::class), ['montant' => '1250,5'])->call('enregistrer')->assertSet('erreur', null);

        $this->assertSame(1250.5, EcritureComptable::query()->where('numero_compte', '618')->first()->debit);
    }

    public function test_seuls_les_comptes_proposes_sont_acceptes(): void
    {
        PlanComptable::query()->whereKey('622')->update(['archive' => true]);
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $c = Livewire::test(Depenses::class);
        $motif = 'Compte inconnu, archivé ou non proposé à la saisie d\'une dépense.';

        // 602 : achat d'intrants (autre ecran) ; 622 : archive ; 702 : produit ; 999 : inconnu.
        foreach (['602', '622', '702', '999'] as $compte) {
            $this->formulaire($c, ['categorie' => $compte])->call('enregistrer')->assertSet('erreur', $motif);
        }
        // Le reglement doit etre de la tresorerie (classe 5) ou un compte fournisseur (40x).
        $this->formulaire($c, ['reglement' => '702'])->call('enregistrer')->assertSet('erreur', $motif);
        $this->formulaire($c, ['reglement' => '411'])->call('enregistrer')->assertSet('erreur', $motif);
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_centre_inconnu_et_date_invalide_sont_refuses(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $c = Livewire::test(Depenses::class);

        $this->formulaire($c, ['centre' => 'Licornes'])->call('enregistrer')->assertSet('erreur', 'Centre analytique inconnu.');
        $this->formulaire($c, ['centre' => '', 'jour' => '31/02/2026'])->call('enregistrer')->assertSet('erreur', 'La date de la dépense est invalide.');
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_dans_un_exercice_cloture_le_formulaire_cede_la_place_a_un_avertissement_et_le_serveur_refuse(): void
    {
        ExerciceComptable::query()->firstOrCreate(['annee' => $this->annee()], ['is_cloture' => false]);
        ExerciceComptable::query()->whereKey($this->annee())->update(['is_cloture' => true]);
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $c = Livewire::test(Depenses::class)->assertSeeHtml('data-avertissement')
            ->assertSee('L\'exercice '.$this->annee().' est clôturé : aucune écriture ne peut plus y être ajoutée ni modifiée.', false)
            ->assertDontSeeHtml('data-action="enregistrer"');
        // Meme en forcant l'appel : le serveur refuse avec son motif.
        $this->formulaire($c)->call('enregistrer')
            ->assertSet('erreur', "L'exercice {$this->annee()} est clôturé : aucune écriture ne peut y être ajoutée ni modifiée (BR-CPT-001).");
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_un_mois_cloture_refuse_la_depense_avec_le_motif_du_serveur(): void
    {
        $admin = $this->utilisateurAvecRole('admin', 'gerante');
        $this->actingAs($admin);
        $maintenant = now(config('logialvia.fuseau'));
        Livewire::test(\App\Livewire\Cloture::class)->call('basculerMois', (int) $maintenant->month);

        $this->formulaire(Livewire::test(Depenses::class))->call('enregistrer')
            ->assertSet('erreur', "Le mois {$maintenant->month}/{$maintenant->year} est clôturé. Une administratrice peut le déclôturer pour correction (BR-CPT-006).");
    }

    // --------------------------------------------------------------- Annulation

    public function test_annuler_une_depense_passe_l_ecriture_inverse_et_la_retire_de_la_liste(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $n = $this->annee();
        $piece = PieceComptable::query()->where('numero_piece', 'DEP-P1-'.$n.'-0001')->firstOrFail();

        Livewire::test(Depenses::class)
            ->call('demanderAnnulation', $piece->id)->assertSeeHtml('data-modale="annulation"')->assertSee('Annuler cette dépense ?')
            ->call('confirmerAnnulation')->assertSee('Dépense annulée (écriture inverse passée).')
            ->assertDontSeeHtml('data-depense="DEP-P1-'.$n.'-0001"')
            ->assertSeeHtmlInOrder(['data-kpi="variables"', '0 FCFA'])
            ->assertSeeHtmlInOrder(['data-total', '(1 dépense)', '12 000 FCFA']);

        $this->assertTrue(PieceComptable::query()->whereKey($piece->id)->exists(), 'la depense originale reste au journal');
        $inverse = PieceComptable::query()->where('contrepasse_de', $piece->id)->with('lignes')->firstOrFail();
        $this->assertSame('ANN-DEP-P1-'.$n.'-0001', $inverse->numero_piece);
        $this->assertSame('OD', $inverse->journal_code);
        $this->assertSame(15000.0, $inverse->lignes->firstWhere('numero_compte', '618')->credit);
        $this->assertSame('Pintades', $inverse->lignes->firstWhere('numero_compte', '618')->axe_analytique, 'l\'annulation garde le centre de la charge');
        // Le resultat net revient d'autant (Compte de Resultat).
        Livewire::test(\App\Livewire\Comptabilite::class)->assertSee('148 000');
    }

    public function test_on_n_annule_qu_une_depense_une_seule_fois(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $piece = PieceComptable::query()->where('numero_piece', 'DEP-P1-'.$this->annee().'-0001')->firstOrFail();
        $c = Livewire::test(Depenses::class);
        $c->call('demanderAnnulation', $piece->id)->call('confirmerAnnulation');

        $c->call('demanderAnnulation', $piece->id)->call('confirmerAnnulation')->assertSet('erreur', 'Cette pièce est déjà annulée.');

        $this->assertSame(1, PieceComptable::query()->where('contrepasse_de', $piece->id)->count());
    }

    public function test_annuler_une_depense_garde_la_confirmation_en_deux_temps(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $piece = PieceComptable::query()->where('numero_piece', 'DEP-P1-'.$this->annee().'-0001')->firstOrFail();

        $c = Livewire::test(Depenses::class)->call('demanderAnnulation', $piece->id);
        $this->assertSame(0, PieceComptable::query()->whereNotNull('contrepasse_de')->count(), 'rien n\'est passe avant confirmation');
        $c->call('annuler')->assertDontSeeHtml('data-modale="annulation"')->call('confirmerAnnulation');
        $this->assertSame(0, PieceComptable::query()->whereNotNull('contrepasse_de')->count());
    }

    public function test_en_mode_cartes_sous_640_px_sans_defilement_cache(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $this->get('/depenses')->assertOk()->assertSeeHtml('data-vue="cartes"')->assertSeeHtml('hidden overflow-x-auto')
            ->assertSeeHtml('data-carte-depense="DEP-P1-'.$this->annee().'-0001"');
    }

    public function test_les_depenses_d_un_autre_exercice_ne_sont_pas_melangees(): void
    {
        $this->poserLeJeuCommun();
        $this->poserPiece('DEP-P1-'.($this->annee() - 1).'-0001', $this->annee() - 1, 3, 3, 'CA', [['658', 900, 0, null], ['571', 0, 900, null]]);
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Depenses::class)->assertDontSeeHtml('data-depense="DEP-P1-'.($this->annee() - 1).'-0001"')
            ->set('exercice', $this->annee() - 1)
            ->assertSeeHtml('data-depense="DEP-P1-'.($this->annee() - 1).'-0001"')->assertDontSeeHtml('data-depense="DEP-P1-'.$this->annee().'-0001"');
    }
}
