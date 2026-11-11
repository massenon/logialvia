<?php

namespace Tests\Feature\Web;

use App\Http\Controllers\ServiceWorkerController;
use App\Http\Middleware\PrechargerPolices;
use Tests\TestCase;

/**
 * PWA et performance du premier chargement (47x_) : manifeste installable, service worker ETROIT (3 regles de surete
 * assertees mot pour mot), page d'attente autonome, polices precompressees, budgets de poids.
 */
class PwaTest extends TestCase
{
    public function test_le_manifeste_est_installable(): void
    {
        $chemin = public_path('manifest.webmanifest');
        $this->assertFileExists($chemin);
        $m = json_decode((string) file_get_contents($chemin), true, 512, JSON_THROW_ON_ERROR);

        $this->assertSame('standalone', $m['display']);
        $this->assertSame('LogiALVIA', $m['short_name']);
        $this->assertStringStartsWith('/', $m['start_url']);
        $this->assertSame('/', $m['scope']);
        $this->assertSame('#1F3864', $m['theme_color']);

        $tailles = [];
        $maskable = false;
        foreach ($m['icons'] as $icone) {
            $fichier = public_path(ltrim($icone['src'], '/'));
            $this->assertFileExists($fichier, $icone['src']);
            [$l, $h] = getimagesize($fichier);
            $this->assertSame($icone['sizes'], "{$l}x{$h}", 'taille declaree = taille reelle de '.$icone['src']);
            $tailles[] = $l;
            $maskable = $maskable || ($icone['purpose'] ?? '') === 'maskable';
        }
        $this->assertContains(192, $tailles);
        $this->assertContains(512, $tailles);
        $this->assertTrue($maskable, 'une icone « maskable » est necessaire a l\'installation sur Android');
        foreach ($m['shortcuts'] as $raccourci) {
            $this->assertStringStartsWith('/', $raccourci['url']);
        }
    }

    public function test_le_service_worker_est_servi_avec_les_bons_en_tetes(): void
    {
        $r = $this->get('/sw.js')->assertOk();
        $this->assertStringContainsString('javascript', (string) $r->headers->get('Content-Type'));
        $this->assertSame('/', $r->headers->get('Service-Worker-Allowed'));
        $this->assertStringContainsString('no-cache', (string) $r->headers->get('Cache-Control'));
    }

    public function test_le_service_worker_garde_ses_trois_regles_de_surete(): void
    {
        $js = $this->get('/sw.js')->assertOk()->getContent();

        // 1. GET seulement.
        $this->assertStringContainsString("if (requete.method !== 'GET') return;", $js);
        // 2. Aucune page HTML en cache : la navigation passe par le reseau, la page d'attente n'est qu'un repli.
        $this->assertStringContainsString("event.respondWith(fetch(requete).catch(() => caches.match('/hors-ligne')));", $js);
        $this->assertStringNotContainsString("cache.put(requete", explode("requete.mode === 'navigate'", $js)[0], 'rien n\'est mis en cache avant le test de navigation');
        // 3. Statique seulement ; Livewire, API et authentification exclus.
        $this->assertStringContainsString("const STATIQUE = ['/build/', '/fonts/', '/icons/'];", $js);
        foreach (['/livewire/', '/api/', '/login', '/logout', '/deconnexion', '/mot-de-passe', '/storage/'] as $exclu) {
            $this->assertStringContainsString("'$exclu'", $js);
        }
        // Le precache ne contient que du statique et la page d'attente : jamais /dashboard, /ventes…
        foreach (ServiceWorkerController::fichiersAPrecacher() as $fichier) {
            $this->assertMatchesRegularExpression('#^/(build/|fonts/|icons/|hors-ligne$|manifest\.webmanifest$)#', $fichier);
        }
    }

    public function test_tout_ce_que_le_service_worker_precache_existe(): void
    {
        foreach (ServiceWorkerController::fichiersAPrecacher() as $fichier) {
            if ($fichier === '/hors-ligne') {
                $this->get($fichier)->assertOk();
            } else {
                $this->assertFileExists(public_path(ltrim($fichier, '/')), $fichier);
            }
        }
    }

    public function test_la_version_du_service_worker_suit_le_precache(): void
    {
        $a = $this->get('/sw.js')->getContent();
        $b = $this->get('/sw.js')->getContent();
        $this->assertSame($a, $b, 'meme build = meme version (pas de cache re-telecharge pour rien)');
        $this->assertMatchesRegularExpression('/const VERSION = "logialvia-[0-9a-f]{10}";/', $a);
    }

    public function test_la_page_d_attente_est_publique_et_autonome(): void
    {
        $html = $this->get('/hors-ligne')->assertOk()->getContent();
        $this->assertStringContainsString('Vous êtes hors ligne', $html);
        $this->assertStringNotContainsString('<link', $html, 'aucun fichier externe : elle doit s\'afficher sans reseau');
        $this->assertStringNotContainsString('<script src', $html);
        $this->assertStringNotContainsString('@vite', $html);
    }

    public function test_les_pages_declarent_le_manifeste_et_prechargent_les_polices(): void
    {
        $r = $this->get('/login')->assertOk();
        $r->assertSee('<link rel="manifest" href="/manifest.webmanifest">', false)
            ->assertSee('<meta name="theme-color" content="#1F3864">', false)
            ->assertSee('rel="apple-touch-icon"', false);

        $liens = implode("\n", $r->headers->all('link'));
        foreach (PrechargerPolices::POLICES as $police) {
            $this->assertStringContainsString("<$police>; rel=preload; as=font", $liens);
            $r->assertSee('<link rel="preload" href="'.$police.'" as="font"', false);
        }
    }

    public function test_les_polices_sont_en_woff2_et_le_css_ne_nomme_qu_elles(): void
    {
        $css = (string) file_get_contents(resource_path('css/app.css'));
        $this->assertStringNotContainsString('.ttf', $css, 'plus de TTF servi au navigateur (489 Ko -> 83 Ko en WOFF2 latin)');
        foreach (['Roboto-Variable-latin.woff2', 'MaterialSymbolsOutlined-LogiALVIA.woff2'] as $police) {
            $this->assertStringContainsString($police, $css);
            $this->assertFileExists(public_path('fonts/'.$police));
        }
        // Pas d'italique telecharge : son echange re-peignait le texte apres le LCP (CI mobile > 2 s).
        $this->assertStringNotContainsString('Roboto-Italic', $css);
        $this->assertStringNotContainsString('Roboto-Italic', (string) file_get_contents(resource_path('js/app.js')));
        $this->assertFileDoesNotExist(public_path('fonts/Roboto-Italic-Variable-latin.woff2'));
    }

    public function test_budgets_de_poids_du_premier_chargement(): void
    {
        $assets = glob(public_path('build/assets/*')) ?: [];
        if ($assets === []) {
            $this->markTestSkipped('Build Vite absent : `npm run build` d\'abord.');
        }
        $poids = fn (string $motif) => array_sum(array_map('filesize', glob(public_path($motif)) ?: []));

        $this->assertLessThan(40_000, filesize(glob(public_path('build/assets/app-*.js'))[0]), 'JS critique (hors chunk PWA) < 40 Ko');
        $this->assertLessThan(60_000, filesize(glob(public_path('build/assets/app-*.css'))[0]), 'CSS critique < 60 Ko');
        $this->assertLessThan(20_000, filesize(public_path('fonts/MaterialSymbolsOutlined-LogiALVIA.woff2')), 'police d\'icones < 20 Ko');
        $this->assertLessThan(100_000, filesize(public_path('fonts/Roboto-Variable-latin.woff2')), 'Roboto latin < 100 Ko');
        $this->assertFileDoesNotExist(public_path('fonts/MaterialSymbolsOutlined-LogiALVIA.woff'));
        $this->assertGreaterThan(0, $poids('build/assets/pwa-*.js'), 'le chunk PWA est separe du chemin critique');
    }
}
