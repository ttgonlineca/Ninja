FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV APP_DIR=/home/container/app

# ---- Packages ----
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip \
    nginx \
    php8.2 php8.2-cli php8.2-fpm \
    php8.2-mysql php8.2-gd php8.2-curl php8.2-zip php8.2-mbstring php8.2-xml php8.2-bcmath php8.2-intl php8.2-imagick \
    mariadb-client \
    chromium fonts-liberation \
    libnss3 libx11-xcb1 libxcomposite1 libxdamage1 libxrandr2 libgbm1 \
    libasound2 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libgtk-3-0 \
    libxshmfence1 libxss1 xdg-utils \
 && rm -rf /var/lib/apt/lists/*

# ---- Chromium aliases ----
RUN ln -sf /usr/bin/chromium /usr/bin/google-chrome \
 && ln -sf /usr/bin/chromium /usr/bin/chromium-browser

# ---- Pterodactyl user ----
RUN useradd -m -d /home/container -u 999 container

# ---- Composer ----
RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin --filename=composer

# ---- App ----
RUN mkdir -p ${APP_DIR}
WORKDIR ${APP_DIR}
COPY . ${APP_DIR}

# ---- Runtime dirs ----
RUN mkdir -p /home/container/.runtime /home/container/.logs \
 && chown -R container:container /home/container

# ---- Nginx template (THIS IS THE KEY FIX) ----
COPY nginx.conf.template /home/container/nginx.conf.template
RUN chown container:container /home/container/nginx.conf.template

# ---- Entrypoint ----
COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

USER container
EXPOSE 8800
CMD ["/usr/local/bin/ttg-entrypoint.sh"]
