#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log_file="$tmp_dir/log.txt"
checklist_file="$tmp_dir/checklist.txt"
supabase_env_file="$tmp_dir/supabase-env.txt"
supabase_state_file="$tmp_dir/supabase-state.txt"

cat >"$tmp_dir/mock-supabase.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'supabase:%s\n' "$*" >>"$LOG_FILE"
state_file="${SUPABASE_STATE_FILE:?}"

case "${1:-}" in
  start)
    printf 'online\n' >"$state_file"
    ;;
  stop)
    printf 'offline\n' >"$state_file"
    ;;
esac

if [[ "${1:-}" == "status" && "${2:-}" == "-o" && "${3:-}" == "env" ]]; then
  if [[ "$(cat "$state_file" 2>/dev/null || printf 'offline\n')" != "online" ]]; then
    exit 1
  fi
  cat <<ENV
API_URL=http://127.0.0.1:54321
ANON_KEY=test-anon-key
ENV
  exit 0
fi
exit 0
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
SUPABASE_STATE_FILE="$supabase_state_file" \
SUPABASE_ENV_FILE="$supabase_env_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
DB_RESET_SCRIPT="$tmp_dir/mock-db-reset.sh" \
PROVISION_DEMO_USER_SCRIPT="$tmp_dir/mock-provision.sh" \
FLUTTER_BIN="$tmp_dir/mock-flutter" \
FLUTTER_DEVICE=chrome \
"$repo_root/scripts/manual-validation/setup-local-first.sh"

LOG_FILE="$log_file" \
SUPABASE_STATE_FILE="$supabase_state_file" \
SUPABASE_ENV_FILE="$supabase_env_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
DB_RESET_SCRIPT="$tmp_dir/mock-db-reset.sh" \
PROVISION_DEMO_USER_SCRIPT="$tmp_dir/mock-provision.sh" \
"$repo_root/scripts/manual-validation/reset-validation-state.sh"

LOG_FILE="$log_file" \
SUPABASE_STATE_FILE="$supabase_state_file" \
SUPABASE_ENV_FILE="$supabase_env_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
FLUTTER_BIN="$tmp_dir/mock-flutter" \
FLUTTER_DEVICE=chrome \
"$repo_root/scripts/manual-validation/run-local-first-app.sh" --web-port 4010

LOG_FILE="$log_file" \
SUPABASE_STATE_FILE="$supabase_state_file" \
SUPABASE_ENV_FILE="$supabase_env_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
"$repo_root/scripts/manual-validation/go-offline.sh"

LOG_FILE="$log_file" \
SUPABASE_STATE_FILE="$supabase_state_file" \
SUPABASE_ENV_FILE="$supabase_env_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
FLUTTER_BIN="$tmp_dir/mock-flutter" \
FLUTTER_DEVICE=chrome \
"$repo_root/scripts/manual-validation/run-local-first-app.sh" --web-port 4011

LOG_FILE="$log_file" \
SUPABASE_STATE_FILE="$supabase_state_file" \
SUPABASE_ENV_FILE="$supabase_env_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
FLUTTER_BIN="$tmp_dir/mock-flutter" \
FLUTTER_DEVICE=emulator-5554 \
"$repo_root/scripts/manual-validation/run-local-first-app.sh"

LOG_FILE="$log_file" \
SUPABASE_STATE_FILE="$supabase_state_file" \
SUPABASE_ENV_FILE="$supabase_env_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
"$repo_root/scripts/manual-validation/go-online.sh"

"$repo_root/scripts/manual-validation/print-checklist.sh" >"$checklist_file"

python3 - <<'PY' "$log_file" "$checklist_file" "$supabase_env_file"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    "supabase:start",
    "db-reset",
    "provision",
    "supabase:status -o env",
    "db-reset",
    "provision",
    "supabase:status -o env",
    "flutter:run -d chrome --target lib/main.dart --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=test-anon-key --web-port 4010",
    "supabase:stop",
    "supabase:status -o env",
    "flutter:run -d chrome --target lib/main.dart --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=test-anon-key --web-port 4011",
    "supabase:status -o env",
    "flutter:run -d emulator-5554 --target lib/main.dart --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_ANON_KEY=test-anon-key",
    "supabase:start",
    "supabase:status -o env",
]

if lines != expected:
    raise SystemExit(f"unexpected log: {lines!r}")

checklist = Path(sys.argv[2]).read_text()
required_phrases = [
    "Online launch",
    "Offline relaunch from cache",
    "Refresh failure while cached data remains visible",
    "Explicit sign-out removes cached authenticated access",
]

for phrase in required_phrases:
    if phrase not in checklist:
        raise SystemExit(f"missing checklist phrase: {phrase!r}")

cached_env = Path(sys.argv[3]).read_text().splitlines()
expected_env = [
    "API_URL=http://127.0.0.1:54321",
    "ANON_KEY=test-anon-key",
]
if cached_env != expected_env:
    raise SystemExit(f"unexpected cached env: {cached_env!r}")
PY
