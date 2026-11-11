#!/usr/bin/env bash
# Essai de TOUS les ecrans web dans un VRAI navigateur (docs/logialvia/47n_TESTS_NAVIGATEUR.md).
#
#   bash logialvia_laravel/e2e/lancer.sh [port] [-- arguments passes a node e2e/executer.mjs (ex. un filtre)]
#
# - base SQLite JETABLE neuve (migrations + seeders + jeu de donnees `donnees.php`), jamais celle de l'exploitation ;
# - comptes admin1 / comptable1 / caissier1 / animalier1 / temporaire1 (mot de passe d'essai) ;
# - `npm run build`, `php artisan serve` (4 workers), puis `node e2e/executer.mjs` (Playwright, Chromium local).
# Variables : LV_DOSSIER (base jetable, /tmp/lv-e2e par defaut), SANS_BUILD=1 (saute `npm run build`).
set -u
PORT="${1:-8799}"
[ "$#" -gt 0 ] && shift
[ "${1:-}" = "--" ] && shift

RACINE="$(cd "$(dirname "$0")/.." && pwd)"
LV_DOSSIER="${LV_DOSSIER:-/tmp/lv-e2e}"
MDP='EssaiPoste-2026!'
mkdir -p "$LV_DOSSIER"

export DB_CONNECTION=sqlite DB_DATABASE="$LV_DOSSIER/e2e.sqlite" ADMIN_INITIAL_PASSWORD="$MDP" \
  BCRYPT_ROUNDS=4 SESSION_DRIVER=file SESSION_LIFETIME=120 CACHE_STORE=file APP_ENV=local APP_DEBUG=false \
  APP_URL="http://127.0.0.1:$PORT"
rm -f "$DB_DATABASE" && touch "$DB_DATABASE"

cd "$RACINE" || exit 1
if [ -z "${SANS_BUILD:-}" ]; then
  npm run build > "$LV_DOSSIER/build.log" 2>&1 || { cat "$LV_DOSSIER/build.log"; exit 1; }
fi
php artisan migrate:fresh --seed --force > "$LV_DOSSIER/migrate.log" 2>&1 || { cat "$LV_DOSSIER/migrate.log"; exit 1; }
php artisan tinker --execute="$(tail -n +2 e2e/donnees.php)" > "$LV_DOSSIER/donnees.log" 2>&1 || { cat "$LV_DOSSIER/donnees.log"; exit 1; }
grep -v "ok$" "$LV_DOSSIER/donnees.log" | head
php artisan tinker --execute='echo json_encode(array_intersect_key(config("logialvia"), array_flip(["routes", "role_permissions", "permissions", "modules"])));' > "$LV_DOSSIER/matrice.json" 2>/dev/null

pkill -f "artisan serve --port=$PORT" 2>/dev/null
PHP_CLI_SERVER_WORKERS=4 php artisan serve --port="$PORT" > "$LV_DOSSIER/serve.log" 2>&1 &
SERVEUR=$!
trap 'kill $SERVEUR 2>/dev/null; pkill -f "artisan serve --port=$PORT" 2>/dev/null' EXIT
for _ in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$PORT/up" && break; sleep 1; done

NODE_PATH="${NODE_PATH:-}:/opt/node-tools/node_modules" \
LV_URL="http://127.0.0.1:$PORT" LV_MDP="$MDP" LV_DB="$DB_DATABASE" LV_DOSSIER="$LV_DOSSIER" \
  node "${LV_SCRIPT:-e2e/executer.mjs}" "$@"
