#!/usr/bin/env bash
set -euo pipefail

# Line-coverage ratchet (DX-2).
#
# Reads an lcov report that a prior `flutter test --coverage` produced and fails
# when line coverage drops below the threshold. The threshold is the value
# measured when the gate was introduced, so it ratchets upward as coverage
# improves instead of failing on the day it lands. Raise it when coverage rises;
# never lower it to make a red build green.
#
# This script does not run the tests. ./scripts/verify.sh already runs them once
# with --coverage and then calls this, so the suite is not executed twice.

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

lcov_path="${COVERAGE_LCOV_PATH:-apps/lyron_app/coverage/lcov.info}"
minimum="${COVERAGE_MINIMUM_PERCENT:-72}"

if [[ ! -f "$lcov_path" ]]; then
  echo "Coverage report not found at $lcov_path." >&2
  echo "Run 'flutter test --coverage' in apps/lyron_app first, or use ./scripts/verify.sh." >&2
  exit 1
fi

python3 - "$lcov_path" "$minimum" <<'PY'
import sys

lcov_path, minimum_raw = sys.argv[1], sys.argv[2]
minimum = float(minimum_raw)

found = hit = 0
with open(lcov_path) as handle:
    for line in handle:
        if line.startswith("LF:"):
            found += int(line[3:])
        elif line.startswith("LH:"):
            hit += int(line[3:])

if found == 0:
    raise SystemExit(f"coverage gate failed: {lcov_path} reports no instrumented lines")

percent = 100.0 * hit / found

if percent + 1e-9 < minimum:
    raise SystemExit(
        "coverage gate failed: line coverage "
        f"{percent:.2f}% ({hit}/{found}) is below the {minimum:.2f}% threshold"
    )

print(
    f"coverage gate passed: line coverage {percent:.2f}% ({hit}/{found}) "
    f"meets the {minimum:.2f}% threshold"
)
PY
