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
PKGS=(xserver-xorg x11-xserver-utils xinit openbox unclutter git ca-certificates curl python3)
# Modern Raspberry Pi OS / Debian Bookworm ships `chromium`. Older Pi OS ships
# `chromium-browser`. If neither is installable (broken sources, missing
# raspi.list, etc.), fall back to firefox-esr which is in plain Debian main
# and runs acceptably as a kiosk on a Pi 3.
browser_pkg=""
for pkg in chromium chromium-browser firefox-esr; do
  candidate="$(apt-cache policy "$pkg" 2>/dev/null | awk '/Candidate:/ {print $2}')"
  if [ -n "$candidate" ] && [ "$candidate" != "(none)" ]; then
    browser_pkg="$pkg"
    break
  fi
done
if [ -z "$browser_pkg" ]; then
  echo "ERROR: no kiosk-capable browser is installable (tried chromium, chromium-browser, firefox-esr). Run 'sudo apt update' and check your sources." >&2
  exit 1
fi
echo "==> Using browser: $browser_pkg"
PKGS+=("$browser_pkg")
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
# Do NOT restart getty@tty1 here. If install.sh is running from the Pi's
# keyboard (i.e. on tty1), restart kills the current session and aborts
# the rest of the script (e.g. .bash_profile never gets written). The new
# autologin config applies on next reboot, which install.sh tells you to
# do at the end anyway.

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

# --- systemd: local static server for the slideshow --------------------
echo "==> Installing slideshow-server systemd unit"
sed -e "s|@USER@|$TARGET_USER|g" \
    -e "s|@REPO_DIR@|$REPO_DIR|g" \
    "$REPO_DIR/systemd/slideshow-server.service" \
    >/etc/systemd/system/slideshow-server.service

# --- systemd updater unit + timer --------------------------------------
echo "==> Installing systemd updater"
sed -e "s|@USER@|$TARGET_USER|g" \
    -e "s|@REPO_DIR@|$REPO_DIR|g" \
    "$REPO_DIR/systemd/slideshow-update.service" \
    >/etc/systemd/system/slideshow-update.service

install -m 0644 "$REPO_DIR/systemd/slideshow-update.timer" \
  /etc/systemd/system/slideshow-update.timer

systemctl daemon-reload
systemctl enable --now slideshow-server.service
systemctl enable slideshow-update.service
systemctl enable --now slideshow-update.timer

# --- wifi-connect captive-portal AP fallback ---------------------------
# When the Pi can't reach a known wifi, raise an AP so a phone can join
# it, pick the venue's network, and type the password. Saves a keyboard
# trip to the booth.
echo "==> Installing wifi-connect AP fallback"
WC_VERSION="${WC_VERSION:-4.11.84}"
case "$(uname -m)" in
  aarch64|arm64) WC_ARCH=aarch64 ;;
  armv7l|armv6l) WC_ARCH=rpi ;;
  *) WC_ARCH="" ;;
esac

if [ -z "$WC_ARCH" ]; then
  echo "    Skipping wifi-connect: unsupported arch $(uname -m)"
else
  # NetworkManager is required (wifi-connect uses it to manage the radio
  # and persist credentials). Pi OS Bookworm has it by default; on Bullseye
  # it's available but not active.
  apt-get install -y --no-install-recommends network-manager
  systemctl enable --now NetworkManager.service || true

  if [ -x /usr/local/sbin/wifi-connect ]; then
    echo "    /usr/local/sbin/wifi-connect already present; skipping download"
  else
    WC_TARBALL="wifi-connect-v${WC_VERSION}-linux-${WC_ARCH}.tar.gz"
    WC_URL="https://github.com/balena-os/wifi-connect/releases/download/v${WC_VERSION}/${WC_TARBALL}"
    TMPDIR=$(mktemp -d)
    echo "    Downloading $WC_URL"
    if curl -fsSL "$WC_URL" -o "$TMPDIR/wc.tar.gz"; then
      tar -xzf "$TMPDIR/wc.tar.gz" -C "$TMPDIR"
      install -m 0755 "$TMPDIR/wifi-connect" /usr/local/sbin/wifi-connect
      install -d /usr/local/share/wifi-connect
      cp -r "$TMPDIR/ui" /usr/local/share/wifi-connect/
      echo "    Installed wifi-connect v${WC_VERSION} ($WC_ARCH)"
    else
      echo "    WARNING: failed to download wifi-connect; AP fallback won't run." >&2
    fi
    rm -rf "$TMPDIR"
  fi

  if [ -x /usr/local/sbin/wifi-connect ]; then
    chmod +x "$REPO_DIR/scripts/wifi-connect-fallback.sh"
    sed -e "s|@REPO_DIR@|$REPO_DIR|g" \
        "$REPO_DIR/systemd/wifi-connect-fallback.service" \
        >/etc/systemd/system/wifi-connect-fallback.service
    systemctl daemon-reload
    systemctl enable --now wifi-connect-fallback.service
  fi
fi

# --- mark git repo as safe (systemd runs it as root) --------------------
git config --system --add safe.directory "$REPO_DIR" || true

echo
echo "==> Done. Reboot to start the slideshow:"
echo "    sudo reboot"
echo
echo "    If the Pi is offline at next boot, look for a wifi network"
echo "    called 'SRP-Kiosk-Setup' to configure a new venue's wifi."
