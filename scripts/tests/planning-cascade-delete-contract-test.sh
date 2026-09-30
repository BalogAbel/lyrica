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
