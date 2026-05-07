(() => {
  const DEFAULT_DURATION_MS = 8000;
  const FADE_MS = 800;
  const MANIFEST_URL = "slides/manifest.json";

  const layers = {
    a: document.querySelector('.slide[data-layer="a"]'),
    b: document.querySelector('.slide[data-layer="b"]'),
  };
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

  const startProgress = (duration) => {
    progressEl.style.transition = "none";
    progressEl.style.width = "0%";
    // Force reflow so the next transition picks up the reset.
    void progressEl.offsetWidth;
    progressEl.style.transition = `width ${duration}ms linear`;
    progressEl.style.width = "100%";
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

    // Prime cache for the first couple of slides.
    await preload(slides[0].file);
    if (slides[1]) preload(slides[1].file).catch(() => {});

    let idx = 0;
    let activeKey = "a";

    // Initial z-index: outgoing below, incoming above. Layers swap on each tick.
    layers.a.style.zIndex = "1";
    layers.b.style.zIndex = "1";

    const renderNext = async () => {
      const slide = slides[idx];
      const nextKey = activeKey === "a" ? "b" : "a";
      try {
        const html = await preload(slide.file);
        layers[nextKey].innerHTML = html;
      } catch (e) {
        layers[nextKey].innerHTML = `<div class="center"><h2>Slide failed to load</h2><p>${slide.file}</p></div>`;
      }

      // Stack incoming above outgoing; outgoing keeps full opacity until incoming
      // finishes fading in, so the page background never bleeds through.
      layers[nextKey].style.zIndex = "2";
      layers[activeKey].style.zIndex = "1";
      layers[nextKey].classList.add("visible");

      const prevKey = activeKey;
      activeKey = nextKey;

      const duration = Number(slide.durationMs) > 0 ? Number(slide.durationMs) : DEFAULT_DURATION_MS;
      startProgress(duration);

      // After the fade is done, drop the (now-covered) previous layer's visible
      // class. No flash because nextKey is at opacity 1 in front of it.
      setTimeout(() => {
        layers[prevKey].classList.remove("visible");
      }, FADE_MS);

      idx = (idx + 1) % slides.length;

      // Preload the slide after next while this one shows.
      const lookahead = slides[idx];
      if (lookahead) preload(lookahead.file).catch(() => {});

      setTimeout(renderNext, duration);
    };

    renderNext();
  };

  window.addEventListener("error", (e) => showError(e.message));
  document.addEventListener("DOMContentLoaded", run);
})();
