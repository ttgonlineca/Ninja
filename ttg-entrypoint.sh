#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/home/container/app}"
RUNTIME_DIR="${RUNTIME_DIR:-/home/container/.runtime}"
LOG_DIR="${LOG_DIR:-/home/container/.logs}"

ROLE="${ROLE:-${TTG_ROLE:-web}}"
PORT="${SERVER_PORT:-${PORT:-8000}}"

echo "[TTG] Invoice Ninja starting..."
echo "[TTG] PORT: ${PORT}"
echo "[TTG] ROLE: ${ROLE}"
echo "[TTG] RUNTIME: ${RUNTIME_DIR}"
echo "[TTG] LOGS: ${LOG_DIR}"
echo "[TTG] APP_DIR: ${APP_DIR}"

mkdir -p "${RUNTIME_DIR}" "${LOG_DIR}"

# ----------------------------
# Detect php-fpm binary (differs by base image)
# ----------------------------
PHP_FPM_BIN=""
for c in php-fpm php-fpm8.2 /usr/sbin/php-fpm8.2 /usr/local/sbin/php-fpm; do
  if command -v "${c}" >/dev/null 2>&1; then
    PHP_FPM_BIN="$(command -v "${c}")"
    break
  elif [[ -x "${c}" ]]; then
    PHP_FPM_BIN="${c}"
    break
  fi
done

if [[ -z "${PHP_FPM_BIN}" ]]; then
  echo "[TTG] ERROR: php-fpm binary not found (tried php-fpm/php-fpm8.2)"
  echo "[TTG] INFO: PATH=${PATH}"
  ls -la /usr/sbin 2>/dev/null | head -n 60 || true
  ls -la /usr/local/sbin 2>/dev/null | head -n 60 || true
  exit 1
fi

# ----------------------------
# Detect Chromium for PDF
# ----------------------------
CHROMIUM_BIN=""
if command -v chromium >/dev/null 2>&1; then
  CHROMIUM_BIN="$(command -v chromium)"
elif command -v chromium-browser >/dev/null 2>&1; then
  CHROMIUM_BIN="$(command -v chromium-browser)"
fi

if [[ -n "${CHROMIUM_BIN}" ]]; then
  echo "[TTG] Chromium detected: ${CHROMIUM_BIN}"
  export CHROMIUM_PATH="${CHROMIUM_BIN}"
  export CHROME_BIN="${CHROMIUM_BIN}"
  export PUPPETEER_EXECUTABLE_PATH="${CHROMIUM_BIN}"
  export BROWSERSHOT_CHROMIUM_PATH="${CHROMIUM_BIN}"
  export BROWSERSHOT_CHROME_PATH="${CHROMIUM_BIN}"
else
  echo "[TTG] WARN: Chromium not found in PATH (PDF preview may fail)"
fi

# ----------------------------
# Redis safety for WEB
# ----------------------------
if [[ "${ROLE}" == "web" ]] && [[ "${TTG_WEB_REDIS:-0}" != "1" ]]; then
  echo "[TTG] WARN: Disabling Redis for WEB (set TTG_WEB_REDIS=1 to allow Redis)"
  export CACHE_DRIVER="${CACHE_DRIVER:-file}"
  export SESSION_DRIVER="${SESSION_DRIVER:-file}"
  export QUEUE_CONNECTION="${QUEUE_CONNECTION:-sync}"
fi

# ----------------------------
# Build Nginx runtime config
#   IMPORTANT: pid + temp paths must be writable (Pterodactyl FS is often RO outside /home/container)
# ----------------------------
mkdir -p \
  "${RUNTIME_DIR}/nginx/body" \
  "${RUNTIME_DIR}/nginx/proxy" \
  "${RUNTIME_DIR}/nginx/fastcgi" \
  "${RUNTIME_DIR}/nginx/uwsgi" \
  "${RUNTIME_DIR}/nginx/scgi"

cat > "${RUNTIME_DIR}/nginx.conf" <<EOF
pid ${RUNTIME_DIR}/nginx.pid;
worker_processes  1;

events { worker_connections  1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  access_log  ${LOG_DIR}/nginx_access.log;
  error_log   ${LOG_DIR}/nginx_error.log warn;

  sendfile        on;
  keepalive_timeout  65;

  client_body_temp_path ${RUNTIME_DIR}/nginx/body;
  proxy_temp_path       ${RUNTIME_DIR}/nginx/proxy;
  fastcgi_temp_path     ${RUNTIME_DIR}/nginx/fastcgi;
  uwsgi_temp_path       ${RUNTIME_DIR}/nginx/uwsgi;
  scgi_temp_path        ${RUNTIME_DIR}/nginx/scgi;

  server {
    listen ${PORT};
    server_name _;

    root ${APP_DIR}/public;
    index index.php index.html;

    location / {
      try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
      include /etc/nginx/fastcgi_params;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      fastcgi_param PATH_INFO \$fastcgi_path_info;
      fastcgi_pass 127.0.0.1:9000;
    }
  }
}
EOF

# ----------------------------
# PHP-FPM runtime config
# ----------------------------
cat > "${RUNTIME_DIR}/php-fpm.conf" <<EOF
[global]
error_log = ${LOG_DIR}/php-fpm_error.log
daemonize = no

[www]
listen = 127.0.0.1:9000
listen.allowed_clients = 127.0.0.1
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
clear_env = no

env[CHROMIUM_PATH] = ${CHROMIUM_BIN}
env[CHROME_BIN] = ${CHROMIUM_BIN}
env[PUPPETEER_EXECUTABLE_PATH] = ${CHROMIUM_BIN}
env[BROWSERSHOT_CHROMIUM_PATH] = ${CHROMIUM_BIN}
env[BROWSERSHOT_CHROME_PATH] = ${CHROMIUM_BIN}
EOF

# ----------------------------
# Sanity: app present
# ----------------------------
if [[ ! -f "${APP_DIR}/artisan" ]]; then
  echo "[TTG] ERROR: Could not locate Laravel 'artisan' at ${APP_DIR}/artisan"
  ls -la "${APP_DIR}" || true
  exit 1
fi

# ----------------------------
# Clean shutdown handling (so Stop/Restart works without 'Kill')
# ----------------------------
PHP_FPM_PID=""
cleanup() {
  echo "[TTG] Caught stop signal, shutting down..."
  if [[ -n "${PHP_FPM_PID}" ]] && kill -0 "${PHP_FPM_PID}" 2>/dev/null; then
    kill -TERM "${PHP_FPM_PID}" 2>/dev/null || true
  fi

  # Ask nginx to quit gracefully if it started
  if [[ -f "${RUNTIME_DIR}/nginx.pid" ]]; then
    nginx -c "${RUNTIME_DIR}/nginx.conf" -s quit 2>/dev/null || true
  fi
}
trap cleanup TERM INT

# ----------------------------
# Start services
# ----------------------------
echo "[TTG] Starting PHP-FPM (${PHP_FPM_BIN})..."
"${PHP_FPM_BIN}" -y "${RUNTIME_DIR}/php-fpm.conf" -F &
PHP_FPM_PID="$!"

echo "[TTG] Starting nginx on port ${PORT}..."
nginx -g "daemon off;" -c "${RUNTIME_DIR}/nginx.conf"

# If nginx exits, ensure php-fpm goes down too
cleanup
wait "${PHP_FPM_PID}" 2>/dev/null || true
