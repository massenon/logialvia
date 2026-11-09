<?php

namespace App\Livewire;

use App\Models\Intrant;
use App\Models\MouvementIntrant;
use App\Models\Poste;
use App\Sync\DemandesReferentiel;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Str;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Gestion des Stocks (Dart : `gestion_stocks_screen.dart`).
 *
 * Deux tableaux, comme au poste : les INTRANTS (referentiel, le serveur fait foi) et le
 * JOURNAL DES MOUVEMENTS (historique partage de tous les postes, en lecture seule).
 *
 * Decision du client : « stock propre a chaque poste + journal partage ». Le web n'affiche
 * NI stock, NI PMP, NI valeur de stock, NI intrants critiques : ils vivent sur chaque poste.
 * Le journal est un historique (avec le poste d'origine), jamais applique a un stock.
 *
 * Toute ecriture d'intrant passe par `DemandesReferentiel::traiter` (memes regles qu'un poste).
 * La suppression d'un intrant n'existe pas cote serveur : elle n'est donc pas construite ici.
 */
#[Layout('components.layouts.app')]
class GestionStocks extends Component
{
    /** Categories du poste (`Intrant.categories`, Doc D1). */
    public const CATEGORIES = ['Intrants Provende', 'Marchandises', 'Vétérinaire'];

    /** Taille du journal affiche (Dart : `chargerMouvements(limite: 100)`). */
    public const LIMITE_JOURNAL = 100;

    /** Fenetre du KPI « Mouvements (7j) » (Dart : `fenetreMouvementsJours`). */
    public const FENETRE_JOURS = 7;

    public string $recherche = '';

    public string $categorie = '';

    public bool $formulaire = false;

    /** Code de l'intrant modifie ; `null` = creation. */
    public ?string $code = null;

    public string $nom = '';

    public string $cat = '';

    public string $unite = 'kg';

    public string $seuil = '0';

    public ?string $erreur = null;

    public ?string $message = null;

    private function verifierDroitDeGerer(): void
    {
        $u = Auth::user();
        abort_unless($u && ($u->can('manage-stocks') || $u->can('manage-achats')), 403);
    }

    public function nouveau(): void
    {
        $this->verifierDroitDeGerer();
        $this->reinitialiser();
        $this->formulaire = true;
    }

    public function modifier(string $code): void
    {
        $this->verifierDroitDeGerer();
        $intrant = Intrant::query()->find($code);
        if ($intrant === null) {
            return;
        }

        $this->reinitialiser();
        $this->code = $intrant->code;
        $this->nom = $intrant->name;
        $this->cat = $intrant->cat;
        $this->unite = $intrant->unit;
        $this->seuil = (string) $intrant->threshold;
        $this->formulaire = true;
    }

    public function annuler(): void
    {
        $this->formulaire = false;
        $this->erreur = null;
    }

    public function enregistrer(): void
    {
        $this->verifierDroitDeGerer();

        $existant = $this->code !== null ? Intrant::query()->find($this->code) : null;
        if ($this->code !== null && $existant === null) {
            $this->erreur = 'Cet intrant n\'existe plus.';

            return;
        }

        $seuil = trim($this->seuil);
        if ($seuil !== '' && ! preg_match('/^-?\d+$/', $seuil)) {
            $this->erreur = 'Le seuil d\'alerte doit être un nombre entier.';

            return;
        }

        $donnees = [
            'code' => $this->code ?? $this->prochainCode(),
            'name' => trim($this->nom),
            'cat' => $this->cat,
            'unit' => trim($this->unite) === '' ? 'u' : trim($this->unite),
            'threshold' => $seuil === '' ? 0 : (int) $seuil,
        ];

        $bilan = app(DemandesReferentiel::class)->traiter(Auth::user(), Catalogue::POSTE_WEB, [[
            'id' => (string) Str::uuid(),
            'type' => DemandesReferentiel::TYPE_INTRANT,
            'saisi_le' => now('UTC')->format('Y-m-d\TH:i:s.u\Z'),
            'donnees' => $donnees,
        ]]);

        $motif = $bilan['rejected'][0]['motif'] ?? null;
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }

        $this->message = $existant === null ? "Intrant « {$donnees['name']} » ajouté." : "Intrant « {$donnees['name']} » modifié.";
        $this->formulaire = false;
        $this->erreur = null;
    }

    /** Code suivant `INT-NNN`, comme le poste (`_prochainCode`). */
    private function prochainCode(): string
    {
        $max = Intrant::query()->pluck('code')
            ->map(fn ($c) => preg_match('/^INT-(\d+)$/', (string) $c, $m) ? (int) $m[1] : 0)
            ->max() ?? 0;

        return sprintf('INT-%03d', $max + 1);
    }

    private function reinitialiser(): void
    {
        $this->reset(['code', 'nom', 'erreur', 'message']);
        $this->cat = '';
        $this->unite = 'kg';
        $this->seuil = '0';
    }

    /** Poste d'origine d'un mouvement : « Web », son code (`P2`), ou repli sur l'identifiant. */
    private function libellePoste(string $deviceId, array $codes): string
    {
        if ($deviceId === Catalogue::POSTE_WEB) {
            return 'Web';
        }

        return $codes[$deviceId] ?? 'Poste '.Str::substr($deviceId, 0, 8);
    }

    public function render()
    {
        $intrants = Intrant::query()
            ->when($this->categorie !== '', fn ($q) => $q->where('cat', $this->categorie))
            ->when(trim($this->recherche) !== '', function ($q) {
                $terme = '%'.trim($this->recherche).'%';
                $q->where(fn ($w) => $w->where('name', 'like', $terme)->orWhere('code', 'like', $terme));
            })
            ->orderBy('name')->get();

        $codes = Poste::query()->pluck('code', 'device_id')->all();
        $journal = MouvementIntrant::query()->orderByDesc('horodatage')->limit(self::LIMITE_JOURNAL)->get()
            ->map(fn (MouvementIntrant $m) => ['mouvement' => $m, 'poste' => $this->libellePoste($m->device_id, $codes)]);

        $u = Auth::user();

        return view('livewire.gestion-stocks', [
            'intrants' => $intrants,
            'articlesSuivis' => Intrant::query()->count(),
            'mouvements7Jours' => MouvementIntrant::query()->where('horodatage', '>', now('UTC')->subDays(self::FENETRE_JOURS))->count(),
            'categories' => collect(self::CATEGORIES)->merge(Intrant::query()->distinct()->pluck('cat'))->unique()->values(),
            'journal' => $journal,
            'peutGerer' => (bool) ($u && ($u->can('manage-stocks') || $u->can('manage-achats'))),
        ])->title('Gestion des Stocks');
    }
}
