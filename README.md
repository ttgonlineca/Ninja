# TTG Invoice Ninja (Pterodactyl) Image

This repo builds a TTG-friendly Invoice Ninja image for Pterodactyl.

## Why this exists
The upstream `invoiceninja/invoiceninja-octane` image writes to:
- `/var/www/html/storage`
- `/var/www/html/public/storage`

Some Pterodactyl/Wings setups run containers with a **read-only root filesystem**.
That causes the upstream image to crash at boot.

## What we changed
We pre-wire writes to Pterodactyl persistent storage:
- `/var/www/html/storage` -> `/home/container/storage`
- `/var/www/html/public/storage` -> `/home/container/storage/app/public`

`/home/container` is the only guaranteed writable path and is included in Pterodactyl backups/migrations.

## How to use
Image:
- `ghcr.io/ttgonlineca/invoiceninja-ptero:latest`

Roles:
- `LARAVEL_ROLE=app` (web)
- `LARAVEL_ROLE=worker` (queue)
- `LARAVEL_ROLE=scheduler` (optional)

Start order:
1) Redis
2) Invoice Ninja app
3) Worker
