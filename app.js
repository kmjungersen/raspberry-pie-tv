(() => {
  const DEFAULT_DURATION_MS = 8000;
  const MANIFEST_URL = "slides/manifest.json";

  const layers = {
    a: document.querySelector('.slide[data-layer="a"]'),
    b: document.querySelector('.slide[data-layer="b"]'),
  };
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

    const renderNext = async () => {
      const slide = slides[idx];
      const nextKey = activeKey === "a" ? "b" : "a";
      try {
        const html = await preload(slide.file);
        layers[nextKey].innerHTML = html;
      } catch (e) {
        layers[nextKey].innerHTML = `<div class="center"><h2>Slide failed to load</h2><p>${slide.file}</p></div>`;
      }

      layers[nextKey].classList.add("visible");
      layers[activeKey].classList.remove("visible");
      activeKey = nextKey;

      const duration = Number(slide.durationMs) > 0 ? Number(slide.durationMs) : DEFAULT_DURATION_MS;
      idx = (idx + 1) % slides.length;

      // Preload the slide after next while this one shows.
      const lookahead = slides[(idx + 0) % slides.length];
      if (lookahead) preload(lookahead.file).catch(() => {});

      setTimeout(renderNext, duration);
    };

    renderNext();
  };

  window.addEventListener("error", (e) => showError(e.message));
  document.addEventListener("DOMContentLoaded", run);
})();
