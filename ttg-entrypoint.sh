#!/bin/sh
set -eu

echo "[TTG] Invoice Ninja (Octane) starting..."

ROLE="${LARAVEL_ROLE:-app}"

# Invoice Ninja Octane image runs from /app
APP_DIR="/app"

# Pterodactyl persistent storage
PERSIST_DIR="/home/container"
STORAGE_DIR="${PERSIST_DIR}/storage"

echo "[TTG] Role: ${ROLE}"
echo "[TTG] APP_DIR=${APP_DIR}"
echo "[TTG] Persistent storage=${STORAGE_DIR}"

# Ensure persistent storage exists
mkdir -p "${STORAGE_DIR}"

# Wire Laravel storage to persistent volume WITHOUT trying to delete read-only image files.
# /app is read-only in this environment, so removing /app/storage will fail.
# We only replace it if it's already a symlink; otherwise we just create/force the symlink path.
if [ -L "${APP_DIR}/storage" ]; then
  ln -sfn "${STORAGE_DIR}" "${APP_DIR}/storage"
else
  # If it's a real directory (from the image), we cannot remove it. Try to move it aside; ignore failure.
  if [ -e "${APP_DIR}/storage" ]; then
    echo "[TTG] Detected image storage dir at ${APP_DIR}/storage (read-only likely)."
    echo "[TTG] Attempting to move aside -> ${APP_DIR}/storage.image (safe if writable, ignored if not)..."
    mv "${APP_DIR}/storage" "${APP_DIR}/storage.image" 2>/dev/null || true
  fi

  # Create/force symlink. If storage couldn't be moved due to read-only, symlink will fail.
  # In that case we continue, but Laravel will use image storage and may not persist. Better than crashing.
  ln -sfn "${STORAGE_DIR}" "${APP_DIR}/storage" 2>/dev/null || true
fi

# Ensure required storage subdirs exist on persistent volume
mkdir -p "${STORAGE_DIR}/app" "${STORAGE_DIR}/framework" "${STORAGE_DIR}/logs"
chmod -R 775 "${STORAGE_DIR}" || true

cd "${APP_DIR}"

# Create .env on first run
if [ ! -f .env ] && [ -f .env.example ]; then
  echo "[TTG] Creating .env from example"
  cp .env.example .env
fi

# Sync env vars safely (only if .env exists)
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

# Final sanity check
if [ ! -f artisan ]; then
  echo "[TTG] FATAL: artisan not found in ${APP_DIR}"
  exit 1
fi

case "${ROLE}" in
  app)
    echo "[TTG] Starting Octane (FrankenPHP)..."
    exec php artisan octane:start \
      --server=frankenphp \
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
