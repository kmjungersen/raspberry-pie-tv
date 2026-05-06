# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Raspberry Pi conference-booth kiosk. Boots straight into a looping HTML slideshow on a TV via HDMI. Replaces a laptop running Google Slides. Target hardware is a Pi 3/3B+ at 1080p.

## Architecture

Two unrelated layers live in this repo:

**1. The slideshow** (`index.html`, `styles.css`, `app.js`, `slides/`)
A vanilla static site with no build step. `app.js` fetches `slides/manifest.json` and crossfades through the HTML fragments it lists, using a two-layer DOM (`.slide[data-layer="a|b"]`) for the transition. Slide order, durations, and which files are active are entirely controlled by `manifest.json` &mdash; dropping a file into `slides/` doesn't display it until it's registered there.

The vanilla-JS choice is deliberate: a Pi 3 has 1 GB of RAM and Chromium needs most of it. Don't add a framework, bundler, or `node_modules`.

**2. The Pi bootstrap** (`scripts/`, `systemd/`, `openbox/`)
The full boot chain after `scripts/install.sh` runs once:

```
getty@tty1 (autologin)
  → user shell on tty1
  → ~/.bash_profile execs startx
  → ~/.xinitrc execs openbox-session
  → openbox/autostart (xset off, unclutter, update.sh, run-kiosk.sh)
  → run-kiosk.sh (waits for HTTP server, then while-true loop on chromium)
```

In parallel, two systemd units run as the target user:
- `slideshow-server.service` &mdash; `python3 -m http.server 8080` bound to 127.0.0.1, serving the repo. The kiosk hits `http://localhost:8080/index.html`.
- `slideshow-update.service` + `.timer` &mdash; `git pull --ff-only` on boot and every hour.

### Two architectural pitfalls to avoid

1. **Never point the kiosk at `file://`.** Chromium blocks `fetch()` on `file://` URLs, so the slideshow shell would render but no slides would load. Always go through the local HTTP server. This was an actual bug fixed in commit `a68b8c0`.

2. **`systemd/*.service` files are templates, not final unit files.** `install.sh` `sed`s `@USER@` and `@REPO_DIR@` into them at install time before writing to `/etc/systemd/system/`. Editing the installed copy directly will be lost on the next install. Edit the template in `systemd/` and re-run `install.sh`.

### Update flow

`scripts/update.sh` does `git pull --ff-only` then `pkill chromium`. `run-kiosk.sh`'s outer `while true` loop relaunches Chromium within ~2 s, picking up the new slides. Power-cycle works because the boot-time `slideshow-update.service` pulls before Chromium starts. Crash recovery uses the same loop.

## Common commands

```sh
# Local dev: serve the slideshow and open http://localhost:8080
python3 -m http.server 8080

# Smoke test: every slide referenced in the manifest must fetch (run while the server is up)
node --input-type=module -e '
const base = "http://127.0.0.1:8080";
const m = await (await fetch(base + "/slides/manifest.json")).json();
for (const s of m.slides) {
  const r = await fetch(base + "/slides/" + s.file);
  console.log(r.ok ? "PASS" : "FAIL", s.file, r.status);
}
'

# Sanity check before committing
bash -n scripts/install.sh scripts/run-kiosk.sh scripts/update.sh openbox/autostart
node --check app.js
python3 -c "import json; json.load(open('slides/manifest.json'))"

# On a fresh Pi: full bootstrap (idempotent)
sudo ./scripts/install.sh && sudo reboot

# On a running Pi: pull new slides immediately
~/raspberry-pie-tv/scripts/update.sh
```

There is no test suite, no linter, no build. The "tests" are the smoke-test snippet above plus `bash -n` syntax checks.

## Authoring slides

A new slide is two edits:
1. Add `slides/NN-name.html` containing a single fragment (no `<html>`/`<body>`). Use the `.stack`, `.center`, and `.accent` classes from `styles.css`; sizes are responsive via `clamp()` and assume 1920&times;1080.
2. Add an entry to `slides/manifest.json` with `file` and `durationMs`.

Images go in `slides/assets/` and are referenced as `assets/foo.png` from inside a slide fragment. Keep them under ~2 MB &mdash; Pi 3 RAM is the constraint.

## What lives where

- Tweakable display constants (`--fade-ms`, `--accent`, slide typography) &mdash; `styles.css`
- Default slide duration and manifest path &mdash; constants at the top of `app.js`
- Chromium kiosk flags &mdash; `CHROMIUM_FLAGS` in `scripts/run-kiosk.sh`
- Update frequency &mdash; `OnUnitActiveSec=` in `systemd/slideshow-update.timer`
- Packages installed on the Pi &mdash; `PKGS=(...)` in `scripts/install.sh`
