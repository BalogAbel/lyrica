# Backend SQL Write Contract Gates Implementation Plan

> Status: Draft

**Goal:** Add repository-owned gating for `scripts/tests/planning-write-contract-test.sh` and `scripts/tests/song-crud-write-contract-test.sh` so backend SQL write regressions fail both the default local verify path and the primary CI release gate.

**Architecture:** Keep the existing shell-based backend contract suites and the repository wrapper-script model. Add one shared backend-contract gate entrypoint, make `./scripts/verify.sh` authoritative for local full verification, and split CI so backend-contract failures stay visible without forcing duplicate execution in the same CI run.

**Tech Stack:** Bash, Docker, Supabase CLI wrapper scripts, CI workflow YAML, Markdown

---

### Assumptions

- The two existing backend contract suites remain the canonical regression coverage for planning and song CRUD SQL write behavior.
- `./scripts/verify.sh` should remain the preferred full local verification command.
- `./scripts/run-ci-locally.sh` should continue mirroring repository CI structure closely enough that developers can reproduce gate behavior locally.
- Supabase lifecycle duplication is acceptable only when it clearly improves isolation; otherwise shared setup should be preferred.

### Recommendation

Use hybrid gating:

1. add one shared repository script that runs both backend write-contract suites
2. call that shared script from `./scripts/verify.sh` by default
3. add one dedicated CI job for the backend write-contract gate
4. avoid CI double execution by giving `./scripts/verify.sh` a documented skip flag for the backend write-contract gate when CI splits jobs

### Plan

1. Capture gate design in repository docs
   - Files: `docs/specs/2026-05-01-backend-sql-write-contract-gates.md`, `docs/plans/2026-05-01-backend-sql-write-contract-gates.md`, `docs/deferred/2026-05-01-backend-sql-write-contract-gates.md`
   - Change:
     - Record current gap, option analysis, and chosen hybrid design.
     - Link deferred item to the new spec and plan so future implementation starts from repository-owned decisions.
   - Verify:
     - `sed -n '1,220p' docs/specs/2026-05-01-backend-sql-write-contract-gates.md`
     - `sed -n '1,260p' docs/plans/2026-05-01-backend-sql-write-contract-gates.md`

2. Add shared backend-contract gate entrypoint and focused regression coverage
   - Files: create shared gate script under `scripts/`; create or update matching shell regression test under `scripts/tests/`
   - Change:
     - Add one repository-owned script that runs both `scripts/tests/planning-write-contract-test.sh` and `scripts/tests/song-crud-write-contract-test.sh`.
     - Keep wrapper-script compliance and avoid direct non-repository Supabase CLI usage.
   - Verify:
     - `bash scripts/tests/planning-write-contract-test.sh`
     - `bash scripts/tests/song-crud-write-contract-test.sh`
     - focused shell test for new shared gate script

3. Wire local full verify to include backend write contracts
   - Files: `scripts/verify.sh`, `scripts/tests/verify-test.sh`
   - Change:
     - Extend `scripts/verify.sh` to run the shared backend-contract gate in the full backend-backed path.
     - Add a documented skip switch only if needed to prevent CI double execution after the dedicated CI job lands.
     - Update `scripts/tests/verify-test.sh` so the expected sequence matches the new verify contract.
   - Verify:
     - `bash scripts/tests/verify-test.sh`
     - `./scripts/verify.sh`

4. Split CI visibility without losing parity
   - Files: `.github/workflows/ci.yml`, `scripts/run-ci-locally.sh`, `scripts/tests/run-ci-locally-test.sh`
   - Change:
     - Add a dedicated backend write-contract CI job that uses the shared backend-contract gate entrypoint.
     - Keep `verify` job authoritative for local-style full verification, but skip duplicate backend-contract execution there if the dedicated CI job now owns that copy.
     - Extend `scripts/run-ci-locally.sh` so local CI simulation mirrors the final gate split.
   - Verify:
     - `bash scripts/tests/run-ci-locally-test.sh`
     - `./scripts/run-ci-locally.sh verify`
     - `./scripts/run-ci-locally.sh all`

5. Repair repository source-of-truth docs to match executable gates
   - Files: `docs/testing/testing-strategy.md`, `docs/workflows/development-workflow.md`, `README.md`, `docs/deferred/2026-05-01-backend-sql-write-contract-gates.md`
   - Change:
     - Remove any statement that implies planning write contract coverage is already inside `verify.sh` before that is true.
     - Describe final local verify path, CI gate shape, and CI-parity commands accurately.
     - Update or close deferred entry in same change once gate lands.
   - Verify:
     - `rg -n "planning write contract|song-crud-write-contract|verify.sh|run-ci-locally" README.md docs/testing/testing-strategy.md docs/workflows/development-workflow.md docs/deferred/2026-05-01-backend-sql-write-contract-gates.md`

### Acceptance Criteria

- `./scripts/verify.sh` fails when either backend write-contract suite fails.
- Primary CI blocks merge when either backend write-contract suite fails.
- CI does not rely on a manual-only script path for backend SQL write acceptance.
- Local CI simulation documents and mirrors the final gate split.
- Repository docs no longer overstate or understate backend write-contract coverage.

### Exact Validation Commands

```bash
bash scripts/tests/verify-test.sh
bash scripts/tests/planning-write-contract-test.sh
bash scripts/tests/song-crud-write-contract-test.sh
bash scripts/tests/run-ci-locally-test.sh
./scripts/verify.sh
./scripts/run-ci-locally.sh verify
./scripts/run-ci-locally.sh all
```

### Risks & Mitigations

- Runtime inflation in `./scripts/verify.sh`
  - Mitigation: use one shared backend-contract gate entrypoint and avoid needless duplicate setup in CI.
- Hidden Supabase lifecycle duplication
  - Mitigation: measure where reset/provision happens, then centralize or explicitly accept isolation boundaries in one place.
- Local/CI drift caused by skip flags
  - Mitigation: keep skip behavior CI-only, documented, and mirrored through `./scripts/run-ci-locally.sh`.
- Documentation drift after gate changes
  - Mitigation: treat docs updates as same-slice acceptance criteria, not follow-up cleanup.

### Rollback Plan

- Revert CI workflow changes first if pipeline runtime or stability regresses unexpectedly.
- Revert `scripts/verify.sh` gate wiring next if local developer workflow becomes unusable.
- Keep the shared backend-contract gate script and focused contract suites intact so the repository does not lose manual regression coverage during rollback.
- Restore docs in the same rollback so repository guidance matches the executable gate state.

### Escalation Points

- If shared setup cannot avoid repeated Supabase reset/provision cost without weakening isolation, escalate gate design before merging.
- If `./scripts/verify.sh` runtime becomes too slow for normal local use, escalate with measured timings and choose whether default local verify keeps or skips backend-contract coverage.
- If CI split introduces meaningfully different behavior from `./scripts/run-ci-locally.sh`, escalate parity design before merge.
- If either backend contract suite needs semantic changes rather than only gating changes, escalate scope because this plan assumes contract coverage itself is already correct.
