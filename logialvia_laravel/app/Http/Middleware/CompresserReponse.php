<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Premier affichage < 2 s (47x_) : compresse les reponses texte (HTML, JSON de Livewire, CSS, JS) — Brotli quand
 * l'extension PHP `brotli` est presente ET que le navigateur l'accepte, sinon gzip.
 *
 * C'est le filet de securite des hebergements mutualises sans mod_brotli/mod_deflate (le `.htaccess` s'en charge
 * pour les fichiers statiques quand le serveur sait le faire). Prudences :
 *  - rien sans `Accept-Encoding` (clients de test, curl nu) ;
 *  - rien si la reponse est deja encodee (pas de double compression), en flux, ou un fichier binaire (XLSX, PDF, images) ;
 *  - rien sous 1 Ko : le gain ne paie pas le cout du processeur ;
 *  - `Vary: Accept-Encoding` toujours ajoute sur les types compressibles, pour que les caches intermediaires ne melangent pas les variantes.
 */
class CompresserReponse
{
    /** Taille minimale du corps a compresser, en octets. */
    public const SEUIL_OCTETS = 1024;

    private const TYPES = ['text/html', 'text/css', 'text/javascript', 'application/javascript', 'application/json', 'image/svg+xml', 'application/xml', 'text/plain', 'application/manifest+json'];

    public function handle(Request $request, Closure $next): Response
    {
        $reponse = $next($request);

        if ($reponse instanceof BinaryFileResponse || $reponse instanceof StreamedResponse || ! $this->compressible($reponse)) {
            return $reponse;
        }

        $reponse->headers->set('Vary', 'Accept-Encoding', false);
        $contenu = $reponse->getContent();
        if ($reponse->headers->has('Content-Encoding') || ! is_string($contenu) || strlen($contenu) < self::SEUIL_OCTETS) {
            return $reponse;
        }

        $accepte = strtolower((string) $request->headers->get('Accept-Encoding'));
        $codage = null;
        if (self::accepte($accepte, 'br') && function_exists('brotli_compress')) {
            $comprime = brotli_compress($contenu, 5);
            $codage = 'br';
        } elseif (self::accepte($accepte, 'gzip') && function_exists('gzencode')) {
            $comprime = gzencode($contenu, 6);
            $codage = 'gzip';
        }
        if ($codage === null || ! is_string($comprime)) {
            return $reponse;
        }

        $reponse->setContent($comprime);
        $reponse->headers->set('Content-Encoding', $codage);
        $reponse->headers->set('Content-Length', (string) strlen($comprime));
        // Un ETag calcule sur le corps non compresse ne decrit plus ce corps : on le rend « faible ».
        if (($etag = $reponse->headers->get('ETag')) && ! str_starts_with($etag, 'W/')) {
            $reponse->headers->set('ETag', 'W/'.$etag);
        }

        return $reponse;
    }

    private function compressible(Response $reponse): bool
    {
        $type = strtolower((string) $reponse->headers->get('Content-Type'));
        foreach (self::TYPES as $t) {
            if (str_starts_with($type, $t)) {
                return true;
            }
        }

        return false;
    }

    /** Vrai si `Accept-Encoding` nomme le codage sans q=0. */
    private static function accepte(string $entete, string $codage): bool
    {
        return (bool) preg_match('/(^|[\s,])'.preg_quote($codage, '/').'(\s*;\s*q=(?!0(\.0*)?(,|$))[0-9.]+)?\s*(,|$)/', $entete);
    }
}
