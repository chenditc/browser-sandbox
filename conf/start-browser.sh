#!/bin/bash
set -e

echo "$(date '+%Y-%m-%d %H:%M:%S') INFO Starting Chrome..."

exec google-chrome-stable \
    --user-data-dir="/home/${USER}/.config/browser" \
    --remote-debugging-port="${CDP_PORT:-9222}" \
    --remote-allow-origins=* \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --disable-backgrounding-occluded-windows \
    --disable-background-timer-throttling \
    --disable-renderer-backgrounding \
    --disable-blink-features=AutomationControlled \
    --disable-infobars \
    --disable-popup-blocking \
    --disable-prompt-on-repost \
    --disable-web-security \
    --disable-site-isolation-trials \
    --disable-features=IsolateOrigins,site-per-process \
    --no-default-browser-check \
    --no-first-run \
    --noerrdialogs \
    --mute-audio \
    --start-maximized \
    --window-position=0,0 \
    --window-size="${DISPLAY_WIDTH:-1280},${DISPLAY_HEIGHT:-1024}" \
    --lang=en-US \
    ${BROWSER_EXTRA_ARGS}
