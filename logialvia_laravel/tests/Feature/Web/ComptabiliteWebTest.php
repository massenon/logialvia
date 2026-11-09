<?php

namespace Tests\Feature\Web;

use App\Livewire\Analytique;
use App\Livewire\BalanceGenerale;
use App\Livewire\BilanEntreprise;
use App\Livewire\Cloture;
use App\Livewire\Comptabilite;
use App\Livewire\EtatsFinanciers;
use App\Livewire\GrandLivre;
use App\Livewire\Journal;
use App\Livewire\PlanComptableEcran;
use App\Models\CloturePeriodique;
use App\Models\EcritureComptable;
use App\Models\ExerciceComptable;
use App\Models\NoteAnnexe;
use App\Models\PieceComptable;
use App\Models\PlanComptable;
use App\Models\User;
use App\Support\UuidDeterministe;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Concerns\JeuComptable;
use Tests\TestCase;

/**
 * Ecrans web de la comptabilite (P8). Lectures calculees par le serveur sur les ecritures de TOUS les
 * postes ; ecritures par `TableSync::absorber`, jamais d'`update` direct.
 */
class ComptabiliteWebTest extends TestCase
{
    use JeuComptable, RefreshDatabase;

    private const ROUTES = [
        '/comptabilite', '/comptabilite/journal', '/comptabilite/grand-livre', '/comptabilite/balance',
        '/comptabilite/plan', '/comptabilite/analytique', '/comptabilite/etats-financiers',
        '/comptabilite/bilan', '/comptabilite/cloture',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerPourLesEcrans();
    }

    // ------------------------------------------------------------------ Acces

    public function test_visiteur_caissier_et_animalier_n_ouvrent_aucun_ecran(): void
    {
        foreach (self::ROUTES as $route) {
            $this->get($route)->assertRedirect('/login');
        }
        $this->actingAs($this->utilisateurAvecRole('caissier', 'amina'));
        foreach (self::ROUTES as $route) {
            $this->get($route)->assertForbidden();
        }
        $this->actingAs($this->utilisateurAvecRole('animalier', 'koffi'));
        foreach (self::ROUTES as $route) {
            $this->get($route)->assertForbidden();
        }
    }

    public function test_le_comptable_et_l_admin_ouvrent_les_neuf_ecrans_qui_sont_les_vrais_ecrans(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $titres = [
            '/comptabilite' => 'Comptabilité', '/comptabilite/journal' => 'Journal Comptable',
            '/comptabilite/grand-livre' => 'Grand Livre', '/comptabilite/balance' => 'Balance Générale',
            '/comptabilite/plan' => 'Plan Comptable', '/comptabilite/analytique' => 'Comptabilité Analytique',
            '/comptabilite/etats-financiers' => 'États Financiers', '/comptabilite/bilan' => 'Bilan de l\'Entreprise',
            '/comptabilite/cloture' => 'Clôture d\'Exercice',
        ];
        foreach ($titres as $route => $titre) {
            $this->get($route)->assertOk()->assertSee($titre)->assertDontSee('Cet écran arrive bientôt');
        }
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));
        foreach (self::ROUTES as $route) {
            $this->get($route)->assertOk();
        }
    }

    public function test_les_ecrans_sont_declares_dans_le_registre(): void
    {
        foreach (array_merge(self::ROUTES, ['/depenses']) as $route) {
            $this->assertContains($route, \App\Support\Ecrans::declarees(), $route);
        }
    }

    public function test_un_compte_qui_ne_fait_que_voir_n_a_aucun_bouton_d_ecriture(): void
    {
        $this->poserLeJeuCommun();
        $lecteur = User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-comptabilite');
        $this->actingAs($lecteur);

        $this->get('/comptabilite/journal')->assertOk()->assertDontSeeHtml('data-action="nouvelle"')->assertDontSeeHtml('data-action="annuler-piece"');
        $this->get('/comptabilite/plan')->assertOk()->assertDontSeeHtml('data-action="nouveau"')->assertDontSeeHtml('data-action="modifier"');
        $this->get('/comptabilite/cloture')->assertOk()->assertDontSeeHtml('data-action="cloturer"')->assertDontSeeHtml('data-action="cloturer-exercice"');
        $this->get('/comptabilite/etats-financiers')->assertOk();
    }

    // -------------------------------------------------------------------- Hub

    public function test_le_hub_calcule_ses_kpi_depuis_les_ecritures(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));

        Livewire::test(Comptabilite::class)
            ->assertSeeHtmlInOrder(['data-kpi="total-actif"', '775 000'])
            ->assertSeeHtml('data-kpi="tresorerie"')
            ->assertSee('545 000')                // tresorerie CUMULEE : ouverture 100 000 + 445 000
            ->assertSee('133 000')                // resultat cumule
            ->assertSeeHtmlInOrder(['data-kpi="marge"', '67']);   // marge nette = 133 000 / 200 000, arrondie
    }

    public function test_le_hub_dit_qu_il_n_y_a_pas_de_marge_sans_produit_et_liste_les_neuf_tuiles(): void
    {
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));

        $c = Livewire::test(Comptabilite::class)->assertSeeHtml('data-grille="tuiles"');
        $c->assertSeeHtmlInOrder(['data-kpi="marge"', '—']);
        foreach (Comptabilite::TUILES as [, , $route]) {
            $c->assertSeeHtml('data-tuile="'.$route.'"');
        }
        $this->assertCount(9, Comptabilite::TUILES);
    }

    public function test_le_bandeau_mecef_suit_l_ifu_et_le_rccm(): void
    {
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));
        Livewire::test(Comptabilite::class)->assertSee('En Attente de Configuration');

        \App\Models\ParametresEntreprise::courant()->forceFill(['ifu' => '3201700012345', 'rccm' => 'RB/NAT/20 B 1234'])->save();
        Livewire::test(Comptabilite::class)->assertSee('Activable')->assertSee('3201700012345');
    }

    // ---------------------------------------------------------------- Journal

    public function test_le_journal_montre_toutes_les_ecritures_avec_leur_origine_et_l_equilibre(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Journal::class)
            ->assertSee('Écritures de l\'exercice '.$this->annee(), false)
            ->assertSee('V-P1-'.$this->annee().'-001')
            ->assertSee('DEP-P1-'.$this->annee().'-0002')
            ->assertSeeHtml('data-origine')
            ->assertSee('Poste 11111111')                       // pas de code de poste connu : repli sur l'identifiant
            ->assertSeeHtml('data-auto')                        // ecriture automatique d'une vente
            ->assertSeeHtmlInOrder(['data-kpi="debit"', '987 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="credit"', '987 000 FCFA'])
            ->assertSee('Équilibré');
    }

    public function test_le_journal_filtre_par_recherche_et_par_journal(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Journal::class)
            ->set('journal', 'VT')
            ->assertSee('V-P1-'.$this->annee().'-001')->assertDontSee('DEP-P1-'.$this->annee().'-0001')
            ->set('journal', '')
            ->set('recherche', 'DEP-P1')
            ->assertSee('DEP-P1-'.$this->annee().'-0001')->assertDontSee('V-P1-'.$this->annee().'-001')
            ->set('recherche', '616')
            ->assertSee('DEP-P1-'.$this->annee().'-0002')->assertDontSee('DEP-P1-'.$this->annee().'-0001')
            ->set('recherche', 'introuvable-xyz')
            ->assertSee('Aucune écriture ne correspond à ces critères.');
    }

    public function test_un_journal_vide_explique_d_ou_viennent_les_ecritures(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Journal::class)->assertSee('Chaque vente et chaque achat enregistré sur un poste génère automatiquement son écriture ici');
    }

    public function test_le_journal_change_d_exercice_et_ignore_un_exercice_inconnu(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $c = Livewire::test(Journal::class)->set('exercice', $this->annee() - 1)
            ->assertSee('OD-P1-'.($this->annee() - 1).'-0001')->assertDontSee('V-P1-'.$this->annee().'-001');
        $c->set('exercice', 1850)->assertSee('V-P1-'.$this->annee().'-001');
    }

    public function test_une_ecriture_manuelle_est_ecrite_par_le_serveur_comme_pour_un_poste(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Journal::class)
            ->call('nouvelle')
            ->set('libelle', 'Régularisation caisse')->set('montant', '5 000'.'')->set('montant', '5000')
            ->set('compteDebit', '531')->set('compteCredit', '701')
            ->call('enregistrer')
            ->assertSet('erreur', null)
            ->assertSee('Écriture OD-WEB-'.$this->annee().'-0001 enregistrée — Débit 531 / Crédit 701.');

        $piece = PieceComptable::query()->with('lignes')->firstOrFail();
        $this->assertSame('OD-WEB-'.$this->annee().'-0001', $piece->numero_piece);
        $this->assertSame('OD', $piece->journal_code);
        $this->assertSame('00000000-0000-0000-0000-000000000000', $piece->device_id);
        $this->assertCount(2, $piece->lignes);
        $this->assertSame(5000.0, $piece->lignes->sum('debit'));
        $this->assertSame(5000.0, $piece->lignes->sum('credit'));
    }

    public function test_la_sequence_des_numeros_web_continue(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $c = Livewire::test(Journal::class);
        foreach ([1, 2] as $i) {
            $c->call('nouvelle')->set('libelle', "Op $i")->set('montant', '100')->call('enregistrer')->assertSet('erreur', null);
        }

        $this->assertSame(
            ['OD-WEB-'.$this->annee().'-0001', 'OD-WEB-'.$this->annee().'-0002'],
            PieceComptable::query()->orderBy('numero_piece')->pluck('numero_piece')->all(),
        );
    }

    public function test_la_saisie_manuelle_est_validee_avec_les_messages_du_poste(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $c = Livewire::test(Journal::class)->call('nouvelle');

        $c->set('libelle', '')->set('montant', '100')->call('enregistrer')
            ->assertSet('erreur', 'Veuillez renseigner le libellé et un montant valide.');
        $c->set('libelle', 'x')->set('montant', '0')->call('enregistrer')
            ->assertSet('erreur', 'Veuillez renseigner le libellé et un montant valide.');
        $c->set('montant', 'abc')->call('enregistrer')
            ->assertSet('erreur', 'Veuillez renseigner le libellé et un montant valide.');
        $c->set('montant', '100')->set('compteDebit', '531')->set('compteCredit', '531')->call('enregistrer')
            ->assertSet('erreur', 'Le compte Débit et le compte Crédit ne peuvent pas être identiques.');
        $c->set('compteCredit', '701')->set('jour', '2026-13-45')->call('enregistrer')
            ->assertSet('erreur', 'La date de l\'écriture est invalide.');
        $c->set('jour', now()->format('Y-m-d'))->set('compteDebit', '999')->call('enregistrer')
            ->assertSet('erreur', 'Compte inconnu ou archivé.');

        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_un_compte_archive_n_est_pas_propose_a_la_saisie(): void
    {
        PlanComptable::query()->whereKey('624')->update(['archive' => true]);
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Journal::class)->call('nouvelle')
            ->set('libelle', 'x')->set('montant', '100')->set('compteDebit', '624')->set('compteCredit', '701')
            ->call('enregistrer')->assertSet('erreur', 'Compte inconnu ou archivé.');
    }

    public function test_le_serveur_refuse_une_ecriture_dans_un_exercice_cloture_avec_son_motif(): void
    {
        ExerciceComptable::query()->firstOrCreate(['annee' => $this->annee()], ['is_cloture' => false]);
        ExerciceComptable::query()->whereKey($this->annee())->update(['is_cloture' => true]);
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $c = Livewire::test(Journal::class)->call('nouvelle')->set('libelle', 'x')->set('montant', '100')->call('enregistrer');

        $c->assertSet('erreur', "L'exercice {$this->annee()} est clôturé : aucune écriture ne peut y être ajoutée ni modifiée (BR-CPT-001).");
        $this->assertSame(0, PieceComptable::query()->count());
    }

    public function test_annuler_une_piece_passe_l_ecriture_inverse_et_ne_supprime_rien(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $originale = PieceComptable::query()->where('numero_piece', 'OD-P1-'.$this->annee().'-0002')->firstOrFail();

        Livewire::test(Journal::class)
            ->call('demanderAnnulation', $originale->id)->assertSeeHtml('data-modale="annulation"')
            ->call('confirmerAnnulation')
            ->assertSee('Pièce annulée (écriture inverse passée).');

        $this->assertTrue(PieceComptable::query()->whereKey($originale->id)->exists(), 'rien n\'est supprime');
        $inverse = PieceComptable::query()->where('contrepasse_de', $originale->id)->with('lignes')->firstOrFail();
        $this->assertSame('ANN-OD-P1-'.$this->annee().'-0002', $inverse->numero_piece);
        $this->assertSame(200000.0, $inverse->lignes->firstWhere('numero_compte', '231')->credit);
        $this->assertSame(200000.0, $inverse->lignes->firstWhere('numero_compte', '531')->debit);
    }

    public function test_une_piece_annulee_ne_s_annule_pas_deux_fois_et_une_annulation_non_plus(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $originale = PieceComptable::query()->where('numero_piece', 'OD-P1-'.$this->annee().'-0002')->firstOrFail();
        $c = Livewire::test(Journal::class);
        $c->call('demanderAnnulation', $originale->id)->call('confirmerAnnulation');

        $c->call('demanderAnnulation', $originale->id)->call('confirmerAnnulation')->assertSee('Cette pièce est déjà annulée.');
        $inverse = PieceComptable::query()->where('contrepasse_de', $originale->id)->firstOrFail();
        $c->call('demanderAnnulation', $inverse->id)->call('confirmerAnnulation')
            ->assertSee("Une écriture d'annulation ne s'annule pas : saisissez une nouvelle écriture.");

        $this->assertSame(1, PieceComptable::query()->where('contrepasse_de', $originale->id)->count());
    }

    public function test_une_piece_automatique_ne_s_annule_pas_ici(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $vente = PieceComptable::query()->where('numero_piece', 'V-P1-'.$this->annee().'-001')->firstOrFail();

        Livewire::test(Journal::class)
            ->call('demanderAnnulation', $vente->id)->call('confirmerAnnulation')
            ->assertSee('Cette pièce est générée automatiquement par V-P1-'.$this->annee().'-001. Annulez l\'opération d\'origine plutôt que l\'écriture.');

        $this->assertSame(0, PieceComptable::query()->whereNotNull('contrepasse_de')->count());
    }

    public function test_les_pieces_annulees_et_les_annulations_sont_signalees(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $originale = PieceComptable::query()->where('numero_piece', 'OD-P1-'.$this->annee().'-0002')->firstOrFail();
        $c = Livewire::test(Journal::class);
        $c->call('demanderAnnulation', $originale->id)->call('confirmerAnnulation');

        $c->assertSeeHtml('data-annulee')->assertSeeHtml('data-annulation');
    }

    public function test_les_methodes_d_ecriture_du_journal_refusent_qui_n_a_pas_le_droit(): void
    {
        $this->poserLeJeuCommun();
        $lecteur = User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-comptabilite');
        $piece = PieceComptable::query()->firstOrFail();
        $this->actingAs($lecteur);

        foreach (['nouvelle' => [], 'enregistrer' => [], 'demanderAnnulation' => [$piece->id], 'confirmerAnnulation' => []] as $methode => $args) {
            Livewire::test(Journal::class)->call($methode, ...$args)->assertForbidden();
        }
        $this->assertSame(0, PieceComptable::query()->whereNotNull('contrepasse_de')->count());
    }

    // ------------------------------------------------------------- Grand livre

    public function test_le_grand_livre_demande_un_compte(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(GrandLivre::class)->assertSeeHtml('data-vide="aucun-compte"')
            ->assertSee('Sélectionnez un compte ci-dessus pour afficher ses écritures et son solde progressif.');
    }

    public function test_le_grand_livre_calcule_ouverture_totaux_et_solde_progressif(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $c = Livewire::test(GrandLivre::class)->set('compte', '531')
            ->assertSeeHtmlInOrder(['data-kpi="ouverture"', '100 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="debit"', '670 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="credit"', '225 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="solde-final"', '545 000 FCFA'])
            ->assertSee('Débiteur par nature')->assertSee('Report — solde d\'ouverture', false);
        // Le solde progressif ligne a ligne : 100 000 + 500 000 = 600 000, +120 000 = 720 000 …
        $c->assertSeeHtmlInOrder(['data-solde', '600 000', 'data-solde', '720 000', 'data-solde', '750 000', 'data-solde', '740 000']);
    }

    public function test_une_periode_deplace_l_ouverture_sans_fausser_le_solde_final(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $n = $this->annee();

        Livewire::test(GrandLivre::class)->set('compte', '531')->set('debut', "$n-05-01")
            ->assertSeeHtmlInOrder(['data-kpi="ouverture"', '740 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="debit"', '20 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="credit"', '215 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="solde-final"', '545 000 FCFA']);
    }

    public function test_la_borne_de_fin_est_incluse(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $n = $this->annee();

        // L'ecriture du 15/06 entre dans « au 15/06 », celle du 01/07 non.
        Livewire::test(GrandLivre::class)->set('compte', '531')->set('fin', "$n-06-15")
            ->assertSee('Libelle REG-V-P1-'.$n.'-002')->assertDontSee('Libelle OD-P1-'.$n.'-0002')
            ->assertSeeHtmlInOrder(['data-kpi="solde-final"', '745 000 FCFA']);
    }

    public function test_la_recherche_ne_change_ni_les_kpi_ni_le_solde_progressif(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(GrandLivre::class)->set('compte', '531')->set('recherche', 'REG-V')
            ->assertSee('Libelle REG-V-P1-'.$this->annee().'-002')->assertDontSee('Libelle OD-P1-'.$this->annee().'-0002')
            ->assertSeeHtmlInOrder(['data-kpi="debit"', '670 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="solde-final"', '545 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-solde', '745 000']);   // le solde progressif de cette ligne reste celui du compte entier
    }

    public function test_un_compte_crediteur_se_lit_dans_son_sens_naturel(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        // Exactement « 120 000 », jamais « -120 000 » : un credit AUGMENTE le solde d'un compte crediteur.
        Livewire::test(GrandLivre::class)->set('compte', '701')
            ->assertSee('Créditeur par nature')
            ->assertSeeHtml('data-kpi="solde-final">120 000 FCFA<')
            ->assertSeeHtml('data-kpi="credit">120 000 FCFA<')
            ->assertSeeHtml('data-kpi="debit">0 FCFA<');

        // Avec une ouverture : le capital (101) — ouverture 100 000 (credit anterieur), +500 000 = 600 000.
        Livewire::test(GrandLivre::class)->set('compte', '101')
            ->assertSee('Créditeur par nature')
            ->assertSeeHtml('data-kpi="ouverture">100 000 FCFA<')
            ->assertSeeHtml('data-kpi="credit">500 000 FCFA<')
            ->assertSeeHtml('data-kpi="solde-final">600 000 FCFA<')
            ->assertSeeHtmlInOrder(['data-solde', '600 000']);
    }

    public function test_un_compte_sans_ecriture_dans_la_periode_le_dit(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(GrandLivre::class)->set('compte', '622')
            ->assertSeeHtml('data-vide="aucune-ecriture"')->assertSee('Aucune écriture ne correspond à ces critères.');
    }

    public function test_les_bornes_invalides_sont_ignorees_et_retirables(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(GrandLivre::class)->set('compte', '531')->set('debut', 'pas-une-date')
            ->assertSeeHtmlInOrder(['data-kpi="ouverture"', '100 000 FCFA'])
            ->set('debut', $this->annee().'-05-01')->call('retirerBorne', 'debut')->assertSet('debut', '');
    }

    // ----------------------------------------------------------------- Balance

    public function test_la_balance_a_six_colonnes_est_equilibree_et_ses_totaux_sont_ceux_du_jeu(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(BalanceGenerale::class)
            ->assertSeeHtmlInOrder(['data-kpi="debits"', '842 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="credits"', '842 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="ecart"', '0 FCFA'])
            ->assertSee('Total débiteur = total créditeur — équilibré')
            ->assertDontSeeHtml('data-bandeau="desequilibre"')
            // Totaux : ouverture D/C 100 000 ; mouvements D/C 987 000 ; final D/C 842 000.
            ->assertSeeHtmlInOrder(['data-total="ouverture_debit"', '100 000', 'data-total="ouverture_credit"', '100 000',
                'data-total="mouvements_debit"', '987 000', 'data-total="mouvements_credit"', '987 000',
                'data-total="final_debit"', '842 000', 'data-total="final_credit"', '842 000']);
    }

    public function test_la_balance_ligne_a_ligne(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(BalanceGenerale::class)
            ->assertSeeHtmlInOrder(['data-compte="101"', '100 000', '500 000', '600 000'])   // ouverture C, mouvement C, solde final C
            ->assertSeeHtmlInOrder(['data-compte="531"', '545 000'])
            ->assertSeeHtmlInOrder(['data-compte="401"', '42 000'])
            ->assertDontSeeHtml('data-compte="622"');                                         // jamais mouvemente : absent
    }

    public function test_mois_en_cours_deplace_la_frontiere_ouverture_mouvements(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        // Une ecriture du mois en cours : le reste (y compris l'exercice anterieur) passe en ouverture.
        $maintenant = now(config('logialvia.fuseau'));
        $this->poserPiece('OD-P1-'.$maintenant->year.'-0099', (int) $maintenant->year, (int) $maintenant->month, 1, 'OD', [['531', 1000, 0, null], ['101', 0, 1000, null]]);

        $c = Livewire::test(BalanceGenerale::class)->set('perimetre', 'mois')
            ->assertSee('Mois en cours — '.BalanceGenerale::MOIS[(int) $maintenant->month - 1].' '.$maintenant->year);
        // Les soldes FINAUX ne changent pas ; seuls les mouvements se restreignent au mois.
        $debitsParMois = [1 => 500000, 2 => 120000, 3 => 80000, 4 => 40000, 5 => 27000, 6 => 20000, 7 => 200000];
        $attendu = ($debitsParMois[(int) $maintenant->month] ?? 0) + 1000;
        $c->assertSeeHtmlInOrder(['data-total="final_debit"', '843 000']);
        $c->assertSeeHtmlInOrder(['data-total="mouvements_debit"', number_format($attendu, 0, ',', ' ')]);
    }

    public function test_une_balance_desequilibree_est_signalee_avec_le_ruban_rouge(): void
    {
        $this->poserLeJeuCommun();
        EcritureComptable::query()->where('numero_compte', '231')->update(['debit' => 150000]);   // corruption : le serveur ne la laisse pas passer par le fil
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(BalanceGenerale::class)
            ->assertSeeHtml('data-bandeau="desequilibre"')->assertSee('Balance Déséquilibrée — BR-CPT-004')
            ->assertSeeHtmlInOrder(['data-kpi="ecart"', '50 000 FCFA'])
            ->assertSee('Une clôture est impossible tant qu\'il subsiste (BR-CPT-004).', false);
    }

    public function test_une_balance_vide_explique_quand_elle_se_remplit(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(BalanceGenerale::class)->assertSeeHtml('data-vide')->assertSee('Aucun compte n\'a été mouvementé sur l\'exercice', false);
    }

    // -------------------------------------------------------------------- Plan

    public function test_le_plan_liste_les_24_comptes_filtre_et_masque_les_archives(): void
    {
        PlanComptable::query()->whereKey('613')->update(['archive' => true]);
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $c = Livewire::test(PlanComptableEcran::class)->assertSee('23 compte(s)')->assertDontSeeHtml('data-compte="613"');
        $c->set('archives', true)->assertSee('24 compte(s)')->assertSeeHtml('data-compte="613"')->assertSeeHtml('data-archive');
        $c->set('classe', '7')->assertSee('2 compte(s)')->assertSee('Ventes de Produits Avicoles')->assertDontSee('Caisse');
        $c->set('classe', '')->set('recherche', 'vétéri')->assertSee('Frais Vétérinaires');
        $c->set('recherche', '531')->assertSee('1 compte(s)')->assertSee('Débiteur');
        $c->set('recherche', '701')->assertSee('1 compte(s)')->assertSee('Créditeur');
    }

    public function test_creer_un_compte_passe_par_les_demandes_et_le_decide(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(PlanComptableEcran::class)->call('nouveau')
            ->set('numero', '635')->set('libelle', 'Frais bancaires')->set('classeCompte', '6')->call('enregistrer')
            ->assertSet('erreur', null)->assertSee('Compte 635 créé.');

        $compte = PlanComptable::query()->find('635');
        $this->assertSame('Frais bancaires', $compte->libelle);
        $this->assertGreaterThan($compte->created_at, $compte->updated_at, 'une demande acceptee decide le compte');
        $this->assertDatabaseHas('demandes_referentiel', ['type' => 'compte_comptable', 'cle' => '635', 'statut' => 'acceptee', 'device_id' => '00000000-0000-0000-0000-000000000000']);
    }

    public function test_la_saisie_d_un_compte_est_validee_avec_les_messages_du_poste(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        $c = Livewire::test(PlanComptableEcran::class)->call('nouveau');

        $c->set('numero', '')->call('enregistrer')->assertSet('erreur', 'Le numéro de compte est obligatoire.');
        $c->set('numero', '8x')->call('enregistrer')->assertSet('erreur', 'Un numéro de compte SYSCOHADA commence par un chiffre de 1 à 7.');
        $c->set('numero', '635')->set('libelle', '')->call('enregistrer')->assertSet('erreur', 'Le libellé est obligatoire.');
        $c->set('libelle', 'x')->set('classeCompte', '')->call('enregistrer')->assertSet('erreur', 'La classe est obligatoire.');
        $c->set('numero', '531')->set('classeCompte', '5')->call('enregistrer')->assertSet('erreur', 'Ce numéro de compte existe déjà.');
        $c->set('numero', '635')->set('classeCompte', '7')->call('enregistrer')->assertSet('erreur', 'Le numéro doit commencer par 7 pour appartenir à cette classe.');

        $this->assertFalse(PlanComptable::query()->whereKey('635')->exists());
    }

    public function test_modifier_un_compte_garde_son_numero_et_son_historique(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $c = Livewire::test(PlanComptableEcran::class)->call('modifier', '624')
            ->assertSet('numero', '624')->assertSet('libelle', 'Transports')
            ->set('libelle', 'Transports et déplacements')->call('enregistrer')
            ->assertSee('Compte 624 modifié.');

        $this->assertSame('Transports et déplacements', PlanComptable::query()->find('624')->libelle);
        $this->assertSame(1, EcritureComptable::query()->where('numero_compte', '624')->count());
        // Le numero n'est pas modifiable : meme si le composant recoit une autre valeur, il garde le sien.
        $c->call('modifier', '624')->set('numero', '999')->call('enregistrer');
        $this->assertFalse(PlanComptable::query()->whereKey('999')->exists());
        $this->assertSame('6', PlanComptable::query()->find('624')->classe);
    }

    public function test_archiver_demande_confirmation_reactiver_non(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        $c = Livewire::test(PlanComptableEcran::class)->call('basculerArchive', '613')
            ->assertSeeHtml('data-modale="archivage"')->assertSee('Archiver le compte 613 ?');
        $this->assertFalse(PlanComptable::query()->find('613')->archive, 'rien n\'est archive avant confirmation');
        $c->call('confirmerArchivage')->assertSee('Compte 613 archivé.');
        $this->assertTrue(PlanComptable::query()->find('613')->archive);

        $c->call('basculerArchive', '613')->assertDontSeeHtml('data-modale="archivage"')->assertSee('Compte 613 réactivé.');
        $this->assertFalse(PlanComptable::query()->find('613')->archive);
    }

    public function test_les_methodes_d_ecriture_du_plan_refusent_qui_n_a_pas_le_droit(): void
    {
        $lecteur = User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-comptabilite');
        $this->actingAs($lecteur);

        foreach (['nouveau' => [], 'modifier' => ['624'], 'enregistrer' => [], 'basculerArchive' => ['624'], 'confirmerArchivage' => []] as $methode => $args) {
            Livewire::test(PlanComptableEcran::class)->call($methode, ...$args)->assertForbidden();
        }
        $this->assertFalse(PlanComptable::query()->find('624')->archive);
    }

    // ------------------------------------------------------------- Analytique

    public function test_l_analytique_ventile_par_axe_puis_par_compte_sans_rien_perdre(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Analytique::class)
            ->assertSeeHtmlInOrder(['data-centre="Goliaths"', '120 000', '120 000'])               // revenus, marge
            ->assertSeeHtmlInOrder(['data-centre="Pintades"', '15 000'])                           // couts imputes par l'axe
            ->assertSeeHtmlInOrder(['data-centre="Commerce Annexe"', 'Comptes 707 et 602', '80 000'])
            ->assertSeeHtmlInOrder(['data-centre="Avicole — filière non précisée"', '40 000'])
            ->assertSeeHtmlInOrder(['data-total-marge', '145 000'])                                // Σ marges
            ->assertSee('Charges de structure non affectées à un centre : 12 000 FCFA');
    }

    public function test_l_invariant_marges_plus_produits_non_affectes_moins_charges_egale_le_resultat(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        // 145 000 (Σ marges) − 12 000 (charges de structure) = 133 000 = resultat net.
        Livewire::test(Analytique::class)->assertSeeHtmlInOrder(['data-total-marge', '145 000'])->assertSee('12 000 FCFA');
        Livewire::test(Comptabilite::class)->assertSee('133 000');
    }

    public function test_l_analytique_vide_et_le_graphique_vide_disent_quand_ils_apparaitront(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Analytique::class)
            ->assertSee('Les marges apparaîtront dès la première vente enregistrée.')
            ->assertSee('Le graphique apparaîtra dès qu\'un revenu sera enregistré.', false);
    }

    public function test_les_barres_du_graphique_sont_proportionnelles_aux_revenus(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Analytique::class)->assertSeeHtml('data-barre="Goliaths"')
            ->assertSeeHtml('width: 100%')       // Goliaths : revenus maximum
            ->assertSeeHtml('width: 66.7%');     // Commerce Annexe : 80 000 / 120 000
    }

    // --------------------------------------------------------- Etats financiers

    public function test_le_bilan_est_equilibre_et_ses_postes_sont_ceux_du_jeu(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(EtatsFinanciers::class)->assertSee('Actif = Passif')->assertSee('non clôturé')
            // Ouverture CUMULEE : immobilisation 200 000 + creances 30 000 + tresorerie 545 000 = capital 600 000 + resultat 133 000 + dettes 42 000.
            ->assertSeeHtmlInOrder(['data-total="actif"', '775 000'])
            ->assertSeeHtmlInOrder(['data-total="passif"', '775 000'])
            ->assertSeeHtmlInOrder(['data-poste="Immobilisations Corporelles"', '200 000'])
            ->assertSeeHtmlInOrder(['data-poste="Créances et Emplois Assimilés"', '30 000'])
            ->assertSeeHtmlInOrder(['data-poste="Trésorerie-Actif"', '545 000'])
            ->assertSeeHtmlInOrder(['data-poste="Capital"', '600 000'])
            ->assertSeeHtmlInOrder(['data-poste="Résultat Net de l\'Exercice"', '133 000'])
            ->assertSeeHtmlInOrder(['data-poste="Dettes Circulantes"', '42 000']);
    }

    public function test_le_compte_de_resultat_donne_le_meme_resultat_net_que_le_bilan(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(EtatsFinanciers::class)->call('choisir', 'resultat')
            ->assertSeeHtmlInOrder(['data-poste="MARGE COMMERCIALE"', '80 000'])
            ->assertSeeHtmlInOrder(['data-poste="Ventes de Produits Avicoles"', '120 000'])
            ->assertSeeHtmlInOrder(['data-poste="Consommations en Provenance des Tiers"', '67 000'])
            ->assertSeeHtmlInOrder(['data-poste="VALEUR AJOUTÉE"', '133 000'])
            ->assertSeeHtmlInOrder(['data-poste="EXCÉDENT BRUT D\'EXPLOITATION"', '133 000'])
            ->assertSeeHtmlInOrder(['data-poste="RÉSULTAT NET DE L\'EXERCICE"', '133 000'])
            ->assertSee('toujours strictement identiques');
    }

    public function test_le_tafire_reprend_le_calcul_du_poste_et_sa_verification_de_coherence(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        // Chiffres du Dart sur le jeu commun (voir jeu_commun_chiffres_test.dart), calcules a la main :
        // exploitation 145 000, investissement −200 000, financement 500 000 (l'apport), variation 445 000,
        // tresorerie d'ouverture 100 000 → de cloture 545 000 = tresorerie nette du bilan : plus d'incoherence.
        Livewire::test(EtatsFinanciers::class)->call('choisir', 'flux')
            ->assertSeeHtmlInOrder(['data-poste="FLUX NET DE TRÉSORERIE D\'EXPLOITATION"', '145 000'])
            ->assertSeeHtmlInOrder(['data-poste="FLUX NET DE TRÉSORERIE D\'INVESTISSEMENT"', '-200 000'])
            ->assertSeeHtmlInOrder(['data-poste="FLUX NET DE TRÉSORERIE DE FINANCEMENT"', '500 000'])
            ->assertSeeHtmlInOrder(['data-poste="VARIATION DE TRÉSORERIE DE LA PÉRIODE"', '445 000'])
            ->assertSee('Trésorerie de clôture (TAFIRE) = Trésorerie nette (Bilan) = 545 000 FCFA.')
            ->assertDontSee('Incohérence');
    }

    public function test_un_tafire_sans_ouverture_est_coherent(): void
    {
        $this->poserPiece('OD-P1-'.$this->annee().'-0001', $this->annee(), 1, 2, 'OD', [['531', 1000, 0, null], ['101', 0, 1000, null]]);
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(EtatsFinanciers::class)->call('choisir', 'flux')
            ->assertSee('Trésorerie de clôture (TAFIRE) = Trésorerie nette (Bilan) = 1 000 FCFA.');
    }

    public function test_les_notes_2_3_et_4_sont_calculees_depuis_la_balance(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(EtatsFinanciers::class)->call('choisir', 'notes')
            ->assertSee('Note 2 — Immobilisations')->assertSee('Bâtiments')
            ->assertSeeHtmlInOrder(['data-total-note="2"', '200 000'])
            ->assertSee('Aucun compte de stock (classe 3) n\'est mouvementé.', false)
            ->assertSeeHtmlInOrder(['data-tiers="411"', 'Créance', '30 000'])
            ->assertSeeHtmlInOrder(['data-tiers="401"', 'Dette', '42 000']);
    }

    public function test_les_notes_redactionnelles_ont_le_texte_du_poste_par_defaut_et_s_enregistrent(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        // Les notes 1 et 5 vivent dans un champ de saisie : leur valeur est une propriete du composant.
        $c = Livewire::test(EtatsFinanciers::class)->call('choisir', 'notes')
            ->assertSet('notes.1', EtatsFinanciers::NOTE_1_PAR_DEFAUT)
            ->assertSet('notes.5', 'Néant à la date de clôture de la période présentée.')
            ->set('notes.1', '  Coût historique, CMUP.  ')
            ->call('enregistrerNote', 1)
            ->assertSee('Note 1 enregistrée.');

        $note = NoteAnnexe::query()->firstOrFail();
        $this->assertSame(UuidDeterministe::note($this->annee(), 1), $note->id);
        $this->assertSame('Coût historique, CMUP.', $note->contenu);
        $this->assertSame('Méthodes Comptables', $note->titre);
        $this->assertSame('00000000-0000-0000-0000-000000000000', $note->device_id);

        // Reouverte, la note enregistree remplace le texte par defaut ; la plus recente gagne.
        $c->set('notes.1', 'Deuxieme version')->call('enregistrerNote', 1);
        $this->assertSame(1, NoteAnnexe::query()->count());
        $this->assertSame('Deuxieme version', NoteAnnexe::query()->first()->contenu);
        Livewire::test(EtatsFinanciers::class)->call('choisir', 'notes')->assertSet('notes.1', 'Deuxieme version');
    }

    public function test_seules_les_notes_1_et_5_s_ecrivent_et_il_faut_le_droit(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        Livewire::test(EtatsFinanciers::class)->call('enregistrerNote', 3)->assertStatus(422);
        $this->assertSame(0, NoteAnnexe::query()->count());

        $lecteur = User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-comptabilite');
        $this->actingAs($lecteur);
        Livewire::test(EtatsFinanciers::class)->call('enregistrerNote', 1)->assertForbidden();
        $this->assertSame(0, NoteAnnexe::query()->count());
    }

    public function test_un_onglet_inconnu_est_ignore(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(EtatsFinanciers::class)->call('choisir', 'inconnu')->assertSet('onglet', 'bilan')
            ->call('choisir', 'notes')->assertSet('onglet', 'notes');
    }

    // ------------------------------------------------------- Bilan de l'entreprise

    public function test_le_bilan_de_l_entreprise_lit_le_capital_au_101_et_ne_perd_pas_les_immobilisations(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        // Ouverture cumulee. Actif : immobilisation 200 000 + creances 30 000 + tresorerie 545 000 = 775 000 ;
        // passif : 600 000 + 133 000 + 42 000 = 775 000. L'ancien ecart de −200 000 etait l'immobilisation (231),
        // absente de l'ecran.
        Livewire::test(BilanEntreprise::class)
            ->assertSeeHtmlInOrder(['data-carte="actif"', 'data-poste="2"', '200 000', 'data-poste="411"', '30 000', 'data-poste="531"', '545 000', 'data-total="actif"', '775 000'])
            ->assertSeeHtmlInOrder(['data-carte="passif"', 'data-poste="101"', '600 000', 'data-poste="13"', '133 000', 'data-poste="401"', '42 000', 'data-total="passif"', '775 000'])
            ->assertDontSeeHtml('data-ligne="ecart"');
    }

    public function test_un_actif_superieur_au_passif_renvoie_au_compte_101(): void
    {
        $this->poserPiece('OD-P1-'.$this->annee().'-0001', $this->annee(), 1, 2, 'OD', [['531', 1000, 0, null], ['701', 0, 1000, null]]);
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        // Actif 1 000 ; passif : resultat 1 000 → equilibre. Tous les comptes etant desormais portes par une
        // ligne du bilan, seule une ecriture DESEQUILIBREE (un debit sans contrepartie) laisse un ecart :
        $this->poserPiece('OD-P1-'.$this->annee().'-0002', $this->annee(), 1, 3, 'OD', [['531', 500, 0, null]]);

        Livewire::test(BilanEntreprise::class)
            ->assertSee('Écart de 500 FCFA entre l\'actif et le passif.', false)
            ->assertSee('L\'entreprise détient des biens dont l\'origine n\'a pas été enregistrée', false)
            ->assertSee('Saisissez-le au compte 101 (Capital) depuis le Journal Comptable.');
    }

    public function test_un_bilan_equilibre_ou_vide_n_a_pas_de_ligne_d_ecart(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        Livewire::test(BilanEntreprise::class)->assertSeeHtml('data-bandeau="vide"')->assertDontSeeHtml('data-ligne="ecart"')
            ->assertSee('Aucune écriture sur l\'exercice', false);

        $this->poserPiece('OD-P1-'.$this->annee().'-0001', $this->annee(), 1, 2, 'OD', [['531', 1000, 0, null], ['101', 0, 1000, null]]);
        Livewire::test(BilanEntreprise::class)->assertSeeHtml('data-bandeau="equilibre"')->assertDontSeeHtml('data-ligne="ecart"')
            ->assertSee('Bilan équilibré — Total Actif = Total Passif = 1 000 FCFA.');
    }

    // ------------------------------------------------------------------ Cloture

    public function test_la_cloture_montre_la_frise_les_kpi_et_les_12_mois(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));

        $c = Livewire::test(Cloture::class)
            ->assertSeeHtml('data-jeton="'.$this->annee().'"')->assertSeeHtml('data-jeton="'.($this->annee() - 1).'"')
            ->assertSeeHtmlInOrder(['data-kpi="resultat"', '133 000 FCFA'])
            ->assertSeeHtmlInOrder(['data-kpi="comptes-gestion"', '5'])      // 701, 707, 601, 624, 616
            ->assertSeeHtmlInOrder(['data-kpi="balance"', 'Équilibrée']);
        foreach (range(1, 12) as $m) {
            $c->assertSeeHtml('data-mois="'.$m.'"');
        }
        $c->assertSee('En cours');
    }

    public function test_cloturer_un_mois_le_verrouille_puis_le_declôturer_est_reserve_a_l_administratrice(): void
    {
        $this->poserLeJeuCommun();
        $comptable = $this->utilisateurAvecRole('comptable', 'paul');
        $this->actingAs($comptable);
        $n = $this->annee();

        $c = Livewire::test(Cloture::class)->call('basculerMois', 3)->assertSet('erreur', null)->assertSee('Mois de Mars clôturé.');
        $clot = CloturePeriodique::query()->where('annee', $n)->where('mois', 3)->firstOrFail();
        $this->assertTrue($clot->is_cloture);
        $this->assertSame(UuidDeterministe::cloturePeriodique($n, 3), $clot->id);
        $this->assertSame('00000000-0000-0000-0000-000000000000', $clot->device_id);

        // Le comptable ne peut pas le rouvrir.
        $c->call('basculerMois', 3)->assertForbidden();
        $this->assertTrue(CloturePeriodique::query()->where('mois', 3)->first()->is_cloture);

        // L'administratrice, si — avec trace d'audit.
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));
        Livewire::test(Cloture::class)->call('basculerMois', 3)
            ->assertSee('Mois de Mars déclôturé — action tracée dans le journal d\'audit.');
        $this->assertFalse(CloturePeriodique::query()->where('mois', 3)->first()->is_cloture);
        $this->assertDatabaseHas('audit_logs', ['action' => 'comptabilite.decloture']);
    }

    public function test_un_mois_cloture_refuse_une_ecriture_a_sa_date(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));
        Livewire::test(Cloture::class)->call('basculerMois', 8);
        $n = $this->annee();

        $motif = (new \App\Services\Comptabilite\Saisie(auth()->user()))->enregistrer(
            \Carbon\CarbonImmutable::create($n, 8, 12, 10, 0, 0, config('logialvia.fuseau'))->utc()->format('Y-m-d\TH:i:s.u\Z'),
            'OD', 'OD-WEB-'.$n.'-0001',
            [['compte' => '531', 'debit' => 10, 'credit' => 0, 'libelle' => 'x'], ['compte' => '701', 'debit' => 0, 'credit' => 10, 'libelle' => 'x']],
        );

        $this->assertStringContainsString("Le mois 8/$n est clôturé", (string) $motif);
    }

    public function test_une_cloture_est_refusee_sur_balance_desequilibree_avec_le_message_du_poste(): void
    {
        $this->poserLeJeuCommun();
        EcritureComptable::query()->where('numero_compte', '231')->update(['debit' => 150000]);
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));

        $c = Livewire::test(Cloture::class)->call('basculerMois', 3)
            ->assertSet('erreur', 'Balance déséquilibrée de 50 000 FCFA. Corrigez la saisie avant toute clôture (BR-CPT-004).');
        $this->assertSame(0, CloturePeriodique::query()->count());

        $c->call('demanderCloture')->call('cloturerExercice')
            ->assertSet('erreur', 'Balance déséquilibrée de 50 000 FCFA. Une clôture annuelle est définitive : elle ne peut pas s\'exécuter sur une comptabilité déséquilibrée (BR-CPT-004).');
        $this->assertFalse(ExerciceComptable::query()->find($this->annee())->is_cloture);
    }

    public function test_seule_l_administratrice_cloture_l_exercice_qui_ouvre_le_suivant(): void
    {
        $this->poserLeJeuCommun();
        $n = $this->annee();

        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        Livewire::test(Cloture::class)->call('demanderCloture')->assertForbidden();
        Livewire::test(Cloture::class)->call('cloturerExercice')->assertForbidden();
        $this->assertFalse(ExerciceComptable::query()->find($n)->is_cloture);

        $admin = $this->utilisateurAvecRole('admin', 'gerante');
        $this->actingAs($admin);
        Livewire::test(Cloture::class)
            ->call('demanderCloture')->assertSeeHtml('data-modale="cloture"')
            ->assertSee('Clôturer définitivement l\'exercice '.$n.' ?', false)->assertSee('le résultat net arrêté est de 133 000 FCFA')
            ->call('cloturerExercice')
            ->assertSee("Exercice $n clôturé. L'exercice ".($n + 1).' est ouvert.')
            ->assertSee('Exercice '.$n.' clôturé et verrouillé.')->assertSee('Clôturé');

        $e = ExerciceComptable::query()->find($n);
        $this->assertTrue($e->is_cloture);
        $this->assertSame($admin->getKey(), $e->cloture_par);
        $this->assertFalse(ExerciceComptable::query()->find($n + 1)->is_cloture);
        $this->assertDatabaseHas('clotures_exercice', ['annee' => $n, 'id' => UuidDeterministe::clotureExercice($n)]);
        $this->assertDatabaseHas('audit_logs', ['action' => 'comptabilite.cloture_exercice']);
    }

    public function test_apres_la_cloture_plus_rien_ne_s_ecrit_dans_l_exercice_et_on_ne_re_cloture_pas(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));
        $c = Livewire::test(Cloture::class)->call('demanderCloture')->call('cloturerExercice');

        $c->call('cloturerExercice')->assertSet('erreur', 'Cet exercice est déjà clôturé.');
        $c->call('basculerMois', 2)->assertSet('erreur', 'L\'exercice est déjà clôturé.');
        Livewire::test(Journal::class)->call('nouvelle')->set('libelle', 'x')->set('montant', '1')->call('enregistrer')
            ->assertSee('est clôturé : aucune écriture ne peut y être ajoutée');
        Livewire::test(Journal::class)->assertSee('Clôturé')->assertSeeHtml('data-badge="cloture"');
    }

    public function test_les_methodes_de_cloture_refusent_qui_n_a_pas_le_droit(): void
    {
        $lecteur = User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-comptabilite');
        $this->actingAs($lecteur);

        foreach (['basculerMois' => [3], 'demanderCloture' => [], 'cloturerExercice' => []] as $methode => $args) {
            Livewire::test(Cloture::class)->call($methode, ...$args)->assertForbidden();
        }
        $this->assertSame(0, CloturePeriodique::query()->count());
        $this->assertFalse(ExerciceComptable::query()->firstOrCreate(['annee' => $this->annee()], ['is_cloture' => false])->is_cloture);
    }

    public function test_un_mois_hors_1_12_est_refuse(): void
    {
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));

        Livewire::test(Cloture::class)->call('basculerMois', 13)->assertStatus(422);
        Livewire::test(Cloture::class)->call('basculerMois', 0)->assertStatus(422);
    }

    public function test_les_ecrans_ne_creent_jamais_un_exercice_inconnu(): void
    {
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));

        Livewire::test(Cloture::class)->set('exercice', 1850)->assertOk();
        $this->assertFalse(ExerciceComptable::query()->whereKey(1850)->exists());
    }

    public function test_une_piece_ne_change_jamais_apres_son_ecriture_au_web(): void
    {
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));
        Livewire::test(Journal::class)->call('nouvelle')->set('libelle', 'x')->set('montant', '100')->call('enregistrer');
        $piece = PieceComptable::query()->firstOrFail();
        $avant = $piece->only(['updated_at', 'serveur_modifie_le', 'numero_piece']);
        $lignes = EcritureComptable::query()->count();

        // Rejouer la meme piece par le meme chemin : acceptee, sans rien changer.
        $motif = (new \App\Sync\Tables\EcrituresTable)->pourUtilisateur(auth()->user())->absorber('x', [
            'id' => $piece->id, 'numero_piece' => 'AUTRE', 'date_ecriture' => now()->toIso8601String(), 'exercice_annee' => $this->annee(),
            'journal_code' => 'OD', 'updated_at' => now()->toIso8601String(),
            'lignes' => [
                ['id' => (string) Str::uuid(), 'numero_compte' => '531', 'debit' => 9, 'credit' => 0, 'libelle' => 'x'],
                ['id' => (string) Str::uuid(), 'numero_compte' => '701', 'debit' => 0, 'credit' => 9, 'libelle' => 'x'],
            ],
        ]);

        $this->assertNull($motif);
        $this->assertSame($lignes, EcritureComptable::query()->count());
        $this->assertEquals($avant, $piece->fresh()->only(['updated_at', 'serveur_modifie_le', 'numero_piece']));
    }

    public function test_les_pieces_d_un_poste_apparaissent_au_web_avec_leur_code_de_poste(): void
    {
        $this->poserLeJeuCommun();
        \App\Models\Poste::query()->create([
            'device_id' => '11111111-1111-4111-8111-111111111111', 'code' => 'P7', 'appaire_le' => now(),
        ]);
        $this->actingAs($this->utilisateurAvecRole('comptable', 'paul'));

        Livewire::test(Journal::class)->assertSee('· P7')->assertDontSee('Poste 11111111');
    }

    public function test_les_ecrans_tiennent_en_mode_cartes_sous_640_px_sans_defilement_cache(): void
    {
        $this->poserLeJeuCommun();
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'));

        foreach (['/comptabilite/journal', '/comptabilite/balance', '/comptabilite/plan', '/comptabilite/analytique'] as $route) {
            $this->get($route)->assertOk()->assertSeeHtml('data-vue="cartes"')->assertSeeHtml('hidden overflow-x-auto');
        }
    }
}
