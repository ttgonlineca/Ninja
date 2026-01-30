#!/bin/sh
set -eu

echo "[TTG] Invoice Ninja (Octane) starting..."
echo "[TTG] Role: ${LARAVEL_ROLE:-app}"

# Pterodactyl persistent storage paths (always writable).
mkdir -p /home/container/storage/app/public /home/container/public

# Sanity: show where writes will go.
if [ -L /var/www/html/storage ]; then
  echo "[TTG] /var/www/html/storage -> $(readlink /var/www/html/storage)"
fi
if [ -L /var/www/html/public/storage ]; then
  echo "[TTG] /var/www/html/public/storage -> $(readlink /var/www/html/public/storage)"
fi

cd /var/www/html

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
