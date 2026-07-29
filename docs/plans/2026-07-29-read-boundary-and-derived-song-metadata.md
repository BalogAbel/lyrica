# Read Boundary and Backend-Derived Song Metadata — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/specs/2026-07-29-read-boundary-and-derived-song-metadata.md` — every decision below is already made and confirmed there. This plan does not re-open, alternative, or extend any of it; it only sequences the work.

**Goal:** Close three deferred items with one slice: (1) an ADR that keeps the read boundary on RLS-protected table reads with no code change, (2) move the `unaccent` extension out of `public` and pin `public.slugify` to a schema-qualified call, behaviour pinned by a parity test written first, and (3) make `create_song` / `song_write_update_common` derive `title`, `artist`, `key_signature`, `tempo_bpm`, and `tags` from canonical ChordPro inside the `security definer` write boundary, removing the client-supplied parameters for those fields (`p_metadata_json` too) from both RPC families.

**Architecture:** All backend work lands in `supabase/migrations/`, continuing the numbering already on this branch (`202607290000`–`202607290002`) from `202607290003`. Two new migrations: one for the `unaccent` move (isolated because it is unrelated to song metadata), one for the ChordPro extraction functions and the song RPC changes (built up across several tasks since it is one coherent, unmerged change). Every schema change is proven by a bash + inlined-python3 contract test against the local Supabase Postgres container, following the house style in `scripts/tests/invitation-redemption-contract-test.sh`. A small SQL "scanner" function reproduces the ChordPro directive grammar (`chordpro_line_scanner.dart:66-84`); five small `immutable` extractor functions sit on top of it, one per derived field, each pinned by its own unit-level SQL assertions before it is wired into the write RPCs.

**Tech Stack:** PostgreSQL 17 (Supabase), PL/pgSQL and SQL functions, bash + python3 contract tests driven through `docker exec ... psql`, no Dart/Flutter changes (the client never sent the removed parameters).

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/202607290003_relocate_unaccent_extension.sql` | Moves `unaccent` to the `extensions` schema; redefines `public.slugify` to call `extensions.unaccent(...)`, inlining `set search_path = public` so the setting survives the `create or replace`. |
| `supabase/migrations/202607290004_derive_song_metadata.sql` | New: `public.chordpro_scan_directives`, `public.chordpro_derive_title`, `public.chordpro_derive_artist`, `public.chordpro_derive_key_signature`, `public.chordpro_derive_tempo_bpm`, `public.chordpro_derive_tags`. Modified in place across tasks: drops and recreates `public.create_song`, `public.song_write_update_common`, `public.update_song`, `public.overwrite_song_update` with the derived-metadata bodies and the narrower parameter lists, and reapplies `revoke`/`grant` for every new signature. |
| `scripts/tests/slug-parity-contract-test.sh` | New. Pins `public.slugify` output across accented characters, punctuation runs, leading/trailing separators, and the empty result. Written and green before the `unaccent` move; unedited by the move itself. |
| `scripts/tests/song-derived-metadata-contract-test.sh` | New. Unit-level assertions on the scanner and each extractor, then integration assertions on `create_song` / `update_song` / `overwrite_song_update`, then the grant/signature regression check. Built up incrementally, one section per task. |
| `scripts/tests/song-crud-write-contract-test.sh` | Modified. Removes the now-false "update preserves arbitrary shadow metadata" assertions and renumbers the two downstream version expectations that depended on them. |
| `scripts/backend-write-contracts.sh` | Modified. Chains the two new test scripts alongside the existing ones. |
| `docs/architecture/decisions/ADR-026-rls-protected-read-boundary.md` | New. Records the read-boundary decision (no code change). |
| `docs/architecture/decisions/ADR-027-backend-derived-song-metadata.md` | New. Records the derivation decision, the rejected alternatives, and the grammar-parity argument. |
| `docs/architecture/repository-review-2026-06-22.md` | Modified. SEC-4 marked fixed, description corrected to the one-field-not-six finding. |
| `docs/architecture/architecture.md` | Modified. Documents the read boundary and the song write contract. |
| `docs/domain/domain-model.md` | Modified. Shadow metadata is source-derived at write acceptance, not client-authoritative. |
| `docs/testing/testing-strategy.md` | Modified. Adds the new contract tests to Backend Verification coverage. |
| `docs/deferred/2026-05-16-auth-schema-lint-followups.md` | Removed. Closed by ADR-026. |
| `docs/deferred/2026-05-09-song-write-derived-fields.md` | Removed. Closed by ADR-027. |

---

## Before you start

All contract tests assume a running local Supabase stack. From a clean shell:

```bash
./scripts/supabase.sh start
./scripts/db-reset.sh
./scripts/provision-local-demo-user.sh
```

After that, run any individual test script with `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1` prefixed so it doesn't repeat the bootstrap:

```bash
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/slug-parity-contract-test.sh
```

Whenever a migration file changes, re-run `./scripts/db-reset.sh` before re-running a test, since that is what applies migrations from scratch.

---

## Task 1: Slug parity contract test (pin current behaviour, before anything moves)

**Files:**
- Create: `scripts/tests/slug-parity-contract-test.sh`
- Modify: `scripts/backend-write-contracts.sh`

This test does not change any behaviour — it characterizes what `public.slugify` already does today, so that Task 2's extension move can be judged against it. Because there is no bug to fix, the "failing" step is procedural (the script doesn't exist yet), not a logic failure.

- [ ] **Step 1: Write the test**

Create `scripts/tests/slug-parity-contract-test.sh`:

```bash
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

python3 - "$db_container_name" <<'PY'
import subprocess
import sys

container_name = sys.argv[1]
failures = []


def sql_quote(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def run_psql(sql: str) -> str:
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
        raise SystemExit(f"psql failed:\nSQL:\n{sql}\nstderr:\n{result.stderr}")
    return result.stdout.strip()


def check(label: str, condition: bool, detail: str = "") -> None:
    if not condition:
        failures.append(f"{label}: {detail}")


def slugify(value: str):
    raw = run_psql(
        f"select coalesce(public.slugify({sql_quote(value)}), '<null>');"
    )
    return None if raw == "<null>" else raw


# (label, input, expected output) -- expected output is None for the
# empty-result case, since slugify nullif()s an empty string.
CASES = [
    ("accented characters", "Café Für Élise", "cafe-fur-elise"),
    ("punctuation runs", "Rock & Roll!!  (Live)", "rock-roll-live"),
    ("leading and trailing separators", "  ---Hello World---  ", "hello-world"),
    ("empty result", "   ...???   ", None),
    (
        "composite accent + punctuation",
        "São Paulo, Brazil — 2026!",
        "sao-paulo-brazil-2026",
    ),
]

for label, input_value, expected in CASES:
    actual = slugify(input_value)
    check(
        f"slugify parity: {label}",
        actual == expected,
        f"input={input_value!r} expected={expected!r} actual={actual!r}",
    )

if failures:
    raise SystemExit(
        "slug parity contract failed:\n  " + "\n  ".join(failures)
    )

print("slug parity contract passed.")
PY
```

Make it executable:

```bash
chmod +x scripts/tests/slug-parity-contract-test.sh
```

- [ ] **Step 2: Run it and see it fail (procedurally)**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/slug-parity-contract-test.sh`

Before this step, the file doesn't exist, so the command fails with `No such file or directory` (or, once written but before `chmod +x`, `Permission denied`). This confirms there is no pre-existing script silently passing.

- [ ] **Step 3: Run it and see it pass**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/slug-parity-contract-test.sh`
Expected: `slug parity contract passed.` — because `public.slugify` already implements this behaviour today (migration `202604030001_add_song_plan_session_slugs.sql`), before any change in this slice.

- [ ] **Step 4: Wire it into the chained suite**

In `scripts/backend-write-contracts.sh`, add the new script to the chain, right before the planning/song CRUD scripts so it runs earliest:

```bash
slug_parity_test_script="${SLUG_PARITY_TEST_SCRIPT:-./scripts/tests/slug-parity-contract-test.sh}"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$slug_parity_test_script"

planning_write_contract_test_script="${PLANNING_WRITE_CONTRACT_TEST_SCRIPT:-./scripts/tests/planning-write-contract-test.sh}"
```

(i.e. insert the `slug_parity_test_script` block immediately above the existing `planning_write_contract_test_script` declaration, keeping everything after it unchanged.)

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/slug-parity-contract-test.sh scripts/backend-write-contracts.sh
git commit -m "$(cat <<'EOF'
test(db): pin public.slugify output before the unaccent extension move

Characterizes current slugify behaviour (accents, punctuation runs,
leading/trailing separators, empty result) so the upcoming unaccent
schema move can be proven identical rather than assumed identical.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Move `unaccent` out of `public`; repoint `slugify`

**Files:**
- Create: `supabase/migrations/202607290003_relocate_unaccent_extension.sql`

There is no new test to write here — Task 1's parity test is the regression guard, and it must stay byte-for-byte unedited so that a green run after this migration is proof, not assertion. This task's own "before/after" is the parity test's pass/fail, not a new assertion.

- [ ] **Step 1: Confirm the baseline is green**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/slug-parity-contract-test.sh`
Expected: `slug parity contract passed.` (this is the pre-move baseline, already proven in Task 1).

- [ ] **Step 2: Write the migration**

Create `supabase/migrations/202607290003_relocate_unaccent_extension.sql`:

```sql
alter extension unaccent set schema extensions;

-- Redefine slugify to call the relocated extension by its new schema. The
-- `set search_path = public` is inlined here (not a follow-up `alter
-- function`) because `create or replace function` does not carry forward a
-- previously-set function config parameter -- the 202605160007 migration's
-- `alter function public.slugify(text) set search_path = public` would be
-- silently discarded if this replacement omitted it.
create or replace function public.slugify(input_value text)
returns text
language sql
immutable
set search_path = public
as $$
  select nullif(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          lower(extensions.unaccent(coalesce(input_value, ''))),
          '[^a-z0-9]+', '-', 'g'
        ),
        '(^-|-$)', '', 'g'
      ),
      '-{2,}', '-', 'g'
    ),
    ''
  );
$$;
```

- [ ] **Step 3: Apply the migration**

Run: `./scripts/db-reset.sh`
Expected: exits 0, applying all migrations including the new one.

- [ ] **Step 4: Verify the extension actually moved (ad hoc, not part of the committed test)**

Run:
```bash
db_container_name="$(docker ps --format '{{.Names}}' | grep '^supabase_db_' | head -n 1)"
docker exec -i "$db_container_name" psql -U postgres -d postgres -qAt -c \
  "select extnamespace::regnamespace::text from pg_extension where extname = 'unaccent';"
```
Expected output: `extensions` (not `public`).

- [ ] **Step 5: Re-run the unedited parity test and see it still pass**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/slug-parity-contract-test.sh`
Expected: `slug parity contract passed.` — identical output to Step 1, from the identical, unedited test file. This is what makes the move provable: `git diff` for `scripts/tests/slug-parity-contract-test.sh` between Task 1's commit and this one is empty.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/202607290003_relocate_unaccent_extension.sql
git commit -m "$(cat <<'EOF'
fix(db): relocate unaccent out of public, repoint slugify

unaccent was the only extension still installed in public; every other
extension already lives in extensions, graphql, vault, or pg_catalog.
Moves it to extensions and repoints public.slugify at the qualified
call, inlining search_path = public so create-or-replace doesn't drop
it. The slug parity test from the prior commit is unchanged and still
green, proving output is identical rather than assumed identical.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: ChordPro directive scanner (`public.chordpro_scan_directives`)

**Files:**
- Create: `supabase/migrations/202607290004_derive_song_metadata.sql`
- Create: `scripts/tests/song-derived-metadata-contract-test.sh`
- Modify: `scripts/backend-write-contracts.sh`

This function reproduces the grammar in `chordpro_line_scanner.dart:66-84` exactly: normalise `\r\n` to `\n`, trim each line (matching Dart's `.trim()`, which strips more than the ASCII space that SQL's default `trim()` strips — so this uses `btrim(x, E' \t\n\r\v\f')` throughout, not bare `trim()`), a directive line starts with `{` and ends with `}`, an empty body is not a directive, the first `:` splits name (trimmed, lowercased) from value (trimmed), and a body with no `:` is a name with a null value. It returns every directive occurrence with its source line number — "last occurrence wins" is left to the per-field extractors built in later tasks, not decided here.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/song-derived-metadata-contract-test.sh`:

```bash
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

def scan(source: str) -> list[tuple[str, str | None]]:
    rows = run_psql_rows(
        "select directive_name, coalesce(directive_value, '<null>') "
        f"from public.chordpro_scan_directives({sql_quote(source)}) "
        "order by line_number;"
    )
    return [
        (name, None if value == "<null>" else value) for name, value in rows
    ]


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

if failures:
    raise SystemExit(
        "song derived metadata contract failed:\n  " + "\n  ".join(failures)
    )

print("song derived metadata contract passed.")
PY
```

Make it executable:

```bash
chmod +x scripts/tests/song-derived-metadata-contract-test.sh
```

- [ ] **Step 2: Run it and see it fail**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `psql failed` with stderr containing `function public.chordpro_scan_directives(unknown) does not exist` — the function does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `supabase/migrations/202607290004_derive_song_metadata.sql`:

```sql
-- ChordPro directive scanner. Reproduces chordpro_line_scanner.dart:66-84
-- exactly: normalize \r\n -> \n, trim each line, a directive line starts
-- with `{` and ends with `}`, an empty body is not a directive, the first
-- `:` splits name (trimmed, lowercased) from value (trimmed); no colon means
-- the whole body is the name and the value is null. Returns every
-- occurrence with its line number; last-occurrence-wins is a decision for
-- the per-field extractors built on top of this, not this function.
--
-- Uses btrim(x, E' \t\n\r\v\f') rather than bare trim(), because SQL's
-- trim() strips only the ASCII space by default, while Dart's String.trim()
-- strips all whitespace -- a ChordPro line indented with a tab would
-- otherwise fail to match a directive that Dart parses correctly.
create or replace function public.chordpro_scan_directives(source text)
returns table(line_number integer, directive_name text, directive_value text)
language sql
immutable
as $$
  with normalized as (
    select replace(coalesce(source, ''), chr(13) || chr(10), chr(10))
      as normalized_source
  ),
  numbered_lines as (
    select
      line_no::integer as line_number,
      btrim(raw_line, E' \t\n\r\v\f') as trimmed_line
    from normalized,
      unnest(string_to_array(normalized.normalized_source, chr(10)))
        with ordinality as t(raw_line, line_no)
  ),
  directive_candidates as (
    select
      line_number,
      btrim(
        substring(trimmed_line from 2 for length(trimmed_line) - 2),
        E' \t\n\r\v\f'
      ) as body
    from numbered_lines
    where trimmed_line like '{%}'
      and length(trimmed_line) >= 2
  ),
  valid_directives as (
    select line_number, body, position(':' in body) as colon_pos
    from directive_candidates
    where body <> ''
  )
  select
    line_number,
    case
      when colon_pos = 0 then lower(body)
      else lower(btrim(substring(body from 1 for colon_pos - 1), E' \t\n\r\v\f'))
    end as directive_name,
    case
      when colon_pos = 0 then null
      else btrim(substring(body from colon_pos + 1), E' \t\n\r\v\f')
    end as directive_value
  from valid_directives
  order by line_number;
$$;

revoke all on function public.chordpro_scan_directives(text)
from public, anon, authenticated;
```

- [ ] **Step 4: Apply and run again to see it pass**

Run: `./scripts/db-reset.sh && BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `song derived metadata contract passed.`

- [ ] **Step 5: Wire it into the chained suite**

In `scripts/backend-write-contracts.sh`, add (directly after the `song_crud_write_contract_test_script` block, before the `organization_read_only_test_script` block):

```bash
song_derived_metadata_test_script="${SONG_DERIVED_METADATA_TEST_SCRIPT:-./scripts/tests/song-derived-metadata-contract-test.sh}"
BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 \
  bash "$song_derived_metadata_test_script"
```

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/202607290004_derive_song_metadata.sql \
  scripts/tests/song-derived-metadata-contract-test.sh \
  scripts/backend-write-contracts.sh
git commit -m "$(cat <<'EOF'
feat(db): add chordpro_scan_directives, parity-tested against the grammar

Reproduces the ChordPro directive grammar from
chordpro_line_scanner.dart:66-84 in SQL: brace-delimited lines, first-colon
name/value split, name lowercased, empty body ignored. Uses an explicit
whitespace charset for trimming since SQL trim() strips only spaces by
default and Dart's trim() strips more. This is the shared foundation the
per-field extractors in the next tasks are built on.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: `public.chordpro_derive_title`

**Files:**
- Modify: `supabase/migrations/202607290004_derive_song_metadata.sql`
- Modify: `scripts/tests/song-derived-metadata-contract-test.sh`

Extraction rule: `title` or `t` directive, last occurrence wins, value or `''` (matching `title = line.directiveValue ?? ''` at `chordpro_parser.dart:55-56,125-126`).

- [ ] **Step 1: Write the failing test**

In `scripts/tests/song-derived-metadata-contract-test.sh`, insert immediately above the `if failures:` closing block:

```python
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
```

- [ ] **Step 2: Run it and see it fail**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `psql failed` with stderr containing `function public.chordpro_derive_title(unknown) does not exist`.

- [ ] **Step 3: Write the implementation**

Append to `supabase/migrations/202607290004_derive_song_metadata.sql`:

```sql
-- title | title, t | last occurrence wins | value or ''
create or replace function public.chordpro_derive_title(source text)
returns text
language sql
immutable
as $$
  select coalesce(
    (
      select directive_value
      from public.chordpro_scan_directives(source)
      where directive_name in ('title', 't')
      order by line_number desc
      limit 1
    ),
    ''
  );
$$;

revoke all on function public.chordpro_derive_title(text)
from public, anon, authenticated;
```

- [ ] **Step 4: Apply and run again to see it pass**

Run: `./scripts/db-reset.sh && BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `song derived metadata contract passed.`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290004_derive_song_metadata.sql \
  scripts/tests/song-derived-metadata-contract-test.sh
git commit -m "$(cat <<'EOF'
feat(db): add chordpro_derive_title

title/t directive, last occurrence wins, value or '' -- matching
chordpro_parser.dart:55-56,125-126 exactly.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `public.chordpro_derive_artist`

**Files:**
- Modify: `supabase/migrations/202607290004_derive_song_metadata.sql`
- Modify: `scripts/tests/song-derived-metadata-contract-test.sh`

Extraction rule: `artist` directive, last occurrence wins, trimmed (matching `artist = line.directiveValue?.trim()` at `chordpro_parser.dart:59-60`). Note the Dart assigns on every occurrence including a bare `{artist}` with a null value, so a later bare occurrence nulls out an earlier valid one — this is intentional and pinned below.

- [ ] **Step 1: Write the failing test**

Insert above the closing block:

```python
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
```

- [ ] **Step 2: Run it and see it fail**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `psql failed` with stderr containing `function public.chordpro_derive_artist(unknown) does not exist`.

- [ ] **Step 3: Write the implementation**

Append to `supabase/migrations/202607290004_derive_song_metadata.sql`:

```sql
-- artist | artist | last occurrence wins | trimmed (assigned every
-- occurrence, so a later bare {artist} can null out an earlier value)
create or replace function public.chordpro_derive_artist(source text)
returns text
language sql
immutable
as $$
  select trim(directive_value)
  from public.chordpro_scan_directives(source)
  where directive_name = 'artist'
  order by line_number desc
  limit 1;
$$;

revoke all on function public.chordpro_derive_artist(text)
from public, anon, authenticated;
```

- [ ] **Step 4: Apply and run again to see it pass**

Run: `./scripts/db-reset.sh && BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `song derived metadata contract passed.`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290004_derive_song_metadata.sql \
  scripts/tests/song-derived-metadata-contract-test.sh
git commit -m "$(cat <<'EOF'
feat(db): add chordpro_derive_artist

artist directive, last occurrence wins, trimmed -- matching
chordpro_parser.dart:59-60, including that a later bare {artist} nulls
out an earlier value since the Dart parser assigns unconditionally on
every occurrence.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: `public.chordpro_derive_key_signature`

**Files:**
- Modify: `supabase/migrations/202607290004_derive_song_metadata.sql`
- Modify: `scripts/tests/song-derived-metadata-contract-test.sh`

Extraction rule per the spec: `key` directive, last occurrence wins, invalid values ignored.

**Important divergence from the full Dart behaviour, noted here deliberately (see plan self-review below):** `chordpro_parser.dart:61-79` only honours a `key` directive `if (!hasSeenSongContent)` — i.e. before any lyric line or section directive has appeared — and, among those, an invalid (null/empty after trim) value is *skipped* (not assigned), so it does not overwrite a previously-assigned valid value. The spec's extraction-rules table states only "last occurrence wins; invalid values are ignored" and does not mention the position gate. This function implements exactly the stated rule — last valid occurrence wins, from anywhere in the source, invalid occurrences skipped rather than overwriting — and does not gate on song content having started. This matches the spec's literal text; it does not fully replicate the Dart parser's position sensitivity.

- [ ] **Step 1: Write the failing test**

Insert above the closing block:

```python
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
```

- [ ] **Step 2: Run it and see it fail**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `psql failed` with stderr containing `function public.chordpro_derive_key_signature(unknown) does not exist`.

- [ ] **Step 3: Write the implementation**

Append to `supabase/migrations/202607290004_derive_song_metadata.sql`:

```sql
-- key_signature | key | last occurrence wins among valid values;
-- invalid (empty-after-trim) occurrences are skipped, not assigned, so they
-- do not overwrite a previously valid value.
create or replace function public.chordpro_derive_key_signature(source text)
returns text
language sql
immutable
as $$
  select nullif(trim(directive_value), '')
  from public.chordpro_scan_directives(source)
  where directive_name = 'key'
    and nullif(trim(directive_value), '') is not null
  order by line_number desc
  limit 1;
$$;

revoke all on function public.chordpro_derive_key_signature(text)
from public, anon, authenticated;
```

- [ ] **Step 4: Apply and run again to see it pass**

Run: `./scripts/db-reset.sh && BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `song derived metadata contract passed.`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290004_derive_song_metadata.sql \
  scripts/tests/song-derived-metadata-contract-test.sh
git commit -m "$(cat <<'EOF'
feat(db): add chordpro_derive_key_signature

key directive, last occurrence among valid values wins; invalid
(empty-after-trim) occurrences are skipped rather than overwriting, per
the spec's extraction-rules table. Does not replicate the Dart parser's
additional !hasSeenSongContent position gate (chordpro_parser.dart:62),
which the spec's table does not call for.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: `public.chordpro_derive_tempo_bpm`

**Files:**
- Modify: `supabase/migrations/202607290004_derive_song_metadata.sql`
- Modify: `scripts/tests/song-derived-metadata-contract-test.sh`

Extraction rule: `tempo` directive, last occurrence wins (unconditionally — matching `tempoBpm = _parseDirectiveInteger(...)` at `chordpro_parser.dart:116-122`, which reassigns on every occurrence, including to `null` if that occurrence fails to parse), integer parse, non-integer ignored (i.e. the field becomes `null`, not an error). Implemented in `plpgsql` (not `sql`) so an out-of-`integer`-range numeric string in the source (which `songs.tempo_bpm` being `integer` cannot store) is also treated as "non-integer ignored" rather than aborting the write with a low-level cast error — a direct `::integer` cast on `'99999999999'` would raise `numeric_value_out_of_range` and abort the whole transaction, which is a worse failure mode than a null tempo.

- [ ] **Step 1: Write the failing test**

Insert above the closing block:

```python
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
```

- [ ] **Step 2: Run it and see it fail**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `psql failed` with stderr containing `function public.chordpro_derive_tempo_bpm(unknown) does not exist`.

- [ ] **Step 3: Write the implementation**

Append to `supabase/migrations/202607290004_derive_song_metadata.sql`:

```sql
-- tempo_bpm | tempo | last occurrence wins (unconditionally -- a later
-- non-integer occurrence nulls an earlier valid one); integer parse,
-- non-integer (including out-of-int4-range) ignored rather than raising.
create or replace function public.chordpro_derive_tempo_bpm(source text)
returns integer
language plpgsql
immutable
as $$
declare
  v_directive_value text;
  v_result integer;
begin
  select directive_value
  into v_directive_value
  from public.chordpro_scan_directives(source)
  where directive_name = 'tempo'
  order by line_number desc
  limit 1;

  if not found then
    return null;
  end if;

  begin
    v_result := trim(v_directive_value)::integer;
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      return null;
  end;

  return v_result;
end;
$$;

revoke all on function public.chordpro_derive_tempo_bpm(text)
from public, anon, authenticated;
```

- [ ] **Step 4: Apply and run again to see it pass**

Run: `./scripts/db-reset.sh && BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `song derived metadata contract passed.`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290004_derive_song_metadata.sql \
  scripts/tests/song-derived-metadata-contract-test.sh
git commit -m "$(cat <<'EOF'
feat(db): add chordpro_derive_tempo_bpm

tempo directive, last occurrence wins unconditionally, integer parse
with non-integer (including out-of-range) ignored -- matching
chordpro_parser.dart:116-122's "non-integer ignored" rule without
letting an out-of-int4-range numeric string abort the write.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: `public.chordpro_derive_tags`

**Files:**
- Modify: `supabase/migrations/202607290004_derive_song_metadata.sql`
- Modify: `scripts/tests/song-derived-metadata-contract-test.sh`

Extraction rule: `tags` or `tag` directive, last occurrence wins, split on `,`, trim each, drop empties (matching `_parseTags` at `chordpro_parser.dart:385-396`). No matching directive, or a bare directive with a null value, both yield `{}` (not null — `songs.tags` is `not null default '{}'`).

- [ ] **Step 1: Write the failing test**

Insert above the closing block:

```python
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
```

- [ ] **Step 2: Run it and see it fail**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `psql failed` with stderr containing `function public.chordpro_derive_tags(unknown) does not exist`.

- [ ] **Step 3: Write the implementation**

Append to `supabase/migrations/202607290004_derive_song_metadata.sql`:

```sql
-- tags | tags, tag | last occurrence wins | split on ',', trim each, drop
-- empties; no matching directive (or a bare one) yields '{}', never null,
-- since songs.tags is not null default '{}'.
create or replace function public.chordpro_derive_tags(source text)
returns text[]
language sql
immutable
as $$
  select coalesce(
    (
      select array_agg(trim(tag_value))
      from (
        select directive_value
        from public.chordpro_scan_directives(source)
        where directive_name in ('tags', 'tag')
        order by line_number desc
        limit 1
      ) as last_tags,
      unnest(string_to_array(last_tags.directive_value, ',')) as tag_value
      where trim(tag_value) <> ''
    ),
    '{}'::text[]
  );
$$;

revoke all on function public.chordpro_derive_tags(text)
from public, anon, authenticated;
```

- [ ] **Step 4: Apply and run again to see it pass**

Run: `./scripts/db-reset.sh && BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `song derived metadata contract passed.`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290004_derive_song_metadata.sql \
  scripts/tests/song-derived-metadata-contract-test.sh
git commit -m "$(cat <<'EOF'
feat(db): add chordpro_derive_tags

tags/tag directive, last occurrence wins, split on comma with empties
dropped, defaulting to '{}' rather than null -- matching
chordpro_parser.dart:385-396 and the not-null tags column.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: `create_song` derives shadow metadata; drops the removed parameters

**Files:**
- Modify: `supabase/migrations/202607290004_derive_song_metadata.sql`
- Modify: `scripts/tests/song-derived-metadata-contract-test.sh`

New signature: `create_song(p_organization_id uuid, p_title text, p_chordpro_source text default null, p_requested_slug text default null, p_song_id uuid default null)` — drops `p_artist`, `p_key_signature`, `p_tempo_bpm`, `p_tags`, `p_metadata_json`. Title fallback chain: derived title if non-empty after trim, else `p_title` if non-empty, else `gen_random_uuid()::text` (mirroring the existing slug fallback chain and `songs.title not null`). `metadata_json` is inserted as `'{}'::jsonb`.

- [ ] **Step 1: Write the failing test**

Insert above the closing block:

```python
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
```

Also add the shared `sql_quote`, `dedent`, `organization_id`, `capture_error`, `fetch_json` helpers already present in the file from Task 3, plus this task's own preamble needs `organization_id` (already defined at module scope) and a fresh `dedent` import (already imported).

- [ ] **Step 2: Run it and see it fail**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `psql failed` — `create_song` still has the old 10-parameter signature, so `p_artist` resolves as a valid named parameter and the derivation assertions (checks against `created_1["title"]` etc.) fail because the client-supplied title/artist/etc. are still stored verbatim instead of derived.

- [ ] **Step 3: Write the implementation**

In `supabase/migrations/202607290004_derive_song_metadata.sql`, append:

```sql
drop function if exists public.create_song(
  uuid, text, text, text, integer, text[], text, jsonb, text, uuid
);

create or replace function public.create_song(
  p_organization_id uuid,
  p_title text,
  p_chordpro_source text default null,
  p_requested_slug text default null,
  p_song_id uuid default null
)
returns public.songs
language plpgsql
security definer
set search_path = public
as $$
declare
  created_song public.songs%rowtype;
  candidate_slug text;
  v_constraint_name text;
  v_effective_source text := coalesce(p_chordpro_source, '');
  v_derived_title text := public.chordpro_derive_title(v_effective_source);
  v_title text := coalesce(
    nullif(trim(v_derived_title), ''),
    nullif(p_title, ''),
    gen_random_uuid()::text
  );
begin
  perform public.require_song_write_access(p_organization_id);

  candidate_slug := public.song_next_slug(
    p_organization_id,
    coalesce(
      nullif(p_requested_slug, ''),
      nullif(v_title, ''),
      gen_random_uuid()::text
    )
  );

  loop
    begin
      insert into public.songs (
        id,
        organization_id,
        title,
        artist,
        key_signature,
        tempo_bpm,
        tags,
        chordpro_source,
        metadata_json,
        slug,
        version,
        base_version,
        sync_status,
        last_modified_by
      )
      values (
        coalesce(p_song_id, gen_random_uuid()),
        p_organization_id,
        v_title,
        public.chordpro_derive_artist(v_effective_source),
        public.chordpro_derive_key_signature(v_effective_source),
        public.chordpro_derive_tempo_bpm(v_effective_source),
        public.chordpro_derive_tags(v_effective_source),
        v_effective_source,
        '{}'::jsonb,
        candidate_slug,
        1,
        null,
        'synced',
        auth.uid()
      )
      returning * into created_song;

      return created_song;
    exception
      when unique_violation then
        get stacked diagnostics v_constraint_name = constraint_name;
        if v_constraint_name <> 'songs_organization_slug_unique' then
          raise;
        end if;

        candidate_slug := public.song_next_slug(p_organization_id, candidate_slug);
    end;
  end loop;

  raise exception using
    errcode = 'P0001',
    message = 'song_slug_generation_failed',
    detail = 'create_song loop terminated unexpectedly without returning a row';
end;
$$;

revoke all on function public.create_song(uuid, text, text, text, uuid)
from public, anon, authenticated;
grant execute on function public.create_song(uuid, text, text, text, uuid)
to authenticated;
```

- [ ] **Step 4: Apply and run again to see it pass**

Run: `./scripts/db-reset.sh && BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `song derived metadata contract passed.`

Note: `overwrite_song_update`'s existing (not-yet-updated) body still calls `create_song(... p_artist => ..., ...)` by name — this only breaks at *execution* time for the overwrite-recreate path (PL/pgSQL resolves callee signatures lazily, at first execution, not at `create or replace` time), and this test does not exercise that path yet. Task 10 fixes `overwrite_song_update` next.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290004_derive_song_metadata.sql \
  scripts/tests/song-derived-metadata-contract-test.sh
git commit -m "$(cat <<'EOF'
feat(db): derive song shadow metadata in create_song, drop client params

create_song now derives title, artist, key_signature, tempo_bpm and
tags from canonical ChordPro inside the security-definer body instead
of accepting them from the caller. p_artist, p_key_signature,
p_tempo_bpm, p_tags and p_metadata_json are removed from the
signature; p_title is retained only as a fallback when the source has
no title/t directive. Grants are reapplied for the new 5-parameter
signature, since dropping parameters creates a new function identity.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: `song_write_update_common`, `update_song`, `overwrite_song_update` derive on every write

**Files:**
- Modify: `supabase/migrations/202607290004_derive_song_metadata.sql`
- Modify: `scripts/tests/song-derived-metadata-contract-test.sh`

New signatures:
- `song_write_update_common(p_organization_id uuid, p_song_id uuid, p_base_version bigint, p_title text, p_chordpro_source text default null, p_enforce_version boolean default true)`
- `update_song(p_organization_id uuid, p_song_id uuid, p_base_version bigint, p_title text, p_chordpro_source text default null)`
- `overwrite_song_update(p_organization_id uuid, p_song_id uuid, p_base_version bigint, p_title text, p_requested_slug text default null, p_chordpro_source text default null)`

The effective source is `coalesce(p_chordpro_source, song.chordpro_source)` — the existing "null means unchanged" rule — and **all five shadow fields are derived from that effective source on every update**, including one that carries no new source at all. Title falls back to `coalesce(p_title, song.title)` when the effective source has no title directive. `metadata_json` is left out of the `set` list entirely (untouched).

- [ ] **Step 1: Write the failing test**

Insert above the closing block:

```python
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
            song_source_with("{title: Legacy Target}\\n{artist: Late Arrival}")
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
```

- [ ] **Step 2: Run it and see it fail**

Run: `BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `psql failed` — the old 10/11-parameter `update_song`/`overwrite_song_update`/`song_write_update_common` signatures are still in place, so calling `update_song` without the removed parameters either fails to resolve (if a required positional parameter without a default is now missing) or, where it does resolve, the shadow-metadata assertions fail because the old `coalesce(p_artist, song.artist)`-style body preserves rather than re-derives.

- [ ] **Step 3: Write the implementation**

Append to `supabase/migrations/202607290004_derive_song_metadata.sql`:

```sql
drop function if exists public.song_write_update_common(
  uuid, uuid, bigint, text, text, text, integer, text[], text, jsonb, boolean
);
drop function if exists public.update_song(
  uuid, uuid, bigint, text, text, text, integer, text[], text, jsonb
);
drop function if exists public.overwrite_song_update(
  uuid, uuid, bigint, text, text, text, text, integer, text[], text, jsonb
);

create or replace function public.song_write_update_common(
  p_organization_id uuid,
  p_song_id uuid,
  p_base_version bigint,
  p_title text,
  p_chordpro_source text default null,
  p_enforce_version boolean default true
)
returns public.songs
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_song public.songs%rowtype;
  updated_song public.songs%rowtype;
begin
  perform public.require_song_write_access(p_organization_id);

  if p_enforce_version and p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'song_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        coalesce(p_base_version::text, 'null'),
        'unknown'
      );
  end if;

  update public.songs as song
  set
    title = coalesce(
      nullif(
        trim(public.chordpro_derive_title(coalesce(p_chordpro_source, song.chordpro_source))),
        ''
      ),
      nullif(p_title, ''),
      song.title
    ),
    artist = public.chordpro_derive_artist(coalesce(p_chordpro_source, song.chordpro_source)),
    key_signature = public.chordpro_derive_key_signature(coalesce(p_chordpro_source, song.chordpro_source)),
    tempo_bpm = public.chordpro_derive_tempo_bpm(coalesce(p_chordpro_source, song.chordpro_source)),
    tags = public.chordpro_derive_tags(coalesce(p_chordpro_source, song.chordpro_source)),
    chordpro_source = coalesce(p_chordpro_source, song.chordpro_source),
    version = song.version + 1,
    base_version = coalesce(p_base_version, song.version),
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where song.organization_id = p_organization_id
    and song.id = p_song_id
    and (not p_enforce_version or song.version = p_base_version)
  returning * into updated_song;

  if found then
    return updated_song;
  end if;

  select *
  into existing_song
  from public.songs as song
  where song.organization_id = p_organization_id
    and song.id = p_song_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'song_not_found',
      detail = 'The target song does not exist in the requested organization';
  end if;

  raise exception using
    errcode = 'P0001',
    message = 'song_version_conflict',
    detail = format(
      'expected base_version %s but found current version %s',
      coalesce(p_base_version::text, 'null'),
      existing_song.version::text
    );
end;
$$;

create or replace function public.update_song(
  p_organization_id uuid,
  p_song_id uuid,
  p_base_version bigint,
  p_title text,
  p_chordpro_source text default null
)
returns public.songs
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.song_write_update_common(
    p_organization_id,
    p_song_id,
    p_base_version,
    p_title,
    p_chordpro_source,
    true
  );
end;
$$;

create or replace function public.overwrite_song_update(
  p_organization_id uuid,
  p_song_id uuid,
  p_base_version bigint,
  p_title text,
  p_requested_slug text default null,
  p_chordpro_source text default null
)
returns public.songs
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.songs as song
    where song.organization_id = p_organization_id
      and song.id = p_song_id
  ) then
    return public.create_song(
      p_organization_id => p_organization_id,
      p_title => p_title,
      p_chordpro_source => p_chordpro_source,
      p_requested_slug => p_requested_slug,
      p_song_id => p_song_id
    );
  end if;

  return public.song_write_update_common(
    p_organization_id,
    p_song_id,
    p_base_version,
    p_title,
    p_chordpro_source,
    false
  );
end;
$$;

revoke all on function public.song_write_update_common(uuid, uuid, bigint, text, text, boolean)
from public, anon, authenticated;

revoke all on function public.update_song(uuid, uuid, bigint, text, text)
from public, anon, authenticated;
grant execute on function public.update_song(uuid, uuid, bigint, text, text)
to authenticated;

revoke all on function public.overwrite_song_update(uuid, uuid, bigint, text, text, text)
from public, anon, authenticated;
grant execute on function public.overwrite_song_update(uuid, uuid, bigint, text, text, text)
to authenticated;
```

- [ ] **Step 4: Apply and run again to see it pass**

Run: `./scripts/db-reset.sh && BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-derived-metadata-contract-test.sh`
Expected: `song derived metadata contract passed.`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202607290004_derive_song_metadata.sql \
  scripts/tests/song-derived-metadata-contract-test.sh
git commit -m "$(cat <<'EOF'
feat(db): derive song shadow metadata on every update, drop client params

song_write_update_common (and therefore update_song and
overwrite_song_update) now re-derives title, artist, key_signature,
tempo_bpm and tags from coalesce(p_chordpro_source, song.chordpro_source)
on every write, including one that carries no new source -- so a
legacy row converges onto its own stored source without a backfill.
p_artist, p_key_signature, p_tempo_bpm, p_tags and p_metadata_json are
removed from both signatures. metadata_json is left untouched.
Old signatures are dropped and grants reapplied for the new ones; a
contract test pins that the old signatures are gone and the new ones
are authenticated-only.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Update `song-crud-write-contract-test.sh` for the new signatures

**Files:**
- Modify: `scripts/tests/song-crud-write-contract-test.sh`

This is its own commit so a regression here is bisectable from the derivation work in Tasks 9–10.

The existing `create_song()`/`update_song()`/`delete_song()` python helpers in this file (lines 232–304) already only pass `p_organization_id`, `p_title`, `p_chordpro_source`, and (conditionally) `p_requested_slug` — they never referenced the removed parameters, so they need no signature changes.

What **does** break is the "metadata preservation" scenario at lines 368–401: it directly `UPDATE`s a song's `artist`/`key_signature`/`tempo_bpm`/`tags` via raw SQL (bypassing the RPC), then calls `update_song()` (whose fixture ChordPro source never contains those directives) and asserts the seeded values survive unchanged. Under the new derive-on-every-write contract, that update now **re-derives** those fields from the source — which contains no such directives — so they become `null`/`{}`, not preserved. This scenario is superseded by Task 10's own rule-9 test (an update with no *new* source re-derives from the *stored* source), so it is deleted here rather than rewritten to assert the new (now-redundant) behaviour.

Deleting it also shifts the `updatable` song's version count: the deleted block's direct `UPDATE` never went through the RPC (no version bump), but the deleted `update_song(...)` call inside it did bump `version` from 2 to 3. Removing both leaves `updatable` at version 2 after `updated_once`, not 3 — so the two downstream assertions that assumed version 3 must be renumbered.

- [ ] **Step 1: Confirm the current (pre-change) test still passes against Tasks 1–10's migrations**

Run: `./scripts/db-reset.sh && BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-crud-write-contract-test.sh`
Expected: FAIL. The `metadata_target`/`metadata_preserved` assertions (`"update preserves artist"`, `"update preserves key signature"`, `"update preserves tempo"`, `"update preserves tags"`) now fail because those fields are re-derived to `null`/`{}` instead of preserved, and `assert_equal(stale_update_detail, ..., "current version 3")` may also mismatch depending on how the earlier assertions unwound. This is the "regression" this task fixes.

- [ ] **Step 2: Delete the now-false preservation block**

In `scripts/tests/song-crud-write-contract-test.sh`, delete lines 368–401 in full (the `metadata_target = fetch_json(...)` block through the `assert_equal(metadata_preserved["version"], 3, ...)` line):

```python
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
```

Use the Edit tool with this exact block as `old_string` and an empty `new_string` (remove entirely, leaving the surrounding blank lines collapsed to one).

- [ ] **Step 3: Renumber the two downstream version expectations**

`updatable` is now at version 2 (not 3) after `updated_once`, since the deleted block's own `update_song` call (the only one that bumped it to 3) is gone.

Edit the stale-update assertion:

```python
assert_equal(stale_update_sql, "P0001", "stale update sqlstate")
assert_equal(stale_update_message, "song_version_conflict", "stale update message")
assert "current version 3" in stale_update_detail, stale_update_detail
```

to:

```python
assert_equal(stale_update_sql, "P0001", "stale update sqlstate")
assert_equal(stale_update_message, "song_version_conflict", "stale update message")
assert "current version 2" in stale_update_detail, stale_update_detail
```

Edit the overwrite-update assertion:

```python
overwrite_update = update_song(
    updatable["id"],
    2,
    "Update Target Overwritten",
    overwrite=True,
    user_id=demo_user_id,
)
assert_equal(overwrite_update["version"], 4, "overwrite update version bump")
assert_equal(overwrite_update["slug"], "write-contract-update", "overwrite update preserves slug")
```

to:

```python
overwrite_update = update_song(
    updatable["id"],
    2,
    "Update Target Overwritten",
    overwrite=True,
    user_id=demo_user_id,
)
assert_equal(overwrite_update["version"], 3, "overwrite update version bump")
assert_equal(overwrite_update["slug"], "write-contract-update", "overwrite update preserves slug")
```

- [ ] **Step 4: Run it and see it pass**

Run: `./scripts/db-reset.sh && BACKEND_WRITE_CONTRACTS_SKIP_BOOTSTRAP=1 ./scripts/tests/song-crud-write-contract-test.sh`
Expected: `song CRUD write contract regression passed`

- [ ] **Step 5: Run the full chained suite once, to confirm nothing else regressed**

Run: `./scripts/backend-write-contracts.sh`
Expected: exits 0, printing a pass line for every chained script (slug parity, planning, song CRUD, song derived metadata, organization-read-only, capability search path, invitation redemption).

- [ ] **Step 6: Commit**

```bash
git add scripts/tests/song-crud-write-contract-test.sh
git commit -m "$(cat <<'EOF'
fix(test): update song CRUD contract for derive-on-every-write

The old "update preserves directly-seeded shadow metadata" scenario
assumed the pre-slice coalesce-if-absent semantics; under the new
derive-from-source-on-every-write contract, an update whose source has
no artist/key/tempo/tags directives now re-derives those fields to
null/{} rather than preserving out-of-band values, which is already
covered by the dedicated derived-metadata contract test's own
no-new-source rule. Removes the now-false assertions and renumbers the
two downstream version expectations that depended on the deleted
update call.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: ADR-026 — RLS-protected read boundary

**Files:**
- Create: `docs/architecture/decisions/ADR-026-rls-protected-read-boundary.md`

No code, no test — this task records a decision that changes nothing about the running system.

- [ ] **Step 1: Write the ADR**

Create `docs/architecture/decisions/ADR-026-rls-protected-read-boundary.md`:

```markdown
# ADR-026: RLS-Protected Read Boundary

- Status: Accepted
- Date: 2026-07-29
- Spec: `docs/specs/2026-07-29-read-boundary-and-derived-song-metadata.md`
- Plan: `docs/plans/2026-07-29-read-boundary-and-derived-song-metadata.md`
- Closes: `docs/deferred/2026-05-16-auth-schema-lint-followups.md` (read-boundary half)

## Context

The auth-invite slice (`202605160007_auth_boundary_hardening.sql`) locked
down anonymous table access and security-definer RPC execution, but
deliberately left one question open: should `authenticated` keep table-level
`SELECT` on `songs`, `plans`, and `sessions`, given that the Flutter
repositories read them directly through the Supabase table API rather than
through an RPC?

Measured surface, verified against the repository rather than assumed:

| | count |
|---|---|
| direct table **reads** (`.from(...).select(...)`) | 8 |
| direct table **writes** | **0** |
| files containing them | 3, all under `lib/src/infrastructure/` |
| tables touched | `songs` (4), `plans` (3), `sessions` (1) |

Call sites: `supabase_song_repository.dart:19,26,34`,
`supabase_song_mutation_repository.dart:13`,
`supabase_planning_repository.dart:26,38,48,63`.

The write half of this question is already closed: there are zero direct
table writes, and every mutation goes through a `security definer` RPC with
RLS denying direct DML.

## Decision

The read boundary stays on RLS-protected table reads. No repository code
changes.

RLS is the enforcement layer today, and it would remain the enforcement layer
behind a `security_invoker` view or be **re-implemented** inside a read RPC.
Replacing the reads changes who spells the query, not who enforces access —
a hand-written tenant predicate in each read RPC is a second place to get it
wrong.

The eight reads feed the local-first projection sync, which the repository
review's own §6 identifies as the highest-risk subsystem in the codebase.
Rewriting them buys no authorization guarantee and spends risk where there is
least margin.

**Consequence, stated plainly:** `authenticated` keeps table `SELECT`, so the
PostgREST and `pg_graphql` surfaces stay reachable — RLS-scoped, but
reachable. That is the accepted trade.

## Rejected alternatives

**`security_invoker` views** (available on PostgreSQL 17.6). Would narrow the
exposed surface without adding authorization logic, and is the strongest of
the alternatives considered. Rejected because the benefit is defence in
depth against a surface RLS already governs, while the cost lands on three
repositories and the projection-sync tests, and every future column has to be
tracked in two places (the table and the view).

**Read RPCs.** Tightest against table exposure, but duplicates the tenant
predicate per RPC, discards PostgREST's column-projection behaviour, and
rewrites the riskiest subsystem in the repository for no additional
authorization guarantee — RLS already enforces the predicate a hand-written
RPC would have to reimplement.

## Consequences

- No Flutter repository changes; no projection-sync test changes.
- The three read repositories continue to read `songs`, `plans`, and
  `sessions` directly through the Supabase table API under RLS.
- A future slice that wants to narrow the PostgREST/`pg_graphql` surface
  further should revisit `security_invoker` views first, since it was judged
  the strongest of the rejected alternatives — not because this ADR expects
  that to happen.
```

- [ ] **Step 2: Commit**

```bash
git add docs/architecture/decisions/ADR-026-rls-protected-read-boundary.md
git commit -m "$(cat <<'EOF'
docs(architecture): add ADR-026, keep the read boundary on RLS

Records the decision to keep authenticated table SELECT under RLS
rather than introduce read RPCs or security_invoker views, closing the
read-boundary half of the 2026-05-16 auth-schema-lint deferred item.
No code changes; the decision is that none are needed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: ADR-027 — backend-derived song metadata

**Files:**
- Create: `docs/architecture/decisions/ADR-027-backend-derived-song-metadata.md`

- [ ] **Step 1: Write the ADR**

Create `docs/architecture/decisions/ADR-027-backend-derived-song-metadata.md`:

```markdown
# ADR-027: Backend-Derived Song Shadow Metadata

- Status: Accepted
- Date: 2026-07-29
- Spec: `docs/specs/2026-07-29-read-boundary-and-derived-song-metadata.md`
- Plan: `docs/plans/2026-07-29-read-boundary-and-derived-song-metadata.md`
- Findings: SEC-4
- Closes: `docs/deferred/2026-05-09-song-write-derived-fields.md`

## Context

SEC-4 in the 2026-06-22 repository review recorded `title`, `artist`,
`key_signature`, `tempo_bpm`, `tags`, and `metadata_json` as client-derived
shadow fields, written verbatim from the client and never re-derived at the
write boundary. Verified against the code, the finding overstated the
problem for five of the six fields:

- `SongMutationRecord` (`application/song_library/song_mutation_sync_types.dart:69-78`)
  carries only `id, organizationId, slug, title, chordproSource, version,
  baseVersion` and error state — no artist, key, tempo, or tags field.
- The sync payload (`infrastructure/song_library/supabase_song_mutation_repository.dart:119-136`)
  sends only `p_organization_id, p_song_id, p_title, p_chordpro_source,
  p_requested_slug, p_base_version`.
- No code anywhere in `apps/lyron_app/lib` passes `p_artist`,
  `p_key_signature`, `p_tempo_bpm`, `p_tags`, or `p_metadata_json`.
- `metadata_json` is not referenced anywhere in the client.

The true situation was two problems, not one: `title` is genuinely
client-authoritative and can drift from its source (the real SEC-4 defect),
while `artist`, `key_signature`, `tempo_bpm`, and `tags` are never written by
the application at all — for any song created through the app they stay null
or empty forever, while the UI re-parses `chordpro_source` on read to display
them. `metadata_json` has no ChordPro origin to derive from (the parser
ignores `{meta}` entirely) and the client never writes it, so there is
nothing to enforce for it.

## Decision

`create_song` and `song_write_update_common` derive `title`, `artist`,
`key_signature`, `tempo_bpm`, and `tags` from canonical ChordPro inside the
`security definer` body. Client-supplied values for those fields are not
consulted; the parameters are removed from both RPC signatures
(`p_metadata_json` is removed too, since there is nothing to derive it from).
`p_title` is retained, but only as a fallback for when the source has no
title directive.

The write RPCs already are the write-acceptance boundary the deferred
document named: writes are RPC-only, and RLS denies direct DML. Deriving
there needs no column-type migration, and a later change to the derivation
applies on the next write rather than requiring a table rewrite.

The grammar reproduced in SQL
(`supabase/migrations/202607290004_derive_song_metadata.sql`) mirrors
`chordpro_line_scanner.dart:66-84` and the extraction rules in
`chordpro_parser.dart` field by field, pinned by unit-level contract tests
per field (`scripts/tests/song-derived-metadata-contract-test.sh`) rather
than approximated.

## Rejected alternatives

**Stored generated columns.** Structurally the strongest option, since the
client could not write the columns at all. Rejected because a `stored`
generated column is not recomputed when its expression changes, so every
future adjustment to the extraction rules would require a full table
rewrite — a poor fit for logic that will keep evolving alongside the parser.

**Validate instead of derive.** Reject a write whose client-supplied shadow
fields disagree with a server-side re-parse. Needs the same SQL extraction
anyway, and would surface as a sync failure for an offline edit — which
conflicts with the non-destructive model in ADR-020.

## On maintaining a second ChordPro implementation

Deriving in SQL does mean a second ChordPro implementation, and the finding
is itself about parser drift. Two things make this acceptable. First, the
derivation is authoritative and the client's value is discarded on
acceptance, so there is exactly one derivation that counts — drift becomes a
cosmetic difference between a provisional local display and the accepted
state, not a divergence between a record and its source. Second, the grammar
being reproduced is small and fully specified: `chordpro_line_scanner.dart:66-84`
is a fifteen-line rule, and only seven directive names matter (`title`, `t`,
`artist`, `key`, `tempo`, `tags`, `tag`). This is parity that can be pinned by
tests, not approximated.

## Known divergence

`chordpro_parser.dart:61-79` additionally gates the `key` directive on
`!hasSeenSongContent` (a `key` directive is only honoured before any lyric
line or section directive has appeared) and, among honoured occurrences,
skips invalid values without overwriting a prior valid one. The SQL
extractor (`public.chordpro_derive_key_signature`) implements the
last-valid-occurrence-wins and invalid-is-skipped halves of that rule from
anywhere in the source, without the position gate — matching this ADR's
extraction-rules table exactly, at the cost of not fully replicating the
Dart parser's position sensitivity for `key`. A source with a `key` directive
appearing only after lyric content has started will therefore derive a key
signature server-side that the Dart parser itself would have ignored. This is
accepted as an edge case narrow enough (a key directive placed after the song
body has started) not to warrant reproducing `hasSeenSongContent` tracking
across the whole scan.

## Risks accepted

- **No backfill.** Existing rows keep whatever they hold until their next
  write. A backfill would rewrite `updated_at`, `version`, and
  `last_modified_by` across the catalogue and would collide with pending
  offline mutations. An update that carries no new source still re-derives
  from the stored source, making convergence automatic and incremental
  instead.
- **A user's local title can change after sync**, if the client's parse and
  the SQL parse disagree on the same source. This is the intended direction
  of authority; the accepted title wins.
- **Breaking signature change for out-of-tree callers.** The Flutter client
  never sent the removed parameters. `scripts/tests/song-crud-write-contract-test.sh`
  is updated in this same slice; any caller outside the repository would
  break.
```

- [ ] **Step 2: Commit**

```bash
git add docs/architecture/decisions/ADR-027-backend-derived-song-metadata.md
git commit -m "$(cat <<'EOF'
docs(architecture): add ADR-027, derive song shadow metadata at write acceptance

Records why create_song and song_write_update_common now derive
title/artist/key_signature/tempo_bpm/tags from canonical ChordPro
instead of accepting them from the client, the rejected alternatives,
and the one known divergence from the Dart parser's key-directive
position gating. Closes the 2026-05-09 song-write-derived-fields
deferred item.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: Correct SEC-4 in the repository review

**Files:**
- Modify: `docs/architecture/repository-review-2026-06-22.md`

- [ ] **Step 1: Correct the SEC-4 finding body**

Replace this block (around line 254):

```markdown
**SEC-4 [verified, team-known] — client-authoritative shadow metadata.** `title`,
`artist`, `key_signature`, `tempo_bpm`, `tags`, `metadata_json` are derived client-side
from canonical ChordPro and written as shadow fields, **not enforced from source at the
write-acceptance boundary**. Client/server parser drift can desync metadata from the
canonical source. Documented in `docs/deferred/2026-05-09-song-write-derived-fields.md`.
**Recommendation**: derive shadow metadata at the backend/write-acceptance boundary;
treat client shadow fields as provisional only.
```

with:

```markdown
**SEC-4 [verified] — corrected and fixed.** The original finding overstated
the problem for five of the six named fields. Verified against the code:
`SongMutationRecord` and the sync payload never carried `artist`,
`key_signature`, `tempo_bpm`, `tags`, or `metadata_json` at all — those four
shadow fields were simply never written by the application (they stayed null
or empty for every app-created song), not "client-authoritative and
drifting." Only `title` was genuinely client-supplied and could drift from
its source. `metadata_json` has no ChordPro origin to derive from and
remains out of scope.
**Status (2026-07-29, read-boundary-and-derived-song-metadata slice):
fixed.** `create_song` and `song_write_update_common`
(`supabase/migrations/202607290004_derive_song_metadata.sql`) now derive
`title`, `artist`, `key_signature`, `tempo_bpm`, and `tags` from canonical
ChordPro inside the `security definer` write boundary; the corresponding
client-supplied RPC parameters (plus `p_metadata_json`) are removed. See
[ADR-027](decisions/ADR-027-backend-derived-song-metadata.md), pinned by
`scripts/tests/song-derived-metadata-contract-test.sh`.
```

- [ ] **Step 2: Update the summary table row**

Replace:

```markdown
| SEC-4 | Security | Song shadow fields client-authoritative, not backend-derived from ChordPro | Medium |
```

with:

```markdown
| ~~SEC-4~~ | Security | ~~Song shadow fields client-authoritative, not backend-derived from ChordPro~~ **Done (read-boundary-and-derived-song-metadata).** | Medium |
```

- [ ] **Step 3: Update the "Still open" digest**

Replace:

```markdown
**Still open** (unchanged): LF-7, LF-9, LF-T3, LF-T5, LF-T8, SEC-2, SEC-4, all
ARCH-*, all UX-*, DX-1, DX-2, and the deferred items in `docs/deferred/`.
```

with:

```markdown
**Still open** (unchanged): LF-7, LF-9, LF-T3, LF-T5, LF-T8, SEC-2, all
ARCH-*, all UX-*, DX-1, DX-2, and the deferred items in `docs/deferred/`.
```

- [ ] **Step 4: Add a "Fixed" bullet to the resolution-status digest**

In the "Resolution status" section (near the `SEC-3` bullet around line 114), add:

```markdown
- **SEC-4** (read-boundary-and-derived-song-metadata slice) — `create_song`
  and `song_write_update_common` now derive `title`, `artist`,
  `key_signature`, `tempo_bpm`, and `tags` from canonical ChordPro at the
  write-acceptance boundary instead of accepting them from the client; the
  original finding's severity was also corrected, since five of the six
  named fields were never written by the client at all rather than
  client-authoritative and drifting. ADR-027. Pinned by
  `scripts/tests/song-derived-metadata-contract-test.sh`.
```

- [ ] **Step 5: Commit**

```bash
git add docs/architecture/repository-review-2026-06-22.md
git commit -m "$(cat <<'EOF'
docs(architecture): mark SEC-4 fixed, correct its description

The original SEC-4 finding described all six shadow fields as
client-authoritative and drifting; verified against the code, five of
them were simply never written by the client at all. Corrects the
finding text and marks it fixed now that create_song and
song_write_update_common derive shadow metadata server-side.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Update architecture.md, domain-model.md, testing-strategy.md

**Files:**
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/testing/testing-strategy.md`

- [ ] **Step 1: architecture.md — document the read boundary and the song write contract**

In `docs/architecture/architecture.md`, in the `### Backend` section, immediately after the existing invitation-redemption paragraph (which ends `See [ADR-025](decisions/ADR-025-invitation-redemption-model.md).`) and before the `Backend policy helpers are responsible for:` list, insert:

```markdown
The read boundary stays on RLS-protected table reads: the Flutter
repositories read `songs`, `plans`, and `sessions` directly through the
Supabase table API, with RLS enforcing tenant visibility on every row. There
are zero direct table writes — every mutation goes through a `security
definer` RPC, with RLS denying direct DML as a second layer. See
[ADR-026](decisions/ADR-026-rls-protected-read-boundary.md).

Song writes derive their shadow metadata (`title`, `artist`,
`key_signature`, `tempo_bpm`, `tags`) from canonical `chordpro_source` inside
the `create_song` / `song_write_update_common` `security definer` bodies,
using a small SQL reproduction of the ChordPro directive grammar
(`public.chordpro_scan_directives` and five per-field
`public.chordpro_derive_*` functions). Client-supplied values for those
fields are not accepted as RPC parameters at all; `p_title` is retained only
as a fallback for sources with no title directive. See
[ADR-027](decisions/ADR-027-backend-derived-song-metadata.md).
```

- [ ] **Step 2: domain-model.md — correct the ChordPro-first rule**

In `docs/domain/domain-model.md`, replace the `ChordPro-first rule:` block under `### songs` (around line 122):

```markdown
ChordPro-first rule:

- `title`, `artist`, `key_signature`, `tempo_bpm`, `tags`, and `metadata_json` are treated as derived shadow fields refreshed from canonical ChordPro source after create, import, or save.
- These fields remain queryable and sortable, but they are not the source of truth for song content.
- The repository may keep them in sync for performance and search, but user edits should flow through ChordPro source.
```

with:

```markdown
ChordPro-first rule:

- `title`, `artist`, `key_signature`, `tempo_bpm`, and `tags` are shadow fields **derived server-side, at write acceptance**, from canonical `chordpro_source` — not accepted as client-supplied write parameters. `create_song` and `song_write_update_common` (`security definer`) re-derive all five on every write, including a write that carries no new source, so a legacy row converges onto its own stored source on its next unrelated edit. See [ADR-027](../architecture/decisions/ADR-027-backend-derived-song-metadata.md).
- `metadata_json` remains client-writable in principle but is not written by the application today; it defaults to `'{}'::jsonb` on create and is left untouched on update.
- These fields remain queryable and sortable, but they are not the source of truth for song content — `chordpro_source` is.
- The Flutter reader still re-parses `chordpro_source` locally for display; the server-derived columns exist for fast lookup, filtering, and import/export mapping, not as the client's parsing engine.
```

- [ ] **Step 3: testing-strategy.md — add the new contract tests**

In `docs/testing/testing-strategy.md`, in the `### Backend Verification` bullet list, after the invitation-redemption bullet (the last one, ending `...verified in scripts/tests/invitation-redemption-contract-test.sh`), add two new bullets:

```markdown
- `public.slugify` output parity across accented characters, punctuation runs, leading/trailing separators, and the empty result, pinned before and unchanged after the `unaccent` extension's relocation out of `public`, verified in `scripts/tests/slug-parity-contract-test.sh`
- Backend-derived song shadow metadata: the ChordPro directive-scanner grammar, each of the five per-field extractors (`title`/`t`, `artist`, `key`, `tempo`, `tags`/`tag`) including last-occurrence-wins and invalid-value handling, `create_song`'s and `song_write_update_common`'s title-fallback chain, re-derivation on an update that carries no new source, and the `create_song`/`update_song`/`overwrite_song_update`/`song_write_update_common` signature and grant contract after parameter removal, verified in `scripts/tests/song-derived-metadata-contract-test.sh`
```

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/architecture.md docs/domain/domain-model.md docs/testing/testing-strategy.md
git commit -m "$(cat <<'EOF'
docs: document the RLS read boundary and derived song write contract

architecture.md documents ADR-026 (read boundary unchanged) and
ADR-027 (song shadow metadata derived at write acceptance).
domain-model.md corrects the ChordPro-first rule to reflect
server-side derivation instead of client-side. testing-strategy.md
adds the two new contract test scripts to Backend Verification
coverage.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Remove the two closed deferred documents

**Files:**
- Remove: `docs/deferred/2026-05-16-auth-schema-lint-followups.md`
- Remove: `docs/deferred/2026-05-09-song-write-derived-fields.md`

- [ ] **Step 1: Remove both files**

```bash
git rm docs/deferred/2026-05-16-auth-schema-lint-followups.md
git rm docs/deferred/2026-05-09-song-write-derived-fields.md
```

- [ ] **Step 2: Verify nothing else references them**

Run: `grep -rn "2026-05-16-auth-schema-lint-followups\|2026-05-09-song-write-derived-fields" docs/ supabase/ apps/ scripts/ 2>/dev/null`
Expected: no output (both references were only ever the deferred docs themselves, now closed by ADR-026 and ADR-027 respectively, which are already cross-referenced from `repository-review-2026-06-22.md` and `architecture.md` in Tasks 14–15).

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
docs: remove deferred items closed by ADR-026 and ADR-027

Both deferred documents' acceptance criteria are met: the read
boundary is decided (ADR-026, no code change needed) and song shadow
metadata is now derived server-side at write acceptance (ADR-027).

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Final verification

- [ ] Run the full chained suite once more from a clean stack:

```bash
./scripts/backend-write-contracts.sh
```

Expected: exits 0, with a pass line printed for each of: slug parity, planning write contract, song CRUD write contract, song derived metadata contract, organization read-only role, capability search path, invitation redemption.

- [ ] Confirm no stray references to the removed RPC parameters remain outside this slice's own files:

```bash
grep -rn "p_metadata_json\|p_key_signature\|p_tempo_bpm" apps/lyron_app/lib scripts/manual-validation 2>/dev/null
```

Expected: no output (the spec's own evidence already established the Flutter client never sent these; this is a final confirmation, not a discovery step).

---

## Self-review against the spec

Walking `docs/specs/2026-07-29-read-boundary-and-derived-song-metadata.md` section by section:

- **Decision 1 (read boundary stays on RLS)** → Task 12 (ADR-026), no code task needed, matching the spec's own "No repository changes" scope line.
- **Decision 2 (song metadata derived at write acceptance)** → Tasks 9–10 (the two write RPCs), Task 13 (ADR-027).
- **Directive grammar parity** → Task 3 (`chordpro_scan_directives`), unit-tested against brace/colon/case/trim/CRLF rules directly, not just indirectly through the field extractors.
- **Extraction rules table (title/t, artist, key, tempo, tags/tag)** → Tasks 4–8, one function and one test section per row of the table.
- **`create_song` behaviour** (derive from `coalesce(p_chordpro_source, '')`, title fallback chain, slug follows derived title, `metadata_json` as `'{}'`) → Task 9, every clause implemented and asserted (items 1–7, 10, 11 partial, 12 partial in the testing-strategy numbering).
- **`song_write_update_common` behaviour** (effective source via `coalesce`, all five fields re-derived on every write including no-new-source, title fallback to `coalesce(p_title, song.title)`, `metadata_json` untouched) → Task 10 (items 8, 9, 13, 11/12 remaining).
- **Grants** → Task 9 and Task 10 each drop the old signature(s) they touch and reapply `revoke`/`grant` for the new ones; Task 10's test asserts both the four old signatures are gone (`to_regprocedure(...) is null`) and the new ones' `has_function_privilege` matrix.
- **`unaccent` move** → Tasks 1–2, parity-test-first as mandated, file unedited across the move to make the proof literal (`git diff` empty).
- **Testing Strategy's 13 numbered items** → all present, distributed across Tasks 3–10 as cross-referenced above.
- **Documentation list** → ADR-026 (Task 12), ADR-027 (Task 13), repository review (Task 14), architecture.md/domain-model.md/testing-strategy.md (Task 15), both deferred docs removed (Task 16).
- **Risks section** — no backfill (Task 10's design, item 9's test), title-drift-after-sync (accepted, documented in ADR-027), breaking signature change (Task 11), `unaccent` behaviour parity (Tasks 1–2), `slugify` immutable-vs-`unaccent`-stable pre-existing mismatch (out of scope per the spec; not touched by this plan).

**Placeholder scan:** no `TBD`, no "add appropriate handling," no "similar to Task N" — every task's SQL, python, and bash is complete and runnable as written.

**Type/signature consistency check:** `create_song(uuid, text, text, text, uuid)` (Task 9) is the exact signature used in Task 10's `overwrite_song_update` call and in Task 10's and Task 16's grant/regprocedure assertions. `song_write_update_common(uuid, uuid, bigint, text, text, boolean)`, `update_song(uuid, uuid, bigint, text, text)`, and `overwrite_song_update(uuid, uuid, bigint, text, text, text)` (all introduced in Task 10) match across the implementation, the grant statements, and the test assertions with no drift.

**Underspecified item found and resolved:** the spec's extraction-rules table states the `key` rule as "last occurrence wins; invalid values are ignored, as the parser does," without mentioning `chordpro_parser.dart`'s additional `!hasSeenSongContent` position gate (a `key` directive is only honoured before any lyric line or section directive appears). Task 6 and ADR-027 both implement and document the literal table rule (last valid occurrence from anywhere in the source; invalid occurrences skipped, not overwriting) without the position gate, and call out the resulting known divergence explicitly rather than silently under- or over-implementing it.
