#!/usr/bin/env bash
set -e

echo "[TTG] Invoice Ninja (FPM) starting..."

PORT="${PORT:-8000}"
APP_DIR="/home/container/app"

echo "[TTG] APP_DIR: $APP_DIR"
echo "[TTG] PORT: $PORT"

# App sanity
if [ ! -f "$APP_DIR/artisan" ]; then
  echo "[TTG] FATAL: Invoice Ninja app not found in $APP_DIR"
  exit 1
fi

# Writable dirs for configs + nginx temps
mkdir -p /home/container/nginx
mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi

# Render nginx.conf into writable path WITHOUT touching nginx $vars
sed "s/__PORT__/${PORT}/g" \
  /etc/nginx/templates/nginx.conf.template \
  > /home/container/nginx/nginx.conf

echo "[TTG] Rendered nginx config: /home/container/nginx/nginx.conf"

# Quick safety check: confirm listen is numeric
if ! grep -qE 'listen[[:space:]]+[0-9]+' /home/container/nginx/nginx.conf; then
  echo "[TTG] FATAL: nginx.conf render failed (listen invalid)"
  grep -nE 'listen' /home/container/nginx/nginx.conf || true
  exit 1
fi

# Best-effort readable perms (no chown in ptero)
chmod -R a+rX /home/container/nginx /home/container/public /home/container/storage 2>/dev/null || true

echo "[TTG] Starting Supervisor"
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
