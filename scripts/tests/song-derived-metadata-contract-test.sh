#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

if [[ "${BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP:-0}" != "1" ]]; then
  ./scripts/supabase.sh start >/dev/null
  ./scripts/db-reset.sh >/dev/null
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
organization_id = "11111111-1111-1111-1111-111111111111"
failures = []


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


def sql_quote(value) -> str:
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
            "docker", "exec", "-i", container_name, "psql",
            "-U", "postgres", "-d", "postgres",
            "-v", "ON_ERROR_STOP=1", "-X", "-qAt", "-F", "\t",
            "-c", sql,
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(
            f"psql failed:\nSQL:\n{sql}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result.stdout.strip()


def run_psql_rows(sql: str) -> list[list[str]]:
    raw = run_psql(sql)
    return [line.split("\t") for line in raw.splitlines() if line != ""]


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
        create temp table if not exists song_derived_error_capture (
          sqlstate text,
          message text,
          detail text
        );
        truncate song_derived_error_capture;
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
            insert into song_derived_error_capture values (
              v_sqlstate,
              v_message,
              coalesce(v_detail, '')
            );
          end;
        end $$;
        select sqlstate, message, detail
        from song_derived_error_capture
        limit 1;
        """
    )
    row = fetch_row(capture_sql, user_id=user_id)
    if len(row) != 3:
        raise SystemExit(f"unexpected captured error row: {row!r}")
    return row[0], row[1], row[2]


def check(label: str, condition: bool, detail: str = "") -> None:
    if not condition:
        failures.append(f"{label}: {detail}")


# --- Section A: chordpro_scan_directives (Task 3) ---------------------------

def scan(source: str, with_window: bool = False):
    rows = run_psql_rows(
        "select directive_name, coalesce(directive_value, '<null>'), key_window_open "
        f"from public.chordpro_scan_directives({sql_quote(source)}) "
        "order by line_number;"
    )
    parsed = [
        (name, None if value == "<null>" else value, window == "t")
        for name, value, window in rows
    ]
    if with_window:
        return parsed
    return [(name, value) for name, value, _window in parsed]


check(
    "scanner: colon splits name/value",
    scan("{title: My Song}") == [("title", "My Song")],
    str(scan("{title: My Song}")),
)
check(
    "scanner: no colon -> null value",
    scan("{soc}") == [("soc", None)],
    str(scan("{soc}")),
)
check(
    "scanner: empty body is not a directive",
    scan("{}") == [],
    str(scan("{}")),
)
check(
    "scanner: lyric line is not a directive",
    scan("Amazing grace, how sweet the sound") == [],
    str(scan("Amazing grace, how sweet the sound")),
)
check(
    "scanner: \\r\\n normalizes to \\n before scanning",
    scan("{title: A}\r\n{title: B}\r\n") == [("title", "A"), ("title", "B")],
    str(scan("{title: A}\r\n{title: B}\r\n")),
)
check(
    "scanner: name lowercased, value not",
    scan("{TITLE: Case Test}") == [("title", "Case Test")],
    str(scan("{TITLE: Case Test}")),
)
check(
    "scanner: tabs and spaces trimmed around name and value",
    scan("{ title :\tTabbed Value\t}") == [("title", "Tabbed Value")],
    str(scan("{ title :\tTabbed Value\t}")),
)
check(
    "scanner: every occurrence returned, in line order",
    scan("{title: First}\nLyric line\n{title: Second}")
    == [("title", "First"), ("title", "Second")],
    str(scan("{title: First}\nLyric line\n{title: Second}")),
)

# Item 18: Unicode whitespace (tab, vertical tab, form feed), not just the
# ASCII space SQL's bare trim() strips, must be trimmed away -- matching
# Dart's String.trim().
check(
    "scanner: vertical tab and form feed are trimmed like Dart's String.trim(), not just spaces/tabs",
    scan("{title:\t\x0b\x0c  Padded Title  \x0c\x0b\t}") == [("title", "Padded Title")],
    str(scan("{title:\t\x0b\x0c  Padded Title  \x0c\x0b\t}")),
)

# Tab-block inertness (supporting Item 14 at the scanner level -- Task 4
# pins the title-specific manifestation the spec names). A directive whose
# name does not start with end_of_ is swallowed entirely while inside a tab
# block: not emitted as a row at all.
check(
    "scanner: a directive inside a tab block is swallowed, not emitted",
    scan("{start_of_tab}\n{title: Tab Title}\n{end_of_tab}")
    == [("start_of_tab", None), ("end_of_tab", None)],
    str(scan("{start_of_tab}\n{title: Tab Title}\n{end_of_tab}")),
)
check(
    "scanner: a directive after end_of_tab is emitted normally",
    scan("{start_of_tab}\n{end_of_tab}\n{title: Real Title}")
    == [("start_of_tab", None), ("end_of_tab", None), ("title", "Real Title")],
    str(scan("{start_of_tab}\n{end_of_tab}\n{title: Real Title}")),
)

# key_window_open: exposed per row as the negation of has_seen_song_content
# as it stood before that row's own effect. Task 6 filters on this for key
# extraction; these assertions pin the flag itself, at the scanner level,
# for each of the three reproduced triggers.
check(
    "scanner: key_window_open is true before any lyric/section content",
    scan("{key: G}", with_window=True) == [("key", "G", True)],
    str(scan("{key: G}", with_window=True)),
)
check(
    "scanner: key_window_open is false once a lyric line has been seen",
    scan("[C] lyric line\n{key: G}", with_window=True) == [("key", "G", False)],
    str(scan("[C] lyric line\n{key: G}", with_window=True)),
)
check(
    "scanner: key_window_open is false once a start_of_* directive has been seen",
    scan("{start_of_verse}\n{key: G}", with_window=True)
    == [("start_of_verse", None, True), ("key", "G", False)],
    str(scan("{start_of_verse}\n{key: G}", with_window=True)),
)
check(
    "scanner: key_window_open is false once an end_of_* directive has been seen",
    scan("{end_of_verse}\n{key: G}", with_window=True)
    == [("end_of_verse", None, True), ("key", "G", False)],
    str(scan("{end_of_verse}\n{key: G}", with_window=True)),
)

# --- Section B: chordpro_derive_title (Task 4) -------------------------------

def derive_title(source: str) -> str:
    return run_psql(
        f"select public.chordpro_derive_title({sql_quote(source)});"
    )


check(
    "title: last occurrence wins",
    derive_title("{title: First}\n{title: Second}") == "Second",
    derive_title("{title: First}\n{title: Second}"),
)
check(
    "title: t is an alias for title",
    derive_title("{t: T Alias Title}") == "T Alias Title",
    derive_title("{t: T Alias Title}"),
)
check(
    "title: t and title share the last-occurrence pool",
    derive_title("{title: First}\n{t: Second Via T}") == "Second Via T",
    derive_title("{title: First}\n{t: Second Via T}"),
)
check(
    "title: no directive -> empty string, not null",
    derive_title("[C] Lyric only, no directive") == "",
    repr(derive_title("[C] Lyric only, no directive")),
)

# Item 14: tab-block inertness, at the title level. A {title: X} between
# {start_of_tab} and {end_of_tab} is not a title; one after {end_of_tab} is.
check(
    "title: a directive inside a tab block does not become the title",
    derive_title("{start_of_tab}\n{title: Tab Title}\n{end_of_tab}\n{title: Real Title}")
    == "Real Title",
    derive_title("{start_of_tab}\n{title: Tab Title}\n{end_of_tab}\n{title: Real Title}"),
)
check(
    "title: with no title after the tab block, falls back to '' (the swallowed one never counted)",
    derive_title("{start_of_tab}\n{title: Tab Title}\n{end_of_tab}") == "",
    repr(derive_title("{start_of_tab}\n{title: Tab Title}\n{end_of_tab}")),
)

if failures:
    raise SystemExit(
        "song derived metadata contract failed:\n  " + "\n  ".join(failures)
    )

print("song derived metadata contract passed.")
PY
