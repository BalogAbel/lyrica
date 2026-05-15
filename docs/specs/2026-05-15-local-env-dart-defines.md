# Spec: Local Environment via Dart Defines

**Date:** 2026-05-15  
**Branch:** `chore/local-env-dart-defines`  
**Status:** Approved

## Problem

Developers running the app locally against a local Supabase instance must pass credentials via the shell script. The current state has two issues:

1. `sign_in_screen.dart` hardcodes demo credentials unconditionally — they appear in every build, including release.
2. `run-app.sh` passes no `--dart-define` flags, so `SupabaseConfig.fromEnvironment()` throws `ArgumentError` immediately. The script is broken and undocumented as such.
3. The original proposal involved a separate `main_local.dart` entry point, which duplicates bootstrap logic and diverges the shipped binary from the tested binary.

## Goal

- Single `main.dart` entry point across all environments.
- Demo credentials pre-filled only when `DEMO_EMAIL` / `DEMO_PASSWORD` dart-defines are present (local dev only).
- Release builds contain no hardcoded credentials.
- Remove `run-app.sh` and its documentation references.

## Non-Goals

- VS Code `launch.json` integration (deferred).
- `dart-define-from-file` approach.
- Any changes to `SupabaseConfig.fromEnvironment()` — it already works correctly.

## Design

### Dart-Define Constants

Four compile-time constants govern runtime behavior:

| Key | Local value | Prod / release |
|---|---|---|
| `SUPABASE_URL` | resolved dynamically by script | passed by CI |
| `SUPABASE_ANON_KEY` | resolved dynamically by script | passed by CI |
| `DEMO_EMAIL` | `demo@lyron.local` | *(not passed — empty string)* |
| `DEMO_PASSWORD` | `LyronDemo123!` | *(not passed — empty string)* |

`String.fromEnvironment` defaults to `''` when a dart-define is absent. Empty string means empty field in the UI — no conditional branching needed.

### `sign_in_screen.dart`

Replace hardcoded strings with compile-time constants:

```dart
// Before
final _emailController = TextEditingController(text: 'demo@lyron.local');
final _passwordController = TextEditingController(text: 'LyronDemo123!');

// After
final _emailController = TextEditingController(
  text: const String.fromEnvironment('DEMO_EMAIL'),
);
final _passwordController = TextEditingController(
  text: const String.fromEnvironment('DEMO_PASSWORD'),
);
```

### `run-authenticated-app.sh`

Append the two new dart-define flags to the existing `flutter run` invocation:

```bash
"$flutter_bin" run \
  -d "$flutter_device" \
  --target lib/main.dart \
  --dart-define=SUPABASE_URL="$resolved_api_url" \
  --dart-define=SUPABASE_ANON_KEY="$ANON_KEY" \
  --dart-define=DEMO_EMAIL="demo@lyron.local" \
  --dart-define=DEMO_PASSWORD="LyronDemo123!" \
  "$@"
```

URL resolution and host-network preparation remain unchanged.

### `run-app.sh`

Deleted. The script was never functional (missing dart-defines) and never called by other scripts or CI.

### Documentation

Remove all references to `run-app.sh` from:
- `README.md` (root)
- `apps/lyron_app/README.md`

## Testing

`sign_in_screen_test.dart` exists. Verify:
- Without dart-defines: text fields are empty.
- The change is purely a compile-time substitution — no behavior logic added, so existing widget tests remain valid.

## Files Changed

| File | Action |
|---|---|
| `apps/lyron_app/lib/src/presentation/auth/sign_in_screen.dart` | Replace hardcoded strings with `String.fromEnvironment` |
| `scripts/run-authenticated-app.sh` | Add `DEMO_EMAIL` + `DEMO_PASSWORD` dart-defines |
| `scripts/run-app.sh` | Delete |
| `README.md` | Remove `run-app.sh` reference |
| `apps/lyron_app/README.md` | Remove `run-app.sh` reference |
