#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8800}"

APP_DIR="/home/container/app"
RUNTIME="/home/container/.runtime"
LOGS="/home/container/.logs"

TEMPLATE_BAKED="/opt/ttg/templates/nginx.conf.template"
TEMPLATE_VOL1="/home/container/nginx.conf.template"
TEMPLATE_VOL2="/home/container/app/nginx.conf.template"

echo "[TTG] Invoice Ninja starting..."
echo "[TTG] PORT: ${PORT}"
echo "[TTG] RUNTIME: ${RUNTIME}"
echo "[TTG] LOGS: ${LOGS}"
echo "[TTG] APP_DIR: ${APP_DIR}"

# Runtime dirs (no chown in rootless)
mkdir -p "${RUNTIME}" "${LOGS}"
mkdir -p "${RUNTIME}/nginx" \
         "${RUNTIME}/nginx/client_body" \
         "${RUNTIME}/nginx/proxy" \
         "${RUNTIME}/nginx/fastcgi" \
         "${RUNTIME}/nginx/uwsgi" \
         "${RUNTIME}/nginx/scgi"

# Chromium
if command -v chromium >/dev/null 2>&1; then
  echo "[TTG] Chromium detected: $(command -v chromium)"
fi

# Choose nginx template
NGINX_TEMPLATE=""
if [[ -f "${TEMPLATE_VOL1}" ]]; then
  NGINX_TEMPLATE="${TEMPLATE_VOL1}"
elif [[ -f "${TEMPLATE_VOL2}" ]]; then
  NGINX_TEMPLATE="${TEMPLATE_VOL2}"
elif [[ -f "${TEMPLATE_BAKED}" ]]; then
  NGINX_TEMPLATE="${TEMPLATE_BAKED}"
fi

if [[ -z "${NGINX_TEMPLATE}" ]]; then
  echo "[TTG] ERROR: nginx.conf.template not found (expected ${TEMPLATE_VOL1} or ${TEMPLATE_VOL2} or ${TEMPLATE_BAKED})"
  exit 1
fi

echo "[TTG] Using nginx.conf.template from: ${NGINX_TEMPLATE}"

# Render nginx conf into writable runtime
sed "s/{{PORT}}/${PORT}/g" "${NGINX_TEMPLATE}" > "${RUNTIME}/nginx.conf"

# PHP-FPM socket config (Debian php-fpm8.2)
# We force it to use a unix socket in writable runtime.
PHP_FPM_BIN="/usr/sbin/php-fpm8.2"
if [[ ! -x "${PHP_FPM_BIN}" ]]; then
  echo "[TTG] ERROR: php-fpm8.2 not found at ${PHP_FPM_BIN}"
  exit 1
fi

# Create a minimal pool override (include into default)
cat > "${RUNTIME}/zz-ttg-fpm.conf" <<'EOF'
[global]
error_log = /home/container/.logs/php-fpm_error.log

[www]
listen = /home/container/.runtime/php-fpm.sock
listen.owner = container
listen.group = container
listen.mode = 0660

pm = dynamic
pm.max_children = 25
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8

catch_workers_output = yes
EOF

# Start php-fpm in foreground (daemonize = no)
echo "[TTG] Starting PHP-FPM (${PHP_FPM_BIN})..."
"${PHP_FPM_BIN}" -F -y /etc/php/8.2/fpm/php-fpm.conf -d "include=${RUNTIME}/zz-ttg-fpm.conf" &
PHP_PID=$!

# Start nginx in foreground with custom conf + runtime prefix
echo "[TTG] Starting nginx on port ${PORT}..."
nginx -c "${RUNTIME}/nginx.conf" -p "${RUNTIME}/nginx" -g "daemon off;" &
NGINX_PID=$!

# Graceful stop
term_handler() {
  echo "[TTG] Caught stop signal, shutting down..."
  if kill -0 "${NGINX_PID}" 2>/dev/null; then
    nginx -c "${RUNTIME}/nginx.conf" -p "${RUNTIME}/nginx" -s quit || true
  fi
  if kill -0 "${PHP_PID}" 2>/dev/null; then
    kill "${PHP_PID}" || true
  fi
  wait || true
  echo "[TTG] Stopped."
}

trap term_handler SIGTERM SIGINT

# Wait on either process
wait -n "${PHP_PID}" "${NGINX_PID}"
term_handler
