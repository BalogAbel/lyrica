# Development Workflow

## Standard Flow

1. Capture the requirement or decision in repository docs.
2. Update or create a design/spec document in `docs/specs/` when the change is material.
3. Write an implementation plan in `docs/plans/`.
4. Implement with tests first where behavior is introduced.
5. Run local verification, typically `./scripts/verify.sh --skip-migrations` for app-only/documentation-only slices and `./scripts/verify.sh` when backend-backed song reading, song-catalog refresh behavior, or local Supabase workflow behavior changes.
6. Update documentation and ADRs if the change affects durable knowledge.
7. Merge only with green CI.

## Local Tooling

- Install repository dependencies with `./scripts/bootstrap.sh`.
- If only Supabase tooling is needed, install it with `npm ci --prefix tooling/supabase`.
- Supabase CLI is managed under `tooling/supabase/`, not at the repository root.
- Use `./scripts/supabase.sh ...` as the canonical interface for local Supabase commands.
- Use `./scripts/check-migrations.sh` as the canonical migration lint entrypoint; it starts or reuses local Supabase before calling `db lint`.
- Typical commands:
  - `./scripts/supabase.sh start`
  - `./scripts/supabase.sh db reset`
  - `./scripts/supabase.sh migration list`
  - `./scripts/check-migrations.sh`
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
2. Launch the app on a native target with `FLUTTER_DEVICE=<native-device-id> ./scripts/manual-validation/run-local-first-app.sh`. Use the default Chrome target only for browser diagnostics, not native offline-relaunch acceptance.
3. Use `./scripts/manual-validation/print-checklist.sh` while validating online, offline, refresh-failed, and explicit sign-out behavior.
4. Use `./scripts/manual-validation/go-offline.sh` and `./scripts/manual-validation/go-online.sh` to switch backend connectivity during the walkthrough.
5. Use `./scripts/manual-validation/reset-validation-state.sh` when you need to restart from a clean local fixture.

The manual-validation launcher caches only the last known local Supabase status env (`API_URL` and `ANON_KEY`) so offline relaunch remains scriptable even when the backend is intentionally stopped and `./scripts/supabase.sh status -o env` is unavailable.
Use `./scripts/verify.sh` to prove persistent cache reopen behavior in automation, then use the manual-validation scripts on native Flutter targets for true offline-relaunch acceptance. Use browser-based offline relaunch checks as best-effort diagnostics only.
For the authenticated song-reader slice, pull requests are expected to pass the full `./scripts/verify.sh` gate in CI, including the local Supabase-backed refresh integrations, rather than only the app-only `--skip-migrations` variant.
For Android emulators, the launch scripts rewrite local host loopback Supabase URLs (`127.0.0.1` or `localhost`) to `10.0.2.2` before invoking Flutter so the app reaches the host machine's backend.
For ADB-managed Android devices, including wireless Flutter targets exposed as `adb-..._adb-tls-connect._tcp` and plain Android serials, the launch scripts run `adb reverse` for the Supabase port and keep the loopback URL unchanged so the app can reach the host machine through the reversed tunnel. This requires Android platform-tools `adb`, or an explicit `ADB_BIN` override.

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
