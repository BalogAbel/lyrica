# Plan: Offline Catalog Local-First Visibility

**Spec:** `docs/specs/2026-09-28-offline-catalog-local-first-visibility.md`
**ADR:** `docs/architecture/decisions/ADR-037-local-first-catalog-visibility.md`
**Branch:** `fix/offline-catalog-local-first-visibility`
**Discipline:** TDD — every task starts with a red test. A guard test must be
shown failing against the old code before the fix lands, for every task.
**Verification:** the FULL suite (`./scripts/run-tests.sh` or, from
`apps/lyron_app`, `flutter test`) after every task — never a subdirectory.

## Step 1 — local-first context establishment (closes F-A)

### Task 1.1 — `SongCatalogStore`/identity-based local-first helper in `SongCatalogController`

- Red test: construct `SongCatalogController` with a non-empty cached
  snapshot for `(userId, organizationId)` already in the store and a
  `LastKnownIdentityReader` returning that identity, but an
  `ActiveOrganizationReader`/`CatalogSessionVerifier` that never resolves
  (a `Completer` that is never completed). Call `refreshCatalog()`. Assert
  `state.context` becomes non-null (with `connectionStatus: offlineCached`,
  `hasCachedCatalog: true`) **before** the pending future is ever completed —
  i.e. synchronously reachable after pumping the event loop once, not after
  the hung network call.
- Implementation: extract a private
  `Future<bool> _tryEstablishLocalFirstContext({required String? sessionUserId, required String? identityUserId, required String? identityOrganizationId})`
  helper (name indicative) used both by the new call site (top of
  `_refreshCatalogBody`, before `_resolveOrganizationId()`) and by
  `handleOfflineAuthenticated` (Task 1.5/2.5 will finish the merge — for this
  task it is fine for `handleOfflineAuthenticated` to keep its own body,
  merging is Task 2.5's job so this task stays reviewable).
  Org resolution order inside the helper: `LastKnownIdentity.organizationId`
  when the identity's `userId` matches the caller-supplied `userId`, else
  `store.readLatestCachedOrganizationId(userId:)`. Only sets state when a
  non-empty local snapshot exists.
- Guard: run the red test against `git stash` of this task's diff to confirm
  it fails on `main`'s current code before implementing.
- Full suite green.

### Task 1.2 — HTTP client timeout

- Red test: unit test on `TracingHttpClient` (or a thin wrapper) with a fake
  inner `http.Client` whose `send` never completes; assert `.send()` throws
  `TimeoutException` within the configured bound (use a short test-only
  duration via constructor injection, not the real 15 s, to keep the test
  fast).
- Implementation: `TracingHttpClient` takes a `Duration` (default
  `Duration(seconds: 15)`) and wraps `_inner.send(request)` in `.timeout(...)`.
  Wire the real 15 s constant at the `bootstrap.dart:218-221` call site
  (named constant, spec cites it).
- Add a focused regression test confirming a `TimeoutException` thrown from
  the injected `http.Client` during a gotrue call surfaces to application
  code as `AuthRetryableFetchException` (documents the library behavior the
  spec relies on — a characterization test against the pinned package, not
  a gotrue-internals test).
- Full suite green.

### Task 1.3 — UI empty/loading message gating

- Red test: widget/provider test asserting the empty-state string is not
  shown when `context` is non-null but `refreshStatus` is `refreshing`
  (currently may incorrectly show empty state mid-refresh — verify actual
  current behavior first via the red test, since the spec's claim is about
  the end state, not a specific existing widget bug).
- Implementation: adjust the empty-state widget's gating condition to key
  off `hasCachedCatalog`/`context`, not `refreshStatus` alone.
- Full suite green.

### Task 1.4 — design-gate note only, no code

`OnlineTransitionDetector` cold-start question is answered by tracing in the
spec (Step 1.4) — add a short code comment at
`online_transition_detector.dart:24-32` cross-referencing the spec section,
no behavior change. Roll into Task 1.1's commit.

**Checkpoint: per-task review (sonnet) on Tasks 1.1-1.2, then Opus adverse
whole-diff review with the Step 1 question from the spec/command. Verify
line numbers against the live diff before fixing anything the review flags.**

## Step 2 — invariant on every branch (closes F-B..F-F)

### Task 2.1 — null-session branch stops destroying state

- Red test: `SongCatalogController` with an established `context` (e.g. via
  a prior successful refresh in the test), then simulate the session going
  null (`authSessionReader` now returns null) and call `refreshCatalog()`.
  Assert `state.context` is unchanged (not reset to `initial()`),
  `sessionStatus` becomes `expired`.
- Implementation: replace the unconditional `CatalogSnapshotState.initial()`
  with: try local-first (Task 1.1's helper, identity-only mode since there
  is no live session), else preserve existing state and set
  `sessionStatus: expired` only.
- Full suite green.

### Task 2.2 — status-only conversions (F-C, F-F ×2)

- Red test per site (3 sites): construct a controller with an established
  `context`, then trigger each failure path in turn
  (org-lookup non-connectivity error with context already set is a no-op
  today already — confirm via test whether this site needs a change per the
  spec's F-C note about ordering with Task 1.1 in place; the verifier
  returning `expired`; `listSongs` throwing an `AuthException` that is a
  genuine 401). Assert `context`/`hasCachedCatalog` survive in all three,
  `sessionStatus` reflects the failure.
- Implementation: remove `clearContext: true` / the `initial()` fallback
  from the three sites named in the spec (`song_catalog_controller.dart`
  lines ~213-221, ~397-410, ~540-553 as of this writing — re-locate by
  content, not line number, since Task 1.1/2.1 will have shifted lines).
- Full suite green.

### Task 2.3 — classification order fix (F-E)

- Red test: feed `_isAuthorizationFailure` (or the `listSongs` catch path
  end-to-end) an `AuthRetryableFetchException`; assert it is NOT classified
  as an authorization failure (i.e. `_isConnectivityFailure` wins).
- Implementation: in `_isAuthorizationFailure`, check
  `error is AuthRetryableFetchException` first and return `false`
  immediately, before the `is AuthException` check.
- Full suite green.

### Task 2.4 — `persistNewIdentity` preserves `organizationId` on same-user unknown resolution

- Red test in the `auth_providers.dart` test suite: seed a stored
  `LastKnownIdentity` with a non-null `organizationId` for `userId`, then
  drive a same-user `signedIn` edge whose membership resolution is
  `ActiveOrganizationUnknownConnectivityFailure` (or `null`). Assert the
  identity written afterward still carries the original `organizationId`,
  not `null`.
- Also a red test for the genuinely-new-user case (`priorIdentity == null`)
  confirming `organizationId: null` is still correct there.
- Implementation: the one-line change described in the spec, inside
  `persistNewIdentity`'s unknown-resolution branch.
- Full suite green.

### Task 2.5 — merge `handleOfflineAuthenticated` into the local-first path

- Red test: with `context` null and `sessionExpired`, call
  `refreshCatalog()` directly (not `handleOfflineAuthenticated()`) and
  assert local-first context establishment still happens — proves the path
  is no longer transition-only.
- Implementation: `handleOfflineAuthenticated()` becomes a thin call into
  Task 1.1's helper; `_refreshCatalogBody`'s null-session branch (Task 2.1)
  and signed-in branch (Task 1.1) both already call the same helper.
- Full suite green.

### Task 2.6 — `UnifiedManualSyncController` reauth gating

- Red test: `UnifiedManualSyncController` with an `activeContextReader`
  returning a non-null context (local-first now keeps it populated) and an
  auth-status reader returning `sessionExpired`. Call `syncNow()`. Assert
  none of the four sync steps (`_syncSongMutations`,
  `_refreshSongCatalog`, `_syncPlanningMutations`, `_refreshPlanning`) were
  invoked, and the result reports `requiresReauth: true`.
- Also a widget test: `UnifiedSyncStatusPopup`'s Sync button, under
  `sessionExpired`, navigates to the sign-in route (same pattern as
  `ReauthBanner`) instead of calling `syncNow()` silently. An automatic
  trigger (`OnlineTransitionDetector`/`foregroundSyncListenerProvider`)
  under the same state does NOT navigate anywhere (test both).
- Implementation: add `requiresReauth` to `UnifiedManualSyncRunResult`, wire
  an `AuthStatusReader` into `UnifiedManualSyncController`, short-circuit
  `_runOnce`, wire the popup's button `onPressed` to check `lastResult`
  after `syncNow()` (or a dedicated pre-check) and navigate on
  `requiresReauth`.
- Full suite green.

### Task 2.7 — planning parity assessment (haiku-scoped)

- Investigation only first (caveman:cavecrew-investigator, "Output: caveman
  ultra." as first line): does `PlanningSyncController` have any path
  equivalent to F-B/F-C/F-E/F-F beyond what Step 2.1-2.3's catalog-side
  reasoning already covered? Specifically: does anything in
  `planning_sync_controller.dart` destroy `_state.userId`/`organizationId`
  outside the four invariant causes, given `_refreshPlanning`'s null-session
  guard is already non-destructive?
- If a small, bounded gap is found: red test + fix, same TDD discipline,
  folded into this task.
- If large: write `docs/deferred/2026-09-28-planning-local-first-parity.md`
  with a trigger condition, per `AGENTS.md` documentation duties. Do not
  leave the finding only in chat.
- Full suite green.

### Task 2.8 — offline soak integration test (mandatory, spec Acceptance)

- New test, provider-level, real wiring (not the individual controller unit
  tests above). Location: `apps/lyron_app/test/integration/` alongside
  `offline_edit_relaunch_sync_flow_test.dart`.
- Contents per the spec/command: `fake_async`, fake lifecycle
  inactive/resumed transitions, manual `syncNow()` presses, a network
  double that never resolves (not an immediately-responding fake — the
  existing suites' fakes answer too fast to have caught F-B/F-E), both
  `signedIn` and `sessionExpired` states exercised in sequence within one
  test run.
- Assert: for as long as a non-empty local snapshot exists for the current
  `(userId, organizationId)`, `songLibraryListProvider` never yields `[]`,
  in any of the exercised sequences — except immediately following a D1
  purge, which the test also exercises once as the one legitimate
  empty-after-purge case.
- Full suite green.

**Checkpoint: per-task review (sonnet for controller/auth-provider tasks,
haiku for UI/docs tasks 2.7), then Opus adverse whole-diff review with the
Step 2 question from the spec/command. Verify line numbers against the live
diff before fixing anything the review flags.**

## Docs (same change, per `AGENTS.md`)

- `docs/architecture/architecture.md` — Offline Strategy section: note the
  local-first read-context rule.
- `docs/testing/testing-strategy.md` — Adversarial Offline/Sync Validation
  section: add the soak-test pattern (never-resolving network double,
  lifecycle fake, both auth states in one run) as a named pattern for future
  slices to reuse.
- `docs/architecture/decisions/ADR-037-local-first-catalog-visibility.md` —
  already drafted alongside the spec (this change); finalize wording only if
  the design-gate review changes the decision.
- Status note already added to
  `docs/specs/2026-08-19-local-data-durability-contract.md` D3 (this
  change).

## Review follow-ups R1–R3 (PR #79 review, 2026-09-28)

See `docs/specs/2026-09-28-offline-catalog-local-first-visibility.md`'s
"Review follow-ups R1–R3" section for full background on each. TDD, full
suite after every task, same discipline as Steps 1–2.

### Task R1 — two-tier HTTP timeout (sonnet)

- Red test: a fake native (`dart:io`) socket that never completes the TCP
  handshake — assert the client throws within the 10s connect-timeout
  bound, not the 60s response backstop. A separate test: a
  `/auth/v1/token`-path request whose connection succeeds but whose
  response body never arrives — assert it does NOT throw at 60s (only the
  connect timeout applies to it). A third: a non-token request whose
  connection succeeds but response never arrives — assert it DOES throw at
  the 60s backstop.
- Implementation: `TracingHttpClient` gains a conditional-import platform
  seam for the connect timeout (native: `IOClient` wrapping an
  `HttpClient()..connectionTimeout = Duration(seconds: 10)`; web: current
  `BrowserClient`-based behavior unchanged, no connect-timeout knob
  available). Path-match the outgoing request against `/auth/v1/token` to
  decide whether the 60s response backstop applies.
- Verify via context7 (pinned `http`, `supabase` 2.16.1, `gotrue` 2.27.2,
  `supabase_flutter` 2.17.2) that the injected `httpClient` really does
  flow into `GoTrueClient`'s own HTTP calls (read `supabase_client.dart`'s
  constructor in the pinned source, don't assume) and that both timeout
  shapes still classify as connectivity failures through the existing
  `isConnectivityFailure`/`AuthRetryableFetchException` machinery — no new
  classification code should be needed, this is a characterization check,
  not a new feature.
- Add `docs/deferred/2026-09-28-client-abandoned-committed-write-lf-t5b.md`
  (already drafted alongside the spec update — verify it, adjust only if
  the implementation ends up differing from what's described there).
- STOP and report if a native connect timeout genuinely cannot be
  implemented against the client Supabase actually uses on this pinned
  stack (would mean falling back to a purely response-based bound, which
  the spec's R1 section explicitly says is insufficient for the DNS/no-route
  case).

### Task R2 — planning cross-user guard, identity-wired (sonnet)

- Red test first, on the current code: the existing I3 planning test with
  `lastKnownIdentityReader: () => (userId: 'user-A', organizationId:
  'org-A')` wired in, session switched to user B. Assert no A context, no
  second org-A fetch, no second org-A `replaceActiveProjection` (count both).
  Must fail before the fix (`state.userId == 'user-A'`).
- Fix: `PlanningSyncController._tryEstablishLocalFirstContext` uses
  `SongCatalogController`'s rule (`session?.userId ?? identity.userId`;
  identity org only when `identity.userId == userId`; store fallback for the
  resolved user; `hasProjection` on the resolved user). `sessionExpired`
  behaviour unchanged (the `handleOfflineAuthenticated` tests stay green).
  Do not touch `wipePriorAndProceedFor` / `cancelToPriorUser`.
- Catalog side: an identity-wired variant of the catalog I3 test that pins
  the rule; mutation-check it (swap the helper's user resolution, see it
  fail, restore).
- Full suite green.

Note: an earlier revision of this task concluded "already closed by I3" from
commit history and only strengthened the identity-less fixture. That was
wrong; see the spec's R2 section.

**Checkpoint: per-task review (sonnet) on R1 and R2 -- R1 approved; R2
re-done as above.**

### Task R3 — offline escape hatch from the sign-in screen (haiku)

- Red test (widget test): `SignInScreen` under `AppAuthStatus.sessionExpired`
  with a `from` query param set — the "Continue offline" button is visible
  and tapping it navigates to `from`. Under `sessionExpired` with no `from`
  — navigates to `AppRoutes.home`. Under `AppAuthStatus.signedOut` — the
  button is absent.
- Implementation: add the button + new `AppStrings` entries. No router
  changes needed (`app_router.dart` already permits in-app routes under
  `sessionExpired`, confirmed by reading it — only redirects away from
  `bootstrap`).
- Full suite green.

**Checkpoint: per-task review (haiku) on R3.**

### Final adversarial review (Opus, whole follow-up diff only)

One question: "Can any request whose server-side effect committed be
abandoned client-side by a timeout, and can any path establish, refresh, or
overwrite catalog or planning context/projection for a user other than the
live session user?" Verify line numbers against the live diff before fixing
anything flagged.

### Docs

- ADR-037: record the two-tier timeout decision (connect vs. response, why
  `/auth/v1/token` is exempted) as an amendment.
- Spec's R1–R3 section (already drafted).

## Final steps

1. `./scripts/verify.sh` green.
2. Open PR to `main` (branch `fix/offline-catalog-local-first-visibility`),
   English body, attribution footer.
3. `/gemini review` PR comment after push; reply inline to bot findings and
   resolve threads.
4. Do NOT merge. Report CI green and wait for approval.
