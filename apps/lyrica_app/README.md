# Lyrica App

Flutter client shell for the Lyrica monorepo.

## Purpose

This app currently provides:

- the application bootstrap entrypoint
- Riverpod dependency wiring
- go_router route registration
- offline policy vocabulary shared with the domain and application layers
- a tablet-first song library and reader slice backed by a song repository boundary
- an authenticated Supabase-backed song catalog that still projects raw ChordPro in-app without falling back to bundled assets for this slice

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

Documented demo credentials:

- email: `demo@lyrica.local`
- password: `LyricaDemo123!`

## Structure

- `lib/src/domain/`: core vocabulary such as tenant scope and capability codes
- `lib/src/application/`: app-level orchestration and summary models
- `lib/src/application/song_library/`: song list and reader result orchestration
- `lib/src/offline/`: local-store and sync-policy contracts
- `lib/src/presentation/`: route-level widgets
- `lib/src/presentation/song_library/`: song list providers and screen wiring
- `lib/src/presentation/song_reader/`: reader projection, controls, and widgets
- `lib/src/router/`: centralized route definitions

## Verification

Run from the repository root:

```bash
./scripts/bootstrap-app.sh
./scripts/run-app.sh
./scripts/run-authenticated-app.sh
./scripts/run-tests.sh
./scripts/verify.sh
```

For the current slice, `./scripts/verify.sh --skip-migrations` is the end-to-end quality gate for app changes.
For the authenticated backend song-reading slice, `./scripts/verify.sh` is the full local quality gate because it also provisions local Supabase auth and runs the real backend repository integration test.
