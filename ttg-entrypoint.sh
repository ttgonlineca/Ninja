#!/bin/sh
set -eu

echo "[TTG] Invoice Ninja (FPM) starting..."

PORT="${PORT:-8800}"

BASE="/home/container"
RUNTIME="${BASE}/.runtime"
LOGS="${BASE}/.logs"
APP_DIR="${BASE}/app"

mkdir -p "$RUNTIME" "$LOGS" "$RUNTIME/tmp" "$RUNTIME/sessions" /tmp

echo "[TTG] PORT: ${PORT}"
echo "[TTG] RUNTIME: ${RUNTIME}"
echo "[TTG] LOGS: ${LOGS}"
echo "[TTG] APP_DIR: ${APP_DIR}"

# Laravel writable directories
if [ -d "$APP_DIR" ]; then
  mkdir -p "$APP_DIR/storage" "$APP_DIR/bootstrap/cache" \
           "$APP_DIR/storage/logs" "$APP_DIR/storage/framework/cache" \
           "$APP_DIR/storage/framework/sessions" "$APP_DIR/storage/framework/views" || true
  chmod -R u+rwX,go+rX "$APP_DIR/storage" "$APP_DIR/bootstrap/cache" 2>/dev/null || true
fi

# Nginx config (absolute include paths)
NGINX_CONF="${RUNTIME}/nginx.conf"

cat > "$NGINX_CONF" <<EOF
worker_processes  1;

events { worker_connections 1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  access_log    ${LOGS}/nginx-access.log;
  error_log     ${LOGS}/nginx-error.log warn;

  sendfile      on;
  keepalive_timeout  65;

  client_body_temp_path /tmp/nginx_client_body;
  proxy_temp_path       /tmp/nginx_proxy;
  fastcgi_temp_path     /tmp/nginx_fastcgi;
  uwsgi_temp_path       /tmp/nginx_uwsgi;
  scgi_temp_path        /tmp/nginx_scgi;

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
      fastcgi_pass 127.0.0.1:9000;
      fastcgi_read_timeout 300;
    }

    location ~ /\. {
      deny all;
    }
  }
}
EOF

mkdir -p /tmp/nginx_client_body /tmp/nginx_proxy /tmp/nginx_fastcgi /tmp/nginx_uwsgi /tmp/nginx_scgi 2>/dev/null || true

echo "[TTG] Wrote nginx config: ${NGINX_CONF}"

# PHP-FPM config (all writable paths)
FPM_CONF="${RUNTIME}/php-fpm.conf"
FPM_POOL="${RUNTIME}/www.conf"
FPM_PID="${RUNTIME}/php-fpm.pid"

cat > "$FPM_CONF" <<EOF
[global]
pid = ${FPM_PID}
error_log = ${LOGS}/php-fpm.log
log_level = notice
daemonize = yes

include=${FPM_POOL}
EOF

cat > "$FPM_POOL" <<EOF
[www]
listen = 127.0.0.1:9000
listen.allowed_clients = 127.0.0.1

pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3

catch_workers_output = yes
clear_env = no

php_admin_value[session.save_path] = ${RUNTIME}/sessions
php_admin_value[sys_temp_dir] = ${RUNTIME}/tmp
php_admin_value[upload_tmp_dir] = ${RUNTIME}/tmp
EOF

echo "[TTG] Prepared PHP-FPM config: ${FPM_CONF}"

FPM_BIN="/usr/sbin/php-fpm8.2"
[ -x "$FPM_BIN" ] || FPM_BIN="/usr/sbin/php-fpm"

echo "[TTG] Starting PHP-FPM: ${FPM_BIN}"
"$FPM_BIN" -y "$FPM_CONF" -D

echo "[TTG] Starting nginx..."
exec nginx -c "$NGINX_CONF" -g "daemon off;"
