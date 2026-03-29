# CI Migration Lint Local Supabase Bootstrap

## Summary

Make the repository migration lint entrypoint self-sufficient by ensuring it starts or reuses the local Supabase stack before running lint. This keeps GitHub Actions and local developer usage aligned behind the same repository script.

## Current State

- `scripts/check-migrations.sh` validates that migration files exist and then runs `./scripts/supabase.sh db lint`.
- `supabase db lint` expects the local Postgres service exposed by the repository-managed Supabase stack.
- The `migrations` GitHub Actions job installs the tooling workspace and invokes `./scripts/check-migrations.sh`, but it does not pre-start the stack.
- As a result, CI can fail with a local Postgres connection-refused error before migration linting actually runs.

## Decision

- `scripts/check-migrations.sh` must start or reuse the local Supabase stack through `./scripts/supabase.sh start` before invoking `db lint`.
- The migration lint contract should live in the repository script, not as hidden setup knowledge in the workflow file.
- `scripts/verify.sh` should rely on that script contract instead of issuing a redundant second `start` immediately afterward.
- Add a regression test that proves the script calls `start` before `db lint`.
- Update repository docs so local and CI expectations explicitly describe the self-bootstrapping migration lint behavior.

## Constraints

- Keep Supabase CLI usage behind `scripts/supabase.sh`.
- Do not introduce a separate root-level Node or direct CLI setup path.
- Keep the change narrow to migration-lint execution behavior and durable documentation.

## Success Criteria

- `./scripts/check-migrations.sh` starts or reuses local Supabase before linting.
- A script-level regression test fails if the `start` call is removed or reordered behind lint.
- CI can use the existing `./scripts/check-migrations.sh` entrypoint without extra hidden database bootstrap steps.
- Repository docs describe the migration-lint bootstrap behavior accurately.
