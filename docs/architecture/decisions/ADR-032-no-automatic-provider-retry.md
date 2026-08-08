# ADR-032: Provider Failures Are Terminal; Retry Is a User Action

- Status: Accepted
- Date: 2026-08-08
- Spec: `docs/specs/2026-08-08-riverpod-3-migration.md`
- Relates to: ADR-003 (Riverpod as the state-management choice),
  ADR-021 (provider domain split), ADR-026 (RLS-protected read boundary)
- Scope: every `FutureProvider`/`StreamProvider` declaration in
  `apps/lyron_app/lib/`, and the song reader's failure surfaces. Synchronous
  providers are deliberately outside it — see Known Limit.

## Context

Riverpod 3 introduces automatic retry and enables it by default: a provider
whose computation throws is retried up to ten times with exponential backoff
from 200ms to 6.4 seconds. While a retry is pending the element does not settle
into `AsyncError` — it emits `AsyncLoading(error: …, retrying: true)`.

That single change breaks the reader's failure behaviour in two ways, both
observed while migrating from 2.6.1:

- **Failure states never render.** `AsyncValue.when(error: …)` is never reached,
  so "This song is unavailable.", the access-denied surface, the retryable
  backend-failure surface and the scoped-context surfaces do not appear at all.
  The user sees an indefinite spinner where the application has a specific
  answer.
- **`await provider.future` never completes with the error.** The awaiting
  provider stays loading; once its subscription closes, autoDispose collects the
  still-loading element and the future completes with
  `Bad state: The provider … was disposed during loading state, yet no value
  could be emitted` — a different failure, at a different time, with no relation
  to the original cause.

Eight of the nine tests that failed on the 3.x bump fail for this reason alone.

The application already has an explicit, tested contract here.
`test/presentation/song_reader/song_reader_screen_test.dart`, "shows a
retryable backend failure state when loading fails", asserts that the failure
surfaces immediately with a "Try again" affordance, that tapping it reloads, and
that the loader ran exactly twice. It also asserts the opposite for terminal
failures: a missing song and a denied song render *without* a "Try again"
affordance. The taxonomy distinguishes what the user can retry from what they
cannot, and it does so at the moment of failure.

Automatic retry removes the affordance, hides the failure behind a spinner for
up to thirteen seconds, and changes the attempt count — including for failures
that are deterministic and will never succeed on a second attempt.

## Decision

**Provider failures are terminal. Nothing retries them automatically.**

`noAutomaticProviderRetry` (`lib/src/application/provider_retry_policy.dart`)
returns `null` for every attempt, and is declared on every `FutureProvider` and
`StreamProvider` in `lib/`.

**The policy is declared on the providers, not on the container.** Riverpod
resolves the effective policy as
`origin.retry ?? container.retry ?? ProviderContainer.defaultRetry`, and
`origin` is the original provider, surviving test overrides. One declaration
per provider therefore gives production and every test the same semantics,
without threading a `retry:` argument through the roughly 175
`ProviderScope`/`ProviderContainer` constructions in `test/` — where a single
omission would silently give that test different failure behaviour from the
application.

`test/application/provider_retry_policy_test.dart` parses every library in
`lib/` and fails when a provider-creating call omits the policy, so a provider
added later cannot quietly opt back in. It parses rather than pattern-matches:
a regex over source cannot distinguish a declaration from the same words inside
a comment or a string, and string interpolation is enough to desynchronise
bracket counting so that one declaration appears to carry its neighbour's
arguments.

## Known Limit

`triggerRetry` sits on the shared build path (`element.dart`), so Riverpod
retries a synchronous provider that throws during build as well. This policy
does not cover those, and the guard test does not look for them.

That is deliberate and currently harmless: no synchronous provider in `lib/`
throws from its build, and for the synchronous case the error surfaces
immediately regardless — `SyncProviderElement` maps the retrying-loading state
to an error result, so nothing is hidden from the UI. What a retry would cost
there is re-running the build body, and with it any side effect that body
performs, up to ten times.

Revisit if a synchronous provider is ever given a build body that can throw, or
one whose re-execution is not free.

## Target Version

`flutter_riverpod` 3.4.2, not the 3.3.2 that the constraint bump first resolved
to. The ninth failing test (`test/integration/song_reader_flow_test.dart`) is an
upstream defect — `setState() or markNeedsBuild() called during build`, raised
from `_UncontrolledProviderScopeState.scheduleRefresh` when a dirty provider is
flushed inside a widget's build phase. 3.4.0 fixes it ("Fix markNeedsBuild
exception when flushing a provider inside Widget lifecycle") and 3.4.2 fixes a
second source of the same error. On 3.4.2 the test passes with no application
change.

3.4.1 and later require Dart `>=3.12.0`, so this pulls the Flutter SDK from
3.38.5 to 3.44.9 for CI and local development. That cost is bounded and visible;
a hand-rolled workaround around provider scheduling would have been neither.

## Rejected Alternatives

**A container-level policy.** Conceptually the right level for an application-
wide rule, and it would read better in one place. Rejected because it has to be
repeated at every root `ProviderScope`/`ProviderContainer`, and the failure mode
of forgetting one is a test that passes while exercising semantics the
application does not have.

**Selective retry — retry transient errors, not domain failures.** Attractive
in the abstract. Rejected because the retryable-failure contract above is
expressed with a plain `Exception`, indistinguishable at the retry boundary from
a transient network error, and that case must *not* retry automatically either:
the test asserts the user's tap is what causes the second attempt. Once the
generic case is excluded there is nothing left for the policy to retry, and what
remains is a rule that looks configurable but never fires.

**Restating the reader error taxonomy in Riverpod 3 terms.** This was the option
the deferred document that this slice removes anticipated
(`docs/specs/2026-08-08-riverpod-3-migration.md` records what it said), on the
hypothesis that Riverpod 3's `ProviderException` wrapping had broken the
taxonomy's `error is SongNotFoundException` branches. Reproducing the failures
disproved it. In Riverpod 3, `AsyncValue.error` carries the original error, and
`FutureProvider.future` resolves through `valueOrRawException`, so `await
ref.watch(p.future)` throws the original error too. `ProviderException` is
thrown only on the synchronous read path
(`Ref.read`/`ProviderContainer.read`, via `valueOrProviderException`), which
this taxonomy does not use. No taxonomy code changed in this migration, and none
needed to.

## Consequences

- A provider that fails because of a genuinely transient condition now stays
  failed until something asks again. That is the existing behaviour, retained
  deliberately: recovery is driven by the user's "Try again", by the sync
  controllers, and by the catalog recovery timer (ADR-031), all of which are
  visible and bounded, rather than by an invisible backoff loop.
- Adding an async provider now requires one extra named argument. The guard test
  makes the omission a failure rather than a silent behaviour change.
- This is the first ADR to pin the reader's error taxonomy as a contract.
  ADR-023 and ADR-024 cover the optimistic reorder overlay and the planning edit
  draft; neither concerns error typing, despite being cited for it in the
  deferred document.

## Non-Goals

- The retry policy is not made configurable per call site or per provider. There
  is one policy, and it is "no".
- No reader error-handling behaviour changes. Every one of the nine previously
  failing assertions passes with its original meaning.
