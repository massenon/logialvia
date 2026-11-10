<?php

namespace App\Http\Middleware;

use App\Services\AuthentificationService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/** Un compte desactive en cours de session est refuse, avec son motif. */
class CompteActif
{
    public function handle(Request $request, Closure $next): Response
    {
        $utilisateur = $request->user();

        if ($utilisateur !== null && ! $utilisateur->is_active) {
            return response()->json([
                'message' => AuthentificationService::MESSAGE_DESACTIVE,
                'code' => 'compte_desactive',
            ], 403);
        }

        return $next($request);
    }
}
