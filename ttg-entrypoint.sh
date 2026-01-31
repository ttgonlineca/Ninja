#!/bin/sh
set -eu

echo "[TTG] Invoice Ninja (Octane) starting..."

ROLE="${LARAVEL_ROLE:-app}"

# Read-only app baked into the image
IMAGE_APP_DIR="${IMAGE_APP_DIR:-/app}"

# Pterodactyl writable persistent dir
PERSIST_DIR="${PERSIST_DIR:-/home/container}"
APP_DIR="${APP_DIR:-${PERSIST_DIR}/app}"

echo "[TTG] Role: ${ROLE}"
echo "[TTG] Using APP_DIR=${APP_DIR}"
echo "[TTG] Image source=${IMAGE_APP_DIR}"

mkdir -p "${PERSIST_DIR}"

# First run: copy app into writable storage
if [ ! -f "${APP_DIR}/artisan" ]; then
  echo "[TTG] First run detected: copying app into ${APP_DIR}..."
  mkdir -p "${APP_DIR}"
  cp -a "${IMAGE_APP_DIR}/." "${APP_DIR}/"
fi

cd "${APP_DIR}"

mkdir -p storage bootstrap/cache
chmod -R 775 storage bootstrap/cache || true

# Make .env if missing
if [ ! -f .env ] && [ -f .env.example ]; then
  cp .env.example .env
fi

# If you pass APP_URL / APP_KEY as env vars, keep .env synced
if [ "${APP_URL:-}" != "" ]; then
  grep -q '^APP_URL=' .env && sed -i "s|^APP_URL=.*|APP_URL=${APP_URL}|g" .env || echo "APP_URL=${APP_URL}" >> .env
fi
if [ "${APP_KEY:-}" != "" ]; then
  grep -q '^APP_KEY=' .env && sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|g" .env || echo "APP_KEY=${APP_KEY}" >> .env
fi

case "${ROLE}" in
  app)
    echo "[TTG] Starting Octane (FrankenPHP)..."
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
