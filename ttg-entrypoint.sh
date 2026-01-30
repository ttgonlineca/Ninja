#!/bin/sh
set -eu

echo "[TTG] Invoice Ninja (Octane) starting..."
echo "[TTG] Role: ${LARAVEL_ROLE:-app}"

# Find app directory (Invoice Ninja images vary)
APP_DIR=""
for d in /var/www/html /var/www/app; do
  if [ -d "$d" ]; then APP_DIR="$d"; break; fi
done

if [ -z "$APP_DIR" ]; then
  echo "[TTG] ERROR: Could not find app directory (/var/www/html or /var/www/app)."
  echo "[TTG] Listing /var/www:"
  ls -la /var/www || true
  exit 1
fi

echo "[TTG] Using APP_DIR=$APP_DIR"

# Pterodactyl persistent storage paths (always writable)
mkdir -p /home/container/storage/app/public /home/container/public

# Wire storage to /home/container (safe even if already linked)
# Laravel expects: storage/ and public/storage symlink
if [ -e "$APP_DIR/storage" ] && [ ! -L "$APP_DIR/storage" ]; then
  rm -rf "$APP_DIR/storage"
fi
ln -sfn /home/container/storage "$APP_DIR/storage"

mkdir -p "$APP_DIR/public" || true
ln -sfn /home/container/storage/app/public "$APP_DIR/public/storage"

# Show where writes go
echo "[TTG] $APP_DIR/storage -> $(readlink "$APP_DIR/storage" || true)"
echo "[TTG] $APP_DIR/public/storage -> $(readlink "$APP_DIR/public/storage" || true)"

cd "$APP_DIR"

case "${LARAVEL_ROLE:-app}" in
  worker)
    exec php artisan queue:work --sleep=3 --tries=3 --timeout=90
    ;;
  scheduler)
    exec php artisan schedule:work
    ;;
  app|*)
    exec frankenphp php-cli artisan octane:frankenphp
    ;;
esac
