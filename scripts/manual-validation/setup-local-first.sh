#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
source "$repo_root/scripts/manual-validation/_supabase_env.sh"

supabase_script="${SUPABASE_SCRIPT:-$repo_root/scripts/supabase.sh}"
db_reset_script="${DB_RESET_SCRIPT:-$repo_root/scripts/db-reset.sh}"
provision_demo_user_script="${PROVISION_DEMO_USER_SCRIPT:-$repo_root/scripts/provision-local-demo-user.sh}"

"$supabase_script" start
"$db_reset_script"
"$provision_demo_user_script"
cache_supabase_env "$supabase_script" >/dev/null

cat <<'EOF'
Local-first manual validation environment is ready.

Next steps:
1. Run ./scripts/manual-validation/run-local-first-app.sh
2. Sign in with demo@lyron.local / LyronDemo123!
3. Load the song list and open at least one song before going offline
4. Use ./scripts/manual-validation/print-checklist.sh while validating
EOF
