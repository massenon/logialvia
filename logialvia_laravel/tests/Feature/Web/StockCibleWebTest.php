<?php

namespace Tests\Feature\Web;

use App\Livewire\Achats;
use App\Livewire\Catalogue;
use App\Livewire\Ventes;
use App\Models\Achat;
use App\Models\EffetStock;
use App\Models\Fournisseur;
use App\Models\Intrant;
use App\Models\MouvementIntrant;
use App\Models\MouvementProduit;
use App\Models\PieceComptable;
use App\Models\Poste;
use App\Models\ProduitVendable;
use App\Models\User;
use App\Models\Vente;
use App\Services\Achats\GestionAchats;
use App\Services\Commerce\CorrectionsStockWeb;
use App\Services\PosteDeStock;
use App\Services\PostesService;
use App\Support\UuidDeterministe;
use App\Sync\Tables\EffetsStockTable;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Livewire\Livewire;
use Tests\Concerns\JeuComptable;
use Tests\TestCase;

/**
 * `47s_` — stock ciblé, côté web : une opération qui a un effet de stock désigne un POSTE DE STOCK.
 * Le fait porte `poste_cible` ; le poste désigné applique l'effet (testé côté poste) ; le web dit où en
 * est l'opération (en attente / appliquée / avertissement) d'après la trace que le poste remonte.
 */
class StockCibleWebTest extends TestCase
{
    use JeuComptable, RefreshDatabase;

    private Fournisseur $fournisseur;

    protected function setUp(): void
    {
        parent::setUp();
        $this->amorcerPourLesEcrans();
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-11-09 12:00:00', config('logialvia.fuseau')));
        (new Intrant)->forceFill(['code' => 'INT-001', 'name' => 'Maïs', 'cat' => 'Intrants Provende', 'unit' => 'kg', 'threshold' => 10, 'saisi_le' => now()])->save();
        $this->fournisseur = (new Fournisseur)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => (string) Str::uuid(), 'nom' => 'Agri Plus',
            'updated_at' => now()->subDay(), 'serveur_modifie_le' => now()->subDay(),
        ]);
        $this->fournisseur->save();
    }

    protected function tearDown(): void
    {
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    private ?User $admin = null;

    private function admin(): User
    {
        return $this->admin ??= $this->utilisateurAvecRole('admin', 'gerante');
    }

    /** Un poste appairé et déjà synchronisé, dont le compte a ce rôle. @return array{0: string, 1: User} */
    private function poste(string $role = 'admin', bool $synchronise = true): array
    {
        $u = $this->utilisateurAvecRole($role, 'poste-'.Str::random(6));
        $device = (string) Str::uuid();
        app(PostesService::class)->appairer($u, $device);
        if ($synchronise) {
            Poste::query()->where('device_id', $device)->update(['curseur_tirage' => now('UTC')]);
        }

        return [$device, $u];
    }

    private function code(string $device): string
    {
        return (string) Poste::query()->where('device_id', $device)->value('code');
    }

    private function panier(): array
    {
        return [['intrant_code' => 'INT-001', 'qte' => '50', 'pu' => '320']];
    }

    private function commander(array $valeurs = [], ?User $u = null)
    {
        $valeurs = array_merge([
            'fournisseurId' => $this->fournisseur->id, 'mode' => 'Crédit', 'paye' => '', 'echeance' => '',
            'livree' => true, 'lignes' => $this->panier(),
        ], $valeurs);
        $c = Livewire::actingAs($u ?? $this->admin())->test(Achats::class)->call('nouveau');
        foreach ($valeurs as $champ => $valeur) {
            $c->set($champ, $valeur);
        }

        return $c->call('enregistrer');
    }

    private function produit(): ProduitVendable
    {
        return ProduitVendable::query()->firstOrCreate(['name' => 'Goliath mature'], [
            'cat' => 'Avicole', 'price' => 6000, 'price_max' => null, 'unit' => 'u', 'icon' => 'egg', 'espece' => 'goliaths', 'saisi_le' => now(),
        ]);
    }

    private function vendre(?string $poste, ?User $u = null)
    {
        $p = $this->produit();
        $c = Livewire::actingAs($u ?? $this->admin())->test(Ventes::class);
        $c->set('panier', [['produit_id' => $p->id, 'nom' => $p->name, 'qte' => 3, 'montant' => 18000.0]])
            ->set('montantRecu', '18000')->set('posteCible', $poste ?? '')->call('encaisser');

        return $c;
    }

    /** La trace que le poste désigné remonterait au serveur. */
    private function effet(string $device, string $faitId, string $fait, string $nature, string $etat = 'applique', ?string $avert = null): void
    {
        $refus = (new EffetsStockTable)->absorber($device, [
            'id' => UuidDeterministe::effetStock($faitId, $nature), 'fait_type' => $fait, 'fait_id' => $faitId, 'nature' => $nature,
            'reference' => 'X', 'libelle' => 'effet', 'etat' => $etat, 'avertissement' => $avert, 'applique_le' => now('UTC')->format('Y-m-d\TH:i:s.u\Z'),
        ]);
        $this->assertNull($refus);
    }

    // ====================================================== postes désignables

    public function test_seuls_les_postes_appaires_actifs_synchronises_dont_le_compte_lit_l_operation_sont_proposes(): void
    {
        [$bon] = $this->poste('admin');
        [$jamais] = $this->poste('admin', false);
        [$revoque] = $this->poste('admin');
        app(PostesService::class)->revoquer($revoque, $this->admin());
        [$caissier] = $this->poste('caissier'); // lit les ventes, pas les achats

        $achats = PosteDeStock::proposables(PosteDeStock::RECEPTION)->pluck('device_id')->all();
        $ventes = PosteDeStock::proposables(PosteDeStock::VENTE)->pluck('device_id')->all();

        $this->assertEqualsCanonicalizing([$bon], $achats);
        $this->assertEqualsCanonicalizing([$bon, $caissier], $ventes);
        $this->assertNotContains($jamais, $ventes);
        $this->assertNotContains($revoque, $ventes);
        $this->assertSame(PosteDeStock::MOTIF_JAMAIS_SYNCHRONISE, PosteDeStock::verifier($jamais, PosteDeStock::VENTE));
        $this->assertSame(PosteDeStock::MOTIF_INCONNU, PosteDeStock::verifier($revoque, PosteDeStock::VENTE));
        $this->assertSame(PosteDeStock::MOTIF_INCONNU, PosteDeStock::verifier((string) Str::uuid(), PosteDeStock::VENTE));
        $this->assertSame(PosteDeStock::MOTIF_INCONNU, PosteDeStock::verifier('', PosteDeStock::VENTE));
        $this->assertStringContainsString('pas le droit de lire', PosteDeStock::verifier($caissier, PosteDeStock::RECEPTION));
    }

    // ============================================================== achats

    public function test_une_commande_livree_designe_un_poste_et_l_ecrit_au_journal_sans_aucun_stock(): void
    {
        [$p1] = $this->poste();

        $this->commander(['posteCible' => $p1])->assertSet('erreur', null)
            ->assertSee('Le poste '.$this->code($p1).' appliquera l\'entrée de stock et le PMP à son propre stock');

        $a = Achat::query()->firstOrFail();
        $this->assertSame($p1, $a->poste_cible);
        $this->assertSame('Livré', $a->statut);
        $m = MouvementIntrant::query()->firstOrFail();
        $this->assertSame($p1, $m->poste_cible, 'le journal dit quel poste est visé');
        $this->assertSame('Entrée', $m->type);
        $this->assertSame(50.0, $m->quantite);
    }

    public function test_sans_poste_designe_c_est_du_journal_seul_et_l_ecran_le_dit(): void
    {
        $this->commander(['posteCible' => ''])->assertSet('erreur', null)->assertSee('Aucun poste de stock désigné');

        $this->assertNull(Achat::query()->firstOrFail()->poste_cible);
        $this->assertNull(MouvementIntrant::query()->firstOrFail()->poste_cible);
    }

    public function test_un_poste_revoque_inconnu_ou_jamais_synchronise_est_refuse_a_la_saisie_sans_aucune_trace(): void
    {
        [$revoque] = $this->poste();
        app(PostesService::class)->revoquer($revoque, $this->admin());
        [$jamais] = $this->poste('admin', false);
        [$caissier] = $this->poste('caissier');
        $avant = [Achat::query()->count(), MouvementIntrant::query()->count(), PieceComptable::query()->count()];

        $this->commander(['posteCible' => $revoque])->assertSet('formulaire', true)->assertSet('erreur', PosteDeStock::MOTIF_INCONNU);
        $this->commander(['posteCible' => (string) Str::uuid()])->assertSet('erreur', PosteDeStock::MOTIF_INCONNU);
        $this->commander(['posteCible' => $jamais])->assertSet('erreur', PosteDeStock::MOTIF_JAMAIS_SYNCHRONISE);
        $this->commander(['posteCible' => $caissier])->assertSee('pas le droit de lire');

        $this->assertSame($avant, [Achat::query()->count(), MouvementIntrant::query()->count(), PieceComptable::query()->count()]);
    }

    public function test_receptionner_pose_le_poste_une_fois_puis_il_ne_change_plus(): void
    {
        [$p1] = $this->poste();
        [$p2] = $this->poste();
        $this->commander(['livree' => false, 'posteCible' => ''])->assertSet('erreur', null);
        $a = Achat::query()->firstOrFail();
        $this->assertNull($a->poste_cible);

        $c = Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderReception', $a->id);
        $c->set('posteReception', $p1)->call('confirmerReception')->assertSee('réceptionnée');
        $this->assertSame($p1, $a->fresh()->poste_cible);

        // Lié : une autre désignation est refusée, avec un message clair.
        $b = (new GestionAchats($this->admin()))->creer([
            'fournisseur_id' => $this->fournisseur->id, 'mode' => 'Crédit', 'paye' => 0, 'echeance' => '', 'livree' => false,
            'poste_cible' => $p1, 'lignes' => $this->panier(),
        ]);
        $this->assertNull($b['erreur']);
        $r = (new GestionAchats($this->admin()))->receptionner($b['achat']->id, $p2);
        $this->assertStringContainsString('ne peut plus être changé', $r['erreur']);
        $this->assertSame('Commandé', $b['achat']->fresh()->statut, 'la réception refusée ne laisse aucune trace');
        $this->assertSame(1, MouvementIntrant::query()->count(), 'seul le premier achat a été réceptionné');
    }

    public function test_la_commande_d_un_poste_peut_etre_receptionnee_au_web_pour_ce_poste(): void
    {
        [$p1] = $this->poste();
        // Commande saisie au poste P1 (son device_id, aucun poste cible), encore « Commandé ».
        $a = (new Achat)->forceFill([
            'id' => (string) Str::uuid(), 'device_id' => $p1, 'reference' => 'ACH-P1-2026-001', 'portee_reference' => '',
            'fournisseur_id' => $this->fournisseur->id, 'date_achat' => now(), 'statut' => 'Commandé', 'total' => 16000, 'paye' => 0,
            'mode' => 'Crédit', 'updated_at' => now()->subHour(), 'serveur_modifie_le' => now()->subHour(),
        ]);
        $a->save();
        (new \App\Models\LigneAchat)->forceFill(['id' => (string) Str::uuid(), 'achat_id' => $a->id, 'intrant_code' => 'INT-001', 'nom' => 'Maïs', 'qte' => 50, 'pu_achat' => 320])->save();

        $c = Livewire::actingAs($this->admin())->test(Achats::class)->call('demanderReception', $a->id);
        $c->assertSet('posteReception', $p1); // proposé : le poste qui a passé la commande
        $c->call('confirmerReception')->assertSet('erreur', null);

        $this->assertSame($p1, $a->fresh()->poste_cible);
        $this->assertSame('Livré', $a->fresh()->statut);
        $this->assertSame('ACH-P1-2026-001', MouvementIntrant::query()->firstOrFail()->reference);
    }

    public function test_l_annulation_d_une_commande_livree_suit_le_meme_poste_et_previent_s_il_est_revoque(): void
    {
        [$p1] = $this->poste();
        $this->commander(['posteCible' => $p1]);
        $a = Achat::query()->firstOrFail();

        $r = (new GestionAchats($this->admin()))->annuler($a->id, 'erreur de saisie');

        $this->assertNull($r['erreur']);
        $this->assertNull($r['avertissement']);
        $sortie = MouvementIntrant::query()->where('type', 'Sortie')->firstOrFail();
        $this->assertSame($p1, $sortie->poste_cible, 'la sortie inverse part au MÊME poste');
        $this->assertSame(-50.0, $sortie->quantite);

        // Poste révoqué entre-temps : l'annulation reste possible mais l'écran avertit.
        [$p2] = $this->poste();
        $this->commander(['posteCible' => $p2]);
        $b = Achat::query()->orderByDesc('reference')->firstOrFail();
        app(PostesService::class)->revoquer($p2, $this->admin());
        $r = (new GestionAchats($this->admin()))->annuler($b->id, 'doublon');
        $this->assertNull($r['erreur']);
        $this->assertStringContainsString('ne peut pas recevoir la sortie de stock', $r['avertissement']);
        $this->assertSame('Annulé', $b->fresh()->statut);
    }

    public function test_l_ecran_montre_en_attente_applique_avertissement_et_non_applique(): void
    {
        [$p1] = $this->poste();
        $this->commander(['posteCible' => $p1]);
        $a = Achat::query()->firstOrFail();
        $code = $this->code($p1);
        $ecran = fn () => Livewire::actingAs($this->admin())->test(Achats::class);

        $ecran()->assertSeeHtml('data-poste-stock="attente"')->assertSee("En attente du poste $code");

        $this->effet($p1, $a->id, 'achat', 'reception');
        $ecran()->assertSeeHtml('data-poste-stock="applique"')->assertSee("Appliqué au poste $code");

        // Annulation : sortie attendue, tant que le poste n'a pas répondu c'est « en attente ».
        (new GestionAchats($this->admin()))->annuler($a->id, 'erreur');
        $ecran()->assertSeeHtml('data-poste-stock="attente"');
        $this->effet($p1, $a->id, 'achat', 'annulation_reception', 'avertissement', "Stock insuffisant au poste $code : « Maïs » — 50 à retirer, 20 disponibles ; stock ramené à 0");
        $ecran()->assertSeeHtml('data-poste-stock="avertissement"')->assertSeeHtml('data-avertissement-stock')->assertSee('Stock insuffisant au poste');
    }

    public function test_un_poste_qui_n_a_pas_applique_le_dit_au_web(): void
    {
        [$p1] = $this->poste();
        $this->commander(['posteCible' => $p1]);
        $a = Achat::query()->firstOrFail();
        $this->effet($p1, $a->id, 'achat', 'reception', 'ignore', 'la commande était déjà livrée sur ce poste : stock inchangé');

        Livewire::actingAs($this->admin())->test(Achats::class)
            ->assertSeeHtml('data-poste-stock="ignore"')->assertSee('Non appliqué par le poste')->assertSee('déjà livrée sur ce poste');
    }

    public function test_une_commande_annulee_avant_toute_livraison_au_poste_n_attend_aucun_effet(): void
    {
        [$p1] = $this->poste();
        $this->commander(['livree' => false, 'posteCible' => $p1]);
        $a = Achat::query()->firstOrFail();
        $ecran = fn () => Livewire::actingAs($this->admin())->test(Achats::class);

        $ecran()->assertSeeHtml('data-poste-stock="a_la_reception"');
        (new GestionAchats($this->admin()))->annuler($a->id, 'plus besoin');
        $ecran()->assertSeeHtml('data-poste-stock="sans_effet"');
    }

    public function test_poste_revoque_apres_coup_l_effet_ne_viendra_jamais_et_le_web_le_dit(): void
    {
        [$p1] = $this->poste();
        $this->commander(['posteCible' => $p1]);
        app(PostesService::class)->revoquer($p1, $this->admin());

        Livewire::actingAs($this->admin())->test(Achats::class)->assertSeeHtml('data-poste-stock="revoque"')->assertSee('révoqué : jamais appliqué');
    }

    public function test_le_formulaire_propose_les_postes_et_fige_celui_d_une_commande_deja_liee(): void
    {
        [$p1] = $this->poste();
        $this->commander(['livree' => false, 'posteCible' => $p1]);
        $a = Achat::query()->firstOrFail();

        Livewire::actingAs($this->admin())->test(Achats::class)->call('nouveau')
            ->assertSeeHtml('data-champ="poste-stock"')->assertSee($this->code($p1))->assertSet('posteCible', $p1, 'un seul poste : proposé par défaut')
            ->call('modifier', $a->id)->assertSet('posteCible', $p1)->assertSee('Lié à la commande : il ne peut plus être changé.');
    }

    public function test_le_poste_choisi_devient_le_defaut_du_compte_pour_la_reception(): void
    {
        [$p1] = $this->poste();
        [$p2] = $this->poste();
        $this->commander(['posteCible' => $p2]);

        Livewire::actingAs($this->admin())->test(Achats::class)->call('nouveau')->assertSet('posteCible', $p2);

        // Défaut périmé (poste révoqué) : jamais proposé.
        app(PostesService::class)->revoquer($p2, $this->admin());
        $this->assertSame($p1, PosteDeStock::defaut($this->admin(), PosteDeStock::RECEPTION), 'il ne reste qu\'un poste désignable');
        [$p3] = $this->poste();
        $this->assertNull(PosteDeStock::defaut($this->admin(), PosteDeStock::RECEPTION), 'deux postes possibles, défaut périmé : le compte choisit');
        $this->assertContains($p3, PosteDeStock::proposables(PosteDeStock::RECEPTION)->pluck('device_id')->all());
    }

    public function test_quand_le_client_l_exige_un_poste_est_obligatoire(): void
    {
        config(['logialvia.stock_cible.obligatoire' => true]);
        [$p1] = $this->poste();

        $this->commander(['posteCible' => ''])->assertSet('erreur', PosteDeStock::MOTIF_OBLIGATOIRE);
        $this->commander(['livree' => false, 'posteCible' => ''])->assertSet('erreur', null); // pas d'effet à la commande seule
        $a = Achat::query()->firstOrFail();
        $r = (new GestionAchats($this->admin()))->receptionner($a->id, '');
        $this->assertSame(PosteDeStock::MOTIF_OBLIGATOIRE, $r['erreur']);
        $this->assertNull((new GestionAchats($this->admin()))->receptionner($a->id, $p1)['erreur']);
        $this->vendre(null)->assertSet('erreur', PosteDeStock::MOTIF_OBLIGATOIRE);
    }

    // ============================================================== ventes

    public function test_une_vente_designe_son_poste_le_journal_partage_la_trace_et_le_defaut_se_souvient(): void
    {
        [$p1] = $this->poste();
        [$p2] = $this->poste();

        $this->vendre($p2)->assertSet('erreur', null)->assertSee('décrémentera son stock à sa prochaine synchronisation');

        $v = Vente::query()->firstOrFail();
        $this->assertSame($p2, $v->poste_cible);
        $this->assertSame('Payée', $v->status);
        $this->assertSame(0, MouvementProduit::query()->count(), 'la vente voyage avec ses lignes, pas de ligne de journal');

        // Défaut mémorisé par type d'opération : la vente n'influence pas la réception.
        Livewire::actingAs($this->admin())->test(Ventes::class)->assertSet('posteCible', $p2);
        $this->assertNull(PosteDeStock::defaut($this->admin(), PosteDeStock::RECEPTION), 'deux postes, aucun mémorisé pour la réception');
        $this->assertContains($p1, PosteDeStock::proposables(PosteDeStock::RECEPTION)->pluck('device_id')->all());
    }

    public function test_une_vente_vers_un_poste_inconnu_revoque_ou_jamais_synchronise_est_refusee_sans_ecriture(): void
    {
        [$revoque] = $this->poste();
        app(PostesService::class)->revoquer($revoque, $this->admin());
        [$jamais] = $this->poste('admin', false);
        $avant = [Vente::query()->count(), PieceComptable::query()->count()];

        $this->vendre($revoque)->assertSet('erreur', PosteDeStock::MOTIF_INCONNU);
        $this->vendre((string) Str::uuid())->assertSet('erreur', PosteDeStock::MOTIF_INCONNU);
        $this->vendre($jamais)->assertSet('erreur', PosteDeStock::MOTIF_JAMAIS_SYNCHRONISE);

        $this->assertSame($avant, [Vente::query()->count(), PieceComptable::query()->count()]);
    }

    public function test_une_vente_sans_poste_reste_possible_et_n_a_aucun_effet_de_stock(): void
    {
        $this->vendre(null)->assertSet('erreur', null)->assertSee('Aucun poste de stock désigné : aucun stock ne bouge.');
        $this->assertNull(Vente::query()->firstOrFail()->poste_cible);
    }

    public function test_l_annulation_suit_le_meme_poste_et_l_historique_montre_l_etat(): void
    {
        [$p1] = $this->poste();
        $c = $this->vendre($p1);
        $v = Vente::query()->firstOrFail();
        $code = $this->code($p1);

        $ecran = fn () => Livewire::actingAs($this->admin())->test(Ventes::class)->call('choisirOnglet', 'historique');
        $ecran()->assertSeeHtml('data-poste-stock="attente"')->assertSee("En attente du poste $code");

        $this->effet($p1, $v->id, 'vente', 'vente', 'avertissement', "Stock insuffisant au poste $code : « Goliath mature » — 3 demandés, 1 disponibles ; stock ramené à 0");
        $ecran()->assertSeeHtml('data-poste-stock="avertissement"')->assertSee('Stock insuffisant au poste');

        $ecran()->call('demanderAnnulation', $v->id)->set('motifAnnulation', 'Erreur de saisie')->call('confirmerAnnulation')
            ->assertSee("Le poste de stock $code réintégrera les quantités");
        $this->assertSame($p1, $v->fresh()->poste_cible, 'le lien ne change jamais');
        $this->assertSame('Annulée', $v->fresh()->status);

        $this->effet($p1, $v->id, 'vente', 'annulation_vente');
        $ecran()->assertSeeHtml('data-poste-stock="avertissement"'); // l'avertissement de la vente reste visible
    }

    // ============================================================ corrections

    public function test_une_correction_designe_un_poste_et_s_inscrit_au_journal(): void
    {
        [$p1] = $this->poste();
        $p = $this->produit();

        $motif = (new CorrectionsStockWeb($this->admin()))->corriger($p->id, '-4', 'Comptage du magasin', $p1);

        $this->assertNull($motif);
        $m = MouvementProduit::query()->firstOrFail();
        $this->assertSame($p1, $m->poste_cible);
        $this->assertSame(-4.0, $m->quantite);
        $this->assertSame('Comptage du magasin', $m->motif);
        $this->assertSame('Goliath mature', $m->article);
        $this->assertSame('00000000-0000-0000-0000-000000000000', $m->device_id, 'poste d\'origine : le web');
    }

    public function test_chaque_refus_d_une_correction_a_son_message_et_n_ecrit_rien(): void
    {
        [$p1] = $this->poste();
        [$jamais] = $this->poste('admin', false);
        $p = $this->produit();
        $s = new CorrectionsStockWeb($this->admin());

        $this->assertSame(CorrectionsStockWeb::MOTIF_VARIATION, $s->corriger($p->id, '0', 'x', $p1));
        $this->assertSame(CorrectionsStockWeb::MOTIF_VARIATION, $s->corriger($p->id, '2,5', 'x', $p1));
        $this->assertSame(CorrectionsStockWeb::MOTIF_VARIATION, $s->corriger($p->id, 'abc', 'x', $p1));
        $this->assertSame(CorrectionsStockWeb::MOTIF_JUSTIFICATION, $s->corriger($p->id, '3', '  ', $p1));
        $this->assertStringContainsString('Désignez le poste', $s->corriger($p->id, '3', 'x', ''));
        $this->assertSame(PosteDeStock::MOTIF_JAMAIS_SYNCHRONISE, $s->corriger($p->id, '3', 'x', $jamais));
        $this->assertSame(PosteDeStock::MOTIF_INCONNU, $s->corriger($p->id, '3', 'x', (string) Str::uuid()));
        $this->assertSame("Ce produit n'est plus au catalogue.", $s->corriger((string) Str::uuid(), '3', 'x', $p1));
        $this->assertSame(0, MouvementProduit::query()->count());
    }

    public function test_la_correction_exige_manage_stocks_ou_manage_ventes_et_chaque_methode_de_l_ecran_le_droit(): void
    {
        [$p1] = $this->poste();
        $p = $this->produit();
        $comptable = $this->utilisateurAvecRole('comptable', 'paul');

        try {
            (new CorrectionsStockWeb($comptable))->corriger($p->id, '3', 'x', $p1);
            $this->fail('Le comptable ne corrige pas un stock.');
        } catch (\Symfony\Component\HttpKernel\Exception\HttpException $e) {
            $this->assertSame(403, $e->getStatusCode());
        }
        foreach (['ouvrirCorrection' => [$p->id], 'enregistrerCorrection' => []] as $methode => $args) {
            Livewire::actingAs($comptable)->test(Catalogue::class)->call($methode, ...$args)->assertForbidden();
        }
        $this->assertSame(0, MouvementProduit::query()->count());
    }

    public function test_l_ecran_du_catalogue_corrige_le_stock_et_montre_l_etat_de_la_correction(): void
    {
        [$p1] = $this->poste();
        $p = $this->produit();

        $c = Livewire::actingAs($this->admin())->test(Catalogue::class)->call('ouvrirCorrection', $p->id)
            ->assertSeeHtml('data-modale="correction-stock"')->assertSet('correctionPoste', $p1)
            ->set('correctionVariation', '-3')->set('correctionMotif', '')->call('enregistrerCorrection')
            ->assertSee(CorrectionsStockWeb::MOTIF_JUSTIFICATION)
            ->set('correctionMotif', 'Casse')->call('enregistrerCorrection')
            ->assertSet('correctionId', null)->assertSee('appliquera à son stock');

        $m = MouvementProduit::query()->firstOrFail();
        $c->assertSeeHtml('data-suivi="attente"');
        $this->effet($p1, $m->id, 'mouvement_produit', 'correction', 'avertissement', 'Stock insuffisant au poste P1 : « Goliath mature » — 3 à retirer, 1 disponibles ; stock ramené à 0');
        Livewire::actingAs($this->admin())->test(Catalogue::class)->assertSeeHtml('data-suivi="avertissement"')->assertSee('stock ramené à 0');
    }

    // ============================================================ effets_stock

    public function test_la_trace_d_un_effet_se_valide_strictement_et_ne_s_ecrit_qu_une_fois(): void
    {
        [$p1] = $this->poste();
        [$p2] = $this->poste();
        $fait = (string) Str::uuid();
        $ligne = [
            'id' => UuidDeterministe::effetStock($fait, 'vente'), 'fait_type' => 'vente', 'fait_id' => $fait, 'nature' => 'vente',
            'reference' => 'V-WEB-2026-001', 'libelle' => 'Vente reçue du web', 'etat' => 'applique', 'avertissement' => null,
            'applique_le' => '2026-11-09T10:00:00.000000Z',
        ];
        $t = new EffetsStockTable;

        $this->assertNull($t->absorber($p1, $ligne));
        $this->assertNull($t->absorber($p1, $ligne), 'rejeu accepté sans rien changer');
        $this->assertSame(1, EffetStock::query()->count());
        // Même identifiant déterministe : un autre poste ne peut ni écraser ni dédoubler la trace.
        $this->assertNull($t->absorber($p2, $ligne), 'accepté sans rien changer (immuable)');
        $this->assertSame(1, EffetStock::query()->count());
        $this->assertSame($p1, EffetStock::query()->firstOrFail()->device_id);

        $this->assertStringContainsString('ne correspond pas', $t->absorber($p1, array_merge($ligne, ['id' => (string) Str::uuid()])));
        $this->assertStringContainsString('nature', $t->absorber($p1, array_merge($ligne, ['nature' => 'magie'])));
        $this->assertStringContainsString('état', $t->absorber($p1, array_merge($ligne, ['etat' => 'ok'])));
        $this->assertStringContainsString('libellé', $t->absorber($p1, array_merge($ligne, ['libelle' => ''])));
        $this->assertSame(1, EffetStock::query()->count());
    }
}
