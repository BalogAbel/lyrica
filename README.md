# Lyrica

Lyrica is a multi-tenant worship and music collaboration platform with a Flutter client, a Supabase backend, and an offline-first operating model for teams that must keep songs, plans, and sessions usable during poor connectivity.

The current first product slice is a tablet-first ChordPro song reader backed by a repository boundary and an asset-based mock catalog.

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
- First product slice: tablet-first song list and reader backed by bundled ChordPro assets
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
- Docker Desktop

Supabase CLI is managed as a repository-local dev dependency under `tooling/supabase/`. Do not install or wire it through a root-level Node workspace for this repository.

### Local Development

Install dependencies with:

```bash
./scripts/bootstrap.sh
```

This installs Flutter dependencies for `apps/lyrica_app` and the repository-local Supabase CLI dependencies under `tooling/supabase/`.

If you only need the Supabase tooling workspace, run `npm ci --prefix tooling/supabase`.

The canonical way to run Supabase CLI commands is through the wrapper script:

```bash
./scripts/supabase.sh start
./scripts/supabase.sh db reset
./scripts/supabase.sh migration list
```

The wrapper resolves the repository-local CLI via `tooling/supabase` and should be preferred over direct `npx` or global `supabase` invocations.

### Common Commands

```bash
./scripts/bootstrap.sh
./scripts/supabase.sh start
./scripts/supabase.sh db reset
./scripts/supabase.sh migration list
./scripts/supabase-start.sh
./scripts/db-reset.sh
./scripts/db-seed.sh
./scripts/run-app.sh
./scripts/run-tests.sh
./scripts/verify.sh
```

`./scripts/verify.sh` runs the Flutter quality gates and migration linting through the repository wrapper.

## Local Development Notes

- The Flutter shell is intentionally thin. It exists to keep routing, provider wiring, and offline policy vocabulary executable while the first real product slices are still pending.
- The first product slice adds a song repository boundary, asset-backed mock catalog, and ChordPro reader controls without introducing auth, backend song storage, or reader preference persistence.
- Supabase remains the authorization authority. Capability names used in Flutter must stay aligned with SQL policy helpers.
- Seed data is organization-scoped demo content. Membership rows still depend on authenticated users created in the local Supabase instance.

## Status

This repository contains a refined production-oriented foundation: architecture and workflow documents with concrete rules, a hardened Supabase schema and RLS baseline, realistic verification scripts, CI quality gates, and a minimal Flutter shell aligned to the documented boundaries.
