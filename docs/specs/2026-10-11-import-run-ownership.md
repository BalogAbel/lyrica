# Spec: An Import Run Writes Only Into the Catalog It Analysed Against

- Date: 2026-10-11
- Branch: `fix/import-run-ownership`
- Closes: R17 and R16 of `docs/deferred/2026-10-09-sign-out-guard-residuals.md`,
  and narrows R10 there
- Builds on: ADR-037 (current-user ownership amendment, XU1–XU6),
  `docs/specs/2026-10-11-reauth-wipe-recount.md` (RW3, the per-user import
  tracker), `docs/specs/2026-10-07-sign-out-pending-work-guard.md` (SO7)
- Related: ADR-029, ADR-035 (unchanged)
- Plan: `docs/plans/2026-10-11-import-run-ownership.md`

## Problem

The ChordPro import captures the catalog context `(userId, organizationId)`
when a run starts and analyses the picked files against it. When the analysis
finds duplicates the run stops in `ImportAwaitingDuplicateResolution` and waits
for the user's answer in a modal dialog, for as long as the user takes. The
answer then calls `commitWithResolutions`, which does not use the run's
context: it reads the live `activeCatalogContextProvider` again
(`chordpro_import_controller.dart`, `commitWithResolutions`) and sets
`_runUserId` from it.

The live catalog context belongs to the current user (XU2). So whoever is
current when the dialog is answered receives the files, whoever picked them.
`SongLibraryService.createSong` and `updateSong` only use the context they are
given; nothing below the controller compares it with the run.

### Reproduced (phase 1)

Real `AppAuthController`, `LocalDataLifecycle`, Drift in-memory stores, the
real reauth providers, the real `ChordProImportController` over the real
import service and `SongLibraryService`, and the real song sync controller
over a recording stand-in for the backend. Only the platform file picker
answers from the test
(`apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart`,
groups "a duplicate resolution never writes into another user's catalog
(R17)" and "an import picked during a sign-out ... (R10, R16)"):

- **(a) A's files go to B.** A's import analyses three files (one duplicates
  a song A has) and waits at the dialog. B signs in; A has no unsynced work,
  so there is no prompt and A's data is wiped (ADR-029). The dialog is
  answered. B's catalog now holds A's two new songs as `pendingCreate`
  (`Expected: <0>  Actual: <2>`), and a sync pass sends
  `[A import one, A import two]` to `org-b`, B's organization. This is the
  cross-user write the entry describes, including the server.
- **(b) B's files go to A.** A has unsynced work, so B's sign-in asks. While
  the prompt is pending B's context is live (R-C) and B imports into it and
  waits at the dialog. B cancels; the app returns to A, A's context is live
  again. The dialog is answered. A's catalog holds B's two files
  (`Actual: <2>`) and a sync pass sends them to `org-a`. This is the chain the
  final review of #88 found (`docs/specs/2026-10-11-reauth-wipe-recount.md`,
  "Found by the final review"): #88 stopped the automatic decline from
  entering it, but a user's own Cancel enters it the same way.
- **(R10, R16) rows for a signed-out user.** An import that SO7 did not see
  (it started inside the sign-out's count, or after the warning closed) is
  waiting for the OS picker. The real sign-out command completes. The picker
  answers; the run analyses and commits with the captured context of the
  signed-out user and writes two rows after the purge (`Actual: <2>`), with
  the app already `signedOut` and no catalog context.

Both (a) and (b) fail on `main`. Two guards stay green and must stay green: A
re-authenticating while the dialog is open, and B's sign-in cancelled before
the dialog is answered, both of which land A's files in A's catalog.

### Root cause

The run's identity is a local variable of `_runImport`. It is dropped when the
run parks at the dialog, and the continuation re-derives "the context" from a
provider that, by XU2, always means "the current user's". Nothing states that
a commit belongs to the context its files were analysed against, and nothing
checks that this context is still the active one when the commit starts.

## Decisions

### IR1 — a commit names the context of the run it resumes

The commit takes its context as an argument; it no longer chooses one.

- `ImportAwaitingDuplicateResolution` gains a required field
  `ActiveCatalogContext context`: the catalog context the run analysed the
  files against. It is the run's continuation: `result`, `successes`, and the
  scope they belong to. `_runImport` sets it from the context it captured at
  its start.
- `commitWithResolutions` gains a required parameter
  `ActiveCatalogContext context` (the same name and shape as
  `ChordProImportService.commitImport`), and the dialog host
  (`SongListScreen._resolveImportDuplicates`) hands back the context of the
  awaiting state the dialog was opened for. `commitWithResolutions` itself no
  longer reads the live context. The controller reads it in three places only:
  when a run starts (to capture), after the analysis before the run parks
  (IR2's parking check) and at the start of `_commit` (IR2's commit check).
- `_runUserId` follows the given context, so the tracker reports a resumed
  commit for the run's user, which is the user whose work it writes (RW3: a
  guard keyed to the protected user).

Why an argument and not a field the controller reads from its own state: the
answer then names its run, whatever the controller holds by the time the
dialog is answered. A commit can no longer be misattributed to another run's
awaiting state, and a future second caller has to say which context its files
belong to, which is the question R17 shows nobody asked.

This is a signature change. It is why the six hand-built awaiting states and
the two direct `commitWithResolutions` calls in existing tests change (see
"Intentional test changes").

### IR2 — a commit starts only while its context is still the active one

`_commit` is the one method every write passes through: `startImport` reaches
it when there are no duplicates, `commitWithResolutions` after the dialog. At
its start, before `ImportCommitting` and before any write:

```dart
if (_contextReader() != context) {
  state = const ImportFailed(AppStrings.songImportContextChangedMessage);
  return;
}
```

Nothing is written. The state leaves any running phase, so the tracker, SO7's
keep-alive link and SO7's sign-out refusal release through the existing state
setter; `_endRun` has nothing left to end. The user sees one snackbar through
the host's existing `ImportFailed` handling (IR2 itself needs no host
change; IR1's argument does).

`ActiveCatalogContext` compares by value, so a context that was re-established
for the same user and organization is the same context.

**A second check point: where a run parks.** The same comparison runs in
`_runImport` once the analysis returned, before the run leaves the analysing
phase: before it enters `ImportAwaitingDuplicateResolution`, and before it ends
`ImportDone` when nothing was left to import. Without it the duplicate dialog
(or the summary) could OPEN after the user switch, because the OS picker or the
analysis straddled the auth edge, and list the first user's titles to the
current user. Reproduced by the probe of the adversarial review (B signs in
while A's picker is open; the picker answers; the dialog opens for `user-a`
while `user-b` is current). A run that never parks needs no pop, so the R9
hazard that keeps R18's "outlives the switch" shape deferred does not apply.
The write is still guarded by the first check point at the start of `_commit`.

**Why the active context, not `AppAuthState.currentUserId`.** The starting
proposal compared the current user with the run's user. The active catalog
context is the better signal:

- By XU2 the active context belongs to the current user only, so "the run's
  context is the active one" implies "the run's user is current". The converse
  already refused: a current user with no context fails an import with
  `songImportNoContextMessage` today. For the same user and organization
  nothing that works today is refused.
- It is stronger on the other axes the same hazard has. A same-user change of
  organization means the duplicates' `existingSongId` values belong to a
  catalog that is no longer the active one, and a released context (a purge, a
  sign-out) means the catalog the files were analysed against is gone. Both
  are the shape of R17 on the organization and lifecycle axes.
- It needs no new dependency. The controller keeps its single reader; the
  tests that drive the real provider keep working without an auth override
  (a user reader would build the real `AppAuthController` in them).

### IR3 — no per-row check (decided, with the reason)

Re-running the check before every row would close the rest of R10, but it is
not cheap and it is not neutral:

- RW3 pins the opposite for a commit that is already writing: AC3 and AC4 of
  `docs/specs/2026-10-11-reauth-wipe-recount.md` require that a different-user
  sign-in resolving behind a running import declines the wipe and that the
  import's rows land in the prior user's catalog. On B's `signedIn` edge XU2
  releases A's context, so a per-row check against the active context would
  stop that commit after its first row and leave a partial import. A per-row
  check would have to change RW3's contract.
- The rows such a commit writes carry the run's own `(userId, organizationId)`.
  They are never another user's. At worst they are R10's orphans, and the
  wipe that RW3 declines cannot delete them unannounced.

So the check runs once, at the start of the commit. A commit that started
while its context was active finishes into it.

### IR4 — what this does to R10 and R16

IR2 refuses a commit that starts after the context was released. The sign-out
sequence releases the catalog context in its first step, synchronously
(`SongCatalogController.handleExplicitSignOut` sets the initial state before
it purges), so every commit that starts after that point is refused. That is
exactly what R16 and the "after the sign-out ends" part of R10 describe:

- **R16 is closed.** An import started after the warning closes finds no
  catalog context and fails at its start (it already did); one that was
  waiting for the picker is refused at its commit.
- **R10 is narrowed, not closed.** What remains is a commit that started
  before the sign-out's first step: the import must have started inside the
  count's await, and its rows are written while the warning is open or while
  the purge runs. They are then deleted by the confirmed purge without having
  been named in the warning, or land after the purge as orphans. Reaching it
  needs the Import tap and the sign-out tap inside one local count read. The
  entry keeps its text with this narrower scope and a fix sketch (a re-check
  of the tracker in the sign-out sequence, which is a change to the sign-out
  flow and not part of this PR).

## What the user sees

- **A's duplicate dialog open, B signs in, the dialog answered:** one snackbar,
  "The account or workspace changed, so the import was stopped and nothing was
  imported. Start the import again." (`AppStrings.songImportContextChangedMessage`;
  it says the import has to be restarted, not only that it failed). Nothing is
  written for either user.
- **The same, but B cancelled back to A before the answer:** A's files are
  imported as before.
- **The user switched while the picker was open or the analysis ran:** no
  dialog opens; the same snackbar.
- **A re-authenticates as A while the dialog is open:** unchanged.
- **The user signed out while the dialog was open, then answers it:** the same
  snackbar (before: "Sign in before importing songs."; the new text says what
  happened).

## Acceptance criteria

Integration (the reproduction suite, red on `main`):

- **AC1 (IR1, IR2, direction a):** after the dialog is answered no pending
  song row exists for B or for A, a sync pass for B's organization sends
  nothing, and the run ends `ImportFailed`.
- **AC2 (IR1, IR2, direction b):** the same for B's files and A's catalog.
- **AC3 (IR2, R10/R16):** an import whose picker answers after the real sign-out
  command completed writes no row for the signed-out user and ends
  `ImportFailed`.
- **AC10 (IR2, parking):** an auth edge while the picker is open, or while the
  analysis runs, leaves no dialog: the run never enters
  `ImportAwaitingDuplicateResolution`, ends `ImportFailed` with the message,
  and writes nothing (integration: both variants; unit: the picker variant).
- **AC4 (guards, green before and after):** A re-authenticating as A while the
  dialog is open, and B's prompt cancelled before the answer, both import A's
  files into A's catalog (two new songs and the overwritten one: three
  pending rows).

Controller (unit, no auth stack):

- **AC5 (IR1):** a run that reached `ImportAwaitingDuplicateResolution`
  carries the context it analysed against (the same instance), and
  `commitWithResolutions(context: ...)` passes the instance it was given to the
  import service when the live context is an equal but distinct object.
- **AC6 (IR2):** when the live context is another user's, the import service
  is not called, the state is `ImportFailed` with
  `AppStrings.songImportContextChangedMessage`, and the tracker is idle.
- **AC7 (IR2):** the same when the live context is the same user's other
  organization, and when it is `null`.
- **AC8 (IR2, no duplicates):** a run without duplicates whose context changed
  while the picker was open is refused before it writes (the service is not
  called, `ImportFailed`).
- **AC9 (IR1, host):** the duplicate dialog host calls
  `commitWithResolutions` with the context of the awaiting state it opened
  the dialog for, not the live one (widget test).

Each guard must be pinned individually: removing IR2's check at the start of
`_commit` fails AC1, AC2, AC6 and AC7 (AC3 and AC8 are refused by either
check and fail only when both are removed), and removing the parking check fails
AC10; making `commitWithResolutions` ignore its argument and read the live
context fails AC1, AC2 and AC5; making the host pass the live context fails
AC9 (the plan lists all three as mutation checks).

## Intentional test changes

Both groups follow from IR1's signature change and are mechanical; no
assertion or behaviour they pin changes:

- The six places that build `const ImportAwaitingDuplicateResolution(
  emptyResult, [])` by hand
  (`test/presentation/auth/sign_out_flow_test.dart`,
  `test/presentation/song_library/chordpro_import_controller_test.dart` four
  times, `test/presentation/song_library/song_list_screen_test.dart`) gain
  `context: <a const context>`.
- The two direct `commitWithResolutions` calls in
  `chordpro_import_controller_test.dart` (the `startCommit` helper and "is
  refused while a commit is running") gain `context:` with the same context
  their `activeCatalogContextProvider` override returns.

A failing existing test outside this list stops the work (see the plan).

## Non-goals

- No new purge, no new `PurgeReason`, no ADR-035 change. Nothing new writes to
  or deletes from a store; a commit that would have written is refused.
- XU1–XU6, SO1–SO8 and RW1–RW4 are unchanged. RW3's tracker keeps its meaning;
  IR1 only makes `_runUserId` name the run's user on the dialog path too.
- No per-row check (IR3), no change to the sign-out flow (R10's remainder), no
  change to the reauth or sign-out hosts.
- The open dialog itself (below) is not closed.

## Residuals

- **R18, the open duplicate dialog outlives the user switch.** The dialog is a
  modal route owned by the navigator, not by the screen. After B signed in it
  is still on screen until it is answered, and the answer is then refused
  (IR2). It lists the titles of the files A had just picked (`incomingTitle`
  of each duplicate; it shows no file names and no catalog entries), each of
  which equals a title A's catalog already holds. Deferred, with the reasons
  stated: it is presentation only; the answer is refused and nothing is
  written; what it shows comes from local files A picked moments earlier, not
  from a list of A's synced catalog; and closing a dialog from code is the R9
  hazard (`showDialog` hands back no route, so a programmatic pop removes
  whatever is on top, for example the reauth dialog stacked above it). A
  correct close needs the host to push its own `DialogRoute` and keep the
  handle, which is a redesign of the host. Trigger: a redesign of the
  duplicate dialog host, or the session-transition coordinator
  (`docs/deferred/2026-10-11-session-transition-coordinator.md`). Recorded in
  the residuals entry.
- **R10, narrowed** as described in IR4.
- **Found by the adversarial review of this fix** (none blocking; recorded in
  the residuals entry): R18's second shape (the dialog can also open after the
  user switch when the picker or the analysis straddles the auth edge) is
  closed in this PR by IR2's second check point, at the user's request; the
  already open dialog (R18 as written) stays deferred. R19 (a same-user
  context gap refuses with the account-changed message), R20 (an answer
  dropped silently while a run is running) and R9 extended (the reauth host's
  pop can reach the duplicate dialog) are recorded.

## Documentation updates (in the implementation PR)

- ADR-037: amendment "import runs hold their context" (IR1, IR2).
- `docs/architecture/architecture.md`: one sentence after the RW3 sentence.
- `docs/testing/testing-strategy.md`: the cross-user pattern gains the
  duplicate-dialog rule (drive the commit the way the host does, after the
  user changed).
- `docs/deferred/2026-10-09-sign-out-guard-residuals.md`: R16 and R17 removed,
  R10 narrowed, R18 added (done at the design gate).
- `docs/plans/2026-10-01-delivery-roadmap.md`: the sequencing note names this
  PR between #88 and S0 PR 2 (done at the design gate).
