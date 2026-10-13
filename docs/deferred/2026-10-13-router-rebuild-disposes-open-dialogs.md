# The Router Is Rebuilt on Every Auth State Change and Disposes Open Dialogs

**Found:** 2026-10-13, by the adversarial whole-diff review of S6a.
**Related:** `docs/specs/2026-10-12-sync-and-account-feedback.md` (FB16),
`docs/specs/2026-10-07-sign-out-pending-work-guard.md`,
`docs/deferred/2026-10-09-sign-out-guard-residuals.md` (R9, R18),
`docs/deferred/2026-10-11-session-transition-coordinator.md`.

**Files:**
- `apps/lyron_app/lib/src/router/app_router.dart` (the provider that watches
  `appAuthControllerProvider`)
- `apps/lyron_app/lib/src/presentation/auth/sign_out_flow.dart`
  (`showUnsyncedSignOutDialog`, the FB16 handling)

**Status:** pre-existing. S6a only made the sign-out confirmation survive it
(FB16); the router behavior is unchanged.

## Problem

`appRouterProvider` uses `ref.watch(appAuthControllerProvider)`. The
controller is a `ChangeNotifier`, and the legacy provider re-notifies its
dependents on every `notifyListeners`, so every auth state change builds a
new `GoRouter` with a new navigator key. The old navigator is disposed with
every route and dialog on it, and a disposed dialog route never completes the
future `showDialog` returned.

Effects:

- Any code that awaits a dialog across an auth change waits forever. S6a
  closed the one that held the sign-out lock (FB16). Other awaits of dialogs
  (the ChordPro duplicate dialog, the reauth prompt host, the delete-account
  confirmation) hang the same way. Not verified harmless: the reauth prompt
  host's awaiting callers hold outer locks (`SongCatalogController`'s refresh
  future, the identity-persistence chain; see `reauth_prompt_host.dart`), its
  `_dialogOpen` flag would stay set, and a later `_closeOpenDialog()` pops
  whatever is on top, possibly a sign-out dialog (which then ends as a silent
  `cancelled`). The slice that fixes the router re-verifies each of them.
- R9 and R18 of the sign-out residuals assume a modal dialog survives a user
  switch. Under this behavior the dialog is disposed unanswered instead.
- The navigation stack is reset on every auth change, which may be intended
  or accidental; nothing in the repository records a decision.

## Known limit of the FB16 handling

A dialog that is popped with an answer and torn down in the same synchronous
turn (no microtask between the pop and the disposal) is reported lost, and the
user would see "Sign-out did not complete". No reachable path was found: taps
and the back button are platform events, and the reauth host's pop comes from
asynchronous flows. Hardening, if one is found: defer the check in the
watcher's `dispose` by one microtask.

## Fix sketch

Read the controller in the router provider (`ref.read`) and rely on its
existing `refreshListenable` to re-run the redirect, so the navigator is not
rebuilt. That changes navigation for every auth transition, so it needs its
own slice with router-level tests, and a check that one user's screens never
stay on the stack under another user.

## Requirements for the slice that picks this up

- Red tests with the real router: user switch, null session to
  `sessionExpired`, sign-out, with a dialog open each time.
- Re-evaluate R9 and R18 and the dialogs listed above once the navigator
  survives.
- Remove the FB16 lost-dialog handling only if the dialog can no longer be
  disposed unanswered.

## Trigger

A change to `app_router.dart`, the session-transition coordinator work, or a
field report of a dialog vanishing or a control going dead after a sign-in
elsewhere.

Roadmap (2026-10-13): S3 does not trigger it (its reader actions await no
dialog). The open reauth-host risk is listed among the roadmap's "Open design
points for S4".
