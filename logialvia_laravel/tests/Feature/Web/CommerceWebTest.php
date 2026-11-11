<?php

namespace Tests\Feature\Web;

use App\Livewire\Clients;
use App\Livewire\Ventes;
use App\Models\Client;
use App\Models\FicheVentesJour;
use App\Models\LigneVente;
use App\Models\MouvementProduit;
use App\Models\ParametresEntreprise;
use App\Models\PieceComptable;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Models\Vente;
use App\Support\ExportXlsx;
use App\Support\UuidDeterministe;
use App\Livewire\Catalogue;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Features\SupportTesting\Testable;
use Livewire\Livewire;
use Tests\Concerns\JeuComptable;
use Tests\Concerns\LitXlsx;
use Tests\TestCase;

/**
 * Commerce au web : caisse, historique (annulation, modification), retours, recouvrement, vues imprimables,
 * exports XLSX. Ecritures : `EcrituresAutomatiquesVentesTest` (jeu commun avec le poste).
 */
class CommerceWebTest extends TestCase
{
    use JeuComptable, LitXlsx, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerPourLesEcrans();
        // Midi (heure de l'entreprise).
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-11-09 12:00:00', config('logialvia.fuseau')));
    }

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    /** @var array<string, User> */
    private array $comptes = [];

    private function caissier(): User
    {
        return $this->comptes['caissier'] ??= $this->utilisateurAvecRole('caissier', 'amina');
    }

    private function comptable(): User
    {
        return $this->comptes['comptable'] ??= $this->utilisateurAvecRole('comptable', 'paul');
    }

    private function produit(string $nom = 'Goliath mature', float $prix = 6000, array $surcharge = []): ProduitVendable
    {
        return ProduitVendable::query()->firstOrCreate(['name' => $nom], $surcharge + [
            'cat' => 'Avicole', 'price' => $prix, 'price_max' => null, 'unit' => 'u', 'icon' => 'egg', 'espece' => 'goliaths', 'saisi_le' => now(),
        ]);
    }

    private function caisse(?User $u = null): Testable
    {
        return Livewire::actingAs($u ?? $this->caissier())->test(Ventes::class);
    }

    /** Vend un goliath 6 000 comptant par l'ecran ; renvoie la vente. */
    private function vendre(Testable $c, array $surcharge = []): Vente
    {
        $p = $this->produit();
        foreach ($surcharge + ['panier' => [['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 1, 'montant' => 6000.0]], 'montantRecu' => '6000'] as $champ => $valeur) {
            $c->set($champ, $valeur);
        }
        $c->call('encaisser')->assertSet('erreur', null);

        return Vente::query()->orderByDesc('reference')->firstOrFail();
    }

    /** Une vente de poste, avec sa piece, posee en base comme le serveur l'aurait recue. */
    private function venteDePoste(array $surcharge = [], bool $avecPiece = true): Vente
    {
        $p = $this->produit();
        $v = (new Vente)->forceFill(array_merge([
            'id' => (string) Str::uuid(), 'device_id' => '11111111-1111-4111-8111-111111111111',
            'reference' => 'V-P1-2026-001', 'portee_reference' => '', 'client' => 'Kofi', 'client_id' => null,
            'date_vente' => CarbonImmutable::now(), 'mode' => 'Espèces', 'status' => 'Payée', 'total' => 6000, 'paye' => 6000,
            'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ], $surcharge));
        $v->save();
        (new LigneVente)->forceFill(['id' => (string) Str::uuid(), 'vente_id' => $v->id, 'produit_id' => $p->id, 'name' => $p->name, 'qte' => 1, 'pu' => 6000, 'espece' => 'goliaths'])->save();
        if ($avecPiece) {
            $this->poserPiece($v->reference, 2026, 11, 9, 'VT', [['571', 6000, 0, null], ['702', 0, 6000, 'Goliaths']], ['vente_ref' => $v->reference]);
        }

        return $v;
    }

    private function xlsx(Testable $c): array
    {
        return $this->lignesXlsx(base64_decode($c->effects['download']['content']));
    }

    // ------------------------------------------------------------------ Acces

    public function test_acces_et_onglets(): void
    {
        $this->get('/ventes')->assertRedirect(route('login'));
        $this->actingAs($this->utilisateurAvecRole('animalier', 'koffi'))->get('/ventes')->assertForbidden();
        $this->actingAs($this->caissier())->get('/ventes')->assertOk()
            ->assertSee('Point de Vente')->assertSee('Historique des Ventes')->assertSee('Retours et Avoirs')
            ->assertSee('Valider la Vente');
        $this->caisse()->assertSet('onglet', 'caisse')->call('choisirOnglet', 'retours')->assertSet('onglet', 'retours')
            ->call('choisirOnglet', 'inconnu')->assertSet('onglet', 'retours');
    }

    public function test_le_comptable_ne_voit_pas_la_caisse_et_chaque_methode_d_ecriture_est_interdite(): void
    {
        $v = $this->venteDePoste();
        $c = $this->comptable();
        Livewire::actingAs($c)->test(Ventes::class)->assertDontSee('Valider la Vente')->assertSeeHtml('data-lecture-seule');

        $appels = [
            'choisirProduit' => ['x'], 'modifierLigne' => [0], 'annulerAjout' => null, 'validerAjout' => [], 'retirerLigne' => [0], 'viderPanier' => [],
            'choisirClient' => ['x'], 'encaisser' => [], 'demanderAnnulation' => [$v->id], 'confirmerAnnulation' => [],
            'demanderModification' => [$v->id], 'choisirClientModification' => ['x'], 'enregistrerModification' => [],
        ];
        foreach ($appels as $methode => $args) {
            if ($args === null) {
                continue; // annulerAjout ne fait que fermer une fenetre locale
            }
            Livewire::actingAs($c)->test(Ventes::class)->call($methode, ...$args)->assertForbidden();
        }
        foreach (['demanderRecouvrement' => [$v->id], 'enregistrerRecouvrement' => []] as $methode => $args) {
            Livewire::actingAs($c)->test(Clients::class)->call($methode, ...$args)->assertForbidden();
        }
        // Meme sans composant d'ecran, le service refuse.
        $service = new \App\Services\Commerce\VentesWeb($c);
        $this->assertStringContainsString('Droit insuffisant', (string) $service->annuler($v->id, 'Autre'));
        $this->assertStringContainsString('Droit insuffisant', (string) $service->modifier($v->id, ['client' => 'X']));
        $this->assertStringContainsString('Droit insuffisant', (string) $service->recouvrer($v->id, 1, 'Espèces'));
        $this->assertStringContainsString('Droit insuffisant', (string) $service->encaisser([])['motif']);
        $this->assertSame('Payée', $v->fresh()->status);
        $this->assertSame(1, Vente::query()->count());
    }

    // ------------------------------------------------------------------ Caisse

    public function test_la_grille_montre_les_produits_avec_leur_fourchette_et_filtre(): void
    {
        $this->produit('Goliath mature', 6000, ['price_max' => 7500]);
        $this->produit('Tee-shirt enfant', 1000, ['cat' => 'Commerce Annexe', 'espece' => null]);
        $this->produit('Ancien produit', 100, ['archive_le' => now()]);

        $this->caisse()->assertSeeHtml('data-produit="Goliath mature"')->assertSee('6 000 – 7 500 F')
            ->assertSeeHtml('data-produit="Tee-shirt enfant"')->assertDontSeeHtml('data-produit="Ancien produit"')
            ->set('categorie', 'Commerce Annexe')->assertDontSeeHtml('data-produit="Goliath mature"')
            ->set('categorie', '')->set('rechercheProduit', 'tee')->assertSeeHtml('data-produit="Tee-shirt enfant"')->assertDontSeeHtml('data-produit="Goliath mature"')
            ->set('rechercheProduit', 'zzz')->assertSee('Aucun produit ne correspond à ce filtre.');
    }

    public function test_la_vente_a_la_piece_saisit_le_montant_global_jamais_qte_fois_prix(): void
    {
        $p = $this->produit('Goliath mature', 6000, ['price_max' => 7500]);
        $c = $this->caisse()->assertSee('Panier vide. Cliquez sur un produit pour l\'ajouter.', false)
            ->call('choisirProduit', $p->id)->assertSet('ajoutMontant', '6000')->assertSeeHtml('data-modale="vente-a-la-piece"')
            ->assertSee('prix indicatif 6 000 à 7 500 FCFA')->assertSee('jamais un prix unitaire multiplié automatiquement')
            ->set('ajoutQte', '3')->set('ajoutMontant', '16 000')->call('validerAjout')
            ->assertSeeHtml('data-ligne-panier="Goliath mature"')->assertSeeHtml('data-total>16 000 FCFA');

        // Un meme produit s'empile a un autre montant ; on modifie, on retire.
        $c->call('choisirProduit', $p->id)->set('ajoutQte', '1')->set('ajoutMontant', '5000')->call('validerAjout')->assertSeeHtml('data-total>21 000 FCFA')
            ->call('modifierLigne', 1)->assertSet('ajoutQte', '1')->set('ajoutMontant', '5500')->call('validerAjout')->assertSeeHtml('data-total>21 500 FCFA')
            ->call('retirerLigne', 0)->assertSeeHtml('data-total>5 500 FCFA')->assertCount('panier', 1);
    }

    public function test_validations_de_l_ajout_au_panier_message_pour_message(): void
    {
        $p = $this->produit();
        $c = $this->caisse();
        foreach ([['', '100'], ['0', '100'], ['1.5', '100'], ['abc', '100'], ['1', ''], ['1', '0'], ['1', '-5'], ['1', 'x']] as [$qte, $montant]) {
            $c->call('choisirProduit', $p->id)->set('ajoutQte', $qte)->set('ajoutMontant', $montant)->call('validerAjout')
                ->assertSet('erreurAjout', 'Veuillez saisir une quantité et un montant valides.')->assertCount('panier', 0);
        }
        // Produit archive entre l'ouverture de la modale et la validation.
        $c->call('choisirProduit', $p->id)->set('ajoutQte', '1')->set('ajoutMontant', '10');
        $p->update(['archive_le' => now()]);
        $c->call('validerAjout')->assertSet('erreurAjout', 'Ce produit n\'est plus au catalogue.')->assertCount('panier', 0);
    }

    public function test_validations_de_l_encaissement_message_pour_message(): void
    {
        $p = $this->produit();
        $ligne = ['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 1, 'montant' => 6000.0];
        $cas = [
            'panier vide' => [['panier' => [], 'montantRecu' => '6000'], 'Le panier est vide.'],
            'comptant insuffisant' => [['panier' => [$ligne], 'montantRecu' => '5999'], 'Le montant reçu est inférieur au total de la vente.'],
            'comptant sans montant' => [['panier' => [$ligne], 'montantRecu' => ''], 'Le montant reçu est inférieur au total de la vente.'],
            'avance sans montant' => [['panier' => [$ligne], 'condition' => 'Avance (Solde Restant Dû)', 'montantRecu' => ''], 'Veuillez saisir le montant reçu pour une vente à crédit.'],
            'avance qui solde' => [['panier' => [$ligne], 'condition' => 'Avance (Solde Restant Dû)', 'montantRecu' => '6000'], 'Le montant reçu solde la vente : choisissez « Comptant ».'],
            'mobile money sans numero' => [['panier' => [$ligne], 'mode' => 'Mobile Money', 'montantRecu' => '6000'], 'Aucun numéro Mobile Money n\'est enregistré. Renseignez le Téléphone Principal dans Paramètres Généraux avant d\'encaisser par Mobile Money.'],
            'livraison facturee sans frais' => [['panier' => [$ligne], 'montantRecu' => '6000', 'livraisonActive' => true, 'livraisonMode' => 'facturee', 'livraisonFrais' => ''], 'Une livraison facturée séparément exige un montant de frais.'],
            'livraison facturee frais nuls' => [['panier' => [$ligne], 'montantRecu' => '6000', 'livraisonActive' => true, 'livraisonMode' => 'facturee', 'livraisonFrais' => '0'], 'Une livraison facturée séparément exige un montant de frais.'],
            'livraison inconnue' => [['panier' => [$ligne], 'montantRecu' => '6000', 'livraisonActive' => true, 'livraisonMode' => 'drone'], 'Le mode de livraison est inconnu.'],
            'echeance invalide' => [['panier' => [$ligne], 'condition' => 'Avance (Solde Restant Dû)', 'montantRecu' => '1000', 'echeance' => '2026-02-30'], 'L\'échéance de paiement est invalide.'],
            'mode inconnu' => [['panier' => [$ligne], 'mode' => 'Troc', 'montantRecu' => '6000'], 'Le mode de règlement est inconnu.'],
            'condition inconnue' => [['panier' => [$ligne], 'condition' => 'Crédit', 'montantRecu' => '6000'], 'La condition de paiement est inconnue.'],
        ];
        // La ligne Mobile Money vient des Parametres Generaux : vide pour ce test.
        ParametresEntreprise::courant()->update(['telephone' => null]);
        foreach ($cas as $nom => [$etat, $message]) {
            $c = $this->caisse();
            foreach ($etat as $champ => $valeur) {
                $c->set($champ, $valeur);
            }
            $c->call('encaisser')->assertSet('erreur', $message);
            $this->assertSame(0, Vente::query()->count(), "aucune vente : $nom");
            $this->assertSame(0, PieceComptable::query()->count(), "aucune piece : $nom");
        }
    }

    public function test_une_ligne_de_panier_falsifiee_est_refusee_par_le_service(): void
    {
        $p = $this->produit();
        $service = new \App\Services\Commerce\VentesWeb($this->caissier());
        foreach ([
            [['produit_id' => $p->id, 'qte' => 0, 'montant' => 100], 'Veuillez saisir une quantité et un montant valides.'],
            [['produit_id' => $p->id, 'qte' => 1.5, 'montant' => 100], 'Veuillez saisir une quantité et un montant valides.'],
            [['produit_id' => $p->id, 'qte' => 1, 'montant' => 0], 'Veuillez saisir une quantité et un montant valides.'],
            [['produit_id' => (string) Str::uuid(), 'qte' => 1, 'montant' => 100], 'Ce produit n\'est plus au catalogue.'],
        ] as [$ligne, $message]) {
            $this->assertSame($message, $service->encaisser(['mode' => 'Espèces', 'condition' => 'Comptant', 'montant_recu' => 100, 'lignes' => [$ligne]])['motif']);
        }
        $this->assertSame(0, Vente::query()->count());
    }

    public function test_un_produit_archive_n_est_plus_vendable_meme_par_un_appel_direct(): void
    {
        $p = $this->produit();
        $p->update(['archive_le' => now()]);
        $service = new \App\Services\Commerce\VentesWeb($this->caissier());

        $this->assertSame('Ce produit n\'est plus au catalogue.', $service->encaisser([
            'mode' => 'Espèces', 'condition' => 'Comptant', 'montant_recu' => 100,
            'lignes' => [['produit_id' => $p->id, 'qte' => 1, 'montant' => 100]],
        ])['motif']);
        $this->assertSame(0, Vente::query()->count());
    }

    public function test_encaissement_comptant_ecrit_la_vente_ses_lignes_ses_ecritures_et_aucun_stock(): void
    {
        $p = $this->produit('Goliath mature', 6000, ['price_max' => 7500]);
        $stockAvant = [ProduitVendable::query()->get()->toArray(), MouvementProduit::query()->count()];

        $c = $this->caisse()->call('choisirProduit', $p->id)->set('ajoutQte', '2')->set('ajoutMontant', '13000')->call('validerAjout')
            ->set('montantRecu', '15000')->assertSeeHtml('data-monnaie')->assertSee('Monnaie à rendre : 2 000 FCFA')
            ->call('encaisser')->assertSet('erreur', null)->assertSee('Vente V-WEB-2026-001 enregistrée — 13 000 FCFA.')
            ->assertSet('panier', [])->assertSet('montantRecu', '')->assertSeeHtml('data-lien="facture"');

        $v = Vente::query()->with('lignes')->sole();
        $this->assertSame('V-WEB-2026-001', $v->reference);
        $this->assertSame('', $v->portee_reference);
        $this->assertSame(Catalogue::POSTE_WEB, $v->device_id);
        $this->assertSame(['Client Comptant', 'Espèces', 'Payée', 13000.0, 13000.0], [$v->client, $v->mode, $v->status, $v->total, $v->paye]);
        $this->assertNull($v->echeance);
        $this->assertNull($v->ligne_mobile_money);
        $l = $v->lignes->sole();
        $this->assertSame([2.0, 6500.0, 'goliaths', 'Goliath mature'], [$l->qte, $l->pu, $l->espece, $l->name]); // pu DEDUIT
        $this->assertSame('571', PieceComptable::query()->where('vente_ref', 'V-WEB-2026-001')->sole()->lignes->firstWhere('debit', '>', 0)->numero_compte);
        // Stock propre a chaque poste : rien n'est decremente ni journalise.
        $this->assertSame($stockAvant, [ProduitVendable::query()->get()->toArray(), MouvementProduit::query()->count()]);
        $this->assertSame(Catalogue::POSTE_WEB, PieceComptable::query()->where('vente_ref', $v->reference)->sole()->device_id);
    }

    public function test_les_references_se_suivent_sans_trou_et_ne_sont_jamais_renumerotees(): void
    {
        $c = $this->caisse();
        $this->vendre($c);
        $this->vendre($c);
        $this->assertSame(['V-WEB-2026-001', 'V-WEB-2026-002'], Vente::query()->orderBy('reference')->pluck('reference')->all());

        // Annuler la premiere ne libere pas son numero.
        $this->assertNull((new \App\Services\Commerce\VentesWeb($this->caissier()))->annuler(Vente::query()->where('reference', 'V-WEB-2026-001')->value('id'), 'Autre'));
        $this->vendre($c);
        $this->assertSame(['V-WEB-2026-001', 'V-WEB-2026-002', 'V-WEB-2026-003'], Vente::query()->orderBy('reference')->pluck('reference')->all());

        // Un numero a 4 chiffres posé par ailleurs est pris en compte (maximum, pas comptage) ; les references d'un poste non.
        $this->venteDePoste(['reference' => 'V-WEB-2026-0100'], false);
        $this->venteDePoste(['reference' => 'V-P2-2026-900'], false);
        $this->assertSame('V-WEB-2026-101', \App\Services\Commerce\VentesWeb::numeroSuivant(2026));
        $this->assertSame('V-WEB-2027-001', \App\Services\Commerce\VentesWeb::numeroSuivant(2027));
    }

    public function test_avance_en_mobile_money_porte_la_ligne_creditee_l_echeance_et_la_livraison(): void
    {
        ParametresEntreprise::courant()->update(['telephone' => '+229 97 00 00 00', 'delai_paiement_jours' => 15]);
        $p = $this->produit();
        $amina = Client::query()->create(['nom' => 'AGOSSOU Prudence', 'updated_at' => now(), 'serveur_modifie_le' => now()]);

        $c = $this->caisse()->set('panier', [['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 1, 'montant' => 6000.0]])
            ->set('mode', 'Mobile Money')->assertSee('Ligne créditée : +229 97 00 00 00')
            ->set('condition', 'Avance (Solde Restant Dû)')->assertSet('echeance', '2026-11-24')   // delai par defaut des Parametres
            ->set('client', 'agossou')->assertSeeHtml('data-suggestion="AGOSSOU Prudence"')->call('choisirClient', $amina->id)
            ->set('montantRecu', '2500')->set('livraisonActive', true)->set('livraisonMode', 'facturee')->set('livraisonFrais', '1 500')
            ->set('livraisonAdresse', 'Kantaborifa')->set('livraisonContact', '+229 97 11 22 33')
            ->assertSeeHtml('data-supplement>+ 1 500')->assertSeeHtml('data-total>7 500 FCFA')
            ->call('encaisser')->assertSet('erreur', null);

        $v = Vente::query()->sole();
        $this->assertSame([$amina->id, 'AGOSSOU Prudence', 'Mobile Money', 'Avance', 7500.0, 2500.0, '+229 97 00 00 00'],
            [$v->client_id, $v->client, $v->mode, $v->status, $v->total, $v->paye, $v->ligne_mobile_money]);
        $this->assertSame('2026-11-24', $v->echeance->timezone(config('logialvia.fuseau'))->format('Y-m-d'));
        $this->assertSame(['facturee', 1500.0, 'Kantaborifa', '+229 97 11 22 33'], [$v->livraison_mode, $v->livraison_frais, $v->livraison_adresse, $v->livraison_contact]);
        $this->assertSame(5000.0, $amina->fresh()->solde_creance, 'solde DERIVE par le serveur');
        // Hors Avance, l'echeance saisie est ignoree.
        $this->caisse()->set('panier', [['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 1, 'montant' => 6000.0]])->set('montantRecu', '6000')->set('echeance', '2026-12-01')->call('encaisser');
        $this->assertNull(Vente::query()->where('reference', 'V-WEB-2026-002')->sole()->echeance);
    }

    public function test_sans_echeance_l_ecran_le_dit_et_le_client_se_resout_par_le_nom_s_il_est_unique(): void
    {
        $p = $this->produit();
        Client::query()->create(['nom' => 'Kofi Mensah', 'updated_at' => now(), 'serveur_modifie_le' => now()]);
        Client::query()->create(['nom' => 'Doublon', 'updated_at' => now(), 'serveur_modifie_le' => now()]);
        Client::query()->create(['nom' => 'doublon', 'updated_at' => now(), 'serveur_modifie_le' => now()]);
        $panier = [['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 1, 'montant' => 6000.0]];

        $c = $this->caisse()->set('panier', $panier)->set('condition', 'Avance (Solde Restant Dû)')
            ->assertSeeHtml('data-sans-echeance')->assertSee('Un délai par défaut se règle dans Paramètres Généraux.');
        $c->set('client', ' kofi mensah ')->set('montantRecu', '1000')->call('encaisser');
        $this->assertSame(Client::query()->where('nom', 'Kofi Mensah')->value('id'), Vente::query()->sole()->client_id);

        // Deux homonymes sans choix : la vente n'est rattachee a personne, et l'ecran le signale.
        $this->caisse()->set('panier', $panier)->set('client', 'DOUBLON')->assertSeeHtml('data-homonymes')
            ->set('montantRecu', '6000')->call('encaisser');
        $v = Vente::query()->where('client', 'DOUBLON')->sole();
        $this->assertNull($v->client_id);
        // Nom libre inconnu : aucun rattachement ; nom vide : « Client Comptant ».
        $this->caisse()->set('panier', $panier)->set('client', 'Passant')->set('montantRecu', '6000')->call('encaisser');
        $this->assertNull(Vente::query()->where('client', 'Passant')->sole()->client_id);
    }

    public function test_retoucher_le_nom_apres_un_choix_oublie_le_client_choisi(): void
    {
        $k = Client::query()->create(['nom' => 'Kofi', 'updated_at' => now(), 'serveur_modifie_le' => now()]);
        $this->caisse()->call('choisirClient', $k->id)->assertSet('clientId', $k->id)
            ->set('client', 'Kofi')->assertSet('clientId', $k->id)
            ->set('client', 'Kofi M')->assertSet('clientId', null);
    }

    public function test_un_client_supprime_n_est_plus_propose_ni_retenu(): void
    {
        $p = $this->produit();
        $k = Client::query()->create(['nom' => 'Parti', 'updated_at' => now(), 'serveur_modifie_le' => now(), 'supprime_le' => now()]);
        $this->caisse()->call('choisirClient', $k->id)->assertSet('clientId', null);
        $this->caisse()->set('panier', [['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 1, 'montant' => 6000.0]])
            ->set('client', 'Parti')->set('clientId', $k->id)->set('montantRecu', '6000')->call('encaisser');
        $this->assertNull(Vente::query()->sole()->client_id);
    }

    public function test_viderPanier_remet_la_caisse_a_zero(): void
    {
        $p = $this->produit();
        $this->caisse()->set('panier', [['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 1, 'montant' => 6000.0]])
            ->set('client', 'X')->set('mode', 'Mobile Money')->set('condition', 'Avance (Solde Restant Dû)')->set('livraisonActive', true)
            ->call('viderPanier')->assertSet('panier', [])->assertSet('client', '')->assertSet('mode', 'Espèces')
            ->assertSet('condition', 'Comptant')->assertSet('livraisonActive', false);
    }

    // ------------------------------------------------ Compteur de ventes du jour (46a_)

    public function test_le_compteur_de_ventes_du_jour_du_web_suit_les_ventes_et_les_annulations(): void
    {
        $p = $this->produit();
        $c = $this->caisse();
        $this->vendre($c, ['panier' => [['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 3, 'montant' => 18000.0]], 'montantRecu' => '18000']);
        $this->vendre($c);

        $id = UuidDeterministe::ventesJour('goliaths', '2026-11-09', Catalogue::POSTE_WEB);
        $ligne = FicheVentesJour::query()->sole();
        $this->assertSame([$id, Catalogue::POSTE_WEB, 'goliaths', 4], [$ligne->id, $ligne->device_id, $ligne->espece, $ligne->qte]);

        $this->assertNull((new \App\Services\Commerce\VentesWeb($this->caissier()))->annuler(Vente::query()->where('reference', 'V-WEB-2026-001')->value('id'), 'Autre'));
        $this->assertSame(1, FicheVentesJour::query()->sole()->qte);
    }

    public function test_un_produit_sans_filiere_ne_touche_aucun_compteur(): void
    {
        $p = $this->produit('Tee-shirt', 1000, ['cat' => 'Commerce Annexe', 'espece' => null]);
        $this->vendre($this->caisse(), ['panier' => [['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 1, 'montant' => 1000.0]], 'montantRecu' => '1000']);
        $this->assertSame(0, FicheVentesJour::query()->count());
    }

    public function test_annuler_une_vente_de_poste_ne_touche_pas_au_compteur_du_web_ni_a_celui_du_poste(): void
    {
        $this->vendre($this->caisse()); // le web a vendu 1 goliath
        $poste = '11111111-1111-4111-8111-111111111111';
        FicheVentesJour::query()->create(['id' => UuidDeterministe::ventesJour('goliaths', '2026-11-09', $poste), 'device_id' => $poste,
            'espece' => 'goliaths', 'date' => '2026-11-09', 'qte' => 5, 'updated_at' => now(), 'serveur_modifie_le' => now()]);
        $vp = $this->venteDePoste();

        $this->assertNull((new \App\Services\Commerce\VentesWeb($this->caissier()))->annuler($vp->id, 'Erreur de saisie'));

        $this->assertSame(1, FicheVentesJour::query()->where('device_id', Catalogue::POSTE_WEB)->sole()->qte);
        $this->assertSame(5, FicheVentesJour::query()->where('device_id', $poste)->sole()->qte);
    }

    public function test_annuler_une_vente_du_web_sans_ligne_de_compteur_n_en_cree_pas(): void
    {
        $this->vendre($this->caisse());
        FicheVentesJour::query()->delete(); // compteur remis a zero ailleurs
        $this->assertNull((new \App\Services\Commerce\VentesWeb($this->caissier()))->annuler(Vente::query()->value('id'), 'Autre'));
        $this->assertSame(0, FicheVentesJour::query()->count());
    }

    public function test_le_compteur_ne_descend_jamais_sous_zero(): void
    {
        $this->vendre($this->caisse());
        FicheVentesJour::query()->update(['qte' => 0]); // compteur corrige ailleurs
        $this->assertNull((new \App\Services\Commerce\VentesWeb($this->caissier()))->annuler(Vente::query()->value('id'), 'Autre'));
        $this->assertSame(0, FicheVentesJour::query()->sole()->qte);
    }

    // ----------------------------------------------------- Periode cloturee : atomicite

    public function test_un_mois_cloture_refuse_la_vente_entiere_avec_le_motif_du_serveur(): void
    {
        \App\Models\CloturePeriodique::query()->create([
            'id' => UuidDeterministe::cloturePeriodique(2026, 11), 'annee' => 2026, 'mois' => 11, 'is_cloture' => true,
            'date_cloture' => now(), 'updated_at' => now(), 'serveur_modifie_le' => now(), 'device_id' => Catalogue::POSTE_WEB,
        ]);

        $c = $this->caisse();
        $p = $this->produit();
        $c->set('panier', [['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 1, 'montant' => 6000.0]])->set('montantRecu', '6000')->call('encaisser')
            ->assertSet('erreur', 'Le mois 11/2026 est clôturé. Une administratrice peut le déclôturer pour correction (BR-CPT-006).')
            ->assertSet('message', null);

        // Le poste garderait la vente SANS ecriture ; le web n'enregistre RIEN (ni vente, ni compteur, ni piece).
        $this->assertSame([0, 0, 0], [Vente::query()->count(), FicheVentesJour::query()->count(), PieceComptable::query()->count()]);
    }

    // ----------------------------------------------------------------- Annulation

    public function test_annulation_depuis_l_historique_motif_obligatoire_extourne_et_retours(): void
    {
        $c = $this->caisse();
        $v = $this->vendre($c);
        $c->set('onglet', 'historique')->call('demanderAnnulation', $v->id)->assertSeeHtml('data-modale="annulation"')
            ->assertSee('Annuler la vente V-WEB-2026-001 ?')->assertSee('Aucun stock n\'est restitué', false)
            ->call('confirmerAnnulation')->assertSet('erreurHistorique', 'Le motif d\'annulation est obligatoire.');
        $this->assertSame('Payée', $v->fresh()->status);
        $this->assertSame(1, PieceComptable::query()->count());

        $c->set('motifAnnulation', 'Client non honoré')->call('confirmerAnnulation')->assertSet('erreurHistorique', null)
            ->assertSet('annulationId', null)->assertSee('Vente V-WEB-2026-001 annulée, écriture d\'extourne passée.');

        $v->refresh();
        $this->assertSame(['Annulée', 'Client non honoré', 6000.0], [$v->status, $v->motif_annulation, $v->paye]); // annulation LOGIQUE
        $this->assertSame(1, Vente::query()->count());
        $ann = PieceComptable::query()->where('numero_piece', 'ANN-V-WEB-2026-001')->sole();
        $this->assertSame(['OD', 'V-WEB-2026-001'], [$ann->journal_code, $ann->vente_ref]);

        $c->call('choisirOnglet', 'retours')->assertSeeHtml('data-retour="V-WEB-2026-001"')->assertSee('Client non honoré')->assertSee('6 000')
            ->assertSee('Factures e-MECeF');
        $c->call('choisirOnglet', 'historique')->assertDontSeeHtml('data-action="annuler-vente"');
    }

    public function test_une_vente_annulee_ne_se_reannule_pas_et_une_inconnue_non_plus(): void
    {
        $v = $this->vendre($this->caisse());
        $service = new \App\Services\Commerce\VentesWeb($this->caissier());
        $this->assertNull($service->annuler($v->id, 'Autre'));
        $this->assertSame('Vente V-WEB-2026-001 déjà annulée.', $service->annuler($v->id, 'Autre'));
        $this->assertSame('Cette vente n\'existe plus.', $service->annuler((string) Str::uuid(), 'Autre'));
        $this->assertSame('Le motif d\'annulation est obligatoire.', $service->annuler($v->id, '   '));
        $this->assertSame('Le motif d\'annulation est trop long.', $service->annuler($v->id, str_repeat('x', 256)));
        $this->assertSame(2, PieceComptable::query()->count());
        $this->caisse()->set('onglet', 'historique')->call('demanderAnnulation', $v->id)->assertSet('annulationId', null);
    }

    public function test_annuler_une_vente_de_poste_dont_les_ecritures_ne_sont_pas_arrivees_est_refuse(): void
    {
        $v = $this->venteDePoste([], false);
        $service = new \App\Services\Commerce\VentesWeb($this->caissier());
        $this->assertStringContainsString('pas encore parvenues au serveur', (string) $service->annuler($v->id, 'Autre'));
        $this->assertSame('Payée', $v->fresh()->status);
    }

    public function test_annuler_une_vente_de_poste_dont_l_ecriture_est_deja_contrepassee_est_refuse(): void
    {
        $v = $this->venteDePoste();
        // Le poste a deja contrepasse (piece recue avant le statut de la vente).
        $this->poserPiece('ANN-'.$v->reference, 2026, 11, 9, 'OD', [['702', 6000, 0, 'Goliaths'], ['571', 0, 6000, null]], ['vente_ref' => $v->reference]);
        $service = new \App\Services\Commerce\VentesWeb($this->caissier());
        $this->assertSame('Les écritures de cette vente sont déjà contrepassées.', $service->annuler($v->id, 'Autre'));
        $this->assertSame('Payée', $v->fresh()->status);
    }

    public function test_annuler_une_vente_de_poste_passe_la_contrepassation_du_web_et_se_synchronise(): void
    {
        $v = $this->venteDePoste();
        $avant = $v->updated_at;
        $this->assertNull((new \App\Services\Commerce\VentesWeb($this->caissier()))->annuler($v->id, 'Produit indisponible'));

        $v->refresh();
        $this->assertSame('Annulée', $v->status);
        $this->assertSame('V-P1-2026-001', $v->reference, 'la reference ne change jamais');
        $this->assertSame('11111111-1111-4111-8111-111111111111', $v->device_id, 'la vente garde son poste d\'origine');
        $this->assertTrue($v->updated_at->greaterThan($avant));
        $this->assertTrue($v->serveur_modifie_le->greaterThan(now()->subHour()), 'le curseur de tirage avance : les postes la recevront');
        $ann = PieceComptable::query()->where('numero_piece', 'ANN-V-P1-2026-001')->sole();
        $this->assertSame(Catalogue::POSTE_WEB, $ann->device_id);
    }

    public function test_deux_ventes_de_postes_sans_code_de_meme_reference_ne_se_confondent_pas_a_l_annulation(): void
    {
        $a = $this->venteDePoste(['reference' => 'V-2026-001', 'portee_reference' => '11111111-1111-4111-8111-111111111111']);
        $this->poserPiece('V-2026-001', 2026, 11, 9, 'VT', [['571', 9000, 0, null], ['702', 0, 9000, null]],
            ['vente_ref' => 'V-2026-001'], '22222222-2222-4222-8222-222222222222'); // l'AUTRE poste, meme reference

        $this->assertNull((new \App\Services\Commerce\VentesWeb($this->caissier()))->annuler($a->id, 'Autre'));
        $ann = PieceComptable::query()->where('numero_piece', 'ANN-V-2026-001')->sole()->lignes;
        $this->assertSame(6000.0, $ann->firstWhere('numero_compte', '571')->credit, 'seules les ecritures du poste de la vente sont reprises');
    }

    // --------------------------------------------------------------- Modification

    public function test_modification_du_client_recalcule_le_solde_des_deux_clients(): void
    {
        $a = Client::query()->create(['nom' => 'Ancien', 'updated_at' => now(), 'serveur_modifie_le' => now()]);
        $b = Client::query()->create(['nom' => 'Nouveau', 'updated_at' => now(), 'serveur_modifie_le' => now()]);
        $v = $this->venteDePoste(['status' => 'Avance', 'total' => 6000, 'paye' => 1000, 'client' => 'Ancien', 'client_id' => $a->id]);
        $a->update(['solde_creance' => 5000]);

        $c = $this->caisse()->set('onglet', 'historique')->call('demanderModification', $v->id)->assertSeeHtml('data-modale="modification"')
            ->assertSet('modClient', 'Ancien')->assertSet('modClientId', $a->id)
            ->set('modClient', 'Nouv')->assertSee('Nouveau')->call('choisirClientModification', $b->id)->assertSet('modClient', 'Nouveau')
            ->call('enregistrerModification')->assertSet('erreurHistorique', null)->assertSet('modificationId', null)
            ->assertSee('Vente V-P1-2026-001 modifiée.');

        $v->refresh();
        $this->assertSame([$b->id, 'Nouveau'], [$v->client_id, $v->client]);
        $this->assertSame(0.0, $a->fresh()->solde_creance, 'l\'ancien client perd la creance');
        $this->assertSame(5000.0, $b->fresh()->solde_creance);
        // Aucun effet comptable : la modification ne passe aucune piece.
        $this->assertSame(1, PieceComptable::query()->count());
    }

    public function test_modification_de_l_echeance_et_de_la_livraison(): void
    {
        $v = $this->venteDePoste(['status' => 'Avance', 'total' => 6000, 'paye' => 1000, 'livraison_mode' => 'facturee', 'livraison_frais' => 500, 'livraison_adresse' => 'Ancienne']);
        $service = new \App\Services\Commerce\VentesWeb($this->caissier());

        $this->assertNull($service->modifier($v->id, ['echeance' => '2026-12-15', 'livraison_adresse' => ' Kantaborifa ', 'livraison_contact' => '97 11 22 33']));
        $v->refresh();
        $this->assertSame('2026-12-15', $v->echeance->timezone(config('logialvia.fuseau'))->format('Y-m-d'));
        $this->assertSame(['Kantaborifa', '97 11 22 33'], [$v->livraison_adresse, $v->livraison_contact]);

        $this->assertNull($service->modifier($v->id, ['echeance' => '', 'livraison_contact' => '']));
        $v->refresh();
        $this->assertNull($v->echeance);
        $this->assertNull($v->livraison_contact);
        $this->assertSame([6000.0, 1000.0, 'Avance', 500.0], [$v->total, $v->paye, $v->status, $v->livraison_frais], 'montants intacts');
    }

    public function test_refus_de_modification_message_pour_message(): void
    {
        $service = new \App\Services\Commerce\VentesWeb($this->caissier());
        $payee = $this->venteDePoste(['reference' => 'V-P1-2026-010'], false);
        $annulee = $this->venteDePoste(['reference' => 'V-P1-2026-011', 'status' => 'Annulée', 'motif_annulation' => 'x'], false);

        foreach (['total', 'paye', 'status', 'mode', 'date_vente', 'reference', 'lignes', 'motif_annulation'] as $champ) {
            $this->assertStringContainsString("Ce champ ne se modifie pas : $champ.", (string) $service->modifier($payee->id, [$champ => 1]));
        }
        $this->assertSame('Une vente annulée ne se modifie pas.', $service->modifier($annulee->id, ['client' => 'X']));
        $this->assertSame('Cette vente n\'existe plus.', $service->modifier((string) Str::uuid(), ['client' => 'X']));
        $this->assertSame('Le client de la vente est obligatoire.', $service->modifier($payee->id, ['client' => '  ']));
        $this->assertSame('Le nom du client est trop long.', $service->modifier($payee->id, ['client' => str_repeat('x', 256)]));
        $this->assertSame('Ce client n\'existe plus.', $service->modifier($payee->id, ['client' => 'X', 'client_id' => (string) Str::uuid()]));
        $this->assertSame('Une vente soldée n\'a pas d\'échéance de paiement.', $service->modifier($payee->id, ['echeance' => '2026-12-01']));
        $this->assertSame('Cette vente n\'a pas de livraison.', $service->modifier($payee->id, ['livraison_adresse' => 'Ici']));
        $avance = $this->venteDePoste(['reference' => 'V-P1-2026-012', 'status' => 'Avance', 'paye' => 100], false);
        $this->assertSame('L\'échéance de paiement est invalide.', $service->modifier($avance->id, ['echeance' => 'demain']));
        $livree = $this->venteDePoste(['reference' => 'V-P1-2026-013', 'livraison_mode' => 'gratuite'], false);
        $this->assertSame('Le texte de livraison est trop long.', $service->modifier($livree->id, ['livraison_adresse' => str_repeat('x', 256)]));
    }

    public function test_une_modification_perdue_n_efface_pas_une_ligne_plus_recente_et_le_web_gagne_sur_une_horloge_en_avance(): void
    {
        // Le poste a une horloge en avance : sa derniere saisie est DANS LE FUTUR.
        $futur = now()->addHour();
        $v = $this->venteDePoste(['updated_at' => $futur]);
        $this->assertNull((new \App\Services\Commerce\VentesWeb($this->caissier()))->modifier($v->id, ['client' => 'Corrige']));

        $v->refresh();
        $this->assertSame('Corrige', $v->client, 'la saisie du web n\'est pas ignoree en silence');
        $this->assertTrue($v->updated_at->greaterThan($futur));
    }

    // ---------------------------------------------------------------- Recouvrement

    private function creance(): array
    {
        $k = Client::query()->create(['nom' => 'AGOSSOU Prudence', 'updated_at' => now(), 'serveur_modifie_le' => now()]);
        $v = $this->venteDePoste(['status' => 'Avance', 'total' => 12000, 'paye' => 3500, 'client' => $k->nom, 'client_id' => $k->id, 'echeance' => now()->addDays(5)]);
        $k->update(['solde_creance' => 8500]);

        return [$v, $k];
    }

    public function test_recouvrement_partiel_puis_total_via_l_ecran_clients(): void
    {
        [$v, $k] = $this->creance();
        $c = Livewire::actingAs($this->caissier())->test(Clients::class)
            ->assertSeeHtml('data-action="recouvrer"')
            ->call('demanderRecouvrement', $v->id)->assertSeeHtml('data-modale="recouvrement"')->assertSee('Solde restant dû : 8 500 FCFA')
            ->assertSet('recMode', 'Espèces')
            ->set('recMontant', '2 000')->call('enregistrerRecouvrement')->assertSet('erreurRecouvrement', null)
            ->assertSet('recouvrementId', null)->assertSee('Paiement enregistré sur la vente V-P1-2026-001.');

        $v->refresh();
        $this->assertSame([5500.0, 'Avance'], [$v->paye, $v->status]);
        $this->assertSame(6500.0, $k->fresh()->solde_creance, 'solde derive recalcule');
        $reg = PieceComptable::query()->where('numero_piece', 'REG-V-P1-2026-001')->sole();
        $this->assertSame(['CA', 'V-P1-2026-001'], [$reg->journal_code, $reg->vente_ref]);
        $this->assertSame([2000.0, 0.0], [$reg->lignes->firstWhere('numero_compte', '571')->debit, $reg->lignes->firstWhere('numero_compte', '571')->credit]);
        $this->assertSame(2000.0, $reg->lignes->firstWhere('numero_compte', '411')->credit);

        $c->call('demanderRecouvrement', $v->id)->set('recMontant', '6500')->call('enregistrerRecouvrement')->assertSet('erreurRecouvrement', null);
        $v->refresh();
        $this->assertSame([12000.0, 'Payée'], [$v->paye, $v->status]);
        $this->assertSame(0.0, $k->fresh()->solde_creance);
        $c->assertDontSeeHtml('data-creance="V-P1-2026-001"'); // sort des creances ouvertes
    }

    public function test_recouvrement_refus_message_pour_message(): void
    {
        [$v] = $this->creance();
        $service = new \App\Services\Commerce\VentesWeb($this->caissier());
        ParametresEntreprise::courant()->update(['telephone' => null]);

        $this->assertSame('Le montant recouvré doit être supérieur à 0.', $service->recouvrer($v->id, 0, 'Espèces'));
        $this->assertSame('Le montant recouvré doit être supérieur à 0.', $service->recouvrer($v->id, -5, 'Espèces'));
        $this->assertSame('Le mode de règlement est inconnu.', $service->recouvrer($v->id, 100, 'Troc'));
        $this->assertSame('Le montant dépasse le reste dû (8 500 FCFA).', $service->recouvrer($v->id, 8501, 'Espèces'));
        $this->assertStringContainsString('Aucun numéro Mobile Money', (string) $service->recouvrer($v->id, 100, 'Mobile Money'));
        $this->assertSame('Cette vente n\'existe plus.', $service->recouvrer((string) Str::uuid(), 100, 'Espèces'));
        $this->assertSame(3500.0, $v->fresh()->paye);
        $this->assertSame(1, PieceComptable::query()->count(), 'aucune piece passee');

        $this->assertNull($service->recouvrer($v->id, 8500, 'Espèces'));
        $this->assertSame('Cette vente est déjà soldée : il n\'y a rien à recouvrer.', $service->recouvrer($v->id, 100, 'Espèces'));
        $annulee = $this->venteDePoste(['reference' => 'V-P1-2026-050', 'status' => 'Annulée', 'total' => 100, 'paye' => 0], false);
        $this->assertSame('Une vente annulée ne peut pas être encaissée.', $service->recouvrer($annulee->id, 10, 'Espèces'));
    }

    public function test_une_vente_payee_n_est_pas_une_creance_meme_si_ses_montants_sont_incoherents(): void
    {
        $v = $this->venteDePoste(['status' => 'Payée', 'total' => 6000, 'paye' => 0]);
        $this->assertSame('Cette vente est déjà soldée : il n\'y a rien à recouvrer.',
            (new \App\Services\Commerce\VentesWeb($this->caissier()))->recouvrer($v->id, 100, 'Espèces'));
        $this->assertSame(0.0, $v->fresh()->paye);
    }

    public function test_solder_ecrit_exactement_le_total_meme_quand_la_somme_flottante_differe(): void
    {
        $v = $this->venteDePoste(['status' => 'Avance', 'total' => 0.3, 'paye' => 0.1]);
        $this->assertNull((new \App\Services\Commerce\VentesWeb($this->caissier()))->recouvrer($v->id, 0.2, 'Espèces'));
        $v->refresh();
        $this->assertSame([0.3, 'Payée'], [$v->paye, $v->status]); // 0.1 + 0.2 = 0.30000000000000004
    }

    public function test_le_montant_exact_du_reste_du_solde_sans_reste_flottant(): void
    {
        $v = $this->venteDePoste(['status' => 'Avance', 'total' => 1000.1, 'paye' => 0.1]);
        $this->assertNull((new \App\Services\Commerce\VentesWeb($this->caissier()))->recouvrer($v->id, 1000, 'Espèces'));
        $v->refresh();
        $this->assertSame([1000.1, 'Payée'], [$v->paye, $v->status]);
    }

    public function test_le_recouvrement_propose_le_mode_de_la_vente_et_l_ecran_refuse_un_depassement(): void
    {
        ParametresEntreprise::courant()->update(['telephone' => '+229 97 00 00 00']);
        [$v] = $this->creance();
        $v->update(['mode' => 'Mobile Money']);

        Livewire::actingAs($this->caissier())->test(Clients::class)->call('demanderRecouvrement', $v->id)->assertSet('recMode', 'Mobile Money')
            ->set('recMontant', '999999')->call('enregistrerRecouvrement')->assertSet('erreurRecouvrement', 'Le montant dépasse le reste dû (8 500 FCFA).')
            ->assertSee('Le montant dépasse le reste dû')
            ->set('recMontant', 'abc')->call('enregistrerRecouvrement')->assertSet('erreurRecouvrement', 'Le montant recouvré doit être supérieur à 0.')
            ->call('fermerRecouvrement')->assertSet('recouvrementId', null)->assertSet('erreurRecouvrement', null);
        // Une vente soldee ou inconnue n'ouvre pas la modale.
        Livewire::actingAs($this->caissier())->test(Clients::class)->call('demanderRecouvrement', (string) Str::uuid())->assertSet('recouvrementId', null);
    }

    public function test_le_comptable_voit_les_creances_sans_bouton_de_recouvrement(): void
    {
        $this->creance();
        Livewire::actingAs($this->comptable())->test(Clients::class)->assertSeeHtml('data-creance="V-P1-2026-001"')
            ->assertDontSeeHtml('data-action="recouvrer"')->assertSeeHtml('data-lien="relance"');
    }

    // ------------------------------------------------------------ Vues imprimables

    public function test_la_facture_imprimable_montre_lignes_total_reste_du_et_le_bouton_d_impression(): void
    {
        $c = $this->caisse();
        $p = $this->produit();
        $v = $this->vendre($c, ['panier' => [['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 1, 'montant' => 6000.0]], 'montantRecu' => '1000',
            'condition' => 'Avance (Solde Restant Dû)', 'livraisonActive' => true, 'livraisonMode' => 'facturee', 'livraisonFrais' => '1500']);

        $this->app['auth']->forgetGuards();
        $this->get(route('ventes.facture', $v->id))->assertRedirect(route('login'));
        $this->actingAs($this->utilisateurAvecRole('animalier', 'koffi'))->get(route('ventes.facture', $v->id))->assertForbidden();
        $this->actingAs($this->comptable())->get(route('ventes.facture', $v->id))->assertOk()
            ->assertSee('Facture de Vente — V-WEB-2026-001')->assertSee('ALLMANY ET COMPAGNIE')->assertSee('Goliath mature')
            ->assertSeeHtml('data-frais-livraison')->assertSee('7 500 FCFA')->assertSee('Réglé : 1 000 FCFA — Reste dû : 6 500 FCFA.')
            ->assertSee('@media print', false)->assertSee('window.print()', false)->assertSeeHtml('data-action="imprimer"');
        $this->actingAs($this->caissier())->get(route('ventes.facture', (string) Str::uuid()))->assertNotFound();
    }

    public function test_la_facture_d_une_vente_soldee_et_celle_d_une_annulee(): void
    {
        $v = $this->vendre($this->caisse());
        $this->actingAs($this->caissier())->get(route('ventes.facture', $v->id))->assertOk()->assertSee('Vente intégralement réglée.')->assertDontSeeHtml('data-annulee');
        (new \App\Services\Commerce\VentesWeb($this->caissier()))->annuler($v->id, 'Erreur de saisie');
        $this->actingAs($this->caissier())->get(route('ventes.facture', $v->id))->assertOk()->assertSeeHtml('data-annulee')
            ->assertSee('Erreur de saisie')->assertSee('Ce document ne vaut pas justificatif de vente.')->assertDontSee('Vente intégralement réglée.');
    }

    public function test_l_historique_imprimable_suit_les_filtres_et_exclut_les_annulees_des_totaux(): void
    {
        $this->venteDePoste(['reference' => 'V-P1-2026-001', 'client' => 'Amina', 'total' => 10000, 'paye' => 10000], false);
        $this->venteDePoste(['reference' => 'V-P1-2026-002', 'client' => 'Kofi', 'status' => 'Avance', 'total' => 5000, 'paye' => 1000], false);
        $this->venteDePoste(['reference' => 'V-P1-2026-003', 'client' => 'Kofi', 'status' => 'Annulée', 'total' => 99000, 'paye' => 99000, 'motif_annulation' => 'x'], false);

        $this->actingAs($this->caissier());
        $this->get(route('ventes.historique.imprimer'))->assertOk()->assertSee('Historique des Ventes')
            ->assertSeeHtml('data-vente="V-P1-2026-003"')->assertSee('15 000 FCFA')->assertSee('11 000 FCFA')->assertSee('4 000 FCFA')
            ->assertDontSee('99 000 FCFA')->assertSee('exclues des totaux')->assertSeeHtml('data-action="imprimer"');
        $this->get(route('ventes.historique.imprimer', ['recherche' => 'amina']))->assertSeeHtml('data-vente="V-P1-2026-001"')
            ->assertDontSeeHtml('data-vente="V-P1-2026-002"')->assertSeeHtml('data-filtre')->assertSee('recherche « amina »');
        $this->get(route('ventes.historique.imprimer', ['statut' => 'Avance']))->assertSeeHtml('data-vente="V-P1-2026-002"')->assertDontSeeHtml('data-vente="V-P1-2026-001"');
        $this->get(route('ventes.historique.imprimer', ['statut' => 'inconnu']))->assertSeeHtml('data-vente="V-P1-2026-001"');
    }

    public function test_les_tableaux_imprimables_exigent_export_ventes(): void
    {
        $this->creance();
        $lecteur = User::factory()->create(['username' => 'lecteur']);
        $lecteur->givePermissionTo('view-ventes');
        foreach (['ventes.historique.imprimer', 'clients.creances.imprimer'] as $route) {
            $this->app['auth']->forgetGuards();
            $this->get(route($route))->assertRedirect(route('login'));
            $this->actingAs($lecteur)->get(route($route))->assertForbidden();
            $this->actingAs($this->comptable())->get(route($route))->assertForbidden(); // comptable : view-ventes seulement
            $this->actingAs($this->caissier())->get(route($route))->assertOk();
        }
        $this->actingAs($lecteur)->get(route('clients.relance', Vente::query()->value('id')))->assertOk(); // la lettre : view-ventes
    }

    public function test_le_suivi_des_soldes_imprimable_liste_les_creances_et_leur_total(): void
    {
        $this->creance();
        $this->venteDePoste(['reference' => 'V-P1-2026-002', 'total' => 100, 'paye' => 100], false); // soldee : absente
        $this->actingAs($this->caissier())->get(route('clients.creances.imprimer'))->assertOk()->assertSee('Suivi des Soldes Clients')
            ->assertSeeHtml('data-creance="V-P1-2026-001"')->assertDontSeeHtml('data-creance="V-P1-2026-002"')->assertSee('8 500 FCFA')->assertSee('TOTAL (1)');
    }

    public function test_lettre_de_relance_avec_echeance_et_rappel_de_solde_sans_echeance(): void
    {
        [$v] = $this->creance();
        $this->actingAs($this->caissier())->get(route('clients.relance', $v->id))->assertOk()
            ->assertSee('Lettre de Relance — AGOSSOU Prudence')->assertSeeHtml('data-corps="relance"')
            ->assertSee('payable le 14/11/2026, reste impayée à ce jour pour un montant de 8 500 FCFA')
            ->assertSee('Madame, Monsieur AGOSSOU Prudence,')->assertSee('La Gérante')->assertSeeHtml('data-action="imprimer"');

        $v->update(['echeance' => null]);
        $this->get(route('clients.relance', $v->id))->assertOk()->assertSee('Rappel de Solde — AGOSSOU Prudence')->assertSeeHtml('data-corps="rappel"')
            ->assertSee('présente un solde de 8 500 FCFA restant à régler.')->assertDontSee('reste impayée');

        // Une vente soldee ou inconnue n'a pas de lettre.
        $v->update(['paye' => 12000, 'status' => 'Payée']);
        $this->get(route('clients.relance', $v->id))->assertNotFound();
        $this->get(route('clients.relance', (string) Str::uuid()))->assertNotFound();
    }

    // ------------------------------------------------------------------ Exports XLSX

    public function test_export_xlsx_de_l_historique_avec_les_memes_lignes_et_filtres_que_l_ecran(): void
    {
        $this->venteDePoste(['reference' => 'V-P1-2026-001', 'client' => '=SOMME(A1)', 'total' => 10000, 'paye' => 10000, 'date_vente' => CarbonImmutable::parse('2026-11-08 12:00:00')], false);
        $this->venteDePoste(['reference' => 'V-P1-2026-002', 'client' => 'Kofi', 'status' => 'Avance', 'total' => 5000, 'paye' => 1000], false);
        $this->venteDePoste(['reference' => 'V-P1-2026-003', 'client' => 'Kofi', 'status' => 'Annulée', 'total' => 7000, 'paye' => 7000, 'motif_annulation' => 'x'], false);

        $c = $this->caisse()->set('onglet', 'historique')->assertSeeHtml('data-action="exporter-historique"')->call('exporterHistorique');
        $c->assertFileDownloaded('historique-ventes.xlsx', null, ExportXlsx::TYPE);
        $this->assertSame([
            ['Référence', 'Date', 'Client', 'Mode', 'Statut', 'Total', 'Payé', 'Reste dû'],
            ['V-P1-2026-002', '09/11/2026', 'Kofi', 'Espèces', 'Avance', '5000', '1000', '4000'],
            ['V-P1-2026-003', '09/11/2026', 'Kofi', 'Espèces', 'Annulée', '7000', '7000', '0'],
            ['V-P1-2026-001', '08/11/2026', '=SOMME(A1)', 'Espèces', 'Payée', '10000', '10000', '0'],
        ], $this->xlsx($c));

        $c2 = $this->caisse()->set('onglet', 'historique')->set('statut', 'Avance')->call('exporterHistorique');
        $this->assertCount(2, $this->xlsx($c2));
        $c3 = $this->caisse()->set('onglet', 'historique')->set('recherche', 'kofi')->set('statut', 'Annulée')->call('exporterHistorique');
        $this->assertSame('V-P1-2026-003', $this->xlsx($c3)[1][0]);
    }

    public function test_export_xlsx_des_creances_avec_les_memes_chiffres_que_l_ecran(): void
    {
        $this->creance();
        $c = Livewire::actingAs($this->caissier())->test(Clients::class)->assertSeeHtml('data-action="exporter-creances"')->call('exporterCreances');
        $c->assertFileDownloaded('creances-clients.xlsx', null, ExportXlsx::TYPE);
        $this->assertSame([
            ['Client', 'Référence Vente', 'Date', 'Échéance', 'Montant Total', 'Déjà Réglé', 'Solde Restant Dû', 'Ancienneté (jours)'],
            ['AGOSSOU Prudence', 'V-P1-2026-001', '09/11/2026', '14/11/2026', '12000', '3500', '8500', '0'],
        ], $this->xlsx($c));
    }

    public function test_les_exports_exigent_export_ventes_verifie_dans_la_methode(): void
    {
        $this->creance();
        Livewire::actingAs($this->comptable())->test(Ventes::class)->set('onglet', 'historique')->assertDontSeeHtml('data-action="exporter-historique"')
            ->call('exporterHistorique')->assertForbidden();
        Livewire::actingAs($this->comptable())->test(Clients::class)->assertDontSeeHtml('data-action="exporter-creances"')
            ->call('exporterCreances')->assertForbidden();
    }

    // ---------------------------------------------------------- Lecture de la parite

    public function test_l_administrateur_encaisse_aussi(): void
    {
        $v = $this->vendre($this->caisse($this->utilisateurAvecRole('admin', 'chef')));
        $this->assertSame('V-WEB-2026-001', $v->reference);
    }

    public function test_l_ecran_ventes_mene_aux_devis_de_prestations(): void
    {
        $this->actingAs($this->utilisateurAvecRole('admin', 'gerante'))->get('/ventes')
            ->assertOk()->assertSeeHtml('data-lien="devis-prestations"')->assertSeeHtml('href="/ventes/devis"');
        $this->actingAs($this->comptable())->get('/ventes')
            ->assertSeeHtml('data-lien="devis-prestations"');
    }
}
