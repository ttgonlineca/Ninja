#!/usr/bin/env bash
set -e

echo "[TTG] Invoice Ninja starting..."

# -----------------------
# Pterodactyl env compat
# -----------------------
PORT="${SERVER_PORT:-${PORT:-8800}}"
ROLE_RAW="${ROLE:-${LARAVEL_ROLE:-web}}"

case "$ROLE_RAW" in
  app) ROLE="web" ;;
  web|worker|scheduler) ROLE="$ROLE_RAW" ;;
  *) ROLE="web" ;;
esac

RUNTIME="${RUNTIME:-/home/container/.runtime}"
LOGS="${LOGS:-/home/container/.logs}"
APP_DIR="${APP_DIR:-/home/container/app}"

echo "[TTG] PORT: $PORT"
echo "[TTG] ROLE: $ROLE"
echo "[TTG] RUNTIME: $RUNTIME"
echo "[TTG] LOGS: $LOGS"
echo "[TTG] APP_DIR: $APP_DIR"

mkdir -p "$RUNTIME/tmp" "$RUNTIME/sessions" "$LOGS"

cd "$APP_DIR"

log() { echo "[TTG] $*"; }

# -----------------------
# Fix company_logo paths
# -----------------------
normalize_company_logo() {
  if [[ -z "${DB_HOST:-}" || -z "${DB_DATABASE:-}" || -z "${DB_USERNAME:-}" ]]; then
    log "DB env missing, skipping logo normalization"
    return
  fi

  php -r '
$dsn = sprintf(
  "mysql:host=%s;port=%s;dbname=%s;charset=utf8mb4",
  getenv("DB_HOST"),
  getenv("DB_PORT") ?: "3306",
  getenv("DB_DATABASE")
);
$pdo = new PDO($dsn, getenv("DB_USERNAME"), getenv("DB_PASSWORD") ?: "", [
  PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION
]);

$q = $pdo->query("SELECT id, settings FROM companies WHERE settings LIKE \"%company_logo%\"");
$u = $pdo->prepare("UPDATE companies SET settings=? WHERE id=?");

foreach ($q as $r) {
  $j = json_decode($r["settings"], true);
  if (!isset($j["company_logo"])) continue;

  $logo = $j["company_logo"];
  if (!is_string($logo) || str_starts_with($logo, "/storage/")) continue;

  $p = strrpos($logo, "/storage/");
  if ($p === false) continue;

  $j["company_logo"] = "/storage/" . substr($logo, $p + 9);
  $u->execute([json_encode($j, JSON_UNESCAPED_SLASHES), $r["id"]]);
}
';
}

normalize_company_logo
php artisan optimize:clear >/dev/null 2>&1 || true

# -----------------------
# Storage symlink
# -----------------------
if [[ ! -L public/storage ]]; then
  php artisan storage:link >/dev/null 2>&1 || true
fi

# -----------------------
# Worker / Scheduler
# -----------------------
if [[ "$ROLE" == "worker" ]]; then
  log "Starting queue worker"
  exec php artisan queue:work --verbose --tries=3 --timeout=120
fi

if [[ "$ROLE" == "scheduler" ]]; then
  log "Starting scheduler"
  while true; do
    php artisan schedule:run --no-interaction || true
    sleep 60
  done
fi

# -----------------------
# WEB STACK (nginx + FPM)
# -----------------------
NGINX_CONF="$RUNTIME/nginx.conf"
FPM_CONF="$RUNTIME/php-fpm.conf"
FPM_POOL="$RUNTIME/php-fpm.pool.conf"

cat > "$NGINX_CONF" <<EOF
worker_processes 1;
events { worker_connections 1024; }

http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  sendfile on;
  keepalive_timeout 65;

  access_log $LOGS/nginx_access.log;
  error_log $LOGS/nginx_error.log warn;

  server {
    listen $PORT;
    root $APP_DIR/public;
    index index.php;

    location / {
      try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
      try_files \$uri =404;
      include fastcgi_params;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      fastcgi_param PATH_INFO \$fastcgi_path_info;
      fastcgi_pass 127.0.0.1:9000;
    }

    location ~* \.(css|js|png|jpg|jpeg|gif|svg|ico|woff2?)\$ {
      expires 365d;
      add_header Cache-Control "public, max-age=31536000, immutable";
    }
  }
}
EOF

cat > "$FPM_CONF" <<EOF
[global]
pid = $RUNTIME/php-fpm.pid
error_log = $LOGS/php-fpm_error.log
daemonize = yes
include=$FPM_POOL
EOF

cat > "$FPM_POOL" <<EOF
[www]
listen = 127.0.0.1:9000
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
clear_env = no
php_admin_value[session.save_path] = $RUNTIME/sessions
php_admin_value[upload_tmp_dir] = $RUNTIME/tmp
php_admin_value[sys_temp_dir] = $RUNTIME/tmp
EOF

/usr/sbin/php-fpm8.2 -y "$FPM_CONF" -D
exec nginx -c "$NGINX_CONF" -g "daemon off;"
