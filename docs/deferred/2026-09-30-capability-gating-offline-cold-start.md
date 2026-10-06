# Capability Gating Is Fail-Open After an Offline Cold Start

**Slice:** feat/plan-delete-session-cascade (found by review gate 4 on
2026-09-30, F5; the mechanism predates that slice and gates every
`IfCapability` affordance, not only delete)
**Related:**
- `docs/specs/2026-09-29-plan-delete-and-session-cascade.md` (I6, D9, D10,
  D11, Acceptance 5)
- AGENTS.md rule 5 (authorization is backend-enforced)
- `docs/architecture/architecture.md` (the Flutter client consumes capability
  results only for UX affordances)

**Files:**
- `apps/lyron_app/lib/src/presentation/shared/if_capability.dart`
  (`IfCapability`: the `catchError((_) => true)` fail-open and the `catch`
  around `ref.watch(capabilityResolverProvider)`)
- `apps/lyron_app/lib/src/application/auth/capability_resolver.dart`
  (`CapabilityResolver`: the in-memory `_cache` and `_resolved` maps,
  `SupabaseCapabilityGateway.resolve`)
- `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`
  (`plan-delete-capability` and the session and plan edit gates)
- `apps/lyron_app/lib/src/presentation/planning/widgets/plan_session_card.dart`
  (`session-delete-button-<id>`)

## Problem

`IfCapability` fails open on purpose. When capability resolution fails (a
transient network error, or an offline cold start), it renders the child. The
resolver's cache is in memory only, so nothing survives a process restart.

On an offline cold start a read-only member therefore sees the plan delete
item and the session delete button. If they use it:

- The delete is recorded locally and the plan (or session) disappears from
  every merged read (D10).
- On reconnect the backend rejects the RPC. `delete_plan` folds its
  capability check into the plan lookup
  (`supabase/migrations/202609290001_plan_content_version_and_cascade_delete.sql`),
  so a caller without `canManagePlans` or `canEditSessions` gets
  `plan_not_found`. The client classifies that as `failedRemoteDelete`.
- The plan stays hidden behind the pending delete, and the sync popup shows
  "Planning sync could not find the target item on the server."
  (`AppStrings.planRemoteMissingMessage`), until the member discards the row.
  The copy says nothing about permissions.

I6 holds: the backend is the authority, and nothing is deleted on the server.
The defect is a local affordance that lies, followed by a message that does
not say why the delete failed.

## Why it was deferred

Fail-open is a deliberate trade-off, not an oversight. The app is
offline-first: a legitimate editor must be able to delete (and edit) offline
after a cold start. Failing closed would take those affordances away from
everyone who is offline and has no cached answer. Authorization is
backend-enforced (AGENTS.md rule 5), so the worst outcome of the current
behavior is a confusing but recoverable local state. The mechanism also
predates the slice and is shared by every gated affordance, so changing it
inside the plan-delete PR would widen its blast radius.

## Options

### (a) Persist resolved capabilities per user and organization

- Store the last successfully resolved `Set<Capability>` (for example in the
  local Drift database, keyed by user id and organization id).
- `CapabilityResolver` seeds `_resolved` from the stored set on startup, so
  `hasCapabilitySync` answers before the network does. A successful resolve
  replaces the stored set; a failed resolve keeps it.
- Only a context with no stored answer stays fail-open (first launch offline).
- Must be cleared on sign-out, and keyed by user so one user's grants never
  apply to another on a shared device.
- A stale stored set can be wrong in both directions (a role revoked or
  granted while offline). The backend stays the authority, so this only
  improves the affordance.

### (b) Clearer copy for a rejected delete

- Give a delete that the backend rejects for lack of capability its own
  classification and copy in the sync popup, instead of reusing
  `planRemoteMissingMessage`.
- The backend deliberately answers `plan_not_found` for a missing
  capability, so the client cannot tell the two apart from the error code
  alone. Either the copy becomes generic ("the delete was rejected; the plan
  may have been removed or you may no longer be allowed to delete it"), or the
  client re-resolves the member's capabilities when it sees the rejection
  and words the message from the result.
- Can be combined with (a), or done alone as a smaller change.

### (c) Fail closed when there is no cached answer

- Rejected as the default: it breaks offline editing for legitimate editors.
  Listed only so a later slice does not rediscover it.

## Requirements for the slice that picks this up

- Choose (a), (b), or both, and record the choice in an ADR or in the
  architecture doc's authorization section.
- Keep the offline-first property: a user whose capabilities were resolved
  before going offline keeps their affordances across a cold start.
- Red tests first:
  - a resolver seeded from storage answers `hasCapabilitySync` with no
    network call;
  - a failed resolve keeps the stored set instead of clearing it;
  - a stored set is never applied to a different user or organization;
  - an `IfCapability` with no stored answer and a failing resolve still shows
    its child (the documented fail-open).
- Cover every capability-gated affordance, not only the delete ones: plan and
  session editing, and the song library, editor, and reader gates (they use
  `IfCapability` or read `hasCapabilitySync` directly, with different
  defaults for an unknown answer).

## Roadmap (2026-10-01)

Scheduled in slice **S6** (`fix/capability-and-telemetry`) of
`docs/plans/2026-10-01-delivery-roadmap.md`.

**Recommended default: (a) and (b) together.** The S6 spec confirms or
overrides this.

**Sequencing constraint.** The persisted capability store is a new per-user
local store, so it joins the ADR-035 purge contract. S3 adds another such
store, so S6 must not run in parallel with S3.

**Update (2026-10-05):** option (a) moved to slice **S0**
(`fix/offline-first-startup-gate`, PR 2), decision SG6 in
`docs/specs/2026-10-05-offline-first-startup-gate.md`. There the set is stored
in the `LastKnownIdentity` database and cleared with the identity, so no new
`PurgeTarget` is added. S6 keeps option (b). This entry narrows to option (b)
when S0's PR 2 merges.
