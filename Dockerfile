# Ubuntu 24.04 LTS (Noble Numbat)
FROM ubuntu@sha256:cd1dba651b3080c3686ecf4e3c4220f026b521fb76978881737d24f200828b2b

ENV DEBIAN_FRONTEND=noninteractive

# Remove default ubuntu user/group (24.04 ships with uid/gid 1000 taken)
RUN userdel -r ubuntu 2>/dev/null || true

# ---------- system packages ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg \
        supervisor nginx \
        tigervnc-standalone-server openbox \
        fonts-liberation fonts-noto-cjk fonts-noto-color-emoji \
        xdg-utils libxss1 libnss3 libatk-bridge2.0-0t64 libgtk-3-0t64 \
        libgbm1 libasound2t64 libx11-xcb1 \
    && rm -rf /var/lib/apt/lists/*

# ---------- Google Chrome stable ----------
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] \
        https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# ---------- websocat (static binary, checksum-verified) ----------
ARG WEBSOCAT_VERSION=1.13.0
ARG WEBSOCAT_SHA256=8f84c57103d33ab73888707041765e0e7e6a43a91fbb6e1828cd5eabc19ae32c
RUN wget -q --retry-connrefused --tries=3 \
        "https://github.com/vi/websocat/releases/download/v${WEBSOCAT_VERSION}/websocat.x86_64-unknown-linux-musl" \
        -O /usr/local/bin/websocat \
    && echo "${WEBSOCAT_SHA256}  /usr/local/bin/websocat" | sha256sum -c - \
    && chmod +x /usr/local/bin/websocat

# ---------- noVNC (checksum-verified) ----------
ARG NOVNC_VERSION=1.4.0
ARG NOVNC_SHA256=89b0354c94ad0b0c88092ec7a08e28086d3ed572f13660bac28d5470faaae9c1
RUN wget -q --retry-connrefused --tries=3 \
        "https://github.com/novnc/noVNC/archive/refs/tags/v${NOVNC_VERSION}.tar.gz" \
        -O /tmp/novnc.tar.gz \
    && echo "${NOVNC_SHA256}  /tmp/novnc.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/novnc.tar.gz -C /opt \
    && mv /opt/noVNC-${NOVNC_VERSION} /opt/novnc \
    && rm /tmp/novnc.tar.gz

# ---------- environment ----------
ENV USER=user \
    USER_UID=1000 \
    USER_GID=1000 \
    DISPLAY=:99.0 \
    DISPLAY_WIDTH=1280 \
    DISPLAY_HEIGHT=1024 \
    DISPLAY_DEPTH=24 \
    VNC_PORT=5900 \
    WEBSOCKET_PORT=6080 \
    CDP_PORT=9222 \
    PUBLIC_PORT=8080 \
    LOG_DIR=/var/log/browser-sandbox \
    XDG_RUNTIME_DIR=/tmp/runtime-user \
    TZ=UTC

# ---------- directories & config files ----------
RUN mkdir -p /etc/opt/chrome/policies/managed \
    && mkdir -p /var/lib/nginx /var/log/nginx "$LOG_DIR"

COPY conf/supervisord.conf  /etc/supervisord.conf
COPY conf/nginx.conf         /etc/nginx/nginx.conf
COPY conf/entrypoint.sh      /opt/entrypoint.sh
COPY conf/start-browser.sh   /opt/start-browser.sh
COPY conf/openbox.xml        /etc/xdg/openbox/rc.xml
COPY conf/preferences.json   /opt/preferences.json
COPY conf/policies.json      /etc/opt/chrome/policies/managed/policies.json

RUN chmod +x /opt/entrypoint.sh /opt/start-browser.sh

EXPOSE ${PUBLIC_PORT}

ENTRYPOINT ["/opt/entrypoint.sh"]
