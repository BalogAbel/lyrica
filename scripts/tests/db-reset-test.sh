#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log_file="$tmp_dir/log.txt"

cat >"$tmp_dir/mock-supabase.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'supabase:%s\n' "$*" >>"$LOG_FILE"
if [[ "${1:-}" == "db" && "${2:-}" == "reset" ]]; then
  echo "Stopping containers..."
  echo "Stopped supabase local development setup."
  echo "supabase start is not running." >&2
  echo "failed to inspect container health: No such container: supabase_db_lyron" >&2
  exit 1
fi
if [[ "${1:-}" == "start" ]]; then
  exit 0
fi
echo "unexpected supabase args: $*" >&2
exit 1
EOF

chmod +x "$tmp_dir/mock-supabase.sh"

LOG_FILE="$log_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
"$repo_root/scripts/db-reset.sh"

python3 - <<'PY' "$log_file"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    "supabase:db reset",
    "supabase:start",
]

if lines != expected:
    raise SystemExit(f"unexpected log: {lines!r}")
PY
