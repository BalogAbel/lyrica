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
