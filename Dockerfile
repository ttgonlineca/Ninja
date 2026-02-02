# TTG - Invoice Ninja Pterodactyl image (nginx + php-fpm + supervisor)
# Goal: run as non-root, persist everything under /home/container

FROM php:8.3-fpm

ENV DEBIAN_FRONTEND=noninteractive

# --- OS packages + nginx + supervisor + build deps for PHP extensions ---
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      nginx \
      supervisor \
      unzip \
      zip \
      gettext-base \
      procps \
      tzdata \
      \
      # php ext deps
      libzip-dev \
      libicu-dev \
      libpng-dev \
      libjpeg62-turbo-dev \
      libfreetype6-dev \
      libonig-dev \
      libxml2-dev \
      libexif-dev \
    ; \
    rm -rf /var/lib/apt/lists/*

# --- PHP extensions ---
RUN set -eux; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" \
      bcmath \
      exif \
      gd \
      intl \
      mbstring \
      pdo_mysql \
      zip \
    ; \
    # HARD FAIL if gd didn't load (prevents "it built but not really" pain)
    php -m | grep -qi '^gd$' || (php -m; echo 'ERROR: PHP gd extension missing' >&2; exit 1)

# Optional: if you want native php redis extension later, uncomment
# RUN pecl install redis && docker-php-ext-enable redis

# --- create Pterodactyl-ish user (UID/GID match what you’ve been using: 999/987) ---
RUN set -eux; \
    groupadd -g 987 pterodactyl || true; \
    useradd -m -u 999 -g 987 -d /home/container -s /bin/bash container || true; \
    mkdir -p /home/container; \
    chown -R 999:987 /home/container

# --- app source baked read-only into image ---
WORKDIR /opt/invoiceninja-ro

# IMPORTANT:
# Your repo must contain the Invoice Ninja app code inside ./invoiceninja/
# (If yours is in a different folder, change the COPY line.)
COPY ./invoiceninja/ /opt/invoiceninja-ro/

# supervisor + templates + entrypoint from your repo
COPY ./supervisord.conf /etc/supervisor/supervisord.conf
COPY ./nginx.conf.template /opt/ttg/nginx.conf.template
COPY ./ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh

RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

EXPOSE 8800

USER 999:987
WORKDIR /home/container

ENTRYPOINT ["/usr/local/bin/ttg-entrypoint.sh"]
