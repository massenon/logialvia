<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Le jeton dit QUI parle : le `device_id` envoye doit etre le nom du jeton
 * courant, sinon 403 — rien n'est ecrit, rien n'est journalise. Un poste ne signe
 * pas au nom d'un autre.
 */
class PosteDuJeton
{
    public function handle(Request $request, Closure $next): Response
    {
        $jeton = $request->user()?->currentAccessToken();

        if ($jeton === null || $request->input('device_id') !== $jeton->name) {
            return response()->json([
                'message' => "Ce poste ne peut pas envoyer au nom d'un autre poste.",
                'code' => 'poste_different_du_jeton',
            ], 403);
        }

        return $next($request);
    }
}
