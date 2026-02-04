#!/usr/bin/env bash
set -euo pipefail

echo "[TTG] Invoice Ninja (FPM) starting..."

# -----------------------
# Pterodactyl env compat
# -----------------------
# Port: prefer Pterodactyl's SERVER_PORT, fallback to PORT, then 8800
PORT="${SERVER_PORT:-${PORT:-8800}}"

# Role: accept either ROLE=web|worker|scheduler OR LARAVEL_ROLE=app|worker|scheduler
ROLE_RAW="${ROLE:-${LARAVEL_ROLE:-web}}"
case "$ROLE_RAW" in
  app) ROLE="web" ;;
  web|worker|scheduler) ROLE="$ROLE_RAW" ;;
  *) ROLE="web" ;;
esac

RUNTIME="${RUNTIME:-/home/container/.runtime}"
LOGS="${LOGS:-/home/container/.logs}"
APP_DIR="${APP_DIR:-/home/container/app}"

echo "[TTG] PORT: ${PORT}"
echo "[TTG] RUNTIME: ${RUNTIME}"
echo "[TTG] LOGS: ${LOGS}"
echo "[TTG] APP_DIR: ${APP_DIR}"
echo "[TTG] ROLE: ${ROLE} (raw=${ROLE_RAW})"

mkdir -p "${RUNTIME}" "${LOGS}"
mkdir -p "${RUNTIME}/tmp" "${RUNTIME}/sessions" || true

cd "${APP_DIR}"

# -----------------------
# Helpers
# -----------------------
log() { echo "[TTG] $*"; }

normalize_company_logo_in_db() {
  # If logo was saved as absolute/host/Tailscale/URL/etc, normalize to "/storage/<path after /storage/>"
  # This fixes URLs like:
  #   100.118.x.x/storage/<company_key>/<file>.png
  #   https://billing.../storage/<company_key>/<file>.png
  #   /settings/company_details/100.118.../storage/<company_key>/<file>.png
  #
  # Requires DB creds in env (Invoice Ninja standard):
  # DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD
  #
  # Safe to run repeatedly.
  if [[ -z "${DB_HOST:-}" || -z "${DB_DATABASE:-}" || -z "${DB_USERNAME:-}" ]]; then
    log "DB vars missing; skipping company_logo normalize"
    return 0
  fi

  local DB_PORT_USE="${DB_PORT:-3306}"
  log "Normalizing company_logo paths in DB (if needed)..."

  # Use PHP to run the SQL because it handles quoting well and avoids shell escaping madness
  php -r '
$h=getenv("DB_HOST"); $p=getenv("DB_PORT")?: "3306"; $db=getenv("DB_DATABASE");
$u=getenv("DB_USERNAME"); $pw=getenv("DB_PASSWORD")?: "";
if(!$h||!$db||!$u){fwrite(STDERR,"missing db env\n"); exit(0);}
$dsn="mysql:host=$h;port=$p;dbname=$db;charset=utf8mb4";
$pdo=new PDO($dsn,$u,$pw,[PDO::ATTR_ERRMODE=>PDO::ERRMODE_EXCEPTION]);

// companies.settings is JSON or json-like text.
// Normalize any company_logo value that contains "/storage/" but isn’t starting with "/storage/".
$sql="SELECT id, settings FROM companies WHERE settings LIKE \"%company_logo%\"";
$st=$pdo->query($sql);
$upd=$pdo->prepare("UPDATE companies SET settings=? WHERE id=?");

$count=0;
while($row=$st->fetch(PDO::FETCH_ASSOC)){
  $id=$row["id"];
  $settings=$row["settings"];
  if(!$settings) continue;

  $j=json_decode($settings,true);
  if(!is_array($j)) continue;
  if(!isset($j["company_logo"])) continue;

  $logo=$j["company_logo"];
  if(!is_string($logo) || $logo==="") continue;

  // Find the last occurrence of "/storage/" and rebuild as "/storage/<tail>"
  $pos=strrpos($logo,"/storage/");
  if($pos===false) continue;

  $tail=substr($logo,$pos+strlen("/storage/"));
  $new="/storage/".$tail;

  if($logo === $new) continue;

  $j["company_logo"]=$new;
  $newSettings=json_encode($j, JSON_UNESCAPED_SLASHES);
  $upd->execute([$newSettings,$id]);
  $count++;
}
echo "updated=$count\n";
' || true
}

laravel_optimize_clear() {
  log "Clearing Laravel caches..."
  php artisan optimize:clear >/dev/null 2>&1 || true
}

# -----------------------
# Storage symlink sanity
# -----------------------
if [[ -d "${APP_DIR}/public" && -d "${APP_DIR}/storage/app/public" ]]; then
  if [[ ! -L "${APP_DIR}/public/storage" ]]; then
    log "Creating public/storage symlink..."
    php artisan storage:link >/dev/null 2>&1 || true
  fi
fi

# Always attempt to normalize logo paths and clear caches on boot
normalize_company_logo_in_db
laravel_optimize_clear

# -----------------------
# ROLE: worker / scheduler
# -----------------------
if [[ "${ROLE}" == "worker" ]]; then
  log "Starting QUEUE worker..."
  exec php artisan queue:work --verbose --tries=3 --timeout=120
fi

if [[ "${ROLE}" == "scheduler" ]]; then
  log "Starting scheduler loop..."
  while true; do
    php artisan schedule:run --verbose --no-interaction || true
    sleep 60
  done
fi

# -----------------------
# ROLE: web (nginx + php-fpm)
# -----------------------
log "Starting web stack (nginx + php-fpm)..."

NGINX_CONF="${RUNTIME}/nginx.conf"
FPM_CONF="${RUNTIME}/php-fpm.conf"
FPM_POOL="${RUNTIME}/php-fpm.pool.conf"

cat > "${NGINX_CONF}" <<EOF
worker_processes  1;

events { worker_connections  1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  sendfile        on;
  keepalive_timeout  65;

  client_max_body_size 128m;

  access_log  ${LOGS}/nginx_access.log;
  error_log   ${LOGS}/nginx_error.log warn;

  server {
    listen ${PORT};
    server_name _;

    root ${APP_DIR}/public;
    index index.php index.html;

    location / {
      try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
      try_files \$uri =404;
      include fastcgi_params;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
      fastcgi_param PATH_INFO \$fastcgi_path_info;
      fastcgi_index index.php;
      fastcgi_pass 127.0.0.1:9000;
    }

    location ~* \.(?:css|js|jpg|jpeg|gif|png|svg|ico|woff2?)$ {
      expires 365d;
      add_header Cache-Control "public, max-age=31536000, immutable";
      try_files \$uri \$uri/ /index.php?\$query_string;
    }
  }
}
EOF

log "Wrote nginx config: ${NGINX_CONF}"

cat > "${FPM_CONF}" <<EOF
[global]
pid = ${RUNTIME}/php-fpm.pid
error_log = ${LOGS}/php-fpm_error.log
daemonize = yes

include=${FPM_POOL}
EOF

cat > "${FPM_POOL}" <<EOF
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
[[ -x "${FPM_BIN}" ]] || FPM_BIN="/usr/sbin/php-fpm"

log "Starting PHP-FPM: ${FPM_BIN}"
"${FPM_BIN}" -y "${FPM_CONF}" -D

log "Starting nginx..."
exec nginx -c "${NGINX_CONF}" -g "daemon off;"
