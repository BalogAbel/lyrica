# Lyrica

Lyrica is a multi-tenant worship and music collaboration platform with a Flutter client, a Supabase backend, and a local-first operating model for teams that must keep songs, plans, and sessions usable during poor connectivity.

The current executable product slice is a tablet-first ChordPro song reader with authenticated local-first song reads. Flutter still parses raw ChordPro and renders the reader locally; the backend remains the authorization and refresh boundary and returns only minimal song summaries and raw ChordPro source.

This repository is the canonical source of truth for:

- Product direction and scope
- Domain model and architectural boundaries
- Development workflow and quality gates
- Testing strategy and CI expectations
- AI-assisted engineering rules and documentation obligations

## Foundation Status

- Monorepo with one Flutter app under `apps/lyrica_app`
- Supabase schema, RLS policies, and seed data under `supabase/`
- MVP platforms: Android, iOS, and Web
- Drift selected as the local store and sync-queue foundation
- First executable product slice: authenticated tablet-first song list and reader backed by a local cache for the current authenticated user and active organization, refreshed from Supabase song summaries and raw ChordPro source
- ChordPro defined as the canonical editable song format, with a documented supported subset for the first slice
- Capability-based authorization enforced in Postgres, not in Flutter
- Vendor-neutral specs and plans stored under `docs/specs/` and `docs/plans/`

Desktop platforms are intentionally out of scope for the MVP, but the architecture must not block later support for macOS, Windows, or Linux.

## Repository Layout

```text
.
├── .github/                # CI workflows
├── apps/
│   └── lyrica_app/         # Flutter application
├── docs/                   # Product, domain, architecture, workflow, specs, plans
├── scripts/                # Developer entrypoints
├── tooling/
│   └── supabase/           # Repository-local Supabase CLI package
└── supabase/               # SQL migrations, seeds, local Supabase config
```

## Core Principles

1. The repository is the source of truth.
2. Critical knowledge must be stored in versioned files, not only in tools or chat.
3. Authorization is enforced by Supabase Auth identity + Postgres RLS and SQL functions.
4. Offline support is a first-class architectural concern, not an enhancement.
5. UX should keep a complex domain operationally simple.
6. TDD is required for behavior changes and new implementation work.
7. Documentation updates are part of the definition of done.

## Key Documents

- [Product vision](docs/product/vision.md)
- [Domain model](docs/domain/domain-model.md)
- [Architecture](docs/architecture/architecture.md)
- [Testing strategy](docs/testing/testing-strategy.md)
- [Development workflow](docs/workflows/development-workflow.md)
- [FreeShow integration boundary](docs/integrations/freeshow.md)
- [Tablet-first song reader spec](docs/specs/2026-03-22-tablet-first-chordpro-song-reader.md)
- [Tablet-first song reader plan](docs/plans/2026-03-22-tablet-first-chordpro-song-reader.md)
- [Authenticated song reading spec](docs/specs/2026-03-23-executable-local-supabase-authenticated-song-reading.md)
- [Authenticated song reading plan](docs/plans/2026-03-23-executable-local-supabase-authenticated-song-reading.md)
- [Local-first cached authenticated song reading spec](docs/specs/2026-03-25-local-first-cached-authenticated-song-reading.md)
- [Local-first cached authenticated song reading plan](docs/plans/2026-03-25-local-first-cached-authenticated-song-reading.md)

## Development Workflow

The expected engineering loop is:

1. Capture or update the spec in `docs/specs/`.
2. Write or update the implementation plan in `docs/plans/`.
3. Implement via TDD.
4. Run verification locally and in CI.
5. Update documentation before merge.

See [development workflow](docs/workflows/development-workflow.md) and [AGENTS.md](AGENTS.md) for operational detail.

## Getting Started

### Prerequisites

- Flutter SDK
- Dart SDK
- Node.js and npm
- Docker-compatible local engine

Supabase CLI is managed as a repository-local dev dependency under `tooling/supabase/`. Do not install or wire it through a root-level Node workspace for this repository.

### Local Development

Install all repository dependencies with:

```bash
./scripts/bootstrap.sh
```

This installs Flutter dependencies for `apps/lyrica_app` and the repository-local Supabase CLI dependencies under `tooling/supabase/`.

If you only want to run the Flutter app locally, use:

```bash
./scripts/bootstrap-app.sh
```

This avoids the Supabase tooling install and only resolves Flutter packages for `apps/lyrica_app`.

If you only need the Supabase tooling workspace, run `npm ci --prefix tooling/supabase`.

The canonical way to run Supabase CLI commands is through the wrapper script:

```bash
./scripts/supabase.sh start
./scripts/supabase.sh db reset
./scripts/supabase.sh migration list
```

The wrapper resolves the repository-local CLI via `tooling/supabase` and should be preferred over direct `npx` or global `supabase` invocations.

Local Supabase development for the authenticated song-reading slice must provide:

- one documented demo user
- one active membership linked to that user
- three backend-seeded songs matching the current reader slice catalog

After `./scripts/supabase.sh start` and `./scripts/db-reset.sh`, provision the local auth fixture with:

```bash
./scripts/provision-local-demo-user.sh
```

Documented demo credentials:

- email: `demo@lyrica.local`
- password: `LyricaDemo123!`

For the simplest end-to-end local app run, use:

```bash
./scripts/run-authenticated-app.sh
```

This starts or reuses local Supabase, resets the local database, provisions the documented demo user, discovers the local Supabase URL and anon key, and launches the Flutter app with the required `--dart-define` values. Extra `flutter run` arguments are forwarded, for example:

```bash
./scripts/run-authenticated-app.sh --web-port 3000
```

When `FLUTTER_DEVICE` targets an Android emulator such as `emulator-5554`, the launcher rewrites local host URLs from `127.0.0.1` or `localhost` to `10.0.2.2` before passing `SUPABASE_URL` into Flutter. This keeps the app pointed at the host machine's local Supabase instance instead of the emulator's own loopback interface.

On macOS with Colima, the repository keeps local Supabase analytics disabled in `supabase/config.toml`. The current Supabase local analytics service expects the default Docker socket mount and blocks `./scripts/supabase.sh start` under the Colima socket path even though this slice does not need analytics.

### Common Commands

```bash
./scripts/bootstrap.sh
./scripts/bootstrap-app.sh
./scripts/supabase.sh start
./scripts/supabase.sh db reset
./scripts/supabase.sh migration list
./scripts/supabase-start.sh
./scripts/db-reset.sh
./scripts/db-seed.sh
./scripts/run-app.sh
./scripts/run-authenticated-app.sh
./scripts/run-tests.sh
./scripts/verify.sh
./scripts/manual-validation/setup-local-first.sh
./scripts/manual-validation/reset-validation-state.sh
./scripts/manual-validation/run-local-first-app.sh
./scripts/manual-validation/go-offline.sh
./scripts/manual-validation/go-online.sh
./scripts/manual-validation/print-checklist.sh
```

`./scripts/verify.sh` runs the Flutter quality gates and migration linting through the repository wrapper. Without `--skip-migrations`, it also starts or reuses local Supabase, resets the database, provisions the demo auth user, runs the repeated-provisioning regression check, runs the manual-validation script contract test, and runs both the authenticated backend song-reading integration test and the local-first cached authenticated song-reading integration test with local `SUPABASE_URL` and `SUPABASE_ANON_KEY` values. The local-first integration slot proves persistent cache reopen behavior after the local catalog database is closed and reopened; it does not replace native manual offline-relaunch validation.

For manual validation of the local-first reader flow:

```bash
./scripts/manual-validation/setup-local-first.sh
./scripts/manual-validation/reset-validation-state.sh
./scripts/manual-validation/run-local-first-app.sh
./scripts/manual-validation/print-checklist.sh
./scripts/manual-validation/go-offline.sh
./scripts/manual-validation/go-online.sh
```

The manual-validation launcher caches only the last known local Supabase `SUPABASE_URL` and `SUPABASE_ANON_KEY` values so the app can be relaunched after `./scripts/manual-validation/go-offline.sh` without requiring a live backend status check.
Use native Flutter targets as the acceptance path for authenticated offline relaunch. The automated test gate proves persistent cache reopen behavior, while browser relaunch remains best-effort diagnostics for the current slice.

## Local Development Notes

- The Flutter shell is intentionally thin. It exists to keep routing, provider wiring, and offline policy vocabulary executable while the first real product slices are still pending.
- The current authenticated slice reads the active song catalog from a local Drift-backed cache for the current authenticated user and active organization. Supabase is used to verify session state and refresh the full visible catalog.
- On web, that cache runs through Drift wasm and the repository-versioned `apps/lyrica_app/web/sqlite3.wasm` runtime asset.
- Hard offline authenticated relaunch is a native-first guarantee for this slice. The browser path keeps a best-effort local cache, but web session persistence is not treated as equivalent to native offline relaunch.
- ChordPro parsing and reader projection stay inside Flutter even when the source comes from Supabase.
- Supabase remains the authorization authority. Capability names used in Flutter must stay aligned with SQL policy helpers.
- Seed data is organization-scoped demo content. `./scripts/provision-local-demo-user.sh` creates the demo auth user through Supabase Auth and idempotently upserts the matching active membership row.
- The organization-membership uniqueness migration deduplicates pre-existing local duplicates by keeping the earliest row by `created_at, id` before recreating the partial unique index.
- Local verification now also proves RLS scope isolation: the seeded hidden-organization song is not visible to the demo user.
- The current slice retains only one active authenticated catalog snapshot per user for the currently active organization. It does not keep a local archive of multiple organization catalogs.
- Explicit sign-out removes that cached authenticated song catalog instead of leaving a device-global offline archive behind.

## Status

This repository contains a refined production-oriented foundation: architecture and workflow documents with concrete rules, a hardened Supabase schema and RLS baseline, realistic verification scripts, CI quality gates, and a minimal Flutter shell aligned to the documented boundaries.
