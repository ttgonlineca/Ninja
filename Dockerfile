FROM php:8.3-fpm-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        nginx \
        supervisor \
        curl \
        unzip \
        zip \
        ca-certificates \
        gettext-base \
        libpng-dev \
        libonig-dev \
        libxml2-dev \
        libzip-dev \
        libicu-dev \
    ; \
    docker-php-ext-install \
        pdo \
        pdo_mysql \
        zip \
        intl \
        bcmath \
        opcache \
    ; \
    rm -rf /var/lib/apt/lists/*

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Templates + supervisor config (repo root)
RUN mkdir -p /etc/nginx/templates
COPY nginx.conf.template /etc/nginx/templates/nginx.conf.template
COPY supervisord.conf /etc/supervisor/supervisord.conf

# Entrypoint
COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

EXPOSE 8000
CMD ["/usr/local/bin/ttg-entrypoint.sh"]
