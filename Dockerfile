# TTG - Invoice Ninja Pterodactyl image (nginx + php-fpm + supervisor)
# Everything persistent lives under /home/container

FROM php:8.3-fpm

ENV DEBIAN_FRONTEND=noninteractive

# --- OS packages + nginx + supervisor + deps for PHP extensions (including GD) ---
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
      # PHP extension build deps
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
    php -m | grep -qi '^gd$' || (php -m; echo 'ERROR: PHP gd extension missing' >&2; exit 1)

# --- Create the container user (matches your Ptero UID/GID pattern) ---
RUN set -eux; \
    groupadd -g 987 pterodactyl || true; \
    useradd -m -u 999 -g 987 -d /home/container -s /bin/bash container || true; \
    mkdir -p /home/container; \
    chown -R 999:987 /home/container

# --- Bake app source into the image read-only ---
WORKDIR /opt/invoiceninja-ro
COPY ./invoiceninja/ /opt/invoiceninja-ro/

# --- Config + entrypoint ---
COPY ./supervisord.conf /etc/supervisor/supervisord.conf
COPY ./nginx.conf.template /opt/ttg/nginx.conf.template
COPY ./ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

EXPOSE 8800

USER 999:987
WORKDIR /home/container

ENTRYPOINT ["/usr/local/bin/ttg-entrypoint.sh"]
