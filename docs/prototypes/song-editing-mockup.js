const body = document.body;
const screenSelect = document.getElementById("screen-select");
const layoutSelect = document.getElementById("layout-select");
const themeSelect = document.getElementById("theme-select");
const stateSelect = document.getElementById("state-select");

const tabs = Array.from(document.querySelectorAll(".tab"));
const canonicalPanel = document.getElementById("canonical-panel");
const canonicalPanelTitle = document.getElementById("canonical-panel-title");
const canonicalSwitches = Array.from(
  document.querySelectorAll("[data-canonical-view]"),
);
const statusBar = document.getElementById("status-bar");
const stateCard = document.getElementById("state-card");
const stateTitle = document.getElementById("state-title");
const stateCopy = document.getElementById("state-copy");
const stateActions = document.getElementById("state-actions");
const statePrimaryButton = document.getElementById("state-primary-button");
const stateSecondaryButton = document.getElementById("state-secondary-button");

const saveButton = document.getElementById("save-button");
const cancelButton = document.getElementById("cancel-button");

const sourceInput = document.getElementById("source-input");
const sourceHighlight = document.getElementById("source-highlight");
const transposeDownButton = document.getElementById("transpose-down");
const transposeUpButton = document.getElementById("transpose-up");
const transposeValue = document.getElementById("transpose-value");
const capoDownButton = document.getElementById("capo-down");
const capoUpButton = document.getElementById("capo-up");
const capoValue = document.getElementById("capo-value");

const derivedTitle = document.getElementById("derived-title");
const derivedArtist = document.getElementById("derived-artist");
const derivedKey = document.getElementById("derived-key");
const derivedTempo = document.getElementById("derived-tempo");
const derivedTags = document.getElementById("derived-tags");
const derivedSettings = document.getElementById("derived-settings");

const previewTitle = document.getElementById("preview-title");
const previewSubtitle = document.getElementById("preview-subtitle");
const previewBadges = document.getElementById("preview-badges");
const readerDirectiveCard = document.getElementById("reader-directive-card");
const readerDirective = document.getElementById("reader-directive");
const readerGrid = document.getElementById("reader-grid");
const sourceView = document.getElementById("source-view");
const previewView = document.getElementById("preview-view");

const NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
const NOTE_INDEX = new Map(NOTE_NAMES.map((name, index) => [name, index]));
const FLAT_ENHARMONICS = new Map([
  ["Ab", "G#"],
  ["Bb", "A#"],
  ["Cb", "B"],
  ["Db", "C#"],
  ["Eb", "D#"],
  ["Fb", "E"],
  ["Gb", "F#"],
]);

const DEFAULT_SOURCE = sourceInput.value;
let syncScrollTimer = null;

const stateMap = {
  default: {
    status: "",
    sourceValue: DEFAULT_SOURCE,
    title: null,
    copy: null,
  },
  loading: {
    status: '<span class="badge">Loading song...</span>',
    sourceValue: "",
    title: "Loading",
    copy: "Loading canonical ChordPro source and derived summary fields.",
  },
  empty: {
    status: '<span class="badge warn">Empty song</span>',
    sourceValue: "",
    title: "Empty song",
    copy: "No ChordPro source loaded yet.",
  },
  "read-only": {
    status: '<span class="badge">Read only</span>',
    sourceValue: DEFAULT_SOURCE,
    title: "Read only",
    copy: "This song can be viewed but not edited.",
  },
  unauthorized: {
    status: '<span class="badge warn">Write access denied</span>',
    sourceValue: DEFAULT_SOURCE,
    title: "Unauthorized",
    copy: "Backend rejected write access for this organization.",
  },
  pending: {
    status: '<span class="badge warn">Local mutation pending</span>',
    sourceValue: DEFAULT_SOURCE,
    title: "Pending mutation",
    copy: "Saved locally. Waiting for sync with backend.",
    primaryLabel: "Sync now",
    secondaryLabel: "Keep editing",
  },
  conflict: {
    status: '<span class="badge warn">Conflict needs review</span>',
    sourceValue: DEFAULT_SOURCE,
    title: "Conflict",
    copy: "Local source diverged from canonical server state.",
    primaryLabel: "Keep mine",
    secondaryLabel: "Discard mine",
  },
  "validation-error": {
    status: '<span class="badge warn">Validation error</span>',
    sourceValue: DEFAULT_SOURCE,
    title: "Validation error",
    copy: "Fix ChordPro syntax before saving.",
    primaryLabel: "Review source",
    secondaryLabel: "Cancel",
  },
  "parse-warning": {
    status: '<span class="badge warn">Parse warning</span>',
    sourceValue: DEFAULT_SOURCE,
    title: "Parse warning",
    copy: "Source parsed with recoverable warnings.",
  },
  "offline-cached": {
    status: '<span class="badge">Offline cached</span>',
    sourceValue: DEFAULT_SOURCE,
    title: "Offline cached",
    copy: "Showing last synced source from local cache.",
  },
};

function escapeHtml(text) {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function normalizeKey(name) {
  return name.trim().toLowerCase();
}

function parseIntOrNull(value) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function parseChordPro(source) {
  const result = {
    title: "",
    artist: "",
    key: "",
    tempo: "",
    tags: [],
    transpose: 0,
    capo: 0,
    bodyLines: [],
    warnings: [],
  };

  const lines = source.split(/\r?\n/);
  for (const line of lines) {
    const directiveMatch = line.match(/^\s*\{([^:}]+):\s*(.*?)\s*\}\s*$/);
    if (directiveMatch) {
      const key = normalizeKey(directiveMatch[1]);
      const value = directiveMatch[2].trim();
      switch (key) {
        case "title":
          result.title = value;
          break;
        case "artist":
          result.artist = value;
          break;
        case "key":
          result.key = value;
          break;
        case "tempo":
          result.tempo = value;
          break;
        case "tags":
          result.tags = value
            .split(",")
            .map((tag) => tag.trim())
            .filter(Boolean);
          break;
        case "transpose":
          result.transpose = parseIntOrNull(value) ?? 0;
          if (!/^-?\d+$/.test(value)) {
            result.warnings.push(`Invalid transpose value: ${value}`);
          }
          break;
        case "capo":
          result.capo = Math.max(0, parseIntOrNull(value) ?? 0);
          if (!/^-?\d+$/.test(value)) {
            result.warnings.push(`Invalid capo value: ${value}`);
          }
          break;
        default:
          if (key.startsWith("comment")) {
            result.bodyLines.push({ type: "comment", text: value });
          } else {
            result.warnings.push(`Unsupported directive: ${directiveMatch[1]}`);
          }
      }
      continue;
    }

    if (line.trim() === "") {
      result.bodyLines.push({ type: "blank" });
      continue;
    }

    result.bodyLines.push({ type: "text", text: line });
  }

  return result;
}

function parseSectionLabel(text) {
  const trimmed = text.trim();
  if (!trimmed) {
    return null;
  }

  const labeled = trimmed.match(/^(verse|chorus|bridge|intro|outro)\s*(\d+)?$/i);
  if (labeled) {
    const label = labeled[1][0].toUpperCase() + labeled[1].slice(1).toLowerCase();
    return labeled[2] ? `${label} ${labeled[2]}` : label;
  }

  return trimmed;
}

function getDirectiveRange(source, directiveName) {
  const directive = new RegExp(`^\\s*\\{${directiveName}:\\s*([^}]*)\\}\\s*$`, "mi");
  const match = source.match(directive);
  if (!match || match.index == null) {
    return null;
  }

  const start = match.index;
  const end = start + match[0].length;
  return { start, end, value: match[1].trim() };
}

function upsertDirective(source, directiveName, value) {
  const lines = source.split(/\r?\n/);
  const directiveLine = `{${directiveName}: ${value}}`;
  const index = lines.findIndex((line) => new RegExp(`^\\s*\\{${directiveName}:`).test(line));

  if (index >= 0) {
    lines[index] = directiveLine;
    return lines.join("\n");
  }

  const insertAt = lines.findIndex((line) => line.trim().length === 0);
  if (insertAt >= 0) {
    lines.splice(insertAt, 0, directiveLine);
    return lines.join("\n");
  }

  return `${directiveLine}\n\n${source}`;
}

function parseChordParts(chord) {
  const match = chord.match(/^([A-G])([#b]?)(.*)$/);
  if (!match) {
    return null;
  }

  const [, root, accidental, suffix] = match;
  const noteName = accidental === "b" ? FLAT_ENHARMONICS.get(`${root}b`) : `${root}${accidental}`;
  const index = NOTE_INDEX.get(noteName);
  if (index == null) {
    return null;
  }

  return { index, suffix };
}

function transposeSingleChord(chord, semitoneOffset) {
  const parts = parseChordParts(chord);
  if (parts == null) {
    return chord;
  }

  const nextIndex = (parts.index + semitoneOffset + 120) % 12;
  return `${NOTE_NAMES[nextIndex]}${parts.suffix}`;
}

function transposeChord(chord, semitoneOffset) {
  const [mainChord, bassChord] = chord.split("/");
  const main = transposeSingleChord(mainChord, semitoneOffset);
  if (bassChord == null) {
    return main;
  }
  return `${main}/${transposeSingleChord(bassChord, semitoneOffset)}`;
}

function formatSignedNumber(value) {
  return value > 0 ? `+${value}` : String(value);
}

function syncSourceControls(parsed) {
  transposeValue.textContent = `Transpose ${formatSignedNumber(parsed.transpose)}`;
  capoValue.textContent = `Capo ${parsed.capo}`;
  capoDownButton.disabled = parsed.capo <= 0;
}

function adjustDirective(name, delta, clamp = null) {
  const parsed = parseChordPro(sourceInput.value);
  const nextValue = clamp == null ? parsed[name] + delta : Math.max(clamp, parsed[name] + delta);
  sourceInput.value = upsertDirective(sourceInput.value, name, nextValue);
  renderSource();
}

function renderHighlightedSource(source) {
  const lines = source.split(/\r?\n/);
  return lines
    .map((line) => {
      if (!line.trim()) {
        return "<span class=\"line\">&nbsp;</span>";
      }

      const escaped = escapeHtml(line);
      const directive = escaped.match(/^(\s*)(\{[^}]+\})(\s*)$/);
      if (directive) {
        const [, leading, content, trailing] = directive;
        const inner = content
          .replace(/^\{([^:}]+):/, (match, name) => {
            const key = escapeHtml(name);
            return `<span class="directive">{</span><span class="directive-key">${key}</span><span class="directive">:</span>`;
          })
          .replace(/\}$/, '<span class="directive">}</span>');
        return `<span class="line">${leading}${inner}${trailing}</span>`;
      }

      const highlighted = escaped
        .replace(/\[[^\]]+\]/g, (match) => `<span class="chord-token">${match}</span>`)
        .replace(/(#.*)$/g, '<span class="comment-token">$1</span>');
      return `<span class="line">${highlighted}</span>`;
    })
    .join("");
}

function parseLyricSegments(lineText, transpose, capo) {
  const chordMatches = [...lineText.matchAll(/\[([^\]]+)\]/g)];
  if (chordMatches.length === 0) {
    return [
      {
        chord: null,
        text: lineText.trimEnd(),
      },
    ];
  }

  return chordMatches.map((match, index) => {
    const nextMatch = chordMatches[index + 1];
    const text = lineText.slice(
      match.index + match[0].length,
      nextMatch ? nextMatch.index : lineText.length,
    );
    return {
      chord: transposeChord(match[1], transpose - capo),
      text,
    };
  });
}

function renderPreviewLines(parsed) {
  const sections = [];
  let currentSection = null;

  if (parsed.capo > 0) {
    readerDirectiveCard.hidden = false;
    readerDirective.textContent = `Capo ${parsed.capo}`;
  } else {
    readerDirectiveCard.hidden = true;
  }

  for (const entry of parsed.bodyLines) {
    if (entry.type === "comment") {
      const label = parseSectionLabel(entry.text);
      if (currentSection && currentSection.lines.length > 0) {
        sections.push(currentSection);
      }
      currentSection = {
        label: label || "Unlabeled",
        lines: [],
      };
      continue;
    }

    if (entry.type === "blank") {
      continue;
    }

    if (currentSection == null) {
      currentSection = {
        label: "Verse 1",
        lines: [],
      };
    }

    currentSection.lines.push(entry.text);
  }

  if (currentSection && currentSection.lines.length > 0) {
    sections.push(currentSection);
  }

  if (sections.length === 0) {
    readerGrid.innerHTML = `
      <article class="section-card">
        <p class="section-label">${escapeHtml(parsed.title || "Song")}</p>
        <div class="section-lines">
          <div class="line-row">
            <div class="segment">
              <div class="chord-row">&nbsp;</div>
              <div class="lyric-row">No renderable song lines yet.</div>
            </div>
          </div>
        </div>
      </article>
    `;
    return;
  }

  readerGrid.innerHTML = sections
    .map((section) => {
      const lines = section.lines
        .map((lineText) => {
          const segments = parseLyricSegments(lineText, parsed.transpose, parsed.capo);
          return `
            <div class="line-row">
              ${segments
                .map(
                  (segment) => `
                    <div class="segment">
                      <div class="chord-row">${segment.chord ? `<span class="chord">${escapeHtml(segment.chord)}</span>` : "&nbsp;"}</div>
                      <div class="lyric-row">${escapeHtml(segment.text || "&nbsp;")}</div>
                    </div>
                  `,
                )
                .join("")}
            </div>
          `;
        })
        .join("");

      return `
        <article class="section-card">
          <p class="section-label">${escapeHtml(section.label)}</p>
          <div class="section-lines">${lines}</div>
        </article>
      `;
    })
    .join("");
}

function updateDerivedSummary(parsed) {
  const title = parsed.title || "Untitled song";
  const artist = parsed.artist || "Unknown artist";
  const key = parsed.key || "—";
  const tempo = parsed.tempo ? `${parsed.tempo} bpm` : "—";
  const tags = parsed.tags.length > 0 ? parsed.tags.join(", ") : "—";
  const settings = `Transpose ${formatSignedNumber(parsed.transpose)} · Capo ${parsed.capo}`;

  derivedTitle.textContent = title;
  derivedArtist.textContent = artist;
  derivedKey.textContent = key;
  derivedTempo.textContent = tempo;
  derivedTags.textContent = tags;
  derivedSettings.textContent = settings;

  previewTitle.textContent = title;
  previewSubtitle.textContent = `${artist} · Key ${key} · Tempo ${tempo}`;
  previewBadges.innerHTML = `
    <span class="badge">Transpose ${formatSignedNumber(parsed.transpose)}</span>
    <span class="badge">Capo ${parsed.capo}</span>
  `;
}

function applyScreen() {
  const screen = body.dataset.screen;
  screenSelect.value = screen;
  for (const tab of tabs) {
    tab.classList.toggle("active", tab.dataset.screen === screen);
  }
  const canonicalView = screen === "preview" ? "preview" : "source";
  applyCanonicalView(canonicalView);
}

function applyCanonicalView(canonicalView) {
  const isPreview = canonicalView === "preview";
  canonicalPanelTitle.textContent = isPreview ? "Preview" : "ChordPro source";
  sourceView.hidden = isPreview;
  previewView.hidden = !isPreview;
  for (const switchButton of canonicalSwitches) {
    switchButton.classList.toggle(
      "active",
      switchButton.dataset.canonicalView === canonicalView,
    );
  }
}

function setStateCard(model) {
  if (!model.title) {
    stateCard.hidden = true;
    stateActions.hidden = true;
    return;
  }

  stateTitle.textContent = model.title;
  stateCopy.textContent = model.copy;
  stateCard.hidden = false;

  const hasActions = Boolean(model.primaryLabel || model.secondaryLabel);
  stateActions.hidden = !hasActions;
  if (hasActions) {
    statePrimaryButton.textContent = model.primaryLabel || "Save";
    stateSecondaryButton.textContent = model.secondaryLabel || "Cancel";
  }
}

function applyState() {
  const state = stateSelect.value;
  body.dataset.state = state;
  const model = stateMap[state] || stateMap.default;

  statusBar.innerHTML = model.status;
  setStateCard(model);

  sourceInput.value = model.sourceValue;
  sourceInput.disabled = state === "loading" || state === "read-only" || state === "empty";

  saveButton.disabled = state === "loading" || state === "read-only" || state === "unauthorized";
  cancelButton.disabled = state === "loading";

  if (state === "conflict") {
    saveButton.textContent = "Keep mine";
    cancelButton.textContent = "Discard mine";
  } else if (state === "pending") {
    saveButton.textContent = "Sync now";
    cancelButton.textContent = "Keep editing";
  } else if (state === "validation-error") {
    saveButton.textContent = "Review";
    cancelButton.textContent = "Cancel";
  } else {
    saveButton.textContent = "Save";
    cancelButton.textContent = "Cancel";
  }

  renderSource();
}

function renderSource() {
  const source = sourceInput.value;
  sourceHighlight.innerHTML = renderHighlightedSource(source);
  const parsed = parseChordPro(source);

  updateDerivedSummary(parsed);
  syncSourceControls(parsed);
  renderPreviewLines(parsed);

  if (parsed.warnings.length > 0 || body.dataset.state === "parse-warning") {
    const warningList = parsed.warnings.length > 0 ? parsed.warnings.join(" · ") : "Recoverable parse warning";
    statusBar.innerHTML = `<span class="badge warn">${warningList}</span>`;
  } else if (body.dataset.state === "offline-cached") {
    statusBar.innerHTML = '<span class="badge">Offline cached</span>';
  } else if (body.dataset.state === "pending") {
    statusBar.innerHTML = '<span class="badge warn">Local mutation pending</span>';
  } else if (body.dataset.state === "conflict") {
    statusBar.innerHTML = '<span class="badge warn">Conflict needs review</span>';
  } else if (body.dataset.state === "unauthorized") {
    statusBar.innerHTML = '<span class="badge warn">Write access denied</span>';
  } else if (body.dataset.state === "read-only") {
    statusBar.innerHTML = '<span class="badge">Read only</span>';
  } else if (body.dataset.state === "empty") {
    statusBar.innerHTML = '<span class="badge warn">Empty song</span>';
  } else if (body.dataset.state === "loading") {
    statusBar.innerHTML = '<span class="badge">Loading song...</span>';
  } else {
    statusBar.innerHTML = "";
  }
}

function syncControls() {
  body.dataset.layout = layoutSelect.value;
  body.dataset.theme = themeSelect.value;
  body.dataset.screen = screenSelect.value;
  applyScreen();
}

function syncHighlightScroll() {
  window.clearTimeout(syncScrollTimer);
  syncScrollTimer = window.setTimeout(() => {
    sourceHighlight.scrollTop = sourceInput.scrollTop;
    sourceHighlight.scrollLeft = sourceInput.scrollLeft;
  }, 0);
}

for (const tab of tabs) {
  tab.addEventListener("click", () => {
    screenSelect.value = tab.dataset.screen;
    syncControls();
  });
}

for (const switchButton of canonicalSwitches) {
  switchButton.addEventListener("click", () => {
    screenSelect.value = switchButton.dataset.canonicalView;
    syncControls();
  });
}

screenSelect.addEventListener("change", syncControls);
layoutSelect.addEventListener("change", syncControls);
themeSelect.addEventListener("change", syncControls);
stateSelect.addEventListener("change", applyState);

sourceInput.addEventListener("input", renderSource);
sourceInput.addEventListener("scroll", syncHighlightScroll);

transposeDownButton.addEventListener("click", () => {
  adjustDirective("transpose", -1);
});

transposeUpButton.addEventListener("click", () => {
  adjustDirective("transpose", 1);
});

capoDownButton.addEventListener("click", () => {
  adjustDirective("capo", -1, 0);
});

capoUpButton.addEventListener("click", () => {
  adjustDirective("capo", 1, 0);
});

saveButton.addEventListener("click", () => {
  if (body.dataset.state === "validation-error") {
    stateSelect.value = "parse-warning";
    applyState();
    return;
  }

  if (body.dataset.state === "conflict") {
    statusBar.innerHTML = '<span class="badge warn">Keep/discard decision required</span>';
    return;
  }

  statusBar.innerHTML = '<span class="badge ok">Saved locally</span>';
});

cancelButton.addEventListener("click", () => {
  stateSelect.value = "default";
  applyState();
  sourceInput.value = DEFAULT_SOURCE;
  renderSource();
});

statePrimaryButton.addEventListener("click", () => {
  if (body.dataset.state === "conflict") {
    statusBar.innerHTML = '<span class="badge ok">Kept local version</span>';
  } else if (body.dataset.state === "pending") {
    statusBar.innerHTML = '<span class="badge ok">Sync requested</span>';
  }
});

stateSecondaryButton.addEventListener("click", () => {
  if (body.dataset.state === "conflict") {
    sourceInput.value = DEFAULT_SOURCE;
    renderSource();
    statusBar.innerHTML = '<span class="badge">Remote version restored</span>';
  }
});

syncControls();
applyState();
renderSource();
