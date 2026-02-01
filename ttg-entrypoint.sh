#!/usr/bin/env bash
set -e

echo "[TTG] Invoice Ninja (FPM) starting..."

PORT="${SERVER_PORT:-${PORT:-8000}}"
APP_DIR="/home/container/app"
ENV_FILE="${APP_DIR}/.env"

echo "[TTG] APP_DIR: $APP_DIR"
echo "[TTG] PORT: $PORT"

if [ ! -f "$APP_DIR/artisan" ]; then
  echo "[TTG] FATAL: Invoice Ninja app not found in $APP_DIR"
  exit 1
fi

# Ensure writable dirs
mkdir -p /home/container/nginx
mkdir -p /tmp/nginx/client_body /tmp/nginx/proxy /tmp/nginx/fastcgi /tmp/nginx/uwsgi /tmp/nginx/scgi

# Ensure .env exists (Invoice Ninja should ship one, but be defensive)
if [ ! -f "$ENV_FILE" ]; then
  if [ -f "${APP_DIR}/.env.example" ]; then
    cp "${APP_DIR}/.env.example" "$ENV_FILE"
    echo "[TTG] Created .env from .env.example"
  else
    touch "$ENV_FILE"
    echo "[TTG] Created empty .env"
  fi
fi

# If APP_KEY variable exists in Pterodactyl, ensure it's set in .env (only if missing/blank)
if [ -n "${APP_KEY:-}" ]; then
  if ! grep -q '^APP_KEY=' "$ENV_FILE"; then
    echo "APP_KEY=${APP_KEY}" >> "$ENV_FILE"
    echo "[TTG] Wrote APP_KEY into .env"
  else
    # Replace blank key only
    if grep -q '^APP_KEY=$' "$ENV_FILE"; then
      sed -i "s|^APP_KEY=$|APP_KEY=${APP_KEY}|" "$ENV_FILE"
      echo "[TTG] Filled blank APP_KEY in .env"
    else
      echo "[TTG] APP_KEY already present in .env (not changing)"
    fi
  fi
else
  echo "[TTG] WARN: APP_KEY env var not set in Pterodactyl"
fi

# Non-root safe perms (Laravel needs these writable)
chmod -R a+rwX "$APP_DIR/storage" "$APP_DIR/bootstrap/cache" 2>/dev/null || true

# Clear cached config (so .env changes are used)
cd "$APP_DIR"
php artisan config:clear >/dev/null 2>&1 || true
php artisan cache:clear  >/dev/null 2>&1 || true

# Render nginx config (PORT only) without touching nginx $vars
sed "s/__PORT__/${PORT}/g" \
  /etc/nginx/templates/nginx.conf.template \
  > /home/container/nginx/nginx.conf

echo "[TTG] Rendered nginx config: /home/container/nginx/nginx.conf"

echo "[TTG] Starting Supervisor"
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
