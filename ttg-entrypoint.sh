#!/usr/bin/env bash
set -e

echo "[TTG] Invoice Ninja (FPM) starting..."

ROLE="${ROLE:-app}"
PORT="${PORT:-8000}"
APP_DIR="${APP_DIR:-/home/container/app}"
SRC_DIR="${SRC_DIR:-/opt/invoiceninja-ro}"

echo "[TTG] Role: $ROLE"
echo "[TTG] APP_DIR: $APP_DIR"
echo "[TTG] SRC_DIR: $SRC_DIR"
echo "[TTG] PORT: $PORT"

# ---- Hard dependency checks ----
command -v envsubst >/dev/null 2>&1 || {
  echo "[TTG] FATAL: envsubst missing (install gettext-base in image)"
  exit 127
}

# ---- App bootstrap ----
if [ ! -f "$APP_DIR/artisan" ]; then
  echo "[TTG] First run detected — copying application files"
  cp -R ${SRC_DIR}/* ${APP_DIR}/
fi

cd ${APP_DIR}

# ---- Nginx config ----
envsubst '${PORT}' \
  < /etc/nginx/templates/default.conf.template \
  > /tmp/nginx.conf

cp /tmp/nginx.conf /etc/nginx/conf.d/default.conf

# ---- Permissions ----
chown -R www-data:www-data ${APP_DIR}
chmod -R 755 ${APP_DIR}

# ---- Start services ----
echo "[TTG] Starting Supervisor"
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
