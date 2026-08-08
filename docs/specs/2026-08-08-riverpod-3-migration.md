# Riverpod 3 Migration

**Slice:** phase5-riverpod-3 (PR-A)
**Supersedes:** `docs/deferred/2026-07-30-riverpod-3-migration.md` (removed by this slice)

## Problem

`flutter_riverpod` is pinned to `^2.6.1`. The bump to 3.x was attempted during
phase 3 and reverted: the mechanical API migration is cheap, but it leaves nine
tests failing on the song reader's error and failure paths, and those nine
assertions encode user-visible behaviour.

The deferred document recorded a hypothesis for the failures — that Riverpod 3
wraps provider errors in a `ProviderException` and so breaks the reader's error
taxonomy. **That hypothesis is wrong.** This spec records the confirmed
mechanisms instead.

## Confirmed Mechanisms

Reproduced on `flutter_riverpod` 3.3.2 with the mechanical migration applied,
each failure run in isolation.

### A. Automatic retry (eight of the nine failures)

Riverpod 3 retries failed providers automatically. The default is up to ten
attempts with exponential backoff from 200ms to 6.4s
(`riverpod-3.4.2/lib/src/core/provider_container.dart`, `defaultRetry`;
`element.dart`, `_performBuild`). While retrying, the element does not settle
into `AsyncError`; it emits `AsyncLoading(error: …, retrying: true)`.

Two consequences, both observed:

- **Error states never render.** `readerAsync.when(error: …)` is not reached, so
  "This song is unavailable." and its siblings never appear. This is the
  production-visible symptom the deferred document flagged.
- **`await provider.future` never completes with the error.** The awaiting
  provider stays loading, its subscription closes, autoDispose runs, and the
  future completes with
  `Bad state: The provider … was disposed during loading state, yet no value
  could be emitted.`

Verified by experiment: disabling retry on `songLibraryReaderProvider`,
`planningPlanDetailProvider` and `sessionScopedReaderContextProvider` turned
eight of the nine failures green with no other change.

### B. `markNeedsBuild` during build (one failure)

`test/integration/song_reader_flow_test.dart` failed with
`setState() or markNeedsBuild() called during build`, raised from
`_UncontrolledProviderScopeState.scheduleRefresh` when a dirty provider was
flushed inside a widget's build phase.

This is an upstream defect, fixed in `flutter_riverpod` 3.4.0 ("Fix
markNeedsBuild exception when flushing a provider inside Widget lifecycle") and
again in 3.4.2 ("Fix a different source of markNeedsBuild error"). Verified: on
3.4.2 the test passes with no application change. An earlier hypothesis — that
the side-effectful `ref.read` calls inside `unifiedSyncOverviewProvider` caused
it — was tested and disproved.

### C. Flutter SDK fallout (surfaced by the version target, not by Riverpod)

`flutter_riverpod` 3.4.1 and later require Dart `>=3.12.0`, which means Flutter
3.44.x. Moving from Flutter 3.38.5 deprecates `ReorderableListView.onReorder` in
favour of `onReorderItem`, which currently produces analyzer errors in
`test/presentation/planning/plan_detail_screen_test.dart` and deprecation
warnings in two library files.

### What is *not* a mechanism

`ProviderException` does not reach any of this code.

- `AsyncValue.error` carries the original error in Riverpod 3, not a wrapper.
- `FutureProvider.future` resolves through `valueOrRawException`
  (`riverpod-3.4.2/lib/src/core/modifiers/future.dart`), so `await
  ref.watch(p.future)` throws the original error.
- `ProviderException` is only thrown by the synchronous read path
  (`Ref.read`/`ProviderContainer.read` via `valueOrProviderException`), and the
  reader taxonomy does not branch on error type there.

The reader's `error is SongNotFoundException` / `error is
SongAccessDeniedException` branches therefore need no change.

Separately: `ADR-023` and `ADR-024` do not pin the reader error taxonomy — they
cover the optimistic reorder overlay and the planning edit draft. No ADR pins it
today.

## Decisions

### Target `flutter_riverpod` 3.4.2, not 3.3.2

3.3.2 requires an application-side workaround for a scheduler defect that
upstream has already fixed. The cost of 3.4.2 is a Flutter SDK bump (3.38.5 →
3.44.9, Dart 3.10.4 → 3.12.2) across CI and local development, plus the
`onReorder` migration in C. That cost is bounded and visible; a hand-rolled
workaround around provider scheduling is neither.

### Disable automatic provider retry, declared on the providers

Automatic retry contradicts an existing, deliberate contract in this codebase:
failures surface immediately, and retry is user-initiated. The clearest evidence
is `test/presentation/song_reader/song_reader_screen_test.dart`, "shows a
retryable backend failure state when loading fails", which asserts that the
failure state renders with a "Try again" affordance, that tapping it reloads,
and that the loader ran exactly twice. Silent background retry removes the
affordance, hides the failure, and changes the attempt count.

The policy is declared on each provider rather than on the container. Riverpod
resolves retry as `origin.retry ?? container.retry ?? defaultRetry`, and
`origin` survives test overrides, so a provider-level declaration gives
production and every test the same semantics with no wiring at the roughly 175
`ProviderScope`/`ProviderContainer` construction sites in `test/`. A guard test
keeps new async providers from silently opting back in.

Recorded in `ADR-032`, together with the rejected alternatives.

## Scope

- `flutter_riverpod` `^2.6.1` → `^3.4.2`; `environment.sdk` `^3.10.4` →
  `^3.12.0`; CI Flutter 3.38.5 → 3.44.9.
- Mechanical Riverpod 3 API migration: `legacy.dart` imports for
  `StateProvider` / `ChangeNotifierProvider` / `StateNotifierProvider` /
  `StateNotifier`; `overrideWithProvider` → family `overrideWith`;
  `AsyncValue.valueOrNull` → nullable `value`; `Override` from `misc.dart`.
- A named no-retry policy applied to every `FutureProvider` and `StreamProvider`
  declaration in `lib/`, plus a guard test that fails when one is missing.
- `ReorderableListView.onReorder` → `onReorderItem`, preserving index semantics.
- `ADR-032`; removal of `docs/deferred/2026-07-30-riverpod-3-migration.md`;
  refreshed `graphify-out/`.

## Non-Goals

ARCH-4 (melos) and SEC-2 ship in a separate pull request. The retry policy is
not made configurable per call site, and no reader error-handling behaviour
changes: every one of the nine assertions must pass with its original meaning.

## Acceptance

- `flutter analyze` reports no issues.
- All nine originally failing tests pass, unmodified in meaning.
- The full suite is green, and CI is green on `verify`,
  `backend_write_contracts`, `migrations`, `flutter build web`, the coverage
  gate and the dependency-audit gate.
- The guard test fails if an async provider is declared without the retry
  policy.
- `ADR-032` records the decision and the rejected alternatives.

## Risks

- **`onReorderItem` index semantics.** `onReorder` receives a `newIndex`
  computed before the dragged item is removed; `onReorderItem` receives one
  adjusted for the removal. A blind rename shifts every downward drag by one.
  The optimistic reorder overlay of ADR-023 sits directly on this. The migration
  must be driven by an assertion on the resulting order, not by the rename.
- **Flutter SDK bump.** It affects every contributor and every CI job, and it is
  the widest part of this change. It is forced by the 3.4.2 target and is
  recorded as such.
