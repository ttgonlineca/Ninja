#!/bin/sh
set -eu

echo "[TTG] Invoice Ninja (Octane) starting..."

ROLE="${LARAVEL_ROLE:-app}"

# Read-only source baked into the image
IMAGE_APP_DIR="${IMAGE_APP_DIR:-/var/www/html}"

# Writable persistent app dir for Pterodactyl
PERSIST_DIR="${PERSIST_DIR:-/home/container}"
APP_DIR="${APP_DIR:-${PERSIST_DIR}/app}"

echo "[TTG] Role: ${ROLE}"
echo "[TTG] Using APP_DIR=${APP_DIR}"
echo "[TTG] Image source=${IMAGE_APP_DIR}"

# Ensure persistent base exists
mkdir -p "${PERSIST_DIR}"

# First-run: copy app from image into writable persistent storage
if [ ! -f "${APP_DIR}/artisan" ]; then
  echo "[TTG] First run detected: copying app into ${APP_DIR}..."
  mkdir -p "${APP_DIR}"
  # Copy everything (preserve perms). Busybox cp -a works in most images.
  cp -a "${IMAGE_APP_DIR}/." "${APP_DIR}/"
fi

cd "${APP_DIR}"

# Ensure writable Laravel dirs
mkdir -p storage bootstrap/cache
chmod -R 775 storage bootstrap/cache || true

# Write .env if missing (optional — remove if you manage env differently)
if [ ! -f .env ] && [ -f .env.example ]; then
  echo "[TTG] .env missing; creating from .env.example"
  cp .env.example .env
fi

# If APP_KEY is provided via env, keep .env in sync (optional)
if [ "${APP_KEY:-}" != "" ] && [ "${APP_KEY}" != "base64:REPLACE_ME" ]; then
  if grep -q '^APP_KEY=' .env 2>/dev/null; then
    sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|g" .env
  else
    echo "APP_KEY=${APP_KEY}" >> .env
  fi
fi

# Run basic artisan prep (safe to no-op if already done)
php artisan config:clear || true
php artisan config:cache || true
php artisan route:cache || true

# Start by role
case "${ROLE}" in
  app)
    echo "[TTG] Starting Octane (FrankenPHP) web..."
    # Adjust the command below to your actual Octane/FrankenPHP start
    # Examples:
    #   php artisan octane:start --server=frankenphp --host=0.0.0.0 --port=${PORT:-8000}
    # or if you have a custom runner:
    #   /usr/local/bin/start-octane.sh
    exec php artisan octane:start --server=frankenphp --host=0.0.0.0 --port="${PORT:-8000}"
    ;;
  worker)
    echo "[TTG] Starting queue worker..."
    exec php artisan queue:work --sleep=3 --tries=3 --timeout=90
    ;;
  scheduler)
    echo "[TTG] Starting scheduler loop..."
    while true; do
      php artisan schedule:run --verbose --no-interaction || true
      sleep 60
    done
    ;;
  *)
    echo "[TTG] Unknown LARAVEL_ROLE=${ROLE}"
    exit 2
    ;;
esac
