# Recovery Actions That Outlive Their Widget — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recovery work keeps running — and keeps invalidating — when the widget
that started it goes away, and the different-user reauth resolution finally runs
on the live sign-in path.

**Architecture:** The three popup row actions move their `ref` work into
controllers built the way `UnifiedDiscardController` already is: no stored `Ref`,
closures over the provider's `ref`, each taking `ref.keepAlive()` and releasing
it in a `finally`. The reauth resolution hooks the `signedIn` edge, reads the
prior identity before anything overwrites it, and asks a `ReauthPromptController`
for a decision; a host widget in `MaterialApp.router`'s `builder:` shows the
dialog.

**Tech Stack:** Dart / Flutter, Riverpod 2 (NOT 3 — see Non-Goals), Drift,
`flutter_test`.

**Spec:** `docs/specs/2026-07-30-recovery-actions-that-outlive-their-widget.md`

---

## Non-Goals, restated because this plan invites them

Do **not** start the Riverpod 3 migration
(`docs/deferred/2026-07-30-riverpod-3-migration.md`). If a task genuinely cannot
land without it, STOP and report — do not expand scope inside this branch.

Do not restructure the router into a shell. Do not refactor the popup beyond
moving the three methods' `ref` work.

---

## File Structure

**Create:**

| path | responsibility |
|---|---|
| `apps/lyron_app/lib/src/application/sync/unified_row_recovery_controller.dart` | the `ref` half of keep-mine / discard-mine / apply-to-group |
| `apps/lyron_app/lib/src/application/auth/reauth_prompt_controller.dart` | publishes a pending reauth prompt and receives its answer |
| `apps/lyron_app/lib/src/application/auth/pending_local_work_counter.dart` | combined song + plan pending count |
| `apps/lyron_app/lib/src/presentation/auth/reauth_prompt_host.dart` | observes the controller, shows the dialog |
| `docs/architecture/decisions/ADR-029-reauth-prompt-host-and-different-user-resolution.md` | the decision record |

**Modify:** `unified_sync_status_popup.dart`, `unified_sync_providers.dart`,
`auth_providers.dart`, `lyron_app.dart`, plus the documentation files.

**Delete on resolution:** `docs/deferred/2026-05-29-popup-row-recovery-provider-ref.md`
(Task 2) and `docs/deferred/2026-06-28-reauth-different-user-live-wiring.md` (Task 6).

Commands run from the repository root as `(cd apps/lyron_app && flutter test <path>)`.

---

### Task 1: Move the popup row actions onto a long-lived controller

**Files:**
- Create: `apps/lyron_app/lib/src/application/sync/unified_row_recovery_controller.dart`
- Modify: `apps/lyron_app/lib/src/presentation/sync/unified_sync_providers.dart`
- Modify: `apps/lyron_app/lib/src/presentation/sync/unified_sync_status_popup.dart`
- Test: new file next to the existing `unified_discard_controller_test.dart`

- [ ] **Step 1: Read the pattern you are copying**

Read `apps/lyron_app/lib/src/application/sync/unified_discard_controller.dart`
and its provider in `unified_sync_providers.dart` in full. The controller stores
no `Ref`; the provider builds closures over its own `ref`, each calling
`ref.keepAlive()` at the start and `link.close()` in a `finally`. Copy that
shape exactly — do not invent a variant.

- [ ] **Step 2: Write the failing tests**

Three behaviours, each of which the current code gets wrong:

1. `keepMine` completes its invalidations even when the caller that started it is
   gone. Model "the popup closed" the way the existing discard-all test models
   its scenarios — if that test has no precedent for it, drive the controller
   directly through its provider and assert the invalidations happened, since the
   controller no longer depends on any widget being alive.
2. Same for `discardMine`.
3. `applyToGroup` performs **all** of its post-work: the
   `planningDataRevisionProvider` bump AND the invalidation of
   `planningMutationEntriesProvider` and `planningPlanListProvider`. Assert the
   revision bump explicitly — it is the only thing that reaches the three
   *family* slug/detail providers, which are never invalidated directly, so
   dropping it in the move would silently stop them refreshing.

- [ ] **Step 3: Run and confirm they fail**

```bash
(cd apps/lyron_app && flutter test test/application/sync/)
```

- [ ] **Step 4: Implement the controller**

`UnifiedRowRecoveryController` exposes `keepMine`, `discardMine` and
`applyToGroup`, each taking the arguments the popup currently passes (song id,
or the plan row's mutation refs plus a retry flag). It holds closures, not a
`Ref`. Its provider wires them over `ref` with `keepAlive`, doing:

- `keepMine` / `discardMine` → call the song mutation sync controller, then
  invalidate `songMutationEntriesProvider` and `songLibraryListProvider`;
- `applyToGroup` → loop the refs calling retry or discard, then bump
  `planningDataRevisionProvider` and invalidate `planningMutationEntriesProvider`
  and `planningPlanListProvider`.

Each must report whether any operation failed, so the widget can still show its
snackbar. Return a value rather than throwing — a partial failure across several
refs is not one exception.

- [ ] **Step 5: Rewire the popup**

`_keepMine`, `_discardMine` and `_applyToGroup` become thin: read the controller,
await it, and show the failure snackbar if it reports one and
`context.mounted`. **Every `ref.invalidate` and revision bump leaves the
widget.** Keep the edit tight; do not restructure anything else in that file.

- [ ] **Step 6: Verify and commit**

```bash
(cd apps/lyron_app && flutter test)
(cd apps/lyron_app && dart format lib test)
(cd apps/lyron_app && flutter analyze)
git add apps/lyron_app/
git commit -m "fix(sync): run row recovery on a controller that outlives the popup"
```

---

### Task 2: Resolve the popup deferred doc

- [ ] **Step 1:** `git rm docs/deferred/2026-05-29-popup-row-recovery-provider-ref.md`
- [ ] **Step 2:** Commit with the code it resolves if Task 1 is not yet pushed,
  otherwise as its own commit:

```bash
git commit -m "docs(deferred): resolve the popup row recovery provider-ref item"
```

---

### Task 3: Count pending local work across songs and plans

**Files:**
- Create: `apps/lyron_app/lib/src/application/auth/pending_local_work_counter.dart`
- Test: alongside it

- [ ] **Step 1: Write the failing test**

A counter that, for a given user and organization, returns
`planning pending mutations + pending songs + conflict songs`. Test: zero when
everything is empty; the sum when each source contributes; and that a source
throwing propagates rather than being silently counted as zero — an undercount
here would understate what a wipe destroys.

- [ ] **Step 2: Implement**

Read the real APIs first: `PlanningMutationStore.readPendingMutations`,
`SongMutationStore.readPendingSongs`, `SongMutationStore.readConflictSongs`. The
counter takes those as injected readers so it is testable without Drift.

- [ ] **Step 3: Verify and commit**

```bash
(cd apps/lyron_app && flutter test test/application/auth/)
git commit -m "feat(auth): count pending local work across songs and plans"
```

---

### Task 4: The reauth prompt controller and its host

**Files:**
- Create: `apps/lyron_app/lib/src/application/auth/reauth_prompt_controller.dart`
- Create: `apps/lyron_app/lib/src/presentation/auth/reauth_prompt_host.dart`
- Modify: `apps/lyron_app/lib/src/app/lyron_app.dart`
- Test: controller test and host widget test

- [ ] **Step 1: Write the failing tests**

Controller: requesting a confirmation publishes a pending prompt carrying the
prior email and the pending count, and completes the returned future with the
answer when one is supplied. Two prompts cannot be pending at once — decide and
pin the behaviour (reject the second, or queue it) rather than leaving it
undefined.

Host widget: when the controller publishes a prompt, the host shows
`showReauthDifferentUserDialog` and feeds the result back. Cover confirm AND
cancel, and cover a barrier dismissal counting as cancel — the existing dialog
tests already pin that dismissal returns `false`, so the host must not turn it
into a confirm.

- [ ] **Step 2: Run and confirm they fail**

- [ ] **Step 3: Implement**

The controller lives on a `ProviderRef` and is app-scoped, not autoDispose — a
prompt must survive whatever is on screen. The host goes in
`MaterialApp.router`'s `builder:` in `lyron_app.dart`, wrapping the routed child.
It must not swallow the child, and it must not rebuild the whole app on every
prompt state change.

- [ ] **Step 4: Verify and commit**

```bash
(cd apps/lyron_app && flutter test)
git commit -m "feat(auth): add a reauth prompt controller and its host"
```

---

### Task 5: Wire the resolution into the live signedIn transition

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth_providers.dart`
- Test: extend the existing auth provider tests

This is the critical auth path. Read
`docs/architecture/decisions/ADR-020-non-destructive-session-and-offline-authenticated-state.md`
before writing any code.

- [ ] **Step 1: Write the failing tests**

All four outcomes, on the live edge:

1. **same user** → flush; nothing wiped, no dialog;
2. **different user, zero pending** → prior data wiped, proceed, no dialog;
3. **different user, pending > 0** → the prompt is requested with the prior email
   and the combined count; on confirm the prior user's catalog, planning data and
   identity are wiped and the new session proceeds;
4. **cancel** → the new session is signed out, nothing is deleted, and the app
   stays offline-authenticated as the prior user.

Plus two hazard tests:

5. **the prior identity is still readable when the resolution runs.** Today
   `lastKnownIdentityPersistenceProvider` overwrites it on the same `signedIn`
   edge. If it wins the race the different-user case cannot be detected at all.
   This test must fail if the ordering regresses.
6. **a failure to count pending work takes the confirm path, never the wipe
   path.** Uncertainty must never authorise deletion.

- [ ] **Step 2: Run and confirm they fail**

- [ ] **Step 3: Implement**

Hook the same `prev != signedIn && next == signedIn` edge that
`membershipRefreshEffectProvider` uses. Read the prior identity from
`LastKnownIdentityStore` **before** anything overwrites it, then call
`resolveReauth` with:

- `flushSameUser` → whatever the current signedIn path already does;
- `wipePriorAndProceed` → `SongCatalogStore.deleteCatalogsForUser`,
  `PlanningLocalStore.deletePlanningDataForUser`, `LastKnownIdentityStore.clear`,
  for the PRIOR user id;
- `confirmDifferentUser` → the reauth prompt controller;
- `cancelToPriorUser` → sign the new session out and leave the prior
  offline-authenticated state intact.

Solving the ordering hazard is part of this task, not a follow-up. Whatever
mechanism you choose — sequencing the listeners, having persistence await the
resolution, or capturing the prior identity earlier — say in your report exactly
what you chose and why it is robust rather than merely lucky about registration
order.

**ADR-020 must not regress:** an unknown or connectivity-failed session stays
non-destructive. Only explicit sign-out, authoritative revocation, and a
confirmed different-user sign-in delete immediately.

- [ ] **Step 4: Verify and commit**

```bash
(cd apps/lyron_app && flutter test)
git commit -m "feat(auth): resolve a different-user sign-in on the live path"
```

---

### Task 6: Documentation

- [ ] **Step 1:** Write
  `docs/architecture/decisions/ADR-029-reauth-prompt-host-and-different-user-resolution.md`,
  following the structure of ADR-027/ADR-028. Carry D2, D3, D4 and D5 from the
  spec — especially D5's boundary: a confirmed different-user sign-in deleting
  local data is not the destructive-on-uncertainty behaviour ADR-020 forbids, and
  cancel deletes nothing. Record the rejected navigator-key option and why.

- [ ] **Step 2:** Update `docs/architecture/architecture.md` (the authenticated
  shell hosts a reauth prompt; recovery actions run on long-lived controllers)
  and `docs/testing/testing-strategy.md` (the new contracts).

- [ ] **Step 3:** `git rm docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`

- [ ] **Step 4:** Verify and commit

```bash
./scripts/verify.sh --skip-migrations --skip-backend-write-contracts
git add docs/
git commit -m "docs(auth): ADR-029 reauth prompt host and different-user resolution"
```

---

## Self-Review

**Spec coverage:** D1 → Tasks 1–2; D2 → Task 4; D3 → Task 5; D4 → Task 3;
D5 → Task 5 and the ADR in Task 6. Testing contracts 1–2 → Task 1; 3–6 → Task 5;
7 → Task 5 hazard test; 8 → Task 5 hazard test.

**Test bodies are described rather than written out** because each must adopt the
fakes and style of an existing suite that has to be read first — the auth
provider tests and the discard-controller test in particular. Every assertion
each test must make is enumerated above.

**The riskiest task is 5**, not because it is large but because it is the
critical auth path with an ordering hazard and a destructive branch. It gets its
own review before Task 6.
