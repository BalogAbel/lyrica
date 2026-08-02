# Phase 4 Closeout Review Remediation

> Status: Approved

## Goal

Close the verified semantic gaps found during the final review of Phase 4 before
the branch is pushed or proposed for merge. The remediation preserves the
existing Phase 4 boundaries: offline durability remains bounded, discard stays
local-first, authorization remains backend-enforced, and the Riverpod 3
migration and Phase 5 work remain deferred.

## Verified Problems

### R1 — different-user reauthentication can undercount destructive work

The different-user flow counts only planning mutations whose status is
`pending`, scoped to one cached organization. The confirmed wipe deletes the
prior user's planning data across every organization and every actionable sync
status. A prior user whose only work is accepted, conflicted, failed, or stored
under another organization can therefore receive no warning before that work is
deleted.

The zero-work shortcut is safe only when no mutation that the wipe can destroy
exists anywhere in the prior user's deletion scope.

### R2 — a superseded reauthentication prompt can still delete data

Different-user resolutions are serialized, but a newer signed-in event does not
immediately invalidate an already-open prompt. If the old prompt is confirmed,
the old transition can delete the durable prior user's data and persist an
identity that is no longer the live session.

The active session and transition generation must still match immediately
before any deletion, cancellation, or identity write.

### R3 — the reauthentication host does not consume a pre-existing prompt

The root prompt host observes only later controller changes. Normal production
startup currently mounts the host before prompt publication, so this is a
component-contract hardening gap rather than a demonstrated production outage.
The host should nevertheless consume a request that already exists when it is
attached and must show each request exactly once.

### R4 — song discard races a sync that already owns a remote request

`SongMutationSyncController` single-flights sync calls but does not coordinate
discard with them. A sync can snapshot a mutation and send it remotely while a
concurrent discard clears the local row. Later sync reconciliation can then
recreate or overwrite local state, and the UI can report a successful discard
for intent that may already have reached the backend.

### R5 — the storage-pressure overview can retain a stale footprint

The local storage footprint provider measures once per provider generation. A
long-lived listener can therefore keep showing old byte counts and the wrong
pressure classification after mutation writes, clears, sync reconciliation, or
catalog-source eviction.

### R6 — ADR-028 overstates when storage eviction runs

The implemented and tested policy evicts droppable catalog sources only after a
local storage write fails, then retries the write once. Some ADR and spec text
also promises proactive eviction when the measured total enters a critical
threshold. No production path implements that second trigger.

The accepted closeout contract is the existing failure-driven policy. This
remediation corrects the documentation; it does not add proactive threshold
eviction.

### R7 — the pg_cron contract test verifies a copied command

The orphan-cleanup contract test executes a duplicate SQL command embedded in
the test and checks only the registered job name. The migration's actual
`cron.job.command` can drift while the copied command continues to pass.

### R8 — Phase 4 source documents still look unfinished

Three implemented Phase 4 specifications still say `Draft`, and their plans
contain unchecked steps despite the register declaring their work closed. The
documents must reflect only work established by repository history and observed
verification; unevidenced boxes must not be checked merely for appearance.

## Decisions

### D1 — destructive-work detection matches the wipe scope

The pending-work boundary will count every song and planning mutation that the
different-user wipe can destroy for the prior user, across all organizations
and all actionable statuses. A storage error remains uncertainty and takes the
confirmation path. It never becomes an inferred zero.

No authorization decision moves into Flutter. This count controls only whether
destructive local cleanup requires explicit confirmation.

### D2 — auth edges invalidate stale work synchronously

Every new signed-in auth notification advances a generation before it is queued
for serialized resolution. A queued resolution captures that generation and
the exact session identity. It revalidates both after every user-controlled
wait and immediately before each destructive or durable side effect.

A superseded resolution performs no deletion, sign-out, or identity write. The
new auth notification synchronously completes any open stale prompt with a
typed, non-confirming superseded outcome so that it cannot indefinitely block
the serialized resolution chain. The latest queued edge then resolves against
the still-durable prior identity. Supersession must not report that a wipe or
cancellation happened.

### D3 — prompt delivery is current-value aware and exactly once

The root host consumes a prompt already present when it attaches and observes
later requests. Rebuilds while a dialog is open do not duplicate the dialog,
and completing an obsolete request cannot complete a newer request.

This stays on Riverpod 2.6.x. It is not a reason to begin the Riverpod 3
migration.

### D4 — sync and discard are mutually exclusive below the widget layer

The controller enforces ownership for a song context; UI disabling is only a
presentation aid, not the correctness boundary.

- If sync has already acquired the operation and may have sent an RPC, discard
  is rejected with a typed `sync in progress` result. Local data is unchanged,
  and the UI tells the user to retry after sync completes.
- If discard acquires the operation first, it completes its network-free local
  mutation removal before a later sync snapshots work. That later sync cannot
  send the discarded mutation.

`Discard All` acquires the same song-context discard ownership before changing
either subsystem. If song sync already owns the context, the whole batch is
rejected before any song or planning mutation is removed. The typed result
propagates through the unified controller to the popup, which reports that sync
is in progress instead of returning success. While the batch owns the context,
a new song sync cannot start between individual discard operations.

Discard does not wait and then claim success, and it does not issue a
compensating remote write. Both alternatives would misrepresent LF-7.

### D5 — footprint reads depend on an explicit storage revision

Every committed storage operation that can change measured local storage
advances one storage-footprint revision. The footprint provider watches that
revision, so it remeasures even while it remains mounted. Revision advancement
is tied to committed writes, clears, reconciliation, and eviction rather than a
top-level action's final result. It therefore also follows eviction whose retry
later fails and earlier rows committed by a batch that later returns an error.
An operation that commits no footprint change does not advance the revision.

The revision is an application invalidation seam, not a second source of byte
accounting. SQL-derived measurement remains authoritative.

### D6 — storage eviction remains failure-driven

ADR-028, the S12 specification, architecture text, and testing guidance will
state one production trigger: a qualifying local storage write failure causes
one droppable catalog-source eviction attempt followed by one write retry. A
critical measured total affects monitoring and user warning, not proactive
eviction.

The native-only verification boundary remains unchanged. Web IndexedDB
capacity assumptions stay unverified, and
`docs/deferred/2026-06-29-web-offline-e2e.md` remains the prerequisite for
relying on them.

### D7 — the cron test executes the registered contract

The contract test will read the registered orphan-cleanup job's command,
schedule, and active state from `cron.job`. It will execute that registered
command against the test fixtures and assert the cleanup boundary. The copied
SQL command will be removed from the test.

### D8 — closeout documents report evidence, not intent

The three Phase 4 specifications move to `Implemented` only after their current
contracts and this remediation are verified. Plan checkboxes are reconciled
against commits and observed command output. Items intentionally deferred or
not executable remain visibly unchecked or explicitly annotated.

## Rejected Alternatives

### Rewrite auth and sync as broad state machines

This could unify more lifecycle behavior, but it expands the regression surface
in two critical paths during closeout. The targeted generation and operation
ownership contracts provide the required safety without a subsystem rewrite.

### Accept the current sync-wins discard race

This can report that local intent was discarded after that intent has already
reached the backend. It is not an honest discard result.

### Compensate remotely after a racing discard

This would make discard depend on connectivity and would contradict LF-7.

### Add proactive threshold eviction now

This is a new policy and behavior change, not a correction required for the
implemented failure-recovery ladder. The accepted remediation instead aligns
the documents with the tested implementation.

### Close only the documentation and tests

That would leave verified destructive auth and sync races in a branch proposed
for merge.

## TDD and Verification Contract

Each behavior change starts with a focused failing test whose red result is
observed before implementation. A failing assertion is not adjusted to fit the
current behavior; unexpected results stop the slice for investigation. Tests
that pin concurrency or lifecycle behavior are falsified deliberately where a
safe temporary implementation break can prove that the assertion detects the
regression.

Required focused coverage includes:

1. A non-pending actionable planning mutation prevents silent different-user
   wipe; separate cross-organization planning and song mutations prove that the
   count matches both domains' user-wide deletion scope.
2. A newer live auth session supersedes an open prompt; confirming the stale
   prompt deletes nothing and persists no stale identity. The superseded prompt
   completes without user input, and the latest queued edge proceeds.
3. A prompt published before host attachment appears exactly once.
4. A remote sync held after RPC entry causes concurrent discard to return the
   typed rejection without clearing local state.
5. A discard that acquires ownership first prevents a later sync from sending
   the discarded mutation. A context snapshot paused on one song also blocks
   discard of a different song captured by that snapshot.
6. A mounted footprint provider remeasures and changes classification after a
   committed footprint-changing action, after eviction followed by a failed
   retry, and after partial batch completion followed by an error.
7. The cron cleanup fixtures are processed by the command fetched from the
   registered job.
8. `Discard All` rejects before changing either subsystem when song sync owns
   the context, and the popup displays the typed retry guidance.

After the focused suites, the branch must pass the full repository verification
and the separately requested backend contract, migration, and web release-build
commands at the final HEAD. No PR is opened until final semantic review has no
unresolved Blocker or Major finding.

## Documentation Impact

- Amend ADR-028 to describe failure-driven eviction precisely.
- Amend ADR-029 and the auth architecture/testing documentation with generation
  invalidation, wipe-scope counting, and current-value prompt delivery.
- Amend the LF-7 specification and sync documentation with the discard/sync
  mutual-exclusion contract.
- Reconcile the three Phase 4 specifications and plans with implemented status
  and observed evidence.
- Keep all Phase 5 exclusions and existing deferred documents out of this
  remediation.

## Non-Goals

- Riverpod 3 migration.
- UX-4/5/6/7/9/10/11, remaining accessibility work, screen-reader pass, i18n,
  dark theme, or design tokens.
- SEC-2, ARCH-4, schema-versus-app reconciliation, FreeShow, performance
  profiling, or production-readiness infrastructure.
- Web offline end-to-end validation or claims about IndexedDB capacity.
- Backend authorization changes.
