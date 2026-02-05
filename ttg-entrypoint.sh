#!/usr/bin/env bash
set -euo pipefail

export PORT="${PORT:-8800}"
export APP_DIR="${APP_DIR:-/home/container/app}"
export RUNTIME_DIR="${RUNTIME_DIR:-/home/container/.runtime}"
export LOG_DIR="${LOG_DIR:-/home/container/.logs}"

echo "[TTG] Invoice Ninja starting..."
echo "[TTG] PORT: ${PORT}"
echo "[TTG] RUNTIME: ${RUNTIME_DIR}"
echo "[TTG] LOGS: ${LOG_DIR}"
echo "[TTG] APP_DIR: ${APP_DIR}"

mkdir -p \
  "${RUNTIME_DIR}" \
  "${RUNTIME_DIR}/nginx/client_body" \
  "${RUNTIME_DIR}/nginx/proxy" \
  "${RUNTIME_DIR}/nginx/fastcgi" \
  "${RUNTIME_DIR}/nginx/uwsgi" \
  "${RUNTIME_DIR}/nginx/scgi" \
  "${RUNTIME_DIR}/sessions" \
  "${RUNTIME_DIR}/tmp" \
  "${LOG_DIR}"

# --- Chromium check (for PDF) ---
if command -v chromium >/dev/null 2>&1; then
  echo "[TTG] Chromium detected: $(command -v chromium)"
  export TTG_CHROMIUM_PATH="$(command -v chromium)"
elif command -v chromium-browser >/dev/null 2>&1; then
  echo "[TTG] Chromium detected: $(command -v chromium-browser)"
  export TTG_CHROMIUM_PATH="$(command -v chromium-browser)"
elif command -v google-chrome >/dev/null 2>&1; then
  echo "[TTG] Chromium detected: $(command -v google-chrome)"
  export TTG_CHROMIUM_PATH="$(command -v google-chrome)"
else
  echo "[TTG] WARN: Chromium not found in PATH"
fi

# --- Find nginx template ---
TEMPLATE=""
if [[ -f "/home/container/nginx.conf.template" ]]; then
  TEMPLATE="/home/container/nginx.conf.template"
elif [[ -f "${APP_DIR}/nginx.conf.template" ]]; then
  TEMPLATE="${APP_DIR}/nginx.conf.template"
elif [[ -f "/opt/ttg/templates/nginx.conf.template" ]]; then
  TEMPLATE="/opt/ttg/templates/nginx.conf.template"
fi

if [[ -z "${TEMPLATE}" ]]; then
  echo "[TTG] ERROR: nginx.conf.template not found (expected /home/container/nginx.conf.template or ${APP_DIR}/nginx.conf.template or /opt/ttg/templates/nginx.conf.template)"
  exit 1
fi

echo "[TTG] Using nginx.conf.template from: ${TEMPLATE}"

# --- Render nginx.conf (replace {{PORT}}) ---
NGINX_CONF="${RUNTIME_DIR}/nginx.conf"
sed "s/{{PORT}}/${PORT}/g" "${TEMPLATE}" > "${NGINX_CONF}"

# --- Ensure fastcgi_params exists (rootless-safe include path) ---
if [[ -f "/etc/nginx/fastcgi_params" ]]; then
  cp -f "/etc/nginx/fastcgi_params" "${RUNTIME_DIR}/fastcgi_params"
else
  cat > "${RUNTIME_DIR}/fastcgi_params" <<'EOF'
fastcgi_param  QUERY_STRING       $query_string;
fastcgi_param  REQUEST_METHOD     $request_method;
fastcgi_param  CONTENT_TYPE       $content_type;
fastcgi_param  CONTENT_LENGTH     $content_length;

fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
fastcgi_param  REQUEST_URI        $request_uri;
fastcgi_param  DOCUMENT_URI       $document_uri;
fastcgi_param  DOCUMENT_ROOT      $document_root;
fastcgi_param  SERVER_PROTOCOL    $server_protocol;
fastcgi_param  REQUEST_SCHEME     $scheme;
fastcgi_param  HTTPS              $https if_not_empty;

fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;

fastcgi_param  REMOTE_ADDR        $remote_addr;
fastcgi_param  REMOTE_PORT        $remote_port;
fastcgi_param  SERVER_ADDR        $server_addr;
fastcgi_param  SERVER_PORT        $server_port;
fastcgi_param  SERVER_NAME        $server_name;
EOF
fi

# --- Rootless PHP-FPM runtime config (TCP 9000, no /var/log, no chown socket) ---
PHP_FPM_BIN="/usr/sbin/php-fpm8.2"
if ! command -v "${PHP_FPM_BIN}" >/dev/null 2>&1; then
  PHP_FPM_BIN="$(command -v php-fpm8.2 || command -v php-fpm || true)"
fi
if [[ -z "${PHP_FPM_BIN}" ]]; then
  echo "[TTG] ERROR: php-fpm binary not found"
  exit 1
fi

PHP_FPM_CONF="${RUNTIME_DIR}/php-fpm.conf"
PHP_FPM_POOL="${RUNTIME_DIR}/php-fpm.pool.conf"

cat > "${PHP_FPM_CONF}" <<EOF
[global]
pid = ${RUNTIME_DIR}/php-fpm.pid
error_log = ${LOG_DIR}/php-fpm_error.log
log_level = notice
daemonize = no
include=${PHP_FPM_POOL}
EOF

cat > "${PHP_FPM_POOL}" <<EOF
[www]
listen = 127.0.0.1:9000
listen.allowed_clients = 127.0.0.1

pm = dynamic
pm.max_children = 20
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8

php_admin_value[session.save_path] = ${RUNTIME_DIR}/sessions
php_admin_value[error_log] = ${LOG_DIR}/php_errors.log
php_admin_flag[log_errors] = on
EOF

NGINX_PID=""
PHP_PID=""

term_handler() {
  echo "[TTG] Caught stop signal, shutting down..."

  if [[ -n "${NGINX_PID}" ]] && kill -0 "${NGINX_PID}" 2>/dev/null; then
    echo "[TTG] Stopping nginx..."
    kill -QUIT "${NGINX_PID}" 2>/dev/null || true
  fi

  if [[ -n "${PHP_PID}" ]] && kill -0 "${PHP_PID}" 2>/dev/null; then
    echo "[TTG] Stopping php-fpm..."
    kill -TERM "${PHP_PID}" 2>/dev/null || true
  fi

  sleep 2
  exit 0
}

trap term_handler SIGTERM SIGINT

echo "[TTG] Starting PHP-FPM (${PHP_FPM_BIN})..."
"${PHP_FPM_BIN}" -y "${PHP_FPM_CONF}" &
PHP_PID="$!"

echo "[TTG] Starting nginx on port ${PORT}..."

# IMPORTANT:
# Force PID file into runtime dir so nginx NEVER touches /run (read-only in Ptero)
# Also run "daemon off" so the container stays alive.
exec nginx \
  -p "${RUNTIME_DIR}" \
  -c "${NGINX_CONF}" \
  -g "pid ${RUNTIME_DIR}/nginx.pid; daemon off;"
