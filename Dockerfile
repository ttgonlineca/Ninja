FROM php:8.3-fpm-bookworm

# ---- system deps ----
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
      libpng-dev \
      libjpeg62-turbo-dev \
      libfreetype6-dev \
      libicu-dev \
      libzip-dev \
      libonig-dev \
      libxml2-dev \
    ; \
    rm -rf /var/lib/apt/lists/*

# ---- php extensions ----
RUN set -eux; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" \
      bcmath \
      exif \
      gd \
      intl \
      mbstring \
      opcache \
      pdo \
      pdo_mysql \
      zip

# Optional but common for Laravel/InvoiceNinja (uncomment if you use Redis)
# RUN pecl install redis && docker-php-ext-enable redis

# ---- create a non-root user that matches Pterodactyl's default uid/gid ----
RUN set -eux; \
    groupadd -g 1000 container || true; \
    useradd -m -u 1000 -g 1000 -s /bin/bash container || true

# ---- php-fpm tuning ----
RUN set -eux; \
    { \
      echo "memory_limit=512M"; \
      echo "upload_max_filesize=128M"; \
      echo "post_max_size=128M"; \
      echo "max_execution_time=300"; \
      echo "opcache.enable=1"; \
      echo "opcache.jit=0"; \
    } > /usr/local/etc/php/conf.d/ttg.ini

# ---- nginx template + supervisor config ----
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ---- app "golden copy" baked into image ----
# Put your Invoice Ninja source in this repo branch (same folder as Dockerfile).
# We'll copy it into /opt/invoiceninja-ro and hydrate it to /home/container/app at runtime.
WORKDIR /opt/invoiceninja-ro
COPY . /opt/invoiceninja-ro

# Remove build-only files so they don't pollute runtime copy (optional)
RUN set -eux; \
    rm -rf /opt/invoiceninja-ro/.git || true; \
    rm -rf /opt/invoiceninja-ro/.github || true

# ---- entrypoint ----
COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

# Nginx will bind to PORT (Pterodactyl provides it)
EXPOSE 8000

# Run as container user (non-root) for safety + Pterodactyl friendliness
USER container

ENTRYPOINT ["/usr/local/bin/ttg-entrypoint.sh"]
