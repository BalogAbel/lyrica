# Lyrica App

Flutter client shell for the Lyrica monorepo.

## Purpose

This app currently provides:

- the application bootstrap entrypoint
- Riverpod dependency wiring
- go_router route registration
- offline policy vocabulary shared with the domain and application layers
- a tablet-first song library and reader slice backed by a song repository boundary
- an authenticated local-first song catalog that reads from a Drift-backed active cache and refreshes that cache from Supabase without falling back to bundled assets for this slice
- a web runtime cache path that uses Drift wasm with the versioned `web/sqlite3.wasm` asset

It does not yet implement sync execution, song editing, or reader preference persistence.

For the authenticated song-reading slice, local Supabase development must provide:

- one documented demo user
- one active membership linked to that user
- three backend-seeded songs matching the current reader slice catalog

Use the repository workflow from the repository root:

```bash
./scripts/run-authenticated-app.sh
```

This is the simplest local path for the authenticated reader slice. It starts or reuses local Supabase, resets the database, provisions the demo auth user idempotently, and launches the Flutter app with the required local Supabase `dart-define` values.
For Android emulators, the launcher rewrites host loopback URLs to `10.0.2.2` so the app can reach the Mac-hosted local Supabase stack.
For ADB-managed Android devices, including wireless targets whose Flutter id looks like `adb-..._adb-tls-connect._tcp` and plain Android serials, the launcher automatically runs `adb reverse` for the local Supabase port and keeps `127.0.0.1` as the app-facing URL. This requires Android platform-tools `adb`, or an explicit `ADB_BIN` override.

Documented demo credentials:

- email: `demo@lyrica.local`
- password: `LyricaDemo123!`

## Structure

- `lib/src/domain/`: core vocabulary such as tenant scope and capability codes
- `lib/src/application/`: app-level orchestration and summary models
- `lib/src/application/song_library/`: local-first catalog controller, active context, and reader result orchestration
- `lib/src/offline/`: local-store and sync-policy contracts plus authenticated catalog cache storage
- `lib/src/presentation/`: route-level widgets
- `lib/src/presentation/song_library/`: song list providers, persistent catalog status, and sign-out wiring
- `lib/src/presentation/song_reader/`: reader projection, controls, and widgets
- `lib/src/router/`: centralized route definitions

## Verification

Run from the repository root:

```bash
./scripts/bootstrap-app.sh
./scripts/run-app.sh
./scripts/run-authenticated-app.sh
./scripts/manual-validation/setup-local-first.sh
./scripts/manual-validation/reset-validation-state.sh
./scripts/manual-validation/run-local-first-app.sh
./scripts/manual-validation/go-offline.sh
./scripts/manual-validation/go-online.sh
./scripts/manual-validation/print-checklist.sh
./scripts/run-tests.sh
./scripts/verify.sh
```

For the current slice, `./scripts/verify.sh --skip-migrations` is the end-to-end quality gate for app and documentation changes when the local Supabase path is unaffected.
For the authenticated local-first song-reading slice, `./scripts/verify.sh` is the full local quality gate because it also provisions local Supabase auth and runs both the real backend repository integration test and the cached offline reader integration test. That local-first integration test proves persistent cache reopen behavior after the catalog database is closed and reopened; it does not replace native manual offline-relaunch validation.
For repeatable manual validation, prefer `./scripts/manual-validation/run-local-first-app.sh` over `./scripts/run-authenticated-app.sh` because the manual-validation launcher preserves previously fetched app state between relaunches.
The web path of that local-first cache depends on `apps/lyrica_app/web/sqlite3.wasm`; keep that asset versioned with Drift web cache changes instead of relying on ad-hoc local setup.
The manual-validation launcher also reuses a cached local Supabase env snapshot containing only `API_URL` and `ANON_KEY` from `supabase status -o env`, so offline relaunch remains scriptable after the backend is intentionally stopped.
For this slice, authenticated offline relaunch is treated as a native-first requirement. The automated gate proves persistent cache reopen behavior, while the browser cache path remains useful and supported but browser relaunch behavior is best-effort rather than a product guarantee.
Set `FLUTTER_DEVICE` when validating on a native target; use the default Chrome launcher only for browser diagnostics and general UI checks. Wireless Android devices can use the `adb-..._adb-tls-connect._tcp` id reported by `flutter devices`, while USB or other ADB-managed devices can use their Android serial.
