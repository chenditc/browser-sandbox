#!/bin/bash
set -e

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') INFO $*"; }

log "Creating user $USER (uid=$USER_UID, gid=$USER_GID)..."
if ! getent group "$USER_GID" >/dev/null 2>&1; then
    groupadd --gid "$USER_GID" "$USER"
fi
id -u "$USER" >/dev/null 2>&1 || useradd --uid "$USER_UID" --gid "$USER_GID" --shell /bin/bash --create-home "$USER"

log "Setting up X11..."
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
chown "$USER" /tmp/.X11-unix/

log "Creating directories..."
mkdir -p "$LOG_DIR" "$XDG_RUNTIME_DIR" /var/lib/nginx
chmod 1777 "$LOG_DIR"
chown "$USER" "$LOG_DIR" "$XDG_RUNTIME_DIR"

log "Copying browser preferences..."
su "$USER" -c '
    touch "$HOME/.Xauthority"
    mkdir -p "$HOME/.config/browser/Default"
    cp /opt/preferences.json "$HOME/.config/browser/Default/Preferences"
'

log "Starting supervisord..."
exec /usr/bin/supervisord -n -c /etc/supervisord.conf
