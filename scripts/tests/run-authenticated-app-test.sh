#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log_file="$tmp_dir/log.txt"

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
ANON_KEY=test-anon-key
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

cat >"$tmp_dir/mock-flutter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'flutter:%s\n' "$*" >>"$LOG_FILE"
EOF

chmod +x \
  "$tmp_dir/mock-supabase.sh" \
  "$tmp_dir/mock-db-reset.sh" \
  "$tmp_dir/mock-provision.sh" \
  "$tmp_dir/mock-flutter"

LOG_FILE="$log_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
DB_RESET_SCRIPT="$tmp_dir/mock-db-reset.sh" \
PROVISION_DEMO_USER_SCRIPT="$tmp_dir/mock-provision.sh" \
FLUTTER_BIN="$tmp_dir/mock-flutter" \
"$repo_root/scripts/run-authenticated-app.sh" --dart-define=EXTRA_FLAG=1

LOG_FILE="$log_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
DB_RESET_SCRIPT="$tmp_dir/mock-db-reset.sh" \
PROVISION_DEMO_USER_SCRIPT="$tmp_dir/mock-provision.sh" \
FLUTTER_BIN="$tmp_dir/mock-flutter" \
FLUTTER_DEVICE=emulator-5554 \
"$repo_root/scripts/run-authenticated-app.sh"

python3 - <<'PY' "$log_file"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    "supabase:start",
    "db-reset",
    "provision",
    "supabase:status -o env",
    "flutter:run -d chrome --target lib/main.dart --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=test-anon-key --dart-define=EXTRA_FLAG=1",
    "supabase:start",
    "db-reset",
    "provision",
    "supabase:status -o env",
    "flutter:run -d emulator-5554 --target lib/main.dart --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_ANON_KEY=test-anon-key",
]

if lines != expected:
    raise SystemExit(f"unexpected log: {lines!r}")
PY
