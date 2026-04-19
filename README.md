# raspberry-pie-tv

A Raspberry Pi that boots straight into a looping HTML slideshow on a TV.
Built to replace the "laptop plugged into HDMI running Google Slides" setup
at conferences. Plug it in, it starts. Update slides by editing this repo
and pushing &mdash; the Pi pulls on boot and hourly.

Target hardware: **Raspberry Pi 3 / 3B+** with HDMI to a 1080p TV.
Works on Pi 4 / 5 too.

---

## What it is

- `index.html` + `styles.css` + `app.js` &mdash; a plain static site that
  crossfades through HTML slides on a timer. No build step, no Node,
  no framework.
- `slides/` &mdash; one HTML fragment per slide, plus `manifest.json`
  listing the order and per-slide duration.
- `scripts/install.sh` &mdash; one-shot bootstrap for a fresh Pi.
- `scripts/run-kiosk.sh` &mdash; launches Chromium in kiosk mode and
  relaunches it if it crashes.
- `scripts/update.sh` &mdash; `git pull` + reload the browser.
- `systemd/slideshow-update.{service,timer}` &mdash; pulls new slides on
  boot and every hour.
- `openbox/autostart` &mdash; disables screen blanking, hides the cursor,
  starts the kiosk.

---

## First-time Pi setup

### 1. Flash the SD card

Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/):

- **OS:** Raspberry Pi OS Lite (64-bit, Bookworm). "Lite" = no desktop,
  boots faster, leaves more RAM for Chromium.
- Click the gear icon / "Edit Settings" and pre-configure:
  - **Hostname:** something memorable (`slideshow-pi`)
  - **Username + password:** the user that will own the slideshow
  - **WiFi** (SSID + password for your home/office network so you can
    test before the conference)
  - **Enable SSH** with password auth

Eject, put the SD card in the Pi, plug the Pi into the TV via HDMI,
plug in power.

### 2. SSH in

```sh
ssh <user>@<hostname>.local
```

### 3. Clone and install

```sh
git clone https://github.com/kmjungersen/raspberry-pie-tv.git ~/raspberry-pie-tv
cd ~/raspberry-pie-tv
sudo ./scripts/install.sh
sudo reboot
```

The Pi will come back up directly into the slideshow. That's it.

---

## Updating slides between events

### Option A: edit in git, let the Pi pull

1. Edit slides in `slides/` locally. Push to `main`.
2. Next time the Pi boots, or within an hour of it being online, it
   picks up the changes automatically.
3. Want it immediate? SSH in and run:

   ```sh
   ~/raspberry-pie-tv/scripts/update.sh
   ```

### Option B: power-cycle

Unplug, replug. On boot it runs `git pull` before the browser starts.

---

## Authoring slides

Each slide is an HTML fragment in `slides/`. The root styles in
`styles.css` provide `h1`, `h2`, `p`, `ul` sized for a 1080p TV plus a
few helpers:

- `.stack` &mdash; vertical flex column with gap
- `.center` &mdash; center-aligned text
- `.accent` &mdash; colored (orange by default, change in `styles.css`)

Example:

```html
<div class="stack center">
  <h1>Hello <span class="accent">World</span></h1>
  <p>Subtitle here</p>
</div>
```

Register the slide in `slides/manifest.json`:

```json
{
  "slides": [
    { "file": "01-title.html",   "durationMs": 8000 },
    { "file": "02-what.html",    "durationMs": 10000 }
  ]
}
```

Images go in `slides/assets/` and reference them with relative paths:

```html
<img src="assets/logo.png" alt="" />
```

Keep images under ~2 MB each &mdash; the Pi 3 only has 1 GB of RAM.

---

## Tweaks

- **Slide duration:** per-slide in `manifest.json`. Default 8 s if missing.
- **Fade speed:** `--fade-ms` in `styles.css`.
- **Accent color:** `--accent` in `styles.css`.
- **Update frequency:** edit `OnUnitActiveSec=1h` in
  `systemd/slideshow-update.timer`.

---

## Troubleshooting

Slideshow didn't start &mdash; SSH in and look at logs:

```sh
journalctl -u slideshow-update.service --no-pager -n 50
systemctl status getty@tty1
cat /tmp/slideshow-update.log   # the Openbox-triggered pull
```

Chromium crashing on startup &mdash; check for the "restore session"
dialog, which `run-kiosk.sh` clears via `Preferences`. If it persists,
delete `~/.config/chromium` and reboot.

Screen still blanks &mdash; some HDMI monitors ignore DPMS. Set
`consoleblank=0` in `/boot/firmware/cmdline.txt` and reboot.

Slides won't render &mdash; open Chromium dev tools remotely with
`--remote-debugging-port=9222` added to `run-kiosk.sh`, then `ssh -L
9222:localhost:9222` from your laptop and visit
`http://localhost:9222`.
