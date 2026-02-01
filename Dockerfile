# Install RoadRunner (rr) without a package manager
RUN set -eux; \
  arch="$(uname -m)"; \
  case "$arch" in \
    x86_64|amd64) RR_ARCH="amd64" ;; \
    aarch64|arm64) RR_ARCH="arm64" ;; \
    *) echo "Unsupported arch: $arch" >&2; exit 1 ;; \
  esac; \
  RR_VER="2024.3.7"; \
  URL="https://github.com/roadrunner-server/roadrunner/releases/download/v${RR_VER}/roadrunner-${RR_VER}-linux-${RR_ARCH}.tar.gz"; \
  echo "Downloading: $URL"; \
  curl -fsSL "$URL" -o /tmp/rr.tgz; \
  tar -xzf /tmp/rr.tgz -C /tmp rr; \
  install -m 0755 /tmp/rr /usr/local/bin/rr; \
  rm -f /tmp/rr.tgz /tmp/rr; \
  /usr/local/bin/rr --version
