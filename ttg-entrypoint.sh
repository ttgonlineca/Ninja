#!/usr/bin/env bash
set -euo pipefail

log() { echo "[TTG] $*"; }

# ----------------------------
# Paths / defaults
# ----------------------------
PORT="${PORT:-8800}"
RUNTIME="/home/container/.runtime"
LOGDIR="/home/container/.logs"
APP_DIR="/home/container/app"

mkdir -p "$RUNTIME" "$LOGDIR"

log "Invoice Ninja (FPM) starting..."
log "PORT: ${PORT}"
log "RUNTIME: ${RUNTIME}"
log "LOGS: ${LOGDIR}"
log "APP_DIR: ${APP_DIR}"

# ----------------------------
# Proxy + URL sanity
# ----------------------------
# We never want the app to "discover" itself via LAN/Tailscale and bake that into URLs.
: "${APP_URL:?ERROR: APP_URL must be set (example: https://billing.ttgonline.ca)}"
: "${TRUSTED_PROXIES:=*}"
: "${REQUIRE_HTTPS:=true}"

export APP_URL TRUSTED_PROXIES REQUIRE_HTTPS

# Optional safe defaults
: "${APP_ENV:=production}"
: "${APP_DEBUG:=false}"
export APP_ENV APP_DEBUG

# ----------------------------
# Ensure .env contains the non-secret URL/proxy values
# ----------------------------
ensure_env_kv() {
  local key="$1" val="$2" envfile="${3:-$APP_DIR/.env}"
  mkdir -p "$(dirname "$envfile")"
  touch "$envfile"

  if grep -qE "^${key}=" "$envfile"; then
    sed -i "s|^${key}=.*|${key}=${val}|g" "$envfile"
  else
    echo "${key}=${val}" >> "$envfile"
  fi
}

ensure_env_kv "APP_URL" "${APP_URL}"
ensure_env_kv "TRUSTED_PROXIES" "${TRUSTED_PROXIES}"
ensure_env_kv "REQUIRE_HTTPS" "${REQUIRE_HTTPS}"
ensure_env_kv "APP_ENV" "${APP_ENV}"
ensure_env_kv "APP_DEBUG" "${APP_DEBUG}"

# ----------------------------
# Fix company_logo on boot (safe + generic)
# ----------------------------
# Converts any absolute logo URL (http(s)://.../storage/... OR 100.x.x.x/storage/...)
# into a relative /storage/... so it works on any domain/server.
fix_company_logo_urls() {
  command -v mysql >/dev/null 2>&1 || { log "mysql client not found - skipping logo fix"; return 0; }

  local db_host="${DB_HOST:-}"
  local db_port="${DB_PORT:-}"
  local db_name="${DB_DATABASE:-}"
  local db_user="${DB_USERNAME:-}"
  local db_pass="${DB_PASSWORD:-}"

  # If you use different env var names, add them here (fallbacks)
  [ -n "$db_host" ] || db_host="${MYSQL_HOST:-}"
  [ -n "$db_port" ] || db_port="${MYSQL_PORT:-}"
  [ -n "$db_name" ] || db_name="${MYSQL_DATABASE:-}"
  [ -n "$db_user" ] || db_user="${MYSQL_USER:-}"
  [ -n "$db_pass" ] || db_pass="${MYSQL_PASSWORD:-}"

  # Need full creds
  [ -n "$db_host" ] && [ -n "$db_port" ] && [ -n "$db_name" ] && [ -n "$db_user" ] && [ -n "$db_pass" ] || {
    log "DB env vars missing - skipping logo fix"
    return 0
  }

  # Avoid password on CLI args (won't echo); still treat env as sensitive
  export MYSQL_PWD="$db_pass"

  # Only run if it appears necessary
  local needs_fix="0"
  needs_fix="$(mysql -N -h "$db_host" -P "$db_port" -u "$db_user" "$db_name" -e \
    "SELECT COUNT(*) FROM companies
     WHERE settings LIKE '%\"company_logo\"%'
       AND (settings LIKE '%\"company_logo\":\"http%'
            OR settings REGEXP '\"company_logo\":\"[0-9]{1,3}\\.[0-9]{1,3}');" 2>/dev/null || echo "0")"

  if [ "${needs_fix:-0}" != "0" ]; then
    log "Normalizing company_logo to relative /storage/... (was absolute)"
    mysql -h "$db_host" -P "$db_port" -u "$db_user" "$db_name" -e \
      "UPDATE companies
       SET settings = REGEXP_REPLACE(settings,
         '\"company_logo\":\"[^\\\"]*\\/storage\\/',
         '\"company_logo\":\"\\/storage\\/'
       )
       WHERE settings LIKE '%\"company_logo\"%';" >/dev/null 2>&1 || true
  else
    log "company_logo already OK (relative or not set)"
  fi

  unset MYSQL_PWD
}

# ----------------------------
# Clear Laravel caches (prevents stale URL behavior)
# ----------------------------
clear_laravel_cache() {
  if [ -f "$APP_DIR/artisan" ]; then
    log "Clearing Laravel caches..."
    php "$APP_DIR/artisan" optimize:clear >/dev/null 2>&1 || true
  fi
}

fix_company_logo_urls
clear_laravel_cache

# ----------------------------
# Write nginx config
# ----------------------------
NGINX_CONF="${RUNTIME}/nginx.conf"
cat > "$NGINX_CONF" <<EOF
worker_processes auto;
pid ${RUNTIME}/nginx.pid;

events { worker_connections 1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  access_log ${LOGDIR}/nginx_access.log;
  error_log  ${LOGDIR}/nginx_error.log warn;

  sendfile on;
  keepalive_timeout 65;

  server {
    listen ${PORT};
    server_name _;

    root ${APP_DIR}/public;
    index index.php index.html;

    # Storage: logos, PDFs, uploads
    location /storage/ {
      try_files \$uri \$uri/ /index.php?\$query_string;
      expires 365d;
      add_header Cache-Control "public, max-age=31536000, immutable";
    }

    location / {
      try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
      include snippets/fastcgi-php.conf;
      fastcgi_pass 127.0.0.1:9000;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      include fastcgi_params;
    }
  }
}
EOF

log "Wrote nginx config: ${NGINX_CONF}"

# ----------------------------
# Write PHP-FPM config
# ----------------------------
FPM_CONF="${RUNTIME}/php-fpm.conf"
FPM_POOL="${RUNTIME}/www.conf"

cat > "$FPM_CONF" <<EOF
[global]
pid = ${RUNTIME}/php-fpm.pid
error_log = ${LOGDIR}/php-fpm_error.log
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

log "Prepared PHP-FPM config: ${FPM_CONF}"

FPM_BIN="/usr/sbin/php-fpm8.2"
[ -x "$FPM_BIN" ] || FPM_BIN="/usr/sbin/php-fpm"

log "Starting PHP-FPM: ${FPM_BIN}"
"$FPM_BIN" -y "$FPM_CONF" -D

log "Starting nginx..."
exec nginx -c "$NGINX_CONF" -g "daemon off;"
