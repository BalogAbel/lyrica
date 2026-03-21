# Lyrica

Lyrica is a cloud-first worship and music collaboration platform with strong offline support for teams that need reliable song, plan, and session workflows across Android, iOS, and Web.

This repository is the canonical source of truth for:

- Product direction and scope
- Domain model and architectural boundaries
- Development workflow and quality gates
- Testing strategy and CI expectations
- AI-assisted engineering rules and documentation obligations

## Current Scope

- Monorepo with Flutter client application
- Supabase backend foundation
- MVP targets: Android, iOS, Web
- Offline-first architecture with Drift
- ChordPro as the canonical song format
- Capability-based authorization enforced in Postgres with RLS
- Documentation-first delivery with ADRs and workflow guides

Desktop platforms are intentionally out of scope for the MVP, but the architecture must not block later support for macOS, Windows, or Linux.

## Repository Layout

```text
.
├── .github/                # CI workflows
├── apps/
│   └── lyrica_app/         # Flutter application
├── docs/                   # Product, domain, architecture, testing, workflow docs
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

## Development Workflow

The expected engineering loop is:

1. Capture or update the spec in the repository.
2. Write or update the implementation plan in the repository.
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
```

## Status

This repository currently contains the initial production-oriented foundation: architecture, domain documentation, ADRs, Supabase schema/RLS baseline, CI workflow definitions, developer scripts, and a Flutter application shell aligned to the documented architecture.
