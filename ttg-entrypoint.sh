#!/bin/sh
set -eu

echo "[TTG] Invoice Ninja (FPM) starting..."

APP_DIR="${APP_DIR:-/home/container/app}"
PORT="${PORT:-8800}"

echo "[TTG] APP_DIR: ${APP_DIR}"
echo "[TTG] PORT: ${PORT}"

# Writable paths in Pterodactyl
RUNTIME_DIR="/home/container/.runtime"
LOG_DIR="/home/container/.logs"
mkdir -p "$RUNTIME_DIR" "$LOG_DIR" /run/php /tmp

# ---- Nginx config ----
# Pterodactyl mounts /home/container, so templates inside it may not exist.
# Use existing /etc/nginx/nginx.conf shipped in the image. Just warn if missing.
NGINX_CONF="/etc/nginx/nginx.conf"
if [ ! -f "$NGINX_CONF" ]; then
  echo "[TTG] ERROR: Missing ${NGINX_CONF}"
  exit 1
fi

# ---- PHP-FPM logging override ----
# Force logs into writable location; do NOT write to /var/log
FPM_BIN="/usr/sbin/php-fpm8.2"
if [ ! -x "$FPM_BIN" ]; then
  FPM_BIN="/usr/sbin/php-fpm"
fi

FPM_INI_OVERRIDE="${RUNTIME_DIR}/zz-ttg-fpm.conf"
cat > "$FPM_INI_OVERRIDE" <<EOF
[global]
error_log = ${LOG_DIR}/php-fpm.log
log_level = notice

[www]
; Keep it simple: listen on 9000 inside container
listen = 9000
; Send worker output to main error log (debug help)
catch_workers_output = yes
EOF

echo "[TTG] Starting PHP-FPM with log at ${LOG_DIR}/php-fpm.log ..."
# -y uses main config, -c uses php.ini dir; we use -d for overrides and include our file
# Debian FPM supports --fpm-config, but simplest is include via -d? Not reliable.
# Instead, we drop our override into the pool config include directory by copying:
cp "$FPM_INI_OVERRIDE" /etc/php/8.2/fpm/pool.d/zz-ttg-runtime.conf 2>/dev/null || true

# Start FPM in daemon mode
$FPM_BIN -D

# ---- Start nginx ----
echo "[TTG] Starting nginx..."
exec nginx -g "daemon off;"
