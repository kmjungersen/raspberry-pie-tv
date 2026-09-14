#!/usr/bin/env bash
# Print everything relevant to slideshow smoothness on the Pi.
# Run over SSH while the kiosk is up:  ~/raspberry-pie-tv/scripts/diag.sh
set -u
export DISPLAY="${DISPLAY:-:0}"

section() { printf '\n== %s ==\n' "$1"; }

section "Display mode (want 1920x1080 at 60 Hz, marked with *)"
xrandr 2>/dev/null | grep -E 'connected|\*' || echo "xrandr unavailable (is X running?)"

section "Throttling (want throttled=0x0)"
vcgencmd get_throttled 2>/dev/null || echo "vcgencmd unavailable"
vcgencmd measure_temp 2>/dev/null

section "Memory"
free -m

section "Chromium command line (look for --ignore-gpu-blocklist)"
pgrep -af 'chromium' | grep -- '--kiosk' | head -1 | cut -c1-400 || echo "chromium not running"

section "Chromium GPU process (present = GPU compositing is on)"
if pgrep -af 'chromium' | grep -q -- '--type=gpu-process'; then
  echo "gpu-process running"
else
  echo "NO gpu-process: Chromium is painting in software"
fi

section "KMS driver (want vc4-kms-v3d)"
grep -E '^dtoverlay=vc4' /boot/firmware/config.txt /boot/config.txt 2>/dev/null || echo "no vc4 overlay line found in config.txt"

section "Top CPU consumers"
top -bn1 | head -12 | tail -6
