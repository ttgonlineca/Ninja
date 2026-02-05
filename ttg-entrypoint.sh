#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/home/container/app}"
RUNTIME_DIR="${RUNTIME_DIR:-/home/container/.runtime}"
LOGS_DIR="${LOGS_DIR:-/home/container/.logs}"
PORT="${PORT:-8800}"

echo "[TTG] Invoice Ninja starting..."
echo "[TTG] PORT: ${PORT}"
echo "[TTG] RUNTIME: ${RUNTIME_DIR}"
echo "[TTG] LOGS: ${LOGS_DIR}"
echo "[TTG] APP_DIR: ${APP_DIR}"

# Writable dirs required for Pterodactyl
mkdir -p "${RUNTIME_DIR}" "${LOGS_DIR}"
mkdir -p "${RUNTIME_DIR}/nginx/client_body" "${RUNTIME_DIR}/nginx/proxy" "${RUNTIME_DIR}/nginx/fastcgi" "${RUNTIME_DIR}/nginx/uwsgi" "${RUNTIME_DIR}/nginx/scgi"

# Ensure ownership (Pterodactyl user is usually container/UID 999)
chown -R container:container "${RUNTIME_DIR}" "${LOGS_DIR}" || true

# Detect chromium (for PDF preview tooling if your app uses it)
if command -v chromium >/dev/null 2>&1; then
  echo "[TTG] Chromium detected: $(command -v chromium)"
elif command -v chromium-browser >/dev/null 2>&1; then
  echo "[TTG] Chromium detected: $(command -v chromium-browser)"
else
  echo "[TTG] Chromium not found (PDF preview may fail)"
fi

# Install nginx config from template (PORT env substitution)
if [ -f /etc/nginx/nginx.conf ]; then
  rm -f /etc/nginx/nginx.conf || true
fi

if [ -f /home/container/nginx.conf.template ]; then
  # Optional: allow template to live in /home/container for debugging
  envsubst '${PORT}' < /home/container/nginx.conf.template > /etc/nginx/nginx.conf
else
  envsubst '${PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
fi

# Ensure PHP-FPM pool config is in place (your Dockerfile should copy docker/www.conf to the right location)
# Common locations:
#   /etc/php/8.2/fpm/pool.d/www.conf (debian php)
#   /usr/local/etc/php-fpm.d/www.conf (php:* images)
# We won't overwrite here; you handle it in Dockerfile copy step.

# Find PHP-FPM binary
PHP_FPM_BIN=""
if command -v php-fpm8.2 >/dev/null 2>&1; then
  PHP_FPM_BIN="$(command -v php-fpm8.2)"
elif command -v php-fpm >/dev/null 2>&1; then
  PHP_FPM_BIN="$(command -v php-fpm)"
elif [ -x /usr/sbin/php-fpm8.2 ]; then
  PHP_FPM_BIN="/usr/sbin/php-fpm8.2"
fi

if [ -z "${PHP_FPM_BIN}" ]; then
  echo "[TTG] ERROR: php-fpm binary not found"
  exit 1
fi

echo "[TTG] Starting PHP-FPM (${PHP_FPM_BIN})..."
"${PHP_FPM_BIN}" -D

# Start nginx (non-daemon so Pterodactyl can supervise)
echo "[TTG] Starting nginx on port ${PORT}..."
nginx -g 'daemon off;' &
NGINX_PID=$!

# Graceful stop handling so “Stop/Restart” works (no kill needed)
shutdown() {
  echo "[TTG] Caught shutdown signal, stopping services..."
  # stop nginx
  if [ -n "${NGINX_PID:-}" ] && kill -0 "${NGINX_PID}" 2>/dev/null; then
    kill -TERM "${NGINX_PID}" 2>/dev/null || true
  fi

  # stop php-fpm
  # Try common pid locations
  if [ -f "${RUNTIME_DIR}/php-fpm.pid" ]; then
    kill -TERM "$(cat "${RUNTIME_DIR}/php-fpm.pid")" 2>/dev/null || true
  else
    pkill -TERM -f 'php-fpm' 2>/dev/null || true
  fi

  wait "${NGINX_PID}" 2>/dev/null || true
  echo "[TTG] Shutdown complete."
}
trap shutdown SIGTERM SIGINT

# Keep container alive tied to nginx
wait "${NGINX_PID}"
