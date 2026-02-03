FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV APP_DIR=/home/container/app

# --------------------------------------------------
# System packages
# --------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    unzip \
    nginx \
    php8.2 \
    php8.2-cli \
    php8.2-fpm \
    php8.2-mysql \
    php8.2-gd \
    php8.2-curl \
    php8.2-zip \
    php8.2-mbstring \
    php8.2-xml \
    php8.2-bcmath \
    php8.2-intl \
    php8.2-imagick \
    mariadb-client \
 && rm -rf /var/lib/apt/lists/*

# --------------------------------------------------
# Create container user (Pterodactyl compatible)
# --------------------------------------------------
RUN useradd -m -d /home/container container

# --------------------------------------------------
# Install Composer
# --------------------------------------------------
RUN curl -sS https://getcomposer.org/installer \
 | php -- --install-dir=/usr/local/bin --filename=composer

# --------------------------------------------------
# App directory
# --------------------------------------------------
RUN mkdir -p ${APP_DIR}
WORKDIR ${APP_DIR}

# --------------------------------------------------
# Copy application
# --------------------------------------------------
COPY . ${APP_DIR}

# --------------------------------------------------
# Permissions
# --------------------------------------------------
RUN chown -R container:container /home/container

# --------------------------------------------------
# Nginx config
# --------------------------------------------------
COPY docker/nginx.conf /etc/nginx/nginx.conf

# --------------------------------------------------
# PHP-FPM config
# --------------------------------------------------
RUN sed -i 's/listen = .*/listen = 9000/' /etc/php/8.2/fpm/pool.d/www.conf

# --------------------------------------------------
# Entrypoint
# --------------------------------------------------
COPY docker/ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

# --------------------------------------------------
# Switch user
# --------------------------------------------------
USER container

EXPOSE 8000 9000

CMD ["/usr/local/bin/ttg-entrypoint.sh"]
