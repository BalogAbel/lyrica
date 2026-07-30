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
    # Strip only the trailing newline psql always appends, not surrounding
    # tabs -- a plain .strip() would eat a trailing tab that represents a
    # genuinely empty last column (e.g. capture_error's detail field for an
    # error with a HINT but no DETAIL), collapsing a 3-column row into 2.
    return result.stdout.strip("\n")


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

# --- Section C: chordpro_derive_artist (Task 5) ------------------------------

def derive_artist(source: str):
    raw = run_psql(
        f"select coalesce(public.chordpro_derive_artist({sql_quote(source)}), '<null>');"
    )
    return None if raw == "<null>" else raw


check(
    "artist: last occurrence wins",
    derive_artist("{artist: First Artist}\n{artist: Second Artist}") == "Second Artist",
    str(derive_artist("{artist: First Artist}\n{artist: Second Artist}")),
)
check(
    "artist: no directive -> null",
    derive_artist("[C] no artist directive here") is None,
    str(derive_artist("[C] no artist directive here")),
)
check(
    "artist: a later bare occurrence nulls an earlier value (last occurrence wins unconditionally)",
    derive_artist("{artist: Someone}\n{artist}") is None,
    str(derive_artist("{artist: Someone}\n{artist}")),
)

# --- Section D: chordpro_derive_key_signature (Task 6) -----------------------

def derive_key(source: str):
    raw = run_psql(
        f"select coalesce(public.chordpro_derive_key_signature({sql_quote(source)}), '<null>');"
    )
    return None if raw == "<null>" else raw


check(
    "key: last valid occurrence wins",
    derive_key("{key: C}\n{key: G}") == "G",
    str(derive_key("{key: C}\n{key: G}")),
)
check(
    "key: no directive -> null",
    derive_key("[C] no key directive") is None,
    str(derive_key("[C] no key directive")),
)

# Item 16: an invalid (empty) occurrence inside the window does not clear an
# earlier valid one.
check(
    "key: an invalid (empty) later occurrence does not overwrite an earlier valid one",
    derive_key("{key: C}\n{key:}") == "C",
    str(derive_key("{key: C}\n{key:}")),
)
check(
    "key: all-invalid occurrences -> null",
    derive_key("{key:}\n{key:   }") is None,
    str(derive_key("{key:}\n{key:   }")),
)

# Item 15: the key window -- honoured before any song content, ignored after
# a lyric line, after a start_of_*, and after an end_of_*.
check(
    "key window: honoured before any lyric line or section directive",
    derive_key("{key: G}\n[C] Amazing grace") == "G",
    str(derive_key("{key: G}\n[C] Amazing grace")),
)
check(
    "key window: ignored once a lyric line has been seen",
    derive_key("[C] Amazing grace\n{key: G}") is None,
    str(derive_key("[C] Amazing grace\n{key: G}")),
)
check(
    "key window: ignored once a start_of_* directive has been seen",
    derive_key("{start_of_verse}\n{key: G}") is None,
    str(derive_key("{start_of_verse}\n{key: G}")),
)
check(
    "key window: ignored once an end_of_* directive has been seen",
    derive_key("{end_of_verse}\n{key: G}") is None,
    str(derive_key("{end_of_verse}\n{key: G}")),
)

# Item 17: the one accepted divergence, pinned explicitly. The Dart parser
# treats {c: Verse} as a section-start comment (_parseCommentSection matches
# a bare word like "Verse"), which would close the key window, so the real
# parser would leave the key null here. chordpro_scan_directives does not
# implement comment-as-section recognition, so this SAME source derives a
# key in SQL. This asserts the SQL's actual behaviour and names the
# divergence, so a future change on either side (SQL growing comment
# support, or the Dart parser's rule changing) fails this assertion loudly
# instead of the two silently drifting further apart.
check(
    "key window: accepted divergence -- a comment Dart reads as a section "
    "start does not close the window in SQL (see ADR-027)",
    derive_key("{c: Verse}\n{key: G}") == "G",
    str(derive_key("{c: Verse}\n{key: G}")),
)

# --- Section E: chordpro_derive_tempo_bpm (Task 7) ---------------------------

def derive_tempo(source: str):
    raw = run_psql(
        f"select coalesce(public.chordpro_derive_tempo_bpm({sql_quote(source)})::text, '<null>');"
    )
    return None if raw == "<null>" else int(raw)


check(
    "tempo: last occurrence wins",
    derive_tempo("{tempo: 100}\n{tempo: 140}") == 140,
    str(derive_tempo("{tempo: 100}\n{tempo: 140}")),
)
check(
    "tempo: no directive -> null",
    derive_tempo("[C] no tempo directive") is None,
    str(derive_tempo("[C] no tempo directive")),
)
check(
    "tempo: non-integer value -> null, write is not expected to fail",
    derive_tempo("{tempo: allegro}") is None,
    str(derive_tempo("{tempo: allegro}")),
)
check(
    "tempo: a later non-integer occurrence overwrites an earlier valid one with null",
    derive_tempo("{tempo: 120}\n{tempo: fast}") is None,
    str(derive_tempo("{tempo: 120}\n{tempo: fast}")),
)
check(
    "tempo: an out-of-int4-range value is ignored rather than raising",
    derive_tempo("{tempo: 99999999999}") is None,
    str(derive_tempo("{tempo: 99999999999}")),
)

# --- Section F: chordpro_derive_tags (Task 8) --------------------------------

def derive_tags(source: str) -> list[str]:
    raw = run_psql(
        f"select public.chordpro_derive_tags({sql_quote(source)})::text;"
    )
    # Postgres text[] literal form, e.g. {a,b,c} or {}
    inner = raw.strip("{}")
    return [] if inner == "" else inner.split(",")


check(
    "tags: split on comma, trimmed, empties dropped",
    derive_tags("{tags: a, b ,, c}") == ["a", "b", "c"],
    str(derive_tags("{tags: a, b ,, c}")),
)
check(
    "tags: tag is an alias for tags",
    derive_tags("{tag: solo, worship}") == ["solo", "worship"],
    str(derive_tags("{tag: solo, worship}")),
)
check(
    "tags: last occurrence wins",
    derive_tags("{tags: old, stale}\n{tags: new, fresh}") == ["new", "fresh"],
    str(derive_tags("{tags: old, stale}\n{tags: new, fresh}")),
)
check(
    "tags: no directive -> empty array, not null",
    derive_tags("[C] no tags directive") == [],
    str(derive_tags("[C] no tags directive")),
)
check(
    "tags: bare directive with no value -> empty array",
    derive_tags("{tags}") == [],
    str(derive_tags("{tags}")),
)

# --- Section G: create_song derivation (Task 9) ------------------------------

def song_source_with(directives: str, body_title: str = "Body") -> str:
    return directives + "\n[C] " + body_title


def create_song(
    title: str,
    chordpro_source: str,
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
              p_chordpro_source => {sql_quote(chordpro_source)}{slug_arg}
            ));
            """
        ),
        user_id=user_id,
    )


# Item 1: derived title wins over a different p_title.
created_1 = create_song(
    "Different Title",
    song_source_with("{title: Real Title}"),
    requested_slug="derived-title-wins",
    user_id=demo_user_id,
)
check(
    "create_song: derived title wins over supplied p_title",
    created_1["title"] == "Real Title",
    created_1["title"],
)
# Item 10: the slug follows the derived title, not the supplied p_title.
check(
    "create_song: slug follows the derived title",
    created_1["slug"] == "derived-title-wins",
    created_1["slug"],
)

# Item 2: no {title} directive -> falls back to p_title.
created_2 = create_song(
    "Fallback Title",
    song_source_with("{artist: Nobody}"),
    requested_slug="fallback-title-song",
    user_id=demo_user_id,
)
check(
    "create_song: falls back to p_title when source has no title",
    created_2["title"] == "Fallback Title",
    created_2["title"],
)

# Item 3: {t: ...} is honoured identically to {title: ...}.
created_3 = create_song(
    "Ignored",
    song_source_with("{t: T Alias Title}"),
    requested_slug="t-alias-title-song",
    user_id=demo_user_id,
)
check(
    "create_song: t is honoured identically to title",
    created_3["title"] == "T Alias Title",
    created_3["title"],
)

# Item 4: later occurrences win over earlier ones.
created_4 = create_song(
    "Ignored",
    song_source_with("{title: First}\n{title: Second}"),
    requested_slug="last-occurrence-title-song",
    user_id=demo_user_id,
)
check(
    "create_song: later directive occurrence wins",
    created_4["title"] == "Second",
    created_4["title"],
)

# Item 5: artist, key_signature, tempo_bpm, tags populated from source.
created_5 = create_song(
    "Metadata Song",
    song_source_with(
        "{title: Metadata Song}\n{artist: The Testers}\n{key: G}\n"
        "{tempo: 120}\n{tags: worship, test}"
    ),
    requested_slug="metadata-song",
    user_id=demo_user_id,
)
check("create_song: artist derived", created_5["artist"] == "The Testers", created_5["artist"])
check("create_song: key_signature derived", created_5["key_signature"] == "G", created_5["key_signature"])
check("create_song: tempo_bpm derived", created_5["tempo_bpm"] == 120, created_5["tempo_bpm"])
check("create_song: tags derived", created_5["tags"] == ["worship", "test"], created_5["tags"])

# Item 6: tags splitting drops empties.
created_6 = create_song(
    "Tags Song",
    song_source_with("{title: Tags Song}\n{tags: a, b ,, c}"),
    requested_slug="tags-splitting-song",
    user_id=demo_user_id,
)
check(
    "create_song: tags splitting drops empties",
    created_6["tags"] == ["a", "b", "c"],
    created_6["tags"],
)

# Item 7: non-integer tempo leaves tempo_bpm null, write still succeeds.
created_7 = create_song(
    "Tempo Song",
    song_source_with("{title: Tempo Song}\n{tempo: allegro}"),
    requested_slug="non-integer-tempo-song",
    user_id=demo_user_id,
)
check(
    "create_song: non-integer tempo does not fail the write",
    created_7["tempo_bpm"] is None,
    created_7["tempo_bpm"],
)

# Item 11: the removed parameters no longer exist on create_song.
removed_param_sql, removed_param_message, removed_param_detail = capture_error(
    dedent(
        f"""
        perform public.create_song(
          p_organization_id => {sql_quote(organization_id)},
          p_title => 'Should Not Exist',
          p_artist => 'Should Not Exist'
        );
        """
    ),
    user_id=demo_user_id,
)
check(
    "create_song: p_artist is no longer a valid parameter",
    removed_param_sql == "42883",
    f"sqlstate={removed_param_sql!r} message={removed_param_message!r}",
)

# --- Section H: song_write_update_common / update_song / overwrite_song_update (Task 10) --

def update_song(
    song_id: str,
    base_version: int,
    title: str,
    chordpro_source: str | None = None,
    overwrite: bool = False,
    requested_slug: str | None = None,
    user_id: str | None = None,
) -> dict:
    function_name = "public.overwrite_song_update" if overwrite else "public.update_song"
    source_arg = (
        f", p_chordpro_source => {sql_quote(chordpro_source)}"
        if chordpro_source is not None
        else ""
    )
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
              p_title => {sql_quote(title)}{source_arg}{slug_arg}
            ));
            """
        ),
        user_id=user_id,
    )


# Item 8: an update carrying a new source re-derives every shadow field.
update_target = create_song(
    "Update Target",
    song_source_with("{title: Update Target}"),
    requested_slug="update-target-song",
    user_id=demo_user_id,
)
check(
    "update_target starts with no artist",
    update_target["artist"] is None,
    update_target["artist"],
)
updated_with_source = update_song(
    update_target["id"],
    update_target["version"],
    "Ignored Title",
    chordpro_source=song_source_with(
        "{title: Updated Title}\n{artist: New Artist}\n{key: D}\n"
        "{tempo: 90}\n{tags: new}"
    ),
    user_id=demo_user_id,
)
check(
    "update_song: new source re-derives title",
    updated_with_source["title"] == "Updated Title",
    updated_with_source["title"],
)
check(
    "update_song: new source re-derives artist",
    updated_with_source["artist"] == "New Artist",
    updated_with_source["artist"],
)
check(
    "update_song: new source re-derives key_signature",
    updated_with_source["key_signature"] == "D",
    updated_with_source["key_signature"],
)
check(
    "update_song: new source re-derives tempo_bpm",
    updated_with_source["tempo_bpm"] == 90,
    updated_with_source["tempo_bpm"],
)
check(
    "update_song: new source re-derives tags",
    updated_with_source["tags"] == ["new"],
    updated_with_source["tags"],
)

# Item 9: an update carrying NO source still re-derives from the stored
# source -- a row with a stale null artist gains it on the next unrelated
# update. Simulate a legacy row by writing chordpro_source directly (not
# through the RPC), leaving artist stale-null, then updating with no source.
legacy_target = create_song(
    "Legacy Target",
    song_source_with("{title: Legacy Target}"),
    requested_slug="legacy-target-song",
    user_id=demo_user_id,
)
check(
    "legacy_target starts with no artist",
    legacy_target["artist"] is None,
    legacy_target["artist"],
)
run_psql(
    dedent(
        f"""
        update public.songs
        set chordpro_source = {sql_quote(
            song_source_with("{title: Legacy Target}\n{artist: Late Arrival}")
        )}
        where organization_id = {sql_quote(organization_id)}
          and id = {sql_quote(legacy_target['id'])};
        """
    )
)
converged = update_song(
    legacy_target["id"],
    legacy_target["version"],
    "Legacy Target",
    chordpro_source=None,
    user_id=demo_user_id,
)
check(
    "update_song: no-source update re-derives from the already-stored source",
    converged["artist"] == "Late Arrival",
    converged["artist"],
)

# Item 13: version-conflict behaviour on update_song is unchanged.
stale_sql, stale_message, _stale_detail = capture_error(
    dedent(
        f"""
        perform public.update_song(
          p_organization_id => {sql_quote(organization_id)},
          p_song_id => {sql_quote(update_target['id'])},
          p_base_version => 1,
          p_title => 'Stale Write',
          p_chordpro_source => {sql_quote(song_source_with("{title: Stale Write}"))}
        );
        """
    ),
    user_id=demo_user_id,
)
check(
    "update_song: stale base_version still raises song_version_conflict",
    stale_sql == "P0001" and stale_message == "song_version_conflict",
    f"sqlstate={stale_sql!r} message={stale_message!r}",
)

# Item 11 (remaining): the removed parameters no longer exist on update_song.
removed_update_sql, _removed_update_message, _removed_update_detail = capture_error(
    dedent(
        f"""
        perform public.update_song(
          p_organization_id => {sql_quote(organization_id)},
          p_song_id => {sql_quote(update_target['id'])},
          p_base_version => {updated_with_source['version']},
          p_title => 'Should Not Exist',
          p_artist => 'Should Not Exist'
        );
        """
    ),
    user_id=demo_user_id,
)
check(
    "update_song: p_artist is no longer a valid parameter",
    removed_update_sql == "42883",
    removed_update_sql,
)

# overwrite_song_update recreate path still works with the new signature.
overwrite_recreate_target = create_song(
    "Overwrite Recreate Target",
    song_source_with("{title: Overwrite Recreate Target}"),
    requested_slug="overwrite-recreate-target",
    user_id=demo_user_id,
)
run_psql(
    dedent(
        f"""
        delete from public.songs
        where organization_id = {sql_quote(organization_id)}
          and id = {sql_quote(overwrite_recreate_target['id'])};
        """
    )
)
recreated = update_song(
    overwrite_recreate_target["id"],
    1,
    "Ignored",
    chordpro_source=song_source_with("{title: Recreated Title}\n{artist: Recreated Artist}"),
    overwrite=True,
    requested_slug="overwrite-recreate-target",
    user_id=demo_user_id,
)
check(
    "overwrite_song_update: recreate path derives title from source",
    recreated["title"] == "Recreated Title",
    recreated["title"],
)
check(
    "overwrite_song_update: recreate path derives artist from source",
    recreated["artist"] == "Recreated Artist",
    recreated["artist"],
)

# Item 12: grants pin the new signatures and the old ones being gone.
old_create_song_gone = run_psql(
    "select to_regprocedure("
    "'public.create_song(uuid, text, text, text, integer, text[], text, jsonb, text, uuid)'"
    ") is null;"
)
old_update_song_gone = run_psql(
    "select to_regprocedure("
    "'public.update_song(uuid, uuid, bigint, text, text, text, integer, text[], text, jsonb)'"
    ") is null;"
)
old_overwrite_song_update_gone = run_psql(
    "select to_regprocedure("
    "'public.overwrite_song_update(uuid, uuid, bigint, text, text, text, text, integer, text[], text, jsonb)'"
    ") is null;"
)
old_song_write_update_common_gone = run_psql(
    "select to_regprocedure("
    "'public.song_write_update_common(uuid, uuid, bigint, text, text, text, integer, text[], text, jsonb, boolean)'"
    ") is null;"
)
check(
    "grants: all four old signatures are gone",
    [
        old_create_song_gone,
        old_update_song_gone,
        old_overwrite_song_update_gone,
        old_song_write_update_common_gone,
    ]
    == ["t", "t", "t", "t"],
    [
        old_create_song_gone,
        old_update_song_gone,
        old_overwrite_song_update_gone,
        old_song_write_update_common_gone,
    ],
)

new_signature_grants = run_psql(
    dedent(
        """
        select
          has_function_privilege('authenticated', 'public.create_song(uuid, text, text, text, uuid)', 'execute'),
          has_function_privilege('anon', 'public.create_song(uuid, text, text, text, uuid)', 'execute'),
          has_function_privilege('authenticated', 'public.update_song(uuid, uuid, bigint, text, text)', 'execute'),
          has_function_privilege('anon', 'public.update_song(uuid, uuid, bigint, text, text)', 'execute'),
          has_function_privilege('authenticated', 'public.overwrite_song_update(uuid, uuid, bigint, text, text, text)', 'execute'),
          has_function_privilege('anon', 'public.overwrite_song_update(uuid, uuid, bigint, text, text, text)', 'execute'),
          has_function_privilege('authenticated', 'public.song_write_update_common(uuid, uuid, bigint, text, text, boolean)', 'execute'),
          has_function_privilege('anon', 'public.song_write_update_common(uuid, uuid, bigint, text, text, boolean)', 'execute');
        """
    )
).split("\t")
check(
    "grants: new signatures executable by authenticated, none by anon, "
    "song_write_update_common executable by neither (internal-only helper)",
    new_signature_grants == ["t", "f", "t", "f", "t", "f", "f", "f"],
    new_signature_grants,
)

# --- Unicode whitespace parity with Dart's String.trim(). --------------------
# Dart trims every Unicode White_Space character plus U+FEFF. An ASCII-only trim
# would read a directive padded with NBSP as a lyric line, so the backend and the
# offline client would derive different metadata from the same source. Each
# fixture below is built with chr() so the test source stays readable.
NBSP = "chr(160)"
EMSP = "chr(8195)"
BOM = "chr(65279)"

parity_cases = [
    (
        "NBSP around the directive",
        f"{NBSP} || '{{title: Padded Song}}' || {NBSP}",
        "Padded Song",
    ),
    (
        "EM SPACE around the directive",
        f"{EMSP} || '{{title: Em Padded}}' || {EMSP}",
        "Em Padded",
    ),
    (
        "BOM before the directive",
        f"{BOM} || '{{title: Bom Song}}'",
        "Bom Song",
    ),
    (
        "NBSP inside the directive body around name and value",
        f"'{{' || {NBSP} || 'title' || {NBSP} || ':' || {NBSP} || "
        f"'Inner Padded' || {NBSP} || '}}'",
        "Inner Padded",
    ),
    (
        "mixed Unicode whitespace around the value",
        f"'{{title:' || {EMSP} || {BOM} || 'Mixed' || {NBSP} || '}}'",
        "Mixed",
    ),
]

for label, expr, expected in parity_cases:
    got = run_psql(f"select public.chordpro_derive_title({expr});")
    check(
        f"unicode parity title: {label}",
        got == expected,
        f"expected {expected!r}, got {got!r}",
    )

# A line that is nothing but Unicode whitespace is empty to Dart, so it must not
# count as song content and must not close the key window.
got = run_psql(
    f"select coalesce(public.chordpro_derive_key_signature("
    f"{NBSP} || chr(10) || '{{key: G}}'), '<null>');"
)
check(
    "unicode parity: a whitespace-only line is not song content",
    got == "G",
    f"a line of only NBSP must not close the key window, got {got!r}",
)

# Ordinary lyric lines keep their meaning: a real lyric before {key:} still
# closes the window.
got = run_psql(
    "select coalesce(public.chordpro_derive_key_signature("
    "'plain lyric line' || chr(10) || '{key: G}'), '<null>');"
)
check(
    "unicode parity: a real lyric line still closes the key window",
    got == "<null>",
    f"a lyric line must still close the key window, got {got!r}",
)

# Unicode whitespace must not leak into a derived artist value either.
got = run_psql(f"select public.chordpro_derive_artist({NBSP} || '{{artist:' || {EMSP} || 'Padded Artist' || {BOM} || '}}');")
check(
    "unicode parity artist trimming",
    got == "Padded Artist",
    f"expected 'Padded Artist', got {got!r}",
)


if failures:
    raise SystemExit(
        "song derived metadata contract failed:\n  " + "\n  ".join(failures)
    )

print("song derived metadata contract passed.")
PY
