# Lyrica App

Flutter client shell for the Lyrica monorepo.

## Purpose

This app currently provides:

- the application bootstrap entrypoint
- Riverpod dependency wiring
- go_router route registration
- offline policy vocabulary shared with the domain and application layers
- a tablet-first song library and reader slice backed by a song repository boundary
- an asset-backed mock catalog for the current ChordPro product slice

It does not yet implement auth, backend song storage, sync execution, song editing, or reader preference persistence.

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
./scripts/run-tests.sh
./scripts/verify.sh
```

For the current slice, `./scripts/verify.sh --skip-migrations` is the end-to-end quality gate for app changes.
