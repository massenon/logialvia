<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Hebergement mutualise (`47r_`) : Apache en CGI/FastCGI RETIRE parfois l'en-tete
 * `Authorization` avant PHP ; le jeton du poste n'arrive alors jamais (401 permanent).
 * Le poste envoie donc AUSSI le meme jeton dans `X-Authorization` (jamais retire) ; on le
 * rend a `Authorization` s'il manque. Les variables `REDIRECT_HTTP_AUTHORIZATION` /
 * `HTTP_AUTHORIZATION` posees par la regle `.htaccess` sont deja lues par Symfony.
 * Aucune faille : c'est le MEME secret, au meme endroit de la requete.
 */
class RestaurerEnTeteAutorisation
{
    public function handle(Request $request, Closure $next): Response
    {
        if (! $request->headers->has('Authorization')) {
            $secours = $request->headers->get('X-Authorization');
            if (is_string($secours) && $secours !== '') {
                $request->headers->set('Authorization', $secours);
            }
        }

        return $next($request);
    }
}
