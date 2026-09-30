# Plan Delete and Cascading Session Delete — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let members delete a plan (cascading to its sessions and session items) and delete a non-empty session (cascading to its items), offline-first, without ever deleting songs and without silently deleting content the deleting client has not seen.

**Architecture:** A new `plans.content_version` counts every accepted write to a plan's sessions and items. `delete_plan` checks it together with `plans.version`. On the client, a new `planDelete` mutation rides the existing mutation store, overlay, sync, and recovery machinery. A best-effort, contiguity-checked rebase keeps the client's own in-flight writes from making its delete conflict with itself.

**Tech stack:**
- Supabase Postgres (plpgsql RPCs, `security definer`)
- Flutter / Dart 3 with Riverpod 3
- Drift (sqlite, schema 6 → 7)
- Backend contract tests: bash + Python + `docker exec psql`

**Spec:** `docs/specs/2026-09-29-plan-delete-and-session-cascade.md`. Decisions D1–D12 and invariants I1–I7 are cited below by number. Read the spec before starting.
**ADR:** ADR-038 (written in Task 4.3)
**Branch:** `feat/plan-delete-session-cascade` (already exists; spec committed)

**Discipline:**
- **TDD.** Every task starts with a red test, run it, and see it fail for the stated reason before implementing. In Dart, a test that references a symbol that does not exist yet fails at compile time; that counts as red.

**Verification:**
- **After every Dart task:** run from `apps/lyron_app`:
  - `dart format --output=none --set-exit-if-changed lib test`
  - `flutter analyze`
  - `flutter test` (the full suite, never a subdirectory)
- **After every backend task:** `./scripts/backend-write-contracts.sh` from the repository root. It requires Docker and a startable local Supabase.

**Commits:**
- One commit per task, Conventional Commits.
- End each message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

---

## Execution model

Four phases on one branch. Each phase ends green, followed by **one adversarial whole-diff review** of that phase's diff. The reviewer gets exactly one negative claim to disprove, stated in the phase's review gate. Fix what it finds, re-run the full suite, then start the next phase. One PR at the end (Task 4.4).

**STOP and report** (do not improvise) when any of these happens:

1. An existing backend contract assertion has to change its **meaning** to pass. Adding a key to a returned object is fine; a different error code or value is not.
2. An existing Dart test would have to be **deleted** rather than updated to pass. Updating the "delete only when empty" expectations in Task 4.2 is planned and does not count.
3. The number of interface implementers differs from the lists in Tasks 2.4 and 3.2.
4. `resolveCancelledCreate`'s signature seems to need a change. It must not change (D5b uses the constant 1).
5. Any need arises to send a base value that was not captured from the local projection or adjusted by D7's contiguity rules.

## File map

**Backend**
- Create `supabase/migrations/202609290001_plan_content_version_and_cascade_delete.sql` (Task 1.2).
- Create `scripts/tests/planning-cascade-delete-contract-test.sh` (Task 1.1).
- Modify `scripts/backend-write-contracts.sh` to run the new contract test.

**Client — data and sync** (all paths under `apps/lyron_app/lib/src/`)
- `offline/planning/planning_local_tables.dart` and
  `offline/planning/planning_local_database.dart` (+ regenerated `.g.dart`):
  schema 7.
- `offline/planning/planning_local_store.dart`:
  - `contentVersion` in the projection
  - `advanceSyncedPlanContentVersion`
  - `deleteSyncedPlan`
- `domain/planning/plan_summary.dart`: `contentVersion`.
- `application/planning/planning_sync_payload.dart`,
  `infrastructure/planning/supabase_planning_repository.dart`,
  `application/planning/planning_sync_controller.dart`: `content_version`
  pull.
- `application/planning/planning_mutation_sync_types.dart`:
  - `planDelete` kind and `bumpsPlanContent`
  - record fields
  - `PlanningPlanDeleteMutationDraft`
  - store interface
- `infrastructure/planning/supabase_planning_mutation_repository.dart`:
  - per-kind parameter whitelist
  - `delete_plan` / `delete_session`
  - response mapping
- `application/planning/drift_planning_mutation_store.dart`:
  - `recordPlanDelete`
  - cascade `recordSessionDelete`
  - `applyAcceptedWriteEffects`
  - tombstone and retry changes
- `application/planning/budgeted_planning_mutation_store.dart`: wrappers.
- `application/planning/planning_mutation_sync_controller.dart`:
  - `planCreate` cancellable
  - D7/D8 call sites
- `application/planning/planning_mutation_reconciler.dart`: `planDelete`, and
  preserving `contentVersion`.
- `application/planning/planning_local_read_repository.dart`: hide deleted
  plans, and carry `contentVersion`.
- `application/planning/planning_write_service.dart`:
  - `deletePlan`
  - no more emptiness precondition in `deleteSession`
- `application/sync/unified_sync_overview.dart`: summary label/copy and
  title fallback.

**Client — UI**
- `shared/app_strings.dart`
- `presentation/planning/plan_detail_screen.dart`
- `presentation/planning/widgets/plan_session_card.dart`

**Docs** (Task 4.3)
- `docs/domain/domain-model.md`
- `docs/architecture/state-machines.md`
- `docs/architecture/architecture.md`
- `docs/architecture/decisions/ADR-038-plan-content-version.md`
- the spec's status line

---

## Phase 1 — Backend

### Task 1.1: Contract test for content version and cascade delete (red)

**Files:**
- Create: `scripts/tests/planning-cascade-delete-contract-test.sh`
- Modify: `scripts/backend-write-contracts.sh`

- [ ] **Step 1: Create the script from the existing prelude.**

Lines 1–201 of `scripts/tests/planning-write-contract-test.sh` are the bash
bootstrap, the demo-user lookup, the opening of the Python heredoc, and the
helpers `normalize_uuid`, `sql_quote`, `run_psql`, `fetch_json`, `fetch_row`,
and `capture_error`. Reuse them verbatim:

```bash
sed -n '1,201p' scripts/tests/planning-write-contract-test.sh \
  > scripts/tests/planning-cascade-delete-contract-test.sh
chmod +x scripts/tests/planning-cascade-delete-contract-test.sh
tail -n 3 scripts/tests/planning-cascade-delete-contract-test.sh
```

Expected: the last lines are the body of `capture_error`, ending in
`return row[0], row[1], row[2]`. If not, STOP: the source file changed; find
the end of `capture_error` and adjust the line range.

- [ ] **Step 2: Append the contract body.**

```bash
cat >> scripts/tests/planning-cascade-delete-contract-test.sh <<'EOF'


# ---------------------------------------------------------------------------
# Plan content version + cascading delete contract
# docs/specs/2026-09-29-plan-delete-and-session-cascade.md, tests B1-B7.
# Runs after planning-write-contract-test.sh on the same database, so every
# id here uses its own c1/c2 prefix.
# ---------------------------------------------------------------------------

seed_song_id = "33333333-3333-3333-3333-333333333333"
plan_p = "c1000000-0000-0000-0000-000000000001"
session_a = "c1000000-0000-0000-0000-00000000000a"
session_b = "c1000000-0000-0000-0000-00000000000b"
item_a1 = "c1000000-0000-0000-0000-0000000000a1"
item_a2 = "c1000000-0000-0000-0000-0000000000a2"
item_b1 = "c1000000-0000-0000-0000-0000000000b1"
read_only_user_id = "c1000000-0000-0000-0000-0000000000ee"
foreign_org_id = "c1000000-0000-0000-0000-0000000000f0"

plan_q = "c2000000-0000-0000-0000-000000000001"
session_t = "c2000000-0000-0000-0000-00000000000a"
extra_song_id = "c2000000-0000-0000-0000-00000000005a"
attachment_id = "c2000000-0000-0000-0000-0000000000a7"
item_t1 = "c2000000-0000-0000-0000-0000000000a1"
item_t2 = "c2000000-0000-0000-0000-0000000000a2"
item_t3 = "c2000000-0000-0000-0000-0000000000a3"

org = sql_quote(organization_id)


def call(function: str, args: str, user_id: str | None = demo_user_id) -> dict:
    return fetch_json(
        f"select to_jsonb(public.{function}({args}));",
        user_id=user_id,
    )


def call_error(
    function: str, args: str, user_id: str | None = demo_user_id
) -> tuple[str, str]:
    sqlstate, message, _detail = capture_error(
        f"perform public.{function}({args});",
        user_id=user_id,
    )
    return sqlstate, message


def plan_content_version(plan_id: str) -> int:
    return int(
        run_psql(
            "select content_version from public.plans "
            f"where id = {sql_quote(plan_id)}::uuid;"
        )
    )


def row_count(sql: str) -> int:
    return int(run_psql(sql))


# --- B2: every child RPC bumps plans.content_version by exactly one -------

created_p = call(
    "create_plan",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_p)}::uuid,
    p_slug => 'cascade-contract',
    p_name => 'Cascade Contract',
    p_description => null,
    p_scheduled_for => null
    """,
)
assert created_p["version"] == 1, created_p
assert created_p["content_version"] == 1, created_p

row = call(
    "create_session",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_p)}::uuid,
    p_session_id => {sql_quote(session_a)}::uuid,
    p_slug => 'cascade-a',
    p_name => 'Cascade A'
    """,
)
assert row["id"] == session_a, row
assert row["slug"] == "cascade-a", row
assert row["version"] == 1, row
assert row["plan_content_version"] == 2, row
assert plan_content_version(plan_p) == 2

row = call(
    "create_session",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_p)}::uuid,
    p_session_id => {sql_quote(session_b)}::uuid,
    p_slug => 'cascade-b',
    p_name => 'Cascade B'
    """,
)
assert row["plan_content_version"] == 3, row

row = call(
    "rename_session",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_a)}::uuid,
    p_base_version => 1,
    p_name => 'Cascade A Renamed'
    """,
)
assert row["name"] == "Cascade A Renamed", row
assert row["version"] == 2, row
assert row["plan_content_version"] == 4, row

row = call(
    "create_song_session_item",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_a)}::uuid,
    p_session_item_id => {sql_quote(item_a1)}::uuid,
    p_song_id => {sql_quote(seed_song_id)}::uuid,
    p_base_version => 2,
    p_position => null
    """,
)
assert row["version"] == 3, row
assert row["plan_content_version"] == 5, row

row = call(
    "reorder_session_items",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_a)}::uuid,
    p_base_version => 3,
    p_session_item_ids => array[{sql_quote(item_a1)}::uuid]
    """,
)
assert row["version"] == 4, row
assert row["plan_content_version"] == 6, row

row = call(
    "create_song_session_item",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_b)}::uuid,
    p_session_item_id => {sql_quote(item_b1)}::uuid,
    p_song_id => {sql_quote(seed_song_id)}::uuid,
    p_base_version => 1,
    p_position => null
    """,
)
assert row["version"] == 2, row
assert row["plan_content_version"] == 7, row

row = call(
    "delete_session_item",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_b)}::uuid,
    p_session_item_id => {sql_quote(item_b1)}::uuid,
    p_base_version => 2
    """,
)
assert row["version"] == 3, row
assert row["plan_content_version"] == 8, row

row = call(
    "reorder_plan_sessions",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_p)}::uuid,
    p_base_version => 1,
    p_session_ids => array[
      {sql_quote(session_b)}::uuid,
      {sql_quote(session_a)}::uuid
    ]
    """,
)
assert row["version"] == 2, row
assert row["plan_content_version"] == 9, row
assert row["ordered_session_ids"] == [session_b, session_a], row

# A failed child write bumps nothing (I4): each of these raises after (or
# before) the bump and must leave content_version at 9.
assert call_error(
    "rename_session",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_a)}::uuid,
    p_base_version => 1,
    p_name => 'Stale rename'
    """,
) == ("P0001", "session_version_conflict")
assert call_error(
    "create_song_session_item",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_a)}::uuid,
    p_session_item_id => {sql_quote(item_a2)}::uuid,
    p_song_id => {sql_quote(seed_song_id)}::uuid,
    p_base_version => 4,
    p_position => null
    """,
) == ("P0001", "duplicate_song_in_session_blocked")
assert call_error(
    "reorder_plan_sessions",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_p)}::uuid,
    p_base_version => 2,
    p_session_ids => array[
      {sql_quote(session_a)}::uuid,
      {sql_quote(session_a)}::uuid
    ]
    """,
) == ("P0001", "session_reorder_blocked_invalid_permutation")
assert plan_content_version(plan_p) == 9

# --- B6: legacy delete_empty_session keeps its rule and now bumps ---------

assert call_error(
    "delete_empty_session",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_a)}::uuid,
    p_base_version => 4
    """,
) == ("P0001", "session_delete_blocked_not_empty")
assert plan_content_version(plan_p) == 9

legacy = call(
    "delete_empty_session",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_b)}::uuid,
    p_base_version => 3
    """,
)
assert legacy["deleted"] is True, legacy
assert "plan_content_version" not in legacy, legacy
assert plan_content_version(plan_p) == 10

# --- B3: delete_plan conflicts on any stale or missing base ---------------

assert call_error(
    "delete_plan",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_p)}::uuid,
    p_base_version => null,
    p_base_content_version => 10
    """,
) == ("P0001", "plan_version_conflict")
assert call_error(
    "delete_plan",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_p)}::uuid,
    p_base_version => 1,
    p_base_content_version => 10
    """,
) == ("P0001", "plan_version_conflict")
assert call_error(
    "delete_plan",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_p)}::uuid,
    p_base_version => 2,
    p_base_content_version => 9
    """,
) == ("P0001", "plan_version_conflict")
assert row_count(
    f"select count(*) from public.plans where id = {sql_quote(plan_p)}::uuid;"
) == 1
assert plan_content_version(plan_p) == 10

# --- B4: authorization -----------------------------------------------------

run_psql(
    dedent(
        f"""
        insert into auth.users (id, email)
        values ({sql_quote(read_only_user_id)}, 'cascade-readonly@lyron.local')
        on conflict (id) do nothing;

        insert into public.memberships (
          user_id, organization_id, role_code, scope_type, status
        )
        values (
          {sql_quote(read_only_user_id)}::uuid,
          {org}::uuid,
          'organization_read_only',
          'organization',
          'active'
        )
        on conflict do nothing;

        insert into public.organizations (id, name, slug)
        values (
          {sql_quote(foreign_org_id)}::uuid,
          'Cascade Foreign Organization',
          'cascade-foreign-organization'
        )
        on conflict (id) do nothing;
        """
    )
)

delete_p_args = f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_p)}::uuid,
    p_base_version => 2,
    p_base_content_version => 10
"""
for denied_user in (blocked_user_id, read_only_user_id):
    assert call_error("delete_plan", delete_p_args, user_id=denied_user) == (
        "P0002",
        "plan_not_found",
    ), denied_user
assert call_error(
    "delete_plan",
    f"""
    p_organization_id => {sql_quote(foreign_org_id)},
    p_plan_id => {sql_quote(plan_p)}::uuid,
    p_base_version => 2,
    p_base_content_version => 10
    """,
) == ("P0002", "plan_not_found")
assert call_error(
    "delete_session",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_a)}::uuid,
    p_base_version => 4
    """,
    user_id=read_only_user_id,
) == ("P0002", "session_not_found")
assert row_count(
    f"select count(*) from public.plans where id = {sql_quote(plan_p)}::uuid;"
) == 1

# --- B5: delete_session cascades items, never songs or attachments --------

call(
    "create_plan",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_q)}::uuid,
    p_slug => 'cascade-session',
    p_name => 'Cascade Session',
    p_description => null,
    p_scheduled_for => null
    """,
)
call(
    "create_session",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_q)}::uuid,
    p_session_id => {sql_quote(session_t)}::uuid,
    p_slug => 'cascade-t',
    p_name => 'Cascade T'
    """,
)
run_psql(
    dedent(
        f"""
        insert into public.songs (
          id, organization_id, slug, title, chordpro_source
        )
        values (
          {sql_quote(extra_song_id)}::uuid,
          {org}::uuid,
          'cascade-extra',
          'Cascade Extra',
          '{{title: Cascade Extra}}'
        );

        insert into public.attachments (
          id, organization_id, song_id, storage_bucket, storage_path,
          mime_type, file_name
        )
        values (
          {sql_quote(attachment_id)}::uuid,
          {org}::uuid,
          {sql_quote(extra_song_id)}::uuid,
          'song-attachments',
          'cascade/extra.pdf',
          'application/pdf',
          'extra.pdf'
        );
        """
    )
)
call(
    "create_song_session_item",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_t)}::uuid,
    p_session_item_id => {sql_quote(item_t1)}::uuid,
    p_song_id => {sql_quote(seed_song_id)}::uuid,
    p_base_version => 1,
    p_position => null
    """,
)
call(
    "create_song_session_item",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_t)}::uuid,
    p_session_item_id => {sql_quote(item_t2)}::uuid,
    p_song_id => {sql_quote(extra_song_id)}::uuid,
    p_base_version => 2,
    p_position => null
    """,
)
run_psql(
    dedent(
        f"""
        insert into public.session_items (
          id, organization_id, session_id, attachment_id, item_type,
          position, version
        )
        values (
          {sql_quote(item_t3)}::uuid,
          {org}::uuid,
          {sql_quote(session_t)}::uuid,
          {sql_quote(attachment_id)}::uuid,
          'attachment',
          99,
          1
        );
        """
    )
)
q_before = plan_content_version(plan_q)
items_of_t = (
    "select count(*) from public.session_items "
    f"where session_id = {sql_quote(session_t)}::uuid;"
)

assert call_error(
    "delete_session",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_t)}::uuid,
    p_base_version => 1
    """,
) == ("P0001", "session_version_conflict")
assert plan_content_version(plan_q) == q_before
assert row_count(items_of_t) == 3

deleted_t = call(
    "delete_session",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_t)}::uuid,
    p_base_version => 3
    """,
)
assert deleted_t["deleted"] is True, deleted_t
assert deleted_t["deleted_version"] == 3, deleted_t
assert deleted_t["plan_id"] == plan_q, deleted_t
assert deleted_t["plan_content_version"] == q_before + 1, deleted_t
assert plan_content_version(plan_q) == q_before + 1
assert row_count(items_of_t) == 0
assert row_count(
    "select count(*) from public.songs where id in ("
    f"{sql_quote(seed_song_id)}::uuid, {sql_quote(extra_song_id)}::uuid);"
) == 2
assert row_count(
    "select count(*) from public.attachments "
    f"where id = {sql_quote(attachment_id)}::uuid;"
) == 1
assert call_error(
    "delete_session",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_t)}::uuid,
    p_base_version => 3
    """,
) == ("P0002", "session_not_found")

# --- B1: delete_plan cascades sessions and items, never songs -------------

deleted_p = call("delete_plan", delete_p_args)
assert deleted_p == {
    "id": plan_p,
    "organization_id": organization_id,
    "deleted": True,
    "deleted_version": 2,
    "deleted_content_version": 10,
}, deleted_p
assert row_count(
    f"select count(*) from public.plans where id = {sql_quote(plan_p)}::uuid;"
) == 0
assert row_count(
    "select count(*) from public.sessions "
    f"where plan_id = {sql_quote(plan_p)}::uuid;"
) == 0
assert row_count(
    "select count(*) from public.session_items "
    f"where id = {sql_quote(item_a1)}::uuid;"
) == 0
assert row_count(
    "select count(*) from public.songs "
    f"where id = {sql_quote(seed_song_id)}::uuid;"
) == 1
assert call_error("delete_plan", delete_p_args) == ("P0002", "plan_not_found")

# --- B7: hardening of every new or recreated function ---------------------

function_signatures = {
    "create_session": "uuid, uuid, uuid, text, text",
    "rename_session": "uuid, uuid, bigint, text",
    "reorder_plan_sessions": "uuid, uuid, bigint, uuid[]",
    "create_song_session_item": "uuid, uuid, uuid, uuid, bigint, integer",
    "delete_session_item": "uuid, uuid, uuid, bigint",
    "reorder_session_items": "uuid, uuid, bigint, uuid[]",
    "delete_empty_session": "uuid, uuid, bigint",
    "delete_session": "uuid, uuid, bigint",
    "delete_plan": "uuid, uuid, bigint, bigint",
}
for name, args in function_signatures.items():
    secdef, config, auth_exec, anon_exec = fetch_row(
        dedent(
            f"""
            select
              p.prosecdef,
              coalesce(array_to_string(p.proconfig, ','), ''),
              has_function_privilege('authenticated', p.oid, 'execute'),
              has_function_privilege('anon', p.oid, 'execute')
            from pg_proc as p
            where p.oid = 'public.{name}({args})'::regprocedure;
            """
        )
    )
    assert secdef == "t", (name, secdef)
    assert "search_path=public" in config, (name, config)
    assert auth_exec == "t", (name, auth_exec)
    assert anon_exec == "f", (name, anon_exec)

helper_privileges = fetch_row(
    dedent(
        """
        select
          has_function_privilege(
            'authenticated',
            'public.bump_plan_content_version(uuid, uuid)'::regprocedure,
            'execute'
          ),
          has_function_privilege(
            'anon',
            'public.bump_plan_content_version(uuid, uuid)'::regprocedure,
            'execute'
          );
        """
    )
)
assert helper_privileges == ["f", "f"], helper_privileges

print("planning cascade delete contract verification passed")
PY
EOF
```

- [ ] **Step 3: Wire it into the backend contract runner.**

In `scripts/backend-write-contracts.sh`, directly after the block that runs
`$planning_write_contract_test_script`, add:

```bash
planning_cascade_delete_test_script="${PLANNING_CASCADE_DELETE_TEST_SCRIPT:-./scripts/tests/planning-cascade-delete-contract-test.sh}"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$planning_cascade_delete_test_script"
```

- [ ] **Step 4: Run it and watch it fail.**

Run: `./scripts/backend-write-contracts.sh`

Expected: FAIL. `planning-write-contract-test.sh` still passes, then the new
script stops with `KeyError: 'content_version'` on the first assertion
against `created_p`.

- [ ] **Step 5: Commit.**

```bash
git add scripts/tests/planning-cascade-delete-contract-test.sh scripts/backend-write-contracts.sh
git commit -m "test(planning): red -- content version and cascade delete contract

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 1.2: Migration (green)

**Files:**
- Create: `supabase/migrations/202609290001_plan_content_version_and_cascade_delete.sql`

The bodies below are the current definitions (`202604100001`, `202604110001`,
`202606290002`) changed in three ways:

1. Each child write bumps `content_version` first, through
   `bump_plan_content_version` or the plan update itself (I4, I5).
2. Session version checks move after that lock and become conditional
   updates (I5). As a side effect, two concurrent item writes on one session
   no longer both pass a stale pre-lock check.
3. Six functions return `plan_content_version` (D1).

Every error code, message, and precedence the existing contract test pins is
unchanged.

- [ ] **Step 1: Write the migration.**

```sql
-- Plan content version and cascading plan/session delete.
--
-- Spec: docs/specs/2026-09-29-plan-delete-and-session-cascade.md (D1-D3,
-- invariants I1, I2, I4, I5). ADR: ADR-038.
--
-- plans.content_version counts every accepted write to a plan's sessions
-- and session items (I4). delete_plan checks it together with plans.version,
-- so a cascade delete can never remove content the deleting client did not
-- see (I2). Every child write locks the owning plan row first, through the
-- content_version bump, before its version check and its session or item
-- writes (I5). The session version checks therefore run as conditional
-- updates after that lock.

alter table public.plans
  add column content_version bigint not null default 1;

alter table public.plans
  add constraint plans_content_version_check check (content_version > 0);

-- Internal helper. Not callable by clients; every caller is a security
-- definer planning RPC that has already authorized the write.
create function public.bump_plan_content_version(
  p_organization_id uuid,
  p_plan_id uuid
)
returns bigint
language plpgsql
set search_path = public
as $$
declare
  v_content_version bigint;
begin
  update public.plans as plan
  set content_version = plan.content_version + 1
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
  returning plan.content_version into v_content_version;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'plan_not_found',
      detail = 'The owning plan does not exist in the requested organization';
  end if;

  return v_content_version;
end;
$$;

-- create_session: returns the session row plus plan_content_version.
drop function public.create_session(uuid, uuid, uuid, text, text);

create function public.create_session(
  p_organization_id uuid,
  p_plan_id uuid,
  p_session_id uuid,
  p_slug text,
  p_name text
)
returns table (
  id uuid,
  organization_id uuid,
  group_id uuid,
  plan_id uuid,
  "position" integer,
  name text,
  notes text,
  version bigint,
  base_version bigint,
  sync_status public.sync_status,
  updated_at timestamptz,
  last_modified_by uuid,
  slug text,
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  parent_plan public.plans%rowtype;
  created_session public.sessions%rowtype;
  candidate_slug text;
  next_position integer;
  v_constraint_name text;
  v_plan_content_version bigint;
begin
  select *
  into parent_plan
  from public.plans as plan
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
    and public.has_capability(
      plan.organization_id,
      'canEditSessions',
      plan.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'plan_not_found',
      detail = 'The target plan does not exist in the requested organization';
  end if;

  -- I5: lock the owning plan before touching sessions (and count, I4).
  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    p_plan_id
  );

  candidate_slug := public.session_next_slug(
    p_plan_id,
    coalesce(nullif(p_slug, ''), nullif(p_name, ''), p_session_id::text)
  );

  select coalesce(max(session.position), 0) + 1
  into next_position
  from public.sessions as session
  where session.plan_id = p_plan_id;

  loop
    begin
      insert into public.sessions (
        id,
        organization_id,
        group_id,
        plan_id,
        slug,
        position,
        name,
        version,
        base_version,
        sync_status,
        last_modified_by
      )
      values (
        p_session_id,
        p_organization_id,
        parent_plan.group_id,
        p_plan_id,
        candidate_slug,
        next_position,
        p_name,
        1,
        null,
        'synced',
        auth.uid()
      )
      returning * into created_session;

      return query
      select
        created_session.id,
        created_session.organization_id,
        created_session.group_id,
        created_session.plan_id,
        created_session.position,
        created_session.name,
        created_session.notes,
        created_session.version,
        created_session.base_version,
        created_session.sync_status,
        created_session.updated_at,
        created_session.last_modified_by,
        created_session.slug,
        v_plan_content_version;
      return;
    exception
      when unique_violation then
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name = 'sessions_plan_slug_unique' then
          candidate_slug := public.session_next_slug(p_plan_id, candidate_slug);
        elsif v_constraint_name = 'sessions_plan_id_position_key' then
          select coalesce(max(session.position), 0) + 1
          into next_position
          from public.sessions as session
          where session.plan_id = p_plan_id;
        else
          raise;
        end if;
    end;
  end loop;

  raise exception using
    errcode = 'P0001',
    message = 'session_create_exhausted',
    detail = 'create_session exited without inserting a session';
end;
$$;

-- rename_session: returns the session row plus plan_content_version.
drop function public.rename_session(uuid, uuid, bigint, text);

create function public.rename_session(
  p_organization_id uuid,
  p_session_id uuid,
  p_base_version bigint,
  p_name text
)
returns table (
  id uuid,
  organization_id uuid,
  group_id uuid,
  plan_id uuid,
  "position" integer,
  name text,
  notes text,
  version bigint,
  base_version bigint,
  sync_status public.sync_status,
  updated_at timestamptz,
  last_modified_by uuid,
  slug text,
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  updated_session public.sessions%rowtype;
  v_plan_content_version bigint;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = 'base_version is required for session updates';
  end if;

  select *
  into existing_session
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and public.has_capability(
      session.organization_id,
      'canEditSessions',
      session.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_not_found',
      detail = 'The target session does not exist in the requested organization';
  end if;

  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  update public.sessions as session
  set
    name = p_name,
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning * into updated_session;

  if found then
    return query
    select
      updated_session.id,
      updated_session.organization_id,
      updated_session.group_id,
      updated_session.plan_id,
      updated_session.position,
      updated_session.name,
      updated_session.notes,
      updated_session.version,
      updated_session.base_version,
      updated_session.sync_status,
      updated_session.updated_at,
      updated_session.last_modified_by,
      updated_session.slug,
      v_plan_content_version;
    return;
  end if;

  raise exception using
    errcode = 'P0001',
    message = 'session_version_conflict',
    detail = format(
      'expected base_version %s but found current version %s',
      p_base_version::text,
      existing_session.version::text
    );
end;
$$;

-- reorder_plan_sessions: the conditional plan update is the lock, the
-- version check, and the content_version bump in one statement.
drop function public.reorder_plan_sessions(uuid, uuid, bigint, uuid[]);

create function public.reorder_plan_sessions(
  p_organization_id uuid,
  p_plan_id uuid,
  p_base_version bigint,
  p_session_ids uuid[]
)
returns table (
  plan_id uuid,
  organization_id uuid,
  version bigint,
  ordered_session_ids uuid[],
  ordered_session_positions integer[],
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_plan public.plans%rowtype;
  current_session_ids uuid[];
  temp_position_offset integer;
  v_version bigint;
  v_plan_content_version bigint;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'plan_version_conflict',
      detail = 'base_version is required for session reorder';
  end if;

  select *
  into existing_plan
  from public.plans as plan
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
    and public.has_capability(
      plan.organization_id,
      'canManagePlans',
      plan.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'plan_not_found',
      detail = 'The target plan does not exist in the requested organization';
  end if;

  update public.plans as plan
  set
    version = plan.version + 1,
    base_version = plan.version,
    content_version = plan.content_version + 1,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
    and plan.version = p_base_version
  returning plan.version, plan.content_version
  into v_version, v_plan_content_version;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'plan_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        existing_plan.version::text
      );
  end if;

  select array_agg(session.id order by session.position, session.id)
  into current_session_ids
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.plan_id = p_plan_id;

  if coalesce(array_length(current_session_ids, 1), 0) <>
      coalesce(array_length(p_session_ids, 1), 0)
      or coalesce(
        array_length(
          array(
            select distinct requested.session_id
            from unnest(coalesce(p_session_ids, array[]::uuid[])) as requested(session_id)
          ),
          1
        ),
        0
      ) <> coalesce(array_length(p_session_ids, 1), 0)
      or exists (
        select 1
        from unnest(coalesce(p_session_ids, array[]::uuid[])) as requested(session_id)
        where not requested.session_id = any(coalesce(current_session_ids, array[]::uuid[]))
      ) then
    raise exception using
      errcode = 'P0001',
      message = 'session_reorder_blocked_invalid_permutation',
      detail = 'session reorder must include each visible session exactly once';
  end if;

  select coalesce(max(session.position), 0) + coalesce(array_length(p_session_ids, 1), 0) + 1
  into temp_position_offset
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.plan_id = p_plan_id;

  update public.sessions as session
  set position = temp_position_offset + reordered.ordinality
  from unnest(p_session_ids) with ordinality as reordered(session_id, ordinality)
  where session.organization_id = p_organization_id
    and session.plan_id = p_plan_id
    and session.id = reordered.session_id;

  update public.sessions as session
  set position = session.position - temp_position_offset
  where session.organization_id = p_organization_id
    and session.plan_id = p_plan_id;

  return query
  select
    existing_plan.id,
    p_organization_id,
    v_version,
    (
      select coalesce(array_agg(session.id order by session.position, session.id), array[]::uuid[])
      from public.sessions as session
      where session.organization_id = p_organization_id
        and session.plan_id = p_plan_id
    ),
    (
      select coalesce(
        array_agg(session.position order by session.position, session.id),
        array[]::integer[]
      )
      from public.sessions as session
      where session.organization_id = p_organization_id
        and session.plan_id = p_plan_id
    ),
    v_plan_content_version;
end;
$$;

-- create_song_session_item: plan lock + bump, then conditional session bump.
drop function public.create_song_session_item(uuid, uuid, uuid, uuid, bigint, integer);

create function public.create_song_session_item(
  p_organization_id uuid,
  p_session_id uuid,
  p_session_item_id uuid,
  p_song_id uuid,
  p_base_version bigint,
  p_position integer default null
)
returns table (
  id uuid,
  plan_id uuid,
  session_id uuid,
  organization_id uuid,
  song_id uuid,
  song_title text,
  "position" integer,
  version bigint,
  ordered_session_item_ids uuid[],
  ordered_session_item_positions integer[],
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  visible_song public.songs%rowtype;
  next_position integer;
  v_constraint_name text;
  v_session_version bigint;
  v_plan_content_version bigint;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = 'base_version is required for session-item create';
  end if;

  select *
  into existing_session
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and public.has_capability(
      session.organization_id,
      'canEditSessions',
      session.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_not_found',
      detail = 'The target session does not exist in the requested organization';
  end if;

  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  update public.sessions as session
  set
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning session.version into v_session_version;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        existing_session.version::text
      );
  end if;

  select *
  into visible_song
  from public.songs as song
  where song.organization_id = p_organization_id
    and song.id = p_song_id
    and public.has_capability(song.organization_id, 'canViewSongs');

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'song_not_visible_blocked',
      detail = 'The requested song is not visible in the active organization';
  end if;

  if exists (
    select 1
    from public.session_items as item
    where item.organization_id = p_organization_id
      and item.session_id = p_session_id
      and item.item_type = 'song'
      and item.song_id = p_song_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'duplicate_song_in_session_blocked',
      detail = 'The same song may appear at most once within one session';
  end if;

  select coalesce(max(item.position), 0) + 1
  into next_position
  from public.session_items as item
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id;

  begin
    insert into public.session_items (
      id,
      organization_id,
      session_id,
      song_id,
      item_type,
      position,
      version,
      base_version,
      sync_status,
      last_modified_by
    )
    values (
      p_session_item_id,
      p_organization_id,
      p_session_id,
      p_song_id,
      'song',
      coalesce(p_position, next_position),
      1,
      null,
      'synced',
      auth.uid()
    );
  exception
    when unique_violation then
      get stacked diagnostics v_constraint_name = constraint_name;
      if v_constraint_name = 'session_items_unique_song_per_session' then
        raise exception using
          errcode = 'P0001',
          message = 'duplicate_song_in_session_blocked',
          detail = 'The same song may appear at most once within one session';
      end if;
      raise;
  end;

  return query
  select
    p_session_item_id,
    existing_session.plan_id,
    p_session_id,
    p_organization_id,
    p_song_id,
    visible_song.title,
    (
      select item.position
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.id = p_session_item_id
    ),
    v_session_version,
    (
      select coalesce(array_agg(item.id order by item.position, item.id), array[]::uuid[])
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    ),
    (
      select coalesce(
        array_agg(item.position order by item.position, item.id),
        array[]::integer[]
      )
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    ),
    v_plan_content_version;
end;
$$;

-- delete_session_item: plan lock + bump, then conditional session bump.
drop function public.delete_session_item(uuid, uuid, uuid, bigint);

create function public.delete_session_item(
  p_organization_id uuid,
  p_session_id uuid,
  p_session_item_id uuid,
  p_base_version bigint
)
returns table (
  id uuid,
  plan_id uuid,
  session_id uuid,
  organization_id uuid,
  version bigint,
  ordered_session_item_ids uuid[],
  ordered_session_item_positions integer[],
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  v_session_version bigint;
  v_plan_content_version bigint;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = 'base_version is required for session-item delete';
  end if;

  select *
  into existing_session
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and public.has_capability(
      session.organization_id,
      'canEditSessions',
      session.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_not_found',
      detail = 'The target session does not exist in the requested organization';
  end if;

  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  update public.sessions as session
  set
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning session.version into v_session_version;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        existing_session.version::text
      );
  end if;

  delete from public.session_items as item
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id
    and item.id = p_session_item_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_item_not_found',
      detail = 'The target session item does not exist in the requested session';
  end if;

  return query
  select
    p_session_item_id,
    existing_session.plan_id,
    p_session_id,
    p_organization_id,
    v_session_version,
    (
      select coalesce(array_agg(item.id order by item.position, item.id), array[]::uuid[])
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    ),
    (
      select coalesce(
        array_agg(item.position order by item.position, item.id),
        array[]::integer[]
      )
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    ),
    v_plan_content_version;
end;
$$;

-- reorder_session_items: plan lock + bump, then conditional session bump.
drop function public.reorder_session_items(uuid, uuid, bigint, uuid[]);

create function public.reorder_session_items(
  p_organization_id uuid,
  p_session_id uuid,
  p_base_version bigint,
  p_session_item_ids uuid[]
)
returns table (
  plan_id uuid,
  session_id uuid,
  organization_id uuid,
  version bigint,
  ordered_session_item_ids uuid[],
  ordered_session_item_positions integer[],
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  current_item_ids uuid[];
  temp_position_offset integer;
  v_session_version bigint;
  v_plan_content_version bigint;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = 'base_version is required for session-item reorder';
  end if;

  select *
  into existing_session
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and public.has_capability(
      session.organization_id,
      'canEditSessions',
      session.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_not_found',
      detail = 'The target session does not exist in the requested organization';
  end if;

  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  update public.sessions as session
  set
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning session.version into v_session_version;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        existing_session.version::text
      );
  end if;

  select array_agg(item.id order by item.position, item.id)
  into current_item_ids
  from public.session_items as item
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id;

  if coalesce(array_length(current_item_ids, 1), 0) <>
      coalesce(array_length(p_session_item_ids, 1), 0)
      or coalesce(
        array_length(
          array(
            select distinct requested.item_id
            from unnest(coalesce(p_session_item_ids, array[]::uuid[])) as requested(item_id)
          ),
          1
        ),
        0
      ) <> coalesce(array_length(p_session_item_ids, 1), 0)
      or exists (
        select 1
        from unnest(coalesce(p_session_item_ids, array[]::uuid[])) as requested(item_id)
        where not requested.item_id = any(coalesce(current_item_ids, array[]::uuid[]))
      ) then
    raise exception using
      errcode = 'P0001',
      message = 'session_item_reorder_blocked_invalid_permutation',
      detail = 'session-item reorder must include each visible item exactly once';
  end if;

  select coalesce(max(item.position), 0) + coalesce(array_length(p_session_item_ids, 1), 0) + 1
  into temp_position_offset
  from public.session_items as item
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id;

  update public.session_items as item
  set position = temp_position_offset + reordered.ordinality
  from unnest(p_session_item_ids) with ordinality as reordered(item_id, ordinality)
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id
    and item.id = reordered.item_id;

  update public.session_items as item
  set position = item.position - temp_position_offset
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id;

  return query
  select
    existing_session.plan_id,
    p_session_id,
    p_organization_id,
    v_session_version,
    (
      select coalesce(array_agg(item.id order by item.position, item.id), array[]::uuid[])
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    ),
    (
      select coalesce(
        array_agg(item.position order by item.position, item.id),
        array[]::integer[]
      )
      from public.session_items as item
      where item.organization_id = p_organization_id
        and item.session_id = p_session_id
    ),
    v_plan_content_version;
end;
$$;

-- delete_empty_session (legacy, D3): same signature, return shape and
-- emptiness rule; gains the bump. `create or replace` keeps its grants.
create or replace function public.delete_empty_session(
  p_organization_id uuid,
  p_session_id uuid,
  p_base_version bigint
)
returns table (
  id uuid,
  plan_id uuid,
  organization_id uuid,
  deleted boolean,
  deleted_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_session public.sessions%rowtype;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = 'base_version is required for session deletes';
  end if;

  select *
  into existing_session
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and public.has_capability(
      session.organization_id,
      'canEditSessions',
      session.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_not_found',
      detail = 'The target session does not exist in the requested organization';
  end if;

  perform public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  if existing_session.version <> p_base_version then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        existing_session.version::text
      );
  end if;

  if exists (
    select 1
    from public.session_items as session_item
    where session_item.organization_id = p_organization_id
      and session_item.session_id = p_session_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'session_delete_blocked_not_empty',
      detail = 'Session delete is allowed only when the session has no session_items';
  end if;

  return query
  delete from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning
    session.id,
    session.plan_id,
    session.organization_id,
    true,
    session.version;

  if found then
    return;
  end if;

  raise exception using
    errcode = 'P0002',
    message = 'session_not_found',
    detail = 'The target session no longer exists in the requested organization';
end;
$$;

comment on function public.delete_empty_session(uuid, uuid, bigint) is
  'Deprecated: kept for installed clients. New clients call delete_session '
  '(cascade). docs/specs/2026-09-29-plan-delete-and-session-cascade.md D3.';

-- delete_session (D3): cascade delete of one session and its items.
create function public.delete_session(
  p_organization_id uuid,
  p_session_id uuid,
  p_base_version bigint
)
returns table (
  id uuid,
  plan_id uuid,
  organization_id uuid,
  deleted boolean,
  deleted_version bigint,
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  v_plan_content_version bigint;
  v_current_version bigint;
begin
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = 'base_version is required for session deletes';
  end if;

  select *
  into existing_session
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and public.has_capability(
      session.organization_id,
      'canEditSessions',
      session.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_not_found',
      detail = 'The target session does not exist in the requested organization';
  end if;

  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  -- Items follow through session_items_session_scope_fk (on delete cascade).
  -- Songs and attachments are only referenced, never deleted (I1).
  return query
  delete from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and session.version = p_base_version
  returning
    session.id,
    session.plan_id,
    session.organization_id,
    true,
    session.version,
    v_plan_content_version;

  if found then
    return;
  end if;

  select session.version
  into v_current_version
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id;

  if found then
    raise exception using
      errcode = 'P0001',
      message = 'session_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        v_current_version::text
      );
  end if;

  raise exception using
    errcode = 'P0002',
    message = 'session_not_found',
    detail = 'The target session no longer exists in the requested organization';
end;
$$;

-- delete_plan (D2): cascade delete of a plan, its sessions and their items.
create function public.delete_plan(
  p_organization_id uuid,
  p_plan_id uuid,
  p_base_version bigint,
  p_base_content_version bigint
)
returns table (
  id uuid,
  organization_id uuid,
  deleted boolean,
  deleted_version bigint,
  deleted_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_plan public.plans%rowtype;
  current_plan public.plans%rowtype;
begin
  if p_base_version is null or p_base_content_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'plan_version_conflict',
      detail = 'base_version and base_content_version are required for plan deletes';
  end if;

  select *
  into existing_plan
  from public.plans as plan
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
    and public.has_capability(
      plan.organization_id,
      'canManagePlans',
      plan.group_id
    )
    and public.has_capability(
      plan.organization_id,
      'canEditSessions',
      plan.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'plan_not_found',
      detail = 'The target plan does not exist in the requested organization';
  end if;

  -- The delete itself takes the plan-row lock (I5). Sessions and items
  -- follow through sessions_plan_scope_fk and
  -- session_items_session_scope_fk (on delete cascade); songs and
  -- attachments are only referenced, never deleted (I1).
  return query
  delete from public.plans as plan
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id
    and plan.version = p_base_version
    and plan.content_version = p_base_content_version
  returning
    plan.id,
    plan.organization_id,
    true,
    plan.version,
    plan.content_version;

  if found then
    return;
  end if;

  select *
  into current_plan
  from public.plans as plan
  where plan.organization_id = p_organization_id
    and plan.id = p_plan_id;

  if found then
    raise exception using
      errcode = 'P0001',
      message = 'plan_version_conflict',
      detail = format(
        'expected version %s / content_version %s but found %s / %s',
        p_base_version::text,
        p_base_content_version::text,
        current_plan.version::text,
        current_plan.content_version::text
      );
  end if;

  raise exception using
    errcode = 'P0002',
    message = 'plan_not_found',
    detail = 'The target plan no longer exists in the requested organization';
end;
$$;

revoke all on function public.bump_plan_content_version(uuid, uuid)
from public, anon, authenticated;

revoke all on function public.create_session(uuid, uuid, uuid, text, text)
from public, anon, authenticated;
revoke all on function public.rename_session(uuid, uuid, bigint, text)
from public, anon, authenticated;
revoke all on function public.reorder_plan_sessions(uuid, uuid, bigint, uuid[])
from public, anon, authenticated;
revoke all on function public.create_song_session_item(uuid, uuid, uuid, uuid, bigint, integer)
from public, anon, authenticated;
revoke all on function public.delete_session_item(uuid, uuid, uuid, bigint)
from public, anon, authenticated;
revoke all on function public.reorder_session_items(uuid, uuid, bigint, uuid[])
from public, anon, authenticated;
revoke all on function public.delete_session(uuid, uuid, bigint)
from public, anon, authenticated;
revoke all on function public.delete_plan(uuid, uuid, bigint, bigint)
from public, anon, authenticated;

grant execute on function public.create_session(uuid, uuid, uuid, text, text)
to authenticated;
grant execute on function public.rename_session(uuid, uuid, bigint, text)
to authenticated;
grant execute on function public.reorder_plan_sessions(uuid, uuid, bigint, uuid[])
to authenticated;
grant execute on function public.create_song_session_item(uuid, uuid, uuid, uuid, bigint, integer)
to authenticated;
grant execute on function public.delete_session_item(uuid, uuid, uuid, bigint)
to authenticated;
grant execute on function public.reorder_session_items(uuid, uuid, bigint, uuid[])
to authenticated;
grant execute on function public.delete_session(uuid, uuid, bigint)
to authenticated;
grant execute on function public.delete_plan(uuid, uuid, bigint, bigint)
to authenticated;
```

- [ ] **Step 2: Run the contracts.**

Run: `./scripts/backend-write-contracts.sh`

Expected: every script passes, including the existing
`planning-write-contract-test.sh`, `slug-parity-contract-test.sh`, and
`organization-read-only-role-test.sh`. The new script prints
`planning cascade delete contract verification passed`.

If an existing assertion fails, apply STOP condition 1.

- [ ] **Step 3: Lint the migrations.**

Run: `./scripts/check-migrations.sh`

Expected: `supabase db lint` reports no errors for the new functions.

- [ ] **Step 4: Commit.**

```bash
git add supabase/migrations/202609290001_plan_content_version_and_cascade_delete.sql
git commit -m "feat(planning): plan content version and cascading delete RPCs

Adds plans.content_version (bumped once by every session and session-item
write, plan row locked first), delete_plan checking version and content
version, and delete_session cascading items. delete_empty_session stays for
installed clients.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Review gate 1

One reviewer, whole Phase 1 diff, one question:

> "Find any path through the new or recreated functions that commits a child
> write without bumping `plans.content_version` exactly once, commits a bump
> without a child write, takes a `sessions` or `session_items` row lock
> before the owning `plans` row lock, or lets `delete_plan` / `delete_session`
> succeed with a stale base. Also find any existing contract assertion whose
> meaning changed."

Fix the findings and re-run `./scripts/backend-write-contracts.sh`.

**Gate 1 outcome (2026-09-30).**

Fixed in the migration, with race contract tests R1–R7 (B8) written red
first:
- `delete_empty_session` re-reads the session under the plan lock. Before,
  a write that committed while it waited made it raise `session_not_found`
  or `session_delete_blocked_not_empty` instead of
  `session_version_conflict`.
- Every conditional-update miss re-selects the row. It raises `*_not_found`
  when the row was deleted during the wait, and otherwise reports the
  current version in `detail`.
- `delete_plan` no longer declares a lookup variable it never reads, which
  clears the lint warning.
- B3 now also covers a foreign `create_session`.

Accepted as-is: the reorder RPCs bump even when they move nothing. This is
fail-safe; see spec I4.

Out of scope, pre-existing: `authenticated` can still write `plans`,
`sessions`, and `session_items` directly under the `for all` RLS policies,
which bypasses the RPCs. See
`docs/deferred/2026-09-30-direct-dml-bypasses-write-rpcs.md`.

---

## Phase 2 — Client content-version plumbing (no delete yet)

### Task 2.1: Drift schema 7

**Files:**
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_tables.dart`
- Modify: `apps/lyron_app/lib/src/offline/planning/planning_local_database.dart` (+ regenerate `planning_local_database.g.dart`)
- Test: `apps/lyron_app/test/offline/adversarial/planning_migration_test.dart`

- [ ] **Step 1: Write the failing migration test.**

Append a third `test(...)` to `planning_migration_test.dart`. It builds a real
v6 database by hand: the v5 DDL already in the second test, plus
`local_revision`.

```dart
  test(
    'an existing v6 database gains contentVersion / baseContentVersion as '
    'null on upgrade and keeps its rows (spec D4)',
    () async {
      final file = await createRelaunchDbFile('planning-migration-v6-v7');
      PlanningLocalDatabase? openDb;
      addTearDown(() async {
        await openDb?.close();
        if (await file.parent.exists()) {
          await file.parent.delete(recursive: true);
        }
      });

      final rawDb = sqlite3.sqlite3.open(file.path);
      rawDb.execute('''
        CREATE TABLE "planning_projection_owners" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "snapshot_version" INTEGER NOT NULL,
          "refreshed_at" INTEGER NOT NULL,
          PRIMARY KEY ("user_id", "organization_id")
        );
        CREATE TABLE "cached_planning_plans" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "snapshot_version" INTEGER NOT NULL,
          "plan_id" TEXT NOT NULL,
          "slug" TEXT NOT NULL,
          "name" TEXT NOT NULL,
          "description" TEXT NULL,
          "scheduled_for" INTEGER NULL,
          "updated_at" INTEGER NOT NULL,
          "version" INTEGER NOT NULL,
          PRIMARY KEY ("user_id", "organization_id", "plan_id")
        );
        CREATE TABLE "cached_planning_sessions" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "snapshot_version" INTEGER NOT NULL,
          "session_id" TEXT NOT NULL,
          "plan_id" TEXT NOT NULL,
          "slug" TEXT NOT NULL,
          "position" INTEGER NOT NULL,
          "name" TEXT NOT NULL,
          "version" INTEGER NOT NULL,
          PRIMARY KEY ("user_id", "organization_id", "session_id")
        );
        CREATE TABLE "cached_planning_session_items" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "snapshot_version" INTEGER NOT NULL,
          "session_item_id" TEXT NOT NULL,
          "plan_id" TEXT NOT NULL,
          "session_id" TEXT NOT NULL,
          "position" INTEGER NOT NULL,
          "song_id" TEXT NOT NULL,
          "song_title" TEXT NOT NULL,
          PRIMARY KEY ("user_id", "organization_id", "session_item_id")
        );
        CREATE TABLE "cached_planning_mutations" (
          "user_id" TEXT NOT NULL,
          "organization_id" TEXT NOT NULL,
          "aggregate_type" TEXT NOT NULL,
          "aggregate_id" TEXT NOT NULL,
          "mutation_kind" TEXT NOT NULL,
          "sync_status" TEXT NOT NULL,
          "plan_id" TEXT NULL,
          "session_id" TEXT NULL,
          "slug" TEXT NULL,
          "name" TEXT NULL,
          "description" TEXT NULL,
          "scheduled_for" INTEGER NULL,
          "position" INTEGER NULL,
          "song_id" TEXT NULL,
          "song_title" TEXT NULL,
          "ordered_sibling_ids" TEXT NULL,
          "base_version" INTEGER NULL,
          "origin_snapshot_json" TEXT NULL,
          "error_code" TEXT NULL,
          "error_message" TEXT NULL,
          "order_key" INTEGER NOT NULL,
          "updated_at" INTEGER NOT NULL,
          "local_revision" INTEGER NOT NULL DEFAULT 1,
          PRIMARY KEY ("user_id", "organization_id", "aggregate_type", "aggregate_id")
        );
      ''');
      rawDb.execute('''
        INSERT INTO planning_projection_owners (
          user_id, organization_id, snapshot_version, refreshed_at
        ) VALUES ('user-1', 'org-1', 1, 0);
        INSERT INTO cached_planning_plans (
          user_id, organization_id, snapshot_version, plan_id, slug, name,
          updated_at, version
        ) VALUES ('user-1', 'org-1', 1, 'plan-1', 'plan-one', 'Plan One', 0, 3);
        INSERT INTO cached_planning_mutations (
          user_id, organization_id, aggregate_type, aggregate_id,
          mutation_kind, sync_status, name, base_version, order_key,
          updated_at, local_revision
        ) VALUES (
          'user-1', 'org-1', 'plan', 'plan-1', 'plan_edit', 'pending',
          'Edited', 3, 1, 0, 1
        );
      ''');
      rawDb.execute('PRAGMA user_version = 6;');
      rawDb.close();

      final db = PlanningLocalDatabase.connect(openRelaunchExecutor(file));
      openDb = db;
      final localStore = DriftPlanningLocalStore(db);
      final store = DriftPlanningMutationStore(
        database: db,
        localStore: localStore,
      );

      final summaries = await localStore.readPlanSummaries(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      expect(summaries.single.version, 3);
      expect(
        summaries.single.contentVersion,
        isNull,
        reason: 'a pre-7 row has no known content version until refresh',
      );

      final edit = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(edit!.kind, PlanningMutationKind.planEdit);
      expect(edit.baseVersion, 3);
      expect(edit.baseContentVersion, isNull);

      await db.close();
      openDb = null;
    },
  );
```

- [ ] **Step 2: Run it and watch it fail.**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/planning_migration_test.dart`

Expected: compile error (`contentVersion` and `baseContentVersion` are not
defined).

- [ ] **Step 3: Add the columns and the migration.**

In `planning_local_tables.dart`, add to `CachedPlanningPlans` after `version`:

```dart
  /// The backend's `plans.content_version` as of this projection row (spec
  /// D4, docs/specs/2026-09-29-plan-delete-and-session-cascade.md). `null`
  /// means unknown: a row written before schema 7, until the next full
  /// refresh.
  IntColumn get contentVersion => integer().nullable()();
```

Add to `CachedPlanningMutations` after `baseVersion`:

```dart
  /// The plan content version a `planDelete` was based on (spec D4/D5).
  /// Only meaningful for `planDelete` rows.
  IntColumn get baseContentVersion => integer().nullable()();
```

In `planning_local_database.dart`, add inside `onUpgrade` after the
`from < 6` block, and bump `schemaVersion` to 7:

```dart
      if (from < 7) {
        // Spec D4 (docs/specs/2026-09-29-plan-delete-and-session-cascade.md):
        // pre-7 plan rows have no known content version. Null makes a plan
        // delete recorded before the next full refresh conflict (fail-safe)
        // instead of guessing a base.
        await m.addColumn(
          cachedPlanningPlans,
          cachedPlanningPlans.contentVersion,
        );
        await m.addColumn(
          cachedPlanningMutations,
          cachedPlanningMutations.baseContentVersion,
        );
      }
```

```dart
  @override
  int get schemaVersion => 7;
```

Regenerate: `cd apps/lyron_app && dart run build_runner build --delete-conflicting-outputs`

The test still fails to compile, because `PlanSummary.contentVersion` and
`PlanningMutationRecord.baseContentVersion` do not exist yet. Add the minimum
now:

- In `domain/planning/plan_summary.dart`:
  - add `this.contentVersion` as the last named constructor parameter
  - add the field `final int? contentVersion;`
  - add `other.contentVersion == contentVersion` to `==` and
    `contentVersion` to `Object.hash`
- In `planning_local_store.dart` `_toPlanSummary`, pass
  `contentVersion: row.contentVersion`.
- In `planning_mutation_sync_types.dart` `PlanningMutationRecord`:
  - add the named constructor parameters `this.baseContentVersion` and
    `this.acceptedPlanContentVersion`
  - add the fields `final int? baseContentVersion;` and
    `final int? acceptedPlanContentVersion;`
  - in `copyWith`, add `int? baseContentVersion, bool clearBaseContentVersion = false, int? acceptedPlanContentVersion, bool clearAcceptedPlanContentVersion = false`
    and pass through:
    `baseContentVersion: clearBaseContentVersion ? null : (baseContentVersion ?? this.baseContentVersion)`,
    `acceptedPlanContentVersion: clearAcceptedPlanContentVersion ? null : (acceptedPlanContentVersion ?? this.acceptedPlanContentVersion)`.
  - Doc comment on `acceptedPlanContentVersion`: "In-memory only, never
    persisted: the backend's `plan_content_version` (or a `plans` row's
    `content_version`) from the RPC response this record was mapped from.
    Spec D4/D7."
- In `drift_planning_mutation_store.dart`:
  - `_toRecord`: add `baseContentVersion: row.baseContentVersion`.
  - `_upsertRecord`: add `baseContentVersion: Value(record.baseContentVersion),`
    to the companion.
  - `_matchesPersistedRecord`: add
    `existing.baseContentVersion == record.baseContentVersion &&`.

- [ ] **Step 4: Run the test, then the full verification.**

Run: `cd apps/lyron_app && flutter test test/offline/adversarial/planning_migration_test.dart`
Expected: PASS (all three tests).

Then run the full verification (format, analyze, full `flutter test`).
Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): local schema 7 with plan content version columns

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2.2: Content version through pull, projection, and overlay

**Files:**
- Modify:
  - `lib/src/application/planning/planning_sync_payload.dart`
  - `lib/src/infrastructure/planning/supabase_planning_repository.dart`
  - `lib/src/application/planning/planning_sync_controller.dart`
  - `lib/src/offline/planning/planning_local_store.dart`
  - `lib/src/application/planning/planning_local_read_repository.dart`
- Test:
  - `test/infrastructure/planning/supabase_planning_repository_test.dart`
  - `test/offline/planning/planning_local_store_test.dart`
  - `test/application/planning/planning_local_read_repository_test.dart`

(Paths are relative to `apps/lyron_app/`.)

- [ ] **Step 1: Write the failing tests.**

In `supabase_planning_repository_test.dart`, this pins I7 and the mapping:

```dart
  test('fetchPlanningSyncPayload reads every plan row before any session row '
      'and carries content_version (spec I7, D4)', () async {
    final calls = <String>[];
    final repository = SupabasePlanningRepository.testing(
      listPlanRows: ({organizationId}) async {
        calls.add('plans');
        return [
          {
            'id': 'plan-1',
            'organization_id': 'org-1',
            'slug': 'plan-1',
            'name': 'One',
            'description': null,
            'scheduled_for': null,
            'updated_at': '2026-09-29T00:00:00Z',
            'version': 1,
            'content_version': 5,
          },
          {
            'id': 'plan-2',
            'organization_id': 'org-1',
            'slug': 'plan-2',
            'name': 'Two',
            'description': null,
            'scheduled_for': null,
            'updated_at': '2026-09-29T00:00:00Z',
            'version': 1,
            'content_version': 2,
          },
        ];
      },
      getPlanRow: (_) async => null,
      listSessionRows: (planId) async {
        calls.add('sessions:$planId');
        return const [];
      },
    );

    final payload = await repository.fetchPlanningSyncPayload(
      organizationId: 'org-1',
    );

    expect(calls, ['plans', 'sessions:plan-1', 'sessions:plan-2']);
    expect(payload.plans.map((plan) => plan.contentVersion), [5, 2]);
  });
```

In `planning_local_store_test.dart`, inside `group('PlanningLocalStore', ...)`:

```dart
    test('a full refresh stores contentVersion and a reconcile upsert never '
        'overwrites an existing row\'s value (spec D4, I7)', () async {
      await store.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            slug: 'plan-1',
            name: 'Plan',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 9, 29),
            version: 3,
            contentVersion: 7,
          ),
        ],
        sessions: const [],
        items: const [],
        refreshedAt: DateTime.utc(2026, 9, 29),
      );
      expect(
        (await store.readPlanSummaries(
          userId: 'user-1',
          organizationId: 'org-1',
        )).single.contentVersion,
        7,
      );

      for (final incoming in [null, 1, 99]) {
        await store.upsertSyncedPlan(
          userId: 'user-1',
          organizationId: 'org-1',
          refreshedAt: DateTime.utc(2026, 9, 29, 1),
          plan: CachedPlanRecord(
            id: 'plan-1',
            slug: 'plan-1',
            name: 'Renamed',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 9, 29, 1),
            version: 4,
            contentVersion: incoming,
          ),
        );
        final detail = await store.readPlanDetail(
          userId: 'user-1',
          organizationId: 'org-1',
          planId: 'plan-1',
        );
        expect(detail!.plan.name, 'Renamed');
        expect(detail.plan.contentVersion, 7, reason: 'incoming $incoming');
      }
    });

    test('a reconcile upsert of a plan not yet in the projection stores its '
        'contentVersion', () async {
      await store.upsertSyncedPlan(
        userId: 'user-1',
        organizationId: 'org-1',
        refreshedAt: DateTime.utc(2026, 9, 29),
        plan: CachedPlanRecord(
          id: 'plan-new',
          slug: 'plan-new',
          name: 'New',
          description: null,
          scheduledFor: null,
          updatedAt: DateTime.utc(2026, 9, 29),
          version: 1,
          contentVersion: 1,
        ),
      );
      final detail = await store.readPlanDetail(
        userId: 'user-1',
        organizationId: 'org-1',
        planId: 'plan-new',
      );
      expect(detail!.plan.contentVersion, 1);
    });
```

In `planning_local_read_repository_test.dart`: the `setUp` projection plan
has no content version. Change that `CachedPlanRecord` in `setUp` to include
`version: 2, contentVersion: 5`, then add:

```dart
    test('a pending plan edit keeps the projection contentVersion in merged '
        'reads (spec D4)', () async {
      await mutationStore.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Renamed',
          baseVersion: 2,
        ),
      );

      final detail = await repository.getPlanDetail('plan-1');
      final summary = (await repository.listPlans()).single;

      expect(detail.plan.name, 'Renamed');
      expect(detail.plan.contentVersion, 5);
      expect(summary.contentVersion, 5);
    });
```

If an existing test in that file asserted `version: 1` for plan-1, update it
to 2. It is the same fixture change, not a meaning change.

- [ ] **Step 2: Run the tests and watch them fail.**

Run: `cd apps/lyron_app && flutter test test/infrastructure/planning/supabase_planning_repository_test.dart test/offline/planning/planning_local_store_test.dart test/application/planning/planning_local_read_repository_test.dart`

Expected: compile errors (`contentVersion` not a parameter of
`CachedPlanRecord` / `PlanningSyncPlan`).

- [ ] **Step 3: Implement.**

1. `planning_sync_payload.dart` `PlanningSyncPlan`: add the optional named
   `this.contentVersion` and `final int? contentVersion;`.
2. `planning_local_store.dart` `CachedPlanRecord`: add the optional named
   `this.contentVersion` and `final int? contentVersion;`.
3. `supabase_planning_repository.dart`:
   - In all three plan `.select(...)` strings, append `, content_version`:
     `'id, organization_id, slug, name, description, scheduled_for, updated_at, version, content_version'`.
   - In `_mapPlanSummary`, add
     `contentVersion: (row['content_version'] as num?)?.toInt(),`.
   - In `fetchPlanningSyncPayload`, add `contentVersion: plan.contentVersion,`
     to `PlanningSyncPlan(...)`.
   - Add this comment above the per-plan session loop:
     `// I7 (docs/specs/2026-09-29-plan-delete-and-session-cascade.md): every plan row, including content_version, is read before any session row, so a race can only leave contentVersion behind its children, never ahead.`
4. `planning_sync_controller.dart`: in the `CachedPlanRecord(...)` built from
   `payload.plans`, add `contentVersion: plan.contentVersion,`.
5. `planning_local_store.dart`:
   - In `_replaceActiveProjection`'s plan companion, add
     `contentVersion: Value(plan.contentVersion),`.
   - In `_upsertPlanRow`, the early-return equality check stays as is. It
     does not compare `contentVersion`, on purpose. Set the companion field
     so that an existing row's value is never overwritten:

```dart
            // Spec D4/I7: only a full refresh (replaceActiveProjection) or
            // the contiguous own-write rule (advanceSyncedPlanContentVersion)
            // may change an existing row's content version. A reconcile
            // upsert keeps it; a brand-new row takes the reconciled value.
            contentVersion: Value(
              existing != null ? existing.contentVersion : plan.contentVersion,
            ),
```

6. `planning_local_read_repository.dart`: in every `PlanSummary(...)` built
   from an existing summary, add `contentVersion: existing.contentVersion,`.
   There are two such places: the `planEdit` case of `_mergePlanSummaries`
   and the `planEdit` branch of `_mergePlanDetail`, where the source is
   `plan.contentVersion`. `planCreate` overlays keep the default `null`.

- [ ] **Step 4: Run the tests, then full verification.**

Expected: the new tests PASS; full suite green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): carry plan content version through pull and projection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2.3: Per-kind RPC parameters and response mapping (fixes converted-delete params)

**Files:**
- Modify: `lib/src/infrastructure/planning/supabase_planning_mutation_repository.dart`
- Test: `test/infrastructure/planning/supabase_planning_mutation_repository_test.dart`

- [ ] **Step 1: Write the failing tests.**

```dart
  test('a session delete converted from a tombstoned create sends only '
      'its own parameters (spec D4)', () async {
    late String rpcName;
    late Map<String, dynamic> rpcParams;
    final repository = SupabasePlanningMutationRepository.testing(
      rpc: (name, {params}) async {
        rpcName = name;
        rpcParams = params ?? const {};
        return [
          {
            'id': 'session-1',
            'plan_id': 'plan-1',
            'organization_id': 'org-1',
            'deleted': true,
            'deleted_version': 1,
          },
        ];
      },
    );

    // resolveCancelledCreate builds the delete with copyWith, so the
    // create's slug/name/position are still on the record.
    await repository.syncMutation(
      organizationId: 'org-1',
      record: PlanningMutationRecord(
        aggregateId: 'session-1',
        organizationId: 'org-1',
        planId: 'plan-1',
        slug: 'warm-up',
        name: 'Warm-Up',
        position: 3,
        baseVersion: 1,
        kind: PlanningMutationKind.sessionDelete,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        updatedAt: DateTime.utc(2026),
      ),
    );

    expect(rpcName, 'delete_empty_session');
    expect(rpcParams, {
      'p_organization_id': 'org-1',
      'p_session_id': 'session-1',
      'p_base_version': 1,
    });
  });

  test('maps plan_content_version and a plans row content_version into '
      'acceptedPlanContentVersion (spec D4)', () async {
    final responses = <Object>[
      [
        {
          'id': 'item-1',
          'plan_id': 'plan-1',
          'session_id': 'session-1',
          'organization_id': 'org-1',
          'version': 4,
          'plan_content_version': 12,
        },
      ],
      {'id': 'plan-1', 'organization_id': 'org-1', 'version': 2, 'content_version': 1},
      [
        {
          'id': 'item-1',
          'plan_id': 'plan-1',
          'session_id': 'session-1',
          'organization_id': 'org-1',
          'version': 5,
        },
      ],
    ];
    var call = 0;
    final repository = SupabasePlanningMutationRepository.testing(
      rpc: (name, {params}) async => responses[call++],
    );
    PlanningMutationRecord record(PlanningMutationKind kind) =>
        PlanningMutationRecord(
          aggregateId: kind == PlanningMutationKind.planEdit
              ? 'plan-1'
              : 'item-1',
          organizationId: 'org-1',
          planId: 'plan-1',
          sessionId: 'session-1',
          name: 'Plan',
          baseVersion: 3,
          kind: kind,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: 1,
          updatedAt: DateTime.utc(2026),
        );

    final itemDelete = await repository.syncMutation(
      organizationId: 'org-1',
      record: record(PlanningMutationKind.sessionItemDelete),
    );
    final planEdit = await repository.syncMutation(
      organizationId: 'org-1',
      record: record(PlanningMutationKind.planEdit),
    );
    final legacyShape = await repository.syncMutation(
      organizationId: 'org-1',
      record: record(PlanningMutationKind.sessionItemDelete),
    );

    expect(itemDelete.acceptedPlanContentVersion, 12);
    expect(itemDelete.baseVersion, 4);
    expect(planEdit.acceptedPlanContentVersion, 1);
    expect(legacyShape.acceptedPlanContentVersion, isNull);
  });
```

- [ ] **Step 2: Run them and watch them fail.**

Run: `cd apps/lyron_app && flutter test test/infrastructure/planning/supabase_planning_mutation_repository_test.dart`

Expected:
- The first test FAILS because `rpcParams` also contains `p_slug` and
  `p_name`. That is the latent defect.
- The second test FAILS on `acceptedPlanContentVersion` (`null`).

- [ ] **Step 3: Implement.**

Replace the `params` map literal in `syncMutation` with
`final params = _paramsFor(record, organizationId: organizationId);` and add:

```dart
  // Spec D4 (docs/specs/2026-09-29-plan-delete-and-session-cascade.md):
  // each kind sends exactly its RPC's parameters. A delete converted from a
  // tombstoned create (resolveCancelledCreate uses copyWith) still carries
  // the create's slug/name; sending those made PostgREST find no matching
  // function (PGRST202), which mapped to `unknown` and left the row pending
  // forever. Parameters a function declares are always sent, null included,
  // so a missing base surfaces as the RPC's own conflict instead.
  Map<String, dynamic> _paramsFor(
    PlanningMutationRecord record, {
    required String organizationId,
  }) {
    final organization = <String, dynamic>{
      'p_organization_id': organizationId,
    };
    return switch (record.kind) {
      PlanningMutationKind.planCreate => {
        ...organization,
        'p_plan_id': record.aggregateId,
        'p_slug': record.slug,
        'p_name': record.name,
        'p_description': record.description,
        'p_scheduled_for': record.scheduledFor?.toIso8601String(),
      },
      PlanningMutationKind.planEdit => {
        ...organization,
        'p_plan_id': record.aggregateId,
        'p_base_version': record.baseVersion,
        'p_name': record.name,
        'p_description': record.description,
        'p_scheduled_for': record.scheduledFor?.toIso8601String(),
      },
      PlanningMutationKind.sessionCreate => {
        ...organization,
        'p_plan_id': record.planId,
        'p_session_id': record.aggregateId,
        'p_slug': record.slug,
        'p_name': record.name,
      },
      PlanningMutationKind.sessionRename => {
        ...organization,
        'p_session_id': record.aggregateId,
        'p_base_version': record.baseVersion,
        'p_name': record.name,
      },
      PlanningMutationKind.sessionDelete => {
        ...organization,
        'p_session_id': record.aggregateId,
        'p_base_version': record.baseVersion,
      },
      PlanningMutationKind.sessionReorder => {
        ...organization,
        'p_plan_id': record.planId ?? record.aggregateId,
        'p_base_version': record.baseVersion,
        'p_session_ids': record.orderedSiblingIds,
      },
      PlanningMutationKind.sessionItemCreateSong => {
        ...organization,
        'p_session_id': record.sessionId,
        'p_session_item_id': record.aggregateId,
        'p_song_id': record.songId,
        'p_base_version': record.baseVersion,
        'p_position': record.position,
      },
      PlanningMutationKind.sessionItemDelete => {
        ...organization,
        'p_session_id': record.sessionId,
        'p_session_item_id': record.aggregateId,
        'p_base_version': record.baseVersion,
      },
      PlanningMutationKind.sessionItemReorder => {
        ...organization,
        'p_session_id': record.sessionId,
        'p_base_version': record.baseVersion,
        'p_session_item_ids': record.orderedSiblingIds,
      },
    };
  }
```

In `_mapRow`'s `copyWith`, add:

```dart
      acceptedPlanContentVersion:
          ((row['plan_content_version'] ?? row['content_version']) as num?)
              ?.toInt(),
```

- [ ] **Step 4: Run the tests, then full verification.**

Expected: both new tests PASS. The existing assertions in the file still pass
(`p_description`/`p_scheduled_for` present-as-null for `planEdit`; no
`p_plan_id` for item create). Full suite green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "fix(planning): send each RPC exactly its own parameters

A delete converted from a tombstoned create kept the create's slug/name
and sent them as p_slug/p_name; PostgREST rejected the call (PGRST202),
which mapped to unknown and left the mutation pending forever. Also maps
plan_content_version / content_version from responses.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2.4: Projection store operations for D7/D8

**Files:**
- Modify: `lib/src/offline/planning/planning_local_store.dart`
- Modify: the 8 `PlanningLocalStore` fakes without `noSuchMethod` (counted
  per class, not per file). The compiler forces all 8 to implement the new
  methods.
  - No-op overrides (6):
    - `test/application/planning/planning_local_read_repository_test.dart`
      (`_RecordingPlanningLocalStore`)
    - `test/application/storage/local_data_lifecycle_test.dart`
      (`_RecordingPlanningLocalStore`)
    - `test/offline/song_catalog/song_catalog_store_test.dart`
      (`_NoopPlanningLocalStore`)
    - `test/app/lyron_app_test.dart` (`_NoopPlanningLocalStore`)
    - `test/presentation/song_library/song_list_screen_test.dart`
      (`_NoopPlanningLocalStore`)
    - `test/application/planning/planning_sync_controller_test.dart`
      (`_BlockingPlanningLocalStore`)
  - Forwarding overrides (2). These wrap a real store in a `_delegate` field;
    a no-op would silently drop a real write passing through them:
    - `test/application/providers_test.dart`
      (`_BlockingDeletePlanningLocalStore`)
    - `test/application/planning/planning_sync_controller_test.dart`
      (`_BlockingBoundaryDeletePlanningLocalStore`)
- Test: `test/offline/planning/planning_local_store_test.dart`

Before starting, list the implementers per class:

```bash
grep -rn "class .* implements PlanningLocalStore" apps/lyron_app/test
```

Inspect each class body for `noSuchMethod`. A file-level `noSuchMethod` grep
is misleading: other fakes in the same file may own it. The classes without
`noSuchMethod` must be exactly the 8 above (`_CallCountingPlanningLocalStore`
extends `DriftPlanningLocalStore` and needs nothing). Otherwise apply STOP
condition 3.

- [ ] **Step 1: Write the failing tests.**

```dart
    group('content version and plan removal (spec D7, D8)', () {
      Future<void> seed() => store.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            slug: 'plan-1',
            name: 'Plan',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 9, 29),
            contentVersion: 4,
          ),
          CachedPlanRecord(
            id: 'plan-2',
            slug: 'plan-2',
            name: 'Other',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 9, 29),
            contentVersion: 1,
          ),
        ],
        sessions: const [
          CachedSessionRecord(
            id: 'session-1',
            planId: 'plan-1',
            position: 1,
            name: 'S',
          ),
          CachedSessionRecord(
            id: 'session-2',
            planId: 'plan-2',
            position: 1,
            name: 'T',
          ),
        ],
        items: const [
          CachedSessionItemRecord(
            id: 'item-1',
            planId: 'plan-1',
            sessionId: 'session-1',
            position: 1,
            songId: 'song-1',
            songTitle: 'Song',
          ),
          CachedSessionItemRecord(
            id: 'item-2',
            planId: 'plan-2',
            sessionId: 'session-2',
            position: 1,
            songId: 'song-1',
            songTitle: 'Song',
          ),
        ],
        refreshedAt: DateTime.utc(2026, 9, 29),
      );

      Future<int?> contentVersion(String planId) async =>
          (await store.readPlanDetail(
            userId: 'user-1',
            organizationId: 'org-1',
            planId: planId,
          ))?.plan.contentVersion;

      test(
        'advanceSyncedPlanContentVersion moves only a contiguous value',
        () async {
          await seed();

          await store.advanceSyncedPlanContentVersion(
            userId: 'user-1',
            organizationId: 'org-1',
            planId: 'plan-1',
            acceptedContentVersion: 6,
          );
          expect(
            await contentVersion('plan-1'),
            4,
            reason: 'gap: foreign write',
          );

          await store.advanceSyncedPlanContentVersion(
            userId: 'user-1',
            organizationId: 'org-1',
            planId: 'plan-1',
            acceptedContentVersion: 5,
          );
          expect(await contentVersion('plan-1'), 5);

          await store.advanceSyncedPlanContentVersion(
            userId: 'user-1',
            organizationId: 'org-1',
            planId: 'plan-1',
            acceptedContentVersion: 5,
          );
          expect(await contentVersion('plan-1'), 5, reason: 'idempotent');
        },
      );

      test(
        'advanceSyncedPlanContentVersion never fills a null value (I7)',
        () async {
          await store.replaceActiveProjection(
            userId: 'user-1',
            organizationId: 'org-1',
            plans: [
              CachedPlanRecord(
                id: 'plan-1',
                slug: 'plan-1',
                name: 'Plan',
                description: null,
                scheduledFor: null,
                updatedAt: DateTime.utc(2026, 9, 29),
                contentVersion: null,
              ),
            ],
            sessions: const [],
            items: const [],
            refreshedAt: DateTime.utc(2026, 9, 29),
          );

          for (final accepted in [0, 1, 2]) {
            await store.advanceSyncedPlanContentVersion(
              userId: 'user-1',
              organizationId: 'org-1',
              planId: 'plan-1',
              acceptedContentVersion: accepted,
            );
            expect(
              await contentVersion('plan-1'),
              isNull,
              reason: 'accepted $accepted: only a full refresh may fill it',
            );
          }
        },
      );

      test('deleteSyncedPlan removes the plan, its sessions and items, and '
          'releases its song references', () async {
        await seed();
        expect(
          await store.countSongReferences(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-1',
          ),
          2,
        );

        await store.deleteSyncedPlan(
          userId: 'user-1',
          organizationId: 'org-1',
          planId: 'plan-1',
          refreshedAt: DateTime.utc(2026, 9, 29, 1),
        );

        expect(
          await store.readPlanDetail(
            userId: 'user-1',
            organizationId: 'org-1',
            planId: 'plan-1',
          ),
          isNull,
        );
        expect(await contentVersion('plan-2'), 1, reason: 'other plan intact');
        expect(
          await store.countSongReferences(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-1',
          ),
          1,
        );
      });
    });
```

- [ ] **Step 2: Run them and watch them fail** (compile error: methods not
  defined).

- [ ] **Step 3: Implement.**

Add to the `PlanningLocalStore` interface:

```dart
  /// Spec D7 rule 1a (docs/specs/2026-09-29-plan-delete-and-session-cascade.md):
  /// sets the synced plan's contentVersion to [acceptedContentVersion] only
  /// when it currently equals `acceptedContentVersion - 1`, i.e. the
  /// accepted write was the only one since the projection's value. No-op
  /// otherwise (I3: never absorb a foreign write).
  Future<void> advanceSyncedPlanContentVersion({
    required String userId,
    required String organizationId,
    required String planId,
    required int acceptedContentVersion,
  });

  /// Spec D8: removes a synced plan and all of its sessions and session
  /// items from the projection, in one transaction.
  Future<void> deleteSyncedPlan({
    required String userId,
    required String organizationId,
    required String planId,
    required DateTime refreshedAt,
  });
```

Implement both in `DriftPlanningLocalStore` as plain `async` bodies:

```dart
  @override
  Future<void> advanceSyncedPlanContentVersion({
    required String userId,
    required String organizationId,
    required String planId,
    required int acceptedContentVersion,
  }) async {
    final owner = await _readOwner(
      userId: userId,
      organizationId: organizationId,
    );
    if (owner == null) {
      return;
    }
    final updatedRows =
        await (_database.update(_database.cachedPlanningPlans)..where(
              (table) =>
                  table.userId.equals(userId) &
                  table.organizationId.equals(organizationId) &
                  table.snapshotVersion.equals(owner.snapshotVersion) &
                  table.planId.equals(planId) &
                  table.contentVersion.equals(acceptedContentVersion - 1),
            ))
            .write(
              CachedPlanningPlansCompanion(
                contentVersion: Value(acceptedContentVersion),
              ),
            );
    if (updatedRows > 0) {
      _onStorageFootprintChanged?.call();
    }
  }

  @override
  Future<void> deleteSyncedPlan({
    required String userId,
    required String organizationId,
    required String planId,
    required DateTime refreshedAt,
  }) async {
    final changed = await _database.transaction(() async {
      final ensuredOwner = await _ensureOwner(
        userId: userId,
        organizationId: organizationId,
        refreshedAt: refreshedAt,
      );
      var changed = ensuredOwner.changed;
      final owner = ensuredOwner.owner;
      changed =
          await (_database.delete(_database.cachedPlanningSessionItems)..where(
                    (table) =>
                        table.userId.equals(userId) &
                        table.organizationId.equals(organizationId) &
                        table.snapshotVersion.equals(owner.snapshotVersion) &
                        table.planId.equals(planId),
                  ))
                  .go() >
              0 ||
          changed;
      changed =
          await (_database.delete(_database.cachedPlanningSessions)..where(
                    (table) =>
                        table.userId.equals(userId) &
                        table.organizationId.equals(organizationId) &
                        table.snapshotVersion.equals(owner.snapshotVersion) &
                        table.planId.equals(planId),
                  ))
                  .go() >
              0 ||
          changed;
      changed =
          await (_database.delete(_database.cachedPlanningPlans)..where(
                    (table) =>
                        table.userId.equals(userId) &
                        table.organizationId.equals(organizationId) &
                        table.snapshotVersion.equals(owner.snapshotVersion) &
                        table.planId.equals(planId),
                  ))
                  .go() >
              0 ||
          changed;
      return changed;
    });
    if (changed) {
      _onStorageFootprintChanged?.call();
    }
  }
```

Neither method is `_guarded`. In this store `_guarded` is only for
storage-growing upserts (`replaceActiveProjection`, `upsertSyncedPlan`, and
the like), not for deletes or in-place version writes.
`deleteSyncedPlan` mirrors `deleteSyncedSession`.
`advanceSyncedPlanContentVersion` mirrors `replaceSyncedSessionOrder`'s
unguarded in-place write, with an early return when there is no owner (no
owner means no row).

In the 6 no-op fakes, add no-op overrides:

```dart
  @override
  Future<void> advanceSyncedPlanContentVersion({
    required String userId,
    required String organizationId,
    required String planId,
    required int acceptedContentVersion,
  }) async {}

  @override
  Future<void> deleteSyncedPlan({
    required String userId,
    required String organizationId,
    required String planId,
    required DateTime refreshedAt,
  }) async {}
```

In the 2 delegating fakes, forward to `_delegate` in the file's existing
forwarding style. Example for `deleteSyncedPlan`; forward
`advanceSyncedPlanContentVersion` the same way:

```dart
  @override
  Future<void> deleteSyncedPlan({
    required String userId,
    required String organizationId,
    required String planId,
    required DateTime refreshedAt,
  }) {
    return _delegate.deleteSyncedPlan(
      userId: userId,
      organizationId: organizationId,
      planId: planId,
      refreshedAt: refreshedAt,
    );
  }
```

- [ ] **Step 4: Run the tests, then full verification.** Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): projection ops for contiguous content version and plan removal

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Review gate 2

> "Find any code path that can set a projection plan's `contentVersion` to a
> value higher than the content the projection reflects (I7): through
> `replaceActiveProjection`, `upsertSyncedPlan`,
> `advanceSyncedPlanContentVersion`, or the pull order. Also find any RPC
> whose parameter set now differs from its SQL signature in
> `202609290001`/earlier migrations."

**Gate 2 outcome (2026-09-30).**

- RPC parameters: every kind's parameter set matches the latest SQL
  signature. No function has a leftover overload.
- `replaceActiveProjection`, `upsertSyncedPlan`,
  `advanceSyncedPlanContentVersion`, and the pull order have no I7 path.
- The reviewer ruled out several cases:
  - old-snapshot rows sharing a primary key (every delete removes all
    snapshots together with the owner);
  - an advance racing a refresh;
  - a pre-7 null row;
  - a stale payload landing after an advance (it can only lower the value).

Found, not fixed in code:
- **Unpaged pull reads (minor).** PostgREST's `max_rows` cap (1000)
  truncates top-level reads silently. A plan with more than 1000 sessions
  would get its full `content_version` next to a truncated session list,
  which breaks I7.
  - Deferred as `docs/deferred/2026-09-30-planning-pull-unpaged-reads.md`,
    because it depends on data volume.
  - The spec (I7) and the pull's I7 comment name the limit.
- **New-row value comes from the caller (minor, latent).**
  `upsertSyncedPlan` stores the passed `contentVersion` for a brand-new row
  whatever the mutation kind. Today no caller passes a `planEdit` response
  value.
  - The interface doc now states the caller rule.
  - Task 3.1 gains a reconciler test that pins `null` for a `planEdit` of a
    plan absent from the projection.
- **Deploy order (spec correction).** Spec D4 said an older backend yields a
  null `content_version`. In fact, selecting the column against a backend
  without `202609290001` fails the whole refresh.
  - D4 now says to deploy the backend first.
  - Task 4.4 Step 3 already puts the deploy order in the PR body. It is a
    hard requirement, not a preference: a client deployed first fails
    every planning refresh.

Accepted as-is:
- `_mapRow` keeps a record's `acceptedPlanContentVersion` when the response
  has none. The field is never persisted, so records read from the store
  always carry `null`, and there is no stale carry-over.

---

## Phase 3 — Delete semantics

### Task 3.1: `planDelete` kind across every exhaustive switch

**Files** (all under `apps/lyron_app/lib/src/`):
- `application/planning/planning_mutation_sync_types.dart`
- `infrastructure/planning/supabase_planning_mutation_repository.dart`
- `application/planning/planning_mutation_reconciler.dart`
- `application/planning/planning_local_read_repository.dart`
- `application/sync/unified_sync_overview.dart`
- `application/planning/drift_planning_mutation_store.dart`
  (`_currentBaseVersionFor`)

**Tests:**
- `test/application/planning/planning_mutation_sync_types_test.dart`
- `test/infrastructure/planning/supabase_planning_mutation_repository_test.dart`
- `test/application/planning/planning_mutation_reconciler_test.dart`
- `test/application/sync/unified_sync_overview_test.dart`

A new enum value breaks every exhaustive switch at once, so this task lands
them all together. Overlay hiding comes in Task 3.6; the store's recording
logic comes in Task 3.2.

- [ ] **Step 1: Write the failing tests.**

`planning_mutation_sync_types_test.dart`:

```dart
  test('planDelete persists as plan_delete on the plan aggregate and does '
      'not count as plan content (spec D4, D7)', () {
    expect(PlanningMutationKind.planDelete.value, 'plan_delete');
    expect(
      planningMutationKindFromValue('plan_delete'),
      PlanningMutationKind.planDelete,
    );
    expect(PlanningMutationKind.planDelete.aggregateType, 'plan');
    expect(
      {
        for (final kind in PlanningMutationKind.values)
          if (kind.bumpsPlanContent) kind,
      },
      {
        PlanningMutationKind.sessionCreate,
        PlanningMutationKind.sessionRename,
        PlanningMutationKind.sessionDelete,
        PlanningMutationKind.sessionReorder,
        PlanningMutationKind.sessionItemCreateSong,
        PlanningMutationKind.sessionItemDelete,
        PlanningMutationKind.sessionItemReorder,
      },
    );
  });
```

`supabase_planning_mutation_repository_test.dart`:

```dart
  test('maps planDelete to delete_plan and sessionDelete to delete_session '
      '(spec D4)', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    final repository = SupabasePlanningMutationRepository.testing(
      rpc: (name, {params}) async {
        calls.add((name, params ?? const {}));
        return [
          {
            'id': name == 'delete_plan' ? 'plan-1' : 'session-1',
            'organization_id': 'org-1',
            'deleted': true,
            'deleted_version': 2,
          },
        ];
      },
    );

    await repository.syncMutation(
      organizationId: 'org-1',
      record: PlanningMutationRecord(
        aggregateId: 'plan-1',
        organizationId: 'org-1',
        slug: 'kept-from-create',
        name: 'Kept From Create',
        description: 'kept',
        baseVersion: 2,
        baseContentVersion: 9,
        kind: PlanningMutationKind.planDelete,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 1,
        updatedAt: DateTime.utc(2026),
      ),
    );
    await repository.syncMutation(
      organizationId: 'org-1',
      record: PlanningMutationRecord(
        aggregateId: 'session-1',
        organizationId: 'org-1',
        planId: 'plan-1',
        baseVersion: 4,
        kind: PlanningMutationKind.sessionDelete,
        syncStatus: PlanningMutationSyncStatus.pending,
        orderKey: 2,
        updatedAt: DateTime.utc(2026),
      ),
    );

    expect(calls[0].$1, 'delete_plan');
    expect(calls[0].$2, {
      'p_organization_id': 'org-1',
      'p_plan_id': 'plan-1',
      'p_base_version': 2,
      'p_base_content_version': 9,
    });
    expect(calls[1].$1, 'delete_session');
    expect(calls[1].$2, {
      'p_organization_id': 'org-1',
      'p_session_id': 'session-1',
      'p_base_version': 4,
    });
  });
```

The `sessionDelete` → `delete_empty_session` expectation added in Task 2.3
changes here to `delete_session`, same parameters. The switch is part of
D3/D4, not a meaning change of that test's subject, which is the parameter
set.

`planning_mutation_reconciler_test.dart`: use the file's existing projection
setup (real `DriftPlanningLocalStore`, or its recording fake). Add a test
that seeds `plan-1` with a session and an item and reconciles a `planDelete`
record:

```dart
PlanningMutationRecord(
  aggregateId: 'plan-1',
  organizationId: 'org-1',
  kind: PlanningMutationKind.planDelete,
  syncStatus: PlanningMutationSyncStatus.pending,
  orderKey: 1,
  updatedAt: DateTime.utc(2026),
)
```

Assert that `readPlanDetail('plan-1')` is `null` afterwards. With a recording
fake, assert `deleteSyncedPlan` was called with `planId: 'plan-1'`.

Add a second test: reconciling a `planCreate` record with
`acceptedPlanContentVersion: 1` for a plan not in the projection yields
`contentVersion == 1`.

Add a third test (review gate 2): reconciling a `planEdit` record with
`acceptedPlanContentVersion: 9` for a plan not in the projection yields
`contentVersion == null`. A `planEdit` response's `content_version` can
include foreign writes, and `upsertSyncedPlan` takes the passed value for a
brand-new row (I7).

`unified_sync_overview_test.dart`: use the file's existing `_compute`
helper, inside `group('computeUnifiedSyncOverview', ...)`.

```dart
  test('a conflicted plan removal is titled from its snapshot and explains '
      'the conflict (spec D9)', () {
    final overview = _compute(
        plans: [
          PlanningMutationRecord(
            aggregateId: 'session-9',
            organizationId: 'org-1',
            planId: 'plan-1',
            kind: PlanningMutationKind.sessionRename,
            syncStatus: PlanningMutationSyncStatus.failedDependency,
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
            originSnapshot: const {'name': 'A Session Name'},
          ),
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            kind: PlanningMutationKind.planDelete,
            syncStatus: PlanningMutationSyncStatus.conflict,
            orderKey: 2,
            updatedAt: DateTime.utc(2026),
            originSnapshot: const {'name': 'Sunday Service'},
          ),
        ],
    );

    final row = overview.planRows.single;
    expect(row.title, 'Sunday Service');
    expect(
      row.nestedSummaries.last,
      'plan removal conflicts: the plan changed after you deleted it — '
      'retry deletes it as it is now, discard keeps it',
    );
  });
```

- [ ] **Step 2: Run them and watch them fail** (compile errors:
  `planDelete`, `bumpsPlanContent`).

- [ ] **Step 3: Implement.**

`planning_mutation_sync_types.dart`:
- Add `planDelete,` after `planEdit,` in `PlanningMutationKind`.
- `value`: `PlanningMutationKind.planDelete => 'plan_delete',`
- `aggregateType`:
  `PlanningMutationKind.planCreate || PlanningMutationKind.planEdit || PlanningMutationKind.planDelete => 'plan',`
- `planningMutationKindFromValue`: `'plan_delete' => PlanningMutationKind.planDelete,`
- Add to `PlanningMutationKindX`:

```dart
  /// Whether this kind's backend RPC bumps `plans.content_version` (spec I4,
  /// D7 rule 1, docs/specs/2026-09-29-plan-delete-and-session-cascade.md).
  /// Exhaustive on purpose: a new kind must decide.
  bool get bumpsPlanContent => switch (this) {
    PlanningMutationKind.planCreate ||
    PlanningMutationKind.planEdit ||
    PlanningMutationKind.planDelete => false,
    PlanningMutationKind.sessionCreate ||
    PlanningMutationKind.sessionRename ||
    PlanningMutationKind.sessionDelete ||
    PlanningMutationKind.sessionReorder ||
    PlanningMutationKind.sessionItemCreateSong ||
    PlanningMutationKind.sessionItemDelete ||
    PlanningMutationKind.sessionItemReorder => true,
  };
```

- Add the draft:

```dart
class PlanningPlanDeleteMutationDraft {
  const PlanningPlanDeleteMutationDraft({
    required this.planId,
    this.baseVersion,
    this.baseContentVersion,
    this.originSnapshot,
  });

  final String planId;
  final int? baseVersion;
  final int? baseContentVersion;
  final Map<String, Object?>? originSnapshot;
}
```

`supabase_planning_mutation_repository.dart`:
- `rpcName`: add `PlanningMutationKind.planDelete => 'delete_plan',` and
  change `sessionDelete` to `'delete_session'`.
- `_paramsFor`: add

```dart
      PlanningMutationKind.planDelete => {
        ...organization,
        'p_plan_id': record.aggregateId,
        'p_base_version': record.baseVersion,
        'p_base_content_version': record.baseContentVersion,
      },
```

`planning_mutation_reconciler.dart`:
- Add a case:

```dart
      case PlanningMutationKind.planDelete:
        await localStore.deleteSyncedPlan(
          userId: context.userId,
          organizationId: context.organizationId,
          planId: record.aggregateId,
          refreshedAt: reconciledAt,
        );
        return;
```

- In the `planCreate`/`planEdit` `CachedPlanRecord(...)`, add:

```dart
            // Spec D4: a new plan starts at the response's content version;
            // an edit never changes it (upsertSyncedPlan keeps an existing
            // row's value anyway).
            contentVersion: record.kind == PlanningMutationKind.planCreate
                ? (record.acceptedPlanContentVersion ?? 1)
                : null,
```

`planning_local_read_repository.dart`:
- Add `case PlanningMutationKind.planDelete:` to the child-kind `break` group
  in `_mergePlanSummaries`, and to the `planCreate`/`planEdit` `break` group
  in `_mergePlanDetail`.
- The hiding behavior comes in Task 3.6. Here the change only keeps the file
  compiling.

`unified_sync_overview.dart`:
- `_nestedSummaryFor`:

```dart
    PlanningMutationKind.planDelete =>
      entry.syncStatus == PlanningMutationSyncStatus.conflict
          ? 'plan removal conflicts: the plan changed after you deleted it — '
                'retry deletes it as it is now, discard keeps it'
          : 'plan removed',
```

- `_planTitle` first loop:
  `if (candidate.kind == PlanningMutationKind.planCreate || candidate.kind == PlanningMutationKind.planEdit || candidate.kind == PlanningMutationKind.planDelete) {`
- `_planGroupKey`: add `case PlanningMutationKind.planDelete:` to the
  `planCreate`/`planEdit` group, which returns `entry.aggregateId`. The
  switch has a `default:`, so the analyzer will not flag it.
  - Without this, a `planDelete` (whose `planId` is null) falls into
    `'__orphan_${entry.aggregateId}'`.
  - It would then form its own row, separate from its plan's other entries,
    and the test above fails on `planRows.single`.

`drift_planning_mutation_store.dart` `_currentBaseVersionFor`:
- Change the first arm to
  `PlanningMutationKind.planEdit || PlanningMutationKind.planDelete || PlanningMutationKind.sessionCreate || PlanningMutationKind.sessionReorder => detail?.plan.version,`.

Then run `flutter analyze`. It lists any other non-exhaustive switch, including
in test files. For each: a `plan`-aggregate branch takes the `planEdit`
behavior; a child-kind branch does nothing. If the right choice is unclear,
STOP.

- [ ] **Step 4: Run the tests, then full verification.** Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): planDelete mutation kind, RPC mapping and reconcile

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3.2: Store interface additions and `recordPlanDelete`

**Files:**
- Modify:
  - `planning_mutation_sync_types.dart` (the `PlanningMutationStore` interface)
  - `drift_planning_mutation_store.dart`
  - `budgeted_planning_mutation_store.dart`
- Modify: the 13 `PlanningMutationStore` fakes:
  - `test/integration/song_list_plan_song_pick_flow_test.dart`
  - `test/application/providers_test.dart`
  - `test/application/planning/planning_local_read_repository_test.dart`
  - `test/application/planning/planning_invalidation_scope_test.dart`
  - `test/application/planning/budgeted_planning_mutation_store_test.dart`
  - `test/application/planning/planning_mutation_sync_controller_test.dart`
  - `test/application/sync/unified_discard_controller_test.dart`
  - `test/application/sync/unified_row_recovery_controller_test.dart`
  - `test/presentation/planning/widgets/plan_song_item_row_test.dart`
  - `test/presentation/planning/plan_detail_screen_test.dart`
  - `test/presentation/planning/plan_list_screen_test.dart`
  - `test/offline/adversarial/planning_reconcile_failure_isolation_test.dart`
  - `test/offline/adversarial/planning_fault_injection_test.dart`
- Test:
  - `test/offline/planning/planning_mutation_store_test.dart`
  - `test/application/planning/budgeted_planning_mutation_store_test.dart`

Verify the fake list first, per class:

```bash
grep -rn "class .* implements PlanningMutationStore" apps/lyron_app/test
```

Inspect each class body for `noSuchMethod`. A file-level `noSuchMethod` grep
is misleading: other fakes in the same file may own it. The classes without
`noSuchMethod` must fall in exactly those 13 files; otherwise apply STOP
condition 3.

Delegation rule: any fake that wraps a real store in a delegate field must
forward the new methods to it, not no-op or throw. Only pure fakes may no-op
or throw.

Both new interface methods (`recordPlanDelete`, `applyAcceptedWriteEffects`)
are added now, so the fakes change once. `applyAcceptedWriteEffects` gets its
real implementation in Task 3.4 and throws `UnimplementedError` in the Drift
store until then. Nothing calls it before Task 3.5.

- [ ] **Step 1: Write the failing tests** in `planning_mutation_store_test.dart`
  (new group; the setup is the same as the file's first group):

```dart
  group('recordPlanDelete (spec D5)', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore store;
    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );
    const draft = PlanningPlanDeleteMutationDraft(
      planId: 'plan-1',
      baseVersion: 2,
      baseContentVersion: 5,
      originSnapshot: {'name': 'Sunday Service'},
    );

    setUp(() {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      store = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
    });

    tearDown(() async {
      await database.close();
    });

    Future<List<PlanningMutationRecord>> all() =>
        store.readAllMutations(userId: 'user-1', organizationId: 'org-1');

    Future<void> seedChildren() async {
      await store.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-new',
          planId: 'plan-1',
          slug: 'new',
          name: 'New',
          position: 3,
        ),
      );
      await store.recordSessionRename(
        context: context,
        draft: const PlanningSessionRenameMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          name: 'Renamed',
          baseVersion: 1,
        ),
      );
      await store.recordSessionReorder(
        context: context,
        draft: const PlanningSessionReorderMutationDraft(
          planId: 'plan-1',
          orderedSessionIds: ['session-2', 'session-1'],
          baseVersion: 2,
        ),
      );
      await store.recordSessionItemCreateSong(
        context: context,
        draft: const PlanningSessionItemCreateSongMutationDraft(
          sessionItemId: 'item-new',
          sessionId: 'session-1',
          planId: 'plan-1',
          songId: 'song-1',
          songTitle: 'Song',
          position: 1,
          baseVersion: 1,
        ),
      );
      await store.recordSessionItemReorder(
        context: context,
        draft: const PlanningSessionItemReorderMutationDraft(
          sessionId: 'session-2',
          planId: 'plan-1',
          orderedSessionItemIds: ['item-b', 'item-a'],
          baseVersion: 1,
        ),
      );
      // A child of ANOTHER plan must never be touched.
      await store.recordSessionRename(
        context: context,
        draft: const PlanningSessionRenameMutationDraft(
          sessionId: 'session-x',
          planId: 'plan-2',
          name: 'Other plan',
          baseVersion: 1,
        ),
      );
    }

    test('(d) a synced plan gets a pending delete with the draft bases, a '
        'fresh order key, and loses its not-yet-sent child rows', () async {
      await seedChildren();
      final maxKeyBefore = (await all())
          .map((record) => record.orderKey)
          .reduce((a, b) => a > b ? a : b);

      await store.recordPlanDelete(context: context, draft: draft);

      final records = await all();
      expect(records.map((record) => record.aggregateId), [
        'session-x',
        'plan-1',
      ]);
      final delete = records.last;
      expect(delete.kind, PlanningMutationKind.planDelete);
      expect(delete.syncStatus, PlanningMutationSyncStatus.pending);
      expect(delete.baseVersion, 2);
      expect(delete.baseContentVersion, 5);
      expect(delete.originSnapshot, {'name': 'Sunday Service'});
      expect(delete.orderKey, greaterThan(maxKeyBefore));
    });

    test('(d) in-flight child rows (sending/accepted/cancelling) survive',
        () async {
      await seedChildren();
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-new',
        syncStatus: PlanningMutationSyncStatus.sending,
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session_item',
        aggregateId: 'item-new',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );

      await store.recordPlanDelete(context: context, draft: draft);

      expect(
        (await all()).map((record) => record.aggregateId).toSet(),
        {'session-new', 'item-new', 'session-x', 'plan-1'},
      );
    });

    test('(d) over a pending planEdit keeps the edit\'s base version',
        () async {
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Edited',
          baseVersion: 1,
          originSnapshot: {'name': 'Before Edit'},
        ),
      );

      await store.recordPlanDelete(context: context, draft: draft);

      final delete = (await all()).single;
      expect(delete.kind, PlanningMutationKind.planDelete);
      expect(delete.baseVersion, 1);
      expect(delete.baseContentVersion, 5);
      expect(delete.originSnapshot, {'name': 'Before Edit'});
    });

    test('(a) a never-sent planCreate collapses with every child row, in '
        'any status', () async {
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'plan-1',
          name: 'Local',
        ),
      );
      await seedChildren();
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-new',
        syncStatus: PlanningMutationSyncStatus.sending,
      );

      await store.recordPlanDelete(context: context, draft: draft);

      expect((await all()).map((record) => record.aggregateId), [
        'session-x',
      ]);
    });

    test('(b) a sending planCreate becomes a cancelling tombstone', () async {
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'plan-1',
          name: 'Local',
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.sending,
      );

      await store.recordPlanDelete(context: context, draft: draft);

      final tombstone = (await all()).single;
      expect(tombstone.kind, PlanningMutationKind.planCreate);
      expect(tombstone.syncStatus, PlanningMutationSyncStatus.cancelling);
    });

    test('(c) an accepted planCreate becomes a pending delete based on the '
        'fresh plan', () async {
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'plan-1',
          name: 'Local',
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );

      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 1,
        ),
      );

      final delete = (await all()).single;
      expect(delete.kind, PlanningMutationKind.planDelete);
      expect(delete.syncStatus, PlanningMutationSyncStatus.pending);
      expect(delete.baseVersion, 1);
      expect(delete.baseContentVersion, 1);
    });

    test('baseContentVersion persists across a database reopen', () async {
      // Reuse the file-backed reopen pattern from 'pending mutations persist
      // across database reopen' in this file: record the delete on a
      // file-backed database, close, reopen, read it back.
    });
  });
```

For the last test, copy the structure of the existing test
`'pending mutations persist across database reopen'` in the same file:
- replace its `recordPlanCreate` with
  `recordPlanDelete(context: context, draft: draft)`
- assert `baseContentVersion == 5` after the reopen

In `budgeted_planning_mutation_store_test.dart`, add two tests next to the
existing `recordSessionDelete` admission tests, mirroring them exactly:
- a `recordPlanDelete` over a pending `planCreate` is admitted past the
  refuse threshold
- a `recordPlanDelete` over a synced plan (no row) is refused past the
  threshold with `PlanningMutationBudgetExceededException`

- [ ] **Step 2: Run them and watch them fail** (compile errors).

- [ ] **Step 3: Implement.**

Interface (`PlanningMutationStore` in `planning_mutation_sync_types.dart`),
after `recordPlanEdit`:

```dart
  /// Spec D5 (docs/specs/2026-09-29-plan-delete-and-session-cascade.md).
  Future<void> recordPlanDelete({
    required PlanningMutationContext context,
    required PlanningPlanDeleteMutationDraft draft,
  });
```

After `resolveCancelledCreate`:

```dart
  /// Spec D7 + D8: the store-side consequences of a backend-accepted write.
  ///
  /// When [remoteResponse] is true, [accepted] was mapped from an RPC
  /// response in the current sync run, and the D7 contiguity rules may use
  /// its returned versions to rebase a not-in-flight pending cascade delete
  /// (and the projection's plan content version). When false (a
  /// crash-resumed `accepted` marker, whose `baseVersion` is still the
  /// pre-write base), only the D8 purge runs.
  ///
  /// D8: when [accepted] is a `planDelete`/`sessionDelete`, every remaining
  /// mutation row of the deleted subtree is removed, in any status.
  ///
  /// Idempotent. Never grows the store.
  Future<void> applyAcceptedWriteEffects({
    required String userId,
    required String organizationId,
    required PlanningMutationRecord accepted,
    required bool remoteResponse,
  });
```

In `DriftPlanningMutationStore`, add the in-flight set and the two
child-deletion helpers next to `_deletePendingMutationsForSession`:

```dart
  /// Spec D5: statuses whose row is on its way to, or already on, the
  /// backend. A cascade delete keeps these child rows; they conclude on
  /// their own and D8 purges whatever is left once the delete is accepted.
  static const _inFlightSyncStatuses = <PlanningMutationSyncStatus>{
    PlanningMutationSyncStatus.sending,
    PlanningMutationSyncStatus.cancelling,
    PlanningMutationSyncStatus.accepted,
  };

  /// Spec D5/D8: every child row of [planId] -- session, session item and
  /// session-item-order rows carrying the plan id, plus the plan's
  /// session_order row -- optionally sparing in-flight rows. Returns the
  /// number of rows deleted.
  Future<int> _deleteChildMutationsOfPlan({
    required PlanningMutationContext context,
    required String planId,
    required bool keepInFlight,
  }) {
    final table = _database.cachedPlanningMutations;
    var predicate =
        table.userId.equals(context.userId) &
        table.organizationId.equals(context.organizationId) &
        ((table.planId.equals(planId) & table.aggregateType.equals('plan').not()) |
            (table.aggregateType.equals('session_order') &
                table.aggregateId.equals(planId)));
    if (keepInFlight) {
      predicate =
          predicate &
          table.syncStatus.isNotIn(
            _inFlightSyncStatuses.map((status) => status.value),
          );
    }
    return (_database.delete(table)..where((_) => predicate)).go();
  }

  /// Spec D6/D8: every session-item and session-item-order row of
  /// [sessionId], optionally sparing in-flight rows.
  Future<int> _deleteChildMutationsOfSession({
    required PlanningMutationContext context,
    required String sessionId,
    required bool keepInFlight,
  }) {
    final table = _database.cachedPlanningMutations;
    var predicate =
        table.userId.equals(context.userId) &
        table.organizationId.equals(context.organizationId) &
        ((table.aggregateType.equals('session_item') &
                table.sessionId.equals(sessionId)) |
            (table.aggregateType.equals('session_item_order') &
                table.aggregateId.equals(sessionId)));
    if (keepInFlight) {
      predicate =
          predicate &
          table.syncStatus.isNotIn(
            _inFlightSyncStatuses.map((status) => status.value),
          );
    }
    return (_database.delete(table)..where((_) => predicate)).go();
  }
```

`recordPlanDelete`:

```dart
  @override
  Future<void> recordPlanDelete({
    required PlanningMutationContext context,
    required PlanningPlanDeleteMutationDraft draft,
  }) async {
    await _database.transaction(() async {
      final existing = await _readMutationByKey(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: 'plan',
        aggregateId: draft.planId,
      );
      final now = DateTime.now().toUtc();

      if (existing?.kind == PlanningMutationKind.planCreate) {
        switch (existing!.syncStatus) {
          case PlanningMutationSyncStatus.cancelling:
            // Already deleted while its create was in flight; nothing new.
            return;
          case PlanningMutationSyncStatus.sending:
            // D5(b): the create is on the wire. Keep a cancellation
            // tombstone (in-flight-create-cancellation D2); the sync
            // controller resolves it once the create concludes.
            await _upsertRecord(
              context: context,
              aggregateType: 'plan',
              record: existing.copyWith(
                syncStatus: PlanningMutationSyncStatus.cancelling,
                updatedAt: now,
                clearErrorCode: true,
                clearErrorMessage: true,
              ),
            );
            await _deleteChildMutationsOfPlan(
              context: context,
              planId: draft.planId,
              keepInFlight: true,
            );
            return;
          case PlanningMutationSyncStatus.accepted:
            // D5(c): the backend already has the plan; delete it for real.
            // A freshly created plan's versions are both 1 unless the
            // merged read already knew better.
            await _upsertRecord(
              context: context,
              aggregateType: 'plan',
              record: PlanningMutationRecord(
                aggregateId: draft.planId,
                organizationId: context.organizationId,
                kind: PlanningMutationKind.planDelete,
                syncStatus: PlanningMutationSyncStatus.pending,
                orderKey: await _nextOrderKey(
                  userId: context.userId,
                  organizationId: context.organizationId,
                ),
                updatedAt: now,
                baseVersion: existing.baseVersion ?? draft.baseVersion,
                baseContentVersion: draft.baseContentVersion ?? 1,
                originSnapshot:
                    existing.originSnapshot ??
                    draft.originSnapshot ??
                    {'name': existing.name},
              ),
            );
            await _deleteChildMutationsOfPlan(
              context: context,
              planId: draft.planId,
              keepInFlight: true,
            );
            return;
          case PlanningMutationSyncStatus.pending:
          case PlanningMutationSyncStatus.failedAuthorization:
          case PlanningMutationSyncStatus.failedDependency:
          case PlanningMutationSyncStatus.failedRemoteDelete:
          case PlanningMutationSyncStatus.conflict:
            // D5(a): as far as this device knows the plan never reached the
            // backend, so neither did any child: collapse everything.
            await (_database.delete(_database.cachedPlanningMutations)..where(
                  (table) =>
                      table.userId.equals(context.userId) &
                      table.organizationId.equals(context.organizationId) &
                      table.aggregateType.equals('plan') &
                      table.aggregateId.equals(draft.planId),
                ))
                .go();
            await _deleteChildMutationsOfPlan(
              context: context,
              planId: draft.planId,
              keepInFlight: false,
            );
            return;
        }
      }

      // D5(d): a synced plan (no row, or a planEdit/planDelete row). Keep
      // the FIRST local base, like recordPlanEdit: a later local action did
      // not observe a newer remote version. A fresh order key puts the
      // delete after every surviving in-flight child row.
      final repeatsDelete = existing?.kind == PlanningMutationKind.planDelete;
      await _upsertRecord(
        context: context,
        aggregateType: 'plan',
        record: PlanningMutationRecord(
          aggregateId: draft.planId,
          organizationId: context.organizationId,
          kind: PlanningMutationKind.planDelete,
          syncStatus: PlanningMutationSyncStatus.pending,
          orderKey: await _nextOrderKey(
            userId: context.userId,
            organizationId: context.organizationId,
          ),
          updatedAt: now,
          baseVersion: existing?.baseVersion ?? draft.baseVersion,
          baseContentVersion: repeatsDelete
              ? existing!.baseContentVersion
              : draft.baseContentVersion,
          originSnapshot: existing?.originSnapshot ?? draft.originSnapshot,
        ),
      );
      await _deleteChildMutationsOfPlan(
        context: context,
        planId: draft.planId,
        keepInFlight: true,
      );
    });
    _onStorageFootprintChanged?.call();
  }
```

Stub until Task 3.4:

```dart
  @override
  Future<void> applyAcceptedWriteEffects({
    required String userId,
    required String organizationId,
    required PlanningMutationRecord accepted,
    required bool remoteResponse,
  }) => throw UnimplementedError('Task 3.4');
```

`BudgetedPlanningMutationStore`:

```dart
  @override
  Future<void> recordPlanDelete({
    required PlanningMutationContext context,
    required PlanningPlanDeleteMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordPlanDelete(context: context, draft: draft),
    isCollapse: () => _collapsesPendingCreate(
      context: context,
      aggregateType: PlanningMutationKind.planDelete.aggregateType,
      aggregateId: draft.planId,
      pendingCreateKind: PlanningMutationKind.planCreate,
    ),
  );

  // Spec D7/D8: queued with every other write for this context (it
  // rewrites delete rows and purges children), never budget-guarded (it
  // never grows the store), no recovery boundary (nothing to grow).
  @override
  Future<void> applyAcceptedWriteEffects({
    required String userId,
    required String organizationId,
    required PlanningMutationRecord accepted,
    required bool remoteResponse,
  }) => _queuedWrite(
    PlanningMutationContext(userId: userId, organizationId: organizationId),
    () => _delegate.applyAcceptedWriteEffects(
      userId: userId,
      organizationId: organizationId,
      accepted: accepted,
      remoteResponse: remoteResponse,
    ),
  );
```

In each of the 13 fakes, add:

```dart
  @override
  Future<void> recordPlanDelete({
    required PlanningMutationContext context,
    required PlanningPlanDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> applyAcceptedWriteEffects({
    required String userId,
    required String organizationId,
    required PlanningMutationRecord accepted,
    required bool remoteResponse,
  }) async {}
```

Two fakes need more than a no-op:
- `budgeted_planning_mutation_store_test.dart`: its delegate fake should
  record the call the same way it records `recordSessionDelete`, for the
  admission assertions.
- `planning_mutation_sync_controller_test.dart`'s `_FakePlanningMutationStore`:
  add `final List<String> events = [];` and implement
  `applyAcceptedWriteEffects` as
  `events.add('effects:${accepted.aggregateId}:$remoteResponse');`. Also add
  `events.add('save:${syncStatus.name}:$aggregateId');` as the first line of
  its `saveSyncAttemptResult`. Task 3.5 uses both.

- [ ] **Step 4: Run the tests, then full verification.** Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): record plan deletes in the mutation store

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3.3: Cascading `recordSessionDelete`

**Files:**
- Modify: `drift_planning_mutation_store.dart` (the non-create branch of `recordSessionDelete`)
- Test: `test/offline/planning/planning_mutation_store_test.dart`

- [ ] **Step 1: Write the failing test.** Add it to the
  `recordPlanDelete (spec D5)` group from Task 3.2, which provides the
  `store` and `context` fixtures.

```dart
  test('deleting a synced session drops its not-yet-sent item rows, keeps '
      'in-flight ones, and takes a fresh order key (spec D6)', () async {
    await store.recordSessionRename(
      context: context,
      draft: const PlanningSessionRenameMutationDraft(
        sessionId: 'session-1',
        planId: 'plan-1',
        name: 'Renamed',
        baseVersion: 3,
      ),
    );
    await store.recordSessionItemCreateSong(
      context: context,
      draft: const PlanningSessionItemCreateSongMutationDraft(
        sessionItemId: 'item-pending',
        sessionId: 'session-1',
        planId: 'plan-1',
        songId: 'song-1',
        songTitle: 'Song',
        position: 1,
        baseVersion: 3,
      ),
    );
    await store.recordSessionItemCreateSong(
      context: context,
      draft: const PlanningSessionItemCreateSongMutationDraft(
        sessionItemId: 'item-sending',
        sessionId: 'session-1',
        planId: 'plan-1',
        songId: 'song-2',
        songTitle: 'Song 2',
        position: 2,
        baseVersion: 3,
      ),
    );
    await store.saveSyncAttemptResult(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session_item',
      aggregateId: 'item-sending',
      syncStatus: PlanningMutationSyncStatus.sending,
    );
    await store.recordSessionItemReorder(
      context: context,
      draft: const PlanningSessionItemReorderMutationDraft(
        sessionId: 'session-1',
        planId: 'plan-1',
        orderedSessionItemIds: ['item-b', 'item-a'],
        baseVersion: 3,
      ),
    );
    final renameKey = (await store.readMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session',
      aggregateId: 'session-1',
    ))!.orderKey;

    await store.recordSessionDelete(
      context: context,
      draft: const PlanningSessionDeleteMutationDraft(
        sessionId: 'session-1',
        planId: 'plan-1',
        baseVersion: 3,
      ),
    );

    final records = await store.readAllMutations(
      userId: 'user-1',
      organizationId: 'org-1',
    );
    expect(records.map((record) => record.aggregateId).toList(), [
      'item-sending',
      'session-1',
    ]);
    final delete = records.last;
    expect(delete.kind, PlanningMutationKind.sessionDelete);
    expect(delete.baseVersion, 3);
    expect(delete.orderKey, greaterThan(renameKey));
  });
```

- [ ] **Step 2: Run it and watch it fail.** Expected: the pending item and
  item-order rows are still present, and the order key equals the rename's.

- [ ] **Step 3: Implement.** In the non-create branch of `recordSessionDelete`:
  - replace `orderKey: existing?.orderKey ?? await _nextOrderKey(...)` with
    the fresh key below
  - add the child drop before `_removeSessionFromPendingReorder`

```dart
          // Spec D6: a fresh key, after every surviving in-flight child row,
          // so those conclude before the cascade delete is sent.
          orderKey: await _nextOrderKey(
            userId: context.userId,
            organizationId: context.organizationId,
          ),
```

```dart
      // Spec D6: under cascade a not-yet-sent child write could only bump
      // the session version and make this delete conflict with itself.
      await _deleteChildMutationsOfSession(
        context: context,
        sessionId: draft.sessionId,
        keepInFlight: true,
      );
```

The three `sessionCreate` branches stay unchanged.

- [ ] **Step 4: Run the test, then full verification.** Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): cascade session delete drops unsent child writes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3.4: `applyAcceptedWriteEffects` (D7 rebase + D8 purge)

**Files:**
- Modify: `drift_planning_mutation_store.dart`
- Test: `test/offline/planning/planning_mutation_store_test.dart`

- [ ] **Step 1: Write the failing tests.** Add a new group to
  `planning_mutation_store_test.dart`. It seeds a projection so rule 1a is
  observable:

```dart
  group('applyAcceptedWriteEffects (spec D7, D8)', () {
    late PlanningLocalDatabase database;
    late DriftPlanningLocalStore localStore;
    late DriftPlanningMutationStore store;
    const context = PlanningMutationContext(
      userId: 'user-1',
      organizationId: 'org-1',
    );

    setUp(() async {
      database = PlanningLocalDatabase.inMemory();
      localStore = DriftPlanningLocalStore(database);
      store = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
      await localStore.replaceActiveProjection(
        userId: 'user-1',
        organizationId: 'org-1',
        plans: [
          CachedPlanRecord(
            id: 'plan-1',
            slug: 'plan-1',
            name: 'Plan',
            description: null,
            scheduledFor: null,
            updatedAt: DateTime.utc(2026),
            version: 2,
            contentVersion: 5,
          ),
        ],
        sessions: const [
          CachedSessionRecord(
            id: 'session-1',
            planId: 'plan-1',
            position: 1,
            name: 'S',
            version: 3,
          ),
        ],
        items: const [],
        refreshedAt: DateTime.utc(2026),
      );
    });

    tearDown(() async {
      await database.close();
    });

    PlanningMutationRecord accepted(
      PlanningMutationKind kind, {
      String aggregateId = 'item-9',
      int? version,
      int? planContentVersion,
    }) => PlanningMutationRecord(
      aggregateId: aggregateId,
      organizationId: 'org-1',
      planId: 'plan-1',
      sessionId: 'session-1',
      baseVersion: version,
      acceptedPlanContentVersion: planContentVersion,
      kind: kind,
      syncStatus: PlanningMutationSyncStatus.pending,
      orderKey: 99,
      updatedAt: DateTime.utc(2026),
    );

    Future<PlanningMutationRecord?> planRow() => store.readMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'plan',
      aggregateId: 'plan-1',
    );

    Future<int?> projectionContentVersion() async => (await localStore
            .readPlanDetail(
              userId: 'user-1',
              organizationId: 'org-1',
              planId: 'plan-1',
            ))
        ?.plan
        .contentVersion;

    test('rule 1: a contiguous own child write rebases the pending plan '
        'delete and the projection', () async {
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionItemCreateSong,
          version: 4,
          planContentVersion: 6,
        ),
        remoteResponse: true,
      );

      expect((await planRow())!.baseContentVersion, 6);
      expect(await projectionContentVersion(), 6);
    });

    test('rule 1: a gap (foreign write interleaved) changes nothing',
        () async {
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionItemCreateSong,
          version: 4,
          planContentVersion: 7,
        ),
        remoteResponse: true,
      );

      expect((await planRow())!.baseContentVersion, 5);
      expect(await projectionContentVersion(), 5);
    });

    test('rule 1 is idempotent and ignores planEdit/planCreate responses',
        () async {
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );
      final child = accepted(
        PlanningMutationKind.sessionItemDelete,
        version: 4,
        planContentVersion: 6,
      );
      for (var i = 0; i < 2; i += 1) {
        await store.applyAcceptedWriteEffects(
          userId: 'user-1',
          organizationId: 'org-1',
          accepted: child,
          remoteResponse: true,
        );
      }
      expect((await planRow())!.baseContentVersion, 6);

      // A planEdit response whose content_version happens to be base + 1
      // must not rebase anything (planEdit does not bump content).
      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.planEdit,
          aggregateId: 'plan-1',
          version: 9,
          planContentVersion: 7,
        ),
        remoteResponse: true,
      );
      expect((await planRow())!.baseContentVersion, 6);
      expect(await projectionContentVersion(), 6);
    });

    test('rule 2: a contiguous own planEdit rebases the delete that '
        'overwrote it', () async {
      await store.recordPlanEdit(
        context: context,
        draft: const PlanningPlanEditMutationDraft(
          planId: 'plan-1',
          name: 'Edited',
          baseVersion: 2,
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.sending,
      );
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.planEdit,
          aggregateId: 'plan-1',
          version: 3,
          planContentVersion: 5,
        ),
        remoteResponse: true,
      );

      final delete = (await planRow())!;
      expect(delete.kind, PlanningMutationKind.planDelete);
      expect(delete.baseVersion, 3);
      expect(delete.baseContentVersion, 5);
    });

    test('rule 3: a contiguous own item write rebases a pending session '
        'delete', () async {
      await store.recordSessionDelete(
        context: context,
        draft: const PlanningSessionDeleteMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          baseVersion: 3,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionItemCreateSong,
          version: 4,
          planContentVersion: 6,
        ),
        remoteResponse: true,
      );

      final delete = (await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
      ))!;
      expect(delete.baseVersion, 4);
    });

    test('remoteResponse: false never rebases', () async {
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionItemCreateSong,
          version: 4,
          planContentVersion: 6,
        ),
        remoteResponse: false,
      );

      expect((await planRow())!.baseContentVersion, 5);
      expect(await projectionContentVersion(), 5);
    });

    test('an in-flight delete row is never rebased', () async {
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionItemCreateSong,
          version: 4,
          planContentVersion: 6,
        ),
        remoteResponse: true,
      );

      expect((await planRow())!.baseContentVersion, 5);
    });

    test('D8: an accepted planDelete purges every remaining child row, in '
        'any status, and nothing of other plans', () async {
      await store.recordSessionRename(
        context: context,
        draft: const PlanningSessionRenameMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          name: 'R',
          baseVersion: 3,
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
        syncStatus: PlanningMutationSyncStatus.accepted,
      );
      await store.recordSessionRename(
        context: context,
        draft: const PlanningSessionRenameMutationDraft(
          sessionId: 'session-x',
          planId: 'plan-2',
          name: 'Other',
          baseVersion: 1,
        ),
      );
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.planDelete,
          aggregateId: 'plan-1',
          version: 2,
        ),
        remoteResponse: false,
      );

      expect(
        (await store.readAllMutations(
          userId: 'user-1',
          organizationId: 'org-1',
        )).map((record) => record.aggregateId).toSet(),
        {'session-x', 'plan-1'},
      );
    });

    test('D8: an accepted sessionDelete purges its item rows', () async {
      await store.recordSessionItemCreateSong(
        context: context,
        draft: const PlanningSessionItemCreateSongMutationDraft(
          sessionItemId: 'item-1',
          sessionId: 'session-1',
          planId: 'plan-1',
          songId: 'song-1',
          songTitle: 'Song',
          position: 1,
          baseVersion: 3,
        ),
      );
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session_item',
        aggregateId: 'item-1',
        syncStatus: PlanningMutationSyncStatus.failedDependency,
      );

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: accepted(
          PlanningMutationKind.sessionDelete,
          aggregateId: 'session-1',
          version: 3,
        ),
        remoteResponse: true,
      );

      expect(
        await store.readAllMutations(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        isEmpty,
      );
    });
  });
```

- [ ] **Step 2: Run them and watch them fail** (`UnimplementedError`).

- [ ] **Step 3: Implement** (replace the stub):

```dart
  @override
  Future<void> applyAcceptedWriteEffects({
    required String userId,
    required String organizationId,
    required PlanningMutationRecord accepted,
    required bool remoteResponse,
  }) async {
    final context = PlanningMutationContext(
      userId: userId,
      organizationId: organizationId,
    );
    final planId = accepted.kind.aggregateType == 'plan'
        ? accepted.aggregateId
        : accepted.planId;
    final acceptedContentVersion = accepted.acceptedPlanContentVersion;

    // D7 rule 1a -- the projection, in the local store's own transaction.
    if (remoteResponse &&
        accepted.kind.bumpsPlanContent &&
        planId != null &&
        acceptedContentVersion != null) {
      await _localStore.advanceSyncedPlanContentVersion(
        userId: userId,
        organizationId: organizationId,
        planId: planId,
        acceptedContentVersion: acceptedContentVersion,
      );
    }

    var changed = false;
    await _database.transaction(() async {
      if (remoteResponse && planId != null) {
        changed =
            await _rebasePendingPlanDelete(
              context: context,
              planId: planId,
              accepted: accepted,
            ) ||
            changed;
      }
      if (remoteResponse) {
        changed =
            await _rebasePendingSessionDelete(
              context: context,
              accepted: accepted,
            ) ||
            changed;
      }
      if (accepted.kind == PlanningMutationKind.planDelete) {
        changed =
            await _deleteChildMutationsOfPlan(
                  context: context,
                  planId: accepted.aggregateId,
                  keepInFlight: false,
                ) >
                0 ||
            changed;
      }
      if (accepted.kind == PlanningMutationKind.sessionDelete) {
        changed =
            await _deleteChildMutationsOfSession(
                  context: context,
                  sessionId: accepted.aggregateId,
                  keepInFlight: false,
                ) >
                0 ||
            changed;
      }
    });
    if (changed) {
      _onStorageFootprintChanged?.call();
    }
  }

  // D7 rules 1b and 2. Only exact contiguity with the backend-returned
  // value ever moves a base (I3): anything else leaves it stale, and a
  // stale base conflicts -- the fail-safe direction.
  Future<bool> _rebasePendingPlanDelete({
    required PlanningMutationContext context,
    required String planId,
    required PlanningMutationRecord accepted,
  }) async {
    final row = await _readMutationByKey(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: 'plan',
      aggregateId: planId,
    );
    if (row == null ||
        row.kind != PlanningMutationKind.planDelete ||
        _inFlightSyncStatuses.contains(row.syncStatus)) {
      return false;
    }
    var next = row;
    final acceptedContentVersion = accepted.acceptedPlanContentVersion;
    if (accepted.kind.bumpsPlanContent &&
        acceptedContentVersion != null &&
        row.baseContentVersion == acceptedContentVersion - 1) {
      next = next.copyWith(baseContentVersion: acceptedContentVersion);
    }
    final acceptedPlanVersion = accepted.baseVersion;
    if ((accepted.kind == PlanningMutationKind.planEdit ||
            accepted.kind == PlanningMutationKind.sessionReorder) &&
        acceptedPlanVersion != null &&
        row.baseVersion == acceptedPlanVersion - 1) {
      next = next.copyWith(baseVersion: acceptedPlanVersion);
    }
    if (identical(next, row)) {
      return false;
    }
    return _upsertRecord(context: context, aggregateType: 'plan', record: next);
  }

  // D7 rule 3.
  Future<bool> _rebasePendingSessionDelete({
    required PlanningMutationContext context,
    required PlanningMutationRecord accepted,
  }) async {
    final sessionId = switch (accepted.kind) {
      PlanningMutationKind.sessionRename => accepted.aggregateId,
      PlanningMutationKind.sessionItemCreateSong ||
      PlanningMutationKind.sessionItemDelete ||
      PlanningMutationKind.sessionItemReorder => accepted.sessionId,
      _ => null,
    };
    final acceptedSessionVersion = accepted.baseVersion;
    if (sessionId == null || acceptedSessionVersion == null) {
      return false;
    }
    final row = await _readMutationByKey(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: 'session',
      aggregateId: sessionId,
    );
    if (row == null ||
        row.kind != PlanningMutationKind.sessionDelete ||
        _inFlightSyncStatuses.contains(row.syncStatus) ||
        row.baseVersion != acceptedSessionVersion - 1) {
      return false;
    }
    return _upsertRecord(
      context: context,
      aggregateType: 'session',
      record: row.copyWith(baseVersion: acceptedSessionVersion),
    );
  }
```

- [ ] **Step 4: Run the tests, then full verification.** Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): contiguous own-write rebase and post-delete purge

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3.5: Sync controller wiring and `planCreate` tombstones

**Files:**
- Modify: `planning_mutation_sync_controller.dart`
- Modify: `drift_planning_mutation_store.dart` (`resolveCancelledCreate`)
- Test:
  - `test/application/planning/planning_mutation_sync_controller_test.dart`
  - `test/offline/adversarial/planning_in_flight_create_cancellation_test.dart`

- [ ] **Step 1: Write the failing tests.**

In `planning_mutation_sync_controller_test.dart` (the fake's `events` list was
added in Task 3.2):

```dart
    test('applies accepted-write effects right after the response, before '
        'the accepted marker, and again before the clear (spec D7/D8)',
        () async {
      final store = _FakePlanningMutationStore(
        pending: [
          PlanningMutationRecord(
            aggregateId: 'item-1',
            organizationId: 'org-1',
            planId: 'plan-1',
            sessionId: 'session-1',
            songId: 'song-1',
            songTitle: 'Song',
            position: 1,
            baseVersion: 3,
            kind: PlanningMutationKind.sessionItemCreateSong,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => _FakePlanningMutationRemoteRepository(),
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      await controller.syncPendingMutations(
        const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );

      expect(store.events, [
        'save:sending:item-1',
        'effects:item-1:true',
        'save:accepted:item-1',
        'effects:item-1:true',
      ]);
    });

    test('a crash-resumed accepted marker gets effects with remoteResponse '
        'false only', () async {
      final store = _FakePlanningMutationStore(
        pending: [
          PlanningMutationRecord(
            aggregateId: 'plan-1',
            organizationId: 'org-1',
            baseVersion: 2,
            baseContentVersion: 5,
            kind: PlanningMutationKind.planDelete,
            syncStatus: PlanningMutationSyncStatus.accepted,
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => _FakePlanningMutationRemoteRepository(),
        refreshPlanning: () async => false,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      await controller.syncPendingMutations(
        const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );

      expect(store.events, ['effects:plan-1:false']);
    });
```

If the fake's `readAllMutations` does not return the `pending:` list
unfiltered, adjust only the fake. Do not change the assertions.

In `planning_in_flight_create_cancellation_test.dart`, inside the existing
group and using its `_GatedPlanningRemote`:

```dart
    test('plan: deleting a plan while its create is in flight survives as a '
        'pending plan delete once the create succeeds (spec D5b)', () async {
      final db = PlanningLocalDatabase.inMemory();
      addTearDown(db.close);
      final localStore = DriftPlanningLocalStore(db);
      final store = DriftPlanningMutationStore(
        database: db,
        localStore: localStore,
      );
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      const readContext = ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'plan-one',
          name: 'Plan One',
        ),
      );

      final remote = _GatedPlanningRemote();
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => remote,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final syncFuture = controller.syncPendingMutations(readContext);
      await remote.entered.future;
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(planId: 'plan-1'),
      );
      remote.gate.complete();
      await syncFuture;

      final afterSync = await store.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );
      expect(afterSync, isNotNull);
      expect(afterSync!.kind, PlanningMutationKind.planDelete);
      expect(afterSync.syncStatus, PlanningMutationSyncStatus.pending);
      expect(afterSync.baseVersion, 1);
      expect(afterSync.baseContentVersion, 1);

      await controller.syncPendingMutations(readContext);
      expect(
        remote.calls.where(
          (record) => record.kind == PlanningMutationKind.planDelete,
        ),
        hasLength(1),
      );
    });

    test('plan: a failed in-flight plan create discards the tombstone and '
        'every child row, including a crash-stale sending one (spec D5b)',
        () async {
      final db = PlanningLocalDatabase.inMemory();
      addTearDown(db.close);
      final localStore = DriftPlanningLocalStore(db);
      final store = DriftPlanningMutationStore(
        database: db,
        localStore: localStore,
      );
      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );
      const readContext = ActivePlanningReadContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-1',
          slug: 'plan-one',
          name: 'Plan One',
        ),
      );
      await store.recordSessionCreate(
        context: context,
        draft: const PlanningSessionCreateMutationDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
          slug: 'session-one',
          name: 'Session One',
          position: 1,
        ),
      );

      final remote = _GatedPlanningRemote(
        failFirstWith: const PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.dependencyBlocked,
        ),
      );
      final controller = PlanningMutationSyncController(
        mutationStore: () => store,
        remoteRepository: () => remote,
        refreshPlanning: () async => true,
        shouldReconcileAcceptedMutation: (_) async => true,
        reconcileAcceptedMutation: (_, _) async {},
      );

      final syncFuture = controller.syncPendingMutations(readContext);
      await remote.entered.future;
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session',
        aggregateId: 'session-1',
        syncStatus: PlanningMutationSyncStatus.sending,
      );
      await store.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(planId: 'plan-1'),
      );
      remote.gate.complete();
      await syncFuture;

      expect(
        await store.readAllMutations(userId: 'user-1', organizationId: 'org-1'),
        isEmpty,
      );
      expect(
        remote.calls.map((record) => record.kind),
        [PlanningMutationKind.planCreate],
        reason: 'the vanished child row must not be sent afterwards',
      );
    });
```

- [ ] **Step 2: Run them and watch them fail.** Expected: `events` has no
  `effects:` entries, and the `planCreate` tombstone is never resolved (the
  create is not cancellable yet).

- [ ] **Step 3: Implement.**

Controller:
- `isCancellableCreate`: add `mutation.kind == PlanningMutationKind.planCreate ||`.
- Add the helper:

```dart
  /// Spec D7/D8: best-effort by design. Failing to rebase leaves a base
  /// stale (fail-safe: a visible conflict); a failed purge re-runs at batch
  /// conclusion. An Exception here must never skip the accepted marker
  /// (ADR-019 exactly-once); an Error still propagates.
  Future<void> _applyAcceptedEffects(
    ActivePlanningReadContext context,
    PlanningMutationRecord accepted, {
    required bool remoteResponse,
  }) async {
    try {
      await _mutationStore().applyAcceptedWriteEffects(
        userId: context.userId,
        organizationId: context.organizationId,
        accepted: accepted,
        remoteResponse: remoteResponse,
      );
    } on Exception {
      // Intentionally swallowed -- see the doc comment.
    }
  }
```

- Call it immediately after `syncMutation` returns, before the
  `saveSyncAttemptResult(accepted)` call:

```dart
        // Spec D7/D8: before the accepted marker, and regardless of its
        // revision gate -- a delete may have overwritten this very row
        // while it was in flight, and that delete is what gets rebased.
        await _applyAcceptedEffects(
          context,
          syncedMutation,
          remoteResponse: true,
        );
```

- Extend the `acceptedRecords` tuple with an explicit flag:
  `(PlanningMutationRecord original, PlanningMutationRecord synced, int clearRevision, bool remoteResponse)`.
  - Crash-resumed marker: `acceptedRecords.add((mutation, mutation, mutation.localRevision, false));`
  - Sent this run: `acceptedRecords.add((mutation, syncedMutation, newRevision, true));`
  - Do not infer the flag from object identity. A remote fake that echoes
    the same instance would silently flip it.
- In both post-batch loops, destructure the flag and call the helper first:

```dart
    if (refreshed) {
      for (final (original, synced, clearRevision, remoteResponse)
          in acceptedRecords) {
        await _applyAcceptedEffects(
          context,
          synced,
          remoteResponse: remoteResponse,
        );
        await _mutationStore().clearMutation(/* unchanged */);
      }
    } else {
      for (final (original, synced, clearRevision, remoteResponse)
          in acceptedRecords) {
        await _applyAcceptedEffects(
          context,
          synced,
          remoteResponse: remoteResponse,
        );
        try {
          /* unchanged reconcile block */
        } on ReconcileFieldError catch (error) { /* unchanged */ }
        await _mutationStore().clearMutation(/* unchanged */);
      }
    }
```

  Calling the helper before each record's reconcile is what applies D7 rule
  1a in `acceptedRecords` order. A `planCreate` reconciled at content
  version 1, followed by its accepted child, reaches 2 even when the refresh
  failed. The reconciler itself needs no rule-1a code.

`resolveCancelledCreate` in `DriftPlanningMutationStore`:
- In the `!created` branch, after deleting the tombstone row:

```dart
        // Spec D5(b): a plan whose create never reached the backend has no
        // children there either; drop every child row left behind.
        if (existing.kind == PlanningMutationKind.planCreate) {
          await _deleteChildMutationsOfPlan(
            context: PlanningMutationContext(
              userId: userId,
              organizationId: organizationId,
            ),
            planId: aggregateId,
            keepInFlight: false,
          );
        }
```

- `deleteKind`: add `PlanningMutationKind.planCreate => PlanningMutationKind.planDelete,`.
- In the conversion `copyWith`, add:

```dart
          // Spec D5(b): a plan's content version starts at 1, and no child
          // of it can have reached the backend before this create's own
          // response (sync is sequential; children sort after the create).
          baseContentVersion: existing.kind == PlanningMutationKind.planCreate
              ? 1
              : existing.baseContentVersion,
```

- Update the `StateError` message and the interface doc comment to list
  `planCreate` among the tombstone kinds.

- [ ] **Step 4: Run the tests, then full verification.** Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): wire accepted-write effects into sync, cancel in-flight plan creates

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3.6: Overlay hides deleted plans

**Files:**
- Modify: `planning_local_read_repository.dart`
- Test: `test/application/planning/planning_local_read_repository_test.dart`

- [ ] **Step 1: Write the failing tests** (the file's real-store `setUp`):

```dart
    test('a pending plan delete hides the plan from list, detail and slug '
        'reads (spec D10)', () async {
      await mutationStore.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );

      expect(await repository.listPlans(), isEmpty);
      expect(await repository.getPlanSummaryBySlug('team-rehearsal'), isNull);
      expect(await repository.getPlanDetailBySlug('team-rehearsal'), isNull);
      await expectLater(repository.getPlanDetail('plan-1'), throwsStateError);
    });

    test('a conflicted plan delete keeps hiding the plan (spec D9, D10)',
        () async {
      await mutationStore.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );
      await mutationStore.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
        syncStatus: PlanningMutationSyncStatus.conflict,
        errorCode: PlanningMutationSyncErrorCode.conflict,
      );

      expect(await repository.listPlans(), isEmpty);
    });

    test('discarding the delete brings the plan back', () async {
      await mutationStore.recordPlanDelete(
        context: context,
        draft: const PlanningPlanDeleteMutationDraft(
          planId: 'plan-1',
          baseVersion: 2,
          baseContentVersion: 5,
        ),
      );
      await mutationStore.clearMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      );

      final detail = await repository.getPlanDetail('plan-1');
      expect(detail.sessions, hasLength(2));
    });
```

- [ ] **Step 2: Run them and watch them fail** (the plan is still listed).

- [ ] **Step 3: Implement.**

`_mergePlanSummaries`: change the `planDelete` case (added to the `break` group
in Task 3.1) to its own case:

```dart
        case PlanningMutationKind.planDelete:
          // Spec D10: any actionable delete intent hides the plan.
          plansById.remove(mutation.aggregateId);
```

`_mergePlanDetail`: first statement of the method:

```dart
    // Spec D10: a plan with an actionable delete intent is gone for every
    // read, including its children.
    if (mutations.any(
      (mutation) =>
          mutation.kind == PlanningMutationKind.planDelete &&
          mutation.aggregateId == planId,
    )) {
      return null;
    }
```

`_resolvePlanIdBySlug`: compute the id as today, then:

```dart
    if (resolved != null &&
        mutations.any(
          (mutation) =>
              mutation.kind == PlanningMutationKind.planDelete &&
              mutation.aggregateId == resolved,
        )) {
      return null;
    }
    return resolved;
```

This requires restructuring the two `return` statements into a local
`resolved` variable.

- [ ] **Step 4: Run the tests, then full verification.** Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): hide plans with a pending delete from merged reads

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3.7: Retry rebases both bases of a plan delete

**Files:**
- Modify: `drift_planning_mutation_store.dart` (`retryMutation`)
- Test: `test/offline/planning/planning_mutation_store_test.dart`

- [ ] **Step 1: Write the failing test.** Add it to the
  `recordPlanDelete (spec D5)` group from Task 3.2, which provides the
  `store`, `localStore`, and `context` fixtures.

```dart
  test('retrying a conflicted plan delete rebases version and content '
      'version from the projection (spec D9)', () async {
    await localStore.replaceActiveProjection(
      userId: 'user-1',
      organizationId: 'org-1',
      plans: [
        CachedPlanRecord(
          id: 'plan-1',
          slug: 'plan-1',
          name: 'Plan',
          description: null,
          scheduledFor: null,
          updatedAt: DateTime.utc(2026),
          version: 2,
          contentVersion: 5,
        ),
      ],
      sessions: const [],
      items: const [],
      refreshedAt: DateTime.utc(2026),
    );
    await store.recordPlanDelete(
      context: context,
      draft: const PlanningPlanDeleteMutationDraft(
        planId: 'plan-1',
        baseVersion: 2,
        baseContentVersion: 5,
      ),
    );
    await store.saveSyncAttemptResult(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'plan',
      aggregateId: 'plan-1',
      syncStatus: PlanningMutationSyncStatus.conflict,
      errorCode: PlanningMutationSyncErrorCode.conflict,
    );
    // A later refresh saw someone else's changes.
    await localStore.replaceActiveProjection(
      userId: 'user-1',
      organizationId: 'org-1',
      plans: [
        CachedPlanRecord(
          id: 'plan-1',
          slug: 'plan-1',
          name: 'Plan',
          description: null,
          scheduledFor: null,
          updatedAt: DateTime.utc(2026, 1, 2),
          version: 3,
          contentVersion: 8,
        ),
      ],
      sessions: const [],
      items: const [],
      refreshedAt: DateTime.utc(2026, 1, 2),
    );

    await store.retryMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'plan',
      aggregateId: 'plan-1',
    );

    final retried = (await store.readMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'plan',
      aggregateId: 'plan-1',
    ))!;
    expect(retried.syncStatus, PlanningMutationSyncStatus.pending);
    expect(retried.baseVersion, 3);
    expect(retried.baseContentVersion, 8);
  });
```

- [ ] **Step 2: Run it and watch it fail** (`baseContentVersion` stays 5).

- [ ] **Step 3: Implement.** In `retryMutation`, after `rebasedBaseVersion`:

```dart
    // Spec D9: retrying a plan delete is the explicit remove -- it targets
    // the plan as the projection now shows it, content version included.
    final rebasedBaseContentVersion =
        existing.kind == PlanningMutationKind.planDelete
        ? (await _localStore.readPlanDetail(
            userId: userId,
            organizationId: organizationId,
            planId: existing.aggregateId,
          ))?.plan.contentVersion
        : null;
```

Then add `baseContentVersion: rebasedBaseContentVersion ?? existing.baseContentVersion,`
to the `copyWith`.

- [ ] **Step 4: Run the test, then full verification.** Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): retry of a plan delete rebases content version

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3.8: Write service — `deletePlan`, cascade `deleteSession`

**Files:**
- Modify: `planning_write_service.dart`
- Test: `test/application/planning/planning_write_service_test.dart`

- [ ] **Step 1: Write the failing tests.** Build the service over real stores,
  the same wiring as the `setUp` in
  `planning_local_read_repository_test.dart`:

```dart
PlanningWriteService(
  PlanningLocalReadRepository(
    store: localStore,
    mutationStore: mutationStore,
    contextReader: ...,
  ),
  mutationStore: mutationStore,
  activeContextReader: () async => const ActivePlanningReadContext(
    userId: 'user-1',
    organizationId: 'org-1',
  ),
)
```

Seed the projection with plan-1 (`version: 2, contentVersion: 5`), sessions
`session-1` (one item, song-1) and `session-2` (empty).

```dart
    test('deletePlan records a delete based on the projection versions and '
        'hides the plan (spec D5)', () async {
      await service.deletePlan(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: const PlanDeleteDraft(planId: 'plan-1'),
      );

      final delete = (await mutationStore.readMutation(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'plan',
        aggregateId: 'plan-1',
      ))!;
      expect(delete.kind, PlanningMutationKind.planDelete);
      expect(delete.baseVersion, 2);
      expect(delete.baseContentVersion, 5);
      expect(delete.originSnapshot?['name'], 'Plan');
      expect(await repository.listPlans(), isEmpty);
    });

    test('a song stays delete-blocked until the plan delete is reconciled '
        '(spec I1)', () async {
      await service.deletePlan(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: const PlanDeleteDraft(planId: 'plan-1'),
      );
      expect(
        await localStore.countSongReferences(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        ),
        1,
      );

      await localStore.deleteSyncedPlan(
        userId: 'user-1',
        organizationId: 'org-1',
        planId: 'plan-1',
        refreshedAt: DateTime.utc(2026, 9, 30),
      );
      expect(
        await localStore.countSongReferences(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        ),
        0,
      );
    });

    test('deleteSession accepts a non-empty session (spec D6)', () async {
      await service.deleteSession(
        context: const PlanningWriteContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
        draft: const SessionDeleteDraft(
          sessionId: 'session-1',
          planId: 'plan-1',
        ),
      );

      final detail = await repository.getPlanDetail('plan-1');
      expect(detail.sessions.map((session) => session.id), ['session-2']);
    });
```

If the file has an existing test expecting `SessionDeleteBlockedException`,
replace it with the last test above. It asserts the D6 rule that replaces it.

- [ ] **Step 2: Run them and watch them fail** (compile error on
  `deletePlan`/`PlanDeleteDraft`).

- [ ] **Step 3: Implement.**

```dart
class PlanDeleteDraft {
  const PlanDeleteDraft({required this.planId});

  final String planId;
}
```

```dart
  Future<void> deletePlan({
    required PlanningWriteContext context,
    required PlanDeleteDraft draft,
  }) async {
    await _requireMatchingContext(context);
    final detail = await _repository.getPlanDetail(draft.planId);
    await _mutationStore.recordPlanDelete(
      context: PlanningMutationContext(
        userId: context.userId,
        organizationId: context.organizationId,
      ),
      draft: PlanningPlanDeleteMutationDraft(
        planId: draft.planId,
        baseVersion: detail.plan.version,
        baseContentVersion: detail.plan.contentVersion,
        originSnapshot: _planSnapshot(detail.plan),
      ),
    );
    await _scheduleSync(context);
  }
```

In `deleteSession`, delete the `if (session.items.isNotEmpty) throw ...;`
block and the `SessionDeleteBlockedException` class. Its only other
reference, `AppStrings.sessionDeleteBlockedMessage`, is removed in Task 4.2.

- [ ] **Step 4: Run the tests, then full verification.** Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): write service plan delete and cascading session delete

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3.9: Adversarial end-to-end scenarios

**Files:**
- Create: `apps/lyron_app/test/offline/adversarial/planning_cascade_delete_test.dart`

Real `DriftPlanningLocalStore`, `DriftPlanningMutationStore`,
`PlanningMutationReconciler`, and `PlanningMutationSyncController`, plus a
scripted remote. The post-write refresh always "fails" (`refreshPlanning`
returns false), so the reconciler path is exercised.

- [ ] **Step 1: Write the tests.**

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

/// Adversarial coverage for
/// docs/specs/2026-09-29-plan-delete-and-session-cascade.md (D5-D10, I2/I3):
/// the real storage boundary and sync controller against a scripted backend.
void main() {
  const context = PlanningMutationContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );
  const readContext = ActivePlanningReadContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );

  late PlanningLocalDatabase db;
  late DriftPlanningLocalStore localStore;
  late DriftPlanningMutationStore store;
  late PlanningLocalReadRepository reads;

  setUp(() async {
    db = PlanningLocalDatabase.inMemory();
    localStore = DriftPlanningLocalStore(db);
    store = DriftPlanningMutationStore(database: db, localStore: localStore);
    reads = PlanningLocalReadRepository(
      store: localStore,
      mutationStore: store,
      contextReader: () async => readContext,
    );
    await seedProjection(localStore, contentVersion: 3);
  });

  tearDown(() async {
    await db.close();
  });

  PlanningMutationSyncController controllerFor(
    PlanningMutationRemoteRepository remote,
  ) {
    final reconciler = PlanningMutationReconciler(localStore: () => localStore);
    return PlanningMutationSyncController(
      mutationStore: () => store,
      remoteRepository: () => remote,
      refreshPlanning: () async => false,
      shouldReconcileAcceptedMutation: (_) async => true,
      reconcileAcceptedMutation: (ctx, record) =>
          reconciler.reconcile(ctx, record),
    );
  }

  Future<PlanningMutationRecord?> planRow() => store.readMutation(
    userId: 'user-1',
    organizationId: 'org-1',
    aggregateType: 'plan',
    aggregateId: 'plan-1',
  );

  Future<List<PlanningMutationRecord>> allRows() =>
      store.readAllMutations(userId: 'user-1', organizationId: 'org-1');

  Future<void> recordNewSession() => store.recordSessionCreate(
    context: context,
    draft: const PlanningSessionCreateMutationDraft(
      sessionId: 's-new',
      planId: 'plan-1',
      slug: 's-new',
      name: 'New',
      position: 2,
    ),
  );

  test('an own in-flight child write does not make the plan delete conflict '
      'with itself (acceptance 4)', () async {
    await recordNewSession();
    final entered = Completer<void>();
    final release = Completer<void>();
    final remote = _ScriptedPlanningRemote((record) async {
      switch (record.kind) {
        case PlanningMutationKind.sessionCreate:
          entered.complete();
          await release.future;
          return record.copyWith(baseVersion: 1, acceptedPlanContentVersion: 4);
        case PlanningMutationKind.planDelete:
          // Backend truth: version 2, content version 3 + own create = 4.
          if (record.baseVersion != 2 || record.baseContentVersion != 4) {
            throw const PlanningMutationSyncException(
              PlanningMutationSyncErrorCode.conflict,
            );
          }
          return record.copyWith(baseVersion: 2);
        default:
          throw StateError('unexpected ${record.kind}');
      }
    });
    final controller = controllerFor(remote);

    final firstRun = controller.syncPendingMutations(readContext);
    await entered.future;
    await store.recordPlanDelete(
      context: context,
      draft: const PlanningPlanDeleteMutationDraft(
        planId: 'plan-1',
        baseVersion: 2,
        baseContentVersion: 3,
      ),
    );
    release.complete();
    await firstRun;

    expect((await planRow())!.baseContentVersion, 4);

    await controller.syncPendingMutations(readContext);

    expect(remote.calls.map((record) => record.kind), [
      PlanningMutationKind.sessionCreate,
      PlanningMutationKind.planDelete,
    ]);
    expect(await allRows(), isEmpty);
    expect(
      await localStore.readPlanDetail(
        userId: 'user-1',
        organizationId: 'org-1',
        planId: 'plan-1',
      ),
      isNull,
    );
  });

  test('a foreign write between view and delete is a visible conflict; retry '
      'after a refresh deletes (acceptance 3)', () async {
    await recordNewSession();
    final entered = Completer<void>();
    final release = Completer<void>();
    final remote = _ScriptedPlanningRemote((record) async {
      switch (record.kind) {
        case PlanningMutationKind.sessionCreate:
          entered.complete();
          await release.future;
          // One foreign write landed before ours: 3 + 1 + 1.
          return record.copyWith(baseVersion: 1, acceptedPlanContentVersion: 5);
        case PlanningMutationKind.planDelete:
          if (record.baseContentVersion != 5) {
            throw const PlanningMutationSyncException(
              PlanningMutationSyncErrorCode.conflict,
            );
          }
          return record.copyWith(baseVersion: 2);
        default:
          throw StateError('unexpected ${record.kind}');
      }
    });
    final controller = controllerFor(remote);

    final firstRun = controller.syncPendingMutations(readContext);
    await entered.future;
    await store.recordPlanDelete(
      context: context,
      draft: const PlanningPlanDeleteMutationDraft(
        planId: 'plan-1',
        baseVersion: 2,
        baseContentVersion: 3,
      ),
    );
    release.complete();
    await firstRun;
    expect((await planRow())!.baseContentVersion, 3, reason: 'gap: no rebase');

    await controller.syncPendingMutations(readContext);
    expect((await planRow())!.syncStatus, PlanningMutationSyncStatus.conflict);
    expect(await reads.listPlans(), isEmpty, reason: 'still hidden (D10)');

    // A later refresh shows the plan as it now is.
    await seedProjection(localStore, contentVersion: 5);
    await controller.retryMutation(
      readContext,
      aggregateType: 'plan',
      aggregateId: 'plan-1',
    );

    expect(remote.calls.last.kind, PlanningMutationKind.planDelete);
    expect(remote.calls.last.baseContentVersion, 5);
    expect(await allRows(), isEmpty);
  });

  test('a crash-resumed accepted child never rebases a pending session '
      'delete (spec D7)', () async {
    await store.recordSessionItemCreateSong(
      context: context,
      draft: const PlanningSessionItemCreateSongMutationDraft(
        sessionItemId: 'item-9',
        sessionId: 'session-1',
        planId: 'plan-1',
        songId: 'song-9',
        songTitle: 'Song',
        position: 2,
        baseVersion: 2,
      ),
    );
    await store.saveSyncAttemptResult(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session_item',
      aggregateId: 'item-9',
      syncStatus: PlanningMutationSyncStatus.accepted,
    );
    await store.recordSessionDelete(
      context: context,
      draft: const PlanningSessionDeleteMutationDraft(
        sessionId: 'session-1',
        planId: 'plan-1',
        baseVersion: 1,
      ),
    );
    final remote = _ScriptedPlanningRemote((record) async {
      throw const PlanningMutationSyncException(
        PlanningMutationSyncErrorCode.connectivityFailure,
      );
    });

    await controllerFor(remote).syncPendingMutations(readContext);

    final sessionDelete = (await store.readMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session',
      aggregateId: 'session-1',
    ))!;
    expect(
      sessionDelete.baseVersion,
      1,
      reason:
          'the resumed marker carries its pre-write base (2); treating it as '
          'a response would have moved 1 -> 2',
    );
  });
}

Future<void> seedProjection(
  DriftPlanningLocalStore localStore, {
  required int contentVersion,
}) => localStore.replaceActiveProjection(
  userId: 'user-1',
  organizationId: 'org-1',
  plans: [
    CachedPlanRecord(
      id: 'plan-1',
      slug: 'plan-1',
      name: 'Plan',
      description: null,
      scheduledFor: null,
      updatedAt: DateTime.utc(2026),
      version: 2,
      contentVersion: contentVersion,
    ),
  ],
  sessions: const [
    CachedSessionRecord(
      id: 'session-1',
      planId: 'plan-1',
      position: 1,
      name: 'S',
      version: 2,
    ),
  ],
  items: const [
    CachedSessionItemRecord(
      id: 'item-1',
      planId: 'plan-1',
      sessionId: 'session-1',
      position: 1,
      songId: 'song-1',
      songTitle: 'Song',
    ),
  ],
  refreshedAt: DateTime.utc(2026),
);

class _ScriptedPlanningRemote implements PlanningMutationRemoteRepository {
  _ScriptedPlanningRemote(this._respond);

  final Future<PlanningMutationRecord> Function(PlanningMutationRecord record)
  _respond;
  final List<PlanningMutationRecord> calls = [];

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) {
    calls.add(record);
    return _respond(record);
  }
}
```

Check the `PlanningMutationReconciler` constructor against
`planning_mutation_reconciler.dart` (named `localStore:` taking a
`PlanningLocalStore Function()`) and adjust the construction if it differs.
Do not change the assertions.

- [ ] **Step 2: Run them.** Expected: PASS, since Tasks 3.2–3.8 implement the
  behavior. If one fails, investigate; do not relax the test.

- [ ] **Step 3: Full verification, then commit.**

```bash
git add apps/lyron_app/test
git commit -m "test(planning): adversarial cascade delete scenarios

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Review gate 3

> "Enumerate every sequence (online, offline, crash-resume, in-flight
> create/edit/child write, retry, discard) in which the client sends a
> `delete_plan` or `delete_session` whose base absorbed a write the deleting
> client never had in its projection or overlay. Also find any sequence that
> leaves a mutation row stranded (never sent, never visible) or a child row
> of a deleted plan alive after acceptance."

**Gate 3 outcome (2026-09-30).** Phase 3 landed as 1656755..333818d (Tasks
3.1–3.9). The reviewer disproved the claim, proving each finding with a
throwaway test. Fixed in 2bbfc82, d3b0b78, e02c16f, f83e6fe, and fbc343c.
A re-verification by the same reviewer confirmed the fixes and found no new
path. The spec's D5, D8, D9, and C7 now state the resulting rules.

- **F1 (critical): a retry silently absorbed foreign writes.**
  `retryMutation` rebased a `planDelete` onto the projection in any status.
  A connectivity-failed delete retried after a refresh therefore deleted
  content the user never saw, because the plan stays hidden (D10). A group
  keep-mine did the same: retrying an earlier row ran a sync, the pending
  delete conflicted inside it, and the loop then retried that unseen
  conflict.
  - Fix: a cascade delete rebases only when its status is `conflict`.
  - Group retries carry the status the popup showed
    (`UnifiedSyncPlanMutationRef.syncStatus` → `retryMutation(expectedStatus:)`)
    and skip a row whose status has changed since.
- **F2 (major): a create tombstone stranded by an interrupted run.** The
  in-slice part is fixed: a delete over a stranded plan-create tombstone,
  once the plan is back in the projection, records a real delete from the
  projection bases. Before, it was a permanent no-op.
  - Retry now never touches `sending`, `accepted`, or `cancelling` rows
    (re-verification N4). Retrying a tombstone would have re-created the
    deleted plan.
  - The general family is still open and needs the user's decision:
    tombstones never resolved after an interrupted run, pre-existing for
    sessions and items. See
    `docs/deferred/2026-09-30-stranded-create-tombstones.md`. The
    reviewer's run-start conversion with base `(1, 1)` would break STOP
    condition 5.
- **F3 (major): a conflicted `sessionDelete` never rebased on retry.**
  `_currentBaseVersionFor` keyed on `sessionId`, which session rows do not
  set.
  - Fixed for `sessionDelete`, conflict-only, with popup copy that says the
    session changed.
  - The same bug for `sessionRename` predates the slice and is deferred:
    `docs/deferred/2026-09-30-session-rename-retry-never-rebases.md`.
- **F4 (minor): branch (c) assumed a content version of 1.**
  `recordPlanCreate` now stamps 1, and branch (c) inherits the create row's
  value. A pre-schema-7 row fails safe as a conflict.
- **F5 (minor): a failed purge left child rows behind.** When the purge at
  batch end fails, the delete stays `accepted` and the next run purges again
  before clearing it.
- **F6 (minor): a repeated delete reset an in-flight delete.** A delete
  over an in-flight `planDelete` is now a no-op.

Accepted:
- A retry skipped because the row's status changed is silent. No snackbar
  is shown, and the row stays visible in its new state.
- A session delete repeated over an in-flight session delete still
  overwrites it, as it did before this slice. The UI hides the session, so
  only a race reaches it.

For Task 4.3: ADR-038 and `docs/architecture/state-machines.md` must state
the conflict-only rebase, the shown-status retry guard, and the rule that
in-flight rows are never retried.

Full suite after the fixes: +1870 ~18.

---

## Phase 4 — UI and documentation

### Task 4.1: Plan delete in the plan detail header

**Files:**
- Modify:
  - `lib/src/shared/app_strings.dart`
  - `lib/src/presentation/planning/plan_detail_screen.dart`
- Test: `test/presentation/planning/plan_detail_screen_test.dart`

- [ ] **Step 1: Write the failing widget tests.** Add a plan-list route to
  `buildApp`'s `GoRouter` (it has only detail and reader routes):

```dart
        GoRoute(
          path: AppRoutes.planList.path,
          builder: (context, state) => const Text('plan-list-placeholder'),
        ),
```

In `_FakePlanningWriteService`, add
`PlanDeleteDraft? deletedPlanDraft;` and:

```dart
  @override
  Future<void> deletePlan({
    required PlanningWriteContext context,
    required PlanDeleteDraft draft,
  }) async {
    deletedPlanDraft = draft;
  }
```

Tests (`_editablePlanDetailFixture()` has 2 sessions; `Warm-Up` holds 1 item):

```dart
  testWidgets('plan delete lives in the overflow menu and needs both '
      'managePlans and editSessions (spec D11)', (tester) async {
    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        capabilityResolver: CapabilityResolver(
          gateway: _PlanDetailStaticCapabilityGateway({
            Capability.managePlans,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('plan-overflow-menu-button')), findsNothing);

    await tester.pumpWidget(
      buildApp(planDetailValue: _editablePlanDetailFixture()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-overflow-menu-button')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.planDeleteAction), findsOneWidget);
  });

  testWidgets('deletes the plan after confirmation and returns to the plan '
      'list', (tester) async {
    final writeService = _FakePlanningWriteService();
    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('plan-overflow-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.planDeleteAction));
    await tester.pumpAndSettle();

    expect(
      find.text(
        AppStrings.planDeleteConfirmMessage(
          planName: 'Team Rehearsal',
          sessionCount: 2,
          songCount: 1,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.text(AppStrings.planningUnsyncedChangesDiscardedMessage),
      findsNothing,
    );

    await tester.tap(find.text(AppStrings.planDeleteConfirmAction));
    await tester.pumpAndSettle();

    expect(writeService.deletedPlanDraft?.planId, 'plan-1');
    expect(find.text('plan-list-placeholder'), findsOneWidget);
  });

  testWidgets('the plan delete dialog warns about unsynced plan changes',
      (tester) async {
    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        loadMutationEntries: () async => [
          PlanningMutationRecord(
            aggregateId: 'item-9',
            organizationId: 'org-1',
            planId: 'plan-1',
            sessionId: 'session-1',
            kind: PlanningMutationKind.sessionItemCreateSong,
            syncStatus: PlanningMutationSyncStatus.pending,
            orderKey: 1,
            updatedAt: DateTime.utc(2026),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-overflow-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.planDeleteAction));
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.planningUnsyncedChangesDiscardedMessage),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the plan delete dialog does not delete',
      (tester) async {
    final writeService = _FakePlanningWriteService();
    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-overflow-menu-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.planDeleteAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();

    expect(writeService.deletedPlanDraft, isNull);
  });
```

Check `_editablePlanDetailFixture()`'s real counts first. If they differ,
adjust `sessionCount`/`songCount` in the expectation to the fixture; do not
change the fixture.

- [ ] **Step 2: Run them and watch them fail** (compile errors on the new
  strings).

- [ ] **Step 3: Implement.**

`app_strings.dart`, next to `planEditAction`:

```dart
  static const planMoreActions = 'More plan actions';
  static const planDeleteAction = 'Delete plan';
  static const planDeleteConfirmTitle = 'Delete plan?';
  static const planDeleteConfirmAction = 'Delete';
  static String planDeleteConfirmMessage({
    required String planName,
    required int sessionCount,
    required int songCount,
  }) =>
      '“$planName” and its ${_count(sessionCount, 'session', 'sessions')} '
      '(${_count(songCount, 'song', 'songs')}) will be deleted. '
      'The songs stay in the song library.';
  static const planningUnsyncedChangesDiscardedMessage =
      'Unsynced changes to this plan will be discarded.';

  static String _count(int count, String one, String other) =>
      count == 1 ? '$count $one' : '$count $other';
```

`plan_detail_screen.dart`:
- Add a top-level `enum _PlanDetailMenuAction { delete }`.
- Append to `actions:`:

```dart
        IfCapability(
          key: const Key('plan-delete-capability'),
          capability: Capability.managePlans,
          organizationId: orgId,
          child: IfCapability(
            capability: Capability.editSessions,
            organizationId: orgId,
            child: PopupMenuButton<_PlanDetailMenuAction>(
              key: const Key('plan-overflow-menu-button'),
              tooltip: AppStrings.planMoreActions,
              icon: const Icon(Icons.more_vert),
              onSelected: (action) {
                switch (action) {
                  case _PlanDetailMenuAction.delete:
                    unawaited(_deletePlan(context, ref));
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _PlanDetailMenuAction.delete,
                  child: Text(AppStrings.planDeleteAction),
                ),
              ],
            ),
          ),
        ),
```

- Add the method:

```dart
  Future<void> _deletePlan(BuildContext context, WidgetRef ref) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }
    final detail = await ref.read(planningPlanDetailProvider(planId).future);
    final entries = await ref.read(planningMutationEntriesProvider.future);
    if (!context.mounted) {
      return;
    }

    final songCount = detail.sessions.fold<int>(
      0,
      (sum, session) => sum + session.items.length,
    );
    // Spec D5/D11: the rows the delete will drop -- this plan's child rows
    // and plan row that are not already on their way to the backend.
    final hasDiscardableChanges = entries.any(
      (entry) =>
          (entry.planId == planId ||
              (entry.kind.aggregateType == 'plan' &&
                  entry.aggregateId == planId)) &&
          entry.syncStatus != PlanningMutationSyncStatus.sending &&
          entry.syncStatus != PlanningMutationSyncStatus.cancelling &&
          entry.syncStatus != PlanningMutationSyncStatus.accepted,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.planDeleteConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.planDeleteConfirmMessage(
                planName: detail.plan.name,
                sessionCount: detail.sessions.length,
                songCount: songCount,
              ),
            ),
            if (hasDiscardableChanges) ...[
              const SizedBox(height: 12),
              const Text(AppStrings.planningUnsyncedChangesDiscardedMessage),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.songCancelAction),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.planDeleteConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    final currentContext = ref.read(activePlanningContextProvider);
    if (currentContext == null ||
        !samePlanningContext(activeContext, currentContext)) {
      return;
    }
    if (!context.mounted) return;
    await ref
        .read(planningWriteServiceProvider)
        .deletePlan(
          context: PlanningWriteContext(
            userId: currentContext.userId,
            organizationId: currentContext.organizationId,
          ),
          draft: PlanDeleteDraft(planId: planId),
        );

    if (!context.mounted) return;
    // Plan-set change (ARCH-2): aggregate signal, like plan create/edit.
    // Navigate in the same frame so this screen never rebuilds against the
    // now-hidden plan.
    ref.read(planningDataRevisionProvider.notifier).state += 1;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    context.go(PlanningRoutes.planListPath);
  }
```

- Add the import
  `package:lyron_app/src/application/planning/planning_mutation_sync_types.dart`
  if `PlanningMutationSyncStatus` is not already visible.

- [ ] **Step 4: Run the tests, then full verification.** Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): delete plan from the plan detail header

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4.2: Cascading session delete in the session card

**Files:**
- Modify:
  - `lib/src/shared/app_strings.dart`
  - `lib/src/presentation/planning/widgets/plan_session_card.dart`
- Test: `test/presentation/planning/plan_detail_screen_test.dart`

- [ ] **Step 1: Update and add the widget tests.**

Replace `'shows delete action only for empty sessions'` with:

```dart
  testWidgets('shows the delete action for every session (spec D6)', (
    tester,
  ) async {
    // Same pumpWidget body as the replaced test.
    // ...
    expect(
      find.byTooltip('${AppStrings.sessionDeleteAction}: Closing'),
      findsOneWidget,
    );
    expect(
      find.byTooltip('${AppStrings.sessionDeleteAction}: Warm-Up'),
      findsOneWidget,
    );
  });
```

Add:

```dart
  testWidgets('deletes a non-empty session after a confirmation naming its '
      'songs', (tester) async {
    final writeService = _FakePlanningWriteService();
    await tester.pumpWidget(
      buildApp(
        planDetailValue: _editablePlanDetailFixture(),
        writeService: writeService,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byTooltip('${AppStrings.sessionDeleteAction}: Warm-Up'),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        AppStrings.sessionDeleteConfirmMessage(
          sessionName: 'Warm-Up',
          songCount: 1,
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text(AppStrings.sessionDeleteConfirmAction));
    await tester.pumpAndSettle();

    expect(writeService.deletedSessionDraft?.sessionId, 'session-1');
  });
```

In `'deletes an empty session locally after confirmation'`, assert the empty
copy before confirming:
`expect(find.text(AppStrings.sessionDeleteEmptyConfirmMessage), findsOneWidget);`.

- [ ] **Step 2: Run them and watch them fail.**

- [ ] **Step 3: Implement.**

`app_strings.dart`:
- `sessionDeleteConfirmTitle = 'Delete session?'`
- replace the `sessionDeleteConfirmMessage` constant with:

```dart
  static const sessionDeleteEmptyConfirmMessage = 'This removes the session.';
  static String sessionDeleteConfirmMessage({
    required String sessionName,
    required int songCount,
  }) =>
      '“$sessionName” and its ${_count(songCount, 'song', 'songs')} will be '
      'removed from this plan. The songs stay in the song library.';
```

- delete `sessionDeleteBlockedMessage`.

`plan_session_card.dart`:
- Remove the `if (session.items.isEmpty) ...[` wrapper around the delete
  `IfCapability`. Keep the `SizedBox(width: 8)` and the `IfCapability`.
- In `_deleteSession`, read
  `final entries = await ref.read(planningMutationEntriesProvider.future);`
  before the dialog, with a `context.mounted` check after it.
- Compute:

```dart
    // Spec D6/D11: the rows a cascade delete drops for this session.
    final hasDiscardableChanges = entries.any(
      (entry) =>
          (entry.sessionId == session.id ||
              (entry.kind.aggregateType == 'session_item_order' &&
                  entry.aggregateId == session.id)) &&
          entry.syncStatus != PlanningMutationSyncStatus.sending &&
          entry.syncStatus != PlanningMutationSyncStatus.cancelling &&
          entry.syncStatus != PlanningMutationSyncStatus.accepted,
    );
```

- Build the dialog content like Task 4.1's:
  - `session.items.isEmpty ? AppStrings.sessionDeleteEmptyConfirmMessage : AppStrings.sessionDeleteConfirmMessage(sessionName: session.name, songCount: session.items.length)`
  - plus the unsynced line when `hasDiscardableChanges`
  - the confirm button styled with the error color scheme.

- [ ] **Step 4: Run the tests, then full verification.** Expected: green.

- [ ] **Step 5: Commit.**

```bash
git add apps/lyron_app/lib apps/lyron_app/test
git commit -m "feat(planning): delete non-empty sessions with a cascade confirmation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4.3: Documentation (same PR, AGENTS.md)

**Files:**
- `docs/domain/domain-model.md`
- `docs/architecture/state-machines.md`
- `docs/architecture/architecture.md`
- `docs/architecture/decisions/ADR-038-plan-content-version.md` (create)
- `docs/specs/2026-09-29-plan-delete-and-session-cascade.md` (status)

- [ ] **Step 1: Domain model.** In `docs/domain/domain-model.md`:

- **plans:**
  - Add `content_version` to the field list.
  - Add these bullets to its rules:
    - "Every accepted write to a plan's sessions or session items bumps
      `content_version` by exactly one, with the plan row locked first."
    - "Plan delete is a cascade: the backend deletes the plan, its sessions
      and their session items only when both `version` and
      `content_version` still match the deleting client's base; songs and
      attachments are never deleted."
    - "A pending plan delete hides the plan from every merged read; until
      the backend accepts it, referenced songs stay delete-blocked."
- **sessions:** replace "Session delete is allowed only for locally empty
  sessions, and the backend re-checks that invariant before accepting the
  delete." with:
  - "Session delete is a cascade that removes the session's items; the
    backend accepts it only on a matching session `version`
    (`delete_session`). `delete_empty_session` is deprecated and kept only
    for installed older clients."
  - Also update the "planning mutation records" lines to include plan
    delete.

- [ ] **Step 2: State machines.** In `docs/architecture/state-machines.md`:

- **Plan:** add "A plan delete carries two bases, `version` and
  `content_version`; a mismatch on either is `RemovedConflict`. Retry is the
  explicit remove and rebases both from the refreshed projection; discard
  restores the plan but not the child intents the delete dropped."
- **Session:** replace "Session delete is allowed only for locally empty
  sessions; backend re-checks the invariant before accepting." with
  "Session delete cascades to the session's items; not-yet-sent item intents
  of the session are dropped when the delete is recorded."

- [ ] **Step 3: Architecture.** In `docs/architecture/architecture.md`:

- In the planning write boundary sentence ("covers plan create/edit, …"),
  add plan delete, and say that session delete cascades.
- Append to the in-flight-create-cancellation paragraph: "`planCreate` joins
  the cancellable creates (a plan deleted mid-create becomes a tombstone,
  then a real `planDelete`). After every accepted planning write the sync
  applies store-side effects: a contiguity-checked rebase of any pending
  cascade delete by the client's own accepted write, and a purge of a
  deleted subtree's remaining mutation rows (ADR-038)."

- [ ] **Step 4: ADR-038.** Create
  `docs/architecture/decisions/ADR-038-plan-content-version.md`, following
  ADR-037's section layout (Status, Context, Decision, Consequences,
  Alternatives considered). Content:

  - **Context:** cascade delete needs to detect concurrent writes to the
    subtree. `plans.version` covers plan fields and session order only.
  - **Decision:**
    - a separate `plans.content_version`, bumped by every child write, with
      the plan row locked first (lock order plan → session → item)
    - `delete_plan` checks both versions
    - the client rebases a pending delete only by exact contiguity with a
      value the backend returned for its own write, and otherwise lets it
      conflict
    - per-kind RPC parameter whitelist
  - **Alternatives rejected:**
    - **`version`-only:** silently deletes others' work.
    - **Client-sent content fingerprint:** it needs the same own-write
      rebasing and is harder to verify.
    - **Folding child writes into `version`:** false conflicts on every plan
      edit and session reorder, plus cross-aggregate client rebasing.
  - **Consequences:**
    - `plans.updated_at` moves on content changes
    - concurrent child writes on one plan serialize
    - narrow crash windows can still surface a self-conflict that retry
      resolves
    - the existing item-RPC race (both passing a pre-lock version check) is
      closed

- [ ] **Step 5: Spec status.** Change the spec's status line to
  `> Status: Implemented`. Add an "Implementation" section listing the
  commits (`git log --oneline main..HEAD`), the way
  `docs/specs/2026-08-06-in-flight-create-cancellation.md` does.

- [ ] **Step 6: Commit.**

```bash
git add docs
git commit -m "docs(planning): plan delete, cascading session delete, ADR-038

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4.4: Final verification and PR

- [ ] **Step 1:** `./scripts/verify.sh` from the repository root. It runs
  format, analyze, the full test suite with coverage, the coverage gate,
  migrations, backend contracts, and the integration flows. Expected: green.
  If the coverage gate fails, add tests for the uncovered new code; do not
  lower the gate.
- [ ] **Step 2: Review gate 4** (whole-branch diff, one adversarial reviewer):

  > "Show a way the UI deletes without confirmation, offers delete to a user
  > lacking `managePlans` or `editSessions`, leaves the user on the detail
  > screen of a deleted plan, or displays a count or warning that
  > contradicts what the delete will actually remove."

  Then apply the phase-3 question once more to the full branch.
- [ ] **Step 3:** Push, then open the PR to `main` with a body that:
  - summarizes D1–D12
  - lists the latent param bug fixed in Task 2.3
  - notes that the backend migration must deploy before the client
  - ends with the attribution line
    `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
- [ ] **Step 4:** Merge only with green CI (AGENTS.md).
