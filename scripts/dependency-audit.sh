#!/usr/bin/env bash
set -euo pipefail

# Dependency audit gate (DX-2).
#
# `dart pub outdated --json` reports three security-relevant flags per package
# that a plain version comparison misses: whether the locked version is affected
# by a published advisory, whether it was retracted, and whether the package is
# discontinued. Those are the signals worth failing a build over.
#
# It also reports `upgradable`, the newest version the declared constraints
# already allow. A direct dependency whose locked version is behind its own
# constraint means the lockfile is stale — actionable, and a one-command fix.
#
# Deliberately NOT a failure: a package whose `latest` is behind a major the
# constraints do not allow. Those need a migration, not a gate; see
# docs/deferred/ for any that are tracked.

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

flutter_bin="${FLUTTER_BIN:-flutter}"
app_dir="${DEPENDENCY_AUDIT_APP_DIR:-apps/lyron_app}"
report_path="${DEPENDENCY_AUDIT_REPORT_PATH:-}"

if [[ -z "$report_path" ]]; then
  # Explicit template with trailing X's rather than `mktemp -t prefix`: GNU
  # mktemp requires at least three X's, while BSD accepts a bare prefix, so the
  # bare form works on macOS and fails on Linux CI.
  report_path="$(mktemp "${TMPDIR:-/tmp}/dependency-audit.XXXXXX")"
  trap 'rm -f "$report_path"' EXIT
  (cd "$app_dir" && "$flutter_bin" pub outdated --json) >"$report_path"
fi

python3 - "$report_path" <<'PY'
import json
import sys

with open(sys.argv[1]) as handle:
    report = json.load(handle)

packages = report.get("packages", [])
if not packages:
    raise SystemExit("dependency audit failed: pub outdated reported no packages")

def version_of(package, key):
    return (package.get(key) or {}).get("version")

advisories = []
retracted = []
discontinued = []
stale = []

for package in packages:
    name = package["package"]
    kind = package.get("kind")

    # Security flags apply to every package, transitive included: a vulnerable
    # transitive dependency ships just the same.
    if package.get("isCurrentAffectedByAdvisory"):
        advisories.append(f"{name} {version_of(package, 'current')} ({kind})")
    if package.get("isCurrentRetracted"):
        retracted.append(f"{name} {version_of(package, 'current')} ({kind})")
    if package.get("isDiscontinued"):
        discontinued.append(f"{name} ({kind})")

    # Staleness only for what this repository declares. A transitive package
    # behind its own constraint is the direct dependency's business.
    if kind in ("direct", "dev"):
        current = version_of(package, "current")
        upgradable = version_of(package, "upgradable")
        if current and upgradable and current != upgradable:
            stale.append(f"{name} {current} -> {upgradable} ({kind})")

failures = []
if advisories:
    failures.append("locked versions affected by a published advisory:\n    " + "\n    ".join(advisories))
if retracted:
    failures.append("locked versions that were retracted:\n    " + "\n    ".join(retracted))
if discontinued:
    failures.append("discontinued packages:\n    " + "\n    ".join(discontinued))
if stale:
    failures.append(
        "declared dependencies behind their own constraints "
        "(run `flutter pub upgrade`):\n    " + "\n    ".join(stale)
    )

if failures:
    raise SystemExit("dependency audit failed:\n  " + "\n  ".join(failures))

print(
    f"dependency audit passed: {len(packages)} packages, no advisories, "
    "nothing retracted or discontinued, and every declared dependency is at the "
    "newest version its constraints allow"
)
PY
