<?php

namespace App\Services;

use App\Models\User;
use App\Support\Audit;
use App\Support\RegleMotDePasse;
use Illuminate\Support\Facades\DB;

/**
 * Gestion des comptes du SERVEUR (`users`) par l'administrateur (droit `manage-users`).
 *
 * Doc 47u. Les comptes locaux d'un poste restent propres au poste (DV-20) : le web ne les
 * gere pas. Ici n'existent que les comptes crees par l'administrateur (pas de compte
 * « acheteur », decision du client du 09/11/2026).
 *
 * Regles de l'expert (garde-fous absents du prototype) :
 *  - le DERNIER administrateur actif ne peut etre ni supprime, ni desactive, ni retrograde ;
 *  - on n'agit jamais sur son PROPRE compte (desactivation, suppression, role, reinitialisation) ;
 *  - un compte desactive ou supprime perd TOUS ses jetons de poste ;
 *  - un mot de passe administre est TEMPORAIRE : le changement est obligatoire a la connexion ;
 *  - aucun mot de passe dans le journal d'audit ni dans un message.
 *
 * Le droit est reverifie ICI (pas seulement a la route ni dans le composant).
 * Chaque methode renvoie le motif du refus (francais), ou `null` quand c'est fait.
 */
class UtilisateursService
{
    private function exigerDroit(User $acteur): void
    {
        abort_unless($acteur->can('manage-users'), 403);
    }

    /** Nombre d'administrateurs ACTIFS (non supprimes) autres que `$cible`. */
    public function autresAdministrateursActifs(User $cible): int
    {
        return User::query()
            ->role('admin')
            ->where('is_active', true)
            ->where('id', '!=', $cible->id)
            ->count();
    }

    private function estAdministrateurActif(User $u): bool
    {
        return $u->is_active && $u->hasRole('admin');
    }

    /** @return string|null motif du refus si `$cible` est le dernier administrateur actif. */
    private function refusDernierAdmin(User $cible, string $action): ?string
    {
        if ($this->estAdministrateurActif($cible) && $this->autresAdministrateursActifs($cible) === 0) {
            return "Impossible de $action le dernier compte administrateur actif.";
        }

        return null;
    }

    /** Valide un mot de passe saisi deux fois (regle du Dart). */
    private function erreurMotDePasse(string $motDePasse, string $confirmation): ?string
    {
        if ($motDePasse === '') {
            return 'Le mot de passe est obligatoire.';
        }
        if (($complexite = RegleMotDePasse::erreur($motDePasse)) !== null) {
            return $complexite;
        }
        if ($motDePasse !== $confirmation) {
            return 'Les deux mots de passe ne correspondent pas.';
        }

        return null;
    }

    /** @return string|null motif si l'adresse est invalide ou deja prise (hors `$sauf`). */
    private function erreurEmail(?string $email, ?string $sauf = null): ?string
    {
        if ($email === null || $email === '') {
            return null;
        }
        if (! preg_match('/^[^@\s]+@[^@\s]+\.[^@\s]+$/', $email) || mb_strlen($email) > 255) {
            return 'Le format de l\'adresse e-mail est invalide.';
        }
        $pris = User::withTrashed()->where('email', $email)->when($sauf, fn ($q) => $q->where('id', '!=', $sauf))->exists();

        return $pris ? 'Cette adresse e-mail est déjà utilisée.' : null;
    }

    /**
     * Cree un compte. Mot de passe temporaire : changement obligatoire a la premiere connexion.
     *
     * @return array{utilisateur: ?User, erreur: ?string}
     */
    public function creer(User $acteur, string $nom, string $identifiant, ?string $email, ?string $role, string $motDePasse, string $confirmation): array
    {
        $this->exigerDroit($acteur);

        $nom = trim($nom);
        $identifiant = trim($identifiant);
        $email = $email === null ? null : trim($email);

        // Dart : un identifiant peut etre une adresse e-mail ; la connexion cherche alors la colonne `email`.
        if ($identifiant !== '' && str_contains($identifiant, '@') && ($email === null || $email === '')) {
            $email = $identifiant;
        }

        $erreur = match (true) {
            $nom === '' => 'Le nom complet est obligatoire.',
            mb_strlen($nom) > 255 => 'Le nom complet est trop long.',
            $identifiant === '' => 'L\'identifiant de connexion est obligatoire.',
            mb_strlen($identifiant) > 60 => 'L\'identifiant de connexion est trop long (60 caractères au plus).',
            $role === null || $role === '' => 'Le rôle est obligatoire.',
            ! array_key_exists($role, config('logialvia.roles')) => 'Ce rôle n\'existe pas.',
            User::withTrashed()->where('username', $identifiant)->exists() => 'Cet identifiant est déjà utilisé (un compte supprimé le garde : restaurez-le depuis la Corbeille).',
            default => $this->erreurEmail($email) ?? $this->erreurMotDePasse($motDePasse, $confirmation),
        };
        if ($erreur !== null) {
            return ['utilisateur' => null, 'erreur' => $erreur];
        }

        $utilisateur = DB::transaction(function () use ($acteur, $nom, $identifiant, $email, $role, $motDePasse) {
            $u = User::query()->create([
                'name' => $nom,
                'username' => $identifiant,
                'email' => $email === '' ? null : $email,
                'password' => $motDePasse,
                'is_active' => true,
                'must_change_password' => true,
            ]);
            $u->syncRoles([$role]);
            Audit::enregistrer('utilisateur.cree', $acteur, ['cible' => $u->username, 'role' => $role]);

            return $u;
        });

        return ['utilisateur' => $utilisateur, 'erreur' => null];
    }

    /** Modifie le nom, le rôle et l'e-mail (l'identifiant de connexion ne change pas). */
    public function modifier(User $acteur, string $id, string $nom, ?string $role, ?string $email): ?string
    {
        $this->exigerDroit($acteur);

        $cible = User::query()->find($id);
        if ($cible === null) {
            return 'Ce compte n\'existe plus.';
        }
        $nom = trim($nom);
        $email = $email === null ? null : trim($email);

        $erreur = match (true) {
            $nom === '' => 'Le nom complet est obligatoire.',
            mb_strlen($nom) > 255 => 'Le nom complet est trop long.',
            $role === null || $role === '' => 'Le rôle est obligatoire.',
            ! array_key_exists($role, config('logialvia.roles')) => 'Ce rôle n\'existe pas.',
            default => $this->erreurEmail($email, $cible->id),
        };
        if ($erreur !== null) {
            return $erreur;
        }

        $roleActuel = $cible->roles->first()?->name;
        if ($role !== $roleActuel) {
            if ($cible->is($acteur)) {
                return 'Vous ne pouvez pas modifier le rôle de votre propre compte.';
            }
            if ($roleActuel === 'admin' && ($refus = $this->refusDernierAdmin($cible, 'rétrograder')) !== null) {
                return $refus;
            }
        }

        DB::transaction(function () use ($acteur, $cible, $nom, $role, $roleActuel, $email) {
            $cible->forceFill(['name' => $nom, 'email' => $email === '' ? null : $email])->save();
            if ($role !== $roleActuel) {
                $cible->syncRoles([$role]);
            }
            Audit::enregistrer('utilisateur.modifie', $acteur, [
                'cible' => $cible->username,
                'role_avant' => $roleActuel,
                'role_apres' => $role,
            ]);
        });

        return null;
    }

    /** Desactive un compte : refuse a la connexion, jetons des postes supprimes. */
    public function desactiver(User $acteur, string $id): ?string
    {
        $this->exigerDroit($acteur);

        $cible = User::query()->find($id);
        if ($cible === null) {
            return 'Ce compte n\'existe plus.';
        }
        if ($cible->is($acteur)) {
            return 'Vous ne pouvez pas désactiver votre propre compte.';
        }
        if (($refus = $this->refusDernierAdmin($cible, 'désactiver')) !== null) {
            return $refus;
        }
        if (! $cible->is_active) {
            return null;
        }

        DB::transaction(function () use ($acteur, $cible) {
            $cible->forceFill(['is_active' => false])->save();
            $jetons = $cible->tokens()->delete();
            Audit::enregistrer('utilisateur.desactive', $acteur, ['cible' => $cible->username, 'jetons_supprimes' => $jetons]);
        });

        return null;
    }

    public function reactiver(User $acteur, string $id): ?string
    {
        $this->exigerDroit($acteur);

        $cible = User::query()->find($id);
        if ($cible === null) {
            return 'Ce compte n\'existe plus.';
        }
        if ($cible->is_active) {
            return null;
        }

        $cible->forceFill(['is_active' => true])->save();
        Audit::enregistrer('utilisateur.reactive', $acteur, ['cible' => $cible->username]);

        return null;
    }

    /** Pose un mot de passe TEMPORAIRE : changement obligatoire, jetons des postes supprimes. */
    public function reinitialiserMotDePasse(User $acteur, string $id, string $motDePasse, string $confirmation): ?string
    {
        $this->exigerDroit($acteur);

        $cible = User::query()->find($id);
        if ($cible === null) {
            return 'Ce compte n\'existe plus.';
        }
        if ($cible->is($acteur)) {
            return 'Pour changer votre propre mot de passe, passez par Mon Profil.';
        }
        if (($erreur = $this->erreurMotDePasse($motDePasse, $confirmation)) !== null) {
            return $erreur;
        }

        DB::transaction(function () use ($acteur, $cible, $motDePasse) {
            $cible->forceFill(['password' => $motDePasse, 'must_change_password' => true])->save();
            $jetons = $cible->tokens()->delete();
            // Jamais le mot de passe dans le detail (Audit::enregistrer l'ecarterait de toute facon).
            Audit::enregistrer('utilisateur.mdp_reinitialise', $acteur, ['cible' => $cible->username, 'jetons_supprimes' => $jetons]);
        });

        return null;
    }

    /** Archive (suppression logique) : le compte disparait de la liste, la Corbeille peut le restaurer. */
    public function supprimer(User $acteur, string $id): ?string
    {
        $this->exigerDroit($acteur);

        $cible = User::query()->find($id);
        if ($cible === null) {
            return 'Ce compte n\'existe plus.';
        }
        if ($cible->is($acteur)) {
            return 'Vous ne pouvez pas supprimer votre propre compte.';
        }
        if (($refus = $this->refusDernierAdmin($cible, 'supprimer')) !== null) {
            return $refus;
        }

        DB::transaction(function () use ($acteur, $cible) {
            $jetons = $cible->tokens()->delete();
            $cible->delete();
            Audit::enregistrer('utilisateur.archive', $acteur, ['cible' => $cible->username, 'jetons_supprimes' => $jetons]);
        });

        return null;
    }

    /** Restaure un compte archive (Corbeille ; reserve a l'administrateur, qui a `manage-users`). */
    public function restaurer(User $acteur, string $id): ?string
    {
        $this->exigerDroit($acteur);

        $cible = User::onlyTrashed()->find($id);
        if ($cible === null) {
            return 'Cet élément n\'est plus en corbeille.';
        }
        $cible->restore();
        Audit::enregistrer('utilisateur.restaure', $acteur, ['cible' => $cible->username]);

        return null;
    }

    /** Efface DEFINITIVEMENT un compte archive. Le journal d'audit le garde (aucune cle etrangere). */
    public function purger(User $acteur, string $id): ?string
    {
        $this->exigerDroit($acteur);
        abort_unless($acteur->hasRole('admin'), 403);

        $cible = User::onlyTrashed()->find($id);
        if ($cible === null) {
            return 'Cet élément n\'est plus en corbeille.';
        }

        DB::transaction(function () use ($acteur, $cible) {
            $cible->tokens()->delete();
            $cible->syncRoles([]);
            $cible->forceDelete();
            Audit::enregistrer('utilisateur.purge', $acteur, ['cible' => $cible->username]);
        });

        return null;
    }
}
