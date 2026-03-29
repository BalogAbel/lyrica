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

cat >"$tmp_dir/mock-adb" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'adb:%s\n' "$*" >>"$LOG_FILE"

if [[ "${1:-}" == "-s" && "${3:-}" == "get-state" ]]; then
  case "${2:-}" in
    adb-R52T104VT8A-s0a8pF._adb-tls-connect._tcp|R52T104VT8A)
      printf 'device\n'
      exit 0
      ;;
  esac
  exit 1
fi
EOF

chmod +x \
  "$tmp_dir/mock-supabase.sh" \
  "$tmp_dir/mock-db-reset.sh" \
  "$tmp_dir/mock-provision.sh" \
  "$tmp_dir/mock-flutter" \
  "$tmp_dir/mock-adb"

missing_adb_stderr="$tmp_dir/missing-adb.stderr"

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

LOG_FILE="$log_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
DB_RESET_SCRIPT="$tmp_dir/mock-db-reset.sh" \
PROVISION_DEMO_USER_SCRIPT="$tmp_dir/mock-provision.sh" \
FLUTTER_BIN="$tmp_dir/mock-flutter" \
ADB_BIN="$tmp_dir/mock-adb" \
FLUTTER_DEVICE=adb-R52T104VT8A-s0a8pF._adb-tls-connect._tcp \
"$repo_root/scripts/run-authenticated-app.sh"

LOG_FILE="$log_file" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
DB_RESET_SCRIPT="$tmp_dir/mock-db-reset.sh" \
PROVISION_DEMO_USER_SCRIPT="$tmp_dir/mock-provision.sh" \
FLUTTER_BIN="$tmp_dir/mock-flutter" \
ADB_BIN="$tmp_dir/mock-adb" \
FLUTTER_DEVICE=R52T104VT8A \
"$repo_root/scripts/run-authenticated-app.sh"

if LOG_FILE="$log_file" \
  SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
  DB_RESET_SCRIPT="$tmp_dir/mock-db-reset.sh" \
  PROVISION_DEMO_USER_SCRIPT="$tmp_dir/mock-provision.sh" \
  FLUTTER_BIN="$tmp_dir/mock-flutter" \
  ADB_BIN="$tmp_dir/does-not-exist-adb" \
  FLUTTER_DEVICE=R52T104VT8A \
  "$repo_root/scripts/run-authenticated-app.sh" \
  2>"$missing_adb_stderr"; then
  echo "expected missing adb launch to fail" >&2
  exit 1
fi

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
    "supabase:start",
    "db-reset",
    "provision",
    "supabase:status -o env",
    "adb:-s adb-R52T104VT8A-s0a8pF._adb-tls-connect._tcp get-state",
    "adb:-s adb-R52T104VT8A-s0a8pF._adb-tls-connect._tcp reverse tcp:54321 tcp:54321",
    "flutter:run -d adb-R52T104VT8A-s0a8pF._adb-tls-connect._tcp --target lib/main.dart --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=test-anon-key",
    "supabase:start",
    "db-reset",
    "provision",
    "supabase:status -o env",
    "adb:-s R52T104VT8A get-state",
    "adb:-s R52T104VT8A reverse tcp:54321 tcp:54321",
    "flutter:run -d R52T104VT8A --target lib/main.dart --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=test-anon-key",
    "supabase:start",
    "db-reset",
    "provision",
    "supabase:status -o env",
]

if lines != expected:
    raise SystemExit(f"unexpected log: {lines!r}")
PY

if ! grep -q "Missing adb binary" "$missing_adb_stderr"; then
  echo "expected missing adb error" >&2
  exit 1
fi
