<?php

namespace App\Livewire;

use App\Models\Vente;
use Carbon\CarbonImmutable;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ventes — onglet « Historique des Ventes » + bandeau KPI (Dart : `ventes_screen.dart`,
 * `onglets_ventes_secondaires.dart`, `ventes_view_model.dart`).
 *
 * LECTURE SEULE : une vente est un FAIT saisi au poste (stock et comptabilite propres au poste).
 * Aucune methode d'ecriture ici ; la caisse, les devis, les retours/avoirs et l'annulation
 * restent sur le poste, comme l'export PDF (ecarts declares dans l'ecran).
 */
#[Layout('components.layouts.app')]
class Ventes extends Component
{
    public const STATUTS = ['Payée', 'Avance', 'Annulée'];

    public string $recherche = '';

    /** Chaine vide = « Tous statuts ». */
    public string $statut = '';

    public ?string $venteId = null;

    public function ouvrir(string $id): void
    {
        $this->venteId = Vente::query()->whereKey($id)->exists() ? $id : null;
    }

    public function fermer(): void
    {
        $this->venteId = null;
    }

    /** Bornes UTC du jour courant dans le fuseau de l'entreprise (les dates sont stockees en UTC). */
    private function bornesDuJour(): array
    {
        $debut = CarbonImmutable::now(config('logialvia.fuseau'))->startOfDay();

        return [
            $debut->utc()->format('Y-m-d H:i:s.u'),
            $debut->addDay()->utc()->format('Y-m-d H:i:s.u'),
        ];
    }

    public function render()
    {
        $fuseau = config('logialvia.fuseau');
        [$debut, $fin] = $this->bornesDuJour();

        // KPI : ventes du jour NON annulees (Dart `_ventesDuJour`).
        $duJour = Vente::query()->where('status', '!=', 'Annulée')
            ->where('date_vente', '>=', $debut)->where('date_vente', '<', $fin);
        $nombreDuJour = (clone $duJour)->count();
        $chiffreAffaires = (float) (clone $duJour)->sum('total');

        $terme = trim($this->recherche);
        $echappe = addcslashes($terme, '%_\\');
        $ventes = Vente::query()
            ->when(in_array($this->statut, self::STATUTS, true), fn ($q) => $q->where('status', $this->statut))
            ->when($terme !== '', fn ($q) => $q->where(fn ($w) => $w
                ->whereRaw("reference like ? escape '\\'", ["%$echappe%"])
                ->orWhereRaw("client like ? escape '\\'", ["%$echappe%"])))
            ->orderByDesc('date_vente')->orderBy('reference')->get();

        $ouverte = $this->venteId
            ? Vente::query()->with(['lignes' => fn ($q) => $q->orderBy('name')])->find($this->venteId)
            : null;

        return view('livewire.ventes', [
            'ventes' => $ventes,
            'chiffreAffaires' => $chiffreAffaires,
            'panierMoyen' => $nombreDuJour === 0 ? null : $chiffreAffaires / $nombreDuJour,
            'enAttente' => Vente::query()->where('status', 'Avance')->count(),
            'ouverte' => $ouverte,
            'fuseau' => $fuseau,
            'statuts' => self::STATUTS,
        ])->title('Ventes');
    }
}
