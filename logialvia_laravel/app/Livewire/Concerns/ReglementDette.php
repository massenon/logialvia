<?php

namespace App\Livewire\Concerns;

use App\Models\Achat;
use App\Models\Fournisseur;
use App\Services\Achats\GestionAchats;
use Illuminate\Support\Facades\Auth;

/**
 * Reglement d'une dette fournisseur (Dart : bouton « Régler » de `fournisseurs_screen`, modale
 * `_FormulaireReglement`), partage par Achats & Commandes et Fournisseurs. Le composant hote declare
 * `$message` et `$erreur`. Le droit `manage-achats` est verifie dans CHAQUE methode.
 */
trait ReglementDette
{
    /** Achat dont le reglement est en cours de saisie. */
    public ?string $aRegler = null;

    public string $montantReglement = '';

    public string $modeReglement = 'Espèces';

    public ?string $erreurReglement = null;

    private function verifierDroitDeRegler(): void
    {
        abort_unless(Auth::user()?->can('manage-achats'), 403);
    }

    public function demanderReglement(string $achatId): void
    {
        $this->verifierDroitDeRegler();
        $this->message = null;
        $this->erreur = null;
        $this->erreurReglement = null;
        $this->montantReglement = '';

        $achat = Achat::query()->find($achatId);
        if ($achat === null) {
            return;
        }
        // Le mode de la commande propose le mode du reglement ; « Crédit » n'est pas un instrument de paiement.
        $this->modeReglement = in_array($achat->mode, GestionAchats::MODES_REGLEMENT, true) ? $achat->mode : 'Espèces';
        $this->aRegler = $achat->id;
    }

    public function annulerReglement(): void
    {
        $this->aRegler = null;
        $this->erreurReglement = null;
    }

    public function confirmerReglement(): void
    {
        $this->verifierDroitDeRegler();
        $id = $this->aRegler;
        if ($id === null) {
            return;
        }

        $bilan = (new GestionAchats(Auth::user()))->regler($id, $this->montantReglement, $this->modeReglement);
        if ($bilan['erreur'] !== null) {
            $this->erreurReglement = $bilan['erreur'];

            return;
        }

        $this->aRegler = null;
        $this->erreurReglement = null;
        $this->message = 'Règlement de '.number_format($bilan['verse'], 0, ',', ' ')." FCFA enregistré ({$bilan['achat']->reference}).";
        if ($bilan['achat']->total - $bilan['achat']->paye < 0.005) {
            $this->message .= ' La dette est soldée.';
        }
    }

    /** @return array{achat: ?Achat, fournisseur: ?string, reste: float} Ce que la modale affiche. */
    protected function reglementEnCours(): array
    {
        $achat = $this->aRegler ? Achat::query()->find($this->aRegler) : null;

        return [
            'achat' => $achat,
            'fournisseur' => $achat ? Fournisseur::query()->find($achat->fournisseur_id)?->nom : null,
            'reste' => $achat ? max(0.0, round($achat->total - $achat->paye, 2)) : 0.0,
        ];
    }
}
