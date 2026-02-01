#!/usr/bin/env bash
set -e

echo "[TTG] Invoice Ninja (FPM) starting..."

PORT="${PORT:-8000}"
APP_DIR="/home/container/app"

echo "[TTG] APP_DIR: $APP_DIR"
echo "[TTG] PORT: $PORT"

command -v envsubst >/dev/null 2>&1 || {
  echo "[TTG] FATAL: envsubst missing (install gettext-base in image)"
  exit 127
}

if [ ! -f "$APP_DIR/artisan" ]; then
  echo "[TTG] FATAL: Invoice Ninja app not found in $APP_DIR"
  exit 1
fi

mkdir -p /home/container/nginx
mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi

# Export PORT so envsubst definitely sees it
export PORT

# Substitute ALL vars (simple + reliable)
envsubst < /etc/nginx/templates/nginx.conf.template > /home/container/nginx/nginx.conf

# Hard check so we don’t launch nginx with a broken config
if ! grep -qE 'listen[[:space:]]+[0-9]+' /home/container/nginx/nginx.conf; then
  echo "[TTG] FATAL: nginx.conf render failed (listen directive missing/invalid)"
  echo "[TTG] Dumping rendered listen lines:"
  grep -n 'listen' /home/container/nginx/nginx.conf || true
  exit 1
fi

echo "[TTG] Rendered nginx config: /home/container/nginx/nginx.conf"

chmod -R a+rX /home/container/nginx /home/container/public /home/container/storage 2>/dev/null || true

echo "[TTG] Starting Supervisor"
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
