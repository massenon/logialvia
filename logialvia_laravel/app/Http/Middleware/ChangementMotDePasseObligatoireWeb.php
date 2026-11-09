<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/** Mot de passe temporaire : l'ecran de changement est la seule page ouverte. */
class ChangementMotDePasseObligatoireWeb
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user()?->must_change_password && ! $request->routeIs('mot-de-passe')) {
            return redirect()->route('mot-de-passe');
        }

        return $next($request);
    }
}
