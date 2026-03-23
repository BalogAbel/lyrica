#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../apps/lyrica_app"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required."
  exit 1
fi

flutter pub get
