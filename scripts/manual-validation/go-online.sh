#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
source "$repo_root/scripts/manual-validation/_supabase_env.sh"
supabase_script="${SUPABASE_SCRIPT:-$repo_root/scripts/supabase.sh}"

"$supabase_script" start
cache_supabase_env "$supabase_script" >/dev/null

cat <<'EOF'
Local Supabase started.
The app can now refresh the authenticated song catalog again.
EOF
