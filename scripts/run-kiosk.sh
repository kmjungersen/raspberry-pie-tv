#!/usr/bin/env bash
# Launch Chromium in kiosk mode and relaunch if it dies.
# Intended to be called from Openbox autostart.
set -u

REPO_DIR="${REPO_DIR:-$HOME/raspberry-pie-tv}"
INDEX_URL="file://${REPO_DIR}/index.html"

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
  "$CHROMIUM_BIN" "${CHROMIUM_FLAGS[@]}" "$INDEX_URL"
  sleep 2
done
