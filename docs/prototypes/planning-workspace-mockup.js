const body = document.body;
const screenSelect = document.getElementById("screen-select");
const layoutSelect = document.getElementById("layout-select");
const themeSelect = document.getElementById("theme-select");
const stateSelect = document.getElementById("state-select");

const workspaceStatus = document.getElementById("workspace-status");
const planStateCard = document.getElementById("plan-state-card");
const planStateTitle = document.getElementById("plan-state-title");
const planStateCopy = document.getElementById("plan-state-copy");
const planRetryButton = document.getElementById("plan-retry-button");
const detailStateCard = document.getElementById("detail-state-card");
const detailStateTitle = document.getElementById("detail-state-title");
const detailStateCopy = document.getElementById("detail-state-copy");
const mutationBanner = document.getElementById("mutation-banner");
const mutationTitle = document.getElementById("mutation-title");
const mutationCopy = document.getElementById("mutation-copy");
const mutationAction = document.getElementById("mutation-action");
const conflictList = document.getElementById("conflict-list");
const addSongButtons = Array.from(document.querySelectorAll("#session-editor-surface .add-song"));

const stateMap = {
  default: {
    status: '<span class="badge ok">Planning data up to date</span>',
  },
  loading: {
    status: '<span class="badge">Loading planning workspace...</span>',
    plan: ["Loading", "Loading plans..."],
    detail: ["Loading", "Loading selected plan..."],
  },
  empty: {
    status: '<span class="badge ok">Planning data up to date</span>',
    plan: ["No plans", "Create a plan to start preparing a service."],
  },
  "no-sessions": {
    status: '<span class="badge ok">Planning data up to date</span>',
    detail: ["No sessions", "Add a session to start building this plan."],
  },
  "empty-session": {
    status: '<span class="badge ok">Planning data up to date</span>',
    detail: ["Empty session", "Response Set has no songs yet."],
  },
  "catalog-unavailable": {
    status: '<span class="badge warn">No local song catalog available</span>',
    detail: ["Song add unavailable", "Add song remains disabled until a local song catalog is available."],
    disableAddSong: true,
  },
  "offline-cached": {
    status: '<span class="badge">Offline. Showing cached planning data.</span>',
  },
  pending: {
    status: '<span class="badge warn">Local planning changes pending</span>',
    banner: ["Local changes pending", "Changes are saved locally and will sync when available.", "Retry"],
  },
  conflict: {
    status: '<span class="badge warn">Planning conflict needs review</span>',
    banner: ["Conflict", "Review each affected local change.", "Refresh"],
    showConflicts: true,
  },
  "auth-denied": {
    status: '<span class="badge warn">Planning authorization changed</span>',
    banner: ["Authorization denied", "Backend rejected this local change for the active organization.", "Review"],
  },
  "retryable-failure": {
    status: '<span class="badge warn">Unable to load planning data</span>',
    plan: ["Retryable failure", "Planning data could not load. Try again."],
    detail: ["Retryable failure", "Selected plan could not load. Try again."],
    retry: true,
  },
};

function setStateCard(card, titleNode, copyNode, model) {
  if (!model) {
    card.hidden = true;
    return;
  }
  titleNode.textContent = model[0];
  copyNode.textContent = model[1];
  card.hidden = false;
}

function applyState() {
  const state = body.dataset.state;
  const model = stateMap[state] || stateMap.default;
  workspaceStatus.innerHTML = model.status;
  setStateCard(planStateCard, planStateTitle, planStateCopy, model.plan);
  setStateCard(detailStateCard, detailStateTitle, detailStateCopy, model.detail);
  planRetryButton.hidden = !model.retry;
  for (const button of addSongButtons) {
    button.disabled = Boolean(model.disableAddSong);
  }

  if (model.banner) {
    mutationTitle.textContent = model.banner[0];
    mutationCopy.textContent = model.banner[1];
    mutationAction.textContent = model.banner[2];
    mutationBanner.hidden = false;
  } else {
    mutationBanner.hidden = true;
  }
  conflictList.hidden = !model.showConflicts;
}

function syncControls() {
  body.dataset.screen = screenSelect.value;
  body.dataset.layout = layoutSelect.value;
  body.dataset.theme = themeSelect.value;
  body.dataset.state = stateSelect.value;
  applyState();
}

screenSelect.addEventListener("change", syncControls);
layoutSelect.addEventListener("change", syncControls);
themeSelect.addEventListener("change", syncControls);
stateSelect.addEventListener("change", syncControls);
syncControls();
