FROM invoiceninja/invoiceninja-octane:latest

USER root

# Store a read-only golden copy of the app
RUN mkdir -p /opt/invoiceninja-ro \
 && cp -a /app/. /opt/invoiceninja-ro/

# Ensure /app exists for PHP preload (base image expects /app/preload.php)
# Keep it minimal: just preload.php copied from the golden source
RUN rm -rf /app \
 && mkdir -p /app \
 && cp -a /opt/invoiceninja-ro/preload.php /app/preload.php

COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ttg-entrypoint.sh"]
