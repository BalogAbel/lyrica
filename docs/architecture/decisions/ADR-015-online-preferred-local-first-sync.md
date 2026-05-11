# ADR-015: Online-Preferred Local-First Sync Contract

## Status

Accepted

## Context

Lyron already uses local-first reads and writes for songs and planning, but the product direction needs one durable contract for mixed online/offline behavior.

Some flows are fully local-first writes with durable mutation queues. Other flows are online refresh paths that preserve the previous local projection when refresh fails. Both are valid, but users should experience them as one coherent system: online work should feel fresh and collaborative, while offline work should remain safe and usable.

Future realtime subscriptions create an additional risk. If subscription payloads become a direct UI data source, the app could bypass repository-owned projection replacement, mutation overlays, backend authorization checks, and refresh-failure preservation.

## Decision

Use an online-preferred, offline-safe, local-first sync contract.

For Lyron:

- UI reads come from repository-owned local projections or merged local-first views.
- Online refresh improves freshness but does not become required for core preparation work when usable local state exists.
- Local write intent remains durable until backend acceptance, explicit discard, conflict resolution, or explicit sign-out cleanup.
- Entity lifecycle state is separate from sync activity, connectivity, and freshness. For songs, syncing is transient activity over durable local states such as created, synced, edited, removed, and intent-specific conflict states.
- Manual sync should converge all active-organization local work, not only the current screen's data.
- Offline-to-online and foreground/resume events should trigger refresh and pending mutation sync where platform signals are available.
- Realtime subscription events are invalidation triggers only.
- Subscription events must call existing refresh paths instead of directly mutating UI state.
- Missed subscription events must be recoverable through reconnect, foreground refresh, periodic refresh, or manual sync.
- Backend authorization remains authoritative for canonical write acceptance.
- Explicit sign-out continues to clear authenticated cached data and must warn when unsynced mutations exist.

## Consequences

- The app can feel online and current without weakening offline guarantees.
- Song and planning sync status can be aggregated into one user-facing overview while keeping domain-specific conflict and recovery actions.
- Future realtime work has a clear boundary: subscriptions request refresh; they do not replace refresh.
- Implementation work must preserve previous local projections on refresh failure.
- Testing must cover mixed song/planning pending queues, reconnect behavior, foreground refresh behavior, refresh-failure preservation, and sign-out warnings.
