<?php

namespace App\Livewire\Auth;

use App\Services\AuthentificationService;
use App\Support\Audit;
use App\Livewire\Aide;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cookie;
use Illuminate\Support\Facades\RateLimiter;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Validate;
use Livewire\Component;

/** Connexion web : memes regles et memes messages que l'appairage d'un poste. */
#[Layout('components.layouts.invite', ['sansMarque' => true])]
class Connexion extends Component
{
    #[Validate('required', message: "L'identifiant est obligatoire.")]
    public string $identifiant = '';

    #[Validate('required', message: 'Le mot de passe est obligatoire.')]
    public string $password = '';

    /** « Se souvenir de moi » : retient l'identifiant (jamais le mot de passe), comme le poste. */
    public bool $souvenir = false;

    public ?string $erreur = null;

    /** Message laisse par la deconnexion d'un compte desactive en cours de session (`CompteActifWeb`). */
    public function mount(): void
    {
        $this->erreur = session('erreur_connexion');

        $memorise = request()->cookie('lv_identifiant');
        if (is_string($memorise) && $memorise !== '') {
            $this->identifiant = $memorise;
            $this->souvenir = true;
        }
    }

    public function connecter(AuthentificationService $authentification)
    {
        $this->validate();
        $this->erreur = null;

        // 5 tentatives par minute, par identifiant ET adresse (comme l'API).
        $cle = 'connexion-web|'.mb_strtolower($this->identifiant).'|'.request()->ip();
        if (RateLimiter::tooManyAttempts($cle, 5)) {
            $this->erreur = 'Trop de tentatives. Réessayez dans '.RateLimiter::availableIn($cle).' secondes.';

            return;
        }

        $resultat = $authentification->verifier($this->identifiant, $this->password, request()->ip());

        if ($resultat['utilisateur'] === null) {
            RateLimiter::hit($cle, 60);
            $this->erreur = $resultat['erreur'];
            $this->password = '';

            return;
        }

        RateLimiter::clear($cle);
        // Retenu seulement apres une connexion REUSSIE : memoriser un identifiant refuse le reproposerait en boucle.
        $this->souvenir
            ? Cookie::queue('lv_identifiant', $resultat['utilisateur']->username, 60 * 24 * 365)
            : Cookie::queue(Cookie::forget('lv_identifiant'));
        Auth::login($resultat['utilisateur']);
        // Nouvel identifiant de session apres connexion (fixation de session).
        if (request()->hasSession()) {
            request()->session()->regenerate();
        }
        $resultat['utilisateur']->forceFill(['last_login_at' => now()])->save();
        Audit::enregistrer('web.login', $resultat['utilisateur']);

        return redirect()->intended('/');
    }

    public function render()
    {
        return view('livewire.auth.connexion', ['version' => Aide::VERSION])->title('Connexion');
    }
}
