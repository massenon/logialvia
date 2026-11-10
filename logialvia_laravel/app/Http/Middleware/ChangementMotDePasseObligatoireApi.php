<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Mot de passe temporaire : tout est refuse (403, motif en francais) SAUF son
 * changement, `me` et la deconnexion — routes qui n'utilisent pas ce middleware.
 */
class ChangementMotDePasseObligatoireApi
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user()?->must_change_password) {
            return response()->json([
                'message' => 'Vous devez changer votre mot de passe temporaire avant de continuer.',
                'code' => 'changement_mot_de_passe_obligatoire',
            ], 403);
        }

        return $next($request);
    }
}
