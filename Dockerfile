FROM invoiceninja/invoiceninja-octane:latest

USER root

RUN set -eux; \
  apk add --no-cache ca-certificates curl unzip

RUN printf "opcache.preload=\nopcache.preload_user=\n" > /usr/local/etc/php/conf.d/zz-disable-preload.ini

RUN mkdir -p /opt/invoiceninja-ro \
 && cp -a /app/. /opt/invoiceninja-ro/

RUN set -eux; \
  curl -fsSL https://raw.githubusercontent.com/roadrunner-server/roadrunner/master/install.sh | sh -s -- -b /usr/local/bin; \
  /usr/local/bin/rr --version

COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ttg-entrypoint.sh"]
