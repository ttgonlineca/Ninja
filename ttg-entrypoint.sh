#!/usr/bin/env bash
set -euo pipefail

echo "[TTG] Invoice Ninja starting..."

# ----------------------------
# Core paths
# ----------------------------
APP_DIR="/home/container/app"
RUNTIME="/home/container/.runtime"
LOGS="/home/container/.logs"

mkdir -p "$RUNTIME" "$LOGS"

# ----------------------------
# Port + role
# ----------------------------
PORT="${SERVER_PORT:-${PORT:-8800}}"
ROLE="${ROLE:-${LARAVEL_ROLE:-web}}"
[ "$ROLE" = "app" ] && ROLE="web"

echo "[TTG] PORT: $PORT"
echo "[TTG] ROLE: $ROLE"
echo "[TTG] RUNTIME: $RUNTIME"
echo "[TTG] LOGS: $LOGS"
echo "[TTG] APP_DIR: $APP_DIR"

# ----------------------------
# Ensure we are in app dir
# ----------------------------
cd "$APP_DIR" || { echo "[TTG] ERROR: APP_DIR missing: $APP_DIR"; exit 1; }

# ----------------------------
# Laravel hygiene (safe)
# ----------------------------
php artisan optimize:clear >/dev/null 2>&1 || true
php artisan storage:link >/dev/null 2>&1 || true

# ----------------------------
# Write runtime mime.types (nginx include-safe)
# ----------------------------
cat > "$RUNTIME/mime.types" <<'EOF'
types {
    text/html                             html htm shtml;
    text/css                              css;
    text/xml                              xml;
    image/gif                             gif;
    image/jpeg                            jpeg jpg;
    application/javascript                js;
    application/atom+xml                  atom;
    application/rss+xml                   rss;

    text/mathml                           mml;
    text/plain                            txt;
    text/vnd.sun.j2me.app-descriptor      jad;
    text/vnd.wap.wml                      wml;
    text/x-component                      htc;

    image/avif                            avif;
    image/png                             png;
    image/svg+xml                         svg svgz;
    image/tiff                            tif tiff;
    image/vnd.wap.wbmp                    wbmp;
    image/webp                            webp;
    image/x-icon                          ico;
    image/x-jng                           jng;
    image/x-ms-bmp                        bmp;

    font/woff                             woff;
    font/woff2                            woff2;

    application/java-archive              jar war ear;
    application/json                      json;
    application/mac-binhex40              hqx;
    application/msword                    doc;
    application/pdf                       pdf;
    application/postscript                ps eps ai;
    application/rtf                       rtf;
    application/vnd.apple.mpegurl         m3u8;
    application/vnd.ms-excel              xls;
    application/vnd.ms-fontobject         eot;
    application/vnd.ms-powerpoint         ppt;
    application/vnd.wap.wmlc              wmlc;
    application/vnd.google-earth.kml+xml  kml;
    application/vnd.google-earth.kmz      kmz;
    application/x-7z-compressed           7z;
    application/x-cocoa                   cco;
    application/x-java-archive-diff       jardiff;
    application/x-java-jnlp-file          jnlp;
    application/x-makeself                run;
    application/x-perl                    pl pm;
    application/x-pilot                   prc pdb;
    application/x-rar-compressed          rar;
    application/x-redhat-package-manager  rpm;
    application/x-sea                     sea;
    application/x-shockwave-flash         swf;
    application/x-stuffit                 sit;
    application/x-tcl                     tcl tk;
    application/x-x509-ca-cert            der pem crt;
    application/x-xpinstall               xpi;
    application/xhtml+xml                 xhtml;
    application/xspf+xml                  xspf;
    application/zip                       zip;

    application/octet-stream              bin exe dll;
    application/octet-stream              deb;
    application/octet-stream              dmg;
    application/octet-stream              iso img;
    application/octet-stream              msi msp msm;

    audio/midi                            mid midi kar;
    audio/mpeg                            mp3;
    audio/ogg                             ogg;
    audio/x-m4a                           m4a;
    audio/x-realaudio                     ra;

    video/3gpp                            3gpp 3gp;
    video/mp2t                            ts;
    video/mp4                             mp4;
    video/mpeg                            mpeg mpg;
    video/quicktime                       mov;
    video/webm                            webm;
    video/x-flv                           flv;
    video/x-m4v                           m4v;
    video/x-mng                           mng;
    video/x-ms-asf                        asx asf;
    video/x-ms-wmv                        wmv;
    video/x-msvideo                       avi;
}
EOF

# ----------------------------
# Write runtime fastcgi_params
# ----------------------------
cat > "$RUNTIME/fastcgi_params" <<'EOF'
fastcgi_param  QUERY_STRING       $query_string;
fastcgi_param  REQUEST_METHOD     $request_method;
fastcgi_param  CONTENT_TYPE       $content_type;
fastcgi_param  CONTENT_LENGTH     $content_length;

fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
fastcgi_param  REQUEST_URI        $request_uri;
fastcgi_param  DOCUMENT_URI       $document_uri;
fastcgi_param  DOCUMENT_ROOT      $document_root;
fastcgi_param  SERVER_PROTOCOL    $server_protocol;
fastcgi_param  REQUEST_SCHEME     $scheme;
fastcgi_param  HTTPS              $https if_not_empty;

fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;

fastcgi_param  REMOTE_ADDR        $remote_addr;
fastcgi_param  REMOTE_PORT        $remote_port;
fastcgi_param  SERVER_ADDR        $server_addr;
fastcgi_param  SERVER_PORT        $server_port;
fastcgi_param  SERVER_NAME        $server_name;

fastcgi_param  REDIRECT_STATUS    200;
EOF

# ----------------------------
# PHP-FPM config
# ----------------------------
PHP_FPM_SOCK="/run/php/php-fpm.sock"
mkdir -p /run/php

cat > "$RUNTIME/php-fpm.conf" <<EOF
[global]
daemonize = no
error_log = /proc/self/fd/2

[www]
user = container
group = container
listen = ${PHP_FPM_SOCK}
listen.owner = container
listen.group = container
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
clear_env = no
EOF

# ----------------------------
# nginx config (absolute includes only)
# ----------------------------
cat > "$RUNTIME/nginx.conf" <<EOF
worker_processes 1;

events { worker_connections 1024; }

http {
  include ${RUNTIME}/mime.types;
  default_type application/octet-stream;

  sendfile on;
  keepalive_timeout 65;

  server {
    listen ${PORT};
    server_name _;

    root ${APP_DIR}/public;
    index index.php index.html;

    location / {
      try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
      include ${RUNTIME}/fastcgi_params;
      fastcgi_pass unix:${PHP_FPM_SOCK};
      fastcgi_index index.php;
      fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\. { deny all; }
  }
}
EOF

# ----------------------------
# Role execution
# ----------------------------
case "$ROLE" in
  web)
    echo "[TTG] Starting PHP-FPM..."
    php-fpm8.2 -y "$RUNTIME/php-fpm.conf" -R &

    echo "[TTG] Starting nginx..."
    exec nginx -c "$RUNTIME/nginx.conf" -g "daemon off;"
    ;;

  worker)
    echo "[TTG] Starting queue worker..."
    exec php artisan queue:work --sleep=3 --tries=3 --timeout=90
    ;;

  scheduler)
    echo "[TTG] Starting scheduler loop..."
    while true; do
      php artisan schedule:run --no-interaction || true
      sleep 60
    done
    ;;

  *)
    echo "[TTG] ERROR: Unknown ROLE '$ROLE' (use web|worker|scheduler)"
    exit 1
    ;;
esac
