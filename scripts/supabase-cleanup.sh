#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR/.."

supabase_script="${SUPABASE_SCRIPT:-./scripts/supabase.sh}"

"$supabase_script" stop
