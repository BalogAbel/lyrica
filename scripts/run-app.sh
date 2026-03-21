#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

flutter run -d chrome --target apps/lyrica_app/lib/main.dart
