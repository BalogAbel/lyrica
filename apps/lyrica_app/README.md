# Lyrica App

Flutter client shell for the Lyrica monorepo.

## Purpose

This app currently provides:

- the application bootstrap entrypoint
- Riverpod dependency wiring
- go_router route registration
- offline policy vocabulary shared with the domain and application layers
- a minimal home screen that communicates the repository's architectural boundaries

It does not yet implement product workflows such as song editing, planning, or sync execution.

## Structure

- `lib/src/domain/`: core vocabulary such as tenant scope and capability codes
- `lib/src/application/`: app-level orchestration and summary models
- `lib/src/offline/`: local-store and sync-policy contracts
- `lib/src/presentation/`: route-level widgets
- `lib/src/router/`: centralized route definitions

## Verification

Run from the repository root:

```bash
./scripts/run-tests.sh
./scripts/verify.sh
```
