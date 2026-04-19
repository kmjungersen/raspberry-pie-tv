#!/usr/bin/env bash
# Pull the latest slides from git and ask Chromium to reload.
# Safe to run at any time; no-ops if there's nothing to update.
set -u

REPO_DIR="${REPO_DIR:-$HOME/raspberry-pie-tv}"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "No git repo at $REPO_DIR" >&2
  exit 0
fi

cd "$REPO_DIR" || exit 0

# Fast-forward only; never auto-merge local edits.
if ! git pull --ff-only --quiet; then
  echo "git pull failed (offline or non-ff); keeping current slides." >&2
  exit 0
fi

# Nudge Chromium to reload by killing it; run-kiosk.sh will relaunch in ~2s.
if pgrep -x chromium-browser >/dev/null 2>&1; then
  pkill -x chromium-browser || true
elif pgrep -x chromium >/dev/null 2>&1; then
  pkill -x chromium || true
fi
