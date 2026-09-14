# Slideshow V2 — LVNx Chicago, September 16–18, 2026

Plan written 2026-09-10. Six days to show. Hardware is the same Pi 3 / 3B+ at 1080p.

## Decisions so far

| Question | Answer |
|---|---|
| Hardware | Pi 3 / 3B+. CSS transforms and opacity only. No video, WebGL, blur, or canvas. |
| Directions | Motion-first deck + Product in motion. No booth-board extras, no staffer control. |
| Content | Re-angle copy for the LVNx pricing / legal-value audience. Same products. |
| Product assets | None yet. Kurtis will gather screenshots later. Product mocks for Portal and Distributions are deferred to a later phase. |
| Event text | "LVNx Chicago · September 16–18" only. No booth number or URL. |

## Goal

Same kiosk, same boot chain, same manifest-driven slides. The difference is that
nothing on screen is ever fully still, and the sharpest product story (Exception
Rates Manager) is told as an animated visualization instead of a static table.

## Scope

**In**
1. A small motion engine in `app.js` + `styles.css`: staggered reveals, animated
   number counters, SVG icon draw-ins, per-slide transition types, ambient
   background drift.
2. Every existing slide re-authored to use it.
3. Exception Rates Manager rebuilt as an animated rate-gap visualization built only
   from the numbers already on the slide (2019: $850 vs $950; today: $850 vs $1,400).
4. LVNx copy changes (see "Proposed copy" below).
5. A Pi 3 performance pass and a burn-in before the show.

**Out (for now)**
- Partner Portal and Partner Distributions animated mock UIs. Blocked on screenshots.
  The engine is built so these drop in as new fragments without touching `app.js`.
- Ticker, clock, QR, staffer control. Explicitly declined.
- Any framework, bundler, or `node_modules`. Still vanilla.

## Architecture

### Manifest gains optional per-slide fields

```json
{ "file": "07-case-exception-rates.html", "durationMs": 14000, "transition": "wipe" }
```

`transition` is one of `fade` (default, today's crossfade), `wipe` (a brand-color
panel sweeps across, covers, then reveals the next slide), or `cut`. Everything else
is unchanged, so old manifests keep working.

### Reveal choreography is declared in the slide HTML

```html
<h2 data-reveal>Who We Are</h2>
<div class="card" data-reveal style="--i:1">…</div>
<div class="card" data-reveal style="--i:2">…</div>
```

When a layer becomes visible, `app.js` adds `.in` one frame later. CSS keyed on
`.slide.in [data-reveal]` runs a transform + opacity keyframe with
`animation-delay: calc(var(--i, 0) * 110ms)`. No JS per element, no layout thrash.

### Counters

`<span data-count="550" data-prefix="$" data-suffix="/hr" data-count-delay="900">`
tweens from 0 with a single `requestAnimationFrame` loop per slide, eased, ~1.2 s.
Cancelled if the slide leaves early.

### SVG draw-in

`app.js` sets `pathLength="1"` on every path in the incoming slide's `.icon svg`.
CSS animates `stroke-dashoffset` from 1 to 0. Cheap: it's a stroke property, not a
layout property.

### Ambient background

Two large absolutely positioned radial-gradient discs at low opacity, translated
slowly on a 24 s loop with `transform` only. On white content slides they read as a
soft brand-colored glow; on dividers they're a slow diagonal sheen. No `filter`.

### Transition overlay

One `#wipe` element outside the layers. For `wipe`: translateX −100% → 0 over 380 ms,
swap layer z-index and content while covered, then 0 → 100% over 380 ms. All
`transform`, so the Pi's compositor handles it without repainting the slides.

### Pi 3 budget rules

- Animate only `transform`, `opacity`, `stroke-dashoffset`.
- No `filter`, `backdrop-filter`, `box-shadow` animation, or `mix-blend-mode`.
- At most ~3 continuously animating elements per slide after reveals finish.
- Fonts stay local (Lato woff2 already in `slides/assets/fonts`). No web requests.
- Verify with Chrome DevTools at 6× CPU throttle locally, then on the real Pi.

## Per-slide choreography

| # | Slide | Motion |
|---|---|---|
| 01 | Title | Accent bars grow in, headline rises, tagline + LVNx line stagger. Logo slow scale 1.00→1.05 over the dwell. |
| 02 | Divider | Wipe in. Headline rises, rule draws left→right. Slow sheen. |
| 03 | Who We Are | Headline, lede, then three cards stagger up. Icons draw in. |
| 04 | What We Do | Same as 03. |
| 05 | Divider (teal) | Same as 02. |
| 06 | Partner Portal | Cards stagger; the card-note fades last. |
| 07 | Exception Rates | **Hero.** Two bars per year grow from a shared baseline. "Gap / hour" counter ticks $100 → $550. The gap region pulses once. Caption and callout land last. Dwell 14 s. |
| 09 | Distributions | Timeline line draws across, dots pop in sequence, each step's label rises as its dot lands. |
| 10 | Divider | Wipe. As 02. |
| 11 | How We Work | As 03. |
| 12 | Why SRP | As 03. |
| 13 | CTA | Wipe. Headline rises, contact line and LVNx line stagger. Progress bar stays visible (hiding it read as a stall on the Pi). |

## Proposed copy (needs Kurtis's sign-off)

Only the lines below change. Everything else stays word-for-word.

| Slide | Today | Proposed |
|---|---|---|
| 01 h1 | Legal Financial Software, Purpose-Built for Aderant Firms | Rates, Pricing & Partner Economics. Purpose-Built for Aderant Firms. |
| 01 new line | — | LVNx Chicago · September 16–18 |
| 06b new divider (optional, before 07) | — | Standard rates grow ~10% a year. Exception rates rarely follow. |
| 07 caption | Standard rates grow ~10% per year. Exception rates rarely follow. | Every year the gap widens. Most firms can't see it until year-end. |
| 13 contact | Sales@steelridge.io \| https://steelridge.io | Sales@steelridge.io · steelridge.io · Find us at LVNx Chicago |

If the 06b divider is added it takes the "10% per year" claim off slide 07 so it isn't said twice.

## Schedule

| Day | Work | Needs from Kurtis |
|---|---|---|
| Thu 9/10 | ✅ Plan approved. Motion engine, all slides choreographed, Exception Rates hero, LVNx copy, local visual check. | — |
| Fri 9/11 | Polish pass after Kurtis reviews in browser. 6× CPU-throttle check. | Review the deck, note anything that reads wrong. |
| Sat 9/12 | First run on the real Pi. Tune timings, fix jank. | Pi powered on and reachable over SSH, or run `update.sh` and report what you see. |
| Sun 9/13 | Buffer. | — |
| Mon 9/14 | Content freeze. PR to `main`. Pi pulls on its hourly timer. | Merge. |
| Tue 9/15 | Two-hour burn-in on the Pi + TV. Check `free -m` and `vcgencmd measure_temp` at the end. Pack. | Run the burn-in. |
| Wed 9/16 | Show. | — |
| Later | Portal + Distributions animated mocks once screenshots exist. | Screenshots. |

## Pi verification checklist (Sat and Tue)

```sh
ssh <user>@slideshow-pi.local
~/raspberry-pie-tv/scripts/update.sh
free -m                      # Chromium should sit well under 700 MB used
vcgencmd measure_temp        # under ~70 °C after an hour
vcgencmd get_throttled       # must be 0x0
top -bn1 | head -15          # chromium CPU during a transition
```

Watch a full loop with eyes on the TV: any stutter on a wipe, any counter that
skips, any reveal that pops instead of eases.

## Rollback

All V2 work is on `claude/project-v2-lvnx-planning-b41404`. If the Pi misbehaves on
Tuesday, `git checkout main` on the Pi and `update.sh` restores the V1 deck in
seconds. The manifest format is backward compatible in both directions.
