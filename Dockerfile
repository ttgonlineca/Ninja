FROM invoiceninja/invoiceninja-octane:latest

USER root

# Make a read-only “golden copy” of the app inside the image,
# then remove /app so we never accidentally run from it at runtime.
RUN mkdir -p /opt/invoiceninja-ro \
 && cp -a /app/. /opt/invoiceninja-ro/ \
 && rm -rf /app

COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ttg-entrypoint.sh"]
