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
- Repository scripts should call the wrapper rather than direct `supabase` or ad hoc `npx` commands.

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
