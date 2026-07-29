# ADR-024: A Planning Edit Draft Carries Full State, So Null Means Cleared

- Status: Accepted
- Date: 2026-07-27
- Related: [ADR-014-planning-write-projection-mutation-boundary.md](ADR-014-planning-write-projection-mutation-boundary.md), [ADR-019-exactly-once-planning-mutation-sync.md](ADR-019-exactly-once-planning-mutation-sync.md)
- Spec: `docs/specs/2026-07-27-ux1-reader-wrap-and-ux2-date-picker.md`
- Findings: `UX-2` (surfaced the ambiguity)

## Context

`PlanEditDraft` and the `PlanningPlanEditMutationDraft` behind it carry
`description` and `scheduledFor` as plain nullables. Nothing recorded whether a
null meant "the user cleared this field" or "this write does not carry a value
for this field", and two layers resolved the ambiguity as "not carried":

- folding a plan edit into a still-pending `planCreate` called
  `PlanningMutationRecord.copyWith` without the `clearDescription` /
  `clearScheduledFor` flags that type already provides, so the previous value
  survived and eventually synced;
- the local read projection merged a `planEdit` with
  `mutation.scheduledFor ?? existing.scheduledFor`, so a clear was invisible
  offline — the user cleared the field, the projection was re-read, and the old
  value was still on screen.

This stayed latent while the value was edited as a raw ISO-8601 string. The UX-2
date/time picker added an explicit clear affordance, which turned a latent
ambiguity into a visibly broken button.

## Decision

A planning **edit** draft always carries the complete form state of the
aggregate it edits. `PlanEditDraft` is constructed at exactly one site — the
plan editor dialog — and that dialog always supplies name, description and
scheduled-for together, whether or not the user touched each one.

Therefore, for a `planEdit` mutation, **null means explicitly cleared**, and
every layer treats it that way:

- `recordPlanEdit` passes `clearDescription` / `clearScheduledFor` when the
  corresponding draft value is null, so folding an edit into a pending create
  clears rather than retains.
- The local read repository takes the mutation's `description` and
  `scheduledFor` directly when merging a `planEdit`, with no fallback to the
  pre-edit value. `name` keeps its fallback: it is non-null on the draft, so the
  fallback can never mask a clear.
- The Supabase mutation repository already sends `p_description` and
  `p_scheduled_for` as explicit keys for `planEdit` regardless of nullness; a
  regression test now pins that, because the condition that produces it is easy
  to "simplify" into an omission.

This contract is a property of the **draft**, not of the record shape. If a
future write path constructs a `PlanEditDraft` that does not carry the full form
state — a partial or field-scoped edit — this decision no longer holds and the
draft must gain an explicit presence flag per field instead. A test asserting
the single construction site is cheaper than rediscovering this the way it was
discovered here.

## Consequences

- Clearing a plan's schedule or description works offline, survives a projection
  re-read, and syncs as a clear rather than reverting to the previous value.
- A name-only edit still cannot blank the other fields, because the dialog
  supplies their current values rather than null. Two existing tests that
  simulated a name-only edit by passing nulls were rewritten to use realistic
  drafts; their intent — an unmodified field must not be blanked — is unchanged.
- Pending mutation rows written before this change carry the same semantics: the
  previous ISO text field produced null for an empty input too, so a stored null
  already meant "no scheduled instant". No migration is needed.
