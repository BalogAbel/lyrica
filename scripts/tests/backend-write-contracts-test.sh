#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log_file="$tmp_dir/log.txt"

cat >"$tmp_dir/mock-planning-write-contract.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "planning-write-contract:$*" >>"$LOG_FILE"
EOF

cat >"$tmp_dir/mock-song-crud-write-contract.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "song-crud-write-contract:$*" >>"$LOG_FILE"
EOF

cat >"$tmp_dir/mock-supabase.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "supabase:$*" >>"$LOG_FILE"
if [[ "${1:-}" == "start" ]]; then
  exit 0
fi
if [[ "${1:-}" == "status" && "${2:-}" == "-o" && "${3:-}" == "env" ]]; then
  cat <<ENV
API_URL=http://127.0.0.1:54321
ENV
  exit 0
fi
echo "unexpected supabase args: $*" >&2
exit 1
EOF

cat >"$tmp_dir/mock-db-reset.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "db-reset" >>"$LOG_FILE"
EOF

cat >"$tmp_dir/mock-provision.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "provision" >>"$LOG_FILE"
EOF

cat >"$tmp_dir/mock-curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF

chmod +x \
  "$tmp_dir/mock-planning-write-contract.sh" \
  "$tmp_dir/mock-song-crud-write-contract.sh" \
  "$tmp_dir/mock-supabase.sh" \
  "$tmp_dir/mock-db-reset.sh" \
  "$tmp_dir/mock-provision.sh" \
  "$tmp_dir/mock-curl"

LOG_FILE="$log_file" \
PLANNING_WRITE_CONTRACT_TEST_SCRIPT="$tmp_dir/mock-planning-write-contract.sh" \
SONG_CRUD_WRITE_CONTRACT_TEST_SCRIPT="$tmp_dir/mock-song-crud-write-contract.sh" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
DB_RESET_SCRIPT="$tmp_dir/mock-db-reset.sh" \
PROVISION_DEMO_USER_SCRIPT="$tmp_dir/mock-provision.sh" \
PATH="$tmp_dir:$PATH" \
"$repo_root/scripts/backend-write-contracts.sh"

python3 - <<'PY' "$log_file"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    "supabase:start",
    "db-reset",
    "supabase:status -o env",
    "provision",
    "planning-write-contract:",
    "song-crud-write-contract:",
]

if lines != expected:
    raise SystemExit(f"unexpected log: {lines!r}")
PY
