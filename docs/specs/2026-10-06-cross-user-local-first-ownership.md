# Cross-User Local-First Ownership

> Status: spec and plan awaiting approval (design gate); no production code yet

**Branch:** `fix/cross-user-local-first-leaks`
**Roadmap:** the cross-user fix PR between S0 PR 1 (merged as #85) and S0
PR 2 in `docs/plans/2026-10-01-delivery-roadmap.md`
**Resolves:** F6 and F7 of `docs/deferred/2026-10-05-gate-cross-user-leaks.md`,
plus three paths of the same class found while reproducing them (R-A, R-B,
F8 below). C4, F5, N1 and N2 stay deferred.
**Builds on:** ADR-020, ADR-029, ADR-035 (unchanged), ADR-037 (amended here),
ADR-040
**Plan:** `docs/plans/2026-10-06-cross-user-local-first-ownership.md`
**Reproduction suite:**
`apps/lyron_app/test/integration/cross_user_local_first_leak_test.dart`

## Problem

A local-first read context (the song catalog `context`, the active planning
context, the planning sync state's `(userId, organizationId)`) can belong to
a user who is not the user the app is acting for. Then that user sees, and in
one case loses, another user's songs or plans.

Every finding below is reproduced by a test in the reproduction suite. It
uses a real `AppAuthController`, a real `LocalDataLifecycle`, Drift in-memory
stores and the real different-user reauth providers
(`lastKnownIdentityPersistenceProvider`, `reauthPromptControllerProvider`,
`pendingLocalWorkCounterProvider`, `membershipRefreshEffectProvider`). Only
the network edges are replaced: the auth session stream, the membership RPC,
the organization lookup and the remote fetches. Two tests pause the real
Drift read for user A to pin an interleaving. The deferred entry's line
references were re-checked against the tree after #85. They still hold, except
that the deferred F7 step 2 ("the active planning context controller stays
null") is true only when A has no cached songs (see F7).

Common setup: A's identity (organization `org-a`) is on the device, A has a
pending planning mutation (so a different-user sign-in asks before wiping,
ADR-029 D3), the app cold-starts offline into `sessionExpired(A)`, and B then
signs in. B's membership RPC answers (`selected(org-b)`), so the gate opens
for B.

### F6 — establishment from another user's identity (reproduced)

B signs in; B's catalog and planning organization lookups fail
(connectivity); B's session is then lost without a sign-out. The different-user
prompt is superseded, the identity is still A's, and the state is
`sessionExpired(B)` (`AppAuthController._stateForSession` takes
`lastKnownSession` from `_state.session`). The catalog's
`handleOfflineAuthenticated` and the planning's `handleOfflineAuthenticated`
both read the identity through an unfiltered `lastKnownIdentityReader`
(`song_catalog_providers.dart:106-113`, `planning_providers.dart:338-345`).
With no live session they establish the identity's user: A.

Observed: state `sessionExpired(B)`, gate `home`, song list
`[A secret song]`, plan list `[A secret plan]`. The deferred entry described
only the catalog half; the planning half has the same cause.

### F7 — planning state held for A survives B's sign-in (reproduced)

The cold start into `sessionExpired(A)` establishes the planning sync state
`(A, org-a, hasLocalPlanningData: true)`. B signs in and B's planning lookup
fails. The planning sync listener ignores `signedIn`
(`planning_providers.dart:367-368`), and the I3 guard in `_refreshPlanning`
never runs because `_readPlanningOrThrow` skips the refresh when
`hasLocalPlanningData` is true.

Observed: state `signedIn(B)`, gate `home`, plan list `[A secret plan]`,
prompt still pending.

This needs A to have no cached songs for the identity's organization (an
organization with plans but no songs, or an evicted catalog). When A's songs
are cached, the catalog's I3 reset at B's refresh clears the catalog context,
`syncToCatalogContext(null)` clears the active planning context and
`handleActiveContextChanged(null)` resets planning. That case is green today
and stays as a regression test.

### R-A — the active planning context held for A survives B's sign-in (reproduced)

`ActivePlanningContextController.refresh` keeps an existing context on a
connectivity failure (`active_planning_context_controller.dart:74-76`) and
`sessionExpired` does nothing to it. Sequence: cold start `sessionExpired(A)`,
A re-authenticates offline (the lookup fails and falls back to A's cached
planning organization), A's session is lost, B signs in offline.

Observed: `activePlanningContextProvider` is `(A, org-a)` under `signedIn(B)`;
`planningMutationEntriesProvider` lists A's pending mutation; the plan list
shows A's plan. `PlanningWriteService` accepts a write whose context matches
the active planning context, so B's edits could be queued under A's context.

### R-B — an establishment started for A lands after B's sign-in (reproduced)

A `signedIn` edge does not advance the catalog refresh generation or the
planning boundary generation. A local-first establishment started for A (two
Drift reads) that is still in flight when B's session arrives commits A's
context under `signedIn(B)`. Reproduced for the catalog (song list
`[A secret song]` under `signedIn(B)`) and for planning, by pausing the A
read until after B's edge. The real window is two local reads long; the
realistic trigger is a foreground resume (the OAuth redirect returning) that
starts a refresh just as B's session arrives.

### F8 — B's planning boundary deletes A's plans and pending work (reproduced, data loss)

Same as F7, but B's planning lookup answers `org-b`. The active planning
context becomes `(B, org-b)`, and `PlanningSyncController.handleActiveContextChanged`
treats it as a boundary switch from `(A, org-a)`: it calls
`deletePlanningData(A, org-a)`, which deletes A's projection **and A's pending
mutations** (`planning_local_store.dart:603-630`), while the different-user
prompt is still pending.

Observed: prompt pending, identity still A, A's pending mutations 1 → 0, A's
plan rows 0. ADR-029 D5 says only a confirmed different-user wipe may delete
A's local data, and cancel deletes nothing. This is not a visibility leak and
not a `LocalDataLifecycle` purge (no `PurgeReason`), but it is a cross-user
effect with the same cause as F7: the previous user's boundary is still held
when the next user's boundary arrives.

### Why the existing tests did not see these

The I3 and R2 regression tests (PR #79) drive one controller at a time with a
live session for B. None of them goes through `sessionExpired(B)` with A's
identity, through the planning sync listener's `signedIn` no-op, or through
two holders that disagree (catalog empty, planning not).

## Invariant

> A local-first read context may belong only to the user the app is acting
> for: `AppAuthState.currentUserId`, which is the live session's user when
> signed in and the last known session's user when `sessionExpired`. It is
> never established from another user's identity, a context held for an
> earlier user is released when the current user changes, and no holder
> adopts a context owned by anyone else.

This narrows ADR-037's ownership rule. That rule said "`identity.userId`
alone when `sessionExpired` (no live session to compare against)". There
always is something to compare against: `lastKnownSession.userId`. It also
generalises ADR-037's invariant cause 4 ("a different-user sign-in") to any
change of the current user: a sign-in, a direct session switch, and a
cancelled reauth that returns to the prior user.

## Constraints (from the task, all kept)

- The fix starts no purge and adds no `PurgeReason`. ADR-035 does not change.
- Only in-memory state and the establishment of contexts change. Nothing
  writes to or deletes from a local store. The only store-level effect is
  that F8's existing delete no longer happens.
- The existing I3 guards (`SongCatalogController._refreshCatalogBody`,
  `PlanningSyncController._refreshPlanning`) and the R2 ownership rule in both
  `_tryEstablishLocalFirstContext` methods stay as they are.

## Decisions

### XU1 — one identity getter for every local-first reader (closes F6)

`AppAuthController` gains `currentUserLastKnownIdentity`: the last known
identity when `identity.userId == state.currentUserId`, else null (no current
user, no identity, or another user's identity). All three readers of the
identity use it and nothing else:

- the catalog `lastKnownIdentityReader` (`song_catalog_providers.dart`),
- the planning `lastKnownIdentityReader` (`planning_providers.dart`),
- the membership gate's `knownOrganizationIdReader` (`auth_providers.dart`),
  which already applied this rule inline. It now uses the getter; its
  behaviour does not change.

The effect on the controllers: with a live session they already ignored a
different user's identity (R2), so nothing changes there. With no live
session the identity is now visible only when it belongs to
`lastKnownSession`'s user. In `sessionExpired(B)` with A's identity, nothing
is established. B sees the empty catalog state with the re-auth banner, which
is not a dead end (the banner opens sign-in, as in every `sessionExpired`
state).

A non-matching identity yields null rather than `(B, organization: null)`.
That keeps one rule for the three readers, and it keeps the
"identity cleared by a D5 purge while `sessionExpired`" case exactly as it is
(nothing established). That case is what PR #73's review protected
(`conflicting-review-fix-vs-existing-invariant`). The cost: in
`sessionExpired(B)` with A's identity, B's own cached data (if any) is not
established either. B has an identity of their own only after
`persistIdentity` completes, so B's own cache in that state is rare. B gets
it back by signing in.

The observability user context (`observabilityUserContextEffectProvider`)
also reads `lastKnownIdentity`. That leak is in telemetry, not the UI, and
is already scheduled in S6. It is not changed here, though S6 can reuse this
getter.

### XU2 — every context holder follows the current user (closes F7, R-A, R-B, F8)

A small value class, `CurrentUserOwnership`
(`application/auth/current_user_ownership.dart`), holds the rule once:

- `observe(userId)` records the current user and reports whether it replaced
  a *different, previously observed* user. The first observation is not a
  change: the holder is new and has started nothing for an earlier user, and
  treating it as a change would invalidate work the planning provider starts
  for the active context while it is being built.
- `allows(ownerUserId)` says whether a context owned by that user may be held
  or adopted. Before the first observation it allows everything (the holders'
  existing guards apply).

Each of the three in-memory holders owns one `CurrentUserOwnership` and a
`handleCurrentUser(String currentUserId)` method. The provider that owns the
holder calls it first in its existing auth switch, for every notification
whose `currentUserId` is non-null (`signedIn` and `sessionExpired`):

| Holder | On a change of the current user | Context of another user held | Adoption guard |
|---|---|---|---|
| `SongCatalogController` | `_invalidateRefreshWork()` (refresh generation) | reset to `CatalogSnapshotState.initial()` | none needed: every establishment and refresh commit is generation-checked |
| `PlanningSyncController` | advance the boundary generation and invalidate the refresh generation | reset to `initial()` with `accessStatus: signedIn` (the I3 shape) | `handleActiveContextChanged` ignores a context owned by another user (a mirror notification queued before the change) |
| `ActivePlanningContextController` | (no generation) | reset to null | `refresh()` applies no outcome after its awaits once the user changed; `syncToCatalogContext` ignores another user's catalog context |

Why on the auth edge and not only inside a refresh: the I3 guards run only
when a refresh runs. Planning skips the refresh when it has local data (F7).
The catalog's refresh can be queued behind the previous user's in-flight
refresh, which may be awaiting a network call for up to 60 s.

F8 closes as a consequence. The planning state is released on B's sign-in
edge, so when B's boundary arrives `handleActiveContextChanged` has no
previous boundary and deletes nothing. The only path that deletes A's
planning data is still the confirmed wipe (ADR-029 D5). `deletePlanningData`
on a boundary switch is not changed: a same-user organization switch still
drops the previous organization's planning data, as
`docs/architecture/architecture.md` documents.

`signedOut` is not fed to `handleCurrentUser`. The existing explicit sign-out
handlers reset all three holders and choose the purge target. That code is
unchanged.

### XU3 — single source, per-holder application

The rule has one source: `AppAuthState.currentUserId`. It is encoded in two
places that cannot drift apart, because both compare against that one value:
`AppAuthController.currentUserLastKnownIdentity` decides which identity is
visible (XU1), and `CurrentUserOwnership` decides which held context is
allowed (XU2). Each holder applies it from its own provider's existing auth
switch.

Rejected: one effect provider that calls all three holders. It would add a
fourth listener on the auth controller with no ordering guarantee against the
holders' own listeners, so a status handler could act on a foreign context
before the release ran. Reading the `autoDispose` catalog controller from an
effect would also create and dispose it outside its real lifetime.

### XU4 — rejected alternatives

- **Build `sessionExpired` from the identity in `_stateForSession` (the
  deferred entry's first sketch).** If B's session is lost while A's identity
  is on file, the app would become `sessionExpired(A)` and show A's data to
  the person who has just signed in as B. That is the same exposure under
  another label. It also changes the auth state machine (ADR-020 D2), which
  the gate, the router and the reauth flow depend on.
- **Filter at the presentation readers** (`activeCatalogContextProvider`,
  `planningSyncStateProvider`, ...). The controllers would still refresh,
  sync, write, and choose a sign-out purge target with a foreign context.
  It would also need a filter at every read site instead of at the holders.
- **Reset only in the planning `signedIn` listener (the deferred entry's F7
  sketch).** Closes F7 alone; R-A, R-B and F8 stay open.

## Consequences

- No purge, no `PurgeReason`, no store write or delete is added. F8's delete
  of A's planning data no longer happens before confirmation.
- Explicit sign-out code is unchanged. Before this fix, a foreign context held
  at an explicit sign-out made the sign-out purge pick the foreign user
  (`handleExplicitSignOut` takes `_state.context?.userId` /
  `_state.userId` first). For example, B signing out in the F7 state purged
  A's planning data and pending work. After XU2 a foreign context is never
  held at a sign-out, so the purge target falls through to the signing-out
  user (or to nobody), as ADR-035 intends. This narrows an existing purge's
  target; it does not add one.
- `sessionExpired(B)` with A's identity shows B an empty catalog and the
  re-auth banner instead of A's data.
- A refresh started for the previous user stops when the current user
  changes. The next user's refresh may still queue behind it (existing
  coalescing), but nothing of the previous user is shown meanwhile.

## Out of scope (pre-existing, unchanged)

- B's explicit sign-out while A's different-user prompt is pending clears A's
  identity (`persistIdentity`'s `signedOut` case clears whatever identity is
  on file). A's data stays on disk and reappears for A on A's next sign-in.
  Not a cross-user view.
- `_verifiedEmptyMembershipSeen` in the catalog and active planning
  controllers is not reset on a direct user switch. Its effect is on the
  connectivity fallback for the next user's own data only.
- The org-id telemetry leak (S6).
- C4, F5, N1 and N2 of the deferred entry.

## Acceptance criteria

Each criterion is a test in the reproduction suite. It is red before its task
and green after.

- **AC1 (F6, catalog):** B loses the session while A's identity is on file;
  no catalog context of A's is established; the song list does not contain
  A's song.
- **AC2 (F6, planning):** the same sequence establishes no planning state of
  A's; the plan list does not contain A's plan.
- **AC3 (F7):** planning established for A from a `sessionExpired` cold start
  is not A's after B's sign-in with a failing lookup; the plan list does not
  contain A's plan.
- **AC4 (F8):** with B's lookup answering and A's prompt pending, A's pending
  planning mutation and A's projection still exist, and the planning state is
  B's.
- **AC5 (R-A):** the active planning context held for A is not A's after B's
  sign-in; the mutation entries do not contain A's mutation.
- **AC6 (R-B):** a catalog and a planning establishment started for A and
  completed after B's sign-in leave no context of A's.
- **AC7 (unchanged access):** cancelling B's reauth returns A's songs and
  plans; A re-authenticating keeps them; with songs and plans cached nothing
  of A's survives B's sign-in. These are green today and stay green.
- **AC8:** `flutter test` (full suite) and `flutter analyze` are green after
  every task; no existing test changes unless the plan names it as an
  intentional behaviour change of this spec.

## Documentation updates (in the implementation PR)

- ADR-037: amendment "current-user ownership" (the narrowed ownership rule,
  cause 4 generalised, XU1–XU2, in memory only).
- ADR-040: the residual-cases consequence no longer lists F6/F7 as open.
- ADR-029: an amendment line for F8 (D5's "cancel deletes nothing" held for
  the confirmed wipe but not for the planning boundary switch).
- `docs/architecture/architecture.md`: the offline-authenticated paragraph
  states the ownership rule.
- `docs/testing/testing-strategy.md`: the cross-user ownership suite.
- `docs/deferred/2026-10-05-gate-cross-user-leaks.md`: F6 and F7 removed;
  C4, F5, N1, N2 kept.
- Roadmap: S0 PR 1 merged (#85); this PR before S0 PR 2 (updated with
  this spec, at the design gate).
- No ADR-035 change. No new ADR: this narrows ADR-037's existing invariant
  and does not add a new decision area.
