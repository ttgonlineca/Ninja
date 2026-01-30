# TTG Invoice Ninja Pterodactyl Image
# Goal: run invoiceninja/invoiceninja-octane with ALL writable data in /home/container
# Works even if the node runs containers with a read-only root filesystem.
FROM invoiceninja/invoiceninja-octane:latest

USER root

# Pre-wire Laravel paths to Pterodactyl persistent storage.
# /home/container is the only guaranteed writable path in Pterodactyl.
RUN rm -rf /var/www/html/storage \
    && ln -s /home/container/storage /var/www/html/storage \
    && rm -f /var/www/html/public/storage \
    && ln -s /home/container/storage/app/public /var/www/html/public/storage

COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/ttg-entrypoint.sh"]
