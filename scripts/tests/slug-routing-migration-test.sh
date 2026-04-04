#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

./scripts/supabase.sh start >/dev/null
./scripts/db-reset.sh >/dev/null

db_container_name="$(
  docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1
)"

if [[ -z "$db_container_name" ]]; then
  echo "Could not find the local Supabase database container." >&2
  exit 1
fi

python3 - <<'PY' "$db_container_name"
import json
import subprocess
import sys

container_name = sys.argv[1]


def psql(sql: str) -> str:
    return subprocess.check_output(
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
            "-At",
            "-c",
            sql,
        ],
        text=True,
    ).strip()


def expect(actual: str, expected: str, label: str) -> None:
    if actual != expected:
        raise SystemExit(f"{label} mismatch:\nexpected: {expected!r}\nactual:   {actual!r}")


expect(
    psql(
        """
        select count(*)
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'songs'
          and column_name = 'slug';
        """
    ),
    "1",
    "songs slug column",
)
expect(
    psql(
        """
        select count(*)
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'plans'
          and column_name = 'slug';
        """
    ),
    "1",
    "plans slug column",
)
expect(
    psql(
        """
        select count(*)
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'sessions'
          and column_name = 'slug';
        """
    ),
    "1",
    "sessions slug column",
)

expect(
    psql(
        """
        select string_agg(slug, ',' order by title)
        from public.songs
        where organization_id = '11111111-1111-1111-1111-111111111111';
        """
    ),
    "a-forrasnal,a-mi-istenunk-leborulok-elotted,egy-ut",
    "seed song slugs",
)
expect(
    psql(
        """
        select string_agg(slug, ',' order by name)
        from public.plans
        where organization_id = '11111111-1111-1111-1111-111111111111';
        """
    ),
    "evening-gathering,sunday-morning,team-rehearsal",
    "seed plan slugs",
)
expect(
    psql(
        """
        select string_agg(slug, ',' order by name)
        from public.sessions
        where plan_id = '44444444-4444-4444-4444-444444444442';
        """
    ),
    "run-through,warm-up",
    "seed session slugs",
)

for table_name, constraint_name in [
    ("songs", "songs_organization_slug_unique"),
    ("plans", "plans_organization_slug_unique"),
    ("sessions", "sessions_plan_slug_unique"),
]:
    expect(
        psql(
            f"""
            select count(*)
            from information_schema.table_constraints
            where table_schema = 'public'
              and table_name = '{table_name}'
              and constraint_type = 'UNIQUE'
              and constraint_name = '{constraint_name}';
            """
        ),
        "1",
        f"{table_name} unique constraint",
    )

PY
