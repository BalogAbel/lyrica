#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

./scripts/supabase.sh start >/dev/null
./scripts/db-reset.sh >/dev/null
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
import time
import subprocess
import sys
from textwrap import dedent

container_name = sys.argv[1]
demo_user_id = sys.argv[2]
blocked_user_id = "88888888-8888-8888-8888-888888888888"
organization_id = "11111111-1111-1111-1111-111111111111"
seed_song_id = "33333333-3333-3333-3333-333333333333"
seed_song_version = 1


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


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def song_source(title: str) -> str:
    return sql_quote("{title:" + title + "}\n[C] " + title)


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


def start_psql(sql: str, user_id: str | None = None) -> subprocess.Popen[str]:
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

    return subprocess.Popen(
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
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


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
        create temp table if not exists song_write_error_capture (
          sqlstate text,
          message text,
          detail text
        );
        truncate song_write_error_capture;
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
            insert into song_write_error_capture values (
              v_sqlstate,
              v_message,
              coalesce(v_detail, '')
            );
          end;
        end $$;
        select sqlstate, message, detail
        from song_write_error_capture
        limit 1;
        """
    )

    row = fetch_row(capture_sql, user_id=user_id)
    if len(row) != 3:
        raise SystemExit(f"unexpected captured error row: {row!r}")
    return row[0], row[1], row[2]


def create_song(
    title: str,
    requested_slug: str | None = None,
    user_id: str | None = None,
) -> dict:
    slug_arg = (
        f", p_requested_slug => {sql_quote(requested_slug)}"
        if requested_slug is not None
        else ""
    )
    return fetch_json(
        dedent(
            f"""
            select to_jsonb(public.create_song(
              p_organization_id => {sql_quote(organization_id)},
              p_title => {sql_quote(title)},
              p_chordpro_source => {song_source(title)}{slug_arg}
            ));
            """
        ),
        user_id=user_id,
    )


def update_song(
    song_id: str,
    base_version: int,
    title: str,
    requested_slug: str | None = None,
    overwrite: bool = False,
    user_id: str | None = None,
) -> dict:
    function_name = "public.overwrite_song_update" if overwrite else "public.update_song"
    slug_arg = (
        f", p_requested_slug => {sql_quote(requested_slug)}"
        if requested_slug is not None and overwrite
        else ""
    )
    return fetch_json(
        dedent(
            f"""
            select to_jsonb({function_name}(
              p_organization_id => {sql_quote(organization_id)},
              p_song_id => {sql_quote(song_id)},
              p_base_version => {base_version},
              p_title => {sql_quote(title)},
              p_chordpro_source => {song_source(title)}{slug_arg}
            ));
            """
        ),
        user_id=user_id,
    )


def delete_song(
    song_id: str,
    base_version: int,
    overwrite: bool = False,
    user_id: str | None = None,
) -> dict:
    function_name = "public.overwrite_song_delete" if overwrite else "public.delete_song"
    return fetch_json(
        dedent(
            f"""
            select to_jsonb({function_name}(
              p_organization_id => {sql_quote(organization_id)},
              p_song_id => {sql_quote(song_id)},
              p_base_version => {base_version}
            ));
            """
        ),
        user_id=user_id,
    )


def assert_equal(actual, expected, label):
    if actual != expected:
        raise SystemExit(f"{label} mismatch:\nexpected: {expected!r}\nactual:   {actual!r}")


def assert_contains(actual: str, expected_fragment: str, label: str) -> None:
    if expected_fragment not in actual:
        raise SystemExit(
            f"{label} missing fragment:\nexpected to contain: {expected_fragment!r}\nactual: {actual!r}"
        )


unauthorized_sql, unauthorized_message, unauthorized_detail = capture_error(
    dedent(
        f"""
        perform public.create_song(
          p_organization_id => {sql_quote(organization_id)},
          p_title => 'Unauthorized Song',
          p_chordpro_source => {song_source('Unauthorized Song')}
        );
        """
    ),
    user_id=blocked_user_id,
)
assert_equal(unauthorized_sql, "42501", "authorization sqlstate")
assert_equal(unauthorized_message, "song_write_not_authorized", "authorization message")
assert "canEditSongs" in unauthorized_detail, unauthorized_detail

first_collision = create_song("Collision Song", "write-contract-collision", user_id=demo_user_id)
assert_equal(first_collision["slug"], "write-contract-collision", "first collision slug")
assert_equal(first_collision["version"], 1, "first collision version")

second_collision = create_song("Collision Song", "write-contract-collision", user_id=demo_user_id)
assert_equal(second_collision["slug"], "write-contract-collision-2", "second collision slug")
assert_equal(second_collision["version"], 1, "second collision version")

collision_row = fetch_json(
    dedent(
        f"""
        select to_jsonb(song)
        from public.songs as song
        where organization_id = {sql_quote(organization_id)}
          and slug = 'write-contract-collision';
        """
    ),
    user_id=demo_user_id,
)
assert_equal(collision_row["slug"], "write-contract-collision", "collision persisted slug")

updatable = create_song("Update Target", "write-contract-update", user_id=demo_user_id)
assert_equal(updatable["slug"], "write-contract-update", "updatable slug")

updated_once = update_song(
    updatable["id"],
    1,
    "Update Target Revised",
    user_id=demo_user_id,
)
assert_equal(updated_once["slug"], "write-contract-update", "update preserves slug")
assert_equal(updated_once["version"], 2, "update version bump")

metadata_target = fetch_json(
    dedent(
        f"""
        with updated as (
          update public.songs
          set
            artist = 'Existing Artist',
            key_signature = 'G',
            tempo_bpm = 96,
            tags = array['worship', 'test']
          where id = {sql_quote(updatable['id'])}
          returning *
        )
        select to_jsonb(updated) from updated;
        """
    ),
    user_id=demo_user_id,
)
assert_equal(metadata_target["artist"], "Existing Artist", "seeded artist")
assert_equal(metadata_target["key_signature"], "G", "seeded key signature")
assert_equal(metadata_target["tempo_bpm"], 96, "seeded tempo")
assert_equal(metadata_target["tags"], ["worship", "test"], "seeded tags")

metadata_preserved = update_song(
    updatable["id"],
    2,
    "Update Target Keeps Metadata",
    user_id=demo_user_id,
)
assert_equal(metadata_preserved["artist"], "Existing Artist", "update preserves artist")
assert_equal(metadata_preserved["key_signature"], "G", "update preserves key signature")
assert_equal(metadata_preserved["tempo_bpm"], 96, "update preserves tempo")
assert_equal(metadata_preserved["tags"], ["worship", "test"], "update preserves tags")
assert_equal(metadata_preserved["version"], 3, "metadata-preserving update version bump")

stale_update_sql, stale_update_message, stale_update_detail = capture_error(
    dedent(
        f"""
        perform public.update_song(
          p_organization_id => {sql_quote(organization_id)},
          p_song_id => {sql_quote(updatable['id'])},
          p_base_version => 1,
          p_title => 'Update Target Stale',
          p_chordpro_source => {song_source('Update Target Stale')}
        );
        """
    ),
    user_id=demo_user_id,
)
assert_equal(stale_update_sql, "P0001", "stale update sqlstate")
assert_equal(stale_update_message, "song_version_conflict", "stale update message")
assert "current version 3" in stale_update_detail, stale_update_detail

atomic_update_target = create_song(
    "Atomic Update Target",
    "write-contract-atomic-update",
    user_id=demo_user_id,
)
run_psql(
    dedent(
        f"""
        create or replace function public.test_song_write_sleep()
        returns trigger
        language plpgsql
        as $$
        begin
          if new.id = {sql_quote(atomic_update_target['id'])}::uuid then
            perform pg_sleep(1.0);
          end if;
          return new;
        end;
        $$;

        drop trigger if exists test_song_write_sleep on public.songs;
        create trigger test_song_write_sleep
        before update on public.songs
        for each row
        execute function public.test_song_write_sleep();
        """
    )
)
try:
    first_update = start_psql(
        dedent(
            f"""
            select to_jsonb(public.update_song(
              p_organization_id => {sql_quote(organization_id)},
              p_song_id => {sql_quote(atomic_update_target['id'])},
              p_base_version => 1,
              p_title => 'Atomic Update Winner',
              p_chordpro_source => {song_source('Atomic Update Winner')}
            ));
            """
        ),
        user_id=demo_user_id,
    )
    time.sleep(0.2)
    stale_concurrent_update = start_psql(
        dedent(
            f"""
            select to_jsonb(public.update_song(
              p_organization_id => {sql_quote(organization_id)},
              p_song_id => {sql_quote(atomic_update_target['id'])},
              p_base_version => 1,
              p_title => 'Atomic Update Loser',
              p_chordpro_source => {song_source('Atomic Update Loser')}
            ));
            """
        ),
        user_id=demo_user_id,
    )

    first_update_stdout, first_update_stderr = first_update.communicate(timeout=15)
    stale_update_stdout, stale_update_stderr = stale_concurrent_update.communicate(timeout=15)

    if first_update.returncode != 0:
        raise SystemExit(
            f"atomic update winner failed unexpectedly:\nstdout:\n{first_update_stdout}\nstderr:\n{first_update_stderr}"
        )
    assert_equal(stale_concurrent_update.returncode, 1, "concurrent stale update should fail")
    assert_contains(stale_update_stderr, "song_version_conflict", "concurrent stale update error")

    atomic_update_row = fetch_json(
        dedent(
            f"""
            select to_jsonb(song)
            from public.songs as song
            where song.organization_id = {sql_quote(organization_id)}
              and song.id = {sql_quote(atomic_update_target['id'])};
            """
        ),
        user_id=demo_user_id,
    )
    assert_equal(atomic_update_row["title"], "Atomic Update Winner", "atomic update preserved winner title")
    assert_equal(atomic_update_row["version"], 2, "atomic update preserved winner version")
finally:
    run_psql(
        dedent(
            """
            drop trigger if exists test_song_write_sleep on public.songs;
            drop function if exists public.test_song_write_sleep();
            """
        )
    )

overwrite_update = update_song(
    updatable["id"],
    2,
    "Update Target Overwritten",
    overwrite=True,
    user_id=demo_user_id,
)
assert_equal(overwrite_update["version"], 4, "overwrite update version bump")
assert_equal(overwrite_update["slug"], "write-contract-update", "overwrite update preserves slug")

dependency_sql, dependency_message, dependency_detail = capture_error(
    dedent(
        f"""
        perform public.delete_song(
          p_organization_id => {sql_quote(organization_id)},
          p_song_id => {sql_quote(seed_song_id)},
          p_base_version => {seed_song_version}
        );
        """
    ),
    user_id=demo_user_id,
)
assert_equal(dependency_sql, "23503", "dependency sqlstate")
assert_equal(
    dependency_message,
    "song_delete_blocked_by_session_items",
    "dependency message",
)
assert "session item" in dependency_detail.lower(), dependency_detail

delete_target = create_song("Delete Target", "write-contract-delete", user_id=demo_user_id)
update_song(delete_target["id"], 1, "Delete Target Revised", user_id=demo_user_id)

stale_delete_sql, stale_delete_message, stale_delete_detail = capture_error(
    dedent(
        f"""
        perform public.delete_song(
          p_organization_id => {sql_quote(organization_id)},
          p_song_id => {sql_quote(delete_target['id'])},
          p_base_version => 1
        );
        """
    ),
    user_id=demo_user_id,
)
assert_equal(stale_delete_sql, "P0001", "stale delete sqlstate")
assert_equal(stale_delete_message, "song_version_conflict", "stale delete message")
assert "current version 2" in stale_delete_detail, stale_delete_detail

remote_deleted_update_target = create_song(
    "Remote Deleted Update Target",
    "write-contract-remote-delete-update",
    user_id=demo_user_id,
)
run_psql(
    dedent(
        f"""
        delete from public.songs
        where organization_id = {sql_quote(organization_id)}
          and id = {sql_quote(remote_deleted_update_target['id'])};
        """
    ),
    user_id=demo_user_id,
)
remote_deleted_update_sql, remote_deleted_update_message, remote_deleted_update_detail = capture_error(
    dedent(
        f"""
        perform public.update_song(
          p_organization_id => {sql_quote(organization_id)},
          p_song_id => {sql_quote(remote_deleted_update_target['id'])},
          p_base_version => 1,
          p_title => 'Remote Deleted Update Target Revised',
          p_chordpro_source => {song_source('Remote Deleted Update Target Revised')}
        );
        """
    ),
    user_id=demo_user_id,
)
assert_equal(remote_deleted_update_sql, "P0002", "remote deleted update sqlstate")
assert_equal(remote_deleted_update_message, "song_not_found", "remote deleted update message")
assert_contains(remote_deleted_update_detail, "does not exist", "remote deleted update detail")

remote_deleted_delete_target = create_song(
    "Remote Deleted Delete Target",
    "write-contract-remote-delete-delete",
    user_id=demo_user_id,
)
run_psql(
    dedent(
        f"""
        delete from public.songs
        where organization_id = {sql_quote(organization_id)}
          and id = {sql_quote(remote_deleted_delete_target['id'])};
        """
    ),
    user_id=demo_user_id,
)
accepted_remote_delete = delete_song(
    remote_deleted_delete_target["id"],
    1,
    user_id=demo_user_id,
)
assert_equal(accepted_remote_delete["id"], remote_deleted_delete_target["id"], "remote deleted delete accepted id")
assert_equal(accepted_remote_delete["organization_id"], organization_id, "remote deleted delete organization")

remote_deleted_recreate_target = create_song(
    "Remote Deleted Recreate Target",
    "write-contract-remote-delete-recreate",
    user_id=demo_user_id,
)
run_psql(
    dedent(
        f"""
        delete from public.songs
        where organization_id = {sql_quote(organization_id)}
          and id = {sql_quote(remote_deleted_recreate_target['id'])};
        """
    ),
    user_id=demo_user_id,
)
recreate_denied_sql, recreate_denied_message, recreate_denied_detail = capture_error(
    dedent(
        f"""
        perform public.overwrite_song_update(
          p_organization_id => {sql_quote(organization_id)},
          p_song_id => {sql_quote(remote_deleted_recreate_target['id'])},
          p_base_version => 1,
          p_title => 'Remote Deleted Recreate Target Blocked',
          p_chordpro_source => {song_source('Remote Deleted Recreate Target Blocked')}
        );
        """
    ),
    user_id=blocked_user_id,
)
assert_equal(recreate_denied_sql, "42501", "remote deleted recreate authorization sqlstate")
assert_equal(recreate_denied_message, "song_write_not_authorized", "remote deleted recreate authorization message")
assert_contains(recreate_denied_detail, "canEditSongs", "remote deleted recreate authorization detail")

slug_claimant = create_song(
    "Slug Claimant",
    "write-contract-remote-delete-recreate",
    user_id=demo_user_id,
)
assert_equal(slug_claimant["slug"], "write-contract-remote-delete-recreate", "slug claimant slug")

recreated_song = update_song(
    remote_deleted_recreate_target["id"],
    1,
    "Remote Deleted Recreate Target Revived",
    requested_slug="write-contract-remote-delete-recreate",
    overwrite=True,
    user_id=demo_user_id,
)
assert_equal(recreated_song["id"], remote_deleted_recreate_target["id"], "remote deleted recreate id")
assert_equal(recreated_song["organization_id"], organization_id, "remote deleted recreate organization")
assert_equal(recreated_song["title"], "Remote Deleted Recreate Target Revived", "remote deleted recreate title")
assert_equal(recreated_song["version"], 1, "remote deleted recreate version")
assert_equal(recreated_song["slug"], "write-contract-remote-delete-recreate-2", "remote deleted recreate canonical slug")

atomic_delete_target = create_song(
    "Atomic Delete Target",
    "write-contract-atomic-delete",
    user_id=demo_user_id,
)
run_psql(
    dedent(
        f"""
        create or replace function public.test_song_write_sleep()
        returns trigger
        language plpgsql
        as $$
        begin
          if new.id = {sql_quote(atomic_delete_target['id'])}::uuid then
            perform pg_sleep(1.0);
          end if;
          return new;
        end;
        $$;

        drop trigger if exists test_song_write_sleep on public.songs;
        create trigger test_song_write_sleep
        before update on public.songs
        for each row
        execute function public.test_song_write_sleep();
        """
    )
)
try:
    winner_update = start_psql(
        dedent(
            f"""
            select to_jsonb(public.update_song(
              p_organization_id => {sql_quote(organization_id)},
              p_song_id => {sql_quote(atomic_delete_target['id'])},
              p_base_version => 1,
              p_title => 'Atomic Delete Winner',
              p_chordpro_source => {song_source('Atomic Delete Winner')}
            ));
            """
        ),
        user_id=demo_user_id,
    )
    time.sleep(0.2)
    stale_concurrent_delete = start_psql(
        dedent(
            f"""
            select to_jsonb(public.delete_song(
              p_organization_id => {sql_quote(organization_id)},
              p_song_id => {sql_quote(atomic_delete_target['id'])},
              p_base_version => 1
            ));
            """
        ),
        user_id=demo_user_id,
    )

    winner_update_stdout, winner_update_stderr = winner_update.communicate(timeout=15)
    stale_delete_stdout, stale_delete_stderr = stale_concurrent_delete.communicate(timeout=15)

    if winner_update.returncode != 0:
        raise SystemExit(
            f"atomic delete winner update failed unexpectedly:\nstdout:\n{winner_update_stdout}\nstderr:\n{winner_update_stderr}"
        )
    assert_equal(stale_concurrent_delete.returncode, 1, "concurrent stale delete should fail")
    assert_contains(stale_delete_stderr, "song_version_conflict", "concurrent stale delete error")

    atomic_delete_row = fetch_json(
        dedent(
            f"""
            select to_jsonb(song)
            from public.songs as song
            where song.organization_id = {sql_quote(organization_id)}
              and song.id = {sql_quote(atomic_delete_target['id'])};
            """
        ),
        user_id=demo_user_id,
    )
    assert_equal(atomic_delete_row["title"], "Atomic Delete Winner", "atomic delete preserved updated row title")
    assert_equal(atomic_delete_row["version"], 2, "atomic delete preserved updated row version")
finally:
    run_psql(
        dedent(
            """
            drop trigger if exists test_song_write_sleep on public.songs;
            drop function if exists public.test_song_write_sleep();
            """
        )
    )

deleted_song = delete_song(delete_target["id"], 1, overwrite=True, user_id=demo_user_id)
assert_equal(deleted_song["id"], delete_target["id"], "overwrite delete id")

delete_lookup = run_psql(
    f"""
    select count(*)
    from public.songs
    where organization_id = {sql_quote(organization_id)}
      and id = {sql_quote(delete_target['id'])};
    """,
    user_id=demo_user_id,
)
assert_equal(delete_lookup, "0", "overwrite delete removal")

attachment_target = create_song("Attachment Target", "write-contract-attachment", user_id=demo_user_id)
run_psql(
    dedent(
        f"""
        insert into public.attachments (
          id,
          organization_id,
          song_id,
          storage_bucket,
          storage_path,
          mime_type,
          file_name
        )
        values (
          gen_random_uuid(),
          {sql_quote(organization_id)},
          {sql_quote(attachment_target['id'])},
          'song-assets',
          'attachments/write-contract-attachment.pdf',
          'application/pdf',
          'write-contract-attachment.pdf'
        );
        """
    ),
    user_id=demo_user_id,
)
deleted_attachment_song = delete_song(attachment_target["id"], 1, user_id=demo_user_id)
assert_equal(
    deleted_attachment_song["id"],
    attachment_target["id"],
    "attachment cascade delete id",
)

attachment_count = run_psql(
    f"""
    select count(*)
    from public.attachments
    where organization_id = {sql_quote(organization_id)}
      and song_id = {sql_quote(attachment_target['id'])};
    """,
    user_id=demo_user_id,
)
assert_equal(attachment_count, "0", "attachment cascade cleanup")

print("song CRUD write contract regression passed")
PY
