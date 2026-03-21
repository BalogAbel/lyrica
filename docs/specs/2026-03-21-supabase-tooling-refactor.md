# Supabase Tooling Refactor

## Summary

Refactor the repository so the Supabase CLI is managed from a dedicated tooling area under `tooling/supabase/` instead of relying on globally installed binaries or root-level Node setup.

## Current State

- Repository scripts call `supabase` directly.
- CI installs the CLI through `supabase/setup-cli`.
- The repository does not currently version a dedicated Node workspace for Supabase CLI.
- There is no stable repository wrapper for Supabase commands.

## Decision

- Introduce `tooling/supabase/` as the only repository-managed Node area for Supabase CLI.
- Install `supabase` there as a dev dependency and commit its lockfile.
- Add `scripts/supabase.sh` as the canonical interface for repository scripts and developer usage.
- Use `npm ci --prefix tooling/supabase` as the lockfile-based install path for local setup and CI.
- Update scripts, CI, and docs to use the wrapper instead of direct CLI invocation.

## Constraints

- Do not broaden `tooling/` into a generic catch-all.
- Do not change domain, schema intent, Flutter architecture, or migrations unless required for tooling correctness.
- Keep repository content in English.
- Keep developer-facing usage simple and repository-root-relative.

## Success Criteria

- `tooling/supabase/package.json` and lockfile exist.
- `scripts/supabase.sh` resolves the repo root safely and invokes `npx --prefix tooling/supabase supabase "$@"`.
- Existing scripts no longer call `supabase` directly.
- GitHub Actions installs tooling dependencies from `tooling/supabase`.
- Repository docs describe the new local and CI workflow accurately.
- No root-level Node setup is introduced solely for Supabase CLI.
