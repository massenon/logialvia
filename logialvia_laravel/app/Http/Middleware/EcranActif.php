<?php

namespace App\Http\Middleware;

use App\Support\Navigation;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/** 404 quand le module de la route est desactive (Doc I2 §3). Parametre : la route de la matrice. */
class EcranActif
{
    public function handle(Request $request, Closure $next, string $route): Response
    {
        abort_unless(Navigation::moduleDeRouteActif($route), 404);

        return $next($request);
    }
}
