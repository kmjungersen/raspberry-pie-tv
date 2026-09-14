(() => {
  const DEFAULT_DURATION_MS = 8000;
  const FADE_MS = 800;   // must match --fade-ms in styles.css
  const WIPE_MS = 420;   // one leg of the wipe (cover or uncover)
  const MANIFEST_URL = "slides/manifest.json";

  // Injected at the top of every slide root so nothing on screen is ever fully still.
  // Only in full-motion mode: continuous full-screen animation is what a Pi 3
  // struggles with, so the default is reveals-only (short, then static).
  const AMBIENT_HTML = '<div class="ambient" aria-hidden="true"><i></i><i></i></div>';
  const params = new URLSearchParams(location.search);
  const FULL_MOTION = params.get("motion") === "full";
  if (FULL_MOTION) document.documentElement.classList.add("motion-full");

  const layers = {
    a: document.querySelector('.slide[data-layer="a"]'),
    b: document.querySelector('.slide[data-layer="b"]'),
  };
  const wipeEl = document.getElementById("wipe");
  const progressEl = document.getElementById("progress");
  const errorEl = document.getElementById("error");

  const showError = (msg) => {
    errorEl.textContent = String(msg);
    errorEl.classList.add("visible");
  };

  const fetchText = async (url) => {
    const res = await fetch(url, { cache: "no-store" });
    if (!res.ok) throw new Error(`${url}: ${res.status}`);
    return res.text();
  };

  const fetchJson = async (url) => {
    const res = await fetch(url, { cache: "no-store" });
    if (!res.ok) throw new Error(`${url}: ${res.status}`);
    return res.json();
  };

  const loadSlideHtml = async (file) => fetchText(`slides/${file}`);

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  // Two frames' worth of wall-clock time. setTimeout rather than rAF so the
  // engine keeps stepping even if the page is briefly backgrounded.
  const nextFrame = () => sleep(40);

  // ---- Progress bar --------------------------------------------------------
  const startProgress = (duration, visible) => {
    progressEl.style.opacity = visible ? "1" : "0";
    progressEl.style.transition = "none";
    progressEl.style.width = "0%";
    void progressEl.offsetWidth; // force reflow so the next transition picks up the reset
    progressEl.style.transition = `width ${duration}ms linear, opacity 300ms`;
    progressEl.style.width = "100%";
  };

  // ---- Counters: <span data-count="550" data-prefix="$" data-suffix="/hr"> ----
  let counterRaf = 0;
  const cancelCounters = () => {
    if (counterRaf) cancelAnimationFrame(counterRaf);
    counterRaf = 0;
  };
  const fmtNumber = (it, v) =>
    it.prefix + v.toFixed(it.decimals).replace(/\B(?=(\d{3})+(?!\d))/g, ",") + it.suffix;
  const easeOutCubic = (t) => 1 - Math.pow(1 - t, 3);

  const runCounters = (root) => {
    cancelCounters();
    const els = Array.from(root.querySelectorAll("[data-count]"));
    if (els.length === 0) return;
    const items = els.map((el) => ({
      el,
      target: Number(el.dataset.count) || 0,
      from: Number(el.dataset.countFrom) || 0,
      delay: Number(el.dataset.countDelay) || 0,
      dur: Number(el.dataset.countDuration) || 1200,
      prefix: el.dataset.prefix || "",
      suffix: el.dataset.suffix || "",
      decimals: Number(el.dataset.decimals) || 0,
    }));
    for (const it of items) it.el.textContent = fmtNumber(it, it.from);
    const start = performance.now();
    const tick = (now) => {
      let done = true;
      for (const it of items) {
        const t = Math.min(1, Math.max(0, (now - start - it.delay) / it.dur));
        if (t < 1) done = false;
        it.el.textContent = fmtNumber(it, it.from + (it.target - it.from) * easeOutCubic(t));
      }
      counterRaf = done ? 0 : requestAnimationFrame(tick);
    };
    counterRaf = requestAnimationFrame(tick);
  };

  // ---- SVG draw-in: normalise path lengths so one CSS rule animates every icon ----
  const DRAWABLE = new Set(["path", "circle", "rect", "line", "polyline", "polygon", "ellipse"]);
  const prepSvg = (root) => {
    root.querySelectorAll(".icon svg *").forEach((el) => {
      if (DRAWABLE.has(el.tagName.toLowerCase())) el.setAttribute("pathLength", "1");
    });
  };

  // ---- Mount a fragment into a layer, prepped but not yet visible ----------
  const mount = (layer, html) => {
    layer.classList.remove("in");
    layer.innerHTML = html;
    const root = layer.firstElementChild;
    if (FULL_MOTION && root && !root.querySelector(":scope > .ambient")) {
      root.insertAdjacentHTML("afterbegin", AMBIENT_HTML);
    }
    prepSvg(layer);
  };

  // Kick off the reveal choreography (CSS keyed on .slide.in) and counters.
  const play = (layer) => {
    void layer.offsetWidth; // commit the mounted DOM before the .in rules match
    layer.classList.add("in");
    runCounters(layer);
  };

  // ---- Wipe overlay --------------------------------------------------------
  const wipeTo = async (x, ms) => {
    wipeEl.style.transition = ms ? `transform ${ms}ms cubic-bezier(.7,0,.3,1)` : "none";
    wipeEl.style.transform = `translateX(${x})`;
    if (!ms) {
      void wipeEl.offsetWidth;
      return;
    }
    await sleep(ms + 20);
  };

  const run = async () => {
    let manifest;
    try {
      manifest = await fetchJson(MANIFEST_URL);
    } catch (e) {
      showError(`Could not load ${MANIFEST_URL}\n${e.message}`);
      return;
    }

    const slides = Array.isArray(manifest.slides) ? manifest.slides : [];
    if (slides.length === 0) {
      showError("manifest.json has no slides");
      return;
    }

    const htmlCache = new Map();
    const preload = async (file) => {
      if (!htmlCache.has(file)) {
        htmlCache.set(file, await loadSlideHtml(file));
      }
      return htmlCache.get(file);
    };


    // Dev aid: ?start=N begins the loop at slide index N (0-based).
    const startAt = Number(params.get("start"));
    let idx = Number.isInteger(startAt) && startAt >= 0 && startAt < slides.length ? startAt : 0;
    let activeKey = "a";
    let first = true;

    layers.a.style.zIndex = "1";
    layers.b.style.zIndex = "1";

    await preload(slides[idx].file);
    if (slides[idx + 1]) preload(slides[idx + 1].file).catch(() => {});

    const renderNext = async () => {
      const slide = slides[idx];
      const nextKey = activeKey === "a" ? "b" : "a";
      const prevKey = activeKey;
      const incoming = layers[nextKey];
      const outgoing = layers[prevKey];

      let html;
      try {
        html = await preload(slide.file);
      } catch (e) {
        html = `<div class="content"><h2>Slide failed to load</h2><p>${slide.file}</p></div>`;
      }

      const duration = Number(slide.durationMs) > 0 ? Number(slide.durationMs) : DEFAULT_DURATION_MS;
      const transition = first ? "fade" : String(slide.transition || "fade");
      const showProgress = slide.progress !== false;

      cancelCounters();

      if (transition === "wipe" && wipeEl) {
        // Cover the stage, swap underneath, uncover. All transform-only.
        wipeEl.className = `wipe-${slide.wipeColor || "orange"}`;
        await wipeTo("-100%", 0);
        await wipeTo("0%", WIPE_MS);
        outgoing.classList.remove("visible", "in");
        mount(incoming, html);
        incoming.style.zIndex = "2";
        outgoing.style.zIndex = "1";
        incoming.classList.add("no-fade", "visible");
        await nextFrame();
        incoming.classList.remove("no-fade");
        startProgress(duration, showProgress);
        play(incoming);
        wipeTo("100%", WIPE_MS);
      } else if (transition === "cut") {
        mount(incoming, html);
        incoming.style.zIndex = "2";
        outgoing.style.zIndex = "1";
        incoming.classList.add("no-fade", "visible");
        outgoing.classList.remove("visible", "in");
        await nextFrame();
        incoming.classList.remove("no-fade");
        startProgress(duration, showProgress);
        play(incoming);
      } else {
        // Crossfade: incoming stacks above outgoing, which keeps full opacity
        // until the fade finishes so the page background never bleeds through.
        mount(incoming, html);
        incoming.style.zIndex = "2";
        outgoing.style.zIndex = "1";
        incoming.classList.add("visible");
        startProgress(duration, showProgress);
        play(incoming);
        setTimeout(() => outgoing.classList.remove("visible", "in"), FADE_MS);
      }

      activeKey = nextKey;
      first = false;
      idx = (idx + 1) % slides.length;

      const lookahead = slides[idx];
      if (lookahead) preload(lookahead.file).catch(() => {});

      setTimeout(renderNext, duration);
    };

    renderNext();
  };

  window.addEventListener("error", (e) => showError(e.message));
  document.addEventListener("DOMContentLoaded", run);
})();
