<?php

namespace App\Http\Middleware;

use App\Models\Poste;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/** Le nom du jeton courant est l'identifiant du poste : on note son dernier contact. */
class EnregistrerContactPoste
{
    public function handle(Request $request, Closure $next): Response
    {
        $jeton = $request->user()?->currentAccessToken();

        if ($jeton !== null && isset($jeton->name)) {
            Poste::query()->where('device_id', $jeton->name)->update(['dernier_contact_le' => now()]);
        }

        return $next($request);
    }
}
