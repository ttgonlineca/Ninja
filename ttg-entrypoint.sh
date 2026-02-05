#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8800}"
APP_DIR="${APP_DIR:-/home/container/app}"
RUNTIME="/home/container/.runtime"
LOGS="/home/container/.logs"

mkdir -p "$RUNTIME/nginx/body" "$RUNTIME/nginx/proxy" "$RUNTIME/nginx/fastcgi" "$RUNTIME/nginx/uwsgi" "$RUNTIME/nginx/scgi" "$LOGS"

echo "[TTG] Invoice Ninja starting..."
echo "[TTG] PORT: $PORT"
echo "[TTG] APP_DIR: $APP_DIR"
echo "[TTG] RUNTIME: $RUNTIME"
echo "[TTG] LOGS: $LOGS"

# ---- Chromium exports (covers most PDF libs) ----
if command -v chromium >/dev/null 2>&1; then
  export CHROMIUM_PATH="/usr/bin/chromium"
  export PUPPETEER_EXECUTABLE_PATH="/usr/bin/chromium"
  export CHROME_PATH="/usr/bin/chromium"
  echo "[TTG] Chromium detected: $CHROMIUM_PATH"
fi

# ---- External Redis: prefer explicit REDIS_HOST, else auto-detect Docker gateway ----
if [[ -z "${REDIS_HOST:-}" ]]; then
  GW="$(ip route | awk '/default/ {print $3; exit}' || true)"
  if [[ -n "$GW" ]]; then
    export REDIS_HOST="$GW"
    echo "[TTG] REDIS_HOST not set; using gateway: $REDIS_HOST"
  fi
fi

# ---- Render nginx config with PORT ----
sed "s/\${PORT}/$PORT/g" /etc/nginx/nginx.conf.template > /home/container/.runtime/nginx.conf

# ---- Make sure we’re in the app ----
cd "$APP_DIR"

# ---- Clear cached config so env edits actually take effect ----
# (Laravel will happily keep stale cached config forever otherwise)
if [[ -f artisan ]]; then
  php artisan config:clear >/dev/null 2>&1 || true
  php artisan cache:clear  >/dev/null 2>&1 || true
  php artisan route:clear  >/dev/null 2>&1 || true
  php artisan view:clear   >/dev/null 2>&1 || true
fi

# ---- Graceful shutdown handler (fixes “stop/restart doesn’t work”) ----
shutdown() {
  echo "[TTG] Caught stop signal, shutting down..."
  nginx -c /home/container/.runtime/nginx.conf -s quit >/dev/null 2>&1 || true
  if [[ -n "${PHP_FPM_PID:-}" ]]; then
    kill -TERM "$PHP_FPM_PID" >/dev/null 2>&1 || true
  fi
  wait || true
  echo "[TTG] Shutdown complete."
  exit 0
}
trap shutdown SIGTERM SIGINT

# ---- Start PHP-FPM in foreground (we background it so nginx can also run) ----
PHPFPM_BIN="/usr/sbin/php-fpm8.2"
echo "[TTG] Starting PHP-FPM ($PHPFPM_BIN)..."
$PHPFPM_BIN -F &
PHP_FPM_PID=$!

# ---- Start nginx in foreground ----
echo "[TTG] Starting nginx on port $PORT..."
nginx -c /home/container/.runtime/nginx.conf -g "daemon off;" &
NGINX_PID=$!

# Wait for either to exit
wait -n "$PHP_FPM_PID" "$NGINX_PID"
echo "[TTG] A process exited, shutting down..."
shutdown
