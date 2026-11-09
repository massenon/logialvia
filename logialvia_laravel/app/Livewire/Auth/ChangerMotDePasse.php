<?php

namespace App\Livewire\Auth;

use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Livewire\Attributes\Layout;
use Livewire\Component;
use App\Support\Audit;

/** Changement du mot de passe : obligatoire apres un mot de passe temporaire. */
#[Layout('components.layouts.invite')]
class ChangerMotDePasse extends Component
{
    public string $actuel = '';

    public string $nouveau = '';

    public string $confirmation = '';

    public ?string $erreur = null;

    public function enregistrer()
    {
        $utilisateur = Auth::user();
        abort_if($utilisateur === null, 403);

        $this->erreur = null;

        if (! Hash::check($this->actuel, $utilisateur->password)) {
            $this->erreur = 'Le mot de passe actuel est incorrect.';

            return;
        }
        if (mb_strlen($this->nouveau) < 10) {
            $this->erreur = 'Le nouveau mot de passe doit comporter au moins 10 caractères.';

            return;
        }
        if ($this->nouveau !== $this->confirmation) {
            $this->erreur = 'La confirmation ne correspond pas.';

            return;
        }

        $utilisateur->forceFill(['password' => $this->nouveau, 'must_change_password' => false])->save();
        // Les postes de cet utilisateur devront se reconnecter.
        $utilisateur->tokens()->delete();
        Audit::enregistrer('web.mot_de_passe_change', $utilisateur);

        return redirect('/');
    }

    public function render()
    {
        return view('livewire.auth.changer-mot-de-passe')->title('Changer le mot de passe');
    }
}
