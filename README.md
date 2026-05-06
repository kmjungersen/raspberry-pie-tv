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
- `systemd/slideshow-server.service` &mdash; tiny static server on
  `http://localhost:8080` that serves the repo to the kiosk browser.
  (Chromium blocks `fetch()` on `file://`, so we go through HTTP.)
- `systemd/slideshow-update.{service,timer}` &mdash; pulls new slides on
  boot and every hour.
- `openbox/autostart` &mdash; disables screen blanking, hides the cursor,
  starts the kiosk.

---

## Local testing (no Pi required)

You can author and preview slides on your laptop before deploying. The
slideshow is a plain static site, but you **must** serve it over HTTP
&mdash; Chromium and Firefox both block `fetch()` on `file://`, so opening
`index.html` directly will load the empty shell and show no slides.

### 1. Serve the repo

Any static file server works. The simplest option (already used by the
Pi) is Python's built-in:

```sh
cd raspberry-pie-tv
python3 -m http.server 8080
```

Other options if you have them: `npx serve .`, `php -S localhost:8080`,
`caddy file-server --listen :8080`.

### 2. Open it in a browser

Visit <http://localhost:8080/index.html>. The slideshow should start
fading through the example slides immediately.

For a TV-sized preview, use your browser's responsive device mode set
to 1920&times;1080, or just press F11 for fullscreen.

### 3. Verify it actually loads

If something's off, open dev tools &rarr; Network and reload. You
should see successful (200) requests for:

- `index.html`, `styles.css`, `app.js`
- `slides/manifest.json`
- one fetch per slide listed in the manifest

If the manifest 404s, the path is wrong. If a slide 404s, the filename
in `manifest.json` doesn't match what's in `slides/`.

For a quick scriptable check without a browser:

```sh
node --input-type=module -e '
const base = "http://127.0.0.1:8080";
const m = await (await fetch(base + "/slides/manifest.json")).json();
for (const s of m.slides) {
  const r = await fetch(base + "/slides/" + s.file);
  console.log(r.ok ? "PASS" : "FAIL", s.file, r.status);
}
'
```

### 4. Iterate

Edit slides in `slides/`, save, refresh the browser. No build step, no
restart. Once you're happy, commit and push &mdash; the Pi will pick it
up on its next pull.

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

Symptoms first &mdash; find the one that matches what you're seeing.

### Black screen / nothing happens after boot

Plug in a USB keyboard and press a key to wake the display. If you
see a login prompt, the kiosk never started. SSH in and check:

```sh
systemctl status getty@tty1            # autologin working?
systemctl --user status                # is openbox even running?
journalctl --user -b | tail -50        # openbox + autostart errors
```

Most common cause: `~/.bash_profile` wasn't written by `install.sh`.
Re-run `sudo ./scripts/install.sh`.

### Slideshow shell loads but slides never appear

Means Chromium is up but `fetch()` is failing. SSH in and check that
the local HTTP server is alive:

```sh
systemctl status slideshow-server.service
curl -fsS http://127.0.0.1:8080/slides/manifest.json
```

If the server isn't running: `sudo systemctl restart slideshow-server`.
If it's running but the manifest 404s, a slide file is missing or
misnamed in `slides/manifest.json`.

### Image is letterboxed, stretched, or wrong resolution

Some TVs only advertise their native resolution after they're on. Pi
boots first → picks a fallback mode → stuck there.

Fix: power on the TV first, *then* power on the Pi. If that doesn't
work, force a mode in `/boot/firmware/config.txt`:

```
hdmi_group=1
hdmi_mode=16   # 1080p @ 60 Hz
```

Reboot.

### Screen blanks after ~10 minutes

`run-kiosk.sh` and Openbox autostart already disable DPMS, but some
HDMI monitors ignore it. Add to `/boot/firmware/cmdline.txt` (single
line):

```
consoleblank=0
```

Reboot.

### Chromium shows "restore session" / "didn't shut down cleanly" banner

`run-kiosk.sh` strips this from `~/.config/chromium/Default/Preferences`
on every launch. If it keeps coming back, nuke the profile:

```sh
rm -rf ~/.config/chromium
sudo reboot
```

### Slides aren't updating after a `git push`

Either the Pi is offline, or the timer hasn't fired yet. Check both:

```sh
systemctl status slideshow-update.timer    # next fire time
journalctl -u slideshow-update.service     # last run output
```

Force an update immediately:

```sh
~/raspberry-pie-tv/scripts/update.sh
```

If `git pull` fails with auth errors, the Pi can't reach GitHub. For
private repos, set up a deploy key or use HTTPS with a token. For
captive-portal WiFi, plug in a keyboard, switch to a TTY (`Ctrl+Alt+F2`),
log in, open the captive portal in a text browser (`sudo apt install
w3m && w3m http://example.com`), or use a phone hotspot.

### No network at the venue

Not actually a problem. The slideshow runs entirely from local files
once the Pi has booted. The hourly `git pull` will fail silently and
the existing slides keep playing.

### Pi reboots randomly / slideshow flickers

Almost always undervoltage. Check:

```sh
vcgencmd get_throttled       # anything other than 0x0 = power issue
dmesg | grep -i voltage
```

Use the official Raspberry Pi power supply, not a random phone
charger. The Pi 3 needs 2.5 A at 5 V.

### Need to debug Chromium itself

Add `--remote-debugging-port=9222` to `CHROMIUM_FLAGS` in
`scripts/run-kiosk.sh` and reboot. Then from your laptop:

```sh
ssh -L 9222:localhost:9222 <user>@<pi>.local
# open http://localhost:9222 on your laptop
```

You get full Chrome DevTools attached to the kiosk session.

### "I just want to start over"

```sh
cd ~/raspberry-pie-tv && git pull
sudo ./scripts/install.sh    # idempotent, safe to re-run
sudo reboot
```

If the Pi itself is wedged, just re-flash the SD card and start from
"First-time Pi setup" again &mdash; the whole setup is ~10 minutes.
