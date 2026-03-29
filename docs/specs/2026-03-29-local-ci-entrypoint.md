# Local CI Entrypoint

## Summary

Add a repository-owned local entrypoint that mirrors the GitHub Actions CI jobs so engineers can reproduce the same script ordering locally before pushing.

## Current State

- GitHub Actions runs two repository jobs: `verify` and `migrations`.
- The repo already has most of the underlying entrypoint scripts (`bootstrap.sh`, `verify.sh`, `check-migrations.sh`), but the migrations job's standalone Supabase-tooling install step is not yet represented as its own local script.
- There is no single local command that mirrors the CI job sequencing directly.

## Decision

- Add `./scripts/run-ci-locally.sh` as the canonical local wrapper for the current CI workflow.
- Add `./scripts/bootstrap-supabase.sh` as the repository-owned local equivalent of the CI migrations job's `npm ci --prefix tooling/supabase` step.
- Support `all`, `verify`, and `migrations` modes so developers can run the full workflow or one job at a time.
- Keep the script thin: it should call the existing repository entrypoints in the same order as CI instead of duplicating workflow logic.

## Constraints

- Reuse existing repository scripts rather than inlining job logic.
- Keep the command names aligned with the current GitHub Actions job names.
- Document the local entrypoint in repository workflow guidance.

## Success Criteria

- `./scripts/run-ci-locally.sh all` runs the local equivalent of the `verify` job followed by the `migrations` job.
- `./scripts/run-ci-locally.sh verify` mirrors the CI `verify` job.
- `./scripts/run-ci-locally.sh migrations` mirrors the CI `migrations` job.
- A focused script test proves the wrapper dispatch order.
