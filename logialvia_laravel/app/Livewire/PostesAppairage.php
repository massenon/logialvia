<?php

namespace App\Livewire;

use App\Models\Poste;
use App\Services\DemandesSynchronisationService;
use App\Services\PostesService;
use App\Sync\MoteurSynchronisation;
use App\Sync\DroitsPoste;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
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

    /** Poste dont on demande le renvoi COMPLET ; `'*'` = tous les postes appaires ; `null` = modale fermee. */
    public ?string $renvoiAConfirmer = null;

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
        $this->renvoiAConfirmer = null;
    }

    /** Recharge la liste (l'etat des postes se lit a chaque rendu : il suffit de rendre de nouveau). */
    public function actualiser(): void
    {
        $this->verifierDroit();

        $this->message = 'Liste des postes actualisée.';
    }

    /**
     * « Synchroniser maintenant » : un poste (`device_id`) ou tous (`null`). Le poste interroge le serveur toutes les
     * 30 s : il synchronise sous 30 s s'il est joignable. Meme service que `POST /api/parametres/postes/synchroniser`.
     */
    public function demander(DemandesSynchronisationService $demandes, ?string $deviceId = null): void
    {
        $this->verifierDroit();

        if ($deviceId === null) {
            $demandes->demander(Auth::user(), null);
            $this->message = 'Synchronisation demandée à tous les postes (ils synchronisent sous 30 secondes).';

            return;
        }

        $poste = Poste::query()->where('device_id', $deviceId)->first();
        if ($poste === null) {
            $this->message = 'Poste inconnu.';

            return;
        }
        $demandes->demander(Auth::user(), $deviceId);
        $this->message = "Synchronisation demandée au poste {$poste->code} (il synchronise sous 30 secondes).";
    }

    /** Ouvre la confirmation d'un renvoi COMPLET (`'*'` = tous les postes appaires). */
    public function demanderRenvoi(string $deviceId): void
    {
        $this->verifierDroit();

        $this->message = null;
        $this->renvoiAConfirmer = $deviceId === '*' || Poste::query()->where('device_id', $deviceId)->exists() ? $deviceId : null;
    }

    public function confirmerRenvoi(DemandesSynchronisationService $demandes): void
    {
        $this->verifierDroit();

        $cible = $this->renvoiAConfirmer;
        $this->renvoiAConfirmer = null;
        if ($cible === null) {
            return;
        }

        $postes = $cible === '*'
            ? Poste::query()->whereNull('revoque_le')->get()
            : Poste::query()->where('device_id', $cible)->get();
        foreach ($postes as $poste) {
            $demandes->renvoyer(Auth::user(), $poste->device_id);
        }

        $this->message = $postes->isEmpty()
            ? 'Poste inconnu.'
            : ($cible === '*'
                ? 'Renvoi complet demandé à tous les postes : chacun repartira d\'un tirage complet à son prochain contact.'
                : "Renvoi complet demandé au poste {$postes->first()->code} : il repartira d'un tirage complet à son prochain contact.");
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

    public function render(MoteurSynchronisation $moteur)
    {
        $this->verifierDroit();

        $postes = Poste::query()->with('dernierUtilisateur')->orderBy('code')->get()
            ->sortBy(fn (Poste $p) => (int) substr($p->code, 1))->values();

        // `47g_` : ce que le compte appaire a le droit d'ecrire (le poste ne propose que cela).
        $droits = [];
        foreach ($postes as $poste) {
            $droits[$poste->id] = $this->droitsDe($poste);
        }

        // Ce qui attend un poste : une demande de synchronisation valide non servie, un renvoi complet non acquitte.
        $attente = [];
        foreach ($postes as $poste) {
            $demandeEnAttente = DB::table('demandes_synchronisation as d')
                ->where('d.expire_le', '>', now())
                ->where(fn ($q) => $q->whereNull('d.device_id')->orWhere('d.device_id', $poste->device_id))
                ->whereNotExists(fn ($q) => $q->select(DB::raw(1))
                    ->from('demandes_synchronisation_servies as s')
                    ->whereColumn('s.demande_id', 'd.id')
                    ->where('s.device_id', $poste->device_id))
                ->exists();
            $attente[$poste->id] = [
                'demande' => $demandeEnAttente,
                'renvoi' => $poste->resync_demandee_le !== null,
            ];
        }

        // Retard : lignes du serveur plus recentes que le dernier tirage du poste (avec les droits de son dernier compte).
        $retards = [];
        foreach ($postes as $poste) {
            $compte = $poste->dernierUtilisateur;
            $retards[$poste->id] = $poste->etat() !== 'appaire' || $compte === null || $compte->trashed()
                ? null
                : [
                    'jamais' => $poste->getRawOriginal('curseur_tirage') === null,
                    'lignes' => array_sum($moteur->retard($poste->getRawOriginal('curseur_tirage'), $compte)),
                ];
        }

        return view('livewire.postes-appairage', [
            'retards' => $retards,
            'attente' => $attente,
            'renvoiCible' => $this->renvoiAConfirmer === '*'
                ? 'tous'
                : ($this->renvoiAConfirmer ? Poste::query()->where('device_id', $this->renvoiAConfirmer)->value('code') : null),
            'postes' => $postes,
            'droits' => $droits,
            'aConfirmer' => $this->posteAConfirmer
                ? Poste::query()->where('device_id', $this->posteAConfirmer)->first()
                : null,
        ])->title('Postes & Appairage');
    }
}
