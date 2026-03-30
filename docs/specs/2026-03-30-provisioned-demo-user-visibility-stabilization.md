# Provisioned Demo User Visibility Stabilization

## Summary

Stabilize the local Supabase provisioning regression check so CI does not fail when the demo user's membership visibility lags briefly behind the provisioning script.

## Current State

- `scripts/verify.sh` provisions the local demo user, then immediately runs `scripts/tests/provision-local-demo-user-test.sh`.
- That regression test resets the database again, provisions the demo user twice, and immediately checks for the expected organization membership through a `db query`.
- In GitHub Actions, the first few post-provision queries can return `rows: []`, even though the provisioning script just reported a valid `user_id`.

## Decision

- Keep the regression test, but allow a short bounded retry window for the membership lookup.
- If the lookup still fails after the retry window, print targeted diagnostics for the demo user and membership queries before failing.
- Keep the stabilization scoped to the test script; do not weaken the provisioning contract or remove the regression gate.

## Constraints

- Preserve repository-managed Supabase CLI usage through `./scripts/supabase.sh`.
- Keep the retry window short and deterministic.
- Surface actionable diagnostics on final failure instead of silent retries.

## Success Criteria

- The provision regression test tolerates short visibility lag and still fails if the demo user never becomes visible.
- Final failure output includes enough context to distinguish missing auth user visibility from missing membership insertion.
- The script remains locally reproducible and mock-testable.
