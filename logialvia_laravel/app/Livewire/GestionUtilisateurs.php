<?php

namespace App\Livewire;

use App\Models\User;
use App\Services\UtilisateursService;
use Illuminate\Support\Facades\Auth;
use Livewire\Component;

/**
 * Onglet « Gestion Utilisateurs » des Parametres Generaux (Dart : `_OngletUtilisateurs`,
 * `modale_utilisateur.dart`), integre a `ParametresGeneraux`. Droit `manage-users`,
 * reverifie dans CHAQUE methode d'ecriture. Toute la logique est dans `UtilisateursService`.
 *
 * Comptes du SERVEUR seulement (DV-20) ; mot de passe jamais affiche ; un mot de passe
 * administre est temporaire (changement obligatoire a la connexion). Doc 47u §1.
 */
class GestionUtilisateurs extends Component
{
    public string $recherche = '';

    // ---- Formulaire de creation / modification
    public bool $formulaire = false;

    public ?string $utilisateurId = null;

    public string $nom = '';

    public string $identifiant = '';

    public string $email = '';

    public string $role = '';

    public string $motDePasse = '';

    public string $confirmation = '';

    // ---- Reinitialisation du mot de passe
    public ?string $reinitialisationId = null;

    // ---- Confirmation d'une action destructive : `desactiver` ou `supprimer`
    public ?string $actionAConfirmer = null;

    public ?string $cibleAConfirmer = null;

    public ?string $erreur = null;

    public ?string $message = null;

    private function verifierDroit(): User
    {
        $acteur = Auth::user();
        abort_unless($acteur?->can('manage-users'), 403);

        return $acteur;
    }

    private function viderMotsDePasse(): void
    {
        $this->motDePasse = '';
        $this->confirmation = '';
    }

    private function fermer(): void
    {
        $this->formulaire = false;
        $this->utilisateurId = null;
        $this->reinitialisationId = null;
        $this->actionAConfirmer = null;
        $this->cibleAConfirmer = null;
        $this->nom = $this->identifiant = $this->email = $this->role = '';
        $this->viderMotsDePasse();
    }

    public function nouveau(): void
    {
        $this->verifierDroit();
        $this->fermer();
        $this->erreur = $this->message = null;
        $this->formulaire = true;
    }

    public function modifier(string $id): void
    {
        $this->verifierDroit();
        $this->fermer();
        $this->erreur = $this->message = null;

        $u = User::query()->find($id);
        if ($u === null) {
            $this->erreur = 'Ce compte n\'existe plus.';

            return;
        }
        $this->utilisateurId = $u->id;
        $this->nom = $u->name;
        $this->identifiant = $u->username;
        $this->email = (string) $u->email;
        $this->role = (string) $u->roles->first()?->name;
        $this->formulaire = true;
    }

    public function enregistrer(UtilisateursService $comptes): void
    {
        $acteur = $this->verifierDroit();
        $this->erreur = $this->message = null;

        if ($this->utilisateurId === null) {
            $resultat = $comptes->creer($acteur, $this->nom, $this->identifiant, $this->email, $this->role, $this->motDePasse, $this->confirmation);
            if ($resultat['erreur'] !== null) {
                $this->erreur = $resultat['erreur'];
                $this->viderMotsDePasse();

                return;
            }
            $this->message = "Compte « {$resultat['utilisateur']->username} » créé. Mot de passe temporaire : la personne devra le changer à sa première connexion.";
        } else {
            $erreur = $comptes->modifier($acteur, $this->utilisateurId, $this->nom, $this->role, $this->email);
            if ($erreur !== null) {
                $this->erreur = $erreur;

                return;
            }
            $this->message = 'Compte modifié.';
        }

        $this->fermer();
    }

    public function annuler(): void
    {
        $this->fermer();
        $this->erreur = null;
    }

    public function demanderReinitialisation(string $id): void
    {
        $this->verifierDroit();
        $this->fermer();
        $this->erreur = $this->message = null;
        $this->reinitialisationId = User::query()->whereKey($id)->exists() ? $id : null;
    }

    public function reinitialiser(UtilisateursService $comptes): void
    {
        $acteur = $this->verifierDroit();
        $this->erreur = $this->message = null;

        if ($this->reinitialisationId === null) {
            return;
        }
        $cible = User::query()->find($this->reinitialisationId);
        $erreur = $comptes->reinitialiserMotDePasse($acteur, $this->reinitialisationId, $this->motDePasse, $this->confirmation);
        if ($erreur !== null) {
            $this->erreur = $erreur;
            $this->viderMotsDePasse();

            return;
        }
        $this->message = "Mot de passe temporaire posé pour « {$cible?->username} » : le changement sera exigé à sa prochaine connexion, ses postes devront se reconnecter.";
        $this->fermer();
    }

    public function demanderAction(string $action, string $id): void
    {
        $this->verifierDroit();
        $this->fermer();
        $this->erreur = $this->message = null;

        if (in_array($action, ['desactiver', 'supprimer'], true) && User::query()->whereKey($id)->exists()) {
            $this->actionAConfirmer = $action;
            $this->cibleAConfirmer = $id;
        }
    }

    public function confirmerAction(UtilisateursService $comptes): void
    {
        $acteur = $this->verifierDroit();
        $this->erreur = $this->message = null;

        $action = $this->actionAConfirmer;
        $id = $this->cibleAConfirmer;
        if ($action === null || $id === null) {
            return;
        }

        $cible = User::query()->find($id);
        $erreur = match ($action) {
            'desactiver' => $comptes->desactiver($acteur, $id),
            'supprimer' => $comptes->supprimer($acteur, $id),
            default => 'Action inconnue.',
        };
        if ($erreur !== null) {
            $this->erreur = $erreur;
            $this->fermer();

            return;
        }
        $this->message = $action === 'desactiver'
            ? "Compte « {$cible?->username} » désactivé : connexion refusée, jetons des postes supprimés."
            : "Compte « {$cible?->username} » supprimé (archivé : il se restaure depuis la Corbeille).";
        $this->fermer();
    }

    public function reactiver(string $id, UtilisateursService $comptes): void
    {
        $acteur = $this->verifierDroit();
        $this->erreur = $this->message = null;

        $erreur = $comptes->reactiver($acteur, $id);
        if ($erreur !== null) {
            $this->erreur = $erreur;

            return;
        }
        $this->message = 'Compte réactivé.';
    }

    public function render()
    {
        $acteur = Auth::user();
        abort_unless($acteur?->can('manage-users'), 403);

        $terme = mb_strtolower(trim($this->recherche));
        $comptes = User::query()->with('roles')->orderBy('name')->get()
            ->filter(fn (User $u) => $terme === ''
                || str_contains(mb_strtolower($u->name.' '.$u->username.' '.$u->email), $terme))
            ->map(fn (User $u) => [
                'id' => $u->id,
                'nom' => $u->name,
                'identifiant' => $u->username,
                'email' => $u->email,
                'role' => $u->roles->first()?->name,
                'libelleRole' => config('logialvia.roles')[$u->roles->first()?->name] ?? '—',
                'actif' => $u->is_active,
                'temporaire' => $u->must_change_password,
                'moi' => $u->is($acteur),
                'derniereConnexion' => $u->last_login_at,
            ])->values();

        return view('livewire.gestion-utilisateurs', [
            'comptes' => $comptes,
            'roles' => config('logialvia.roles'),
            'cibleReinitialisation' => $this->reinitialisationId ? User::query()->find($this->reinitialisationId) : null,
            'cibleAction' => $this->cibleAConfirmer ? User::query()->find($this->cibleAConfirmer) : null,
        ]);
    }
}
