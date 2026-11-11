#!/usr/bin/env bash
# Essai de synchronisation poste <-> VRAI serveur Laravel (docs/logialvia/47h_PREUVE_VRAI_SERVEUR.md).
#
#   bash logialvia_app/outils/essai_vrai_serveur.sh [port] [-- arguments de flutter test]
#
# - base SQLite JETABLE neuve (migrations + seeders), jamais celle de l'exploitation ;
# - comptes admin1..admin150, caissier1, comptable1, animalier1 (mot de passe d'essai) ;
# - un module et des paramètres « décidés » côté serveur (essai des référentiels) ;
# - remise à zéro activée (essai « remise à zéro ») ;
# - lance php artisan serve, puis flutter test test/integration/serveur_reel_test.dart.
# Variables : FLUTTER (chemin de flutter), TZ (rejouer sous un autre fuseau),
#             LV_DOSSIER (dossier de la base jetable, /tmp/lv par défaut).
set -u
PORT="${1:-8765}"
[ "$#" -gt 0 ] && shift
[ "${1:-}" = "--" ] && shift

RACINE="$(cd "$(dirname "$0")/../.." && pwd)"
LV_DOSSIER="${LV_DOSSIER:-/tmp/lv}"
FLUTTER="${FLUTTER:-flutter}"
MDP='EssaiPoste-2026!'
mkdir -p "$LV_DOSSIER"

# Base : sqlite (defaut, fichier jetable) ou mysql / mariadb (47r_). Pour MySQL/MariaDB :
#   LV_BASE=mariadb LV_MYSQL_USER=lv LV_MYSQL_PASSWORD=lv bash logialvia_app/outils/essai_vrai_serveur.sh
# (LV_MYSQL_HOST=127.0.0.1, LV_MYSQL_PORT=3306, LV_MYSQL_BASE=lv_essai ; la base est RECREEE : jamais
# celle de l'exploitation). Le serveur doit deja tourner ; le client `mysql` doit etre installe.
LV_BASE="${LV_BASE:-sqlite}"
export ADMIN_INITIAL_PASSWORD="$MDP" REMISE_A_ZERO_ACTIVEE=true BCRYPT_ROUNDS=4
if [ "$LV_BASE" = "sqlite" ]; then
  export DB_CONNECTION=sqlite DB_DATABASE="$LV_DOSSIER/essai.sqlite"
  rm -f "$DB_DATABASE" && touch "$DB_DATABASE"
  BASE_ESSAI="$DB_DATABASE"
else
  export DB_CONNECTION="$LV_BASE" DB_HOST="${LV_MYSQL_HOST:-127.0.0.1}" DB_PORT="${LV_MYSQL_PORT:-3306}" \
    DB_DATABASE="${LV_MYSQL_BASE:-lv_essai}" DB_USERNAME="${LV_MYSQL_USER:-root}" DB_PASSWORD="${LV_MYSQL_PASSWORD:-}"
  MYSQL_CLI=(mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USERNAME")
  [ -n "$DB_PASSWORD" ] && MYSQL_CLI+=("-p$DB_PASSWORD")
  "${MYSQL_CLI[@]}" -e "DROP DATABASE IF EXISTS \`$DB_DATABASE\`; CREATE DATABASE \`$DB_DATABASE\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
    || { echo "Impossible de recreer la base $DB_DATABASE sur $DB_HOST:$DB_PORT."; exit 1; }
  BASE_ESSAI="mysql"
fi

cd "$RACINE/logialvia_laravel" || exit 1
# Poste neuf ou CI : ni .env ni APP_KEY -> clef jetable, sinon MissingAppKeyException.
if [ -z "${APP_KEY:-}" ] && [ ! -f .env ]; then
  APP_KEY="$(php artisan key:generate --show)" || exit 1
  export APP_KEY
fi
php artisan migrate:fresh --seed --force > "$LV_DOSSIER/migrate.log" 2>&1 \
  || { cat "$LV_DOSSIER/migrate.log"; exit 1; }

cat > "$LV_DOSSIER/comptes.php" <<'PHP'
foreach (range(1, 150) as $i) { $u = App\Models\User::query()->create(['name' => 'Admin '.$i, 'username' => 'admin'.$i, 'password' => 'EssaiPoste-2026!', 'is_active' => true, 'must_change_password' => false]); $u->assignRole('admin'); }
foreach (['caissier' => 'caissier', 'comptable' => 'comptable', 'animalier' => 'animalier'] as $n => $r) { $u = App\Models\User::query()->create(['name' => ucfirst($n), 'username' => $n.'1', 'password' => 'EssaiPoste-2026!', 'is_active' => true, 'must_change_password' => false]); $u->assignRole($r); }
App\Models\ModuleActif::where('module_id', 'ovins')->update(['is_actif' => true]);
App\Models\ParametresEntreprise::query()->update(['raison_sociale' => 'ALLMANY SARL (web)', 'prefixe_bac' => 'BC']);
PHP
php artisan tinker --execute="$(cat "$LV_DOSSIER/comptes.php")" > "$LV_DOSSIER/comptes.log" 2>&1 \
  || { cat "$LV_DOSSIER/comptes.log"; exit 1; }

pkill -f "artisan serve --port=$PORT" 2>/dev/null
PHP_CLI_SERVER_WORKERS=4 php artisan serve --port="$PORT" > "$LV_DOSSIER/serve.log" 2>&1 &
SERVEUR=$!
trap 'kill $SERVEUR 2>/dev/null; pkill -f "artisan serve --port=$PORT" 2>/dev/null' EXIT
for _ in $(seq 1 30); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/up" && break
  sleep 1
done

# --- Reseau reel (47r_) : ESSAI_RESEAU=1 lance, devant le MEME serveur, le mandataire de test
# (outils/mandataire_reseau.py : 413, coupures, lenteurs, 5xx, redirection, TLS auto-signe /
# autorite maison / expire / mauvais nom) et un second serveur a post_max_size=3K (vrai 413 PHP),
# puis test/integration/reseau_reel_test.dart au lieu de l'essai complet.
if [ "${ESSAI_RESEAU:-0}" = "1" ]; then
  PM=$((PORT + 10)); CERTS="$LV_DOSSIER/certs"; PETIT=$((PORT + 1))
  python3 "$RACINE/logialvia_app/outils/mandataire_reseau.py" --generer-seulement "$CERTS" > /dev/null \
    || { echo "openssl indisponible : certificats d'essai non generes."; exit 1; }
  PIDS=()
  python3 "$RACINE/logialvia_app/outils/mandataire_reseau.py" --amont "http://127.0.0.1:$PORT" \
    --port "$PM" --controle $((PM + 1)) > "$LV_DOSSIER/mandataire.log" 2>&1 &
  PIDS+=($!)
  TLS=""
  i=2
  for c in autosigne expire mauvais_nom valide; do
    python3 "$RACINE/logialvia_app/outils/mandataire_reseau.py" --amont "http://127.0.0.1:$PORT" \
      --port $((PM + i)) --controle $((PM + 20 + i)) --tls "$CERTS" --certificat "$c" \
      > "$LV_DOSSIER/mandataire_$c.log" 2>&1 &
    PIDS+=($!)
    TLS="$TLS$c=$((PM + i)),"
    i=$((i + 1))
  done
  (cd public && PHP_CLI_SERVER_WORKERS=2 exec php -d post_max_size=3K \
    -S "127.0.0.1:$PETIT" ../vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php \
    > "$LV_DOSSIER/petit.log" 2>&1) &
  PIDS+=($!)
  trap 'kill $SERVEUR "${PIDS[@]}" 2>/dev/null; pkill -f "artisan serve --port=$PORT" 2>/dev/null; pkill -f "S 127.0.0.1:$PETIT" 2>/dev/null' EXIT
  for _ in $(seq 1 30); do
    curl -s -o /dev/null "http://127.0.0.1:$((PM + 1))/sante" && curl -s -o /dev/null "http://127.0.0.1:$PETIT/up" && break
    sleep 1
  done
  cd "$RACINE/logialvia_app" || exit 1
  LOGIALVIA_MANDATAIRE="127.0.0.1:$PM" LOGIALVIA_MANDATAIRE_CTL=$((PM + 1)) LOGIALVIA_CERTS="$CERTS" \
    LOGIALVIA_TLS="${TLS%,}" LOGIALVIA_SERVEUR_PETIT="http://127.0.0.1:$PETIT" LOGIALVIA_MDP="$MDP" \
    "$FLUTTER" test test/integration/reseau_reel_test.dart "$@"
  exit $?
fi

cd "$RACINE/logialvia_app" || exit 1
LOGIALVIA_SERVEUR="http://127.0.0.1:$PORT" LOGIALVIA_MDP="$MDP" \
  LOGIALVIA_LARAVEL="$RACINE/logialvia_laravel" LOGIALVIA_DB="$BASE_ESSAI" \
  "$FLUTTER" test test/integration/serveur_reel_test.dart "$@"
