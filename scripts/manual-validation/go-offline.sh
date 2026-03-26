#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
supabase_script="${SUPABASE_SCRIPT:-$repo_root/scripts/supabase.sh}"

"$supabase_script" stop

cat <<'EOF'
Local Supabase stopped.
The app should now rely on the cached authenticated catalog if one was fetched earlier.
EOF
