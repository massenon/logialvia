<?php

namespace App\Livewire;

use App\Livewire\Auth\ChangerMotDePasse;
use App\Models\AuditLog;
use Illuminate\Support\Facades\Auth;
use Livewire\Attributes\Layout;

/**
 * Mon Profil (Dart : `mon_profil_screen.dart`) : identite du compte connecte (nom, identifiant, role)
 * et changement de mot de passe. Ouvert a TOUT compte connecte.
 *
 * Le changement de mot de passe est celui de `ChangerMotDePasse` (heritage) : AUCUNE regle reecrite
 * (mot de passe actuel verifie, regle du Dart : 8 caracteres, 1 majuscule, 1 chiffre, confirmation,
 * nouveau different de l'ancien, jetons des postes revoques, audit).
 *
 * Metadonnees de session et journal PERSONNEL comme au poste (doc 47u §5) : « derniere connexion » (la
 * connexion precedente), nombre de connexions, 20 dernieres actions du compte, lus dans `audit_logs`.
 * Ecart declare : le serveur ne journalise pas les deconnexions ni les ventes/achats (faits des postes) ;
 * le journal personnel montre ce que le serveur sait.
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

        // Connexions : web et appairage d'un poste. La premiere est la session EN COURS (Dart).
        $connexions = AuditLog::query()->where('utilisateur_id', $utilisateur->id)->whereIn('action', ['web.login', 'api.login'])
            ->orderByDesc('created_at')->orderByDesc('id')->get(['created_at']);
        $journal = AuditLog::query()->where('utilisateur_id', $utilisateur->id)
            ->orderByDesc('created_at')->orderByDesc('id')->limit(20)->get();

        return view('livewire.profil', [
            'derniereConnexion' => $connexions->count() >= 2 ? $connexions[1]->created_at : null,
            'nombreConnexions' => $connexions->count(),
            'actif' => (bool) $utilisateur->is_active,
            'journal' => $journal,
            'fuseau' => config('logialvia.fuseau'),
            'nom' => $utilisateur->name,
            'identifiant' => $utilisateur->username,
            'libelleRole' => config('logialvia.roles')[$role] ?? '—',
            'initiales' => $initiales === '' ? '?' : $initiales,
        ])->title('Mon Profil');
    }
}
