# Planning Backend Write-Contract Hardening

> Status: Draft

## Goal

Close three gaps in the planning backend write contracts surfaced by the
local-first-validation slice (post PR #55): a real slug-suffix integer-overflow
bug, a missing database-level uniqueness invariant for songs within a session
(SEC-5), and two unpinned RPC error-code contracts. All three live in the same
subsystem (planning write contracts) and are provable through the existing
backend write-contract test harness.

## Problem

1. **Slug suffix integer overflow (real bug, security-adjacent — priority).**
   `supabase/migrations/202604100001_planning_write_contract.sql` defines
   `plan_next_slug` (~line 56) and `session_next_slug` (~line 90), each with:

   ```sql
   slug_number := substring(normalized_base_slug from '([0-9]+)$')::integer;
   ```

   The trailing digit run of a slugified name is cast straight to `integer`
   (int4) with no bounds check and no exception handling. Any plan/session name
   ending in a number ≥ 2_147_483_648 overflows the cast and raises an unhandled
   Postgres `22003` ("value ... is out of range for type integer"). Observed
   live: `value "1782711809759068" is out of range for type integer`. The error
   reaches the client as a raw `PostgrestException` mapped to
   `PlanningMutationSyncErrorCode.unknown`; the offline mutation stays `pending`
   with a generic "unknown" error and no user-facing explanation — a silent
   failure to create the plan/session. Because the name is user-controlled (and
   could be attacker-controlled via shared orgs), this is a denial-of-write
   vector.

2. **No DB-level `unique(session_id, song_id)` for songs (SEC-5).**
   `create_song_session_item` enforces "a song appears at most once per session"
   only with an application-level pre-check that raises
   `P0001 duplicate_song_in_session_blocked`. There is no database constraint, so
   a truly concurrent double-insert sharing one stale `base_version` can slip
   past the pre-check (the version check fires before the duplicate check, and
   there is no DB-level `unique(session_id, song_id)`). The invariant has no
   database-level proof.

3. **Two unpinned RPC error-code contracts.**
   - **edit vs remote-delete** — the precise RPC error code for editing a
     remotely-deleted plan was asserted loosely in the integration suite.
   - **partial edit (name only) vs full edit (LF-5)** — `update_plan_fields`
     field-level no-op/merge semantics were not independently confirmed.

## Scope

- Ship a NEW migration making the slug-suffix parse overflow-safe in both
  `plan_next_slug` and `session_next_slug`.
- Ship a NEW migration adding a partial unique index
  `unique(session_id, song_id) where item_type = 'song'` and making
  `create_song_session_item` translate the resulting `unique_violation` back into
  the existing `P0001 duplicate_song_in_session_blocked` contract.
- Extend the backend write-contract test
  (`scripts/tests/planning-write-contract-test.sh`) with assertions for: a
  large-numeric-suffix name, the SEC-5 index (both the raw DB-level violation and
  the RPC-path re-raise), and the two pinned RPC error-code contracts.
- Remove the `two_device_conflict_matrix_test.dart` slug workaround
  (`run$runId` prefix) once the backend slug fix is verified green.
- Update `docs/testing/testing-strategy.md` and resolve the two deferred docs
  (plus `docs/deferred/README.md` tracking).

## Non-Goals

- No change to the shipped migrations `202604100001` / `202604110001` (new
  migrations only, per AGENTS.md #9/#11).
- No change to the dart `_mapError` mapping in
  `supabase_planning_mutation_repository.dart` — the tests pin the existing
  contract, they do not redesign it.
- No new ADR — the slug overflow-fallback semantics are a bugfix, documented in
  the spec and an inline migration comment (decided in brainstorm).
- No true-concurrency stress harness (parallel un-awaited transactions). The
  SEC-5 index is proven by a direct DB-level duplicate insert; a concurrency
  stress test is a separate effort if ever needed.
- No change to `update_plan_fields` semantics — the LF-5 contract test pins the
  existing full-overwrite behavior, it does not introduce field-level merge.

## Decisions (from brainstorm)

- **Slug fix approach:** wrap the `::integer` cast in
  `BEGIN ... EXCEPTION WHEN numeric_value_out_of_range THEN slug_number := 1; END;`.
  Robust to any digit count, preserves the full text slug on first insert (the
  numeric suffix only drives collision numbering), minimal change. Casting to
  `bigint` only moves the overflow boundary and still needs exception handling.
- **SEC-5 contract:** catch the index's `unique_violation` (23505) in
  `create_song_session_item`, check the constraint name, and re-raise the
  existing `P0001 duplicate_song_in_session_blocked` (which the dart layer maps
  to `dependencyBlocked`). Keeps the client-facing error contract stable.
- **No ADR** for the slug-fallback semantics.

## Current State

- `plan_next_slug` / `session_next_slug` cast the suffix to `integer` with no
  guard.
- `create_song_session_item` (in `202604110001_planning_session_item_write_contract.sql`)
  raises `P0001 duplicate_song_in_session_blocked` from an app-level pre-check;
  no DB constraint backs it.
- `session_items` has `unique (session_id, position)` but no
  `unique(session_id, song_id)`.
- dart `_mapError` (`supabase_planning_mutation_repository.dart:144-176`):
  `P0002`/`not_found` → `remoteMissing`; `P0001` + `conflict` → `conflict`;
  `P0001` + `blocked`/`duplicate`/`out_of_scope` → `dependencyBlocked`.
- `two_device_conflict_matrix_test.dart` prefixes its scratch-session suffix with
  a non-digit (`run$runId`) to dodge the slug overflow bug.
- The backend write-contract test harness (`planning-write-contract-test.sh`)
  drives the RPCs via a Python `psql`-in-container runner with `fetch_json`,
  `fetch_row`, and `capture_error` helpers.

## Target Behavior

### Slug overflow

- `create_plan` / `create_session` with a name whose slug ends in a very large
  number (e.g. `"Set 1782711809759068"`) succeeds: the first row keeps the full
  text slug; on collision, the candidate falls back to `<root>-2`, `<root>-3`, …
  (collision numbering restarts at 1, never raising `22003`).

### SEC-5

- Sequential duplicate add still raises `P0001 duplicate_song_in_session_blocked`
  (unchanged app-level pre-check).
- A direct DB-level insert of a second `(session_id, song_id, item_type='song')`
  row fails with `23505` against `session_items_unique_song_per_session`.
- A `create_song_session_item` call that loses the duplicate race surfaces
  `P0001 duplicate_song_in_session_blocked` (the caught-and-re-raised contract),
  not a raw `23505`.

### RPC error-code contracts

- **edit vs remote-delete:** `update_plan_fields` against a deleted plan id
  raises `P0002 plan_not_found` → `remoteMissing`.
- **partial edit name only (LF-5):** `update_plan_fields` with
  `p_description => null`, `p_scheduled_for => null` and a new name overwrites all
  three fields (full overwrite, not field-level merge), bumping `version`.

## Testing Strategy

TDD / write-contract-first (AGENTS.md #6). New assertions added to the existing
Python harness in `scripts/tests/planning-write-contract-test.sh`, reusing the
`fetch_json` / `capture_error` patterns:

1. **Slug overflow (RED before fix):** create a plan and a session with a
   large-numeric-suffix name, including a forced collision, asserting success and
   a sane slug. Fails with `22003` before the migration; passes after.
2. **SEC-5:** keep the existing sequential `duplicate_song_in_session_blocked`
   assert; add (a) a direct `capture_error` insert proving the `23505` index
   violation by constraint name, and (b) an RPC-path assert that the re-raise
   yields `P0001 duplicate_song_in_session_blocked`.
3. **RPC contract pins:** assert `update_plan_fields` on a deleted plan →
   `P0002 plan_not_found`; assert the LF-5 name-only overwrite semantics.

Full-suite gates: `./scripts/check-migrations.sh` (migration lint),
`./scripts/backend-write-contracts.sh`, and `./scripts/verify.sh` (which runs the
two integration suites, validating the dart workaround removal).

## Documentation & Deferred Resolution

- `docs/testing/testing-strategy.md`: record the three new contract points.
- Resolve `docs/deferred/2026-06-29-slug-suffix-integer-overflow.md` and
  `docs/deferred/2026-06-29-integration-live-stack-verification.md` (delete or
  update) and update `docs/deferred/README.md` per the tracking rule.
- Plan in `docs/plans/2026-06-29-planning-write-contract-hardening.md`.

## Risks

- **Migration ordering:** the new migrations must `CREATE OR REPLACE` the
  functions defined in `202604100001` / `202604110001`; timestamps must sort
  after them and pass `check-migrations.sh`.
- **Existing duplicate-song rows:** adding the partial unique index will fail if
  any session already holds two rows for the same song. Acceptable for this
  pre-launch codebase, but the plan must verify a clean local DB build; if real
  data existed, a dedup step would precede the index.
- **Workaround removal timing:** remove the `two_device_conflict_matrix_test.dart`
  workaround only after the slug fix is verified, so the integration suite proves
  the fix end-to-end.
