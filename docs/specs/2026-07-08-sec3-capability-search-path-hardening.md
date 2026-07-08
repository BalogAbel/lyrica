# S0b — SEC-3: `search_path` hardening for capability helpers

**Date:** 2026-07-08
**Slice:** S0b (Phase 0)
**Finding:** SEC-3 (`docs/architecture/repository-review-2026-06-22.md`)
**Branch:** `refactor/arch-spine-phase0-1`

## Problem

Two authorization helper functions run with a mutable `search_path`:

- `public.has_capability(uuid, text, uuid)` — had `set search_path = public` in
  `20260323220000_fix_membership_helper_rls_recursion.sql`, then **regressed**
  when redefined without it in
  `202605250002_organization_read_only_role_constraints.sql`.
- `public.get_my_capabilities(uuid, uuid)` — never carried it
  (`202605280001_get_my_capabilities_batch_function.sql`).

The third helper the review names, `public.current_organization_ids()`, already
carries `security definer set search_path = public`. SEC-3 is rated Low: the
functions are invoker-rights and every reference is `public`-qualified, so
behavior is unaffected today; the risk is inconsistency with the hardening
baseline and a Supabase advisor flag. The root cause is a **silent regression**:
a later `create or replace` dropped a previously-set `search_path`.

## Goal

Pin `search_path = public` on both helpers, and add a regression guard so the
setting cannot silently disappear again.

## Scope

**In scope**

- New migration adding `search_path = public` to `has_capability` and
  `get_my_capabilities`.
- New backend contract test asserting all three security helpers
  (`has_capability`, `get_my_capabilities`, `current_organization_ids`) carry
  `search_path=public` in `pg_proc.proconfig`.
- Wire the test into `scripts/backend-write-contracts.sh` so the
  `backend_write_contracts` CI job runs it.
- Mark SEC-3 fixed in the repository-review doc.

**Out of scope / decisions**

- No ADR. This is a `search_path` config hardening, not an authorization-semantic
  or schema change. The established precedent
  (`202605160007_auth_boundary_hardening.sql`) added `search_path` to existing
  functions the same way with no ADR. AGENTS rule 6's ADR requirement targets
  authz/schema changes, which this is not.
- No function body change. `alter function ... set search_path = public` is the
  house style for this exact fix (see `auth_boundary_hardening.sql`), so no
  `create or replace` and no body duplication/drift.

## Design

### Migration

`supabase/migrations/202607080001_capability_search_path_hardening.sql`
(timestamp sorts after the current latest, `202606290002`):

```sql
alter function public.has_capability(uuid, text, uuid)
  set search_path = public;

alter function public.get_my_capabilities(uuid, uuid)
  set search_path = public;
```

### Regression guard test

`scripts/tests/capability-search-path-contract-test.sh`, mirroring the structure
of `scripts/tests/organization-read-only-role-test.sh`:

- Honor `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP` (start/reset/provision only when
  not set), find the `supabase_db_*` container, run SQL via `docker exec psql`.
- Query `pg_proc.proconfig` for the three helpers and assert each contains
  `search_path=public`; fail with a clear message otherwise.

Query shape:

```sql
select p.proname, coalesce(array_to_string(p.proconfig, ','), '')
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('has_capability', 'get_my_capabilities', 'current_organization_ids')
order by p.proname;
```

Assertion: every listed function's config string contains `search_path=public`.

### CI wiring

Append to `scripts/backend-write-contracts.sh`, after the organization-read-only
invocation, following the existing pattern:

```bash
capability_search_path_test_script="${CAPABILITY_SEARCH_PATH_TEST_SCRIPT:-./scripts/tests/capability-search-path-contract-test.sh}"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$capability_search_path_test_script"
```

## Behavior impact

None. `search_path = public` matches the effective path already used (all
references are `public`-qualified; `config.toml` sets
`extra_search_path = ["public", "extensions"]`). Query results are identical;
only the function config metadata changes.

## Testing (TDD)

1. Write the guard test script and wire it into `backend-write-contracts.sh`
   **before** adding the migration.
2. Run the guard test against the current schema (migration absent): it **fails**
   on `has_capability` and `get_my_capabilities` (no `search_path`).
3. Add the migration.
4. Re-run: the guard test **passes** for all three helpers.
5. Run `scripts/check-migrations.sh` (db lint) and the full
   `scripts/backend-write-contracts.sh`: both green.

## Commits

1. `test(backend): guard search_path on capability helpers` — new guard test +
   wiring; failing first.
2. `fix(db): pin search_path=public on capability helpers` — the migration;
   guard now green.
3. `docs(review): mark SEC-3 fixed (capability search_path hardening)` — review
   doc status update.

## Done when

- Guard test written and failing first, then green after the migration.
- `has_capability`, `get_my_capabilities`, `current_organization_ids` all carry
  `search_path=public` in `proconfig`.
- `check-migrations.sh` (migration lint) and `backend-write-contracts.sh` green
  locally.
- SEC-3 marked fixed in `docs/architecture/repository-review-2026-06-22.md`
  (including the "2 of 3 open" tally).
