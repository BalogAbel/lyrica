# Live-Stack Verification of New Integration Suites

**Slice:** local-first-validation
**Files:**
- `apps/lyron_app/test/integration/offline_edit_relaunch_sync_flow_test.dart` (LF-T1 scenario, skip-gated)
- `apps/lyron_app/test/integration/two_device_conflict_matrix_test.dart` (scenario 2, skip-gated)

## Problem

Two new integration suites were added against the real local Supabase stack contract
(`SUPABASE_URL`/`SUPABASE_ANON_KEY` skip-gated, matching the existing integration-test
convention): `offline_edit_relaunch_sync_flow_test.dart` (offline edit → relaunch → sync,
`LF-T1`) and `two_device_conflict_matrix_test.dart` (concurrent-edit conflict matrix across
two simulated devices). Both are faithfully wired to the real RPC/auth contracts, but
neither has been **run** against a live local Supabase stack in this slice — `flutter test`
without the env vars set skips them, which is what happened here.

Within `two_device_conflict_matrix_test.dart`, three pairs are fully wired and exercise real
expected behavior end to end:

- rename vs rename (device A wins, device B conflict stays visible — `LF-1`, `LF-4`)
- reorder vs reorder (device A wins, device B conflict stays visible — `LF-1`, `LF-4`)
- add-same-song twice: distinct item ids race on one `songId` (`LF-6`)

Two further pairs are **structure-only** — the test bodies are written against the intended
flow but the exact backend error code/semantics they assert on have not been confirmed live:

- edit vs remote-delete (surviving device converges on the delete)
- partial edit (name only) vs full edit (preserves untouched fields)

## Deferred Because

Running these requires a local Supabase stack bootstrap (`./scripts/supabase.sh` /
`./scripts/verify.sh`) in an environment with Docker available, which was not exercised as
part of this documentation-focused finish to the slice. Confirming the two structure-only
pairs additionally requires observing the actual RPC error code/conflict shape the backend
returns for remote-delete-vs-edit and partial-vs-full-edit races, which can only be done
against a running stack, not by reasoning about the SQL alone.

## What This Slice Did Instead

Wrote both suites to the same skip-gated convention as the existing authenticated
integration suites (`local_first_authenticated_song_reader_flow_test.dart` and friends), so
they are ready to run the moment `SUPABASE_URL`/`SUPABASE_ANON_KEY` are present, and so CI
configurations that already provide those env vars will pick them up without further
wiring.

## Trigger Condition

Run both suites against a live local Supabase stack (`./scripts/verify.sh` or equivalent)
before treating `LF-T1` (non-destructive offline relaunch) or the two-device conflict matrix
as backend-verified rather than structurally-verified. If the two structure-only pairs
reveal a different error code/shape than assumed, update the test bodies and this entry
together; once all five pairs are confirmed live, fold this note into the testing strategy
instead of carrying it here.
