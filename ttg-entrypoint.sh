#!/usr/bin/env bash
set -euo pipefail

PORT="${SERVER_PORT:-8800}"
APP_DIR="${APP_DIR:-/home/container/app}"
RUNTIME_DIR="${RUNTIME_DIR:-/home/container/.runtime}"
LOG_DIR="${LOG_DIR:-/home/container/.logs}"

echo "[TTG] Invoice Ninja starting..."
echo "[TTG] PORT: $PORT"
echo "[TTG] RUNTIME: $RUNTIME_DIR"
echo "[TTG] LOGS: $LOG_DIR"
echo "[TTG] APP_DIR: $APP_DIR"

mkdir -p "$RUNTIME_DIR" "$LOG_DIR" "$RUNTIME_DIR/nginx" "$RUNTIME_DIR/tmp"

# ---- Chromium detection ----
CHROMIUM_BIN=""
for p in /usr/bin/chromium /usr/bin/chromium-browser /usr/bin/google-chrome; do
  if [[ -x "$p" ]]; then CHROMIUM_BIN="$p"; break; fi
done
if [[ -n "$CHROMIUM_BIN" ]]; then
  echo "[TTG] Chromium detected: $CHROMIUM_BIN"
  export CHROME_PATH="$CHROMIUM_BIN"
  export CHROMIUM_PATH="$CHROMIUM_BIN"
  export PUPPETEER_EXECUTABLE_PATH="$CHROMIUM_BIN"
fi

# ---- Find nginx template ----
TEMPLATE=""
for t in \
  /home/container/nginx.conf.template \
  "$APP_DIR/nginx.conf.template" \
  /opt/ttg/templates/nginx.conf.template
do
  if [[ -f "$t" ]]; then TEMPLATE="$t"; break; fi
done

if [[ -z "$TEMPLATE" ]]; then
  echo "[TTG] ERROR: nginx.conf.template not found (expected /home/container/nginx.conf.template or $APP_DIR/nginx.conf.template or /opt/ttg/templates/nginx.conf.template)"
  exit 1
fi

echo "[TTG] Using nginx.conf.template from: $TEMPLATE"

# ---- Build nginx.conf into runtime ----
NGINX_CONF="$RUNTIME_DIR/nginx.conf"
sed \
  -e "s/{{PORT}}/${PORT}/g" \
  -e "s/\${PORT}/${PORT}/g" \
  "$TEMPLATE" > "$NGINX_CONF"

# Ensure nginx temp paths exist (template should point here)
mkdir -p \
  "$RUNTIME_DIR/nginx/client_body" \
  "$RUNTIME_DIR/nginx/proxy" \
  "$RUNTIME_DIR/nginx/fastcgi" \
  "$RUNTIME_DIR/nginx/uwsgi" \
  "$RUNTIME_DIR/nginx/scgi"

# ---- PHP-FPM binary ----
PHP_FPM_BIN="/usr/sbin/php-fpm8.2"
if [[ ! -x "$PHP_FPM_BIN" ]]; then
  PHP_FPM_BIN="$(command -v php-fpm8.2 || true)"
fi
if [[ -z "$PHP_FPM_BIN" || ! -x "$PHP_FPM_BIN" ]]; then
  echo "[TTG] ERROR: php-fpm8.2 not found"
  exit 1
fi

# ---- PHP-FPM runtime config (NO unix socket) ----
PHP_FPM_CONF="$RUNTIME_DIR/php-fpm.conf"
PHP_FPM_POOL="$RUNTIME_DIR/php-fpm.pool.conf"

cat > "$PHP_FPM_CONF" <<EOF
[global]
daemonize = yes
error_log = ${LOG_DIR}/php-fpm.error.log
pid = ${RUNTIME_DIR}/php-fpm.pid
include=${PHP_FPM_POOL}
EOF

# Use repo pool file if present, else fallback
if [[ -f "$APP_DIR/docker/www.conf" ]]; then
  cp "$APP_DIR/docker/www.conf" "$PHP_FPM_POOL"
else
  cat > "$PHP_FPM_POOL" <<EOF
[www]
listen = 127.0.0.1:9000
pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 6
catch_workers_output = yes
access.log = ${LOG_DIR}/php-fpm.access.log
slowlog = ${LOG_DIR}/php-fpm.slow.log
request_slowlog_timeout = 10s
clear_env = no
EOF
fi

echo "[TTG] Starting PHP-FPM ($PHP_FPM_BIN)..."
"$PHP_FPM_BIN" -y "$PHP_FPM_CONF"

echo "[TTG] Starting nginx on port $PORT..."
exec nginx -c "$NGINX_CONF" -g "pid ${RUNTIME_DIR}/nginx.pid; error_log ${LOG_DIR}/nginx.error.log;"
