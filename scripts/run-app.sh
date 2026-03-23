#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$repo_root/apps/lyrica_app"

cd "$app_dir"
flutter run -d chrome --target lib/main.dart
