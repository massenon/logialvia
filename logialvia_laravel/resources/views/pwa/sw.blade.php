{{-- Service worker (47x_) : voir ServiceWorkerController pour les regles de surete. --}}
/* LogiALVIA — service worker étroit. Règles : (1) GET seulement ; (2) aucune page HTML en cache ;
   (3) fichiers statiques seulement (/build/, /fonts/, /icons/). Version : {!! $version !!} */
const VERSION = {!! json_encode($version) !!};
const PRECACHE = {!! json_encode($fichiers, JSON_UNESCAPED_SLASHES) !!};
const STATIQUE = ['/build/', '/fonts/', '/icons/'];
const EXCLUS = ['/livewire/', '/api/', '/login', '/logout', '/deconnexion', '/mot-de-passe', '/reset-password', '/storage/', '/sw.js'];

self.addEventListener('install', (event) => {
    event.waitUntil(caches.open(VERSION).then((cache) => cache.addAll(PRECACHE)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys()
            .then((noms) => Promise.all(noms.filter((n) => n.startsWith('logialvia-') && n !== VERSION).map((n) => caches.delete(n))))
            .then(() => self.clients.claim()),
    );
});

self.addEventListener('fetch', (event) => {
    const requete = event.request;
    if (requete.method !== 'GET') return; // règle 1
    const url = new URL(requete.url);
    if (url.origin !== self.location.origin) return;
    if (EXCLUS.some((p) => url.pathname.startsWith(p))) return;

    // Navigation : réseau d'abord ; la page d'attente n'apparaît qu'en cas d'échec réel (règle 2).
    if (requete.mode === 'navigate') {
        event.respondWith(fetch(requete).catch(() => caches.match('/hors-ligne')));
        return;
    }

    // Statique : cache d'abord (fichiers nommés par empreinte), puis réseau (règle 3).
    if (STATIQUE.some((p) => url.pathname.startsWith(p))) {
        event.respondWith(
            caches.match(requete).then((trouve) => trouve || fetch(requete).then((reponse) => {
                if (reponse.ok) {
                    const copie = reponse.clone();
                    caches.open(VERSION).then((cache) => cache.put(requete, copie));
                }

                return reponse;
            })),
        );
    }
});
