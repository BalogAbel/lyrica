# Song Key Layers, PR 1 (Backend) Implementation Plan

> Status: Ready for execution (2026-10-13). Covers PR 1 of
> `docs/specs/2026-10-13-personal-song-settings.md` only; PR 2 and PR 3 get
> their own plans after this PR merges and its migration is deployed.

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the plan layer's storage and write contract: two nullable key
columns on `session_items` and the `set_session_item_key` RPC, proven by a
real-role contract suite written first.

**Architecture:** One migration adds `session_items.transpose` and
`session_items.capo` with range checks, and one `security definer` RPC writes
them with keep / set / clear per field, a no-op fast path, and optimistic
concurrency on the item's own `version`. It locks the owning plan row first
(ADR-038 lock order) and bumps `plans.content_version`, never
`sessions.version`. No client code changes in this PR.

**Tech Stack:** PostgreSQL (Supabase local stack via `./scripts/supabase.sh`),
PL/pgSQL, the repository's bash + embedded Python contract-test harness
(psql inside the `supabase_db_*` container).

**Spec:** `docs/specs/2026-10-13-personal-song-settings.md` (PS10–PS13,
PS23, PS24; tests K1–K15). ADR-042, ADR-038, ADR-039.

## Global Constraints

- Branch: `feat/personal-settings-backend` (already exists, holds the docs
  commits). Never commit to `main`.
- Migration file: `supabase/migrations/202610130001_session_item_key.sql`.
- Columns: `transpose smallint null` with `check (transpose between -11 and
  11)`; `capo smallint null` with `check (capo between 0 and 11)`.
  Constraint names: `session_items_transpose_range_check`,
  `session_items_capo_range_check`.
- RPC signature, exactly:
  `public.set_session_item_key(uuid, uuid, uuid, bigint, text, integer, text, integer)`
  with parameter names `p_organization_id`, `p_session_id`,
  `p_session_item_id`, `p_base_version`, `p_transpose_mode`, `p_transpose`,
  `p_capo_mode`, `p_capo`.
- Modes: exactly `keep`, `set`, `clear` (case-sensitive, no trimming).
- Error vocabulary, exactly: `invalid_session_item_key` (`22023`),
  `session_item_version_conflict` (`P0001`), `session_not_found` (`P0002`),
  `plan_not_found` (`P0002`), `session_item_not_found` (`P0002`). Conflict
  detail: `expected base_version <base> but found current version <current>`.
- ADR-039 convention: `security definer`, owner `postgres`,
  `set search_path = public`, `revoke all ... from public, anon,
  authenticated`, `grant execute ... to authenticated`, no `service_role`
  grant, no grant change on any table.
- Do not change any existing RPC, policy, table or column beyond the two new
  columns and their checks.
- Contract tests call every RPC as `authenticated` with the caller's JWT
  claims (the harness's `run_psql(..., user_id=...)`); fixtures are written as
  `postgres`.
- Hosted deploy is a user action after merge, in the Supabase SQL editor,
  wrapped in `begin;` ... `commit;`. Never run `supabase db push`.
- Every task's verification runs the full gates named in that task, never a
  single suite alone.
- Code, SQL comments, commits and docs in English. Subagent reports in
  caveman ultra (terse; identifiers, file:line and code exact).

## Review Focus

Inputs the spec implies that a naive implementation gets wrong. Each has a
pinning test in Task 1:

1. A mode spelled differently (`'SET'`, `' set'`, `null`) must be
   `invalid_session_item_key`, not a silent `keep`. (K8)
2. A value outside `smallint` (`40000`) must be `invalid_session_item_key`,
   not a numeric-overflow error from a cast. (K8)
3. A key edit aimed at an attachment item must be `session_item_not_found`.
   (K10)
4. A key edit that waited on the plan lock while the whole session was
   deleted must be `session_item_not_found`, not a crash or a write. (K13)
5. A no-op must not physically rewrite the row (its `xmin` is unchanged) and
   must return the server's current values, including a field the request
   kept. (K5)

## STOP-and-report conditions

Stop, report and wait for the user (do not improvise) when any of these
happens:

- An existing contract suite, `./scripts/check-migrations.sh` or
  `./scripts/verify.sh` fails after the migration, or needs a change to pass.
- `scripts/tests/direct-table-dml-contract-test.sh` flags the new function or
  columns.
- A K13 race reports that the waiter "never blocked on a lock" (the RPC does
  not lock the plan row first, so the lock-order design is not what runs).
- Making a K-test pass seems to need a change to an existing RPC, policy,
  table, the harness helpers' behavior, or the spec's error vocabulary.
- `supabase db lint` reports an error or warning in the new function.

## File Structure

- Create `scripts/tests/session-item-key-contract-test.sh`: the K1–K15
  contract suite (bash bootstrap + embedded Python, same harness as
  `scripts/tests/planning-cascade-delete-contract-test.sh`).
- Modify `scripts/backend-write-contracts.sh`: run the new suite in the
  backend contract gate.
- Create `supabase/migrations/202610130001_session_item_key.sql`: columns,
  checks, RPC, grants.
- Modify `docs/architecture/decisions/ADR-038-plan-content-version.md`: the
  2026-10-13 amendment (PS13).
- Modify `docs/domain/domain-model.md`: `session_items` key fields.
- Modify `docs/specs/2026-10-13-personal-song-settings.md`: status note.

Not touched: `scripts/tests/backend-write-contracts-test.sh` (an unwired,
already stale mock test of the gate's call order; no gate runs it).

---

### Task 1: Contract suite K1–K15, red

**Files:**
- Create: `scripts/tests/session-item-key-contract-test.sh`
- Modify: `scripts/backend-write-contracts.sh` (append after the
  `planning_cascade_delete_test_script` block, before
  `song_crud_write_contract_test_script`'s invocation is fine too; keep each
  suite on its own line pair)

**Interfaces:**
- Consumes: the existing RPCs `create_plan`, `create_session`,
  `create_song_session_item`, `reorder_session_items`, `rename_session`,
  `delete_session_item`, `delete_session`, `delete_plan`; seed organization
  `11111111-1111-1111-1111-111111111111`, seed song
  `33333333-3333-3333-3333-333333333333`, demo user `demo@lyron.local`.
- Produces: the suite Task 2 turns green, and its gate wiring.

- [ ] **Step 1: Write the suite**

Create `scripts/tests/session-item-key-contract-test.sh` with exactly this
content:

````bash
#!/usr/bin/env bash
set -euo pipefail

# Session item key contract (S3 PR 1).
# Spec: docs/specs/2026-10-13-personal-song-settings.md, PS10-PS13, K1-K15.

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

if [[ "${BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP:-0}" != "1" ]]; then
  ./scripts/supabase.sh start >/dev/null
  ./scripts/db-reset.sh >/dev/null

  status_env="$(./scripts/supabase.sh status -o env)"
  eval "$status_env"

  if [[ -z "${API_URL:-}" ]]; then
    echo "Local Supabase is not running or did not return API_URL." >&2
    exit 1
  fi

  for _ in $(seq 1 30); do
    if curl --silent --fail "$API_URL/auth/v1/health" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  ./scripts/provision-local-demo-user.sh >/dev/null
fi

db_container_name="$(
  docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1
)"

if [[ -z "$db_container_name" ]]; then
  echo "Could not find the local Supabase database container." >&2
  exit 1
fi

demo_user_query="$(
  ./scripts/supabase.sh db query -o json "
    select id
    from auth.users
    where email = 'demo@lyron.local';
  "
)"

demo_user_id="$(
  QUERY_RESULT="$demo_user_query" REPO_ROOT="$repo_root" python3 - <<'PY'
import json
import os
import subprocess

payload = json.loads(
    subprocess.check_output(
        ["python3", f"{os.environ['REPO_ROOT']}/scripts/extract_supabase_json.py"],
        input=os.environ["QUERY_RESULT"],
        text=True,
    )
)
rows = payload if isinstance(payload, list) else payload.get("rows", [])
if len(rows) != 1:
    raise SystemExit(f"unexpected rows: {rows!r}")
print(rows[0]["id"])
PY
)"

python3 - "$db_container_name" "$demo_user_id" <<'PY'
import json
import subprocess
import sys
import threading
import time
from textwrap import dedent

container_name = sys.argv[1]
demo_user_id = sys.argv[2]
blocked_user_id = "88888888-8888-8888-8888-888888888888"
organization_id = "11111111-1111-1111-1111-111111111111"


def normalize_uuid(value: str) -> str:
    if value.startswith("["):
        parts = json.loads(value)
        if len(parts) != 16:
            raise SystemExit(f"unexpected uuid bytes: {parts!r}")
        hex_value = "".join(f"{part:02x}" for part in parts)
        return (
            f"{hex_value[0:8]}-{hex_value[8:12]}-{hex_value[12:16]}-"
            f"{hex_value[16:20]}-{hex_value[20:32]}"
        )
    return value


demo_user_id = normalize_uuid(demo_user_id)


def sql_quote(value: str | None) -> str:
    if value is None:
        return "null"
    return "'" + value.replace("'", "''") + "'"


def sql_int(value: int | None) -> str:
    return "null" if value is None else str(value)


def run_psql(sql: str, user_id: str | None = None) -> str:
    if user_id is not None:
        sql = dedent(
            f"""
            do $$
            begin
              perform set_config('request.jwt.claim.sub', {sql_quote(user_id)}, true);
              perform set_config('request.jwt.claim.role', 'authenticated', true);
            end $$;
            set local role authenticated;
            {sql}
            """
        )

    result = subprocess.run(
        [
            "docker",
            "exec",
            "-i",
            container_name,
            "psql",
            "-U",
            "postgres",
            "-d",
            "postgres",
            "-v",
            "ON_ERROR_STOP=1",
            "-X",
            "-qAt",
            "-F",
            "\t",
            "-c",
            sql,
        ],
        text=True,
        capture_output=True,
        check=False,
    )

    if result.returncode != 0:
        raise SystemExit(
            "psql failed:\n"
            f"SQL:\n{sql}\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )

    return result.stdout.strip()


def fetch_json(sql: str, user_id: str | None = None) -> dict:
    raw = run_psql(sql, user_id=user_id)
    if not raw:
        raise SystemExit(f"expected JSON output, got empty result for:\n{sql}")
    return json.loads(raw)


def fetch_row(sql: str, user_id: str | None = None) -> list[str]:
    raw = run_psql(sql, user_id=user_id)
    if not raw:
        raise SystemExit(f"expected row output, got empty result for:\n{sql}")
    return raw.split("\t")


def capture_error(sql: str, user_id: str | None = None) -> tuple[str, str, str]:
    capture_sql = dedent(
        f"""
        create temp table if not exists planning_write_error_capture (
          sqlstate text,
          message text,
          detail text
        );
        truncate planning_write_error_capture;
        do $$
        declare
          v_sqlstate text;
          v_message text;
          v_detail text;
        begin
          begin
            {sql}
          exception when others then
            get stacked diagnostics
              v_sqlstate = RETURNED_SQLSTATE,
              v_message = MESSAGE_TEXT,
              v_detail = PG_EXCEPTION_DETAIL;
            insert into planning_write_error_capture values (
              v_sqlstate,
              v_message,
              coalesce(v_detail, '')
            );
          end;
        end $$;
        select sqlstate, message, detail
        from planning_write_error_capture
        limit 1;
        """
    )

    row = fetch_row(capture_sql, user_id=user_id)
    if len(row) != 3:
        raise SystemExit(f"unexpected captured error row: {row!r}")
    return row[0], row[1], row[2]


# ---------------------------------------------------------------------------
# Runs after the other planning suites on the same database, so every id here
# uses its own e5/e6 prefix and every slug its own key- prefix.
# ---------------------------------------------------------------------------

seed_song_id = "33333333-3333-3333-3333-333333333333"
plan_k = "e5000000-0000-0000-0000-000000000001"
session_k = "e5000000-0000-0000-0000-00000000000a"
session_l = "e5000000-0000-0000-0000-00000000000b"
song_x = "e5000000-0000-0000-0000-00000000005a"
song_y = "e5000000-0000-0000-0000-00000000005b"
attachment_id = "e5000000-0000-0000-0000-0000000000a7"
item_k1 = "e5000000-0000-0000-0000-0000000000a1"
item_k2 = "e5000000-0000-0000-0000-0000000000a2"
item_att = "e5000000-0000-0000-0000-0000000000a3"
item_k4 = "e5000000-0000-0000-0000-0000000000a4"
item_l1 = "e5000000-0000-0000-0000-0000000000b1"
unknown_item_id = "e5000000-0000-0000-0000-0000000000ff"
read_only_user_id = "e5000000-0000-0000-0000-0000000000ee"
foreign_org_id = "e5000000-0000-0000-0000-0000000000f0"

org = sql_quote(organization_id)
key_signature = (
    "public.set_session_item_key"
    "(uuid, uuid, uuid, bigint, text, integer, text, integer)"
)


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


def plan_version(plan_id: str) -> int:
    return int(
        run_psql(
            f"select version from public.plans where id = {sql_quote(plan_id)}::uuid;"
        )
    )


def session_version(session_id: str) -> int:
    return int(
        run_psql(
            "select version from public.sessions "
            f"where id = {sql_quote(session_id)}::uuid;"
        )
    )


def row_count(sql: str) -> int:
    return int(run_psql(sql))


def key_args(
    item_id: str,
    base: int | None,
    transpose_mode: str | None = "keep",
    transpose: int | None = None,
    capo_mode: str | None = "keep",
    capo: int | None = None,
    session_id: str = session_k,
    organization: str = organization_id,
) -> str:
    return f"""
        p_organization_id => {sql_quote(organization)}::uuid,
        p_session_id => {sql_quote(session_id)}::uuid,
        p_session_item_id => {sql_quote(item_id)}::uuid,
        p_base_version => {sql_int(base)},
        p_transpose_mode => {sql_quote(transpose_mode)},
        p_transpose => {sql_int(transpose)},
        p_capo_mode => {sql_quote(capo_mode)},
        p_capo => {sql_int(capo)}
    """


def item_state(item_id: str) -> dict:
    row = fetch_row(
        dedent(
            f"""
            select
              version,
              coalesce(transpose::text, 'null'),
              coalesce(capo::text, 'null'),
              coalesce(base_version::text, 'null'),
              sync_status::text,
              coalesce(last_modified_by::text, 'null'),
              xmin::text
            from public.session_items
            where id = {sql_quote(item_id)}::uuid;
            """
        )
    )

    def optional_int(text: str) -> int | None:
        return None if text == "null" else int(text)

    return {
        "version": int(row[0]),
        "transpose": optional_int(row[1]),
        "capo": optional_int(row[2]),
        "base_version": optional_int(row[3]),
        "sync_status": row[4],
        "last_modified_by": None if row[5] == "null" else row[5],
        "xmin": row[6],
    }


def key_of(state: dict) -> tuple:
    return state["version"], state["transpose"], state["capo"]


def world() -> tuple:
    """Everything a rejected or no-op key edit must leave untouched. The
    items' xmin proves that the rows were not rewritten at all."""
    return (
        item_state(item_k1),
        item_state(item_k2),
        session_version(session_k),
        plan_content_version(plan_k),
    )


def add_song_item(session_id: str, item_id: str, song_id: str) -> dict:
    return call(
        "create_song_session_item",
        f"""
        p_organization_id => {org},
        p_session_id => {sql_quote(session_id)}::uuid,
        p_session_item_id => {sql_quote(item_id)}::uuid,
        p_song_id => {sql_quote(song_id)}::uuid,
        p_base_version => {session_version(session_id)},
        p_position => null
        """,
    )


def race(tag: str, holder_sql: str, waiter_sql: str) -> tuple[str, str, str]:
    """Run holder_sql as the demo user inside an open transaction (it takes the
    plan row lock), start waiter_sql (a `perform public.x(...);` statement) via
    capture_error in a thread, wait until the waiter blocks on a lock, commit
    the holder, and return the waiter's (sqlstate, message, detail)."""
    holder = subprocess.Popen(
        [
            "docker",
            "exec",
            "-i",
            container_name,
            "psql",
            "-U",
            "postgres",
            "-d",
            "postgres",
            "-v",
            "ON_ERROR_STOP=1",
            "-X",
            "-qAt",
        ],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    result: list = []

    # pg_stat_activity.query is cut at track_activity_query_size (1 kB
    # locally), so the tag goes before the statement.
    def run_waiter() -> None:
        try:
            result.append(
                capture_error(
                    f"-- race-waiter-{tag}\n" + waiter_sql, user_id=demo_user_id
                )
            )
        except BaseException as error:  # SystemExit included
            result.append(error)

    waiter = threading.Thread(target=run_waiter)
    try:
        assert holder.stdin is not None
        for statement in (
            "begin;",
            f"select set_config('request.jwt.claim.sub', {sql_quote(demo_user_id)}, true);",
            "select set_config('request.jwt.claim.role', 'authenticated', true);",
            "set local role authenticated;",
            holder_sql,
            f"select 'race-holder-{tag}';",
        ):
            holder.stdin.write(statement + "\n")
        holder.stdin.flush()

        deadline = time.monotonic() + 30
        while True:
            if holder.poll() is not None:
                raise SystemExit(
                    f"race {tag}: holder exited early:\n{holder.stderr.read()}"
                )
            ready = run_psql(
                "select count(*) from pg_stat_activity "
                "where state = 'idle in transaction' "
                f"and query like '%race-holder-{tag}%' "
                "and pid <> pg_backend_pid();"
            )
            if ready == "1":
                break
            if time.monotonic() > deadline:
                raise SystemExit(f"race {tag}: holder never became ready")
            time.sleep(0.1)

        waiter.start()

        deadline = time.monotonic() + 30
        while True:
            if not waiter.is_alive():
                raise SystemExit(
                    f"race {tag}: waiter finished without blocking: {result!r}"
                )
            blocked = run_psql(
                "select count(*) from pg_stat_activity "
                "where wait_event_type = 'Lock' "
                f"and query like '%race-waiter-{tag}%' "
                "and pid <> pg_backend_pid();"
            )
            if blocked == "1":
                break
            if time.monotonic() > deadline:
                raise SystemExit(f"race {tag}: waiter never blocked on a lock")
            time.sleep(0.1)

        holder.stdin.write("commit;\n")
        holder.stdin.close()
        holder.wait(timeout=30)
        if holder.returncode != 0:
            raise SystemExit(
                f"race {tag}: holder failed:\n{holder.stderr.read()}"
            )
        waiter.join(timeout=30)
        if waiter.is_alive():
            raise SystemExit(f"race {tag}: waiter did not finish after commit")
    finally:
        if holder.poll() is None:
            holder.kill()
            holder.wait()

    outcome = result[0]
    if isinstance(outcome, BaseException):
        raise outcome
    return outcome


# --- K1: function shape ----------------------------------------------------

secdef, config, auth_exec, anon_exec, owner = fetch_row(
    dedent(
        f"""
        select
          p.prosecdef,
          coalesce(array_to_string(p.proconfig, ','), ''),
          has_function_privilege('authenticated', p.oid, 'execute'),
          has_function_privilege('anon', p.oid, 'execute'),
          pg_get_userbyid(p.proowner)
        from pg_proc as p
        where p.oid = '{key_signature}'::regprocedure;
        """
    )
)
assert secdef == "t", secdef
assert "search_path=public" in config, config
assert auth_exec == "t", auth_exec
assert anon_exec == "f", anon_exec
assert owner == "postgres", owner

# --- Fixtures --------------------------------------------------------------

created = call(
    "create_plan",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_k)}::uuid,
    p_slug => 'key-layers',
    p_name => 'Key Layers',
    p_description => null,
    p_scheduled_for => null
    """,
)
assert created["content_version"] == 1, created
for fixture_session, slug in ((session_k, "key-k"), (session_l, "key-l")):
    call(
        "create_session",
        f"""
        p_organization_id => {org},
        p_plan_id => {sql_quote(plan_k)}::uuid,
        p_session_id => {sql_quote(fixture_session)}::uuid,
        p_slug => '{slug}',
        p_name => '{slug}'
        """,
    )

run_psql(
    dedent(
        f"""
        insert into public.songs (
          id, organization_id, slug, title, chordpro_source
        )
        values
          (
            {sql_quote(song_x)}::uuid,
            {org}::uuid,
            'key-layers-x',
            'Key Layers X',
            '{{title: Key Layers X}}'
          ),
          (
            {sql_quote(song_y)}::uuid,
            {org}::uuid,
            'key-layers-y',
            'Key Layers Y',
            '{{title: Key Layers Y}}'
          );

        insert into public.attachments (
          id, organization_id, song_id, storage_bucket, storage_path,
          mime_type, file_name
        )
        values (
          {sql_quote(attachment_id)}::uuid,
          {org}::uuid,
          {sql_quote(song_x)}::uuid,
          'song-attachments',
          'key-layers/x.pdf',
          'application/pdf',
          'x.pdf'
        );
        """
    )
)

add_song_item(session_k, item_k1, seed_song_id)
add_song_item(session_k, item_k2, song_x)
add_song_item(session_l, item_l1, seed_song_id)
run_psql(
    dedent(
        f"""
        insert into public.session_items (
          id, organization_id, session_id, attachment_id, item_type,
          position, version
        )
        values (
          {sql_quote(item_att)}::uuid,
          {org}::uuid,
          {sql_quote(session_k)}::uuid,
          {sql_quote(attachment_id)}::uuid,
          'attachment',
          99,
          1
        );

        insert into auth.users (id, email)
        values ({sql_quote(read_only_user_id)}, 'key-readonly@lyron.local')
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
          'Key Foreign Organization',
          'key-foreign-organization'
        )
        on conflict (id) do nothing;
        """
    )
)

# --- K11 (part 1): a created item starts without a key, at version 1 ------

for created_item in (item_k1, item_k2, item_l1):
    assert key_of(item_state(created_item)) == (1, None, None), created_item

# --- K15: read boundary ----------------------------------------------------

read_key = (
    "select version, coalesce(transpose::text, 'null'), "
    "coalesce(capo::text, 'null') from public.session_items "
    f"where id = {sql_quote(item_k1)}::uuid;"
)
assert run_psql(read_key, user_id=demo_user_id).split("\t") == ["1", "null", "null"]
assert run_psql(read_key, user_id=read_only_user_id).split("\t") == [
    "1",
    "null",
    "null",
]
assert run_psql(read_key, user_id=blocked_user_id) == ""

# --- K2: column checks (direct write as postgres) --------------------------

for column, value, constraint in (
    ("transpose", 12, "session_items_transpose_range_check"),
    ("transpose", -12, "session_items_transpose_range_check"),
    ("capo", -1, "session_items_capo_range_check"),
    ("capo", 12, "session_items_capo_range_check"),
):
    sqlstate, message, _detail = capture_error(
        f"update public.session_items set {column} = {value} "
        f"where id = {sql_quote(item_k1)}::uuid;"
    )
    assert sqlstate == "23514", (column, value, sqlstate, message)
    assert constraint in message, (column, value, message)
run_psql(
    "update public.session_items set transpose = null, capo = null "
    f"where id = {sql_quote(item_k1)}::uuid;"
)

# --- K8: invalid payloads change nothing -----------------------------------

before = world()
for payload in (
    {"transpose_mode": "move"},
    {"transpose_mode": "SET", "transpose": 2},
    {"transpose_mode": " set", "transpose": 2},
    {"transpose_mode": None},
    {"capo_mode": None},
    {"transpose_mode": "set", "transpose": None},
    {"capo_mode": "set", "capo": None},
    {"transpose_mode": "keep", "transpose": 2},
    {"transpose_mode": "clear", "transpose": 0},
    {"capo_mode": "keep", "capo": 1},
    {"capo_mode": "clear", "capo": 0},
    {"transpose_mode": "set", "transpose": 12},
    {"transpose_mode": "set", "transpose": -12},
    {"transpose_mode": "set", "transpose": 40000},
    {"capo_mode": "set", "capo": -1},
    {"capo_mode": "set", "capo": 12},
    {"capo_mode": "set", "capo": 40000},
):
    assert call_error(
        "set_session_item_key", key_args(item_k1, 1, **payload)
    ) == ("22023", "invalid_session_item_key"), payload
assert world() == before

# --- K7: a null base is a conflict -----------------------------------------

assert call_error(
    "set_session_item_key", key_args(item_k1, None, "set", 2)
) == ("P0001", "session_item_version_conflict")
assert world() == before

# --- K9: authorization ----------------------------------------------------

for denied_user in (blocked_user_id, read_only_user_id):
    assert call_error(
        "set_session_item_key",
        key_args(item_k1, 1, "set", 2),
        user_id=denied_user,
    ) == ("P0002", "session_not_found"), denied_user
assert call_error(
    "set_session_item_key",
    key_args(item_k1, 1, "set", 2, organization=foreign_org_id),
) == ("P0002", "session_not_found")
assert world() == before

# --- K10: only a song item of this session --------------------------------

for target_item in (unknown_item_id, item_l1, item_att):
    assert call_error(
        "set_session_item_key", key_args(target_item, 1, "set", 2)
    ) == ("P0002", "session_item_not_found"), target_item
assert world() == before

# --- K3: set both at the current base --------------------------------------

content_before = plan_content_version(plan_k)
session_before = session_version(session_k)
result = call("set_session_item_key", key_args(item_k1, 1, "set", 2, "set", 3))
assert result == {
    "id": item_k1,
    "plan_id": plan_k,
    "session_id": session_k,
    "organization_id": organization_id,
    "version": 2,
    "transpose": 2,
    "capo": 3,
    "plan_content_version": content_before + 1,
}, result
assert plan_content_version(plan_k) == content_before + 1
assert session_version(session_k) == session_before
state = item_state(item_k1)
assert (
    state["version"],
    state["transpose"],
    state["capo"],
    state["base_version"],
    state["sync_status"],
    state["last_modified_by"],
) == (2, 2, 3, 1, "synced", demo_user_id), state

# --- K4: keep / set / clear -----------------------------------------------

for base, t_mode, t_value, c_mode, c_value, want_t, want_c in (
    (2, "keep", None, "clear", None, 2, None),
    (3, "clear", None, "set", 5, None, 5),
    (4, "set", -11, "keep", None, -11, 5),
    (5, "clear", None, "clear", None, None, None),
    (6, "set", 11, "set", 0, 11, 0),
    (7, "keep", None, "set", 11, 11, 11),
):
    content_before = plan_content_version(plan_k)
    result = call(
        "set_session_item_key",
        key_args(item_k1, base, t_mode, t_value, c_mode, c_value),
    )
    assert (
        result["version"],
        result["transpose"],
        result["capo"],
        result["plan_content_version"],
    ) == (base + 1, want_t, want_c, content_before + 1), (base, result)
assert key_of(item_state(item_k1)) == (8, 11, 11)
assert session_version(session_k) == session_before

# --- K5: no-op at any base writes and bumps nothing ------------------------

before = world()
for target_item, args, want in (
    (item_k1, key_args(item_k1, 1, "set", 11), (8, 11, 11)),
    (item_k1, key_args(item_k1, 1, "set", 11, "set", 11), (8, 11, 11)),
    (item_k1, key_args(item_k1, 99, "keep", None, "keep", None), (8, 11, 11)),
    (item_k2, key_args(item_k2, 7, "clear", None, "clear", None), (1, None, None)),
):
    result = call("set_session_item_key", args)
    assert (result["id"], result["version"], result["transpose"], result["capo"]) == (
        target_item,
        *want,
    ), result
    assert result["plan_content_version"] == before[3], result
assert world() == before

# --- K6: a stale base with a differing value conflicts ---------------------

assert capture_error(
    f"perform public.set_session_item_key({key_args(item_k1, 7, 'set', 3)});",
    user_id=demo_user_id,
) == (
    "P0001",
    "session_item_version_conflict",
    "expected base_version 7 but found current version 8",
)
assert world() == before

# --- K14: two items of one session never conflict -------------------------

session_before = session_version(session_k)
content_before = plan_content_version(plan_k)
first = call("set_session_item_key", key_args(item_k1, 8, "set", 1))
second = call("set_session_item_key", key_args(item_k2, 1, "set", 4, "set", 2))
assert first["version"] == 9, first
assert second["version"] == 2, second
assert session_version(session_k) == session_before
assert plan_content_version(plan_k) == content_before + 2

# --- K11 (part 2): existing RPCs never write the key ----------------------

k1_before = key_of(item_state(item_k1))
k2_before = key_of(item_state(item_k2))
call(
    "reorder_session_items",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_k)}::uuid,
    p_base_version => {session_version(session_k)},
    p_session_item_ids => array[
      {sql_quote(item_att)}::uuid,
      {sql_quote(item_k2)}::uuid,
      {sql_quote(item_k1)}::uuid
    ]
    """,
)
call(
    "rename_session",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_k)}::uuid,
    p_base_version => {session_version(session_k)},
    p_name => 'key-k renamed'
    """,
)
add_song_item(session_k, item_k4, song_y)
assert key_of(item_state(item_k1)) == k1_before
assert key_of(item_state(item_k2)) == k2_before
assert key_of(item_state(item_k4)) == (1, None, None)

# --- K12: cascade guards --------------------------------------------------

plan_version_before = plan_version(plan_k)
content_before = plan_content_version(plan_k)
call(
    "set_session_item_key",
    key_args(item_k1, item_state(item_k1)["version"], "set", -3),
)
assert call_error(
    "delete_plan",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_k)}::uuid,
    p_base_version => {plan_version_before},
    p_base_content_version => {content_before}
    """,
) == ("P0001", "plan_version_conflict")

session_l_before = session_version(session_l)
call("set_session_item_key", key_args(item_l1, 1, "set", 5, session_id=session_l))
assert session_version(session_l) == session_l_before
deleted = call(
    "delete_session",
    f"""
    p_organization_id => {org},
    p_session_id => {sql_quote(session_l)}::uuid,
    p_base_version => {session_l_before}
    """,
)
assert deleted["deleted"] is True, deleted
assert row_count(
    "select count(*) from public.session_items "
    f"where id = {sql_quote(item_l1)}::uuid;"
) == 0

# --- K13: waits on the plan lock, then sees the committed state -----------


def setup_race(n: int) -> tuple[str, str, str]:
    plan_id = f"e6000000-0000-0000-0000-0000000000{n}1"
    session_id = f"e6000000-0000-0000-0000-0000000000{n}2"
    item_id = f"e6000000-0000-0000-0000-0000000000{n}3"
    call(
        "create_plan",
        f"""
        p_organization_id => {org},
        p_plan_id => {sql_quote(plan_id)}::uuid,
        p_slug => 'key-race-{n}',
        p_name => 'Key Race {n}',
        p_description => null,
        p_scheduled_for => null
        """,
    )
    call(
        "create_session",
        f"""
        p_organization_id => {org},
        p_plan_id => {sql_quote(plan_id)}::uuid,
        p_session_id => {sql_quote(session_id)}::uuid,
        p_slug => 'key-race-{n}-s',
        p_name => 'Key Race {n} S'
        """,
    )
    add_song_item(session_id, item_id, seed_song_id)
    return plan_id, session_id, item_id


_plan_1, session_1, item_1 = setup_race(1)
outcome = race(
    "k13a",
    f"""select public.delete_session_item(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_1)}::uuid,
      p_session_item_id => {sql_quote(item_1)}::uuid,
      p_base_version => {session_version(session_1)}
    );""",
    "perform public.set_session_item_key("
    f"{key_args(item_1, 1, 'set', 2, session_id=session_1)});",
)
assert outcome[:2] == ("P0002", "session_item_not_found"), outcome

_plan_2, session_2, item_2 = setup_race(2)
outcome = race(
    "k13b",
    f"""select public.delete_session(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_2)}::uuid,
      p_base_version => {session_version(session_2)}
    );""",
    "perform public.set_session_item_key("
    f"{key_args(item_2, 1, 'set', 2, session_id=session_2)});",
)
assert outcome[:2] == ("P0002", "session_item_not_found"), outcome

_plan_3, session_3, item_3 = setup_race(3)
outcome = race(
    "k13c",
    "select public.set_session_item_key("
    f"{key_args(item_3, 1, 'set', 2, session_id=session_3)});",
    "perform public.set_session_item_key("
    f"{key_args(item_3, 1, 'set', 3, session_id=session_3)});",
)
assert outcome == (
    "P0001",
    "session_item_version_conflict",
    "expected base_version 1 but found current version 2",
), outcome
assert key_of(item_state(item_3)) == (2, 2, None)

# K13d: key edits of two different items of one plan still serialize on the
# plan row (ADR-038 lock order). Without the step-4 plan lock the waiter
# would not block at all, and race() would fail.
_plan_4, session_4, item_4 = setup_race(4)
item_4b = "e6000000-0000-0000-0000-000000000044"
add_song_item(session_4, item_4b, song_x)
outcome = race(
    "k13d",
    "select public.set_session_item_key("
    f"{key_args(item_4, 1, 'set', 2, session_id=session_4)});",
    "perform public.set_session_item_key("
    f"{key_args(item_4b, 0, 'set', 3, session_id=session_4)});",
)
assert outcome == (
    "P0001",
    "session_item_version_conflict",
    "expected base_version 0 but found current version 1",
), outcome

print("session item key contract verification passed")
PY
````

- [ ] **Step 2: Wire it into the backend contract gate**

In `scripts/backend-write-contracts.sh`, directly after these lines:

```bash
planning_cascade_delete_test_script="${PLANNING_CASCADE_DELETE_TEST_SCRIPT:-./scripts/tests/planning-cascade-delete-contract-test.sh}"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$planning_cascade_delete_test_script"
```

add:

```bash

session_item_key_test_script="${SESSION_ITEM_KEY_TEST_SCRIPT:-./scripts/tests/session-item-key-contract-test.sh}"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$session_item_key_test_script"
```

- [ ] **Step 3: Run the suite and see it fail for the right reason**

Run: `bash scripts/tests/session-item-key-contract-test.sh`
Expected: FAIL at K1 with `psql failed` and a stderr line like
`function public.set_session_item_key(uuid, uuid, uuid, bigint, text, integer, text, integer) does not exist`.
Any other failure (bootstrap, fixtures, a Python error) is a harness bug: fix
it before going on.

- [ ] **Step 4: Prove the fixture half runs**

Temporarily comment out the K1 block, rerun the suite, and confirm it now
fails at the first fixture or K11 statement that touches the missing columns
(`column "transpose" does not exist`), not earlier. Restore the K1 block.
This shows the fixtures themselves are valid against the current schema.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/session-item-key-contract-test.sh scripts/backend-write-contracts.sh
git commit -m "test(planning): session item key contract suite, red (S3 PR 1)"
```

(End the commit message with the repository's `Co-Authored-By` line.)

---

### Task 2: Migration, green

**Files:**
- Create: `supabase/migrations/202610130001_session_item_key.sql`
- Test: `scripts/tests/session-item-key-contract-test.sh` (from Task 1)

**Interfaces:**
- Consumes: `public.has_capability(uuid, text, uuid)`,
  `public.bump_plan_content_version(uuid, uuid)` (both existing).
- Produces: the columns and the RPC exactly as in Global Constraints; PR 2's
  client calls the RPC by these parameter names.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/202610130001_session_item_key.sql`:

```sql
-- Session item key: the shared plan layer of the song key (S3 PR 1).
-- Spec: docs/specs/2026-10-13-personal-song-settings.md (PS10-PS13);
-- ADR-042; ADR-038 amendment of 2026-10-13.
--
-- A song item's transpose and capo are what everyone who opens the song from
-- this plan sees; null falls through to the song's ChordPro base. Only
-- set_session_item_key writes them. It versions a key edit on
-- session_items.version (no other RPC bumps it), bumps the plan's
-- content_version like every child write, and leaves sessions.version alone:
-- a key is not session structure.

alter table public.session_items
  add column transpose smallint,
  add column capo smallint;

alter table public.session_items
  add constraint session_items_transpose_range_check
    check (transpose between -11 and 11),
  add constraint session_items_capo_range_check
    check (capo between 0 and 11);

create function public.set_session_item_key(
  p_organization_id uuid,
  p_session_id uuid,
  p_session_item_id uuid,
  p_base_version bigint,
  p_transpose_mode text,
  p_transpose integer,
  p_capo_mode text,
  p_capo integer
)
returns table (
  id uuid,
  plan_id uuid,
  session_id uuid,
  organization_id uuid,
  version bigint,
  transpose integer,
  capo integer,
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  existing_item public.session_items%rowtype;
  v_new_transpose smallint;
  v_new_capo smallint;
  v_plan_content_version bigint;
begin
  -- PS12 step 1: validate the payload before reading or locking anything.
  if p_transpose_mode is null
    or p_capo_mode is null
    or p_transpose_mode not in ('keep', 'set', 'clear')
    or p_capo_mode not in ('keep', 'set', 'clear')
    or (
      p_transpose_mode = 'set'
      and (p_transpose is null or p_transpose not between -11 and 11)
    )
    or (p_transpose_mode <> 'set' and p_transpose is not null)
    or (
      p_capo_mode = 'set'
      and (p_capo is null or p_capo not between 0 and 11)
    )
    or (p_capo_mode <> 'set' and p_capo is not null)
  then
    raise exception using
      errcode = '22023',
      message = 'invalid_session_item_key',
      detail = 'Each mode is keep, set or clear; set needs a value in range, keep and clear need null';
  end if;

  -- Step 2: a key edit always names the version it was made against.
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_item_version_conflict',
      detail = 'base_version is required for a session-item key edit';
  end if;

  -- Step 3: the same authorization as every session-item write.
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

  -- Step 4: lock the owning plan row first (ADR-038 lock order), without
  -- bumping it yet, so a no-op can still return without writing.
  perform 1
  from public.plans as plan
  where plan.organization_id = p_organization_id
    and plan.id = existing_session.plan_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'plan_not_found',
      detail = 'The owning plan does not exist in the requested organization';
  end if;

  -- Step 5: re-read the song item after the lock.
  select *
  into existing_item
  from public.session_items as item
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id
    and item.id = p_session_item_id
    and item.item_type = 'song'
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_item_not_found',
      detail = 'The target song item does not exist in the requested session';
  end if;

  v_new_transpose := case p_transpose_mode
    when 'set' then p_transpose::smallint
    when 'clear' then null
    else existing_item.transpose
  end;
  v_new_capo := case p_capo_mode
    when 'set' then p_capo::smallint
    when 'clear' then null
    else existing_item.capo
  end;

  -- Step 6: every affected field already holds the requested value. Return
  -- the current row and write nothing, whatever the base (LF-T5b).
  if v_new_transpose is not distinct from existing_item.transpose
    and v_new_capo is not distinct from existing_item.capo
  then
    select plan.content_version
    into v_plan_content_version
    from public.plans as plan
    where plan.organization_id = p_organization_id
      and plan.id = existing_session.plan_id;

    return query
    select
      existing_item.id,
      existing_session.plan_id,
      existing_item.session_id,
      existing_item.organization_id,
      existing_item.version,
      existing_item.transpose::integer,
      existing_item.capo::integer,
      v_plan_content_version;
    return;
  end if;

  -- Step 7: optimistic concurrency on the item's own version.
  if existing_item.version <> p_base_version then
    raise exception using
      errcode = 'P0001',
      message = 'session_item_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        existing_item.version::text
      );
  end if;

  -- Step 8: write. The session's version is deliberately left alone.
  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  update public.session_items as item
  set
    transpose = v_new_transpose,
    capo = v_new_capo,
    version = item.version + 1,
    base_version = item.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where item.organization_id = p_organization_id
    and item.id = p_session_item_id;

  return query
  select
    item.id,
    existing_session.plan_id,
    item.session_id,
    item.organization_id,
    item.version,
    item.transpose::integer,
    item.capo::integer,
    v_plan_content_version
  from public.session_items as item
  where item.organization_id = p_organization_id
    and item.id = p_session_item_id;
end;
$$;

revoke all on function public.set_session_item_key(
  uuid, uuid, uuid, bigint, text, integer, text, integer
) from public, anon, authenticated;

grant execute on function public.set_session_item_key(
  uuid, uuid, uuid, bigint, text, integer, text, integer
) to authenticated;
```

- [ ] **Step 2: Run the new suite**

Run: `bash scripts/tests/session-item-key-contract-test.sh`
Expected: `session item key contract verification passed`.
If a K-test fails, fix the migration, not the test, unless the test
contradicts the spec; a test that contradicts the spec is a STOP condition.

- [ ] **Step 3: Prove a guard can fail**

Temporarily change step 7's comparison to `existing_item.version <
p_base_version` (so a stale base slips through), run
`./scripts/db-reset.sh >/dev/null && bash scripts/tests/session-item-key-contract-test.sh`,
and confirm K6 fails. Then temporarily remove `for update` from step 4,
reset and rerun, and confirm K13d fails with "waiter finished without
blocking" (K13a–c may still pass: they also block on the item row). Restore
both, reset and rerun until green. (`./scripts/db-reset.sh` re-applies the
migrations from the files, so each temporary edit takes effect.)

- [ ] **Step 4: Run the gates**

Run, in order, each must pass:

```bash
./scripts/check-migrations.sh
./scripts/backend-write-contracts.sh
```

Expected: `db lint` reports no issue in `set_session_item_key`; every suite
prints its "passed" line, including
`session item key contract verification passed` and the direct-table-DML
suite.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202610130001_session_item_key.sql
git commit -m "feat(planning): session item key columns and set_session_item_key RPC (S3 PR 1)"
```

---

### Task 3: Documentation

**Files:**
- Modify: `docs/architecture/decisions/ADR-038-plan-content-version.md`
  (append at the end)
- Modify: `docs/domain/domain-model.md` (`### session_items`)
- Modify: `docs/specs/2026-10-13-personal-song-settings.md` (status note)

**Interfaces:** none (docs only).

- [ ] **Step 1: Append the ADR-038 amendment**

Append to `docs/architecture/decisions/ADR-038-plan-content-version.md`:

```markdown

## Amendment: key edits (2026-10-13, S3)

Spec: `docs/specs/2026-10-13-personal-song-settings.md` (PS10–PS13); ADR-042;
migration `supabase/migrations/202610130001_session_item_key.sql`.

`set_session_item_key` writes a song item's plan-level `transpose` and `capo`.

- It is a child write. It locks the owning plan row first and bumps
  `plans.content_version` (decision 1; I4 unchanged). A no-op (every affected
  field already holds the requested value) writes and bumps nothing.
- Its optimistic concurrency uses `session_items.version`, which no other RPC
  bumps. Key edits on different items, and a key edit next to a structural
  write in the same session, never conflict.
- It does not bump `sessions.version`. A session's version covers its
  structure (items added, removed, reordered) and its name; a key is not
  structure. A session delete recorded from a view older than a key edit
  therefore still succeeds, while a plan delete recorded from such a view
  conflicts through `content_version`. Accepted: the deleting user removes
  the items they saw, and the key edit added no content they did not see.
- Lock order: plan, then item. It locks no session row.
```

- [ ] **Step 2: Update the domain model**

In `docs/domain/domain-model.md`, `### session_items`:

1. In "Key fields", after `- \`notes\``, insert:

```markdown
- `transpose` (song items: the plan's shared transpose, −11..+11, or null)
- `capo` (song items: the plan's shared capo, 0..11, or null)
```

2. At the end of "Invariants", add:

```markdown
- `transpose` is null or between −11 and +11; `capo` is null or between 0 and 11.
- Only `set_session_item_key` writes `transpose` and `capo`, and only on song items; `version` counts those key edits, while structural item writes version the owning session.
```

3. At the end of "Read-model note", add:

```markdown
- A song item's `transpose` and `capo` are the plan layer of the song key (ADR-042): everyone who opens the song from this plan sees them, and a null field falls through to the song's ChordPro base. They are absolute values, relative to the written chords. The client reads them from S3 PR 2 on.
```

- [ ] **Step 3: Update the spec's status note**

In `docs/specs/2026-10-13-personal-song-settings.md`, replace the first
status line

```markdown
> Status: Accepted (2026-10-13, design gate approved). Not implemented yet;
> delivered in three PRs (see "PR Boundaries"). Amends
```

with

```markdown
> Status: Accepted (2026-10-13, design gate approved). PR 1 (backend)
> implemented on `feat/personal-settings-backend`; PR 2 and PR 3 not yet
> (see "PR Boundaries"). Amends
```

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/decisions/ADR-038-plan-content-version.md docs/domain/domain-model.md docs/specs/2026-10-13-personal-song-settings.md
git commit -m "docs(planning): record session item key edits in ADR-038 and the domain model"
```

---

### Task 4: Full verification, review, PR

**Files:** none new.

- [ ] **Step 1: Full repository gate**

Run: `./scripts/verify.sh`
Expected: PASS (it includes the Flutter suite and the backend contract gate).
PR 1 changes no Dart code; a Flutter failure here is a STOP condition, not
something to fix in this PR.

- [ ] **Step 2: One adversarial whole-diff review**

Dispatch one reviewer (most capable model, caveman ultra report) over
`git diff c713872..HEAD -- supabase scripts` with this single claim to
disprove: "There is a sequence of calls, as any authenticated user, that
makes `set_session_item_key` write a value outside the range, write an item
the caller may not edit, write without bumping `plans.content_version`, bump
anything on a no-op, or succeed over a stale base with a differing value."
Fix confirmed findings with a red test first; rerun Task 2 Step 4.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin feat/personal-settings-backend
gh pr create --base main --title "feat(planning): session item key RPC and contract suite (S3 PR 1)" --body-file "$PR_BODY_FILE"
```

`$PR_BODY_FILE` is a Markdown file you write in your scratchpad first. The PR
body states: the docs commits (roadmap scope change, spec, ADR-042,
2026-04-01 amendment); the migration and the RPC; K1–K15; that no client
code changes; and the hosted deploy steps of Step 4 as a merge checklist.
End it with the repository's `🤖 Generated with [Claude Code](https://claude.com/claude-code)` line.

- [ ] **Step 4: Hand off the hosted deploy (user action, after merge)**

Not done by the executor. Tell the user, after merge and before any PR 2
build:

1. In the Supabase SQL editor, run the contents of
   `supabase/migrations/202610130001_session_item_key.sql` between `begin;`
   and `commit;`. Never `supabase db push`.
2. Run this read-only check; expect two rows, two constraint names, and
   `t | search_path=public | t | f | postgres`:

```sql
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'session_items'
  and column_name in ('transpose', 'capo')
order by column_name;

select conname
from pg_constraint
where conname in (
  'session_items_transpose_range_check',
  'session_items_capo_range_check'
)
order by conname;

select
  p.prosecdef,
  array_to_string(p.proconfig, ','),
  has_function_privilege('authenticated', p.oid, 'execute'),
  has_function_privilege('anon', p.oid, 'execute'),
  pg_get_userbyid(p.proowner)
from pg_proc as p
where p.oid = 'public.set_session_item_key(uuid, uuid, uuid, bigint, text, integer, text, integer)'::regprocedure;
```

3. Re-run the D8 read-only check of
   `docs/specs/2026-10-01-direct-table-dml-lockdown.md`.

- [ ] **Step 5: STOP**

Report the PR link, CI status and the deploy checklist. Do not start PR 2.
