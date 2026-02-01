FROM invoiceninja/invoiceninja-octane:latest

USER root

# Disable PHP preload (preload expects /app/preload.php and breaks our /home/container app layout)
RUN printf "opcache.preload=\nopcache.preload_user=\n" > /usr/local/etc/php/conf.d/zz-disable-preload.ini

# Make a read-only "golden copy" of the app for first-run hydration
RUN mkdir -p /opt/invoiceninja-ro \
 && cp -a /app/. /opt/invoiceninja-ro/

# Install RoadRunner (rr) using official installer
RUN set -eux; \
  curl -fsSL https://raw.githubusercontent.com/roadrunner-server/roadrunner/master/install.sh | sh -s -- -b /usr/local/bin; \
  rr --version

COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ttg-entrypoint.sh"]
