# Sync UX Contract

Canonical UX contract for sync status surfaces in authenticated non-reader workspaces.

See [domain-vocabulary.md](../domain/domain-vocabulary.md) for term definitions.  
See [state-machines.md](../architecture/state-machines.md) for entity lifecycle patterns.

## Manual Sync Contract

A visible manual sync action means "sync my local work and refresh my current workspace", not "refresh only this list."

The unified manual sync must:

- sync pending song mutations for the active authenticated organization
- sync pending planning mutations for the active authenticated organization
- refresh song catalog data after song sync attempts
- refresh planning projections after planning sync attempts
- leave domain-specific recovery actions visible for conflicts, authorization denials, and dependency-blocked mutations
- not hide failed or conflicted work behind a single generic error state

Song sync requests for the same authenticated user and active organization
coalesce into one run. If a request arrives while discard owns that context, it
queues behind the discard and coalesces with any other waiting sync request;
the run takes its mutation snapshot only after discard completes.

## Header Sync Control

Authenticated non-reader workspaces show one consistent sync status control in the header. This replaces separate screen-specific top-level sync banners.

Surfaces that show the header sync control:

- song library
- plan list
- plan detail
- future authenticated management or editing surfaces

The song reader does not show the header sync control. Reader surfaces stay focused on reading and presenting songs.

The song create/edit workspace also does not show the header sync control. Its explicit `Cancel`/`Save` affordances and dirty state already communicate local persistence intent, so a background workspace-sync indicator there is redundant and visually misplaced. This supersedes the editor inclusion from [2026-05-02-song-editing-ui](../specs/2026-05-02-song-editing-ui.md) and [2026-05-29-sync-ui-consolidation](../specs/2026-05-29-sync-ui-consolidation.md); see [2026-06-06-header-consistency-and-sync-presentation](../specs/2026-06-06-header-consistency-and-sync-presentation.md).

### Header Presentation

The header sync control renders as a single colored status dot. The status word (`Synced`, `Unsynced`, `Conflict`) and any secondary connectivity or freshness detail are exposed through the control's tooltip and the status popup rather than as always-visible header text. This keeps the header compact and consistent with the icon-based header actions across workspaces. Color remains the primary signal; the status words below name the colors and the tooltip/popup copy, not a required inline label.

### Status Colors

Three primary sync colors:

- **Green `Synced`**: no known local divergence and no unresolved sync issue.
- **Yellow `Unsynced`**: local work exists that has not been accepted by the backend.
- **Red `Conflict`**: at least one local item or order intent needs user action or targeted recovery.

The header status is aggregated across active-organization song and planning work. Red wins over yellow, and yellow wins over green.

Status mapping:

- **Green `Synced`**: no durable local `Created`, `Edited`, `Removed`, or `Reordered` intent exists, and no conflict state exists.
- **Yellow `Unsynced`**: one or more `Created`, `Edited`, `Removed`, or `Reordered` states exist. Retryable network, timeout, or temporary backend failures remain yellow because the local intent is still retryable.
- **Red `Conflict`**: one or more `CreatedConflict`, `EditedConflict`, `RemovedConflict`, or `ReorderConflict` states exist, or the backing sync metadata represents `authorization_denied`, `dependency_blocked`, `remote_missing`, or another non-retryable rejection.

Connectivity and freshness are secondary status dimensions. Offline cached data may still show green if there is no known local divergence or unresolved sync issue. Offline or stale status is surfaced through the control tooltip and the status popup rather than changing the primary green/yellow/red sync color.

### Header Status Popup

Clicking or tapping the header sync control opens a compact popup or sheet with non-synced details. Synced items are not listed.

The popup shows:

- a grouped summary of unsynced and conflict counts
- a global `Sync now` action
- song-level rows for unsynced or conflicted songs
- plan-level rows for unsynced or conflicted planning work
- domain-specific recovery actions where available

Song rows list the song title and item state: `Created`, `Edited`, `Removed`, `CreatedConflict`, `EditedConflict`, or `RemovedConflict`.

Planning rows are grouped by plan. Session, session item, and reorder mutations do not appear as top-level popup rows because users experience them as part of plan editing. A plan row may expose a short nested detail list: `plan edited`, `session added`, `session removed`, `session order changed`, `song added`, `song removed`, or `song order changed`.

Planning popup grouping uses the best available identity in this order:

1. current merged plan title when available
2. mutation name or slug
3. preserved origin snapshot title
4. stable aggregate id as the last resort

Failed plan creates appear as their own plan-level rows. Mutations for sessions or session items whose parent plan is unavailable must still appear under a recoverable plan-level fallback row instead of disappearing from the popup.

### Recovery Actions

Song rows expose **Keep mine** and **Discard mine** buttons for conflict-severity rows. Pending and retryable rows have no per-row actions — the global `Sync now` covers them.

Plan rows expose group-level recovery actions for all mutations belonging to that plan:

- Conflict severity: **Keep mine** (retries all grouped mutations) and **Discard mine** (discards all grouped mutations).
- Retryable failure severity: **Retry** (retries all grouped mutations).
- Pending severity: no per-row action.

The popup header also exposes a **Discard all** action (destructive, styled with the error color) when `hasUnsyncedWork` is true. Tapping opens a confirmation dialog naming the count of affected songs and plans. On confirm, all local song and planning mutations for the active organization are discarded. The scope matches `Sync now`.

Song sync and discard are mutually exclusive for the active `(userId,
organizationId)` context. A per-row song discard attempted while sync owns that
context returns immediately with no local change. **Discard all** must acquire
the song-context discard lease before either song or planning discard begins;
if sync already owns it, the whole request is rejected before either domain
changes. This is an atomic admission rule, not a promise of transactional
rollback after an admitted multi-domain discard starts.

The expected rejection has dedicated guidance: **“Sync is in progress. Try
again after it finishes.”** It must not show the generic “action could not be
completed” or “some changes could not be discarded” message. Generic failure
copy is reserved for unexpected failures after admission, not the typed
`syncInProgress` result (the typed sync in progress outcome).

The popup does not hide domain-specific recovery. The red header label may use `Conflict` as the compact top-level status, but popup rows must show the specific blocking reason where known: `conflict`, `authorization_denied`, `dependency_blocked`, `remote_missing`, or another non-retryable rejection. These reasons must not collapse into a generic conflict message in the detailed view.

Retry may appear for retryable unsynced rows as well as recovery rows where retry is meaningful. Non-retryable conflict rows should prefer explicit recovery actions such as discard, explicit overwrite, explicit remove, or explicit reorder overwrite.

## Inline Status Responsibility

Screen-level status surfaces (the song catalog banner, the per-song mutation cards, and the `PlanningWorkspaceStatusSurface`) and the pending/conflict browse filter have been removed.

The header control and popup are now the single sync surface for authenticated non-reader workspaces:

- the header sync control answers "is this workspace fully synced?"
- the popup answers "what is not synced, why, and how do I fix it?"

Inline row badges remain available for future use to locate affected items in the current view, but no such badges are currently rendered.
