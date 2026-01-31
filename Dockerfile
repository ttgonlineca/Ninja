FROM invoiceninja/invoiceninja-octane:latest

USER root

# Keep a read-only golden copy for first-run hydration
RUN mkdir -p /opt/invoiceninja-ro \
 && cp -a /app/. /opt/invoiceninja-ro/

# Disable PHP preload (it expects /app/preload.php before entrypoint runs)
RUN printf "opcache.preload=\nopcache.preload_user=\n" > /usr/local/etc/php/conf.d/zz-disable-preload.ini

COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ttg-entrypoint.sh"]
