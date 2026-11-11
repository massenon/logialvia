# 47x — PWA installable et performance du premier chargement (web Laravel)

Objectif (PWA-PERF) : **LCP < 2 s au premier chargement**, page de connexion et tableau de bord, cache vide — et une garde automatique qui échoue sinon.

## Ce qui est livré

| Sujet | Réalisation |
|---|---|
| Installable | `public/manifest.webmanifest`, icônes 192/512/maskable/apple-touch, `<x-pwa-tete />` dans les deux layouts, invite d'installation (`resources/js/pwa.js`, chargé après `load` au repos du navigateur). |
| Service worker | `/sw.js` **généré** (`ServiceWorkerController`) : la liste de précache suit `public/build/manifest.json` (fichiers nommés par empreinte). Règles étroites : GET seulement ; aucune page HTML en cache ; seuls `/build/`, `/fonts/`, `/icons/` sont stockés ; exclus `/livewire/ /api/ /login /logout /deconnexion /mot-de-passe /reset-password /storage/`. **Cache-first** sur ces trois dossiers : dès la 2ᵉ visite les fichiers hachés sortent du cache. Hors réseau : page autonome `/hors-ligne`. Le vrai travail hors ligne reste celui du poste Windows (`/api/sync`, doc 40). |
| Séparation des vendors | `vite.config.js` (`manualChunks`) : Livewire + Alpine (~187 Ko) dans `vendor-livewire-<hash>.js`, à part du code applicatif (~4 Ko). `resources/js/app.js` importe `livewire.esm` et appelle `Livewire.start()` ; `config/livewire.php` met `inject_assets=false` ; les layouts déclarent `@livewireStyles` + `@livewireScriptConfig`. Plus de `livewire.min.js` bloquant : tous les scripts sont des modules différés. |
| CSS critique | `<link rel="preload" as="style">` du CSS haché dans les layouts (avant `@vite`). |
| Polices | WOFF2 latin (Roboto 489 → 83 Ko ; police d'icônes statique 154 → 12 Ko), préchargement `Link:` de la police d'icônes (`PrechargerPolices`). Remplace le « HTTP/2 push », retiré des navigateurs. |
| Compression | Production : `public/.htaccess` (mod_brotli sinon mod_deflate) + cache immuable de `/build`. Filet pour hébergement sans ces modules : `App\Http\Middleware\CompresserReponse` (Brotli si l'extension PHP existe et est acceptée, sinon gzip ; ≥ 1 Ko ; jamais de double compression ni de fichier binaire/flux ; `Vary: Accept-Encoding`). |
| Axios | retiré (jamais utilisé, −35 Ko). |

## Gardes (toutes automatiques)

1. **`PerformanceAssetsTest`** (job `laravel`, `php artisan test`) : échoue si le JS total du build > 300 Ko ou le CSS > 100 Ko ; si Livewire/Alpine retournent dans le bundle applicatif ; si une page contient un `<script>` bloquant ; si le CSS critique n'est plus préchargé. En CI, un build absent est une erreur.
2. **`PwaTest`, `CompresserReponseTest`** : manifeste, règles du service worker, précache existant, middleware.
3. **Garde LCP** `logialvia_laravel/e2e/performance.mjs` (workflow `.github/workflows/performance.yml`) : Lighthouse **desktop** et **mobile** (4G lente simulée, CPU ×4) + LCP réel Playwright (liaison 10 Mbit/s, 40 ms, cache vide), sur `/login` **et sur les 36 autres écrans de l'application** (élevage, ventes, stocks, achats, comptabilité, paramètres, profil, aide…). Les écrans d'impression sont exclus. Seuils : LCP < 2000 ms, score ≥ 90, CLS ≤ 0,1, TBT ≤ 200 ms. Vérifie aussi, via Playwright (`response.fromServiceWorker()`), que **tous** les fichiers `/build/assets/` de la 2ᵉ visite viennent du service worker.

```bash
# base jetable + serveur local + comptes d'essai
LV_SCRIPT=e2e/performance.mjs bash logialvia_laravel/e2e/lancer.sh 8799
# réglages : LV_SEUIL_LCP_MS=2000  LV_PROFILS=desktop,mobile  LV_PAGES=connexion  LV_MANDATAIRE=0
```

Le serveur de dev (`php artisan serve`) ne compresse pas les fichiers statiques : par défaut le script place devant lui un petit mandataire qui joue le rôle d'Apache (Brotli/gzip + cache immuable de `/build`), pour mesurer ce que verra l'utilisateur en production.

## Mesurer le serveur de production

```bash
bash logialvia_laravel/outils/mesure_performance.sh https://votre-domaine            # page de connexion
LV_MDP='…' bash logialvia_laravel/outils/mesure_performance.sh https://votre-domaine admin1   # + tableau de bord
```

Sans mandataire : c'est ce que le serveur sert réellement (donc la preuve que Brotli/gzip et le cache sont actifs). Rapports JSON dans `logialvia_laravel/e2e/rapports-performance/`. Code de sortie 1 si un seuil est dépassé.

## Résultats constatés (poste de développement, serveur local derrière le mandataire)

| Page | Lighthouse desktop (LCP / score) | Lighthouse mobile (LCP / score) | LCP réel 10 Mbit/s |
|---|---|---|---|
| Connexion | ≈ 0,55 s / 100 | ≈ 1,97 s / 98 | ≈ 0,12–0,35 s |
| Tableau de bord | ≈ 0,55–0,6 s / 100 | ≈ 1,97 s / 99 | ≈ 0,18 s |

**Marge faible sur mobile simulé** (≈ 30–40 ms sous 2 s) : le profil Lighthouse mobile impose RTT 150 ms et 1,6 Mbit/s ; le plancher est dû au nombre d'aller-retours (HTML puis CSS), pas au poids. Avant ce lot, avec Livewire en `<script>` bloquant et sans compression : 2,6 s (connexion) et 3,1 s (tableau de bord). Si un hébergeur n'active ni Brotli ni gzip sur les fichiers statiques, le mobile peut dépasser 2 s : `mesure_performance.sh` le montrera.

## Défauts trouvés en étendant la garde à tous les écrans (corrigés)
- **CLS 0,2–0,34 (achats, catalogue, ventes, fiches pintades/escargots, états financiers)** : la police Roboto arrivait après le premier affichage ; son échange avec la police de repli changeait la largeur des titres et faisait passer les boutons d'en-tête de la ligne du dessous à la ligne du titre. Correction : Roboto est de nouveau préchargée (`Link: rel=preload` + `<link>`), CLS ≈ 0.
- **LCP mobile 2,2 s (rapports, profil, paramètres généraux)** : (1) le bandeau « Installer LogiALVIA » devenait le plus grand élément texte ; il n'apparaît plus qu'à la première interaction (ou après 8 s) ; (2) l'italique de Roboto (97 Ko) concurrençait le premier affichage ; il est maintenant chargé après `load` (FontFace, `app.js`).
- La boîte des icônes est fixée à 1em × 1em (évite qu'un glyphe de remplacement plus large ne pousse la page avant l'arrivée de la police d'icônes).

## Limites connues
- Mesures faites en HTTP local ; en HTTPS réel s'ajoute le coût TLS (non simulé ici).
- Lighthouse « mobile » est un modèle simulé, pas un téléphone réel.
- Le cache-first ne s'applique qu'aux fichiers hachés/statiques ; une page HTML n'est jamais servie depuis le cache.
