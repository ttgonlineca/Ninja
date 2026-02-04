#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/home/container/app}"
RUNTIME_DIR="${RUNTIME_DIR:-/home/container/.runtime}"
LOG_DIR="${LOG_DIR:-/home/container/.logs}"
PORT="${PORT:-8800}"

mkdir -p "$RUNTIME_DIR" "$LOG_DIR"

CHROMIUM_BIN="$(command -v chromium || command -v chromium-browser || true)"
if [[ -n "${CHROMIUM_BIN}" ]]; then
  echo "[TTG] Chromium detected: ${CHROMIUM_BIN}"
else
  echo "[TTG] WARN: Chromium not found"
fi

export CHROMIUM_PATH="${CHROMIUM_BIN}"
export CHROME_BIN="${CHROMIUM_BIN}"
export PUPPETEER_EXECUTABLE_PATH="${CHROMIUM_BIN}"
export BROWSERSHOT_CHROMIUM_PATH="${CHROMIUM_BIN}"
export BROWSERSHOT_CHROME_PATH="${CHROMIUM_BIN}"

export APP_DEBUG="${APP_DEBUG:-false}"
export LOG_CHANNEL="${LOG_CHANNEL:-stderr}"

# ----------------------------
# PHP-FPM runtime config
# ----------------------------
cat > "${RUNTIME_DIR}/php-fpm.conf" <<EOF
[global]
error_log = ${LOG_DIR}/php-fpm_error.log
daemonize = yes

[www]
listen = 127.0.0.1:9000
listen.allowed_clients = 127.0.0.1

pm = dynamic
pm.max_children = ${PHP_FPM_MAX_CHILDREN:-5}
pm.start_servers = ${PHP_FPM_START_SERVERS:-2}
pm.min_spare_servers = ${PHP_FPM_MIN_SPARE:-1}
pm.max_spare_servers = ${PHP_FPM_MAX_SPARE:-2}
pm.max_requests = ${PHP_FPM_MAX_REQUESTS:-200}

request_terminate_timeout = ${PHP_FPM_REQ_TIMEOUT:-60s}
request_slowlog_timeout   = ${PHP_FPM_SLOW_TIMEOUT:-10s}
slowlog = ${LOG_DIR}/php-fpm_slow.log

catch_workers_output = yes
clear_env = no

env[CHROMIUM_PATH] = ${CHROMIUM_BIN}
env[CHROME_BIN] = ${CHROMIUM_BIN}
env[PUPPETEER_EXECUTABLE_PATH] = ${CHROMIUM_BIN}
env[BROWSERSHOT_CHROMIUM_PATH] = ${CHROMIUM_BIN}
env[BROWSERSHOT_CHROME_PATH] = ${CHROMIUM_BIN}
EOF

# ----------------------------
# Nginx runtime config
# ----------------------------
cat > "${RUNTIME_DIR}/nginx.conf" <<EOF
worker_processes auto;
pid ${RUNTIME_DIR}/nginx.pid;

events { worker_connections 1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  access_log ${LOG_DIR}/nginx_access.log;
  error_log  ${LOG_DIR}/nginx_error.log warn;

  sendfile on;
  keepalive_timeout 65;

  server {
    listen ${PORT};
    server_name _;

    root ${APP_DIR}/public;
    index index.php index.html;

    location / {
      try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
      include fastcgi_params;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      fastcgi_pass 127.0.0.1:9000;
    }

    location ~ /\. { deny all; }
  }
}
EOF

# ----------------------------
# Start services
# ----------------------------
echo "[TTG] Starting PHP-FPM (/usr/sbin/php-fpm8.2)..."
/usr/sbin/php-fpm8.2 -y "${RUNTIME_DIR}/php-fpm.conf"

# wait up to ~3s for FPM to accept connections
for i in {1..30}; do
  (echo > /dev/tcp/127.0.0.1/9000) >/dev/null 2>&1 && break
  sleep 0.1
done

echo "[TTG] Starting nginx on port ${PORT}..."
exec nginx -c "${RUNTIME_DIR}/nginx.conf" -g "daemon off;"
