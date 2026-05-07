#!/usr/bin/env bash
# Launch a browser in kiosk mode and relaunch it if it dies.
# Intended to be called from Openbox autostart.
# Supports Chromium (preferred) and Firefox ESR as a fallback.
set -u

REPO_DIR="${REPO_DIR:-$HOME/raspberry-pie-tv}"
# The slideshow is served over localhost by systemd (slideshow-server.service).
# We go through HTTP (not file://) because browsers block fetch() on file:// URLs.
SLIDESHOW_URL="${SLIDESHOW_URL:-http://localhost:8080/index.html}"

# Wait for the local server to come up (systemd may not have started it yet).
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null "$SLIDESHOW_URL" 2>/dev/null; then break; fi
  sleep 1
done

run_chromium() {
  local bin="$1"

  # Clear Chromium "you didn't shut down cleanly" banner if present.
  local prefs="$HOME/.config/chromium/Default/Preferences"
  if [ -f "$prefs" ]; then
    sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' "$prefs" || true
    sed -i 's/"exit_type":"[^"]*"/"exit_type":"Normal"/' "$prefs" || true
  fi

  local flags=(
    --kiosk
    --incognito
    --disk-cache-size=1
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
    "$bin" "${flags[@]}" "$SLIDESHOW_URL"
    sleep 2
  done
}

run_firefox() {
  local bin="$1"
  local profile="$HOME/.mozilla/kiosk-profile"

  # Build a clean profile every boot, with prefs that suppress the
  # "Firefox didn't shut down properly" dialog and the welcome page.
  mkdir -p "$profile"
  cat >"$profile/user.js" <<'EOF'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("toolkit.startup.max_resumed_crashes", -1);
user_pref("browser.sessionstore.resume_from_crash", false);
user_pref("browser.sessionstore.max_resumed_crashes", -1);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("app.normandy.first_run", false);
user_pref("trailhead.firstrun.didSeeAboutWelcome", true);
user_pref("media.autoplay.default", 0);
user_pref("media.autoplay.blocking_policy", 0);
EOF
  # Fresh profile.ini-friendly name file.
  : >"$profile/times.json"

  while true; do
    "$bin" --kiosk --no-remote --new-instance --profile "$profile" "$SLIDESHOW_URL"
    sleep 2
  done
}

# Pick the first browser that's actually installed.
if command -v chromium-browser >/dev/null 2>&1; then
  run_chromium "$(command -v chromium-browser)"
elif command -v chromium >/dev/null 2>&1; then
  run_chromium "$(command -v chromium)"
elif command -v firefox-esr >/dev/null 2>&1; then
  run_firefox "$(command -v firefox-esr)"
elif command -v firefox >/dev/null 2>&1; then
  run_firefox "$(command -v firefox)"
else
  echo "ERROR: no browser found on PATH (chromium / chromium-browser / firefox-esr / firefox)" >&2
  exit 1
fi
