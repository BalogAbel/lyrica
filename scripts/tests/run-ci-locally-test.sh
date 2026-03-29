#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

log_file="$tmp_dir/log.txt"

cat >"$tmp_dir/mock-bootstrap.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "bootstrap" >>"$LOG_FILE"
EOF

cat >"$tmp_dir/mock-bootstrap-supabase.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "bootstrap-supabase" >>"$LOG_FILE"
EOF

cat >"$tmp_dir/mock-verify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "verify" >>"$LOG_FILE"
EOF

cat >"$tmp_dir/mock-check-migrations.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "check-migrations" >>"$LOG_FILE"
EOF

chmod +x \
  "$tmp_dir/mock-bootstrap.sh" \
  "$tmp_dir/mock-bootstrap-supabase.sh" \
  "$tmp_dir/mock-verify.sh" \
  "$tmp_dir/mock-check-migrations.sh"

LOG_FILE="$log_file" \
BOOTSTRAP_SCRIPT="$tmp_dir/mock-bootstrap.sh" \
BOOTSTRAP_SUPABASE_SCRIPT="$tmp_dir/mock-bootstrap-supabase.sh" \
VERIFY_SCRIPT="$tmp_dir/mock-verify.sh" \
CHECK_MIGRATIONS_SCRIPT="$tmp_dir/mock-check-migrations.sh" \
"$repo_root/scripts/run-ci-locally.sh"

python3 - <<'PY' "$log_file"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    "bootstrap",
    "verify",
    "bootstrap-supabase",
    "check-migrations",
]

if lines != expected:
    raise SystemExit(f"unexpected all-job log: {lines!r}")
PY

: >"$log_file"

LOG_FILE="$log_file" \
BOOTSTRAP_SCRIPT="$tmp_dir/mock-bootstrap.sh" \
BOOTSTRAP_SUPABASE_SCRIPT="$tmp_dir/mock-bootstrap-supabase.sh" \
VERIFY_SCRIPT="$tmp_dir/mock-verify.sh" \
CHECK_MIGRATIONS_SCRIPT="$tmp_dir/mock-check-migrations.sh" \
"$repo_root/scripts/run-ci-locally.sh" verify

python3 - <<'PY' "$log_file"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    "bootstrap",
    "verify",
]

if lines != expected:
    raise SystemExit(f"unexpected verify-job log: {lines!r}")
PY

: >"$log_file"

LOG_FILE="$log_file" \
BOOTSTRAP_SCRIPT="$tmp_dir/mock-bootstrap.sh" \
BOOTSTRAP_SUPABASE_SCRIPT="$tmp_dir/mock-bootstrap-supabase.sh" \
VERIFY_SCRIPT="$tmp_dir/mock-verify.sh" \
CHECK_MIGRATIONS_SCRIPT="$tmp_dir/mock-check-migrations.sh" \
"$repo_root/scripts/run-ci-locally.sh" migrations

python3 - <<'PY' "$log_file"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
expected = [
    "bootstrap-supabase",
    "check-migrations",
]

if lines != expected:
    raise SystemExit(f"unexpected migrations-job log: {lines!r}")
PY
