#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"

raw_output=$'Connecting to local database...\n{\n  "rows": [\n    {\n      "membership_count": "1"\n    }\n  ]\n}\nA new version of Supabase CLI is available: v2.84.2 (currently installed v2.83.0)\nWe recommend updating regularly for new features and bug fixes: https://supabase.com/docs/guides/cli/getting-started#updating-the-supabase-cli\n'

parsed_json="$(
  printf '%s' "$raw_output" | python3 "$repo_root/scripts/extract_supabase_json.py"
)"

PARSED_JSON="$parsed_json" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["PARSED_JSON"])
rows = payload.get("rows", [])
if len(rows) != 1 or rows[0]["membership_count"] != "1":
    raise SystemExit(f"unexpected payload: {payload!r}")
PY
