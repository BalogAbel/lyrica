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


def reorder_plan_sessions(
    *,
    plan_id: str,
    base_version: int,
    session_ids: list[str],
    user_id: str | None = None,
) -> dict:
    session_ids_sql = ", ".join(f"{sql_quote(session_id)}::uuid" for session_id in session_ids)
    return fetch_json(
        dedent(
            f"""
            select to_jsonb(public.reorder_plan_sessions(
              p_organization_id => {sql_quote(organization_id)},
              p_plan_id => {sql_quote(plan_id)}::uuid,
              p_base_version => {base_version},
              p_session_ids => array[{session_ids_sql}]
            ));
            """
        ),
        user_id=user_id,
    )


def create_song_session_item(
    *,
    session_id: str,
    session_item_id: str,
    song_id: str,
    base_version: int,
    position: int | None = None,
    user_id: str | None = None,
) -> dict:
    return fetch_json(
        dedent(
            f"""
            select to_jsonb(public.create_song_session_item(
              p_organization_id => {sql_quote(organization_id)},
              p_session_id => {sql_quote(session_id)}::uuid,
              p_session_item_id => {sql_quote(session_item_id)}::uuid,
              p_song_id => {sql_quote(song_id)}::uuid,
              p_base_version => {base_version},
              p_position => {position if position is not None else 'null'}
            ));
            """
        ),
        user_id=user_id,
    )


def delete_session_item(
    *,
    session_id: str,
    session_item_id: str,
    base_version: int,
    user_id: str | None = None,
) -> dict:
    return fetch_json(
        dedent(
            f"""
            select to_jsonb(public.delete_session_item(
              p_organization_id => {sql_quote(organization_id)},
              p_session_id => {sql_quote(session_id)}::uuid,
              p_session_item_id => {sql_quote(session_item_id)}::uuid,
              p_base_version => {base_version}
            ));
            """
        ),
        user_id=user_id,
    )


def reorder_session_items(
    *,
    session_id: str,
    base_version: int,
    session_item_ids: list[str],
    user_id: str | None = None,
) -> dict:
    item_ids_sql = ", ".join(f"{sql_quote(item_id)}::uuid" for item_id in session_item_ids)
    return fetch_json(
        dedent(
            f"""
            select to_jsonb(public.reorder_session_items(
              p_organization_id => {sql_quote(organization_id)},
              p_session_id => {sql_quote(session_id)}::uuid,
              p_base_version => {base_version},
              p_session_item_ids => array[{item_ids_sql}]
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

run_psql(
    dedent(
        f"""
        update public.sessions
        set position = case id
          when {sql_quote(created_session["id"])}::uuid then 2400
          when {sql_quote(duplicate_session["id"])}::uuid then 1200
        end
        where organization_id = {sql_quote(organization_id)}::uuid
          and id in (
            {sql_quote(created_session["id"])}::uuid,
            {sql_quote(duplicate_session["id"])}::uuid
          );
        """
    )
)

reordered_sessions = reorder_plan_sessions(
    plan_id=created_plan["id"],
    base_version=updated_plan["version"],
    session_ids=[duplicate_session["id"], created_session["id"]],
    user_id=demo_user_id,
)
assert reordered_sessions["plan_id"] == created_plan["id"]
assert reordered_sessions["version"] == 3
assert reordered_sessions["ordered_session_ids"] == [
    duplicate_session["id"],
    created_session["id"],
]
assert reordered_sessions["ordered_session_positions"] == [1, 2]

session_reorder_duplicate = capture_error(
    dedent(
        f"""
        perform public.reorder_plan_sessions(
          p_organization_id => {sql_quote(organization_id)},
          p_plan_id => {sql_quote(created_plan["id"])}::uuid,
          p_base_version => {reordered_sessions["version"]},
          p_session_ids => array[
            {sql_quote(duplicate_session["id"])}::uuid,
            {sql_quote(duplicate_session["id"])}::uuid
          ]
        );
        """
    ),
    user_id=demo_user_id,
)
assert session_reorder_duplicate[0] == "P0001"
assert session_reorder_duplicate[1] == "session_reorder_blocked_invalid_permutation"

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
        insert into public.songs (
          id,
          organization_id,
          slug,
          title,
          chordpro_source
        )
        values (
          '44444444-4444-4444-4444-444444444444'::uuid,
          {sql_quote(organization_id)}::uuid,
          'beta',
          'Beta',
          '{{title: Beta}}'
        );
        """
    ),
)

run_psql(
    dedent(
        """
        insert into public.organizations (id, name, slug)
        values (
          '66666666-6666-6666-6666-666666666666'::uuid,
          'Alternate Hidden Organization',
          'alternate-hidden-organization'
        );
        insert into public.songs (
          id,
          organization_id,
          slug,
          title,
          chordpro_source
        )
        values (
          '77777777-7777-7777-7777-777777777777'::uuid,
          '66666666-6666-6666-6666-666666666666'::uuid,
          'hidden-song',
          'Hidden Song',
          '{title: Hidden Song}'
        );
        """
    )
)

created_item = create_song_session_item(
    session_id=created_session["id"],
    session_item_id="ffffffff-ffff-ffff-ffff-ffffffffffff",
    song_id="33333333-3333-3333-3333-333333333333",
    base_version=renamed_session["version"],
    position=1,
    user_id=demo_user_id,
)
assert created_item["id"] == "ffffffff-ffff-ffff-ffff-ffffffffffff"
assert created_item["session_id"] == created_session["id"]
assert created_item["song_id"] == "33333333-3333-3333-3333-333333333333"
assert created_item["version"] == 3
assert created_item["ordered_session_item_ids"] == [
    "ffffffff-ffff-ffff-ffff-ffffffffffff"
]
assert created_item["ordered_session_item_positions"] == [1]

duplicate_song_error = capture_error(
    dedent(
        f"""
        perform public.create_song_session_item(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_session_item_id => '12121212-1212-1212-1212-121212121212'::uuid,
          p_song_id => '33333333-3333-3333-3333-333333333333'::uuid,
          p_base_version => {created_item["version"]},
          p_position => 2
        );
        """
    ),
    user_id=demo_user_id,
)
assert duplicate_song_error[0] == "P0001"
assert duplicate_song_error[1] == "duplicate_song_in_session_blocked"

song_visibility_error = capture_error(
    dedent(
        f"""
        perform public.create_song_session_item(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_session_item_id => '13131313-1313-1313-1313-131313131313'::uuid,
          p_song_id => '77777777-7777-7777-7777-777777777777'::uuid,
          p_base_version => {created_item["version"]},
          p_position => 2
        );
        """
    ),
    user_id=demo_user_id,
)
assert song_visibility_error[0] == "P0001"
assert song_visibility_error[1] == "song_not_visible_blocked"

second_created_item = create_song_session_item(
    session_id=created_session["id"],
    session_item_id="abababab-abab-abab-abab-abababababab",
    song_id="44444444-4444-4444-4444-444444444444",
    base_version=created_item["version"],
    position=2,
    user_id=demo_user_id,
)
assert second_created_item["version"] == 4
assert second_created_item["ordered_session_item_ids"] == [
    "ffffffff-ffff-ffff-ffff-ffffffffffff",
    "abababab-abab-abab-abab-abababababab",
]
assert second_created_item["ordered_session_item_positions"] == [1, 2]

run_psql(
    dedent(
        """
        update public.session_items
        set position = case id
          when 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid then 3200
          when 'abababab-abab-abab-abab-abababababab'::uuid then 1500
        end
        where organization_id = '11111111-1111-1111-1111-111111111111'::uuid
          and session_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'::uuid
          and id in (
            'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid,
            'abababab-abab-abab-abab-abababababab'::uuid
          );
        """
    )
)

blocked_song_add = capture_error(
    dedent(
        f"""
        perform public.create_song_session_item(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_session_item_id => '14141414-1414-1414-1414-141414141414'::uuid,
          p_song_id => '44444444-4444-4444-4444-444444444444'::uuid,
          p_base_version => {second_created_item["version"]},
          p_position => 3
        );
        """
    ),
    user_id=blocked_user_id,
)
assert blocked_song_add[0] == "P0002"
assert blocked_song_add[1] == "session_not_found"

reordered_items = reorder_session_items(
    session_id=created_session["id"],
    base_version=second_created_item["version"],
    session_item_ids=[
        "abababab-abab-abab-abab-abababababab",
        "ffffffff-ffff-ffff-ffff-ffffffffffff",
    ],
    user_id=demo_user_id,
)
assert reordered_items["version"] == 5
assert reordered_items["ordered_session_item_ids"] == [
    "abababab-abab-abab-abab-abababababab",
    "ffffffff-ffff-ffff-ffff-ffffffffffff",
]
assert reordered_items["ordered_session_item_positions"] == [1, 2]

item_reorder_duplicate = capture_error(
    dedent(
        f"""
        perform public.reorder_session_items(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_base_version => {reordered_items["version"]},
          p_session_item_ids => array[
            'abababab-abab-abab-abab-abababababab'::uuid,
            'abababab-abab-abab-abab-abababababab'::uuid
          ]
        );
        """
    ),
    user_id=demo_user_id,
)
assert item_reorder_duplicate[0] == "P0001"
assert item_reorder_duplicate[1] == "session_item_reorder_blocked_invalid_permutation"

item_reorder_conflict = capture_error(
    dedent(
        f"""
        perform public.reorder_session_items(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_base_version => 4,
          p_session_item_ids => array[
            'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid,
            'abababab-abab-abab-abab-abababababab'::uuid
          ]
        );
        """
    ),
    user_id=demo_user_id,
)
assert item_reorder_conflict[0] == "P0001"
assert item_reorder_conflict[1] == "session_version_conflict"

deleted_item = delete_session_item(
    session_id=created_session["id"],
    session_item_id="abababab-abab-abab-abab-abababababab",
    base_version=reordered_items["version"],
    user_id=demo_user_id,
)
assert deleted_item["id"] == "abababab-abab-abab-abab-abababababab"
assert deleted_item["version"] == 6
assert deleted_item["ordered_session_item_ids"] == [
    "ffffffff-ffff-ffff-ffff-ffffffffffff"
]
assert deleted_item["ordered_session_item_positions"] == [2]

item_delete_conflict = capture_error(
    dedent(
        f"""
        perform public.delete_session_item(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_session_item_id => 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid,
          p_base_version => 5
        );
        """
    ),
    user_id=demo_user_id,
)
assert item_delete_conflict[0] == "P0001"
assert item_delete_conflict[1] == "session_version_conflict"

session_not_empty = capture_error(
    dedent(
        f"""
        perform public.delete_empty_session(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_base_version => {deleted_item["version"]}
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

read_only_user_id = "77777777-7777-7777-7777-777777777777"

run_psql(
    dedent(
        f"""
        insert into auth.users (id, email)
        values ({sql_quote(read_only_user_id)}, 'readonly@lyron.local')
        on conflict (id) do nothing;

        insert into public.memberships (
          user_id,
          organization_id,
          role_code,
          scope_type,
          status
        )
        values (
          {sql_quote(read_only_user_id)}::uuid,
          {sql_quote(organization_id)}::uuid,
          'organization_read_only',
          'organization',
          'active'
        )
        on conflict do nothing;
        """
    )
)

read_only_plan_error = capture_error(
    dedent(
        f"""
        perform public.create_plan(
          p_organization_id => {sql_quote(organization_id)},
          p_plan_id => 'cccccccc-cccc-cccc-cccc-000000000001'::uuid,
          p_slug => 'readonly-plan',
          p_name => 'Read-Only Plan',
          p_description => null,
          p_scheduled_for => null
        );
        """
    ),
    user_id=read_only_user_id,
)
assert read_only_plan_error[0] == "42501", f"expected 42501, got {read_only_plan_error[0]!r}"
assert read_only_plan_error[1] == "plan_write_not_authorized", f"unexpected: {read_only_plan_error[1]!r}"

read_only_session_error = capture_error(
    dedent(
        f"""
        perform public.create_session(
          p_organization_id => {sql_quote(organization_id)},
          p_plan_id => {sql_quote(created_plan["id"])}::uuid,
          p_session_id => 'cccccccc-cccc-cccc-cccc-000000000002'::uuid,
          p_slug => 'readonly-session',
          p_name => 'Read-Only Session'
        );
        """
    ),
    user_id=read_only_user_id,
)
assert read_only_session_error[0] == "P0002", f"expected P0002, got {read_only_session_error[0]!r}"
assert read_only_session_error[1] == "plan_not_found", f"unexpected: {read_only_session_error[1]!r}"

read_only_item_error = capture_error(
    dedent(
        f"""
        perform public.create_song_session_item(
          p_organization_id => {sql_quote(organization_id)},
          p_session_id => {sql_quote(created_session["id"])}::uuid,
          p_session_item_id => 'cccccccc-cccc-cccc-cccc-000000000003'::uuid,
          p_song_id => '33333333-3333-3333-3333-333333333333'::uuid,
          p_base_version => {deleted_item["version"]},
          p_position => null
        );
        """
    ),
    user_id=read_only_user_id,
)
assert read_only_item_error[0] == "P0002", f"expected P0002, got {read_only_item_error[0]!r}"
assert read_only_item_error[1] == "session_not_found", f"unexpected: {read_only_item_error[1]!r}"

# --- Slug suffix overflow (large numeric suffix must not raise 22003) ---
# A name whose slug ends in a number >= 2^31 must create successfully and keep
# its full text slug; a forced collision must fall back to the slug root.
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
# On collision the regex strips the (overflowing) trailing number to the root
# "set" and the fallback slug_number=1 increments to 2, yielding "set-2".
assert overflow_plan_collision["slug"] == "set-2", overflow_plan_collision["slug"]

overflow_session = create_session(
    session_id="a3333333-3333-3333-3333-333333333333",
    plan_id=overflow_plan["id"],
    slug="",
    name="Cue 9999999999999999",
    user_id=demo_user_id,
)
assert overflow_session["slug"] == "cue-9999999999999999", overflow_session["slug"]

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

print("planning write contract verification passed")
PY
