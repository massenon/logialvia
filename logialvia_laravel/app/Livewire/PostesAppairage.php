<?php

namespace App\Livewire;

use App\Models\Poste;
use App\Services\PostesService;
use App\Sync\DroitsPoste;
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
    /** Tables que n'importe quel compte peut ecrire (aucun droit particulier requis). */
    private const TABLES_OUVERTES_A_TOUT_COMPTE = ['messages_editeur', 'effets_stock'];

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

    /**
     * Etat de droits d'un poste : compte, role(s) et ce que le compte peut ecrire. `null` : aucun
     * compte connu. Le serveur ne sait pas combien de saisies attendent DE DROIT sur le poste :
     * cet etat-la se lit dans l'onglet Appairage du poste.
     *
     * @return array{compte: string, roles: string, tables: int, demandes: int, lecture_seule: bool, supprime: bool}|null
     */
    private function droitsDe(Poste $poste): ?array
    {
        $utilisateur = $poste->dernierUtilisateur;
        if ($utilisateur === null) {
            return null;
        }

        $d = DroitsPoste::pour($utilisateur);
        $libelles = config('logialvia.roles');

        return [
            'compte' => $d['compte'],
            'roles' => implode(', ', array_map(fn (string $r) => $libelles[$r] ?? $r, $d['roles'])) ?: 'Aucun rôle',
            'tables' => count($d['tables_ecrites']),
            'demandes' => count($d['demandes']),
            // Les tables ouvertes a TOUT compte (messages a l'editeur, trace des effets de stock du poste) ne
            // comptent pas comme un droit d'ecriture.
            'lecture_seule' => array_diff($d['tables_ecrites'], self::TABLES_OUVERTES_A_TOUT_COMPTE) === [] && $d['demandes'] === [],
            'supprime' => $utilisateur->trashed(),
        ];
    }

    public function render()
    {
        $this->verifierDroit();

        $postes = Poste::query()->with('dernierUtilisateur')->orderBy('code')->get()
            ->sortBy(fn (Poste $p) => (int) substr($p->code, 1))->values();

        // `47g_` : ce que le compte appaire a le droit d'ecrire (le poste ne propose que cela).
        $droits = [];
        foreach ($postes as $poste) {
            $droits[$poste->id] = $this->droitsDe($poste);
        }

        return view('livewire.postes-appairage', [
            'postes' => $postes,
            'droits' => $droits,
            'aConfirmer' => $this->posteAConfirmer
                ? Poste::query()->where('device_id', $this->posteAConfirmer)->first()
                : null,
        ])->title('Postes & Appairage');
    }
}
