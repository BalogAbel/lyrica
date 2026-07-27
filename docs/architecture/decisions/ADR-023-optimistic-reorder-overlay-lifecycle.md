# ADR-023: Optimistic Reorder Overlay Lifecycle

- Status: Accepted
- Date: 2026-07-27
- Related: [ADR-014-planning-write-projection-mutation-boundary.md](ADR-014-planning-write-projection-mutation-boundary.md)
- Spec: `docs/specs/2026-07-27-arch3-ui-decomposition.md`
- Plan: `docs/plans/2026-07-27-arch3-ui-decomposition.md`
- Findings: `ARCH-3`
- Closes: `docs/deferred/2026-04-30-planning-reorder-optimistic-state.md`

## Context

Plan detail keeps an optimistic order overlay in widget state for both session
reorder and session-item reorder, so a drag stays visible while the local write
and the provider invalidation settle.

The overlay had no end condition. It was cleared only when the write failed, or
implicitly ignored when the refreshed projection was structurally incompatible
with it (different length, or an id that no longer exists). On success it was
never cleared, so an overlay that stayed structurally compatible masked every
later projection for the lifetime of the screen — including projections that
legitimately disagreed with it, such as a reorder reconciled differently by
sync. Failure was also invisible: the drag undid itself and only
`FlutterError.reportError` recorded why.

The deferred entry recorded this as a cleanup-semantics gap, deliberately left
out of the originating slice because the write path was already correct.

## Decision

An optimistic reorder overlay survives exactly as long as its write is in flight
or the refreshed projection disagrees with it. The rule is pure and lives in
`application/planning/planning_reorder_overlay.dart`:

```
resolveReorderOverlay(optimisticOrder, projectionOrder, hasWriteInFlight)
```

- no overlay → null
- write in flight → keep the overlay
- structurally incompatible with the projection → drop it
- projection order equals the optimistic order → drop it (the projection has
  caught up and is the single source of truth again)
- otherwise → keep it (the projection has not caught up yet)

"In flight" is derived from the existing generation counters: a
`_lastCompleted…ReorderGeneration` field is set on both the success and the
failure path, and in-flight means the two generations differ. The rule is
applied when a fresh projection arrives, before the list is built — the field is
assigned directly, never through `setState` during `build`.

A rollback caused by a write failure also surfaces
`AppStrings.planningReorderFailedMessage` to the user, in addition to the
existing `FlutterError.reportError` call. A **superseded** (stale) failure stays
silent, as it was before: the newer drag already owns the overlay, so reporting
the older failure would be noise.

The same rule and the same message apply to the session-level overlay in
`plan_detail_screen.dart` and the item-level overlay in
`widgets/plan_session_card.dart`.

## Consequences

- The overlay can no longer outlive the write it belongs to, so a refreshed
  projection is never masked indefinitely.
- The lifecycle rule is unit tested without a widget tree; the screen wiring is
  covered by widget tests that force the refetch-during-write interleaving.
- Reorder failures are visible to the user without changing the write path or
  the mutation/projection boundary of ADR-014.
