# Debt sweep: ARCH-4 (melos overhead) + SEC-2 (create_invitation null-caller gate)

**Status:** approved, combined spec + plan (per AGENTS.md small-item allowance — both
items are Low severity, single-file/single-migration scope, a separate plan doc would
duplicate this one).

**Branch:** `chore/debt-sweep-arch4-sec2`, cut from `main` (Riverpod 3 migration, PR #67,
already merged).

**Prerequisite check:** `main` at branch time has PR #67 as its tip commit; `git status`
on `main` is clean (no stray `apps/lyron_app/pubspec.yaml` version bump to carry over).

## Scope

Two independent, unrelated Low-severity findings from
`docs/architecture/repository-review-2026-06-22.md`, bundled into one small PR because
each is too small to justify its own branch/PR cycle. They touch disjoint files and can
be implemented and reviewed as two sequential commits.

Out of scope: everything under "Explicitly out of scope (Phase 6+)" in the governing
prompt — no other review findings, no deferred docs.

---

## Item 1 — ARCH-4: drop melos

### Current state (confirmed by repo audit)

- `melos.yaml` (repo root) manages exactly one package: `apps/lyron_app`. No other
  package exists under `apps/**`.
- It defines three scripts, all pure passthroughs for the single package:
  - `analyze` → `melos exec -- flutter analyze`
  - `test` → `melos exec -- flutter test`
  - `format` → `melos exec -- dart format lib test`
- Zero references in `scripts/bootstrap.sh`, `scripts/verify.sh`,
  `.github/workflows/ci.yml`, or `AGENTS.md`. Melos is not wired into any automated path.
- No root `pubspec.yaml`; melos is not declared as a pub dependency anywhere in the repo
  (installed ad hoc, e.g. via `dart pub global activate melos`, outside repo control).
- References to update: `docs/architecture/repository-review-2026-06-22.md:33` (stack
  overview) and `:290` (ARCH-4 finding). `docs/architecture/architecture.md` likely
  mentions melos in its stack description — confirm and update in the same commit.
  Historical mentions in `docs/plans/2026-08-08-riverpod-3-migration.md` and
  `docs/specs/2026-08-08-riverpod-3-migration.md` are **not** touched — they document a
  past decision to defer this exact item to this PR, and stay accurate as history.

### Decision (user-approved, 2026-08-08)

Drop melos. No multi-package direction exists or is planned; keeping a workspace
manager for a single package is pure overhead with zero current benefit and zero
current integration cost to preserve.

### Plan

1. Delete `melos.yaml`.
2. Update `docs/architecture/architecture.md`: remove/replace any "Melos monorepo"
   stack-overview line with a note that `flutter analyze` / `flutter test` /
   `dart format lib test` run directly against `apps/lyron_app` from the repo root (or
   from within the package directory, whichever matches actual current dev workflow —
   confirm against `scripts/verify.sh` before wording it).
3. Update `docs/architecture/repository-review-2026-06-22.md`: strike the ARCH-4 line
   with `~~struck~~ **Done (2026-08-08, debt sweep, PR #TBD):** ...` per the existing
   convention, stating the removal and that no multi-package direction exists.
4. No test required — this is a deletion with no behavior, no CI job depends on melos
   (confirmed above), so there is nothing to assert against. Verification is: repo still
   builds/analyzes/tests via the plain `flutter`/`dart` commands (run manually as part of
   local verification, not a new automated test).

### Acceptance criteria

- `melos.yaml` no longer exists.
- `flutter analyze` and `flutter test` still run cleanly from `apps/lyron_app` (or repo
  root, matching whatever `scripts/verify.sh` already does — melos was never in that
  path so this should be a no-op check).
- `docs/architecture/architecture.md` and the review doc no longer describe melos as
  active tooling.

---

## Item 2 — SEC-2: explicit admin gate in `create_invitation`

### Current state (confirmed by repo audit)

Defined in `supabase/migrations/202605160002_invitations_functions.sql:1`, `security
definer`, `set search_path = public`:

```sql
create or replace function public.create_invitation(
  p_organization_id uuid,
  p_role public.role_code,
  p_email text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_token text;
  v_is_admin boolean;
begin
  if v_caller is not null then
    select exists (
      select 1
      from public.memberships m
      where m.user_id = v_caller
        and m.organization_id = p_organization_id
        and m.scope_type = 'organization'
        and m.role_code = 'organization_admin'
        and m.status = 'active'
    ) into v_is_admin;

    if not v_is_admin then
      raise exception using
        errcode = '42501',
        message = 'invitation_create_not_authorized';
    end if;
  end if;

  v_token := translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_');

  insert into public.invitations (
    token, email, organization_id, role_code,
    expires_at, issued_by
  ) values (
    v_token, p_email, p_organization_id, p_role,
    now() + interval '30 days', v_caller
  );

  return v_token;
end;
$$;
```

Grant, from `supabase/migrations/202605160007_auth_boundary_hardening.sql:50-51`:

```sql
grant execute on function public.create_invitation(uuid, public.role_code, text)
to authenticated, service_role;
```

**The gap:** when `auth.uid()` is null, the entire admin-membership check is skipped and
the function inserts an invitation unconditionally. Today this is safe in practice only
because an `authenticated`-role caller always carries a non-null `auth.uid()` (Supabase
issues that role exclusively off a valid user JWT); the null-caller path is therefore
only ever reachable via `service_role`. But that safety is an artifact of how the grant
happens to be scoped today, not something the function itself asserts. A future grant
change (e.g. adding `anon`, or a PostgREST/session config change that leaves `auth.uid()`
null under `authenticated`) would silently reopen this path with zero enforcement.
Review finding: `docs/architecture/repository-review-2026-06-22.md:355-356`.

### Decision

Make the gate explicit: when `auth.uid()` is null, assert the caller is actually
`service_role` (checked via the session's current role, not inferred from grants) before
skipping the admin-membership check. Any other null-caller path raises the same
`42501 invitation_create_not_authorized` error the admin check already uses.

**No ADR.** This does not change the function's authorization semantics for any real
caller path — an `authenticated` caller still needs `organization_admin`, and
`service_role` still bypasses the check, exactly as today. It only replaces an implicit
guarantee (derived from grant scope) with an explicit runtime assertion, closing a
latent gap without altering intended behavior. State this plainly in the migration
comment, the commit message, and the PR body — do not overstate it as a live
vulnerability fix.

The exact Postgres/Supabase idiom for "is the current session `service_role`" (candidate:
`current_setting('role', true) = 'service_role'`, alternatives: `session_user`,
`pg_has_role`) is not yet used anywhere else in this repo (confirmed by grep across
`supabase/migrations/`) — resolve the correct idiom via the `context7` MCP
(Supabase/Postgres docs) before writing the migration, per AGENTS.md rule 16. Do not
guess from memory.

### Plan (TDD, per AGENTS.md rule 6 and the SEC-5/SEC-1 precedent)

1. **Failing test first**, added to the backend write-contract suite exercised by
   `scripts/backend-write-contracts.sh` (same harness/pattern as
   `scripts/tests/invitation-redemption-contract-test.sh`, which already exercises
   `create_invitation` via its `make_invitation` helper). New test case: call
   `create_invitation` as a caller with null `auth.uid()` and a session role that is
   **not** `service_role` (simulate however the harness simulates non-privileged/anon
   sessions elsewhere — follow its existing convention rather than inventing a new one).
   Assert the call is rejected with `42501 invitation_create_not_authorized`. Run it
   against the current migration first and confirm it **fails** (the call currently
   succeeds) — this is the "red" step, and its output must be captured as evidence.
2. **Migration**: new file
   `supabase/migrations/<timestamp>_create_invitation_explicit_service_role_gate.sql`
   that `create or replace function public.create_invitation(...)` with the added
   explicit role assertion in the null-caller branch. Keep everything else in the
   function body identical. Add a one-line SQL comment explaining why the check exists
   (defense-in-depth against future grant drift, not a live exploit) — link back to the
   SEC-2 finding.
3. Re-run the test: confirm it now **passes** (the "green" step). Capture output.
4. Run the full `scripts/backend-write-contracts.sh` suite to confirm no regression in
   the existing invitation redemption / creation contract tests, and re-run
   `scripts/tests/invitation-redemption-contract-test.sh` specifically since it already
   exercises `create_invitation` on the happy path.
5. Update `docs/architecture/repository-review-2026-06-22.md:355-356`: strike the SEC-2
   line with `~~struck~~ **Done (2026-08-08, debt sweep, PR #TBD):** ...`, stating the
   explicit gate and referencing the new migration file. Keep the "safe today via grant
   scope" honesty from the original finding — this closes defense-in-depth, not an
   active vulnerability.
6. Confirm coherence with ADR-025 (invitation redemption model) — this change only
   touches invitation *creation*, not redemption; ADR-025's model is unaffected. No edit
   to the ADR needed; note this explicitly in the PR body so reviewers don't go looking
   for one. `pg_cron` orphan cleanup
   (`202605160006_pg_cron_orphan_cleanup.sql`) operates on expired/orphaned rows and is
   unaffected by who was allowed to create them.

### Acceptance criteria

- New backend contract test exists, demonstrably red-then-green (both outputs captured
  for the PR/review evidence).
- `create_invitation`'s null-caller branch explicitly asserts `service_role` before
  bypassing the admin check.
- Full `scripts/backend-write-contracts.sh` suite green.
- Review doc SEC-2 entry struck with the `Done` convention.
- No ADR added; PR body states why.

---

## Definition of done (both items)

- Both findings struck in `docs/architecture/repository-review-2026-06-22.md`.
- CI green on all jobs: `verify`, `backend_write_contracts`, `migrations`,
  `flutter build web`, coverage gate, dependency-audit gate.
- Two commits minimum (one per item), each independently coherent.
- No merge, no branch deletion, without explicit user go-ahead.
