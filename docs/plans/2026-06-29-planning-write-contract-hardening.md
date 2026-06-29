# Planning Backend Write-Contract Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close three planning write-contract gaps — slug-suffix integer overflow, the missing DB-level unique-song-per-session invariant (SEC-5), and two unpinned RPC error-code contracts — via two new migrations plus backend write-contract test coverage.

**Architecture:** Ship two NEW Supabase migrations that `CREATE OR REPLACE` the affected functions and add a partial unique index; never edit the shipped migrations. Pin every behavior with assertions in the existing Python `psql`-in-container backend write-contract harness (`scripts/tests/planning-write-contract-test.sh`), TDD-style (RED before each backend change). Resolve the two deferred docs and the dart test workaround once the backend is green.

**Tech Stack:** PostgreSQL/PL-pgSQL (Supabase), Python test harness driving `psql` via `docker exec`, Dart/Flutter integration tests, bash gate scripts.

**Spec:** `docs/specs/2026-06-29-planning-write-contract-hardening.md`

---

## Reference: conventions an executor must know

- **Migrations are append-only.** Do NOT edit `202604100001_planning_write_contract.sql` or
  `202604110001_planning_session_item_write_contract.sql`. Add new files under
  `supabase/migrations/` named `<UTCYYYYMMDD><NNNN>_<slug>.sql`. The latest existing timestamp
  is `202605280001`; this plan uses `202606290001` and `202606290002` (sort after all existing).
- **Supabase CLI** is invoked through the repo wrapper `./scripts/supabase.sh` (AGENTS.md #11).
  Never call a global `supabase` binary.
- **Backend write-contract test** is `scripts/tests/planning-write-contract-test.sh`. It is a bash
  wrapper that runs an embedded Python script (heredoc `python3 - "$db_container_name" "$demo_user_id" <<'PY'`).
  Edit the Python body inside that heredoc. Helpers available in scope:
  - `create_plan(...)`, `update_plan_fields(...)`, `create_session(...)`, `rename_session(...)`,
    `delete_empty_session(...)`, `create_song_session_item(...)` — all return parsed JSON dicts.
  - `capture_error(sql, user_id=...)` — runs `sql` (a `perform ...;` statement) inside an
    exception-capturing `do $$` block and returns `(sqlstate, message, detail)`.
  - `run_psql(sql, user_id=None)` — raw psql; use for direct table inserts.
  - `sql_quote(value)` — SQL-escapes a Python str/None.
  - Module-scope constants: `organization_id = "11111111-1111-1111-1111-111111111111"`,
    `demo_user_id` (the authorized writer), `blocked_user_id = "88888888-8888-8888-8888-888888888888"`.
  - New assertion blocks go BEFORE the final `print("planning write contract verification passed")`
    line, after the existing assertions, so they reuse already-created fixtures where useful but do
    not disturb the ordered version numbers of existing fixtures. Use FRESH uuids/slugs for new rows.
- **Run a single backend contract test cycle** with:
  `./scripts/backend-write-contracts.sh` (starts Supabase, resets DB, provisions demo user, runs all
  three contract scripts). This is the loop you iterate on. To see a RED failure for an unfixed
  backend you must run the test BEFORE adding the migration.
- **Migration lint gate:** `./scripts/check-migrations.sh` (runs `supabase db lint`).
- **Full gate:** `./scripts/verify.sh` (formatting, analysis, Flutter tests, migration lint, Supabase
  reset, backend integration suites incl. the two-device matrix, contract scripts).

## File Structure

- **Create:** `supabase/migrations/202606290001_planning_slug_suffix_overflow_fix.sql`
  — `CREATE OR REPLACE` of `plan_next_slug` and `session_next_slug` with overflow-safe suffix parse.
- **Create:** `supabase/migrations/202606290002_session_item_unique_song_index.sql`
  — partial unique index `session_items_unique_song_per_session` + `CREATE OR REPLACE` of
  `create_song_session_item` that catches the index violation and re-raises the existing P0001.
- **Modify:** `scripts/tests/planning-write-contract-test.sh` — new assertion blocks (slug overflow,
  SEC-5 DB + RPC, RPC contract pins).
- **Modify:** `apps/lyron_app/test/integration/two_device_conflict_matrix_test.dart:264-283` — remove
  the slug-overflow workaround and its explanatory comment.
- **Modify:** `docs/testing/testing-strategy.md` — record the three new contract points.
- **Modify/Delete:** `docs/deferred/2026-06-29-slug-suffix-integer-overflow.md`,
  `docs/deferred/2026-06-29-integration-live-stack-verification.md`, `docs/deferred/README.md`.

---

## Task 1: Pin slug-overflow as a failing backend contract (RED)

**Files:**
- Modify/Test: `scripts/tests/planning-write-contract-test.sh`

- [ ] **Step 1: Add the failing slug-overflow assertions**

Insert this block in the embedded Python (inside the `<<'PY' ... PY` heredoc), immediately before
the final `print("planning write contract verification passed")` line:

```python
# --- Slug suffix overflow (large numeric suffix must not raise 22003) ---
# A name whose slug ends in a number >= 2^31 must create successfully and keep
# its full text slug; a forced collision must fall back to "<root>-2", not crash.
overflow_plan = create_plan(
    plan_id="a1111111-1111-1111-1111-111111111111",
    slug="",
    name="Set 1782711809759068",
    description=None,
    scheduled_for=None,
    user_id=demo_user_id,
)
assert overflow_plan["slug"] == "set-1782711809759068", overflow_plan["slug"]

overflow_plan_collision = create_plan(
    plan_id="a2222222-2222-2222-2222-222222222222",
    slug="",
    name="Set 1782711809759068",
    description=None,
    scheduled_for=None,
    user_id=demo_user_id,
)
assert overflow_plan_collision["slug"] == "set-1782711809759068-2", (
    overflow_plan_collision["slug"]
)

overflow_session = create_session(
    session_id="a3333333-3333-3333-3333-333333333333",
    plan_id=overflow_plan["id"],
    slug="",
    name="Cue 9999999999999999",
    user_id=demo_user_id,
)
assert overflow_session["slug"] == "cue-9999999999999999", overflow_session["slug"]
```

- [ ] **Step 2: Run the contract test to verify it FAILS**

Run: `./scripts/backend-write-contracts.sh`
Expected: FAIL. The first `create_plan` raises `22003` ("value ... is out of range for type
integer") because `plan_next_slug` casts the 16-digit suffix to `integer`. The Python `SystemExit`
from `run_psql`/`fetch_json` surfaces the psql error.

- [ ] **Step 3: Commit the RED test**

```bash
git add scripts/tests/planning-write-contract-test.sh
git commit -m "test(planning): pin slug suffix overflow as failing contract"
```

---

## Task 2: Fix slug-suffix overflow (GREEN)

**Files:**
- Create: `supabase/migrations/202606290001_planning_slug_suffix_overflow_fix.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/202606290001_planning_slug_suffix_overflow_fix.sql` with the full
overflow-safe re-definitions. The only behavioral change vs `202604100001` is the suffix-parse
exception block; everything else is copied verbatim so the function bodies stay complete.

```sql
-- Make slug-suffix numbering overflow-safe.
--
-- plan_next_slug / session_next_slug parse a trailing digit run of the
-- slugified name to continue a numbering sequence. The original cast to
-- integer (int4) raised an unhandled 22003 for any suffix >= 2^31, turning a
-- user-controlled name into a denial-of-write. We wrap the cast so an
-- out-of-range (or otherwise unparseable) suffix falls back to numbering from
-- 1. The full text slug is still used for the first insert; the fallback only
-- affects collision numbering ("<root>-2", "<root>-3", ...).
create or replace function public.plan_next_slug(
  target_organization_id uuid,
  base_slug text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_base_slug text := coalesce(nullif(public.slugify(base_slug), ''), 'plan');
  slug_root text := normalized_base_slug;
  slug_number integer := 1;
  candidate_slug text := normalized_base_slug;
begin
  if normalized_base_slug ~ '^(.*)-([0-9]+)$' then
    slug_root := regexp_replace(normalized_base_slug, '-[0-9]+$', '');
    begin
      slug_number := substring(normalized_base_slug from '([0-9]+)$')::integer;
    exception
      when numeric_value_out_of_range then
        slug_number := 1;
    end;
  end if;

  while exists (
    select 1
    from public.plans as plan
    where plan.organization_id = target_organization_id
      and plan.slug = candidate_slug
  ) loop
    slug_number := slug_number + 1;
    candidate_slug := slug_root || '-' || slug_number::text;
  end loop;

  return candidate_slug;
end;
$$;

create or replace function public.session_next_slug(
  target_plan_id uuid,
  base_slug text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_base_slug text := coalesce(nullif(public.slugify(base_slug), ''), 'session');
  slug_root text := normalized_base_slug;
  slug_number integer := 1;
  candidate_slug text := normalized_base_slug;
begin
  if normalized_base_slug ~ '^(.*)-([0-9]+)$' then
    slug_root := regexp_replace(normalized_base_slug, '-[0-9]+$', '');
    begin
      slug_number := substring(normalized_base_slug from '([0-9]+)$')::integer;
    exception
      when numeric_value_out_of_range then
        slug_number := 1;
    end;
  end if;

  while exists (
    select 1
    from public.sessions as session
    where session.plan_id = target_plan_id
      and session.slug = candidate_slug
  ) loop
    slug_number := slug_number + 1;
    candidate_slug := slug_root || '-' || slug_number::text;
  end loop;

  return candidate_slug;
end;
$$;
```

- [ ] **Step 2: Run migration lint**

Run: `./scripts/check-migrations.sh`
Expected: PASS (no lint errors).

- [ ] **Step 3: Run the contract test to verify GREEN**

Run: `./scripts/backend-write-contracts.sh`
Expected: PASS. The slug-overflow assertions from Task 1 now pass; all pre-existing assertions still
pass.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/202606290001_planning_slug_suffix_overflow_fix.sql
git commit -m "fix(planning): make slug suffix numbering overflow-safe"
```

---

## Task 3: Pin SEC-5 unique-song invariant as failing contract (RED)

**Files:**
- Modify/Test: `scripts/tests/planning-write-contract-test.sh`

The harness already asserts the sequential app-level pre-check raises
`P0001 duplicate_song_in_session_blocked` (existing `duplicate_song_error` block). This task adds the
DB-level proof: a direct second insert of the same `(session_id, song_id, item_type='song')` must be
rejected by a unique index named `session_items_unique_song_per_session`.

- [ ] **Step 1: Add the failing DB-level uniqueness assertion**

Insert before the final `print(...)` line. It reuses `created_session["id"]` and song
`33333333-...` already added to that session by the existing `created_item` block (so a second row
for that pair is a true duplicate):

```python
# --- SEC-5: DB-level unique(session_id, song_id) where item_type='song' ---
# A direct insert bypassing the app-level pre-check must still be rejected by
# the partial unique index.
sec5_direct_dup = capture_error(
    dedent(
        f"""
        insert into public.session_items (
          id, organization_id, session_id, song_id, item_type, position, version
        )
        values (
          '15151515-1515-1515-1515-151515151515'::uuid,
          {sql_quote(organization_id)}::uuid,
          {sql_quote(created_session["id"])}::uuid,
          '33333333-3333-3333-3333-333333333333'::uuid,
          'song',
          9001,
          1
        );
        """
    ),
    user_id=demo_user_id,
)
assert sec5_direct_dup[0] == "23505", sec5_direct_dup
assert "session_items_unique_song_per_session" in (
    sec5_direct_dup[1] + " " + sec5_direct_dup[2]
), sec5_direct_dup
```

- [ ] **Step 2: Run the contract test to verify it FAILS**

Run: `./scripts/backend-write-contracts.sh`
Expected: FAIL. Without the index the direct insert either succeeds (no error captured → empty row →
`SystemExit`) or fails only on `session_items_session_position` — not on
`session_items_unique_song_per_session`. The assertion on the constraint name fails.

- [ ] **Step 3: Commit the RED test**

```bash
git add scripts/tests/planning-write-contract-test.sh
git commit -m "test(planning): pin DB-level unique-song-per-session as failing contract"
```

---

## Task 4: Add SEC-5 partial unique index + stable RPC contract (GREEN)

**Files:**
- Create: `supabase/migrations/202606290002_session_item_unique_song_index.sql`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/202606290002_session_item_unique_song_index.sql`. It adds the partial
unique index and `CREATE OR REPLACE`s `create_song_session_item` so a lost duplicate race (which now
hits the index instead of slipping past the app-level pre-check) re-raises the existing
`P0001 duplicate_song_in_session_blocked` rather than a raw `23505`. The function body is copied
verbatim from `202604110001` except: a new `v_constraint_name text;` declaration, and the `insert`
wrapped in a `begin ... exception when unique_violation ... end;` block.

```sql
-- SEC-5: enforce "a song appears at most once per session" at the database
-- level, not only via the application-level pre-check in
-- create_song_session_item. The pre-check can be bypassed by a truly
-- concurrent double-insert sharing one stale base_version; the partial unique
-- index is the backstop. create_song_session_item catches the index violation
-- and re-raises the existing P0001 duplicate_song_in_session_blocked so the
-- client-facing error contract (mapped to dependencyBlocked) stays stable.
create unique index session_items_unique_song_per_session
  on public.session_items (session_id, song_id)
  where item_type = 'song';

create or replace function public.create_song_session_item(
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
  ordered_session_item_positions integer[]
)
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_session public.sessions%rowtype;
  visible_song public.songs%rowtype;
  next_position integer;
  v_constraint_name text;
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

  update public.sessions as session
  set
    version = session.version + 1,
    base_version = session.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where session.organization_id = p_organization_id
    and session.id = p_session_id;

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
    existing_session.version + 1,
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
    );
end;
$$;
```

- [ ] **Step 2: Run migration lint**

Run: `./scripts/check-migrations.sh`
Expected: PASS.

- [ ] **Step 3: Run the contract test to verify GREEN**

Run: `./scripts/backend-write-contracts.sh`
Expected: PASS. The SEC-5 DB-level assertion (Task 3) now passes; the pre-existing
`duplicate_song_error` (P0001 via app-level pre-check) still passes.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/202606290002_session_item_unique_song_index.sql
git commit -m "fix(planning): enforce unique song per session via partial index (SEC-5)"
```

---

## Task 5: Pin the two residual RPC error-code contracts

**Files:**
- Modify/Test: `scripts/tests/planning-write-contract-test.sh`

These assert the EXISTING backend behavior (no backend change). Both pass immediately; they exist so a
future regression is caught.

- [ ] **Step 1: Add the contract-pin assertions**

Insert before the final `print(...)` line. These create their own fresh fixtures so they do not
depend on the version state of earlier blocks.

```python
# --- RPC contract pin 1: edit vs remote-delete -> P0002 plan_not_found ---
# update_plan_fields against a plan id that does not exist (the remote-delete
# case) must raise P0002 plan_not_found, which the dart layer maps to
# remoteMissing (not conflict).
edit_vs_delete = capture_error(
    dedent(
        f"""
        perform public.update_plan_fields(
          p_organization_id => {sql_quote(organization_id)},
          p_plan_id => 'deadbeef-0000-0000-0000-000000000001'::uuid,
          p_base_version => 1,
          p_name => 'Edit after remote delete',
          p_description => null,
          p_scheduled_for => null
        );
        """
    ),
    user_id=demo_user_id,
)
assert edit_vs_delete[0] == "P0002", edit_vs_delete
assert edit_vs_delete[1] == "plan_not_found", edit_vs_delete

# --- RPC contract pin 2: LF-5 partial (name-only) edit is a full overwrite ---
# update_plan_fields always writes name, description and scheduled_for. A
# "name only" edit that passes null description/scheduled_for OVERWRITES the
# stored values (no field-level merge). Pin this so the contract is explicit.
lf5_plan = create_plan(
    plan_id="b1111111-1111-1111-1111-111111111111",
    slug="lf5-overwrite",
    name="LF5 Original",
    description="original description",
    scheduled_for="2026-07-01T09:00:00Z",
    user_id=demo_user_id,
)
assert lf5_plan["description"] == "original description", lf5_plan
lf5_updated = update_plan_fields(
    plan_id=lf5_plan["id"],
    base_version=lf5_plan["version"],
    name="LF5 Renamed",
    description=None,
    scheduled_for=None,
    user_id=demo_user_id,
)
assert lf5_updated["name"] == "LF5 Renamed", lf5_updated
assert lf5_updated["description"] is None, lf5_updated
assert lf5_updated["scheduled_for"] is None, lf5_updated
assert lf5_updated["version"] == lf5_plan["version"] + 1, lf5_updated
```

- [ ] **Step 2: Run the contract test to verify GREEN**

Run: `./scripts/backend-write-contracts.sh`
Expected: PASS (both blocks describe existing behavior).

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/planning-write-contract-test.sh
git commit -m "test(planning): pin edit-vs-remote-delete and LF-5 overwrite RPC contracts"
```

---

## Task 6: Remove the dart slug-overflow workaround

**Files:**
- Modify: `apps/lyron_app/test/integration/two_device_conflict_matrix_test.dart:264-283`

Now that the backend slug fix is shipped (Task 2), the scratch-session name no longer needs the
non-digit `run` prefix.

- [ ] **Step 1: Remove the workaround comment**

Delete the explanatory comment block at lines 264-275 (the paragraph beginning
`// The session name is suffixed with "-run$runId" ...` through
`// this test isn't about slug numbering.`).

- [ ] **Step 2: Drop the `run` prefix from the scratch-session name**

Change the create-session draft name (currently line ~281):

```dart
            name: 'Scratch session (edit-vs-delete run$runId)',
```

to:

```dart
            name: 'Scratch session (edit-vs-delete $runId)',
```

- [ ] **Step 3: Run the two-device integration suite against the live stack**

Run: `./scripts/verify.sh`
Expected: PASS — including `two_device_conflict_matrix_test.dart` (5/5). The bare
`microsecondsSinceEpoch` suffix now flows through the overflow-safe slug allocator. This is the
end-to-end proof of Task 2.

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/test/integration/two_device_conflict_matrix_test.dart
git commit -m "test(planning): drop slug-overflow workaround after backend fix"
```

---

## Task 7: Documentation and deferred resolution

**Files:**
- Modify: `docs/testing/testing-strategy.md`
- Delete: `docs/deferred/2026-06-29-slug-suffix-integer-overflow.md`
- Modify or Delete: `docs/deferred/2026-06-29-integration-live-stack-verification.md`
- Modify: `docs/deferred/README.md`

- [ ] **Step 1: Record the new contract points in testing-strategy**

In `docs/testing/testing-strategy.md`, in the section describing planning backend write-contract
coverage, add three bullet points (match the surrounding prose style):

```markdown
- Slug-suffix numbering is overflow-safe: a plan/session name ending in a number >= 2^31 creates
  successfully and keeps its full text slug (collision numbering falls back to 1). Verified in
  `scripts/tests/planning-write-contract-test.sh`.
- Unique song per session (SEC-5) is enforced by the partial index
  `session_items_unique_song_per_session`; a direct duplicate insert is rejected with 23505, and the
  `create_song_session_item` RPC re-raises `duplicate_song_in_session_blocked` (P0001).
- RPC error-code contracts pinned: editing a remotely-deleted plan raises `plan_not_found` (P0002 ->
  remoteMissing); `update_plan_fields` is a full overwrite (name-only edit clears description /
  scheduled_for), not a field-level merge.
```

- [ ] **Step 2: Resolve the deferred docs**

Per `docs/deferred/README.md`'s tracking rule, the resolving change updates/removes the deferred docs:
- Delete `docs/deferred/2026-06-29-slug-suffix-integer-overflow.md` (fully resolved by Tasks 1-2 + 6).
- For `docs/deferred/2026-06-29-integration-live-stack-verification.md`: its "Residual open questions"
  (RPC error-code pins) and the SEC-5 item are now resolved by Tasks 3-5. If nothing in the doc
  remains open, delete it; otherwise trim it to only any still-open item. Verify by re-reading the
  doc — at plan-writing time the only open items are the two RPC pins and the SEC-5 constraint
  question, all addressed here, so deletion is expected.

- [ ] **Step 3: Update the deferred index**

Edit `docs/deferred/README.md` to remove the index entries / tracking rows for both deleted docs
(match whatever table or list format the README uses).

- [ ] **Step 4: Commit**

```bash
git add docs/testing/testing-strategy.md docs/deferred/
git commit -m "docs(planning): record write-contract pins and resolve deferred items"
```

---

## Task 8: Final full-gate verification

- [ ] **Step 1: Run the complete gate**

Run: `./scripts/verify.sh`
Expected: PASS — formatting, analysis, Flutter unit/widget tests, migration lint, backend
write-contract scripts, and the backend integration suites (including the two-device matrix).

- [ ] **Step 2: Confirm migration lint independently**

Run: `./scripts/check-migrations.sh`
Expected: PASS.

- [ ] **Step 3: Open the PR**

```bash
git push -u origin fix/planning-write-contract-hardening
gh pr create --fill --base main
```

The PR body should summarize the three closed gaps and link the spec/plan. Ensure CI is green before
requesting review (AGENTS.md #7).

---

## Self-Review (completed by plan author)

- **Spec coverage:** slug overflow → Tasks 1-2, 6; SEC-5 index + stable contract → Tasks 3-4; RPC
  pins (edit-vs-remote-delete, LF-5) → Task 5; dart workaround removal → Task 6; testing-strategy +
  deferred resolution → Task 7; gates (check-migrations, backend-write-contracts, verify) → Tasks 2,
  4, 8. All spec scope items mapped.
- **No-ADR decision:** honored (semantics documented in the migration comment + spec, no ADR task).
- **No shipped-migration edits:** all changes are new migrations `202606290001` / `202606290002`.
- **Type/name consistency:** index name `session_items_unique_song_per_session` used identically in
  the migration (Task 4), the RED assertion (Task 3), and testing-strategy (Task 7). Re-raised
  message `duplicate_song_in_session_blocked` matches the existing app-level pre-check string.
- **Contract direction:** edit-vs-remote-delete pinned to `P0002 plan_not_found` (→ remoteMissing),
  consistent with `supabase_planning_mutation_repository.dart:152-156`; not `conflict`.
