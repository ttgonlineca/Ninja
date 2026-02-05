#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${RUNTIME:-/home/container/.runtime}"
LOGS="${LOGS:-/home/container/.logs}"
APP_DIR="${APP_DIR:-/home/container/app}"
PORT="${PORT:-8800}"

NGINX_BIN="${NGINX_BIN:-/usr/sbin/nginx}"
PHP_FPM_BIN="${PHP_FPM_BIN:-/usr/sbin/php-fpm8.2}"

echo "[TTG] Invoice Ninja starting..."
echo "[TTG] PORT: ${PORT}"
echo "[TTG] RUNTIME: ${RUNTIME}"
echo "[TTG] LOGS: ${LOGS}"
echo "[TTG] APP_DIR: ${APP_DIR}"

# Must be writable volume paths in Pterodactyl
mkdir -p "${RUNTIME}/nginx" "${RUNTIME}/tmp" "${RUNTIME}/sessions" "${LOGS}"

# Chromium (optional)
if command -v chromium >/dev/null 2>&1; then
  echo "[TTG] Chromium detected: $(command -v chromium)"
  export CHROME_BIN="$(command -v chromium)"
elif command -v chromium-browser >/dev/null 2>&1; then
  echo "[TTG] Chromium detected: $(command -v chromium-browser)"
  export CHROME_BIN="$(command -v chromium-browser)"
fi

# Render nginx.conf into runtime (NEVER touch /etc at runtime)
if [[ -f "/home/container/nginx.conf.template" ]]; then
  export PORT RUNTIME LOGS APP_DIR
  envsubst '${PORT} ${RUNTIME} ${LOGS} ${APP_DIR}' \
    < "/home/container/nginx.conf.template" \
    > "${RUNTIME}/nginx.conf"
elif [[ -f "${APP_DIR}/nginx.conf.template" ]]; then
  export PORT RUNTIME LOGS APP_DIR
  envsubst '${PORT} ${RUNTIME} ${LOGS} ${APP_DIR}' \
    < "${APP_DIR}/nginx.conf.template" \
    > "${RUNTIME}/nginx.conf"
else
  echo "[TTG] ERROR: nginx.conf.template not found (expected /home/container/nginx.conf.template or ${APP_DIR}/nginx.conf.template)"
  exit 1
fi

# Render php-fpm.conf into runtime (NEVER touch /etc at runtime)
if [[ -f "/home/container/docker/php-fpm.conf" ]]; then
  export RUNTIME LOGS
  envsubst '${RUNTIME} ${LOGS}' \
    < "/home/container/docker/php-fpm.conf" \
    > "${RUNTIME}/php-fpm.conf"
else
  echo "[TTG] ERROR: /home/container/docker/php-fpm.conf not found"
  exit 1
fi

# Render pool config into runtime
if [[ -f "/home/container/docker/www.conf" ]]; then
  export RUNTIME LOGS
  envsubst '${RUNTIME} ${LOGS}' \
    < "/home/container/docker/www.conf" \
    > "${RUNTIME}/www.conf"
else
  echo "[TTG] ERROR: /home/container/docker/www.conf not found"
  exit 1
fi

# Make sure FPM includes our pool
# (php-fpm.conf will include ${RUNTIME}/www.conf)
# Also ensure app exists
if [[ ! -d "${APP_DIR}" ]]; then
  echo "[TTG] ERROR: APP_DIR does not exist: ${APP_DIR}"
  exit 1
fi

# Clean stale pid/socket files if any
rm -f "${RUNTIME}/nginx.pid" "${RUNTIME}/php-fpm.pid" "${RUNTIME}/php-fpm.sock" 2>/dev/null || true

# Graceful shutdown for Pterodactyl stop/restart
terminate() {
  echo "[TTG] Caught stop signal, shutting down..."

  # Stop nginx
  if [[ -f "${RUNTIME}/nginx.pid" ]]; then
    "${NGINX_BIN}" -c "${RUNTIME}/nginx.conf" -s quit 2>/dev/null || true
  fi

  # Stop php-fpm
  if [[ -f "${RUNTIME}/php-fpm.pid" ]]; then
    kill -TERM "$(cat "${RUNTIME}/php-fpm.pid")" 2>/dev/null || true
  fi

  # Give them a second then exit
  sleep 1
  exit 0
}
trap terminate SIGTERM SIGINT

echo "[TTG] Starting PHP-FPM (${PHP_FPM_BIN})..."
"${PHP_FPM_BIN}" -y "${RUNTIME}/php-fpm.conf" --fpm-config "${RUNTIME}/php-fpm.conf" -D

echo "[TTG] Starting nginx on port ${PORT}..."
# Run nginx in foreground so container stays alive and stop works
exec "${NGINX_BIN}" -c "${RUNTIME}/nginx.conf" -g "daemon off;"
