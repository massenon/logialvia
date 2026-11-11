<?php

namespace App\Http\Controllers;

use Illuminate\Http\Response;

/**
 * Service worker de la PWA (`/sw.js`), GENERE pour que la liste de precache suive toujours le build Vite
 * (les fichiers sont nommes par empreinte). Trois regles de surete, ecrites en tete du fichier servi :
 *  1. seules les requetes GET sont interceptees ;
 *  2. aucune page HTML n'est stockee : une navigation passe par le reseau et ne retombe sur `/hors-ligne`
 *     qu'en cas d'echec reel (jamais de page authentifiee en cache) ;
 *  3. seuls les fichiers statiques (`/build/`, `/fonts/`, `/icons/`) sont mis en cache ; sont exclus
 *     `/livewire/`, `/api/`, `/login`, `/logout`, `/deconnexion`, `/mot-de-passe`, `/storage/`.
 * Le travail hors ligne n'est PAS fait ici (deux sources de verite) : c'est le poste Windows, via /api/sync.
 */
class ServiceWorkerController extends Controller
{
    /** @return list<string> Les fichiers statiques a precharger (JS/CSS du build, polices, icones, page d'attente). */
    public static function fichiersAPrecacher(): array
    {
        $liste = ['/hors-ligne', '/manifest.webmanifest', '/icons/icon-192.png', '/icons/icon-512.png'];
        foreach (glob(public_path('fonts/*.woff2')) ?: [] as $police) {
            $liste[] = '/fonts/'.basename($police);
        }
        $manifeste = public_path('build/manifest.json');
        if (is_file($manifeste)) {
            foreach (json_decode((string) file_get_contents($manifeste), true) ?: [] as $entree) {
                foreach (array_merge([$entree['file'] ?? null], $entree['css'] ?? []) as $fichier) {
                    if (is_string($fichier)) {
                        $liste[] = '/build/'.$fichier;
                    }
                }
            }
        }

        return array_values(array_unique($liste));
    }

    public function __invoke(): Response
    {
        $fichiers = self::fichiersAPrecacher();
        $version = 'logialvia-'.substr(md5(implode('|', $fichiers)), 0, 10);

        $corps = view('pwa.sw', ['version' => $version, 'fichiers' => $fichiers])->render();

        return response($corps, 200, [
            'Content-Type' => 'text/javascript; charset=utf-8',
            'Service-Worker-Allowed' => '/',
            // Le navigateur doit pouvoir detecter une nouvelle version a chaque visite.
            'Cache-Control' => 'no-cache, max-age=0',
        ]);
    }
}
