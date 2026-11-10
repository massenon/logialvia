<?php

namespace App\Http\Middleware;

use App\Services\AuthentificationService;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Un compte DESACTIVE en cours de session web est deconnecte aussitot (son prochain clic mene
 * a la connexion, avec le motif), comme l'API refuse deja un jeton de compte desactive
 * (`CompteActif`). Sans cela, la desactivation par l'administrateur n'aurait d'effet qu'a la
 * prochaine connexion. Un compte SUPPRIME (suppression logique) n'est plus retrouve par le
 * garde : la session tombe d'elle-meme.
 */
class CompteActifWeb
{
    public function handle(Request $request, Closure $next): Response
    {
        $utilisateur = $request->user();

        if ($utilisateur !== null && ! $utilisateur->is_active) {
            Auth::logout();
            $request->session()->invalidate();
            $request->session()->regenerateToken();

            return redirect()->route('login')->with('erreur_connexion', AuthentificationService::MESSAGE_DESACTIVE);
        }

        return $next($request);
    }
}
