const body = document.body;
const layoutSelect = document.getElementById("layout-select");
const themeSelect = document.getElementById("theme-select");
const overlayToggle = document.getElementById("overlay-toggle");
const overlay = document.getElementById("reader-overlay");
const readerSurface = document.getElementById("reader-surface");
const fitChip = document.getElementById("fit-chip");
const layoutChip = document.getElementById("layout-chip");

let overlayTimer;
let pinchStartDistance = null;
let pinchStartScale = 1;

function isCompactMode() {
  return body.dataset.layout === "compact";
}

function syncOverlay() {
  const shown = body.dataset.overlay === "shown";
  const compact = isCompactMode();
  overlay.hidden = !shown || !compact;
  overlayToggle.disabled = !compact;
  overlayToggle.textContent = shown && compact ? "Hide Overlay" : "Show Overlay";
}

function clampScale(scale) {
  return Math.min(1.3, Math.max(0.85, scale));
}

function touchDistance(touches) {
  const [first, second] = touches;
  return Math.hypot(second.clientX - first.clientX, second.clientY - first.clientY);
}

function syncScale() {
  const scale = Number(body.dataset.scaleFactor || "1");
  body.style.setProperty("--reader-scale", String(scale));
}

function syncAdaptiveState() {
  const autoFit = body.dataset.fit === "auto";
  const scale = Number(body.dataset.scaleFactor || "1");
  const compact = isCompactMode();
  const readerWidth = readerSurface.clientWidth;
  const compactCanSplit = readerWidth >= 860 && scale <= 1.05;
  const columns = !compact || (autoFit && compactCanSplit) ? "two" : "one";

  body.dataset.columns = columns;
  fitChip.textContent = autoFit ? "Auto Fit: On" : "Auto Fit: Off";

  if (!compact) {
    layoutChip.textContent = `Layout: Adaptive Panels, ${columns === "two" ? "2" : "1"} Cols`;
    return;
  }

  if (columns === "two") {
    layoutChip.textContent = "Layout: Auto 2 Columns";
    return;
  }

  layoutChip.textContent =
    scale > 1 ? `Layout: 1 Column Zoomed (${Math.round(scale * 100)}%)` : "Layout: 1 Column";
}

function scheduleOverlayHide() {
  window.clearTimeout(overlayTimer);
  overlayTimer = window.setTimeout(() => {
    body.dataset.overlay = "hidden";
    syncOverlay();
  }, 2600);
}

function revealOverlay() {
  body.dataset.overlay = "shown";
  syncOverlay();
  scheduleOverlayHide();
}

function applyScale(nextScale, { forceManualFit = false } = {}) {
  body.dataset.scaleFactor = String(clampScale(nextScale));
  if (forceManualFit) {
    body.dataset.fit = "manual";
  }
  syncScale();
  syncAdaptiveState();
}

layoutSelect.addEventListener("change", (event) => {
  body.dataset.layout = event.target.value;
  if (!isCompactMode()) {
    body.dataset.overlay = "hidden";
    window.clearTimeout(overlayTimer);
  }
  syncOverlay();
  syncAdaptiveState();
});

themeSelect.addEventListener("change", (event) => {
  body.dataset.theme = event.target.value;
});

overlayToggle.addEventListener("click", () => {
  if (!isCompactMode()) {
    body.dataset.overlay = "hidden";
    syncOverlay();
    return;
  }

  if (body.dataset.overlay === "shown") {
    body.dataset.overlay = "hidden";
    window.clearTimeout(overlayTimer);
    syncOverlay();
    return;
  }

  revealOverlay();
});

readerSurface.addEventListener("click", () => {
  if (!isCompactMode()) {
    return;
  }

  if (body.dataset.overlay === "shown") {
    body.dataset.overlay = "hidden";
    window.clearTimeout(overlayTimer);
    syncOverlay();
    return;
  }

  revealOverlay();
});

readerSurface.addEventListener("dblclick", () => {
  if (!isCompactMode()) {
    return;
  }

  body.dataset.fit = body.dataset.fit === "auto" ? "manual" : "auto";
  if (body.dataset.fit === "auto") {
    applyScale(0.96);
  } else {
    applyScale(1);
  }
  revealOverlay();
});

readerSurface.addEventListener("touchstart", (event) => {
  if (!isCompactMode()) {
    return;
  }

  if (event.touches.length >= 2) {
    pinchStartDistance = touchDistance(event.touches);
    pinchStartScale = Number(body.dataset.scaleFactor || "1");
    revealOverlay();
  }
});

readerSurface.addEventListener(
  "touchmove",
  (event) => {
    if (!isCompactMode()) {
      return;
    }

    if (event.touches.length < 2 || pinchStartDistance == null) {
      return;
    }

    const distance = touchDistance(event.touches);
    const nextScale = pinchStartScale * (distance / pinchStartDistance);
    applyScale(nextScale, { forceManualFit: true });
    revealOverlay();
    event.preventDefault();
  },
  { passive: false },
);

readerSurface.addEventListener("touchend", () => {
  if (!isCompactMode()) {
    return;
  }

  if (pinchStartDistance != null) {
    pinchStartDistance = null;
    pinchStartScale = Number(body.dataset.scaleFactor || "1");
  }
});

window.addEventListener("resize", () => {
  syncAdaptiveState();
});

body.dataset.overlay = "hidden";
body.dataset.fit = "manual";
body.dataset.scaleFactor = "1";
syncOverlay();
syncScale();
syncAdaptiveState();
