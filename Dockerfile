FROM invoiceninja/invoiceninja-octane:latest

USER root

COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ttg-entrypoint.sh"]
