// Garde de performance du premier chargement web (47x_ / PWA-PERF) : ECHOUE si le LCP depasse 2 s.
//
//   LV_SCRIPT=e2e/performance.mjs bash e2e/lancer.sh [port]      (base jetable, serveur, comptes d'essai)
//   cd e2e/performance && npm ci && npm run garde                  (contre LV_URL deja lance)
//
// Profils Lighthouse : desktop (10 Mbit/s, 40 ms) ET mobile (4G lente simulee : 1,6 Mbit/s, 150 ms, processeur x4) ; LV_PROFILS=desktop pour n'en garder qu'un.
// Deux mesures independantes, sur la page de connexion ET le tableau de bord (apres connexion), navigateur neuf (cache vide) :
//  1. Lighthouse (simule) — LCP, FCP, TBT, CLS, score de performance ;
//  2. Playwright — LCP REEL (PerformanceObserver) sur une liaison limitee a 10 Mbit/s / 40 ms (CDP), cache vide.
// Seuils : LCP < 2000 ms (les deux mesures), score Lighthouse >= 90, CLS <= 0,1, TBT <= 200 ms.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const ICI = path.dirname(fileURLToPath(import.meta.url));
const exiger = createRequire(path.join(ICI, 'performance', 'package.json'));
const { chromium } = exiger('playwright');
const lighthouse = (await import(pathToFileURL(exiger.resolve('lighthouse')).href)).default;
const configurationDesktop = (await import(pathToFileURL(path.join(path.dirname(exiger.resolve('lighthouse/package.json')), 'core/config/desktop-config.js')).href)).default;

const URL_SERVEUR = process.env.LV_URL ?? 'http://127.0.0.1:8799';
const IDENTIFIANT = process.env.LV_IDENTIFIANT ?? 'admin1';
const MDP = process.env.LV_MDP ?? 'EssaiPoste-2026!';
const SEUIL_LCP_MS = Number(process.env.LV_SEUIL_LCP_MS ?? 2000);
const SEUIL_SCORE = 90;
const SEUIL_CLS = 0.1;
const SEUIL_TBT_MS = 200;
const PORT_DEBUG = Number(process.env.LV_PORT_DEBUG ?? 9333);
const PROFILS = (process.env.LV_PROFILS ?? 'desktop,mobile').split(',');
const SORTIE = process.env.LV_RAPPORTS ?? path.join(ICI, 'rapports-performance');
fs.mkdirSync(SORTIE, { recursive: true });

/**
 * `php artisan serve` ne compresse ni ne met en cache les fichiers statiques ; la production (Apache, `public/.htaccess`)
 * le fait. Pour mesurer ce que verra l'utilisateur, un mandataire local reproduit mod_brotli/mod_deflate (Brotli sinon gzip)
 * et le cache immuable de /build. LV_MANDATAIRE=0 le desactive (cible deja en production : outils/mesure_performance.sh).
 */
import http from 'node:http';
import zlib from 'node:zlib';

const COMPRESSIBLES = /^(text\/(html|css|javascript|plain)|application\/(javascript|json|manifest\+json)|image\/svg\+xml)/;

function demarrerMandataire(cible) {
    const amont = new URL(cible);
    const serveur = http.createServer((req, res) => {
        const entetes = { ...req.headers };
        const accepte = String(req.headers['accept-encoding'] ?? '');
        delete entetes['accept-encoding'];
        const r = http.request({ host: amont.hostname, port: amont.port, path: req.url, method: req.method, headers: entetes }, (reponse) => {
            const morceaux = [];
            reponse.on('data', (c) => morceaux.push(c));
            reponse.on('end', () => {
                let corps = Buffer.concat(morceaux);
                const sortie = { ...reponse.headers };
                delete sortie['transfer-encoding'];
                const type = String(sortie['content-type'] ?? '');
                if (COMPRESSIBLES.test(type) && corps.length > 1024 && !sortie['content-encoding']) {
                    if (/\bbr\b/.test(accepte)) { corps = zlib.brotliCompressSync(corps, { params: { [zlib.constants.BROTLI_PARAM_QUALITY]: 5 } }); sortie['content-encoding'] = 'br'; }
                    else if (/\bgzip\b/.test(accepte)) { corps = zlib.gzipSync(corps); sortie['content-encoding'] = 'gzip'; }
                    sortie.vary = 'Accept-Encoding';
                }
                if (req.url.startsWith('/build/')) sortie['cache-control'] = 'public, max-age=31536000, immutable';
                sortie['content-length'] = corps.length;
                res.writeHead(reponse.statusCode, sortie);
                res.end(corps);
            });
        });
        r.on('error', () => { res.writeHead(502); res.end(); });
        req.pipe(r);
    });
    return new Promise((ok) => serveur.listen(0, '127.0.0.1', () => ok({ serveur, url: `http://127.0.0.1:${serveur.address().port}` })));
}

const mandataire = process.env.LV_MANDATAIRE === '0' ? null : await demarrerMandataire(URL_SERVEUR);
const URL_BASE = mandataire ? mandataire.url : URL_SERVEUR;

const resultats = [];
const TOUTES_PAGES = [
    { nom: 'connexion', chemin: '/login', authentifie: false },
    { nom: 'tableau-de-bord', chemin: '/dashboard', authentifie: true },
];
// LV_PAGES=connexion : sans identifiants (mesure d'un serveur de production dont on n'a pas de compte d'essai).
const pages = TOUTES_PAGES.filter((p) => !process.env.LV_PAGES || process.env.LV_PAGES.split(',').includes(p.nom));

/** Profil de navigateur persistant : c'est le contexte PAR DEFAUT, celui que Lighthouse (port de debogage) pilote aussi. */
async function lancer() {
    const profil = fs.mkdtempSync(path.join(SORTIE, 'profil-'));

    return chromium.launchPersistentContext(profil, {
        executablePath: process.env.CHROME_PATH || undefined,
        headless: true,
        viewport: { width: 1350, height: 940 },
        args: [`--remote-debugging-port=${PORT_DEBUG}`, '--no-sandbox', '--disable-dev-shm-usage'],
    });
}

async function seConnecter(contexte) {
    const page = await contexte.newPage();
    await page.goto(`${URL_BASE}/login`, { waitUntil: 'networkidle' });
    await page.fill('#identifiant', IDENTIFIANT);
    await page.fill('#password', MDP);
    await Promise.all([page.waitForURL((u) => !u.pathname.startsWith('/login'), { timeout: 20000 }), page.click('button[type=submit]')]);
    await page.close();
}

/** Mesure Lighthouse (simulee, profil desktop) dans le navigateur pilote (session ouverte comprise). */
async function mesureLighthouse(chemin, profil) {
    // « mobile » = configuration par defaut de Lighthouse (4G lente simulee : 1,6 Mbit/s, 150 ms, processeur x4).
    const rapport = await lighthouse(`${URL_BASE}${chemin}`, {
        port: PORT_DEBUG, output: 'json', logLevel: 'error', onlyCategories: ['performance'],
    }, profil === 'desktop' ? configurationDesktop : undefined);
    const a = rapport.lhr.audits;

    return {
        score: Math.round((rapport.lhr.categories.performance.score ?? 0) * 100),
        lcp: Math.round(a['largest-contentful-paint'].numericValue),
        fcp: Math.round(a['first-contentful-paint'].numericValue),
        tbt: Math.round(a['total-blocking-time'].numericValue),
        cls: Number((a['cumulative-layout-shift'].numericValue ?? 0).toFixed(3)),
        poids: Math.round((a['total-byte-weight'].numericValue ?? 0) / 1024),
        rapport: rapport.report,
    };
}

/** LCP reel : cache vide, liaison 10 Mbit/s / 40 ms (CDP), PerformanceObserver. */
async function mesureLcpReel(contexte, chemin) {
    const page = await contexte.newPage();
    const cdp = await contexte.newCDPSession(page);
    await cdp.send('Network.enable');
    await cdp.send('Network.clearBrowserCache');
    await cdp.send('Network.emulateNetworkConditions', {
        offline: false, latency: 40, downloadThroughput: (10 * 1024 * 1024) / 8, uploadThroughput: (10 * 1024 * 1024) / 8,
    });
    await page.addInitScript(() => {
        window.__lcp = 0;
        new PerformanceObserver((liste) => {
            for (const e of liste.getEntries()) window.__lcp = Math.max(window.__lcp, e.startTime);
        }).observe({ type: 'largest-contentful-paint', buffered: true });
    });
    await page.goto(`${URL_BASE}${chemin}`, { waitUntil: 'load' });
    await page.waitForTimeout(800); // laisse le LCP se stabiliser
    const lcp = await page.evaluate(() => Math.round(window.__lcp));
    await page.close();

    return lcp;
}

/** 2e visite : une fois le service worker actif, les fichiers hachees de /build/assets/ sortent TOUS du cache (aucun octet du reseau). */
async function verifierSecondeVisite(contexte) {
    const page = await contexte.newPage();
    await page.goto(`${URL_BASE}/login`, { waitUntil: 'load' });
    const pret = await page.evaluate(() => Promise.race([
        navigator.serviceWorker.ready.then(() => true),
        new Promise((r) => setTimeout(() => r(false), 8000)),
    ]));
    if (!pret) { await page.close(); return { ok: false, detail: 'service worker non actif apres 8 s' }; }
    await page.waitForTimeout(500); // le precache (install) est termine quand `ready` repond ; marge pour la prise de controle
    await page.reload({ waitUntil: 'load' }); // la page rechargee est maintenant controlee par le service worker
    const vus = [];
    page.on('response', (r) => { if (r.url().includes('/build/assets/')) vus.push({ url: r.url(), sw: r.fromServiceWorker() }); });
    await page.reload({ waitUntil: 'load' });
    await page.waitForTimeout(1500); // laisse partir le chargement differe du chunk PWA
    await page.close();
    const reseau = vus.filter((v) => !v.sw).map((v) => v.url.split('/').pop());

    return { ok: vus.length >= 3 && reseau.length === 0, detail: `${vus.length} fichiers /build/assets/, ${reseau.length} depuis le reseau${reseau.length ? ' : ' + reseau.join(', ') : ''}` };
}

const contexte = await lancer();
let secondeVisite = null;
try {
    // Connexion d'abord (page publique, session vierge) ; le tableau de bord ensuite, session ouverte dans CE navigateur.
    let connecte = false;
    for (const p of pages) {
        if (p.authentifie && !connecte) {
            await seConnecter(contexte);
            connecte = true;
        }
        if (!secondeVisite && !p.authentifie) secondeVisite = await verifierSecondeVisite(contexte);
        const lcpReel = await mesureLcpReel(contexte, p.chemin);
        for (const profil of PROFILS) {
            const lh = await mesureLighthouse(p.chemin, profil);
            fs.writeFileSync(path.join(SORTIE, `lighthouse-${p.nom}-${profil}.json`), lh.rapport);
            resultats.push({ page: `${p.nom} (${profil})`, chemin: p.chemin, ...lh, rapport: undefined, lcpReel });
        }
    }
} finally {
    await contexte.close();
    mandataire?.serveur.close();
}

// ---------------------------------------------------------------------------------------------- verdict
const fautes = [];
console.log('\nPerformance du premier chargement (cache vide)');
console.log('page'.padEnd(18), 'score', 'LCP LH', 'LCP reel', 'FCP', 'TBT', 'CLS', 'Ko');
for (const r of resultats) {
    console.log(r.page.padEnd(18), String(r.score).padEnd(5), String(r.lcp).padEnd(6), String(r.lcpReel).padEnd(8), String(r.fcp).padEnd(3), String(r.tbt).padEnd(3), String(r.cls).padEnd(3), r.poids);
    if (r.lcp > SEUIL_LCP_MS) fautes.push(`${r.page} : LCP Lighthouse ${r.lcp} ms > ${SEUIL_LCP_MS} ms`);
    if (r.lcpReel > SEUIL_LCP_MS) fautes.push(`${r.page} : LCP reel ${r.lcpReel} ms > ${SEUIL_LCP_MS} ms`);
    if (r.score < SEUIL_SCORE) fautes.push(`${r.page} : score de performance ${r.score} < ${SEUIL_SCORE}`);
    if (r.cls > SEUIL_CLS) fautes.push(`${r.page} : CLS ${r.cls} > ${SEUIL_CLS}`);
    if (r.tbt > SEUIL_TBT_MS) fautes.push(`${r.page} : TBT ${r.tbt} ms > ${SEUIL_TBT_MS} ms`);
}
console.log(`2e visite (service worker, cache-first /build/assets/) : ${secondeVisite?.ok ? 'OK' : 'ECHEC'} — ${secondeVisite?.detail}`);
if (!secondeVisite?.ok) fautes.push(`2e visite : les fichiers /build/assets/ ne sortent pas tous du cache du service worker (${secondeVisite?.detail})`);
fs.writeFileSync(path.join(SORTIE, 'synthese.json'), JSON.stringify({ date: new Date().toISOString(), seuilLcpMs: SEUIL_LCP_MS, secondeVisite, resultats }, null, 2));

if (fautes.length) {
    console.error('\nECHEC — seuils de performance non tenus :\n  ' + fautes.join('\n  '));
    process.exit(1);
}
console.log(`\nOK — LCP < ${SEUIL_LCP_MS} ms sur la connexion et le tableau de bord (Lighthouse + mesure reelle).`);
