#!/usr/bin/env bash
set -euo pipefail

# Regenerates the widget goldens on Linux/amd64, the platform CI compares them
# on (docs/testing/testing-strategy.md, "Reader chrome goldens"). Other hosts
# render anti-aliasing a little differently, so goldens are never generated on
# them, and the golden tests skip themselves there.
#
# Usage:
#   ./scripts/update-goldens.sh            regenerate every golden test file
#   ./scripts/update-goldens.sh --check    compare only, change nothing
#   ./scripts/update-goldens.sh [--check] <test file>...
#     (paths relative to apps/lyron_app, e.g.
#      test/presentation/song_reader/widgets/song_reader_key_controls_golden_test.dart)
#
# Needs Docker. On an arm64 host the amd64 image runs under emulation
# (Docker Desktop: enable Rosetta for x86_64/amd64 emulation).

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$repo_root/apps/lyron_app"
image="${LYRON_GOLDENS_IMAGE:-lyron-goldens:3.44.9}"

update_flag="--update-goldens"
if [[ "${1:-}" == "--check" ]]; then
  update_flag=""
  shift
fi

golden_tests=("$@")
if [[ ${#golden_tests[@]} -eq 0 ]]; then
  while IFS= read -r file; do
    golden_tests+=("${file#"$app_dir"/}")
  done < <(grep -rl "matchesGoldenFile" "$app_dir/test" | sort)
fi

if [[ ${#golden_tests[@]} -eq 0 ]]; then
  echo "No golden test files found." >&2
  exit 1
fi

docker build --quiet --platform linux/amd64 -t "$image" \
  "$repo_root/tooling/goldens" >/dev/null

out_dir="$(mktemp -d)"
trap 'rm -rf "$out_dir"' EXIT

# The app is copied inside the container, so the host's .dart_tool and build
# directories are neither read nor rewritten with container paths. Only the
# golden PNGs come back.
docker run --rm --platform linux/amd64 \
  -v "$app_dir:/src:ro" \
  -v "$out_dir:/out" \
  "$image" \
  bash -c '
    set -euo pipefail
    update_flag="$1"
    shift
    mkdir -p /tmp/app
    tar -C /src --exclude=./.dart_tool --exclude=./build -cf - . \
      | tar -C /tmp/app -xf -
    cd /tmp/app
    flutter pub get >/dev/null
    flutter test $update_flag "$@"
    if [[ -n "$update_flag" ]]; then
      find test -path "*/goldens/*.png" -print0 \
        | tar --null -T - -cf /out/goldens.tar
    fi
  ' _ "$update_flag" "${golden_tests[@]}"

if [[ -n "$update_flag" ]]; then
  tar -C "$app_dir" -xf "$out_dir/goldens.tar"
  echo "Goldens regenerated on linux/amd64. Review the changed PNGs before committing:"
  git -C "$repo_root" status --short -- "apps/lyron_app/test"
fi
