# Direct Table DML Bypasses the Write RPCs

**Slice:** feat/plan-delete-session-cascade (found by review gate 1 on
2026-09-30; pre-existing, out of that slice's scope)
**Related:** `docs/specs/2026-09-29-plan-delete-and-session-cascade.md`
(invariants I2, I4, I5), ADR-026, ADR-027
**Files:**
- `supabase/migrations/202605160007_auth_boundary_hardening.sql` (revoked
  table DML from `anon` only)
- the initial schema migrations that create the `for all` write policies on
  `plans`, `sessions`, `session_items`, and `songs`
- `docs/architecture/architecture.md` and ADR-026 / ADR-027 (they state that
  RLS denies direct DML)

## Problem

The role `authenticated` still has `INSERT`, `UPDATE`, `DELETE`, and
`TRUNCATE` on `public.plans`, `public.sessions`, `public.session_items`,
`public.songs`, and `public.attachments`. The write policies are `for all`,
with `using` and `with check` set to `has_capability(...)`:
- `plans are editable with plan capability`
- `sessions are editable with session capability`
- `session items inherit session edit capability`
- `songs are editable with song edit capability`
- `attachments are editable to song editors`

A member with the capability can therefore write these tables through the
table API (`/rest/v1/...`) and skip the RPC write contract:
- version checks
- slug rules
- derived song metadata
- the `plans.content_version` bump

Review gate 1 reproduced this as the demo user:
- Directly inserting a session and an item left `content_version` unchanged.
- `update public.plans set content_version = 1` succeeded.
- `delete_plan(..., 1, 1)` then cascaded content the caller had never seen.
- A plain `DELETE` on `plans` skips the base check entirely.
- Direct writes also take `sessions` and `session_items` row locks without
  taking the `plans` row lock first, which breaks I5.

This is not an authorization escalation. The same member may call the RPCs
anyway, including `delete_plan` with fresh bases. It does mean I2, I4, and I5
hold only for clients that write through the RPCs. The Flutter app makes zero
direct table writes; `.from(...)` is used only for reads.

## Why it was deferred

The gap predates the plan-delete slice and covers song tables too. Closing it
changes the table grants and policies for every writer, so it needs its own
contract tests. It was kept out of the plan-delete PR to keep that PR
reviewable.

**Decision (2026-09-30):** it will be fixed in its own slice and PR, on a
branch cut from `main` (for example `fix/direct-dml-write-rpc-bypass`), not
folded into `feat/plan-delete-session-cascade`. It does not block the
plan-delete slice, because the app writes only through the RPCs. It should
still land soon: the `content_version` guarantee is only as strong as the
RPC-only write path.

### Sequencing with the plan-delete slice

The two PRs may be developed in parallel. Whichever merges into `main`
second must bring its branch up to date with `main` and re-run the full
`./scripts/backend-write-contracts.sh` before merging.

- **If this slice merges first,** the plan-delete branch must pick up the
  revoked grants. Its contract tests seed through RPCs, and direct inserts
  run as `postgres`, so they should keep passing. Confirm it instead of
  assuming it.
- **If the plan-delete slice merges first,** this slice's "every `security
  definer` RPC still works" check must also cover `delete_plan`,
  `delete_session`, and the internal `bump_plan_content_version` helper
  (migration `202609290001`).
- **Where this entry lives.** It was written on the plan-delete branch, so it
  is not on `main` until that branch merges.
  - If the fix branch starts earlier, it takes the file with
    `git checkout feat/plan-delete-session-cascade -- docs/deferred/2026-09-30-direct-dml-bypasses-write-rpcs.md`.
  - If the fix then merges first and removes this entry, the plan-delete
    branch must keep it removed when it syncs with `main`, instead of
    re-adding it. The same applies to its `architecture.md` wording, which
    the fix slice supersedes.

## Requirements for the slice that picks this up

- Add a red contract test first. It runs as `authenticated` and impersonates
  a capable member. Direct `insert`, `update`, and `delete` on each table
  above must be denied.
- Revoke table DML from `authenticated` and narrow the `for all` policies to
  `for select`, or do either one alone with a recorded reason.
- Show that every `security definer` RPC still passes
  `./scripts/backend-write-contracts.sh`.
- Check that nothing outside the RPCs still writes these tables as
  `authenticated`:
  - the seed and provisioning scripts (`scripts/db-seed.sh`,
    `scripts/provision-local-demo-user.sh`, `supabase/seed/`)
  - the manual-validation scripts
  - the Flutter integration tests under `apps/lyron_app/test/integration/`,
    which create fixtures with `SERVICE_ROLE_KEY`
  - Anything that does must move to `service_role`, `postgres`, or an RPC.
- Check every other `public` table for the same pattern.
- Correct `docs/architecture/architecture.md` and note the correction for
  ADR-026 / ADR-027.
- Update this entry, or remove it, in the same change.
