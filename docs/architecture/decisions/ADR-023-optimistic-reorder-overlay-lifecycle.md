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

An optimistic reorder overlay survives exactly as long as its write is in
flight, plus at most one further disagreeing reload. The rule is pure and
lives in `application/planning/planning_reorder_overlay.dart`:

```
resolveReorderOverlay(
  optimisticOrder,
  projectionOrder,
  hasWriteInFlight,
  hasConsumedPostWriteReload,
)
```

- no overlay → null
- write in flight → keep the overlay
- structurally incompatible with the projection → drop it
- projection order equals the optimistic order → drop it (the projection has
  caught up and is the single source of truth again)
- projection disagrees and the post-write grace has not been consumed yet →
  keep the overlay
- projection disagrees and the grace has already been consumed → drop it (the
  projection is authoritative now)

The grace exists because the invalidation issued when the write completes can
be overtaken by a read that was already in flight: the very first projection
to arrive after completion may still reflect the pre-invalidation state, and
dropping the overlay on it would flash the stale order. That is a one-time
allowance, not a standing exemption — at most one post-write reload may
disagree with the overlay before the projection wins. A second (or later)
disagreement is treated as authoritative: a concurrent reorder from another
device, a server-side reconciliation, or a rejected-but-not-failed write, and
the overlay is dropped so the refreshed projection is shown.

"In flight" is derived from the existing generation counters: a
`_lastCompleted…ReorderGeneration` field is set on both the success and the
failure path, and in-flight means the two generations differ. Each screen also
tracks whether the post-write grace has been consumed for the current
optimistic order: the flag resets to `false` wherever the generation counter
is bumped (a new reorder write starting) and is set to `true` the first time
the rule is consulted with the write no longer in flight and a disagreeing
projection. The rule is applied when a fresh, settled projection arrives,
before the list is built — the field is assigned directly, never through
`setState` during `build`. A projection carried over from before the
provider's own reload settles (the transient value `skipLoadingOnReload` /
`skipLoadingOnRefresh` surface while refetching) is not treated as a fresh
arrival and does not consult the rule or spend the grace.

A rollback caused by a write failure also surfaces
`AppStrings.planningReorderFailedMessage` to the user, in addition to the
existing `FlutterError.reportError` call. A **superseded** (stale) failure stays
silent, as it was before: the newer drag already owns the overlay, so reporting
the older failure would be noise.

The same rule and the same message apply to the session-level overlay in
`plan_detail_screen.dart` and the item-level overlay in
`widgets/plan_session_card.dart`.

Consuming the grace only records that it was spent; dropping the overlay
still requires another build with a settled projection, and nothing
otherwise guarantees one ever arrives. If the first post-write projection
disagrees and no independent invalidation follows, the optimistic order
would keep masking the server state until some unrelated rebuild happened to
occur. Each screen closes that gap itself: the moment the grace is consumed,
it schedules exactly one follow-up refresh, via
`WidgetsBinding.instance.addPostFrameCallback`, of the same family-scoped
provider it already depends on (`planningPlanDetailProvider(planId)`), so the
rule is guaranteed to be re-consulted against a fresh projection. A second
"follow-up already scheduled" flag — reset alongside the consumed flag
whenever the generation counter bumps — keeps this to one invalidate per
consumed grace rather than one per build, which would otherwise loop. Once
that follow-up projection arrives, the rule above drops the overlay (either
because it now matches, or because the grace is spent and a second
disagreement is authoritative), and with the overlay gone nothing schedules
again — the lifecycle always terminates without depending on an unrelated
rebuild.

## Consequences

- The overlay can no longer outlive the write it belongs to plus one
  disagreeing reload, so a refreshed projection is never masked indefinitely —
  a stale-but-compatible order beyond that single grace reload is always
  superseded.
- The lifecycle rule is unit tested without a widget tree; the screen wiring is
  covered by widget tests that force the refetch-during-write interleaving.
- Reorder failures are visible to the user without changing the write path or
  the mutation/projection boundary of ADR-014.
