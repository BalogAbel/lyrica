#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR/.."

supabase_script="${SUPABASE_SCRIPT:-./scripts/supabase.sh}"

if ! stop_output="$("$supabase_script" stop 2>&1)"; then
  if grep -q "is not running" <<<"$stop_output"; then
    printf '%s\n' "$stop_output"
    exit 0
  fi

  printf '%s\n' "$stop_output" >&2
  exit 1
fi

printf '%s\n' "$stop_output"
