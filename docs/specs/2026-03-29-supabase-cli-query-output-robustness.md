# Supabase CLI Query Output Robustness

## Summary

Harden the repository's Supabase-backed regression tests so they keep working when `supabase db query` writes human-oriented status or update notices around the JSON payload.

## Current State

- The repository has shell regression tests that capture `./scripts/supabase.sh db query ...` output and parse it as JSON in embedded Python.
- Supabase CLI `v2.83.0` running in this repository can prepend lines such as `Connecting to local database...` and append update notices to stdout around the JSON body.
- That mixed output causes `json.loads(...)` to fail in CI even though the underlying query succeeds.

## Decision

- Add a repository-owned helper that extracts the first valid JSON object from Supabase CLI stdout.
- Route the affected regression tests through that helper instead of assuming the entire stdout stream is pure JSON.
- Keep the fix scoped to repository test consumers of `db query` output; do not change the product behavior or database schema.

## Constraints

- Keep the repository wrapper (`./scripts/supabase.sh`) as the only Supabase CLI entrypoint.
- Preserve the existing query assertions and migration semantics.
- Avoid depending on undocumented CLI behavior beyond the presence of one JSON object in the mixed output.

## Success Criteria

- Script tests that consume `db query` output pass when stdout contains both CLI notices and a JSON payload.
- A focused regression test proves the helper extracts the JSON body from noisy output.
- Existing Supabase-backed regression tests continue to validate the same database behavior as before.
