const body = document.body;
const screenSelect = document.getElementById("screen-select");
const layoutSelect = document.getElementById("layout-select");
const themeSelect = document.getElementById("theme-select");
const stateSelect = document.getElementById("state-select");

const songScreen = document.getElementById("song-list-screen");
const pickerScreen = document.getElementById("picker-screen");

const songStateCard = document.getElementById("song-state-card");
const songStateTitle = document.getElementById("song-state-title");
const songStateCopy = document.getElementById("song-state-copy");
const songStatus = document.getElementById("song-status");
const songList = document.getElementById("song-list");
const songSearch = document.getElementById("song-search");
const filterChips = Array.from(document.querySelectorAll("#song-list-screen .chip"));
const songRetryButton = document.getElementById("song-retry-button");

const pickerStateCard = document.getElementById("picker-state-card");
const pickerStateTitle = document.getElementById("picker-state-title");
const pickerStateCopy = document.getElementById("picker-state-copy");
const pickerList = document.getElementById("picker-list");
const pickerSearch = document.getElementById("picker-search");
const pickerStatus = document.getElementById("picker-status");
const pickerCloseButton = document.getElementById("picker-close-button");

const songRows = Array.from(songList.querySelectorAll(".row"));
const pickerRows = Array.from(pickerList.querySelectorAll(".row"));
const pickerAddButtons = Array.from(pickerList.querySelectorAll("button"));

let activeSongFilter = "all";

const songStateMap = {
  default: {
    status: '<span class="badge ok">Online. Songs are up to date.</span>',
    listHidden: false,
    searchValue: "grace",
    title: "",
    copy: "",
  },
  loading: {
    status: '<span class="badge">Refreshing song catalog...</span>',
    listHidden: true,
    searchValue: "",
    title: "Loading",
    copy: "Loading songs...",
  },
  unavailable: {
    status: '<span class="badge warn">No cached song catalog is available yet.</span>',
    listHidden: true,
    searchValue: "",
    title: "Unavailable",
    copy: "No cached song catalog is available yet.",
  },
  empty: {
    status: '<span class="badge ok">Online. Songs are up to date.</span>',
    listHidden: true,
    searchValue: "",
    title: "Empty catalog",
    copy: "No songs available.",
  },
  "no-results": {
    status: '<span class="badge ok">Online. Songs are up to date.</span>',
    listHidden: true,
    searchValue: "xyz",
    title: "No results",
    copy: "No songs match your current search/filter.",
  },
  offline: {
    status: '<span class="badge">Offline. Showing cached songs.</span>',
    listHidden: false,
    searchValue: "grace",
    title: "",
    copy: "",
  },
  failed: {
    status: '<span class="badge warn">Unable to refresh songs. Showing last cached catalog.</span>',
    listHidden: false,
    searchValue: "grace",
    title: "",
    copy: "",
  },
  error: {
    status: '<span class="badge warn">Unable to load songs.</span>',
    listHidden: true,
    searchValue: "",
    title: "Retryable error",
    copy: "Unable to load songs. Please try again.",
  },
};

const pickerStateMap = {
  default: {
    listHidden: false,
    searchValue: "",
    title: "",
    copy: "",
  },
  loading: {
    listHidden: true,
    searchValue: "",
    title: "Loading",
    copy: "Preparing eligible songs...",
  },
  unavailable: {
    listHidden: true,
    searchValue: "",
    title: "Unavailable",
    copy: "Offline song add is unavailable until a local song catalog is available.",
  },
  "no-results": {
    listHidden: true,
    searchValue: "qwerty",
    title: "No results",
    copy: "No eligible songs match your search.",
  },
  "eligible-empty": {
    listHidden: true,
    searchValue: "",
    title: "No eligible songs",
    copy: "All visible songs are already present in this session.",
  },
  "add-in-progress": {
    listHidden: false,
    searchValue: "holy",
    title: "",
    copy: "",
  },
};

function applyScreen() {
  const screen = body.dataset.screen;
  const songMode = screen === "song-list";
  songScreen.hidden = !songMode;
  pickerScreen.hidden = songMode;
}

function syncPickerCloseLabel() {
  const narrow = body.dataset.layout === "narrow";
  pickerCloseButton.textContent = narrow ? "Back" : "Cancel";
}

function normalize(text) {
  return (text || "").trim().toLowerCase();
}

function applySongRowsFromControls() {
  const query = normalize(songSearch.value);

  let visibleCount = 0;
  for (const row of songRows) {
    const title = normalize(row.dataset.songTitle);
    const status = row.dataset.songStatus || "synced";
    const matchesQuery = query.length === 0 || title.includes(query);
    const matchesFilter =
      activeSongFilter === "all" ||
      (activeSongFilter === "pending" && status === "pending") ||
      (activeSongFilter === "conflict" && status === "conflict");
    const show = matchesQuery && matchesFilter;
    row.hidden = !show;
    if (show) {
      visibleCount += 1;
    }
  }

  return visibleCount;
}

function applyPickerRowsFromSearch() {
  const query = normalize(pickerSearch.value);
  let visibleCount = 0;
  for (const row of pickerRows) {
    const title = normalize(row.dataset.pickerTitle);
    const show = query.length === 0 || title.includes(query);
    row.hidden = !show;
    if (show) {
      visibleCount += 1;
    }
  }
  return visibleCount;
}

function setSongStateCard(title, copy) {
  songStateTitle.textContent = title;
  songStateCopy.textContent = copy;
  songStateCard.hidden = false;
}

function hideSongStateCard() {
  songStateCard.hidden = true;
}

function setPickerStateCard(title, copy) {
  pickerStateTitle.textContent = title;
  pickerStateCopy.textContent = copy;
  pickerStateCard.hidden = false;
}

function hidePickerStateCard() {
  pickerStateCard.hidden = true;
}

function applySongState(stateKey) {
  const model = songStateMap[stateKey] || songStateMap.default;
  songStatus.innerHTML = model.status;
  songSearch.value = model.searchValue;
  songList.hidden = model.listHidden;
  songSearch.disabled = model.listHidden;
  songRetryButton.hidden = stateKey !== "error";

  if (model.listHidden) {
    for (const row of songRows) {
      row.hidden = false;
    }
    if (model.title) {
      setSongStateCard(model.title, model.copy);
    } else {
      hideSongStateCard();
    }
    return;
  }

  const count = applySongRowsFromControls();
  if (count === 0) {
    setSongStateCard("No results", "No songs match your current search/filter.");
    return;
  }

  hideSongStateCard();
}

function applyPickerState(stateKey) {
  const model = pickerStateMap[stateKey] || pickerStateMap.default;
  pickerSearch.value = model.searchValue;
  pickerList.hidden = model.listHidden;
  pickerSearch.disabled = ["loading", "unavailable", "eligible-empty"].includes(stateKey);
  const addInProgress = stateKey === "add-in-progress";
  for (const button of pickerAddButtons) {
    button.disabled = addInProgress;
    button.textContent = addInProgress ? "Adding..." : "Add";
  }
  if (addInProgress) {
    pickerStatus.innerHTML = `
      <span class="badge">Session: Response Set</span>
      <span class="badge">Eligible songs only</span>
      <span class="badge">Sort: Title (A-Z)</span>
      <span class="badge warn">Adding song locally...</span>
    `;
  } else {
    pickerStatus.innerHTML = `
      <span class="badge">Session: Response Set</span>
      <span class="badge">Eligible songs only</span>
      <span class="badge">Sort: Title (A-Z)</span>
    `;
  }

  if (model.listHidden) {
    for (const row of pickerRows) {
      row.hidden = false;
    }
    if (model.title) {
      setPickerStateCard(model.title, model.copy);
    } else {
      hidePickerStateCard();
    }
    return;
  }

  const count = applyPickerRowsFromSearch();
  if (count === 0) {
    setPickerStateCard("No results", "No eligible songs match your search.");
    return;
  }

  hidePickerStateCard();
}

function applyState() {
  const state = stateSelect.value;
  if (body.dataset.screen === "song-list") {
    applySongState(state);
    return;
  }

  applyPickerState(state);
}

screenSelect.addEventListener("change", (event) => {
  body.dataset.screen = event.target.value;
  stateSelect.value = "default";
  applyScreen();
  applyState();
});

layoutSelect.addEventListener("change", (event) => {
  body.dataset.layout = event.target.value;
  syncPickerCloseLabel();
});

themeSelect.addEventListener("change", (event) => {
  body.dataset.theme = event.target.value;
});

stateSelect.addEventListener("change", applyState);
songSearch.addEventListener("input", () => {
  if (body.dataset.screen !== "song-list") {
    return;
  }
  if (!["default", "offline", "failed"].includes(stateSelect.value)) {
    return;
  }
  applySongState(stateSelect.value);
});

for (const chip of filterChips) {
  chip.addEventListener("click", () => {
    activeSongFilter = chip.dataset.filter || "all";
    for (const candidate of filterChips) {
      candidate.classList.toggle("active", candidate === chip);
      candidate.setAttribute(
        "aria-pressed",
        candidate === chip ? "true" : "false",
      );
    }
    if (body.dataset.screen !== "song-list") {
      return;
    }
    if (!["default", "offline", "failed"].includes(stateSelect.value)) {
      return;
    }
    applySongState(stateSelect.value);
  });
}

pickerSearch.addEventListener("input", () => {
  if (body.dataset.screen !== "picker") {
    return;
  }
  if (!["default", "no-results"].includes(stateSelect.value)) {
    return;
  }
  stateSelect.value = "default";
  applyPickerState("default");
});

for (const row of songRows) {
  row.addEventListener("keydown", (event) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }
    event.preventDefault();
    songStatus.innerHTML = '<span class="badge ok">Demo: open reader from selected song.</span>';
  });
}

for (const row of pickerRows) {
  const activate = () => {
    if (stateSelect.value !== "default") {
      return;
    }
    stateSelect.value = "add-in-progress";
    applyState();
  };
  row.addEventListener("click", activate);
  row.addEventListener("keydown", (event) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }
    event.preventDefault();
    activate();
  });
}

pickerCloseButton.addEventListener("click", () => {
  body.dataset.screen = "song-list";
  screenSelect.value = "song-list";
  stateSelect.value = "default";
  applyScreen();
  applyState();
});

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") {
    return;
  }
  if (body.dataset.screen !== "picker") {
    return;
  }
  body.dataset.screen = "song-list";
  screenSelect.value = "song-list";
  stateSelect.value = "default";
  applyScreen();
  applyState();
});

songRetryButton.addEventListener("click", () => {
  stateSelect.value = "default";
  applyState();
});

applyScreen();
syncPickerCloseLabel();
applyState();
