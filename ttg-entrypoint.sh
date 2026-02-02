#!/usr/bin/env bash
set -euo pipefail

echo "[TTG] Invoice Ninja (FPM) starting..."
echo "[TTG] APP_DIR: /home/container/app"

APP_DIR="/home/container/app"
SRC_DIR="/opt/invoiceninja-ro"

# Pterodactyl usually injects SERVER_PORT; fall back to PORT; then default
PORT="${SERVER_PORT:-${PORT:-8800}}"
echo "[TTG] PORT: ${PORT}"

mkdir -p /home/container/nginx

# Copy app on first run
if [ ! -f "${APP_DIR}/artisan" ]; then
  echo "[TTG] First run: copying app into ${APP_DIR}"
  mkdir -p "${APP_DIR}"
  cp -a "${SRC_DIR}/." "${APP_DIR}/"
fi

# Ensure required writable dirs
mkdir -p "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache"
chmod -R 777 "${APP_DIR}/storage" "${APP_DIR}/bootstrap/cache" || true

# Ensure .env exists
if [ ! -f "${APP_DIR}/.env" ]; then
  if [ -f "${APP_DIR}/.env.example" ]; then
    cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
  else
    touch "${APP_DIR}/.env"
  fi
fi

# If Ptero provides APP_KEY, enforce it into .env
if [ -n "${APP_KEY:-}" ]; then
  if grep -q '^APP_KEY=' "${APP_DIR}/.env"; then
    sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|" "${APP_DIR}/.env"
  else
    echo "APP_KEY=${APP_KEY}" >> "${APP_DIR}/.env"
  fi
fi

# IMPORTANT: Pterodactyl runtime env should win
# (prevents old .env values overriding panel variables)
export DB_HOST="${DB_HOST:-}"
export DB_PORT="${DB_PORT:-}"
export DB_DATABASE="${DB_DATABASE:-}"
export DB_USERNAME="${DB_USERNAME:-}"
export DB_PASSWORD="${DB_PASSWORD:-}"
export REDIS_HOST="${REDIS_HOST:-}"
export REDIS_PORT="${REDIS_PORT:-}"
export CACHE_DRIVER="${CACHE_DRIVER:-}"
export SESSION_DRIVER="${SESSION_DRIVER:-}"
export QUEUE_CONNECTION="${QUEUE_CONNECTION:-}"

# Render nginx config
env PORT="${PORT}" envsubst < /opt/ttg/nginx.conf.template > /home/container/nginx/nginx.conf
echo "[TTG] Rendered nginx config: /home/container/nginx/nginx.conf"

# Point nginx to our rendered config
# Use -c to load our config directly, avoid writing into /etc (read-only in Ptero sometimes)
export NGINX_CONF="/home/container/nginx/nginx.conf"
sed -i 's|command=/usr/sbin/nginx -g "daemon off;"|command=/usr/sbin/nginx -c /home/container/nginx/nginx.conf -g "daemon off;"|' \
  /etc/supervisor/supervisord.conf || true

echo "[TTG] Starting Supervisor"
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
