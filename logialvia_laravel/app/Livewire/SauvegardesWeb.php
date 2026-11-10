<?php

namespace App\Livewire;

use App\Services\SauvegardeLogiqueService;
use Illuminate\Support\Facades\Auth;
use Livewire\Component;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Onglet « Sauvegardes » des Parametres Generaux (Dart : `onglet_sauvegardes.dart`), integre a
 * `ParametresGeneraux`. Le web propose le TELECHARGEMENT d'une sauvegarde LOGIQUE des donnees du
 * serveur (administrateur seul, droit verifie dans la methode). Creation/restauration d'une copie
 * de base, planification et verification se font sur le poste (doc 47u §5).
 */
class SauvegardesWeb extends Component
{
    public function telecharger(SauvegardeLogiqueService $sauvegarde): StreamedResponse
    {
        $acteur = Auth::user();
        abort_unless($acteur?->can('manage-parametres'), 403);

        return $sauvegarde->telecharger($acteur);
    }

    public function render()
    {
        $acteur = Auth::user();
        abort_unless($acteur?->can('view-parametres'), 403);

        return view('livewire.sauvegardes-web', [
            'peutTelecharger' => $acteur->can('manage-parametres') && $acteur->hasRole('admin'),
            'tables' => count(SauvegardeLogiqueService::tables()),
        ]);
    }
}
