#!/usr/bin/env bash
set -euo pipefail

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


def run_psql(sql: str, user_id: str | None = None) -> str:
    if user_id is not None:
        sql = dedent(
            f"""
            do $$
            begin
              perform set_config('request.jwt.claim.sub', {sql_quote(user_id)}, true);
              perform set_config('request.jwt.claim.role', 'authenticated', true);
            end $$;
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
# Plan content version + cascading delete contract
# docs/specs/2026-09-29-plan-delete-and-session-cascade.md, tests B1-B8.
# Runs after planning-write-contract-test.sh on the same database, so every
# id here uses its own c1/c2 prefix.
# ---------------------------------------------------------------------------

import threading
import time

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

    def run_waiter() -> None:
        try:
            result.append(
                capture_error(
                    waiter_sql + f"\n-- race-waiter-{tag}", user_id=demo_user_id
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

# B3 (cont.): a foreign create_session makes p_base_content_version stale.
plan_r = "c3000000-0000-0000-0000-000000000001"
session_r = "c3000000-0000-0000-0000-00000000000a"

created_r = call(
    "create_plan",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_r)}::uuid,
    p_slug => 'cascade-foreign-write',
    p_name => 'Cascade Foreign Write',
    p_description => null,
    p_scheduled_for => null
    """,
)
assert created_r["version"] == 1, created_r
assert created_r["content_version"] == 1, created_r
call(
    "create_session",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_r)}::uuid,
    p_session_id => {sql_quote(session_r)}::uuid,
    p_slug => 'cascade-r',
    p_name => 'Cascade R'
    """,
)
assert call_error(
    "delete_plan",
    f"""
    p_organization_id => {org},
    p_plan_id => {sql_quote(plan_r)}::uuid,
    p_base_version => 1,
    p_base_content_version => 1
    """,
) == ("P0001", "plan_version_conflict")
assert row_count(
    f"select count(*) from public.plans where id = {sql_quote(plan_r)}::uuid;"
) == 1

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

# --- B8: races under the plan lock yield the sequential error ------------
# Every function reads its session or plan before it waits on the plan lock
# (I5). When another write commits during that wait, the pre-lock read is
# stale, and the outcome must still be the error a sequential call would give.


def setup_race_plan(n: int, with_item: bool = False) -> tuple[str, str, str]:
    plan_id = f"c4000000-0000-0000-0000-0000000000{n}1"
    session_id = f"c4000000-0000-0000-0000-0000000000{n}2"
    item_id = f"c4000000-0000-0000-0000-0000000000{n}3"

    created = call(
        "create_plan",
        f"""
        p_organization_id => {org},
        p_plan_id => {sql_quote(plan_id)}::uuid,
        p_slug => 'race-r{n}',
        p_name => 'Race R{n}',
        p_description => null,
        p_scheduled_for => null
        """,
    )
    assert created["version"] == 1, created
    assert created["content_version"] == 1, created

    created_session = call(
        "create_session",
        f"""
        p_organization_id => {org},
        p_plan_id => {sql_quote(plan_id)}::uuid,
        p_session_id => {sql_quote(session_id)}::uuid,
        p_slug => 'race-r{n}-s',
        p_name => 'Race R{n} S'
        """,
    )
    assert created_session["version"] == 1, created_session
    assert created_session["plan_content_version"] == 2, created_session

    if with_item:
        added = call(
            "create_song_session_item",
            f"""
            p_organization_id => {org},
            p_session_id => {sql_quote(session_id)}::uuid,
            p_session_item_id => {sql_quote(item_id)}::uuid,
            p_song_id => {sql_quote(seed_song_id)}::uuid,
            p_base_version => 1,
            p_position => null
            """,
        )
        assert added["version"] == 2, added
        assert added["plan_content_version"] == 3, added

    return plan_id, session_id, item_id


def session_version(session_id: str) -> int:
    return int(
        run_psql(
            "select version from public.sessions "
            f"where id = {sql_quote(session_id)}::uuid;"
        )
    )


def create_item_args(session_id: str, item_id: str, base_version: int) -> str:
    return f"""
        p_organization_id => {org},
        p_session_id => {sql_quote(session_id)}::uuid,
        p_session_item_id => {sql_quote(item_id)}::uuid,
        p_song_id => {sql_quote(seed_song_id)}::uuid,
        p_base_version => {base_version},
        p_position => null
    """


# R1: a rename commits while delete_empty_session waits -> version conflict.
plan_1, session_1, item_1 = setup_race_plan(1)
outcome = race(
    "r1",
    f"""select public.rename_session(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_1)}::uuid,
      p_base_version => 1,
      p_name => 'Race renamed'
    );""",
    f"""perform public.delete_empty_session(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_1)}::uuid,
      p_base_version => 1
    );""",
)
assert outcome == (
    "P0001",
    "session_version_conflict",
    "expected base_version 1 but found current version 2",
), outcome
assert session_version(session_1) == 2
assert plan_content_version(plan_1) == 3

# R2: an item create commits while delete_empty_session waits -> version
# conflict, not session_delete_blocked_not_empty.
plan_2, session_2, item_2 = setup_race_plan(2)
outcome = race(
    "r2",
    f"select public.create_song_session_item({create_item_args(session_2, item_2, 1)});",
    f"""perform public.delete_empty_session(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_2)}::uuid,
      p_base_version => 1
    );""",
)
assert outcome == (
    "P0001",
    "session_version_conflict",
    "expected base_version 1 but found current version 2",
), outcome
assert session_version(session_2) == 2
assert plan_content_version(plan_2) == 3

# R3: the session is deleted while rename_session waits -> session_not_found.
plan_3, session_3, item_3 = setup_race_plan(3)
outcome = race(
    "r3",
    f"""select public.delete_session(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_3)}::uuid,
      p_base_version => 1
    );""",
    f"""perform public.rename_session(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_3)}::uuid,
      p_base_version => 1,
      p_name => 'Too late'
    );""",
)
assert outcome[:2] == ("P0002", "session_not_found"), outcome

# R4: the session is deleted while delete_session_item waits.
plan_4, session_4, item_4 = setup_race_plan(4, with_item=True)
outcome = race(
    "r4",
    f"""select public.delete_session(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_4)}::uuid,
      p_base_version => 2
    );""",
    f"""perform public.delete_session_item(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_4)}::uuid,
      p_session_item_id => {sql_quote(item_4)}::uuid,
      p_base_version => 2
    );""",
)
assert outcome[:2] == ("P0002", "session_not_found"), outcome

# R5: the plan is deleted while reorder_plan_sessions waits -> plan_not_found.
plan_5, session_5, item_5 = setup_race_plan(5)
outcome = race(
    "r5",
    f"""select public.delete_plan(
      p_organization_id => {org},
      p_plan_id => {sql_quote(plan_5)}::uuid,
      p_base_version => 1,
      p_base_content_version => 2
    );""",
    f"""perform public.reorder_plan_sessions(
      p_organization_id => {org},
      p_plan_id => {sql_quote(plan_5)}::uuid,
      p_base_version => 1,
      p_session_ids => array[{sql_quote(session_5)}::uuid]
    );""",
)
assert outcome[:2] == ("P0002", "plan_not_found"), outcome

# R6: the session is deleted while create_song_session_item waits.
plan_6, session_6, item_6 = setup_race_plan(6)
outcome = race(
    "r6",
    f"""select public.delete_session(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_6)}::uuid,
      p_base_version => 1
    );""",
    f"perform public.create_song_session_item({create_item_args(session_6, item_6, 1)});",
)
assert outcome[:2] == ("P0002", "session_not_found"), outcome

# R7: the session is deleted while reorder_session_items waits.
plan_7, session_7, item_7 = setup_race_plan(7, with_item=True)
outcome = race(
    "r7",
    f"""select public.delete_session(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_7)}::uuid,
      p_base_version => 2
    );""",
    f"""perform public.reorder_session_items(
      p_organization_id => {org},
      p_session_id => {sql_quote(session_7)}::uuid,
      p_base_version => 2,
      p_session_item_ids => array[{sql_quote(item_7)}::uuid]
    );""",
)
assert outcome[:2] == ("P0002", "session_not_found"), outcome

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
