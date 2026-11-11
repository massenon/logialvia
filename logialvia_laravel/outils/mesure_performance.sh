#!/usr/bin/env bash
# Mesure LOCALE, avec Lighthouse, du LCP reel d'un serveur LogiALVIA en ligne (47x_ / PWA-PERF).
#
#   bash logialvia_laravel/outils/mesure_performance.sh https://logialvia.exemple.bj [identifiant]
#   LV_MDP='...' bash logialvia_laravel/outils/mesure_performance.sh https://logialvia.exemple.bj admin1
#
# - sans identifiant : la page de connexion seule ; avec identifiant (+ LV_MDP, sinon demande au clavier) : aussi le tableau de bord ;
# - profils desktop ET mobile (4G lente simulee), cache vide, memes seuils que la garde CI : LCP < 2000 ms, score >= 90, CLS <= 0,1, TBT <= 200 ms ;
# - AUCUN mandataire : on mesure ce que le serveur sert vraiment (c'est la que se verifie que Brotli/gzip et le cache sont actifs) ;
# - les rapports Lighthouse (JSON) et synthese.json sont ecrits dans logialvia_laravel/e2e/rapports-performance/ ;
# - code de sortie 1 si un seuil est depasse. Variables : LV_SEUIL_LCP_MS, LV_PROFILS=desktop,mobile, CHROME_PATH (Chrome/Chromium a utiliser).
# Pre-requis : Node 20+ et un Chrome/Chromium (a defaut, `npx playwright install chromium` dans e2e/performance).
set -u
URL="${1:-}"
IDENTIFIANT="${2:-}"
if [ -z "$URL" ]; then
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
fi
URL="${URL%/}"

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RACINE/e2e/performance" || exit 1
[ -d node_modules ] || npm ci || exit 1

if [ -z "${CHROME_PATH:-}" ]; then
  for c in chromium chromium-browser google-chrome google-chrome-stable /opt/pw-browsers/chromium; do
    if command -v "$c" > /dev/null 2>&1; then CHROME_PATH="$(command -v "$c")"; break; fi
  done
  if [ -z "${CHROME_PATH:-}" ]; then
    npx playwright install chromium > /dev/null || exit 1
    CHROME_PATH="$(node -e "console.log(require('playwright').chromium.executablePath())")"
  fi
  export CHROME_PATH
fi

export LV_URL="$URL" LV_MANDATAIRE=0
if [ -n "$IDENTIFIANT" ]; then
  if [ -z "${LV_MDP:-}" ]; then
    read -r -s -p "Mot de passe de $IDENTIFIANT : " LV_MDP; echo
  fi
  export LV_IDENTIFIANT="$IDENTIFIANT" LV_MDP
else
  export LV_PAGES=connexion
fi
exec node ../performance.mjs
