#!/usr/bin/env bash
# Launch Chromium in kiosk mode and relaunch if it dies.
# Intended to be called from Openbox autostart.
set -u

REPO_DIR="${REPO_DIR:-$HOME/raspberry-pie-tv}"
# The slideshow is served over localhost by systemd (slideshow-server.service).
# We go through HTTP (not file://) because Chromium blocks fetch() on file:// URLs.
SLIDESHOW_URL="${SLIDESHOW_URL:-http://localhost:8080/index.html}"

# Wait for the local server to come up (systemd may not have started it yet).
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null "$SLIDESHOW_URL" 2>/dev/null; then break; fi
  sleep 1
done

PROFILE_DIR="$HOME/.config/chromium"
PREFS="$PROFILE_DIR/Default/Preferences"

# Clear Chromium "you didn't shut down cleanly" dialog if present.
if [ -f "$PREFS" ]; then
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' "$PREFS" || true
  sed -i 's/"exit_type":"[^"]*"/"exit_type":"Normal"/' "$PREFS" || true
fi

# Pick whichever Chromium binary is installed.
CHROMIUM_BIN="$(command -v chromium-browser || command -v chromium || true)"
if [ -z "$CHROMIUM_BIN" ]; then
  echo "chromium not found on PATH" >&2
  exit 1
fi

CHROMIUM_FLAGS=(
  --kiosk
  --noerrdialogs
  --disable-infobars
  --disable-session-crashed-bubble
  --disable-translate
  --disable-features=TranslateUI
  --check-for-update-interval=604800
  --overscroll-history-navigation=0
  --disable-pinch
  --autoplay-policy=no-user-gesture-required
  --password-store=basic
  --no-first-run
  --start-fullscreen
  --window-position=0,0
)

while true; do
  "$CHROMIUM_BIN" "${CHROMIUM_FLAGS[@]}" "$SLIDESHOW_URL"
  sleep 2
done
