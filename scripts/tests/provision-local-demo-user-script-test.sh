#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log_file="$tmp_dir/log.txt"
query_counter_file="$tmp_dir/query-counter.txt"
: >"$query_counter_file"

cat >"$tmp_dir/mock-supabase.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'supabase:%s\n' "$*" >>"$LOG_FILE"

if [[ "${1:-}" == "start" ]]; then
  exit 0
fi

if [[ "${1:-}" == "db" && "${2:-}" == "query" && "${3:-}" == "-o" && "${4:-}" == "json" ]]; then
  count="$(cat "$QUERY_COUNTER_FILE")"
  count=$((count + 1))
  printf '%s' "$count" >"$QUERY_COUNTER_FILE"

  if [[ "$count" -lt 3 ]]; then
    cat <<JSON
{"rows":[]}
JSON
    exit 0
  fi

  cat <<JSON
{"rows":[{"membership_count":"1"}]}
JSON
  exit 0
fi

if [[ "${1:-}" == "db" && "${2:-}" == "query" ]]; then
  cat <<JSON
{"rows":[{"diagnostic":"ok"}]}
JSON
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

cat >"$tmp_dir/mock-sleep.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sleep:%s\n' "$*" >>"$LOG_FILE"
EOF

chmod +x \
  "$tmp_dir/mock-supabase.sh" \
  "$tmp_dir/mock-db-reset.sh" \
  "$tmp_dir/mock-provision.sh" \
  "$tmp_dir/mock-sleep.sh"

LOG_FILE="$log_file" \
QUERY_COUNTER_FILE="$query_counter_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
DB_RESET_SCRIPT="$tmp_dir/mock-db-reset.sh" \
PROVISION_DEMO_USER_SCRIPT="$tmp_dir/mock-provision.sh" \
SLEEP_BIN="$tmp_dir/mock-sleep.sh" \
PROVISION_USER_QUERY_MAX_ATTEMPTS=4 \
PROVISION_USER_QUERY_RETRY_DELAY_SECONDS=0 \
bash "$repo_root/scripts/tests/provision-local-demo-user-test.sh"

python3 - <<'PY' "$log_file"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
if lines[:4] != ["supabase:start", "db-reset", "provision", "provision"]:
    raise SystemExit(f"unexpected setup log: {lines!r}")

query_invocations = sum(1 for line in lines if line == "supabase:db query -o json ")
if query_invocations != 3:
    raise SystemExit(f"expected 3 query attempts, got {query_invocations}: {lines!r}")

sleep_invocations = [line for line in lines if line.startswith("sleep:")]
if sleep_invocations != ["sleep:0", "sleep:0"]:
    raise SystemExit(f"unexpected sleeps: {sleep_invocations!r}")
PY
