# Paged Pull Residuals

**Slice:** fix/paged-remote-pulls (S5a; found by the final adversarial review
on 2026-10-12)
**Related:** `docs/specs/2026-10-12-paged-remote-pulls.md` (PG5, PG8, PG11),
ADR-041, invariant I7 of
`docs/specs/2026-09-29-plan-delete-and-session-cascade.md`
**Files:**
- `apps/lyron_app/lib/src/infrastructure/planning/supabase_planning_repository.dart`
- `apps/lyron_app/lib/src/application/planning/planning_sync_controller.dart`

The review found no silent row loss, no cross-organization or cross-user
row, and no break of I7 caused by the change. These are the residuals it
rated non-blocking.

## R1. A reorder between two pages can tear positions

A plan's sessions, or a session's items, can now span two pages read at
different times. A reorder RPC that commits between those pages can leave
two rows with the same `position`, or a mix of old and new positions, in the
projection. Ties are broken by id; the local tables have no position
uniqueness.

- No row is lost. The reorder bumped `content_version` after the plan
  stream read it, so the projection is behind (safe for a delete, I7).
- Visible effect: an odd order until the next refresh.
- Fix if it ever shows: re-read the affected streams when a page boundary
  splits one parent, or compare each plan's `content_version` before and
  after the child streams and retry the refresh when it moved.

## R2. A membership revoked between streams stores childless plans

If the membership is revoked after the plans stream and before the sessions
stream, RLS returns empty session and item pages. The projection then holds
plans with their `content_version` and no children: `content_version` is
ahead of the stored children.

- Not new: main's per-plan session reads had the same shape.
- Reachable harm needs the membership to be restored and the user to delete
  that plan before any further refresh; ADR-016's verified-empty purge
  usually removes the projection first.
- Fix options: reject a payload in which a plan with `content_version > 1`
  has no sessions, or re-check membership after the child streams.

## R3. A throwing observability adapter would leave the refresh "refreshing"

Both controllers report a `PagedReadContractException` before they set the
`failed` state (PG8). If `Observability.captureException` threw,
`refreshStatus` would stay `refreshing`. The Sentry adapter calls
`Sentry.captureException` without awaiting it, so this does not happen
today. Fix: set the state first, or guard the report with try/catch.

## R4. The `session_items` stream has no organization index

PG11: the items stream is a primary-key range scan filtered by
`organization_id`. Acceptable for a single-organization database. If it ever
matters, add an `(organization_id, id)` index as a separate backend chore
(hosted deploys are manual).

Roadmap (2026-10-12): scheduled in S5b (R2, fixed with a membership re-check after the child streams, not the `content_version > 1` rejection, because a plan whose sessions were all deleted legitimately has that shape) and S6b (R3); R1 and R4 stay trigger-gated (S9).
