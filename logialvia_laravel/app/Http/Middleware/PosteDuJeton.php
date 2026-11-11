<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Le jeton dit QUI parle : le `device_id` envoye doit etre le nom du jeton
 * courant, sinon 403 — rien n'est ecrit, rien n'est journalise. Un poste ne signe
 * pas au nom d'un autre.
 *
 * Ecritures (`poste.jeton`) : `device_id` OBLIGATOIRE. Lectures (`poste.jeton:lecture` : tirage, demande de
 * synchronisation) : recoupe le `device_id` quand le poste l'envoie, tolere son absence (anciens postes) ;
 * le serveur lit de toute facon l'identite dans le nom du jeton, jamais dans la requete.
 */
class PosteDuJeton
{
    public function handle(Request $request, Closure $next, string $mode = 'ecriture'): Response
    {
        $jeton = $request->user()?->currentAccessToken();
        $envoye = $request->input('device_id');
        $tolere = $mode === 'lecture' && $envoye === null;

        if ($jeton === null || (! $tolere && $envoye !== $jeton->name)) {
            return response()->json([
                'message' => "Ce poste ne peut pas envoyer au nom d'un autre poste.",
                'code' => 'poste_different_du_jeton',
            ], 403);
        }

        return $next($request);
    }
}
