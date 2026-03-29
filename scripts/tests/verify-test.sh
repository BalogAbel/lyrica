#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log_file="$tmp_dir/log.txt"

cat >"$tmp_dir/mock-check-migrations.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "check-migrations" >>"$LOG_FILE"
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
ANON_KEY=test-anon-key
SERVICE_ROLE_KEY=test-service-role-key
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

cat >"$tmp_dir/mock-provision-test.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "provision-test" >>"$LOG_FILE"
EOF

cat >"$tmp_dir/mock-manual-validation-test.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "manual-validation-test" >>"$LOG_FILE"
EOF

cat >"$tmp_dir/mock-dart" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'dart:%s\n' "$*" >>"$LOG_FILE"
EOF

cat >"$tmp_dir/mock-flutter" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'flutter:%s\n' "$*" >>"$LOG_FILE"
EOF

chmod +x \
  "$tmp_dir/mock-check-migrations.sh" \
  "$tmp_dir/mock-supabase.sh" \
  "$tmp_dir/mock-db-reset.sh" \
  "$tmp_dir/mock-provision.sh" \
  "$tmp_dir/mock-provision-test.sh" \
  "$tmp_dir/mock-manual-validation-test.sh" \
  "$tmp_dir/mock-dart" \
  "$tmp_dir/mock-flutter"

LOG_FILE="$log_file" \
CHECK_MIGRATIONS_SCRIPT="$tmp_dir/mock-check-migrations.sh" \
SUPABASE_SCRIPT="$tmp_dir/mock-supabase.sh" \
DB_RESET_SCRIPT="$tmp_dir/mock-db-reset.sh" \
PROVISION_DEMO_USER_SCRIPT="$tmp_dir/mock-provision.sh" \
PROVISION_DEMO_USER_TEST_SCRIPT="$tmp_dir/mock-provision-test.sh" \
MANUAL_VALIDATION_SCRIPTS_TEST_SCRIPT="$tmp_dir/mock-manual-validation-test.sh" \
DART_BIN="$tmp_dir/mock-dart" \
FLUTTER_BIN="$tmp_dir/mock-flutter" \
"$repo_root/scripts/verify.sh"

python3 - <<'PY' "$log_file"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    "dart:format --output=none --set-exit-if-changed lib test",
    "flutter:analyze",
    "flutter:test",
    "check-migrations",
    "db-reset",
    "provision",
    "provision-test",
    "supabase:status -o env",
    "flutter:test test/integration/authenticated_song_reader_flow_test.dart --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=test-anon-key --dart-define=SERVICE_ROLE_KEY=test-service-role-key",
    "flutter:test test/integration/local_first_authenticated_song_reader_flow_test.dart --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_ANON_KEY=test-anon-key --dart-define=SERVICE_ROLE_KEY=test-service-role-key",
    "manual-validation-test",
]

if lines != expected:
    raise SystemExit(f"unexpected log: {lines!r}")
PY
