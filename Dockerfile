FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV APP_DIR=/home/container/app

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

RUN ln -sf /usr/bin/chromium /usr/bin/google-chrome \
 && ln -sf /usr/bin/chromium /usr/bin/chromium-browser

RUN useradd -m -d /home/container -u 999 container

RUN curl -sS https://getcomposer.org/installer | php -- \
    --install-dir=/usr/local/bin --filename=composer

# ---- App ----
RUN mkdir -p ${APP_DIR}
WORKDIR ${APP_DIR}
COPY . ${APP_DIR}

# ---- Runtime dirs ----
RUN mkdir -p /home/container/.runtime /home/container/.logs \
 && chown -R container:container /home/container

# ---- Put template somewhere that survives Pterodactyl volume mounts ----
# 1) Inside app (persisted)
# 2) Also in /opt/ttg/templates (not mounted, good fallback)
RUN mkdir -p /opt/ttg/templates
COPY nginx.conf.template ${APP_DIR}/nginx.conf.template
COPY nginx.conf.template /opt/ttg/templates/nginx.conf.template

RUN chown container:container ${APP_DIR}/nginx.conf.template \
 && chmod 644 ${APP_DIR}/nginx.conf.template \
 && chmod 644 /opt/ttg/templates/nginx.conf.template

COPY ttg-entrypoint.sh /usr/local/bin/ttg-entrypoint.sh
RUN chmod +x /usr/local/bin/ttg-entrypoint.sh

USER container
EXPOSE 8800
CMD ["/usr/local/bin/ttg-entrypoint.sh"]
