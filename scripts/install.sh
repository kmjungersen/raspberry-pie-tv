#!/usr/bin/env bash
# One-shot bootstrap for a fresh Raspberry Pi OS Lite install.
# Installs X + Openbox + Chromium, enables tty1 autologin, wires up
# Openbox autostart to launch the kiosk, and installs a systemd unit
# that pulls slide updates from git on boot.
#
# Idempotent: re-running it is safe.
#
# Usage:  sudo ./scripts/install.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo $0" >&2
  exit 1
fi

# --- figure out the target user (the human who cloned the repo) ---------
TARGET_USER="${SUDO_USER:-pi}"
if ! id "$TARGET_USER" >/dev/null 2>&1; then
  echo "User '$TARGET_USER' does not exist. Re-run with: sudo -u <your-user> ... or create the user first." >&2
  exit 1
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Target user:  $TARGET_USER"
echo "==> Target home:  $TARGET_HOME"
echo "==> Repo dir:     $REPO_DIR"

# --- packages -----------------------------------------------------------
echo "==> Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
# chromium-browser exists on Raspberry Pi OS; chromium is the Debian name.
# Install whichever resolves.
PKGS=(xserver-xorg x11-xserver-utils xinit openbox unclutter git ca-certificates)
if apt-cache show chromium-browser >/dev/null 2>&1; then
  PKGS+=(chromium-browser)
else
  PKGS+=(chromium)
fi
apt-get install -y --no-install-recommends "${PKGS[@]}"

# --- tty1 autologin -----------------------------------------------------
echo "==> Enabling tty1 autologin for $TARGET_USER"
install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
cat >/etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
EOF
systemctl daemon-reload
systemctl restart getty@tty1.service || true

# --- ~/.bash_profile: startx on tty1 ------------------------------------
echo "==> Writing $TARGET_HOME/.bash_profile"
cat >"$TARGET_HOME/.bash_profile" <<'EOF'
# Auto-start the slideshow kiosk on tty1.
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx -- -nocursor
fi
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.bash_profile"

# --- ~/.xinitrc: launch openbox ----------------------------------------
cat >"$TARGET_HOME/.xinitrc" <<'EOF'
exec openbox-session
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xinitrc"

# --- ~/.config/openbox/autostart: the kiosk -----------------------------
echo "==> Writing Openbox autostart"
install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" \
  "$TARGET_HOME/.config" \
  "$TARGET_HOME/.config/openbox"

install -m 0644 -o "$TARGET_USER" -g "$TARGET_USER" \
  "$REPO_DIR/openbox/autostart" \
  "$TARGET_HOME/.config/openbox/autostart"

# Expose REPO_DIR to the autostart script.
if ! grep -q "^REPO_DIR=" "$TARGET_HOME/.config/openbox/autostart"; then
  sed -i "1a REPO_DIR=\"$REPO_DIR\"" "$TARGET_HOME/.config/openbox/autostart"
fi

# --- make scripts executable -------------------------------------------
chmod +x "$REPO_DIR/scripts/install.sh" \
         "$REPO_DIR/scripts/update.sh" \
         "$REPO_DIR/scripts/run-kiosk.sh"

# --- systemd updater unit + timer --------------------------------------
echo "==> Installing systemd updater"
sed -e "s|@USER@|$TARGET_USER|g" \
    -e "s|@REPO_DIR@|$REPO_DIR|g" \
    "$REPO_DIR/systemd/slideshow-update.service" \
    >/etc/systemd/system/slideshow-update.service

install -m 0644 "$REPO_DIR/systemd/slideshow-update.timer" \
  /etc/systemd/system/slideshow-update.timer

systemctl daemon-reload
systemctl enable slideshow-update.service
systemctl enable --now slideshow-update.timer

# --- mark git repo as safe (systemd runs it as root) --------------------
git config --system --add safe.directory "$REPO_DIR" || true

echo
echo "==> Done. Reboot to start the slideshow:"
echo "    sudo reboot"
