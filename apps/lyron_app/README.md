# Lyron Chords

Flutter client shell for the Lyron Chords monorepo.

## Purpose

This app currently provides:

- the application bootstrap entrypoint
- Riverpod dependency wiring
- go_router route registration
- offline policy vocabulary shared with the domain and application layers
- a tablet-first song library and reader slice backed by a song repository boundary
- an authenticated local-first song catalog that reads from a Drift-backed active cache and refreshes that cache from Supabase without falling back to bundled assets for this slice
- local-first song create, edit, delete, conflict, and explicit manual sync behavior for the active organization
- a local-first planning slice that reads visible plans from a normalized local projection and records local plan, session, and song-backed session-item writes through a persisted mutation layer
- a session-scoped reader flow that opens songs from planning context and preserves previous/next navigation within the current session
- a web runtime cache path that uses Drift wasm with the versioned `web/sqlite3.wasm` asset

It does not yet implement background sync while the app is suspended or terminated, multi-organization UX, or reader preference persistence.

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

- email: `demo@lyron.local`
- password: `Lyron ChordsDemo123!`

## Structure

- `lib/src/domain/`: core vocabulary such as tenant scope and capability codes
- `lib/src/application/`: app-level orchestration and summary models
- `lib/src/application/song_library/`: local-first catalog controller, active context, reader orchestration, and song mutation sync coordination
- `lib/src/domain/planning/`: read-side planning entities and repository contract
- `lib/src/offline/`: local-store and sync-policy contracts plus authenticated catalog and planning storage
- `lib/src/presentation/`: route-level widgets
- `lib/src/presentation/planning/`: plan list/detail routes, mutation surfaces, and planning providers
- `lib/src/presentation/song_library/`: song list providers, persistent catalog status, song create flow, and sign-out wiring
- `lib/src/presentation/song_reader/`: reader projection, controls, and widgets
- `lib/src/infrastructure/planning/`: Supabase-backed planning read and write repositories
- `lib/src/infrastructure/song_library/`: local-first and Supabase-backed song repositories plus mutation contract adapters
- `lib/src/router/`: centralized route definitions

## Reader UI Behavior

Current reader behavior uses one shared reader core with presentation shells:

- compact shell for touch-first viewports
- expanded shell for large viewports

Compact shell behavior:

- app bar shows only back, current song title, and overflow menu while a song is loaded
- bottom context bar appears only for scoped session/list reader entry
- temporary control overlay revealed by single tap
- double-tap toggles auto-fit state
- control overlay auto-hides after inactivity

Expanded shell behavior:

- persistent title bar above the song content
- left context panel
- center song surface
- right tools panel
- no compact overlay

Compact edit and delete actions live in the header overflow menu. Expanded shell keeps the stable top action area outside side panels.

## Current Behavior Notes

- Song writes and planning writes are local-first and persisted across restart for the active authenticated user and active organization boundary.
- Song and planning mutations synchronize in the foreground through explicit or repository-owned sync paths rather than through background execution while the app is suspended.
- Explicit sign-out clears authenticated cached song and planning data instead of leaving a device-global archive behind.

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
For the authenticated local-first song-reading and planning read slices, `./scripts/verify.sh` is the full local quality gate because it also provisions local Supabase auth and runs the real backend song-reading integration test, the cached offline reader integration test, and the backend-backed planning integration test. That local-first integration test proves persistent cache reopen behavior after the catalog database is closed and reopened; it does not replace native manual offline-relaunch validation.
For repeatable manual validation, prefer `./scripts/manual-validation/run-local-first-app.sh` over `./scripts/run-authenticated-app.sh` because the manual-validation launcher preserves previously fetched app state between relaunches.
The web path of that local-first cache depends on `apps/lyron_app/web/sqlite3.wasm`; keep that asset versioned with Drift web cache changes instead of relying on ad-hoc local setup.
The manual-validation launcher also reuses a cached local Supabase env snapshot containing only `API_URL` and `ANON_KEY` from `supabase status -o env`, so offline relaunch remains scriptable after the backend is intentionally stopped.
For this slice, authenticated offline relaunch is treated as a native-first requirement. The automated gate proves persistent cache reopen behavior, while the browser cache path remains useful and supported but browser relaunch behavior is best-effort rather than a product guarantee.
Set `FLUTTER_DEVICE` when validating on a native target; use the default Chrome launcher only for browser diagnostics and general UI checks. Wireless Android devices can use the `adb-..._adb-tls-connect._tcp` id reported by `flutter devices`, while USB or other ADB-managed devices can use their Android serial.
