# Local-First Validation (Adversarial Offline/Sync Hardening)

- Status: Proposed
- Date: 2026-06-29
- Scope: Mobile (`apps/lyron_app`) test suites + targeted production fixes in the planning/song
  sync, reconcile, and offline-store layers. Native test surface only.
- Findings: `LF-1`, `LF-2`, `LF-3`, `LF-4`, `LF-5`, `LF-6`, `LF-8`, `LF-T1`, `LF-T7` (full
  validation + fix); `LF-T4`, `LF-T6` (characterization probe + targeted fix only). Source:
  `docs/architecture/repository-review-2026-06-22.md` §11.1, §10; `ADR-019`, `ADR-020`.

## Goal

Prove the behaviour shipped in PR #55 — exactly-once planning mutation sync (`ADR-019`) and
non-destructive session expiry / offline relaunch (`ADR-020`) — along the **failure, conflict,
and convergence paths**, not the happy path. The suites are deliberately adversarial: they exist
to expose bugs. Every **concrete, localized** bug a suite uncovers is fixed in this slice
(TDD red→green). Every **feature-sized gap** a probe uncovers (server-clock anchor, storage
eviction policy) is documented and deferred with a stable finding id — the test stays as a
characterization of current behaviour rather than failing CI.

The slice leaves the repository measurably clearer: the testing-strategy gap list (§10) shrinks,
and the highest-risk subsystem moves from "engineered, happy-path-validated" to "adversarially
validated".

## Current State

PR #55 shipped the behaviour but validated it on happy-path persistence. The runtime
failure/convergence paths carry the most risk and least coverage (review §6, §10):

- **No live offline/conflict e2e**: no edit-offline → relaunch → sync → convergence test against
  a real backend; no two-device conflict matrix.
- **No fault-injection**: crash between backend-accept and local-clear (`LF-1`), partial RPC
  success + refresh failure → reconcile path (`LF-2`), and concurrent sync triggers (`LF-3`) are
  unproven under adversarial timing.
- **Silent-distortion paths untested**: reconcile null-field coercion (`LF-8`, `?? ''`×11 / `?? 0`×2
  in `providers.dart`), failed/conflict edits reverting from the merged read (`LF-4`), partial-edit
  field blanking (`LF-5`), and double-add of the same song offline (`LF-6`).
- **No migration-with-pending-mutations test** (`LF-T7`): the planning DB migration is additive but
  untested with a pending queue present, and the catalog DB declares `schemaVersion 2` with **no**
  `MigrationStrategy`.
- **No storage-pressure or clock-skew characterization** (`LF-T4`, `LF-T6`): quota/eviction and
  device-clock ordering behaviour are undocumented at the test level.

The merged offline-membership relaunch bug surfaced after merge confirms the gap: the shipped
non-destructive relaunch behaviour is not adversarially validated.

## Design

### Approach: layered, native-only

Two layers, chosen per scenario by fidelity-vs-cost:

- **Deterministic unit/controller tests** (fakes) carry fault injection, single-flight, reconcile
  null-field, merge visibility, migration, and the two probes. These reuse the existing controller
  fakes (`_FakePlanningMutationStore`, `_FakePlanningMutationRemoteRepository`).
- **Integration tests** against a real local Supabase (`SUPABASE_URL`/`SUPABASE_ANON_KEY`
  dart-defines, the existing `test/integration/` pattern with native Drift temp-file databases)
  carry the true end-to-end edit → relaunch → sync → convergence and the two-device conflict
  matrix.

Web/IndexedDB offline (chromedriver e2e) is deferred (see Deferred). All scenarios here run on the
native Drift surface, where "relaunch" is a temp-file database close + reopen — the pattern already
used by `test/integration/local_first_authenticated_song_reader_flow_test.dart`.

### Shared test support (new, `apps/lyron_app/test/support/`)

Three focused helpers beside the existing `drift_test_setup.dart`:

- **`fault_injecting_remote.dart`** — a configurable fake remote repository for both planning and
  song mutation sync. It can: accept a mutation then throw on the subsequent refresh (partial RPC
  success + refresh failure → reconcile path, `LF-2`); simulate a "crash" by recording an accepted
  mutation and aborting before `clearMutation` (`LF-1`); and count concurrent in-flight calls
  (`LF-3`). It records call order so tests assert exactly-once and no double-send.
- **`fake_clock.dart`** — an injectable clock the reconcile/freshness path reads instead of
  `DateTime.now()`, enabling deterministic skew for the `LF-T6` probe. Introducing this seam is the
  minimum production change needed to make ordering testable; it does **not** add a server-clock
  anchor (that is the deferred fix).
- **`drift_relaunch.dart`** — a helper that closes a Drift temp-file database and reopens it from
  the same file, asserting persisted state survives, so relaunch scenarios read like a single
  linear flow.

### Scenario coverage matrix

| # | Scenario | Layer | Findings | Domain |
| --- | --- | --- | --- | --- |
| 1 | edit-offline → relaunch → sync → convergence | integration (+ unit on merge logic) | `LF-T1`, `ADR-019/020` | planning + song |
| 2 | two-device conflict matrix | integration | `LF-1`, `LF-5`, `LF-6`, OCC | planning (song: shared core) |
| 3a | crash between accept-marker and `clearMutation` → no double-send / no false conflict | unit (fault fake) | `LF-1` | planning + song |
| 3b | partial RPC success + refresh failure → reconcile path, no data loss | unit (fault fake) | `LF-2` | planning + song |
| 3c | reconcile null-field → invariant assert / explicit rejection, not silent `?? ''` / `?? 0` | unit | `LF-8` (fix) | planning |
| 3d | single-flight: concurrent triggers coalesce into one in-flight run | unit | `LF-3` | planning + song |
| 3e | failed / conflict edit stays visible in merged read (no silent revert) | unit + widget | `LF-4`, `LF-5`, `LF-6` | planning |
| 4 | Drift migration with pending mutations present; catalog `schemaVersion 2` gains a `MigrationStrategy` | unit | `LF-T7` (fix) | planning + catalog |
| 5 | storage-pressure probe: quota / write failure — is a pending mutation lost? | unit | `LF-T4` (probe) | planning store |
| 6 | clock-skew probe: device-clock ordering consequence | unit (fake clock) | `LF-T6` (probe) | planning reconcile |

### Two-device conflict matrix (scenario 2)

Two real Supabase clients mutate the same plan / session item with a stale `base_version`, then
sync in turn. Operation pairs:

- rename ↔ rename (OCC conflict)
- reorder ↔ reorder
- edit ↔ remote delete (remote-delete convergence — the mature song-side path is regression-covered)
- add-same-song twice with distinct item ids (`LF-6`)
- partial edit (name only) ↔ full edit (`LF-5`: `description` / `scheduledFor` must not blank)

Each asserts: deterministic convergence after both sync, and the losing side's edit remains
**visible** for review (`LF-4`), never silently reverted.

### Fix policy ("validate + fix all found")

- A **concrete, localized** bug a suite exposes is fixed here via TDD red→green. Expected
  candidates: `LF-8` null-field coercion, `LF-5` partial-edit blanking, `LF-6` double-add,
  the offline-membership relaunch gate, and any pending-mutation loss the storage probe reveals.
- A **feature-sized gap** a probe exposes is documented and deferred with a finding id, never built
  here. Specifically: a server-clock anchor (`LF-T6` fix) and a storage-eviction policy
  (`LF-T4` fix) are out of scope; the probes characterize current behaviour instead.
- The boundary rule: if the fix lives inside an existing seam (a merge function, a reconcile field,
  a store write path, a migration callback), it is in scope. If it requires a new subsystem
  (clock-sync protocol, eviction engine), it is deferred.

### Documentation duties (AGENTS.md #4)

Documentation ships with the change:

- `docs/testing/testing-strategy.md` — record the adversarial offline/sync suites and remove the
  matching items from the §10 gap list.
- `ADR-019` / `ADR-020` — add a "Validation" note linking the suites that prove each decision.
- `docs/architecture/repository-review-2026-06-22.md` — annotate validated findings.
- Any production fix updates the relevant ADR/architecture doc in the same commit.

## Out of Scope (Deferred)

Each deferred item gets a `docs/deferred/` entry so it stays visible for future slice planning:

- **Web / IndexedDB offline e2e** (`docs/deferred/2026-06-29-web-offline-e2e.md`) — chromedriver CI
  lane, real IndexedDB eviction. Native-only here.
- **Server-clock anchor** (`docs/deferred/2026-06-29-server-clock-anchor-lf-t6.md`) — the `LF-T6`
  fix. The probe characterizes device-clock ordering; the anchor is a new seam.
- **Storage-eviction policy** (`docs/deferred/2026-06-29-storage-eviction-policy-lf-t4.md`) — the
  `LF-T4` fix (size monitor + eviction, mutations protected). The probe asserts current failure mode.
- Full mirrored song-side conflict matrix (song covers the shared sync core only).
- Different-user re-auth live wiring — already deferred
  (`docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`).
- `LF-T3` mutation-budget/squash, `LF-T5` incremental sync, `LF-9` read N+1 — out of this slice.

## Success Criteria

- Adversarial suites exist and are green for scenarios 1–4 on the native surface; the two probes
  (5, 6) run and assert documented current behaviour.
- Every concrete bug a suite exposed is fixed and covered by a regression test.
- Every deferred feature-gap has a `docs/deferred/` entry with a finding id.
- `docs/testing/testing-strategy.md` §10 gap list is reduced accordingly.
- CI is green; integration tests run against the local Supabase stack via the existing entrypoint.

## Testing Strategy

TDD throughout (AGENTS.md #6): each scenario is a failing test first. For fix scenarios the test is
red against current code, then the production fix makes it green. For pure-validation scenarios the
test passes against current behaviour and stands as a regression guard. For probes the test asserts
the documented current behaviour; if the probe reveals an in-seam bug, it converts to a red→green
fix, otherwise it remains a characterization test referencing the deferred finding.
