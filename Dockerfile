FROM invoiceninja/invoiceninja-octane:latest

USER root

# Disable PHP preload (preload expects /app/preload.php and breaks portable layouts)
RUN printf "opcache.preload=\nopcache.preload_user=\n" > /usr/local/etc/php/conf.d/zz-disable-preload.ini

# Make a read-only "golden copy" of the app for first-run hydration
RUN mkdir -p /opt/invoiceninja-ro \
 && cp -a /app/. /opt/invoiceninja-ro/

# Install RoadRunner (rr) WITHOUT apk/apt
# Note: requires curl + tar to exist in the base image. If curl is missing, see note below.
RUN set -eux; \
  arch="$(uname -m)"; \
  case "$arch" in \
    x86_64|amd64) RR_ARCH="amd64" ;; \
    aarch64|arm64) RR_ARCH="arm64" ;; \
    *) echo "Unsupported arch: $arch" >&2; exit 1 ;; \
  esac; \
  RR_VER="2024.3.7"; \
  URL="https://github.com/roadrunner-server/roadrunner/releases/download/v${RR_VER}/roadrunner-${RR_VER}-linux-${RR_ARCH}.tar.gz"; \
  echo "Downloading: $URL"; \
  curl -fsSL "$URL" -o /tmp/rr.tgz; \
  tar -xzf /tmp/rr.tgz -C /tmp rr; \
  install -m 0755 /tmp/rr /usr/local/bin/rr; \
  rm -f /tmp/rr.tgz /tmp/rr; \
  /usr/local/bin/rr --version

COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ttg-entrypoint.sh"]
