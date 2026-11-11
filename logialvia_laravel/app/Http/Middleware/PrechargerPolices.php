<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Premier affichage < 2 s (47x_) : ajoute aux pages HTML l'en-tete `Link: rel=preload` des deux polices critiques.
 * Le navigateur (ou le serveur, en 103 Early Hints) les demande AVANT d'avoir lu le CSS qui les nomme.
 * Remplace le « HTTP/2 push », retire de Chrome et des serveurs courants.
 */
class PrechargerPolices
{
    public const POLICES = [
        '/fonts/Roboto-Variable-latin.woff2',
        '/fonts/MaterialSymbolsOutlined-LogiALVIA.woff2',
    ];

    public function handle(Request $request, Closure $next): Response
    {
        $reponse = $next($request);

        if (str_contains((string) $reponse->headers->get('Content-Type'), 'text/html')) {
            foreach (self::POLICES as $police) {
                $reponse->headers->set('Link', "<$police>; rel=preload; as=font; type=\"font/woff2\"; crossorigin", false);
            }
        }

        return $reponse;
    }
}
