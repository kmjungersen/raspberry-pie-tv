#!/usr/bin/env bash
# Watchdog that raises a captive-portal AP when the Pi has no wifi.
# When connected: just sleep. When offline: launch balena-os/wifi-connect
# so a phone can join the Pi's AP, pick the venue's wifi, and type the
# password. wifi-connect saves credentials via NetworkManager, exits, and
# we go back to sleeping until the connection drops again.
set -u

PORTAL_SSID="${PORTAL_SSID:-SRP-Kiosk-Setup}"
PORTAL_PASSPHRASE="${PORTAL_PASSPHRASE:-}"
ACTIVITY_TIMEOUT="${ACTIVITY_TIMEOUT:-600}"
UI_DIR="${UI_DIR:-/usr/local/share/wifi-connect/ui}"
CHECK_INTERVAL=60
COOLOFF=30

is_connected() {
  # NetworkManager reports "connected" when at least one device has a
  # default route. "connected (limited)" still counts: the Pi reached
  # *something* and a captive portal isn't our problem to solve.
  local state
  state=$(nmcli -t -f STATE g 2>/dev/null) || return 1
  case "$state" in
    connected|"connected (limited)"|"connected (site only)") return 0 ;;
    *) return 1 ;;
  esac
}

while true; do
  if is_connected; then
    sleep "$CHECK_INTERVAL"
    continue
  fi

  echo "No connection. Starting wifi-connect captive portal '${PORTAL_SSID}'..."
  args=(
    --portal-ssid "$PORTAL_SSID"
    --activity-timeout "$ACTIVITY_TIMEOUT"
    --ui-directory "$UI_DIR"
  )
  if [ -n "$PORTAL_PASSPHRASE" ]; then
    args+=(--portal-passphrase "$PORTAL_PASSPHRASE")
  fi
  /usr/local/sbin/wifi-connect "${args[@]}" || true

  # Whether we connected or timed out, wait a beat before re-checking so
  # we don't spin if NetworkManager is mid-reconfigure.
  sleep "$COOLOFF"
done
