#!/usr/bin/env bash
set -e

echo "[TTG] Invoice Ninja (FPM) starting..."

PORT="${PORT:-8000}"
APP_DIR="/home/container/app"

echo "[TTG] APP_DIR: $APP_DIR"
echo "[TTG] PORT: $PORT"

# Hard dependency check
command -v envsubst >/dev/null 2>&1 || {
  echo "[TTG] FATAL: envsubst missing (install gettext-base in image)"
  exit 127
}

# Sanity check app layout
if [ ! -f "$APP_DIR/artisan" ]; then
  echo "[TTG] FATAL: Invoice Ninja app not found in $APP_DIR"
  exit 1
fi

# Render nginx config
envsubst '${PORT}' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/conf.d/default.conf

# Permissions (don’t fight Pterodactyl, just ensure access)
chown -R www-data:www-data /home/container || true

echo "[TTG] Starting Supervisor"
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
