# Lyrica

Lyrica is a multi-tenant worship and music collaboration platform with a Flutter client, a Supabase backend, and an offline-first operating model for teams that must keep songs, plans, and sessions usable during poor connectivity.

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
- ChordPro defined as the canonical editable song format
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
- [AI development workflow](docs/workflows/ai-development.md)
- [FreeShow integration boundary](docs/integrations/freeshow.md)
- [Current audit spec](docs/specs/2026-03-21-repository-audit-refinement.md)
- [Current audit plan](docs/plans/2026-03-21-repository-audit-refinement.md)

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
- Supabase CLI
- Docker Desktop

### Common Commands

```bash
./scripts/bootstrap.sh
./scripts/supabase-start.sh
./scripts/db-reset.sh
./scripts/db-seed.sh
./scripts/run-app.sh
./scripts/run-tests.sh
./scripts/verify.sh
```

`./scripts/verify.sh` runs the Flutter quality gates and, when the Supabase CLI is available, migration linting as well.

## Local Development Notes

- The Flutter shell is intentionally thin. It exists to keep routing, provider wiring, and offline policy vocabulary executable while the first real product slices are still pending.
- Supabase remains the authorization authority. Capability names used in Flutter must stay aligned with SQL policy helpers.
- Seed data is organization-scoped demo content. Membership rows still depend on authenticated users created in the local Supabase instance.

## Status

This repository contains a refined production-oriented foundation: architecture and workflow documents with concrete rules, a hardened Supabase schema and RLS baseline, realistic verification scripts, CI quality gates, and a minimal Flutter shell aligned to the documented boundaries.
