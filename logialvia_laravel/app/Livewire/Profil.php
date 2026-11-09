<?php

namespace App\Livewire;

use App\Livewire\Auth\ChangerMotDePasse;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;

/**
 * Mon Profil (Dart : `mon_profil_screen.dart`) : identite du compte connecte (nom, identifiant, role)
 * et changement de mot de passe. Ouvert a TOUT compte connecte.
 *
 * Le changement de mot de passe est celui de `ChangerMotDePasse` (heritage) : AUCUNE regle reecrite
 * (mot de passe actuel verifie, 10 caracteres minimum, confirmation, jetons des postes revoques, audit).
 * Ecarts declares : ni journal d'audit personnel, ni « derniere connexion » / nombre de connexions
 * (le serveur ne garde que la connexion en cours : il n'a pas l'historique que tient le poste).
 */
#[Layout('components.layouts.app')]
class Profil extends ChangerMotDePasse
{
    public function render()
    {
        $utilisateur = Auth::user();
        abort_if($utilisateur === null, 403);

        $role = $utilisateur->roles->first()?->name;
        $mots = preg_split('/\s+/', trim($utilisateur->name)) ?: [];
        $initiales = mb_strtoupper(collect($mots)->filter()->take(2)->map(fn ($m) => mb_substr($m, 0, 1))->implode(''));

        return view('livewire.profil', [
            'nom' => $utilisateur->name,
            'identifiant' => $utilisateur->username,
            'libelleRole' => config('logialvia.roles')[$role] ?? '—',
            'initiales' => $initiales === '' ? '?' : $initiales,
        ])->title('Mon Profil');
    }
}
