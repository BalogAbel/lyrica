#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

supabase_script="${SUPABASE_SCRIPT:-./scripts/supabase.sh}"

if ! compgen -G "supabase/migrations/*.sql" >/dev/null; then
  echo "No Supabase migrations found under supabase/migrations/."
  exit 1
fi

"$supabase_script" start
"$supabase_script" db lint
