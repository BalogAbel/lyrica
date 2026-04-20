#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

supabase_script="${SUPABASE_SCRIPT:-./scripts/supabase.sh}"

if ! reset_output="$("$supabase_script" db reset 2>&1)"; then
  if grep -Eq "is not running|No such container|failed to inspect container health" <<<"$reset_output"; then
    printf '%s\n' "$reset_output"
  else
    printf '%s\n' "$reset_output" >&2
    exit 1
  fi
else
  printf '%s\n' "$reset_output"
fi

"$supabase_script" start
