<?php

namespace App\Livewire;

use App\Models\ProduitVendable;
use App\Sync\DemandesReferentiel;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Catalogue & Seuils (Dart : `catalogue_screen.dart`). REFERENTIEL : le serveur fait foi.
 *
 * Toute ecriture passe par `DemandesReferentiel::traiter` — les MEMES regles que pour un
 * poste (validation, droit `manage-ventes`, dernier ecrivain gagne, audit, historique).
 * Le STOCK n'existe pas ici : il est propre a chaque poste (decision du client), donc
 * ni colonne « Stock », ni valeur du catalogue, ni seuils critiques : ils restent au poste.
 */
#[Layout('components.layouts.app')]
class Catalogue extends Component
{
    /** Identifiant du « poste » web dans l'historique des demandes (UUID nul). */
    public const POSTE_WEB = '00000000-0000-0000-0000-000000000000';

    /** Categories du poste (`ProduitVendable.categories`). */
    public const CATEGORIES = ['Avicole', 'Commerce Annexe', 'Cuniculture', 'Héliciculture', 'Élevage bovin', 'Pisciculture'];

    public string $recherche = '';

    public string $categorie = '';

    public bool $formulaire = false;

    public ?string $produitId = null;

    public string $nom = '';

    public string $cat = '';

    public string $prix = '';

    public string $prixMax = '';

    public string $unite = '';

    public string $coutRevient = '';

    public string $seuil = '0';

    public ?string $erreur = null;

    public ?string $message = null;

    /** Identifiant du produit dont on demande la suppression ; `null` = modale fermee. */
    public ?string $aSupprimer = null;

    private function verifierDroitDeGerer(): void
    {
        abort_unless(Auth::user()?->can('manage-ventes'), 403);
    }

    private function nombre(string $valeur): ?float
    {
        $valeur = trim(str_replace([' ', ','], ['', '.'], $valeur));

        return $valeur === '' ? null : (is_numeric($valeur) ? (float) $valeur : null);
    }

    public function nouveau(): void
    {
        $this->verifierDroitDeGerer();
        $this->reinitialiser();
        $this->formulaire = true;
    }

    public function modifier(string $id): void
    {
        $this->verifierDroitDeGerer();
        $produit = ProduitVendable::query()->whereNull('archive_le')->find($id);
        if ($produit === null) {
            return;
        }

        $this->reinitialiser();
        $this->produitId = $produit->id;
        $this->nom = $produit->name;
        $this->cat = $produit->cat;
        $this->prix = (string) $produit->price;
        $this->prixMax = $produit->price_max === null ? '' : (string) $produit->price_max;
        $this->unite = $produit->unit;
        $this->coutRevient = $produit->cout_revient === null ? '' : (string) $produit->cout_revient;
        $this->seuil = (string) $produit->threshold;
        $this->formulaire = true;
    }

    public function annuler(): void
    {
        $this->formulaire = false;
        $this->aSupprimer = null;
        $this->erreur = null;
    }

    public function enregistrer(): void
    {
        $this->verifierDroitDeGerer();

        $existant = $this->produitId ? ProduitVendable::query()->find($this->produitId) : null;
        if ($this->produitId !== null && $existant === null) {
            $this->erreur = 'Ce produit n\'existe plus.';

            return;
        }

        $donnees = [
            'id' => $this->produitId ?? (string) Str::uuid(),
            // Le SKU d'un produit existant n'est jamais reecrit ; un nouveau recoit le suivant.
            'sku' => $existant?->sku ?? $this->prochainSku(),
            'name' => trim($this->nom),
            'cat' => $this->cat,
            'price' => $this->nombre($this->prix),
            'price_max' => $this->nombre($this->prixMax),
            'unit' => trim($this->unite) === '' ? 'u' : trim($this->unite),
            'icon' => $existant?->icon ?? 'category',
            'cout_revient' => $this->nombre($this->coutRevient),
            'groupe_taxe' => $existant?->groupe_taxe ?? 'A',
            'threshold' => is_numeric($this->seuil) ? (int) $this->seuil : 0,
            'espece' => $existant?->espece,
        ];

        $motif = $this->proposer($donnees);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = $existant === null ? "Produit « {$donnees['name']} » ajouté." : "Produit « {$donnees['name']} » modifié.";
        $this->formulaire = false;
        $this->erreur = null;
    }

    public function demanderSuppression(string $id): void
    {
        $this->verifierDroitDeGerer();
        $this->message = null;
        $this->aSupprimer = ProduitVendable::query()->whereNull('archive_le')->whereKey($id)->exists() ? $id : null;
    }

    public function confirmerSuppression(): void
    {
        $this->verifierDroitDeGerer();
        $produit = $this->aSupprimer ? ProduitVendable::query()->whereNull('archive_le')->find($this->aSupprimer) : null;
        $this->aSupprimer = null;
        if ($produit === null) {
            return;
        }

        // Jamais d'effacement : pierre tombale, que les postes archivent a leur tour.
        $motif = $this->proposer([
            'id' => $produit->id,
            'sku' => $produit->sku,
            'name' => $produit->name,
            'cat' => $produit->cat,
            'price' => $produit->price,
            'price_max' => $produit->price_max,
            'unit' => $produit->unit,
            'icon' => $produit->icon,
            'cout_revient' => $produit->cout_revient,
            'groupe_taxe' => $produit->groupe_taxe,
            'threshold' => $produit->threshold,
            'espece' => $produit->espece,
            'archive' => true,
        ]);

        $this->message = $motif ?? "Produit « {$produit->name} » supprimé du catalogue.";
    }

    private function proposer(array $donnees): ?string
    {
        $bilan = app(DemandesReferentiel::class)->traiter(Auth::user(), self::POSTE_WEB, [[
            'id' => (string) Str::uuid(),
            'type' => DemandesReferentiel::TYPE_PRODUIT,
            'saisi_le' => now('UTC')->format('Y-m-d\TH:i:s.u\Z'),
            'donnees' => $donnees,
        ]]);

        return $bilan['rejected'][0]['motif'] ?? null;
    }

    private function prochainSku(): string
    {
        $max = ProduitVendable::query()->pluck('sku')
            ->map(fn ($s) => preg_match('/^PRD-(\d+)$/', (string) $s, $m) ? (int) $m[1] : 0)
            ->max() ?? 0;

        return sprintf('PRD-%03d', $max + 1);
    }

    private function reinitialiser(): void
    {
        $this->reset(['produitId', 'nom', 'cat', 'prix', 'prixMax', 'unite', 'coutRevient', 'erreur', 'message']);
        $this->seuil = '0';
        $this->cat = self::CATEGORIES[0];
    }

    public function render()
    {
        $produits = ProduitVendable::query()->whereNull('archive_le')
            ->when($this->categorie !== '', fn ($q) => $q->where('cat', $this->categorie))
            ->when(trim($this->recherche) !== '', function ($q) {
                $terme = '%'.trim($this->recherche).'%';
                $q->where(fn ($w) => $w->where('name', 'like', $terme)->orWhere('sku', 'like', $terme));
            })
            ->orderBy('name')->get();

        $tous = ProduitVendable::query()->whereNull('archive_le');

        return view('livewire.catalogue', [
            'produits' => $produits,
            'nombre' => (clone $tous)->count(),
            'nombreCategories' => (clone $tous)->distinct()->count('cat'),
            'categories' => collect(self::CATEGORIES)->merge(ProduitVendable::query()->distinct()->pluck('cat'))->unique()->values(),
            'peutGerer' => Auth::user()?->can('manage-ventes') ?? false,
            'aConfirmer' => $this->aSupprimer ? ProduitVendable::query()->find($this->aSupprimer) : null,
        ])->title('Catalogue & Seuils');
    }
}
