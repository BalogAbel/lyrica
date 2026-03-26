# Development Workflow

## Standard Flow

1. Capture the requirement or decision in repository docs.
2. Update or create a design/spec document in `docs/specs/` when the change is material.
3. Write an implementation plan in `docs/plans/`.
4. Implement with tests first where behavior is introduced.
5. Run local verification, typically `./scripts/verify.sh --skip-migrations` for app-only/documentation-only slices and `./scripts/verify.sh` when backend-backed song reading or local Supabase workflow behavior changes.
6. Update documentation and ADRs if the change affects durable knowledge.
7. Merge only with green CI.

## Local Tooling

- Install repository dependencies with `./scripts/bootstrap.sh`.
- If only Supabase tooling is needed, install it with `npm ci --prefix tooling/supabase`.
- Supabase CLI is managed under `tooling/supabase/`, not at the repository root.
- Use `./scripts/supabase.sh ...` as the canonical interface for local Supabase commands.
- Typical commands:
  - `./scripts/supabase.sh start`
  - `./scripts/supabase.sh db reset`
  - `./scripts/supabase.sh migration list`
  - `./scripts/provision-local-demo-user.sh`
  - `./scripts/run-authenticated-app.sh`
  - `./scripts/manual-validation/setup-local-first.sh`
  - `./scripts/manual-validation/reset-validation-state.sh`
  - `./scripts/manual-validation/run-local-first-app.sh`
  - `./scripts/manual-validation/go-offline.sh`
  - `./scripts/manual-validation/go-online.sh`
  - `./scripts/manual-validation/print-checklist.sh`
- Repository scripts should call the wrapper rather than direct `supabase` or ad hoc `npx` commands.

## Manual Validation

For the local-first authenticated song-reader slice:

1. Run `./scripts/manual-validation/setup-local-first.sh`.
2. Launch the app with `./scripts/manual-validation/run-local-first-app.sh`.
3. Use `./scripts/manual-validation/print-checklist.sh` while validating online, offline, refresh-failed, and explicit sign-out behavior.
4. Use `./scripts/manual-validation/go-offline.sh` and `./scripts/manual-validation/go-online.sh` to switch backend connectivity during the walkthrough.
5. Use `./scripts/manual-validation/reset-validation-state.sh` when you need to restart from a clean local fixture.

The manual-validation launcher caches only the last known local Supabase app env (`SUPABASE_URL` and `SUPABASE_ANON_KEY`) so offline relaunch remains scriptable even when the backend is intentionally stopped and `./scripts/supabase.sh status -o env` is unavailable.
Use browser-based offline relaunch checks as best-effort diagnostics. Treat native Flutter targets as the required acceptance path for authenticated offline relaunch in this slice.
For Android emulators, the launch scripts rewrite local host loopback Supabase URLs (`127.0.0.1` or `localhost`) to `10.0.2.2` before invoking Flutter so the app reaches the host machine's backend.

## Commit Guidance

- Keep commits meaningful and reviewable.
- Pair schema changes with policy and documentation updates.
- Pair architecture changes with ADRs.
- Avoid tool-specific document locations for repository-critical knowledge.
- If a product slice changes reader behavior, song catalog shape, or parser policy, update the corresponding spec, plan, and repo docs in the same change.

## Definition Of Done

- Behavior implemented
- Tests added or updated
- Relevant docs updated
- CI expectations met
- No critical decision left only in chat or tools
