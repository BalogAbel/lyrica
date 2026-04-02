# Development Workflow

## Standard Flow

1. Capture the requirement or decision in repository docs.
2. Update or create a design/spec document in `docs/specs/` when the change is material.
3. Write an implementation plan in `docs/plans/`.
4. Create or switch to a branch before making implementation changes; do not develop directly on `main`.
   Branch names must follow the Conventional Branch pattern `<type>/<description>`, for example `feat/song-reader-search`, `fix/catalog-refresh-timeout`, or `chore/update-docs`.
5. Implement with tests first where behavior is introduced.
6. Run local verification, typically `./scripts/verify.sh --skip-migrations` for app-only/documentation-only slices and `./scripts/verify.sh` when backend-backed song reading, song-catalog refresh behavior, or local Supabase workflow behavior changes.
7. Update documentation and ADRs if the change affects durable knowledge.
8. Open or update a pull request from that branch; changes reach `main` only through PR merge with green CI.

## Spec And Plan Status Labels

- Every file under `docs/specs/` and `docs/plans/` should keep a short status note directly under the title.
- Use a small canonical vocabulary:
  - `Status: Draft`
  - `Status: In progress`
  - `Status: Implemented`
  - `Status: Abandoned`
- If a later repository document changes an earlier document's effective meaning, append exactly one of:
  - `; superseded by <repository path>`
  - `; partially superseded by <repository path>[, <repository path> ...]`
- Do not invent alternate relationship verbs such as `extended by`, `clarified by`, or `follow-up to` in the status line.
- When a status line references a later document, always name the concrete repository path rather than a vague category like "later plans".
- Update the status note in the same change whenever a slice is implemented, narrowed, abandoned, or superseded.
- Treat specs and plans as historical decision records once implementation moves on; the status note is what separates historical slice docs from the current canonical truth in `README.md`, `docs/product/vision.md`, `docs/architecture/`, `docs/architecture/decisions/`, `docs/domain/`, `docs/testing/`, and `docs/workflows/`.

## Local Tooling

- Install repository dependencies with `./scripts/bootstrap.sh`.
- If only Supabase tooling is needed, install it with `npm ci --prefix tooling/supabase`.
- `./scripts/bootstrap-supabase.sh` is the repository-owned shortcut for that Supabase-tooling-only install path.
- Supabase CLI is managed under `tooling/supabase/`, not at the repository root.
- Use `./scripts/supabase.sh ...` as the canonical interface for local Supabase commands.
- Use `./scripts/supabase-cleanup.sh` as the repository-owned convenience entrypoint for stopping the current local Supabase stack through the wrapper script.
- Use `./scripts/check-migrations.sh` as the canonical migration lint entrypoint; it starts or reuses local Supabase before calling `db lint`.
- Use `./scripts/run-ci-locally.sh` when you want the closest local equivalent of the current GitHub Actions job sequencing.
- Typical commands:
  - `./scripts/supabase.sh start`
  - `./scripts/supabase-cleanup.sh`
  - `./scripts/supabase.sh db reset`
  - `./scripts/supabase.sh migration list`
  - `./scripts/bootstrap-supabase.sh`
  - `./scripts/check-migrations.sh`
  - `./scripts/run-ci-locally.sh`
  - `./scripts/run-ci-locally.sh verify`
  - `./scripts/run-ci-locally.sh migrations`
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
- Keep active implementation work off `main`; branch first, then open a PR back to `main`.
- Name working branches with the Conventional Branch pattern `<type>/<description>` and use lowercase, concise, hyphenated descriptions.
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
