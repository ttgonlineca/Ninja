#!/bin/sh
set -eu

echo "[TTG] Invoice Ninja (FPM) starting..."

PORT="${PORT:-8800}"
echo "[TTG] PORT: ${PORT}"

# Writable paths in Pterodactyl
RUNTIME_DIR="/home/container/.runtime"
LOG_DIR="/home/container/.logs"
mkdir -p "$RUNTIME_DIR" "$LOG_DIR" /tmp /run/php

# ---------- Build a self-contained PHP-FPM config (no /var/log, no /etc writes) ----------
FPM_CONF="${RUNTIME_DIR}/php-fpm.conf"
FPM_POOL="${RUNTIME_DIR}/www.conf"

cat > "$FPM_CONF" <<EOF
[global]
pid = /run/php/php-fpm.pid
error_log = ${LOG_DIR}/php-fpm.log
log_level = notice

include=${FPM_POOL}
EOF

cat > "$FPM_POOL" <<'EOF'
[www]
user = container
group = container

listen = 9000
listen.allowed_clients = 127.0.0.1

pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3

catch_workers_output = yes
clear_env = no
EOF

# ---------- Start PHP-FPM using our config ----------
FPM_BIN="/usr/sbin/php-fpm8.2"
[ -x "$FPM_BIN" ] || FPM_BIN="/usr/sbin/php-fpm"

echo "[TTG] Starting PHP-FPM with -y ${FPM_CONF} (log: ${LOG_DIR}/php-fpm.log)..."
"$FPM_BIN" -y "$FPM_CONF" -D

# ---------- Start nginx ----------
echo "[TTG] Starting nginx..."
exec nginx -g "daemon off;"
