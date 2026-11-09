<?php

namespace App\Livewire;

use App\Models\Poste;
use App\Services\PostesService;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Postes & Appairage (droit `manage-users`) : les postes connus du serveur, leur
 * etat, et la revocation. La revocation passe par une modale de confirmation, et
 * le droit est reverifie dans chaque methode qui ecrit (jamais seulement a la route).
 */
#[Layout('components.layouts.app')]
class PostesAppairage extends Component
{
    /** Identifiant (UUID) du poste dont on demande la revocation ; `null` = modale fermee. */
    public ?string $posteAConfirmer = null;

    public ?string $message = null;

    private function verifierDroit(): void
    {
        abort_unless(Auth::user()?->can('manage-users'), 403);
    }

    public function demanderRevocation(string $deviceId): void
    {
        $this->verifierDroit();

        $this->message = null;
        $this->posteAConfirmer = Poste::query()->where('device_id', $deviceId)->exists() ? $deviceId : null;
    }

    public function annuler(): void
    {
        $this->posteAConfirmer = null;
    }

    public function confirmerRevocation(PostesService $postes): void
    {
        $this->verifierDroit();

        if ($this->posteAConfirmer === null) {
            return;
        }

        $poste = Poste::query()->where('device_id', $this->posteAConfirmer)->first();
        $supprimes = $postes->revoquer($this->posteAConfirmer, Auth::user());

        $this->message = $supprimes === null
            ? 'Poste inconnu.'
            : "Appairage révoqué pour le poste {$poste->code} : $supprimes jeton(s) supprimé(s).";
        $this->posteAConfirmer = null;
    }

    public function render()
    {
        $this->verifierDroit();

        return view('livewire.postes-appairage', [
            'postes' => Poste::query()->with('dernierUtilisateur')->orderBy('code')->get()
                ->sortBy(fn (Poste $p) => (int) substr($p->code, 1))->values(),
            'aConfirmer' => $this->posteAConfirmer
                ? Poste::query()->where('device_id', $this->posteAConfirmer)->first()
                : null,
        ])->title('Postes & Appairage');
    }
}
