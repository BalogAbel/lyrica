#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

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


def create_plan(
    *,
    plan_id: str,
    slug: str,
    name: str,
    description: str | None,
    scheduled_for: str | None,
    user_id: str | None = None,
) -> dict:
    return fetch_json(
        dedent(
            f"""
            select to_jsonb(public.create_plan(
              p_organization_id => {sql_quote(organization_id)},
              p_plan_id => {sql_quote(plan_id)}::uuid,
              p_slug => {sql_quote(slug)},
              p_name => {sql_quote(name)},
              p_description => {sql_quote(description)},
              p_scheduled_for => {sql_quote(scheduled_for)}::timestamptz
            ));
            """
        ),
        user_id=user_id,
    )


def update_plan_fields(
    *,
    plan_id: str,
    base_version: int,
    name: str,
    description: str | None,
    scheduled_for: str | None,
    user_id: str | None = None,
) -> dict:
    return fetch_json(
        dedent(
            f"""
            select to_jsonb(public.update_plan_fields(
              p_organization_id => {sql_quote(organization_id)},
              p_plan_id => {sql_quote(plan_id)}::uuid,
              p_base_version => {base_version},
              p_name => {sql_quote(name)},
              p_description => {sql_quote(description)},
              p_scheduled_for => {sql_quote(scheduled_for)}::timestamptz
            ));
            """
        ),
        user_id=user_id,
    )


def create_session(
    *,
    session_id: str,
    plan_id: str,
    slug: str,
    name: str,
    user_id: str | None = None,
) -> dict:
    return fetch_json(
        dedent(
            f"""
            select to_jsonb(public.create_session(
              p_organization_id => {sql_quote(organization_id)},
              p_plan_id => {sql_quote(plan_id)}::uuid,
              p_session_id => {sql_quote(session_id)}::uuid,
              p_slug => {sql_quote(slug)},
              p_name => {sql_quote(name)}
            ));
            """
        ),
        user_id=user_id,
    )


def rename_session(
    *,
    session_id: str,
    base_version: int,
    name: str,
    user_id: str | None = None,
) -> dict:
    return fetch_json(
        dedent(
            f"""
            select to_jsonb(public.rename_session(
              p_organization_id => {sql_quote(organization_id)},
              p_session_id => {sql_quote(session_id)}::uuid,
              p_base_version => {base_version},
              p_name => {sql_quote(name)}
            ));
            """
        ),
        user_id=user_id,
    )


def delete_empty_session(
    *,
    session_id: str,
    base_version: int,
    user_id: str | None = None,
) -> dict:
    return fetch_json(
        dedent(
            f"""
            select to_jsonb(public.delete_empty_session(
              p_organization_id => {sql_quote(organization_id)},
              p_session_id => {sql_quote(session_id)}::uuid,
              p_base_version => {base_version}
            ));
            """
        ),
        user_id=user_id,
    )


created_plan = create_plan(
    plan_id="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    slug="weekend-service",
    name="Weekend Service",
    description="Initial draft",
    scheduled_for="2026-04-12T09:00:00Z",
    user_id=demo_user_id,
)
assert created_plan["id"] == "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
assert created_plan["organization_id"] == organization_id
assert created_plan["group_id"] is None
assert created_plan["slug"] == "weekend-service"
assert created_plan["version"] == 1

conflicting_plan = create_plan(
    plan_id="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
    slug="weekend-service",
    name="Weekend Service",
    description=None,
    scheduled_for=None,
    user_id=demo_user_id,
)
assert conflicting_plan["slug"] == "weekend-service-2"

updated_plan = update_plan_fields(
    plan_id=created_plan["id"],
    base_version=created_plan["version"],
    name="Weekend Service Updated",
    description="Adjusted description",
    scheduled_for="2026-04-13T09:00:00Z",
    user_id=demo_user_id,
)
assert updated_plan["version"] == 2
assert updated_plan["name"] == "Weekend Service Updated"

plan_conflict = capture_error(
    dedent(
        f"""
        perform public.update_plan_fields(
          p_organization_id => {sql_quote(organization_id)},
          p_plan_id => {sql_quote(created_plan["id"])}::uuid,
          p_base_version => 1,
          p_name => 'Stale write',
          p_description => null,
          p_scheduled_for => null
        );
        """
    ),
    user_id=demo_user_id,
)
assert plan_conflict[0] == "P0001"
assert plan_conflict[1] == "plan_version_conflict"

plan_auth_error = capture_error(
    dedent(
        f"""
        perform public.create_plan(
          p_organization_id => {sql_quote(organization_id)},
          p_plan_id => 'cccccccc-cccc-cccc-cccc-cccccccccccc'::uuid,
          p_slug => 'blocked-plan',
          p_name => 'Blocked plan',
          p_description => null,
          p_scheduled_for => null
        );
        """
    ),
    user_id=blocked_user_id,
)
assert plan_auth_error[0] == "42501"
assert plan_auth_error[1] == "plan_write_not_authorized"

blocked_plan_update = capture_error(
    dedent(
        f"""
        perform public.update_plan_fields(
          p_organization_id => {sql_quote(organization_id)},
          p_plan_id => {sql_quote(created_plan["id"])}::uuid,
          p_base_version => {updated_plan["version"]},
          p_name => 'Blocked update',
          p_description => null,
          p_scheduled_for => null
        );
        """
    ),
    user_id=blocked_user_id,
)
assert blocked_plan_update[0] == "P0002"
assert blocked_plan_update[1] == "plan_not_found"

created_session = create_session(
    session_id="dddddddd-dddd-dddd-dddd-dddddddddddd",
    plan_id=created_plan["id"],
    slug="welcome",
    name="Welcome",
    user_id=demo_user_id,
)
assert created_session["id"] == "dddddddd-dddd-dddd-dddd-dddddddddddd"
assert created_session["plan_id"] == created_plan["id"]
assert created_session["slug"] == "welcome"
assert created_session["position"] == 1
assert created_session["version"] == 1

duplicate_session = create_session(
    session_id="eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
    plan_id=created_plan["id"],
    slug="welcome",
    name="Welcome",
    user_id=demo_user_id,
)
assert duplicate_session["slug"] == "welcome-2"
assert duplicate_session["position"] == 2

renamed_session = rename_session(
    session_id=created_session["id"],
    base_version=created_session["version"],
    name="Welcome Team",
    user_id=demo_user_id,
)
assert renamed_session["name"] == "Welcome Team"
assert renamed_session["version"] == 2

session_conflict = capture_error(
    dedent(
        f"""
        perform public.rename_session(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_base_version => 1,
          p_name => 'Stale rename'
        );
        """
    ),
    user_id=demo_user_id,
)
assert session_conflict[0] == "P0001"
assert session_conflict[1] == "session_version_conflict"

blocked_session_rename = capture_error(
    dedent(
        f"""
        perform public.rename_session(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_base_version => {renamed_session["version"]},
          p_name => 'Blocked rename'
        );
        """
    ),
    user_id=blocked_user_id,
)
assert blocked_session_rename[0] == "P0002"
assert blocked_session_rename[1] == "session_not_found"

run_psql(
    dedent(
        f"""
        insert into public.session_items (
          id,
          organization_id,
          session_id,
          song_id,
          item_type,
          position
        )
        values (
          'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid,
          {sql_quote(organization_id)}::uuid,
          {sql_quote(created_session["id"])}::uuid,
          '33333333-3333-3333-3333-333333333333'::uuid,
          'song',
          1
        );
        """
    ),
    user_id=demo_user_id,
)

session_not_empty = capture_error(
    dedent(
        f"""
        perform public.delete_empty_session(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_base_version => {renamed_session["version"]}
        );
        """
    ),
    user_id=demo_user_id,
)
assert session_not_empty[0] == "P0001"
assert session_not_empty[1] == "session_delete_blocked_not_empty"

delete_conflict = capture_error(
    dedent(
        f"""
        perform public.delete_empty_session(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(duplicate_session["id"])}::uuid,
          p_base_version => 999
        );
        """
    ),
    user_id=demo_user_id,
)
assert delete_conflict[0] == "P0001"
assert delete_conflict[1] == "session_version_conflict"

deleted_session = delete_empty_session(
    session_id=duplicate_session["id"],
    base_version=duplicate_session["version"],
    user_id=demo_user_id,
)
assert deleted_session["id"] == duplicate_session["id"]
assert deleted_session["deleted"] is True

deleted_missing = capture_error(
    dedent(
        f"""
        perform public.delete_empty_session(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(duplicate_session["id"])}::uuid,
          p_base_version => {duplicate_session["version"]}
        );
        """
    ),
    user_id=demo_user_id,
)
assert deleted_missing[0] == "P0002"
assert deleted_missing[1] == "session_not_found"

blocked_session_delete = capture_error(
    dedent(
        f"""
        perform public.delete_empty_session(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_base_version => {renamed_session["version"]}
        );
        """
    ),
    user_id=blocked_user_id,
)
assert blocked_session_delete[0] == "P0002"
assert blocked_session_delete[1] == "session_not_found"

session_auth_error = capture_error(
    dedent(
        f"""
        perform public.create_session(
          p_organization_id => {sql_quote(organization_id)},
          p_plan_id => {sql_quote(created_plan["id"])}::uuid,
          p_session_id => '99999999-9999-9999-9999-999999999999'::uuid,
          p_slug => 'blocked-session',
          p_name => 'Blocked session'
        );
        """
    ),
    user_id=blocked_user_id,
)
assert session_auth_error[0] == "P0002"
assert session_auth_error[1] == "plan_not_found"

print("planning write contract verification passed")
PY
