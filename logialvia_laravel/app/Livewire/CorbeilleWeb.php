<?php

namespace App\Livewire;

use App\Services\CorbeilleService;
use App\Support\ExportXlsx;
use Illuminate\Support\Facades\Auth;
use Livewire\Component;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Onglet « Corbeille » des Parametres Generaux (Dart : `onglet_corbeille.dart`), integre a
 * `ParametresGeneraux`. Lecture : `view-parametres` (celui qui voit l'ecran). Restauration : droit
 * d'ecriture de l'element (+ administrateur pour les types reserves). Purge : administrateur, comptes
 * seulement. Toute la logique est dans `CorbeilleService` (doc 47u §3).
 */
class CorbeilleWeb extends Component
{
    public string $type = '';

    public string $recherche = '';

    /** Purge en attente de confirmation : `type|id`. */
    public ?string $purgeAConfirmer = null;

    public ?string $message = null;

    public ?string $erreur = null;

    private function acteur()
    {
        $u = Auth::user();
        abort_unless($u?->can('view-parametres'), 403);

        return $u;
    }

    public function restaurer(string $type, string $id, CorbeilleService $corbeille): void
    {
        $acteur = $this->acteur();
        $this->message = $this->erreur = $this->purgeAConfirmer = null;

        $motif = $corbeille->restaurer($acteur, $type, $id);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        $this->message = 'Élément restauré : il redescend vers les postes à leur prochaine synchronisation.';
    }

    public function demanderPurge(string $type, string $id): void
    {
        $this->acteur();
        $this->message = $this->erreur = null;
        $this->purgeAConfirmer = $type.'|'.$id;
    }

    public function annuler(): void
    {
        $this->acteur();
        $this->purgeAConfirmer = null;
    }

    public function confirmerPurge(CorbeilleService $corbeille): void
    {
        $acteur = $this->acteur();
        $this->message = $this->erreur = null;
        [$type, $id] = array_pad(explode('|', (string) $this->purgeAConfirmer, 2), 2, '');
        $this->purgeAConfirmer = null;

        $motif = $corbeille->purger($acteur, $type, $id);
        if ($motif !== null) {
            $this->erreur = $motif;

            return;
        }
        $this->message = 'Élément effacé définitivement.';
    }

    private function filtres(CorbeilleService $corbeille)
    {
        $terme = mb_strtolower(trim($this->recherche));

        return $corbeille->elements($this->acteur())
            ->when($this->type !== '', fn ($c) => $c->where('type', $this->type))
            ->when($terme !== '', fn ($c) => $c->filter(fn ($e) => str_contains(mb_strtolower($e['designation'].' '.$e['libelle']), $terme)))
            ->values();
    }

    /** Export XLSX : meme contenu que l'ecran (filtres compris). */
    public function exporter(CorbeilleService $corbeille): StreamedResponse
    {
        $this->acteur();
        $lignes = [['Module', 'Type', 'Désignation', 'Archivé le (UTC)', 'Origine']];
        foreach ($this->filtres($corbeille) as $e) {
            $lignes[] = [$e['module'], $e['libelle'], $e['designation'], $e['archive_le']->utc()->format('Y-m-d H:i:s'), $e['origine']];
        }

        return ExportXlsx::telecharger($lignes, 'corbeille.xlsx', 'Corbeille');
    }

    public function render(CorbeilleService $corbeille)
    {
        $elements = $this->filtres($corbeille);

        return view('livewire.corbeille-web', [
            'elements' => $elements,
            'types' => collect(CorbeilleService::types())->map(fn ($d) => $d['libelle'])->all(),
            'fuseau' => config('logialvia.fuseau'),
        ]);
    }
}
