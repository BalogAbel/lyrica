const body = document.body;
const layoutSelect = document.getElementById("layout-select");
const themeSelect = document.getElementById("theme-select");
const overlayToggle = document.getElementById("overlay-toggle");
const overlay = document.getElementById("reader-overlay");
const readerSurface = document.getElementById("reader-surface");
const fitChip = document.getElementById("fit-chip");
const layoutChip = document.getElementById("layout-chip");
const songKicker = document.getElementById("song-kicker");
const capoDirective = document.getElementById("capo-directive");
const overlayTransposeChip = document.getElementById("overlay-transpose-chip");
const overlayCapoChip = document.getElementById("overlay-capo-chip");
const panelTransposeValue = document.getElementById("panel-transpose-value");
const panelCapoValue = document.getElementById("panel-capo-value");
const instrumentGuitarButton = document.getElementById("instrument-guitar");
const instrumentPianoButton = document.getElementById("instrument-piano");
const chordLines = [...document.querySelectorAll(".line.chord[data-chords]")];

const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const NOTE_INDEX = new Map(NOTE_NAMES.map((name, index) => [name, index]));
const BASE_KEY = "G";
const BASE_TRANSPOSE = 2;
const BASE_CAPO = 2;

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

function clampCapo(value) {
  return Math.max(0, value);
}

function parseChordParts(chord) {
  const match = chord.match(/^([A-G])([#b]?)(.*)$/);
  if (!match) {
    return null;
  }

  const [, letter, accidental, suffix] = match;
  const flatEnharmonics = new Map([
    ["Ab", "G#"],
    ["Bb", "A#"],
    ["Cb", "B"],
    ["Db", "C#"],
    ["Eb", "D#"],
    ["Fb", "E"],
    ["Gb", "F#"],
  ]);
  const noteName = accidental === "b" ? flatEnharmonics.get(`${letter}b`) : `${letter}${accidental}`;
  const index = NOTE_INDEX.get(noteName);
  if (index == null) {
    return null;
  }

  return { index, suffix };
}

function transposeChord(chord, semitoneOffset) {
  const [mainChord, bassChord] = chord.split("/");
  const transposedMain = transposeSingleChord(mainChord, semitoneOffset);
  if (bassChord == null) {
    return transposedMain;
  }
  return `${transposedMain}/${transposeSingleChord(bassChord, semitoneOffset)}`;
}

function transposeSingleChord(chord, semitoneOffset) {
  const parts = parseChordParts(chord);
  if (parts == null) {
    return chord;
  }

  const nextIndex = (parts.index + semitoneOffset + 120) % 12;
  return `${NOTE_NAMES[nextIndex]}${parts.suffix}`;
}

function formatSignedNumber(value) {
  return value > 0 ? `+${value}` : String(value);
}

function effectiveTranspose() {
  return BASE_TRANSPOSE + Number(body.dataset.transposeDelta || "0");
}

function effectiveCapo() {
  return clampCapo(BASE_CAPO + Number(body.dataset.capoDelta || "0"));
}

function isGuitarMode() {
  return body.dataset.instrument !== "piano";
}

function syncInstrumentControls() {
  const guitarMode = isGuitarMode();
  instrumentGuitarButton.classList.toggle("active", guitarMode);
  instrumentPianoButton.classList.toggle("active", !guitarMode);

  const transposeValue = formatSignedNumber(effectiveTranspose());
  overlayTransposeChip.textContent = `Transpose: ${transposeValue}`;
  panelTransposeValue.textContent = transposeValue;

  const capoValue = effectiveCapo();
  overlayCapoChip.textContent = `Capo: ${capoValue}`;
  panelCapoValue.textContent = String(capoValue);
  const capoDownDisabled = capoValue <= 0;
  overlayCapoDown.disabled = capoDownDisabled;
  panelCapoDown.disabled = capoDownDisabled;

  capoDirective.hidden = !guitarMode || capoValue <= 0;
  capoDirective.textContent = `Capo ${capoValue}`;

  const soundingKey = transposeChord(BASE_KEY, effectiveTranspose());
  songKicker.textContent = guitarMode
    ? `Player Key: ${BASE_KEY}  Sounding Key: ${soundingKey}`
    : `Piano Key: ${soundingKey}`;

  for (const line of chordLines) {
    const originalChords = line.dataset.chords.split(",");
    const visibleChords = originalChords.map((chord) => {
      const soundingChord = transposeChord(chord, effectiveTranspose());
      return guitarMode ? transposeChord(soundingChord, -effectiveCapo()) : soundingChord;
    });
    line.textContent = visibleChords.join("        ");
  }
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

instrumentGuitarButton.addEventListener("click", () => {
  body.dataset.instrument = "guitar";
  syncInstrumentControls();
});

instrumentPianoButton.addEventListener("click", () => {
  body.dataset.instrument = "piano";
  syncInstrumentControls();
});

document.getElementById("overlay-transpose-down").addEventListener("click", () => {
  body.dataset.transposeDelta = String(Number(body.dataset.transposeDelta || "0") - 1);
  syncInstrumentControls();
  revealOverlay();
});

document.getElementById("overlay-transpose-up").addEventListener("click", () => {
  body.dataset.transposeDelta = String(Number(body.dataset.transposeDelta || "0") + 1);
  syncInstrumentControls();
  revealOverlay();
});

document.getElementById("panel-transpose-down").addEventListener("click", () => {
  body.dataset.transposeDelta = String(Number(body.dataset.transposeDelta || "0") - 1);
  syncInstrumentControls();
});

document.getElementById("panel-transpose-up").addEventListener("click", () => {
  body.dataset.transposeDelta = String(Number(body.dataset.transposeDelta || "0") + 1);
  syncInstrumentControls();
});

document.getElementById("overlay-capo-down").addEventListener("click", () => {
  body.dataset.capoDelta = String(effectiveCapo() <= 0 ? Number(body.dataset.capoDelta || "0") : Number(body.dataset.capoDelta || "0") - 1);
  syncInstrumentControls();
  revealOverlay();
});

document.getElementById("overlay-capo-up").addEventListener("click", () => {
  body.dataset.capoDelta = String(Number(body.dataset.capoDelta || "0") + 1);
  syncInstrumentControls();
  revealOverlay();
});

document.getElementById("panel-capo-down").addEventListener("click", () => {
  body.dataset.capoDelta = String(effectiveCapo() <= 0 ? Number(body.dataset.capoDelta || "0") : Number(body.dataset.capoDelta || "0") - 1);
  syncInstrumentControls();
});

document.getElementById("panel-capo-up").addEventListener("click", () => {
  body.dataset.capoDelta = String(Number(body.dataset.capoDelta || "0") + 1);
  syncInstrumentControls();
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
body.dataset.instrument = "guitar";
body.dataset.transposeDelta = "0";
body.dataset.capoDelta = "0";
syncOverlay();
syncScale();
syncAdaptiveState();
syncInstrumentControls();
