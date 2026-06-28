# ADR-019: Exactly-Once Planning Mutation Sync via Durable Accepted Marker

## Status

Accepted

## Date

2026-06-28

## Relates To

ADR-014, ADR-015

## Context

The prior planning mutation sync loop refreshed once per mutation, had no durable record that a write was backend-accepted, allowed overlapping concurrent sync triggers, gated discard/retry behind a successful refresh, and dropped failed/conflict edits from the merged read.

This created several correctness gaps:

- **At-least-once semantics**: A crash between backend acceptance and local mutation clear could cause a resend on the next run, potentially duplicating a write that the backend had already accepted. The app had no way to recover except by manual conflict resolution or data correction.
- **Double-send under concurrency**: Manual sync, foreground-resume, offline-to-online transition, and discard could all trigger `syncPendingMutations` simultaneously, causing overlapping backend RPCs for the same mutation and unpredictable ordering.
- **Offline operability gap**: Discard and retry required a successful full refresh first, so a user could not clear a stuck mutation or requeue it while offline.
- **Silent edit loss**: Failed and conflicted edits disappeared from the merged read path, reverting the user's view to the last server state without explanation, so users could not see what had failed or what the conflict was.

## Decision

Implement exactly-once planning mutation sync with the following controls:

1. **Durable accepted marker**: Mark a mutation as `accepted` before the batch refresh runs, using a free-text `sync_status` column (no schema migration). On the next sync run, skip re-send for already-`accepted` rows and reconcile them into the local projection before clearing, preventing double-send after a crash.

2. **Single-flight guard**: Coalesce concurrent sync triggers (manual sync, foreground-resume, offline-to-online transition, discard) into one in-flight run. Concurrent `syncPendingMutations` calls made while a run is in flight return the same in-flight future and share that single run; no overlapping backend sends occur. The run is not repeated for the additional callers.

3. **Batch refresh optimization**: Send all mutations in a batch before running the full refresh, not once per mutation. Skip the refresh entirely when no mutations were accepted in the batch.

4. **Offline discard/retry**: Discard and retry update local write intent unconditionally and then sync best-effort, without requiring a successful refresh first. This allows users to clear or requeue stuck mutations while offline.

5. **Actionable-mutation merge**: Overlay not just pending mutations but all actionable mutations (pending, accepted, failed-authorization, failed-dependency, failed-remote-delete, conflict) in the merged local-first read. This keeps failed and conflicted edits visible for review instead of silently reverting to the last server state.

6. **Visible-edit guard**: When a `planEdit` overlay record leaves description or scheduledFor unset, do not blank those fields in the merged view; preserve the last known value from the projection or previous edit state. This prevents silent data loss when the user explicitly did not modify those fields.

7. **Extracted reconciler**: Move the accepted-mutation reconciliation logic into an injected, independently testable `PlanningMutationReconciler` unit instead of inline provider logic. This makes the exactly-once contract testable in isolation and easier to evolve.

## Consequences

- **Exactly-once sync**: Mutations are never re-sent after backend acceptance, even if a crash occurs between acceptance and local clear. The `accepted` marker is durable and checked before sending.
- **No double-send under concurrency**: Single-flight coalescing prevents overlapping sends for the same mutation when multiple triggers fire at once.
- **Offline operability**: Users can discard or retry stuck mutations without waiting for a successful refresh, improving usability in unreliable network conditions.
- **Visible failed edits**: Failed and conflicted edits remain visible in the merged read for user review and explicit action, instead of silently reverting to the server state.
- **No-sync optimization**: When no mutations are accepted in a batch, the full refresh is skipped, reducing unnecessary backend traffic.
- **Testable architecture**: The `PlanningMutationReconciler` is independently testable, making sync-correctness behavior explicit and regression-proof.

## Limitations

- The visible-edit guard cannot fully represent an intentional clear-to-null (setting a field to null); the merged view will preserve the last non-null value if the edit record does not include the field. Full support for intentional nulls is deferred.
- Single-flight coalescing shares one in-flight run across concurrent callers; a mutation enqueued after the in-flight run has already read its candidate set is not picked up by that shared run. It is synced by the next sync trigger (foreground-resume, manual sync, offline-to-online transition, etc.), not by an automatic rerun. This is acceptable for manual sync and background reconnection triggers.

## Future Work

- Realtime subscription events should request a refresh rather than directly mutating mutation state; this contract does not change that decision from ADR-015.
- Conflict resolution, remote-delete recovery, and authorization-failure replay remain explicit and manual in the MVP; automatic retry policies are deferred.

## Validation

The local-first-validation slice (2026-06-29) added adversarial regression coverage that
exercises this decision's exactly-once contract directly, rather than relying solely on the
happy-path coverage already listed under "Testable architecture":

- `apps/lyron_app/test/offline/adversarial/planning_fault_injection_test.dart` validates the
  durable-accepted-marker contract (`LF-1`: a crash between backend acceptance and local
  clear does not re-send the mutation on the next run) and the batch-refresh contract
  (`LF-2`: a partial-RPC-success batch followed by a failed refresh still reconciles
  correctly afterward).
- `apps/lyron_app/test/offline/adversarial/song_single_flight_test.dart` validates the
  single-flight guard (`LF-3`) for the song mutation sync path. The planning path was
  already guarded by this ADR; this suite closes the equivalent gap on
  `SongMutationSyncController.syncPendingSongs`, which previously had no internal
  single-flight coalescing.

Both suites are part of the broader adversarial offline/sync validation effort recorded in
`docs/testing/testing-strategy.md`.
