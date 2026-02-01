#!/bin/bash
set -euo pipefail

ROLE="${LARAVEL_ROLE:-web}"

PERSIST_DIR="/home/container"
APP_DIR="${PERSIST_DIR}/app"
SRC_DIR="/opt/invoiceninja-ro"
PORT="${PORT:-8000}"

echo "[TTG] Invoice Ninja (FPM) starting..."
echo "[TTG] Role: ${ROLE}"
echo "[TTG] APP_DIR: ${APP_DIR}"
echo "[TTG] SRC_DIR: ${SRC_DIR}"
echo "[TTG] PORT: ${PORT}"

# 1) Hydrate app into persistent storage (first run only)
if [[ ! -f "${APP_DIR}/artisan" ]]; then
  echo "[TTG] First run: copying app to ${APP_DIR}..."
  mkdir -p "${APP_DIR}"
  cp -a "${SRC_DIR}/." "${APP_DIR}/"
fi

cd "${APP_DIR}"

# 2) Ensure writable dirs
mkdir -p storage bootstrap/cache
mkdir -p storage/app storage/framework/{cache,sessions,views} storage/logs
chmod -R 775 storage bootstrap/cache || true

# 3) Ensure .env exists (in persistent app dir, writable)
if [[ ! -f .env && -f .env.example ]]; then
  echo "[TTG] Creating .env from .env.example"
  cp .env.example .env
fi

# 4) Apply a few key runtime vars if provided (safe / optional)
apply_kv () {
  local key="$1"
  local val="${!key:-}"
  [[ -z "$val" ]] && return 0
  if grep -q "^${key}=" .env 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|g" .env
  else
    echo "${key}=${val}" >> .env
  fi
}

# Common ones you likely set via egg vars
apply_kv APP_URL
apply_kv APP_KEY
apply_kv DB_CONNECTION
apply_kv DB_HOST
apply_kv DB_PORT
apply_kv DB_DATABASE
apply_kv DB_USERNAME
apply_kv DB_PASSWORD

# Logging: container-friendly by default
apply_kv LOG_CHANNEL
apply_kv LOG_LEVEL

# 5) Render nginx config from template using PORT
# Nginx does NOT expand env vars inside config, so we generate a real file.
export PORT
envsubst '${PORT}' < /etc/nginx/templates/default.conf.template > /tmp/nginx.conf

# 6) Pick role
case "${ROLE}" in
  web)
    echo "[TTG] Starting web stack (nginx + php-fpm)..."
    # php-fpm expects to run as current user; nginx will run in foreground via supervisor
    export NGINX_CONF="/tmp/nginx.conf"
    exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
    ;;
  worker)
    echo "[TTG] Starting queue worker..."
    exec php artisan queue:work --sleep=3 --tries=3 --timeout=120
    ;;
  scheduler)
    echo "[TTG] Starting scheduler loop..."
    while true; do
      php artisan schedule:run --no-interaction || true
      sleep 60
    done
    ;;
  *)
    echo "[TTG] Unknown LARAVEL_ROLE=${ROLE}"
    exit 2
    ;;
esac
