#!/bin/sh
set -eu

echo "[TTG] Invoice Ninja (Octane) starting..."

ROLE="${LARAVEL_ROLE:-app}"

PERSIST_DIR="/home/container"
APP_DIR="${PERSIST_DIR}/app"
SRC_DIR="/opt/invoiceninja-ro"

echo "[TTG] Role: ${ROLE}"
echo "[TTG] APP_DIR=${APP_DIR}"
echo "[TTG] SRC_DIR=${SRC_DIR}"

# First boot: hydrate app into persistent storage
if [ ! -f "${APP_DIR}/artisan" ]; then
  echo "[TTG] First run: copying app -> ${APP_DIR}"
  mkdir -p "${APP_DIR}"
  cp -a "${SRC_DIR}/." "${APP_DIR}/"
fi

cd "${APP_DIR}"

# Ensure writable dirs Laravel/IN needs
mkdir -p storage bootstrap/cache
mkdir -p storage/app storage/framework/cache storage/framework/sessions storage/framework/views storage/logs
chmod -R 775 storage bootstrap/cache || true

# Create .env on first run (inside persistent app dir)
if [ ! -f .env ] && [ -f .env.example ]; then
  echo "[TTG] Creating .env from .env.example"
  cp .env.example .env
fi

# Optional: apply runtime vars into .env (safe)
if [ -f .env ] && [ "${APP_URL:-}" != "" ]; then
  grep -q '^APP_URL=' .env \
    && sed -i "s|^APP_URL=.*|APP_URL=${APP_URL}|g" .env \
    || echo "APP_URL=${APP_URL}" >> .env
fi

if [ -f .env ] && [ "${APP_KEY:-}" != "" ]; then
  grep -q '^APP_KEY=' .env \
    && sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|g" .env \
    || echo "APP_KEY=${APP_KEY}" >> .env
fi

# Sanity
if [ ! -f artisan ]; then
  echo "[TTG] FATAL: artisan missing in ${APP_DIR}"
  ls -la "${APP_DIR}" | head -n 50 || true
  exit 1
fi

case "${ROLE}" in
  app)
    echo "[TTG] Starting Octane (RoadRunner)..."

    if ! command -v rr >/dev/null 2>&1; then
      echo "[TTG] FATAL: RoadRunner binary (rr) not found in image."
      echo "[TTG] Fix: add rr to the image or switch to a non-Octane start method."
      exit 127
    fi

    exec php artisan octane:start \
      --server=roadrunner \
      --host=0.0.0.0 \
      --port="${PORT:-8000}"
    ;;
  worker)
    echo "[TTG] Starting queue worker..."
    exec php artisan queue:work --sleep=3 --tries=3 --timeout=90
    ;;
  scheduler)
    echo "[TTG] Starting scheduler..."
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
