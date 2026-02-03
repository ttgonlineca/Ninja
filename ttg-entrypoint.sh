#!/bin/sh
set -eu

echo "[TTG] Invoice Ninja (FPM) starting..."

APP_DIR="${APP_DIR:-/home/container/app}"
PORT="${PORT:-8800}"

echo "[TTG] APP_DIR: ${APP_DIR}"
echo "[TTG] PORT: ${PORT}"

# ---- Paths ----
TEMPLATE_IN_APP="${APP_DIR}/nginx.conf.template"
NGINX_CONF="/etc/nginx/nginx.conf"

# ---- Ensure runtime dirs exist ----
mkdir -p /run/php /tmp

# ---- Render nginx config ----
# Prefer template shipped with app (repo root), fallback to existing nginx.conf.
if [ -f "$TEMPLATE_IN_APP" ]; then
  # Replace common placeholders if present; safe if not present.
  sed \
    -e "s|__PORT__|${PORT}|g" \
    -e "s|{{PORT}}|${PORT}|g" \
    -e "s|\${PORT}|${PORT}|g" \
    "$TEMPLATE_IN_APP" > "$NGINX_CONF"
  echo "[TTG] Wrote nginx.conf from ${TEMPLATE_IN_APP}"
else
  echo "[TTG] WARN: nginx.conf.template not found at ${TEMPLATE_IN_APP}. Using existing ${NGINX_CONF}."
fi

# ---- Start PHP-FPM ----
# Debian php-fpm binary path
PHP_FPM_BIN="/usr/sbin/php-fpm8.2"
if [ ! -x "$PHP_FPM_BIN" ]; then
  PHP_FPM_BIN="/usr/sbin/php-fpm"
fi

echo "[TTG] Starting PHP-FPM..."
$PHP_FPM_BIN -D

# ---- Start nginx ----
echo "[TTG] Starting nginx..."
exec nginx -g "daemon off;"
