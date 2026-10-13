# Plan: Sync and Account Feedback (S6a)

> Status: implemented (2026-10-12) on `fix/sync-and-account-feedback`, PR
> pending merge.

- Spec: `docs/specs/2026-10-12-sync-and-account-feedback.md` (FB1–FB16,
  CP/SF/DA/L acceptance criteria)
- Branch: `fix/sync-and-account-feedback` (from `main` at `c561d20`)
- Execution: subagent-driven. Implementer Sonnet 5.5 per task, task review
  Haiku 4.5. One adversarial Opus 5.5 whole-diff review before the PR.
- Every task: red test first, then `flutter test` (full suite) and
  `flutter analyze` from `apps/lyron_app`. A failing dependency audit is
  fixed in a separate `chore(deps)` commit with a targeted
  `flutter pub upgrade <pkg>`.

## STOP-and-report conditions

- A fix would change the sign-out sequence, a purge, the D5 gate, the
  Delete-account RPC or the `signedOut` edge it emits.
- A fix would need a backend change, a migration or a stored-data change.
- A row's severity, a row action (Keep mine, Discard mine, Try again) or
  which rows are retried would change for any reason other than copy.
- An existing test fails for a reason other than the text it matched.

## Tasks

### Task 1: Chips and dead strings (FB1–FB5, FB13)

Files: `lib/src/shared/app_strings.dart`,
`lib/src/presentation/sync/unified_sync_status_popup.dart` (no logic change),
`test/presentation/sync/unified_sync_status_popup_test.dart`,
`test/application/sync/unified_sync_overview_test.dart`.

- Red: CP1–CP4.
- Replace the seven `unifiedSyncReason*` values with the spec's copy table.
  Rewrite the comment above `unifiedSyncReasonAuthorizationDenied`: it no
  longer says its siblings are code-shaped; it says the chip names the likely
  cause and keeps "retrying will not help" (D5.6).
- Delete the nine dead constants of FB4. Before deleting each, grep `lib/`
  and `test/` for it; after, `flutter analyze` must be clean.
- The existing popup tests find chips through the constants and stay valid.
  CP1 uses literals on purpose.

### Task 2: English dialogs and the language guard (FB14, FB15)

Files: `lib/src/shared/app_strings.dart`,
`test/presentation/auth/reauth_different_user_dialog_test.dart`,
`test/presentation/auth/reauth_prompt_host_test.dart`, the membership-gate
tests that open the purge dialog, new
`test/shared/app_strings_language_test.dart`.

- Red: L1, L2.
- Translate the ten constants with the spec's table. Keep the signatures
  (`email`, `count`). Add the singular for a count of one, as
  `unsyncedSignOutPendingMessage` does.
- `reauth_different_user_dialog_test.dart` has one literal Hungarian
  expectation; rewrite it to the English text.
- The guard reads `lib/src/shared/app_strings.dart` from disk (the test's
  working directory is `apps/lyron_app`) and fails on
  `[áéíóöőúüűÁÉÍÓÖŐÚÜŰ]`. It does not look at song data.

### Task 3: Sign-out feedback (FB6–FB8)

Files: `lib/src/application/auth/sign_out_command.dart`,
`lib/src/presentation/auth/sign_out_flow.dart`,
`lib/src/presentation/song_library/song_list_screen.dart`,
`lib/src/shared/app_strings.dart`,
`test/application/auth/sign_out_command_test.dart`,
`test/presentation/auth/sign_out_flow_test.dart`,
`test/presentation/song_library/song_list_screen_test.dart`,
`test/presentation/account/account_screen_test.dart`.

- Red: SF1–SF8.
- `SignOutOutcome` gains `blockedByImport`, with a doc comment: produced only
  by the presentation flow (SO7), never by `SignOutCommand`.
- `SignOutCommand._confirm` returns `bool?`: `null` after reporting an error.
  `run` maps `null` to `SignOutOutcome.failed`, `false` to `cancelled`. No
  other line of the sequence changes.
- The flow, prescribed shape:

  ```dart
  Future<SignOutOutcome> signOutWithPendingWorkGuard(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // FB7: before the first await. The messenger belongs to the app; the
    // screen that took the tap can unmount while the dialog or the sequence
    // runs.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final outcome = await _run(context, ref);
    final message = signOutFeedbackMessage(outcome);
    if (message != null && messenger != null && messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
    return outcome;
  }
  ```

  `_run` is the current body, returning `blockedByImport` where it returned
  `cancelled` for the SO7 refusal. `signOutFeedbackMessage` is a pure function
  of the outcome (the spec's FB7 table) so the mapping is unit-testable.
- Remove the `isImportRunning` early `return` in `song_list_screen.dart`
  (FB8). The flow performs the same check.
- Add the three sign-out strings to `AppStrings`.
- Rewrite the three existing `sign_out_flow_test.dart` "cancels" cases to
  expect `blockedByImport`, and the throwing-confirmation case of
  `sign_out_command_test.dart` to expect `failed`.

### Task 4: Delete account (FB9, FB10)

Files: `lib/src/presentation/account/account_screen.dart`,
`lib/src/shared/app_strings.dart`,
`test/presentation/account/account_screen_test.dart`,
`test/application/auth/app_auth_controller_sign_out_test.dart`.

- Red: DA1–DA3. DA1 is red today because the unhandled error fails the
  widget test.
- In the tile's handler: capture `ScaffoldMessenger.of(context)` before the
  first `await`; keep the SO8 `askedUserId` check; wrap
  `controller.deleteAccount()` in `try`/`catch`/`finally`. In `catch`: report
  with `FlutterError.reportError` (library `AccountScreen`, a static context,
  nothing from the error's data added) unless
  `isConnectivityFailure(error)`; show `deleteAccountFailedMessage`. The
  `finally` keeps its `mounted` check.
- `AppAuthController.deleteAccount` is not changed. DA3 pins what it already
  does.

### Task 5: Documents (FB12)

- Deferred:
  - add `2026-10-12-sync-popup-narrow-layout.md` (pre-existing: at a 360 px
    phone the header buttons and a conflict row's action buttons fill the
    dialog and squeeze the title and chips to zero width; layout work, found
    by CP4 of this slice; trigger: S3 PR 2 extends the popup);
  - add `2026-10-12-delete-account-session-loss-purge.md` (pre-existing: a
    session lost while the Delete-account RPC runs is mapped to `signedOut`
    because `AppAuthController.deleteAccount` holds `_isSigningOut` for the
    whole call, so the purges run although the RPC may reject; found by the
    Task 4 review; fix sketch: map a session loss during the call to
    `sessionExpired` unless the RPC succeeded; trigger: the next change to
    `AppAuthController.deleteAccount` or `_isSigningOut`);
  - remove `2026-10-12-sync-reason-chip-copy.md`;
  - remove `2026-09-30-capability-gating-offline-cold-start.md`;
  - `2026-10-05-membership-revoked-notice.md`: option (b) marked done in S6a,
    option (a) stays trigger-gated;
  - `2026-10-09-sign-out-guard-residuals.md`: remove R8 and R15, extend the
    "closed since" note.
- `docs/specs/2026-10-07-sign-out-pending-work-guard.md`: it still says the
  SO7 import refusal and a throwing confirmation give `cancelled` (enum list,
  SO3, SO7, AC6). Add a status note under the title pointing at FB6/FB7 of
  the S6a spec and amend those four statements: the import refusal gives
  `blockedByImport`, a throwing confirmation gives `failed`.
- `docs/architecture/architecture.md`: next to the stored capability set,
  record that `IfCapability` fails open without a stored set and that
  failing closed was rejected (it would take offline editing from legitimate
  editors); and that a rejected delete shows the generic remote-missing
  phrase because the backend answers `plan_not_found` for a missing
  capability. Update the unified sync overview paragraph: the popup shows
  phrases for the domain reasons, not reason codes.
- `docs/product/sync-ux-contract.md` and `docs/testing/testing-strategy.md`:
  the same wording fix. `docs/domain/domain-vocabulary.md` keeps the domain
  names.
- Roadmap: S6a row and status note (merged placeholder until the PR number
  is known), the deferred-triage list.
- Mark the spec and this plan implemented; add the review outcome section.

## Final review

One Opus 5.5 adversarial whole-diff review. Claim to disprove:

> A refused or failed sign-out or Delete account can still end with no
> visible feedback, a user's own cancel shows an error, a message states
> something false about what happened to the user's data, or the change
> alters sign-out, purge or delete behavior beyond feedback.

Blocking findings only that claim. At most one fix round. Everything else is
deferred with a document.

## Final review outcome

Adversarial Opus 5.5 whole-diff review of `c561d20..86dc79e`, claim: "a
refused or failed sign-out or Delete account can still end with no visible
feedback, a user's own cancel shows an error, a message states something
false about what happened to the user's data, or the change alters sign-out,
purge or delete behavior beyond feedback."

- **Blocking (B1, one counterexample to the first part).** The router is
  rebuilt on every auth state change (`app_router.dart` watches the
  controller) and disposes an open sign-out confirmation unanswered. The
  future never completed, `SignOutCommand` kept its lock, and every later
  sign-out was `alreadyRunning`, silent. Pre-existing, reproduced with the
  real router (a user switch, or a null session, while the dialog is open).
  Fixed in the one allowed round (FB16, SF9): the flow detects a dialog lost
  unanswered and ends `failed` with a message, the lock is released. The
  router is not changed; the rebuild is a deferred entry.
- **Reverted (N1).** The mounted guard on the Delete-account spinner (Task 4
  polish) changed Delete behavior against the guarantee in a path the app
  cannot reach; it was reverted with its two tests.
- **Corrected docs (N2, N3, N4, N6, N7).** The lost-response retry wording,
  the `superseded` examples, the reachability of the Delete `superseded`
  message (defense in depth behind the router rebuild), the router-rebuild
  notes on R9 and R18, and the Delete-account fix sketch's generation check.
- **Parts 2–4 of the claim: no counterexample.** A user's own Cancel shows
  nothing; no shipped string was false (the Delete-account message was fixed
  earlier, by the Task 4 review: a session lost during the call is purged by
  the pre-existing mapping, so the message makes no local-data claim);
  `AppAuthController`, the router, the purges and the D5 gate are untouched,
  and `SignOutCommand` changed only by FB6.
- **Fix-round re-review:** accepted. Two observations went into the router
  deferred entry (a same-turn pop and teardown; the reauth host's locks).
- **Non-blocking, deferred:** "Check your connection" also shows for a
  non-connectivity RPC rejection (N5, not false); two quick refused taps
  queue two identical snackbars (N8).

## Manual device check (after the PR)

- Offline Delete account: a message appears, and the account and the data
  are intact.
- Sign-out during a ChordPro import: a message appears.
- Cancelling the discard dialog: nothing appears.
- The sync popup chips are readable.
