FROM php:8.3-fpm-bookworm

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        nginx \
        supervisor \
        git \
        unzip \
        zip \
        curl \
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

# App paths
ENV APP_DIR=/home/container/app
ENV SRC_DIR=/opt/invoiceninja-ro

RUN mkdir -p ${APP_DIR} ${SRC_DIR}

# Copy Invoice Ninja source (read-only)
COPY invoiceninja/ ${SRC_DIR}/

# Nginx config template
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template

# Supervisor config
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf

# Entrypoint
COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

EXPOSE 8000

CMD ["/usr/local/bin/ttg-entrypoint.sh"]
