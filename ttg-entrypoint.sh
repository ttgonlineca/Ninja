#!/bin/sh
set -eu

echo "[TTG] Invoice Ninja (Octane) starting..."

ROLE="${LARAVEL_ROLE:-app}"

APP_DIR="/app"

PERSIST_DIR="/home/container"
ENV_FILE="${PERSIST_DIR}/.env"
STORAGE_DIR="${PERSIST_DIR}/storage"

echo "[TTG] Role: ${ROLE}"
echo "[TTG] APP_DIR=${APP_DIR}"
echo "[TTG] Env file=${ENV_FILE}"
echo "[TTG] Persistent storage=${STORAGE_DIR}"

# Ensure persistent dirs exist
mkdir -p "${PERSIST_DIR}" \
  "${STORAGE_DIR}/app" \
  "${STORAGE_DIR}/framework/cache" \
  "${STORAGE_DIR}/framework/sessions" \
  "${STORAGE_DIR}/framework/views" \
  "${STORAGE_DIR}/logs"

chmod -R 775 "${STORAGE_DIR}" || true

cd "${APP_DIR}"

# Create persistent .env on first run
if [ ! -f "${ENV_FILE}" ] && [ -f .env.example ]; then
  echo "[TTG] Creating persistent .env from /app/.env.example -> ${ENV_FILE}"
  cp .env.example "${ENV_FILE}"
fi

# Load persistent env early (so we can override logging + paths)
if [ -f "${ENV_FILE}" ]; then
  set -a
  . "${ENV_FILE}"
  set +a
else
  echo "[TTG] WARNING: ${ENV_FILE} not found; continuing with runtime env only."
fi

# Force log + pid paths away from /app/storage (read-only in Pterodactyl)
# This avoids crashing even if /app/storage can't be redirected.
export LOG_CHANNEL="${LOG_CHANNEL:-stderr}"
export LOG_STACK="${LOG_STACK:-stderr}"
export LOG_LEVEL="${LOG_LEVEL:-debug}"
export OCTANE_SERVER="${OCTANE_SERVER:-frankenphp}"
export OCTANE_HTTPS="${OCTANE_HTTPS:-false}"

# Some apps write PID files under storage; keep them in /home/container
export OCTANE_PID_PATH="${OCTANE_PID_PATH:-${STORAGE_DIR}/octane.pid}"
export OCTANE_STATE_FILE="${OCTANE_STATE_FILE:-${STORAGE_DIR}/octane.state}"

# Also ensure Laravel uses a writable cache path where possible
export CACHE_DRIVER="${CACHE_DRIVER:-file}"
export SESSION_DRIVER="${SESSION_DRIVER:-file}"

# Apply APP_URL / APP_KEY into persistent .env if provided as runtime env
if [ -f "${ENV_FILE}" ] && [ "${APP_URL:-}" != "" ]; then
  grep -q '^APP_URL=' "${ENV_FILE}" \
    && sed -i "s|^APP_URL=.*|APP_URL=${APP_URL}|g" "${ENV_FILE}" \
    || echo "APP_URL=${APP_URL}" >> "${ENV_FILE}"
fi
if [ -f "${ENV_FILE}" ] && [ "${APP_KEY:-}" != "" ]; then
  grep -q '^APP_KEY=' "${ENV_FILE}" \
    && sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|g" "${ENV_FILE}" \
    || echo "APP_KEY=${APP_KEY}" >> "${ENV_FILE}"
fi

# Sanity check
if [ ! -f artisan ]; then
  echo "[TTG] FATAL: artisan not found in ${APP_DIR}"
  exit 1
fi

case "${ROLE}" in
  app)
    echo "[TTG] Starting Octane (FrankenPHP) with env from ${ENV_FILE}..."
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
