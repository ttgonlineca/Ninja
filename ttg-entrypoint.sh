#!/usr/bin/env bash
set -e

echo "[TTG] Invoice Ninja (FPM) starting..."

PORT="${PORT:-8000}"
APP_DIR="/home/container/app"

echo "[TTG] APP_DIR: $APP_DIR"
echo "[TTG] PORT: $PORT"

# Hard dependency checks
command -v envsubst >/dev/null 2>&1 || {
  echo "[TTG] FATAL: envsubst missing (install gettext-base in image)"
  exit 127
}

# App sanity
if [ ! -f "$APP_DIR/artisan" ]; then
  echo "[TTG] FATAL: Invoice Ninja app not found in $APP_DIR"
  exit 1
fi

# Writable dirs for configs + nginx temps
mkdir -p /home/container/nginx
mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi

# Render nginx.conf into writable path
envsubst '${PORT}' \
  < /etc/nginx/templates/nginx.conf.template \
  > /home/container/nginx/nginx.conf

echo "[TTG] Rendered nginx config: /home/container/nginx/nginx.conf"

# Permissions (best-effort)
chown -R www-data:www-data /home/container || true

echo "[TTG] Starting Supervisor"
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
