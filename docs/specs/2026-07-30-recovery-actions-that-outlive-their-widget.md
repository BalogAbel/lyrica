# Recovery Actions That Outlive Their Widget

> Status: Implemented
>
> Evidence: branch `feat/offline-durability-phase4`. Full closeout verification
> passed at `6ffa35c` — `./scripts/verify.sh` exit 0 with the local Supabase
> stack, database reset, demo-user provisioning and the skip-gated integration
> suites actually executed (1090 tests passed, 18 skipped, coverage 73.57%),
> all backend write contracts green, `./scripts/check-migrations.sh` exit 0,
> and `flutter build web --release` exit 0.
>
> Implementing D3 surfaced three hazards this document does not name, all
> fixed in the same phase and recorded in ADR-029: identity persistence
> overwrote the prior identity on the same `signedIn` edge, so the
> different-user case would have been undetectable; cancelling via a plain
> `signOut()` would have cleared the identity that cancel exists to preserve
> (`bfdd12f`); and two edges arriving close together could each request a
> confirmation, throwing an uncaught `StateError` out of an unawaited listener
> (`083281c`, `173b196`). D4's pending count was also organization-scoped while
> the wipe is user-wide, so the dialog understated what it would destroy
> (`8303b9c`, `105cb94`).

## Goal

Resolve two deferred items with one root cause — recovery logic bound to a
transient `WidgetRef`, or with no host to run in at all:

- `docs/deferred/2026-05-29-popup-row-recovery-provider-ref.md`
- `docs/deferred/2026-06-28-reauth-different-user-live-wiring.md`

ARCH-5's `ActiveOrganizationResolver` (ADR-022) and the existing
`UnifiedDiscardController` pattern make both cheap now in a way they were not
before.

## Problem

### A — popup recovery actions die with the popup

`_keepMine`, `_discardMine` and `_applyToGroup` in
`unified_sync_status_popup.dart` run async work on the popup's `WidgetRef` and
then perform their side effects behind a `context.mounted` guard:

| method | side effects after the `await` | skipped if the popup closes |
|---|---|---|
| `_keepMine` | invalidate `songMutationEntriesProvider`, `songLibraryListProvider` | yes |
| `_discardMine` | same two | yes |
| `_applyToGroup` | bump `planningDataRevisionProvider`, invalidate `planningMutationEntriesProvider`, `planningPlanListProvider` | yes |

Close the popup mid-operation and the mutation still commits, but the
invalidations never fire — screens keep showing stale sync state until something
else happens to refresh them. The failure snackbar is also lost, which is
correct and unavoidable: a snackbar needs a live `BuildContext`.

The repository already solves this for discard-all. `UnifiedDiscardController`
holds no `Ref`; it takes closures, and `unifiedDiscardControllerProvider` builds
those closures over the *provider's* `ref`, each taking `ref.keepAlive()` at its
start and closing the link in a `finally`. That is the shape to reuse.

Note for the migration: `planningDataRevisionProvider` is the only thing that
reaches the three slug/detail **family** providers, which are never invalidated
directly. The revision bump has to move with the rest, not be dropped.

### B — different-user reauth is fully built and never called

`resolveReauth` (`application/auth/reauth_resolution.dart`) and
`showReauthDifferentUserDialog` (`presentation/auth/reauth_different_user_dialog.dart`)
are implemented and tested. Nothing in `lib/` calls either. They are dead code.

What actually happens today on the `signedIn` transition is three independent
listeners, none of which compares the new user to the prior one:

1. `lastKnownIdentityPersistenceProvider` **unconditionally overwrites** the
   single `LastKnownIdentity` row with the new user — it never reads the old
   value first;
2. the song catalog controller swaps to the new user's context;
3. the active planning context controller refreshes.

So signing in as a different user on a device holding another user's unsynced
work silently switches context and leaves that work stranded and invisible,
with the prior identity already overwritten.

**There is no dialog host.** No `GlobalKey<NavigatorState>` anywhere, no
`builder:` on `MaterialApp.router`, no `ShellRoute` wrapping the authenticated
routes. `ReauthBanner` exists but is wired by hand into a single screen.

## Decisions

### D1 — Move the `ref` half of the popup actions into long-lived controllers

Each of the three methods splits along one clean line: everything except the
failure snackbar is `ref` work. The controllers take over the `ref` half —
mutation call, revision bump, invalidations — under `ref.keepAlive()`, exactly
as `discardSongs`/`discardPlanning` already do. The widget keeps only the
snackbar, and only when it is still mounted.

Consequence, and it is the point: closing the popup mid-operation no longer
skips the invalidations. The user may miss the error toast; they will not be
left looking at stale sync state.

### D2 — A `ReauthPromptController` with a host widget, not a navigator key

The reauth prompt needs somewhere to run. Two options were considered:

- **A `GlobalKey<NavigatorState>` on `MaterialApp.router`.** Less code — any
  caller can `showDialog` from anywhere. Rejected: it introduces global mutable
  navigation state, is harder to isolate in tests, and `currentContext` can be
  null across lifecycle boundaries. That is the same class of bug this slice
  exists to remove.
- **Chosen: a `ReauthPromptController` plus a host widget** mounted in
  `MaterialApp.router`'s `builder:`. The controller lives on a `ProviderRef` and
  publishes a pending prompt as state; the host observes it and shows the
  dialog. The decision logic stays testable without any UI, the host is testable
  as a widget, and no route needs restructuring.

### D3 — All four outcomes, wired to the live `signedIn` edge

The wiring hooks the same `prev != signedIn && next == signedIn` edge that
`membershipRefreshEffectProvider` already listens on, and calls `resolveReauth`
with the prior identity read from `LastKnownIdentityStore`:

| case | outcome |
|---|---|
| same user | flush — proceed normally, nothing destroyed |
| different user, **no** pending mutations | wipe the prior user's data, proceed |
| different user, **with** pending mutations | confirm dialog showing the prior email and the pending count; on confirm, wipe and proceed |
| the user cancels | sign the new session out and stay offline-authenticated as the prior user |

The already-pinned contracts from the existing tests must not be contradicted:
**no wipe may be attempted before the confirmation resolves true**, a barrier
dismissal counts as cancel, and a zero pending count skips the prompt entirely.

**Ordering against the existing listeners matters and is part of this slice.**
`lastKnownIdentityPersistenceProvider` currently overwrites the prior identity
on the same edge. If it runs first, the prior identity is gone before
`resolveReauth` can read it, and the different-user case becomes undetectable.
The resolution must observe the prior identity before anything overwrites it.

### D4 — The pending count is songs **and** plans

The confirm dialog must state everything at stake. The wipe deletes both
subsystems (`SongCatalogStore.deleteCatalogsForUser` and
`PlanningLocalStore.deletePlanningDataForUser`), so a planning-only number would
understate it — worse than useless, because it would be a specific wrong number.

No combined counter exists today. This slice adds a small one: planning
contributes `readPendingMutations(...).length`; songs contribute
`readPendingSongs(...)` plus `readConflictSongs(...)`. It is a counting seam, not
a new subsystem.

### D5 — ADR-020 non-destructive session semantics are not relaxed

Deleting another user's local data on an explicit, confirmed different-user
sign-in is not the destructive-on-uncertainty behaviour ADR-020 forbids. The
distinction stays sharp:

- an unknown or connectivity-failed session remains non-destructive — nothing is
  deleted, and the app stays offline-authenticated as the prior user;
- only explicit sign-out, authoritative revocation, and now an explicitly
  **confirmed** different-user sign-in delete immediately;
- **cancel deletes nothing** and returns to being offline-authenticated as the
  prior user.

If the pending count cannot be read — a storage failure while gathering it — the
slice treats that as uncertainty and takes the confirm path rather than the
silent-wipe path. Never wipe because a count was unavailable.

## Non-Goals

- The Riverpod 3 migration. This slice touches provider lifetime and will invite
  it; it stays out. If the work genuinely cannot land without it, stop and
  surface that rather than expanding this PR.
- Restructuring the router into a shell.
- Any change to what the backend authorizes.
- Broader popup restructuring beyond moving the three methods' `ref` work.

## Testing

1. **Invalidations survive an unmounted popup.** Invoke each controller, dispose
   the widget mid-operation, and assert the invalidations still happened. This
   fails against the current `context.mounted`-guarded code.
2. **The revision bump moves with the rest** — the family slug/detail providers
   still refresh after `_applyToGroup`'s work completes.
3. **Same user → flush**, nothing wiped.
4. **Different user, no pending → wipe prior and proceed**, no dialog shown.
5. **Different user, with pending → confirm dialog** showing the prior email and
   the combined song+plan pending count; on confirm, the prior user's catalog,
   planning data and identity are wiped and the new session proceeds.
6. **Cancel → the new session is signed out and the app stays
   offline-authenticated as the prior user**, with nothing deleted. Both confirm
   and cancel are covered, as the deferred doc requires.
7. **The prior identity is still readable when resolution runs** — a regression
   test against the ordering hazard in D3, failing if identity persistence runs
   first.
8. **A failure to count pending work takes the confirm path**, never the wipe
   path.

## Documentation

- ADR for the reauth host seam and the different-user resolution, including the
  ADR-020 boundary in D5.
- `docs/architecture/architecture.md` — the authenticated shell now hosts a
  reauth prompt; recovery actions run on long-lived controllers.
- `docs/testing/testing-strategy.md` — the new contracts.
- Both deferred docs removed in the commits that resolve them, per
  `docs/deferred/README.md`.
