#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

supabase_script="${SUPABASE_SCRIPT:-./scripts/supabase.sh}"

"$supabase_script" stop
