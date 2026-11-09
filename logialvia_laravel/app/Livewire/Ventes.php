<?php

namespace App\Livewire;

use App\Models\Client;
use App\Models\ProduitVendable;
use App\Models\Vente;
use App\Services\Commerce\VentesWeb;
use App\Support\ExportXlsx;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Ventes (Dart : `ventes_screen.dart`, `onglet_pos.dart`, `onglets_ventes_secondaires.dart`, `ventes_view_model.dart`).
 *
 * Onglets : Enregistrer Vente (caisse), Historique des Ventes, Retours et Avoirs. L'onglet « Devis Prestations »
 * appartient au composant des devis (autre tranche) : `$onglets` est la liste a completer.
 *
 * Toute ecriture passe par `App\Services\Commerce\VentesWeb` (tables de synchronisation, ecritures automatiques,
 * transaction unique). Le droit `manage-ventes` est reverifie dans CHAQUE methode d'ecriture.
 * Stock propre a chaque poste : une vente au web ne decremente aucun stock (declare dans l'ecran).
 */
#[Layout('components.layouts.app')]
class Ventes extends Component
{
    public const STATUTS = ['Payée', 'Avance', 'Annulée'];

    public const ONGLETS = ['caisse' => 'Enregistrer Vente', 'historique' => 'Historique des Ventes', 'retours' => 'Retours et Avoirs'];

    public string $onglet = 'caisse';

    // ---- caisse
    public string $rechercheProduit = '';

    public string $categorie = '';

    /** @var list<array{produit_id: string, nom: string, qte: int, montant: float}> */
    public array $panier = [];

    public ?string $ajoutProduit = null;

    public ?int $ajoutIndex = null;

    public string $ajoutQte = '';

    public string $ajoutMontant = '';

    public ?string $erreurAjout = null;

    public string $client = '';

    public ?string $clientId = null;

    public string $mode = 'Espèces';

    public string $condition = VentesWeb::COMPTANT;

    public string $montantRecu = '';

    public string $echeance = '';

    public bool $livraisonActive = false;

    public string $livraisonMode = 'gratuite';

    public string $livraisonFrais = '';

    public string $livraisonAdresse = '';

    public string $livraisonContact = '';

    public ?string $erreur = null;

    public ?string $message = null;

    public ?string $derniereVente = null;

    // ---- historique
    public string $recherche = '';

    /** Chaine vide = « Tous statuts ». */
    public string $statut = '';

    public ?string $venteId = null;

    public ?string $annulationId = null;

    public string $motifAnnulation = '';

    public ?string $modificationId = null;

    public string $modClient = '';

    public ?string $modClientId = null;

    public string $modEcheance = '';

    public string $modAdresse = '';

    public string $modContact = '';

    public ?string $erreurHistorique = null;

    public ?string $messageHistorique = null;

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-ventes'), 403);
    }

    private function service(): VentesWeb
    {
        return new VentesWeb(Auth::user());
    }

    public function choisirOnglet(string $onglet): void
    {
        if (array_key_exists($onglet, self::ONGLETS)) {
            $this->onglet = $onglet;
        }
    }

    /** « 4 500 », « 4500,5 » → float ; `null` si ce n'est pas un nombre. */
    private function nombre(string $texte): ?float
    {
        $t = str_replace([' ', "\u{00A0}", "\u{202F}", ','], ['', '', '', '.'], trim($texte));

        return $t !== '' && is_numeric($t) ? (float) $t : null;
    }

    // ================================================================= caisse

    public function choisirProduit(string $id): void
    {
        $this->verifierDroitDeGerer();
        $produit = ProduitVendable::query()->whereNull('archive_le')->find($id);
        if ($produit === null) {
            return;
        }
        $this->ajoutProduit = $produit->id;
        $this->ajoutIndex = null;
        $this->ajoutQte = '';
        $this->ajoutMontant = (string) (int) round($produit->price);
        $this->erreurAjout = null;
    }

    public function modifierLigne(int $index): void
    {
        $this->verifierDroitDeGerer();
        if (! isset($this->panier[$index])) {
            return;
        }
        $l = $this->panier[$index];
        $this->ajoutProduit = $l['produit_id'];
        $this->ajoutIndex = $index;
        $this->ajoutQte = (string) $l['qte'];
        $this->ajoutMontant = (string) (int) round($l['montant']);
        $this->erreurAjout = null;
    }

    public function annulerAjout(): void
    {
        $this->ajoutProduit = null;
        $this->ajoutIndex = null;
        $this->erreurAjout = null;
    }

    /** `confirmWeightAdd()` : la quantite ET le montant global sont saisis ; le montant n'est jamais qte × prix. */
    public function validerAjout(): void
    {
        $this->verifierDroitDeGerer();
        $produit = $this->ajoutProduit ? ProduitVendable::query()->whereNull('archive_le')->find($this->ajoutProduit) : null;
        if ($produit === null) {
            $this->erreurAjout = 'Ce produit n\'est plus au catalogue.';

            return;
        }
        $qte = $this->nombre($this->ajoutQte);
        $montant = $this->nombre($this->ajoutMontant);
        if ($qte === null || $qte < 1 || floor($qte) != $qte || $montant === null || $montant <= 0) {
            $this->erreurAjout = 'Veuillez saisir une quantité et un montant valides.';

            return;
        }

        $ligne = ['produit_id' => $produit->id, 'nom' => $produit->name, 'qte' => (int) $qte, 'montant' => $montant];
        if ($this->ajoutIndex !== null && isset($this->panier[$this->ajoutIndex])) {
            $this->panier[$this->ajoutIndex] = $ligne;
        } else {
            // Un meme produit peut etre ajoute plusieurs fois a des montants differents (le prototype empile).
            $this->panier[] = $ligne;
        }
        $this->annulerAjout();
        $this->erreur = null;
    }

    public function retirerLigne(int $index): void
    {
        $this->verifierDroitDeGerer();
        unset($this->panier[$index]);
        $this->panier = array_values($this->panier);
    }

    public function viderPanier(): void
    {
        $this->verifierDroitDeGerer();
        $this->reset(['panier', 'client', 'clientId', 'mode', 'condition', 'montantRecu', 'echeance', 'livraisonActive',
            'livraisonMode', 'livraisonFrais', 'livraisonAdresse', 'livraisonContact', 'erreur']);
    }

    public function choisirClient(string $id): void
    {
        $this->verifierDroitDeGerer();
        $c = Client::query()->whereNull('supprime_le')->find($id);
        if ($c !== null) {
            $this->client = $c->nom;
            $this->clientId = $c->id;
        }
    }

    /** Retoucher le nom a la main oublie le choix : on ne garde pas l'id d'un client dont le nom n'est plus affiche. */
    public function updatedClient(string $valeur): void
    {
        if ($this->clientId !== null && Client::query()->whereKey($this->clientId)->value('nom') !== $valeur) {
            $this->clientId = null;
        }
    }

    public function updatedCondition(string $valeur): void
    {
        if ($valeur === VentesWeb::COMPTANT) {
            $this->montantRecu = '';
            $this->echeance = '';
        } elseif ($this->echeance === '') {
            $delai = \App\Models\ParametresEntreprise::courant()->delai_paiement_jours;
            if ($delai !== null && $delai > 0) {
                $this->echeance = CarbonImmutable::now(config('logialvia.fuseau'))->addDays($delai)->format('Y-m-d');
            }
        }
    }

    private function livraison(): ?array
    {
        if (! $this->livraisonActive) {
            return null;
        }

        return [
            'mode' => $this->livraisonMode,
            'frais' => $this->nombre($this->livraisonFrais),
            'adresse' => $this->livraisonAdresse,
            'contact' => $this->livraisonContact,
        ];
    }

    public function encaisser(): void
    {
        $this->verifierDroitDeGerer();
        $this->erreur = null;
        $this->message = null;

        $r = $this->service()->encaisser([
            'client' => $this->client,
            'client_id' => $this->clientId,
            'mode' => $this->mode,
            'condition' => $this->condition,
            'montant_recu' => $this->nombre($this->montantRecu) ?? 0,
            'lignes' => $this->panier,
            'livraison' => $this->livraison(),
            'echeance' => $this->echeance,
        ]);
        if ($r['motif'] !== null) {
            $this->erreur = $r['motif'];

            return;
        }

        $this->derniereVente = $r['vente']->id;
        $this->message = "Vente {$r['vente']->reference} enregistrée — ".number_format($r['vente']->total, 0, ',', ' ').' FCFA.';
        $this->reset(['panier', 'client', 'clientId', 'mode', 'condition', 'montantRecu', 'echeance', 'livraisonActive',
            'livraisonMode', 'livraisonFrais', 'livraisonAdresse', 'livraisonContact']);
    }

    // ============================================================== historique

    public function ouvrir(string $id): void
    {
        $this->venteId = Vente::query()->whereKey($id)->exists() ? $id : null;
    }

    public function fermer(): void
    {
        $this->venteId = null;
    }

    public function demanderAnnulation(string $id): void
    {
        $this->verifierDroitDeGerer();
        $this->erreurHistorique = null;
        $this->messageHistorique = null;
        $this->motifAnnulation = '';
        $this->annulationId = Vente::query()->where('status', '!=', 'Annulée')->whereKey($id)->exists() ? $id : null;
    }

    public function confirmerAnnulation(): void
    {
        $this->verifierDroitDeGerer();
        $id = $this->annulationId;
        if ($id === null) {
            return;
        }
        $this->erreurHistorique = null;
        $motif = $this->service()->annuler($id, $this->motifAnnulation === '' ? null : $this->motifAnnulation);
        if ($motif !== null) {
            $this->erreurHistorique = $motif;

            return;
        }
        $reference = Vente::query()->whereKey($id)->value('reference');
        $this->annulationId = null;
        $this->messageHistorique = "Vente $reference annulée, écriture d'extourne passée.";
    }

    public function fermerAnnulation(): void
    {
        $this->annulationId = null;
        $this->erreurHistorique = null;
    }

    public function demanderModification(string $id): void
    {
        $this->verifierDroitDeGerer();
        $v = Vente::query()->where('status', '!=', 'Annulée')->find($id);
        if ($v === null) {
            return;
        }
        $this->erreurHistorique = null;
        $this->messageHistorique = null;
        $this->modificationId = $v->id;
        $this->modClient = $v->client;
        $this->modClientId = $v->client_id;
        $this->modEcheance = $v->echeance?->timezone(config('logialvia.fuseau'))->format('Y-m-d') ?? '';
        $this->modAdresse = (string) $v->livraison_adresse;
        $this->modContact = (string) $v->livraison_contact;
    }

    public function choisirClientModification(string $id): void
    {
        $this->verifierDroitDeGerer();
        $c = Client::query()->whereNull('supprime_le')->find($id);
        if ($c !== null) {
            $this->modClient = $c->nom;
            $this->modClientId = $c->id;
        }
    }

    public function enregistrerModification(): void
    {
        $this->verifierDroitDeGerer();
        $v = $this->modificationId ? Vente::query()->find($this->modificationId) : null;
        if ($v === null) {
            return;
        }
        $champs = ['client' => $this->modClient, 'client_id' => $this->modClientId];
        if ($v->status === 'Avance') {
            $champs['echeance'] = $this->modEcheance;
        }
        if ($v->livraison_mode !== null) {
            $champs['livraison_adresse'] = $this->modAdresse;
            $champs['livraison_contact'] = $this->modContact;
        }
        $this->erreurHistorique = null;
        $motif = $this->service()->modifier($v->id, $champs);
        if ($motif !== null) {
            $this->erreurHistorique = $motif;

            return;
        }
        $this->messageHistorique = "Vente {$v->reference} modifiée.";
        $this->modificationId = null;
    }

    public function fermerModification(): void
    {
        $this->modificationId = null;
        $this->erreurHistorique = null;
    }

    /** Ventes de l'historique, filtrees comme a l'ecran. */
    public function ventesFiltrees()
    {
        $terme = trim($this->recherche);

        return Vente::query()
            ->when(in_array($this->statut, self::STATUTS, true), fn ($q) => $q->where('status', $this->statut))
            ->tap(fn ($q) => \App\Support\RechercheLike::appliquer($q, ['reference', 'client'], $terme))
            ->orderByDesc('date_vente')->orderBy('reference')->get();
    }

    /** Export XLSX de l'historique : memes colonnes et memes filtres que l'ecran. Droit `export-ventes`. */
    public function exporterHistorique(): StreamedResponse
    {
        abort_unless(Auth::user()?->can('export-ventes'), 403);
        $fuseau = config('logialvia.fuseau');
        $lignes = [['Référence', 'Date', 'Client', 'Mode', 'Statut', 'Total', 'Payé', 'Reste dû']];
        foreach ($this->ventesFiltrees() as $v) {
            $lignes[] = [
                $v->reference, $v->date_vente->timezone($fuseau)->format('d/m/Y'), $v->client, $v->mode, $v->status,
                (int) round($v->total), (int) round($v->paye),
                $v->status === 'Annulée' ? 0 : (int) round(max(0, $v->total - $v->paye)),
            ];
        }

        return ExportXlsx::telecharger(array_map(fn ($l) => array_map(ExportXlsx::typer(...), $l), $lignes), 'historique-ventes.xlsx', 'Historique');
    }

    /** Bornes UTC du jour courant dans le fuseau de l'entreprise (les dates sont stockees en UTC). */
    private function bornesDuJour(): array
    {
        $debut = CarbonImmutable::now(config('logialvia.fuseau'))->startOfDay();

        return [$debut->utc()->format('Y-m-d H:i:s.u'), $debut->addDay()->utc()->format('Y-m-d H:i:s.u')];
    }

    public function render()
    {
        [$debut, $fin] = $this->bornesDuJour();

        // KPI : ventes du jour NON annulees (Dart `_ventesDuJour`).
        $duJour = Vente::query()->where('status', '!=', 'Annulée')
            ->where('date_vente', '>=', $debut)->where('date_vente', '<', $fin);
        $nombreDuJour = (clone $duJour)->count();
        $chiffreAffaires = (float) (clone $duJour)->sum('total');

        $peutGerer = Auth::user()?->can('manage-ventes') ?? false;
        $terme = mb_strtolower(trim($this->rechercheProduit));
        $produits = ProduitVendable::query()->whereNull('archive_le')
            ->when($this->categorie !== '', fn ($q) => $q->where('cat', $this->categorie))
            ->orderBy('name')->get()
            ->filter(fn ($p) => $terme === '' || str_contains(mb_strtolower($p->name), $terme))->values();

        $total = VentesWeb::totalLignes($this->panier);
        $livraison = $this->livraison();
        $supplement = VentesWeb::supplementLivraison($livraison);
        $saisieClient = mb_strtolower(trim($this->client));
        $suggestions = $saisieClient === '' || $this->clientId !== null ? collect()
            : Client::query()->whereNull('supprime_le')->orderBy('nom')->get()
                ->filter(fn ($c) => str_contains(mb_strtolower($c->nom), $saisieClient))->take(8);
        $homonymes = $this->clientId === null && $saisieClient !== ''
            && Client::query()->whereNull('supprime_le')->get()->filter(fn ($c) => mb_strtolower(trim($c->nom)) === $saisieClient)->count() > 1;

        $ouverte = $this->venteId
            ? Vente::query()->with(['lignes' => fn ($q) => $q->orderBy('name')])->find($this->venteId)
            : null;

        return view('livewire.ventes', [
            'ventes' => $this->onglet === 'historique' ? $this->ventesFiltrees() : collect(),
            'retours' => $this->onglet === 'retours' ? Vente::query()->where('status', 'Annulée')->orderByDesc('date_vente')->get() : collect(),
            'chiffreAffaires' => $chiffreAffaires,
            'panierMoyen' => $nombreDuJour === 0 ? null : $chiffreAffaires / $nombreDuJour,
            'enAttente' => Vente::query()->where('status', 'Avance')->count(),
            'ouverte' => $ouverte,
            'fuseau' => config('logialvia.fuseau'),
            'statuts' => self::STATUTS,
            'peutGerer' => $peutGerer,
            'peutExporter' => Auth::user()?->can('export-ventes') ?? false,
            'produits' => $produits,
            'categories' => ProduitVendable::query()->whereNull('archive_le')->distinct()->orderBy('cat')->pluck('cat'),
            'produitAjout' => $this->ajoutProduit ? ProduitVendable::query()->find($this->ajoutProduit) : null,
            'totalLignes' => $total,
            'supplement' => $supplement,
            'totalPanier' => $total + $supplement,
            'suggestions' => $suggestions,
            'homonymes' => $homonymes,
            'clientsModification' => $this->modificationId && mb_strlen(trim($this->modClient)) > 0
                ? Client::query()->whereNull('supprime_le')->orderBy('nom')->get()->filter(fn ($c) => str_contains(mb_strtolower($c->nom), mb_strtolower(trim($this->modClient))))->take(6)
                : collect(),
            'ligneMobileMoney' => VentesWeb::ligneMobileMoney(),
            'delaiDefaut' => \App\Models\ParametresEntreprise::courant()->delai_paiement_jours,
            'aAnnuler' => $this->annulationId ? Vente::query()->find($this->annulationId) : null,
            'aModifier' => $this->modificationId ? Vente::query()->find($this->modificationId) : null,
            'derniere' => $this->derniereVente ? Vente::query()->find($this->derniereVente) : null,
            'motifs' => VentesWeb::MOTIFS_ANNULATION,
            'livraisons' => VentesWeb::LIVRAISONS,
            'conditions' => VentesWeb::CONDITIONS,
            'modes' => VentesWeb::MODES,
            'onglets' => self::ONGLETS,
        ])->title('Ventes');
    }
}
