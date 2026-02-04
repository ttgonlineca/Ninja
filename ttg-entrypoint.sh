#!/usr/bin/env bash
set -euo pipefail

# ----------------------------
# TTG Invoice Ninja Entrypoint
# ----------------------------

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
# Your earlier 500s were Redis timeouts; default WEB should not hard-require Redis.
# Set TTG_WEB_REDIS=1 if you *want* WEB to use Redis.
if [[ "${ROLE}" == "web" ]] && [[ "${TTG_WEB_REDIS:-0}" != "1" ]]; then
  echo "[TTG] WARN: Disabling Redis for WEB (set TTG_WEB_REDIS=1 to allow Redis)"
  export CACHE_DRIVER="${CACHE_DRIVER:-file}"
  export SESSION_DRIVER="${SESSION_DRIVER:-file}"
  export QUEUE_CONNECTION="${QUEUE_CONNECTION:-sync}"
fi

# ----------------------------
# Build Nginx runtime config
#   IMPORTANT: Use absolute include paths because nginx is started with -c in RUNTIME_DIR.
# ----------------------------
cat > "${RUNTIME_DIR}/nginx.conf" <<EOF
worker_processes  1;

events { worker_connections  1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  access_log  ${LOG_DIR}/nginx_access.log;
  error_log   ${LOG_DIR}/nginx_error.log warn;

  sendfile        on;
  keepalive_timeout  65;

  # Avoid readonly FS writes in /var/lib/nginx/*
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

    location ~* \.(?:css|js|jpg|jpeg|gif|png|svg|ico|woff|woff2|ttf|eot)\$ {
      expires 7d;
      access_log off;
      add_header Cache-Control "public";
    }
  }
}
EOF

mkdir -p \
  "${RUNTIME_DIR}/nginx/body" \
  "${RUNTIME_DIR}/nginx/proxy" \
  "${RUNTIME_DIR}/nginx/fastcgi" \
  "${RUNTIME_DIR}/nginx/uwsgi" \
  "${RUNTIME_DIR}/nginx/scgi"

# ----------------------------
# Build PHP-FPM runtime config
#   IMPORTANT: clear_env=no so the app can see CHROMIUM_PATH/CHROME_BIN, etc.
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

; Pass common chromium vars into PHP-FPM explicitly (belt + suspenders)
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
  echo "[TTG] INFO: Listing ${APP_DIR} so we can see what's mounted:"
  ls -la "${APP_DIR}" || true
  exit 1
fi

# ----------------------------
# Start services
# ----------------------------
echo "[TTG] Starting PHP-FPM..."
php-fpm -y "${RUNTIME_DIR}/php-fpm.conf" -F &

echo "[TTG] Starting nginx on port ${PORT}..."
nginx -g "daemon off;" -c "${RUNTIME_DIR}/nginx.conf"
