#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"

db_reset_script="${DB_RESET_SCRIPT:-$repo_root/scripts/db-reset.sh}"
provision_demo_user_script="${PROVISION_DEMO_USER_SCRIPT:-$repo_root/scripts/provision-local-demo-user.sh}"

"$db_reset_script"
"$provision_demo_user_script"

cat <<'EOF'
Validation state reset complete.
Re-launch the app and re-fetch the catalog before testing offline relaunch again.
EOF
