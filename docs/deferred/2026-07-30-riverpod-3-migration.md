# Riverpod 3 Migration

**Slice:** security-read-boundary-phase3 (DX-1)
**Files:**
- `apps/lyron_app/pubspec.yaml` (`flutter_riverpod: ^2.6.1`)
- `apps/lyron_app/lib/src/presentation/song_library/song_library_providers.dart:220`
  (`songLibraryReaderProvider`, a `FutureProvider.autoDispose.family`)
- `apps/lyron_app/lib/src/presentation/song_reader/` (the reader error taxonomy)

## Problem

`flutter_riverpod` and `riverpod` are on 2.6.1; 3.3.2 is resolvable and 3.4.2 is
the latest. The bump was attempted in this slice and **reverted**, because the
mechanical part of the migration is not the whole migration.

The mechanical part was completed and is cheap to redo:

1. `flutter_riverpod: ^3.0.0` in `pubspec.yaml` resolves to 3.3.2.
2. Legacy providers move behind a separate import. Thirteen files use
   `StateProvider` (14 uses), `ChangeNotifierProvider` (10),
   `StateNotifierProvider` (2) or `StateNotifier` (2) and each needs
   `import 'package:flutter_riverpod/legacy.dart';`. In four of them the main
   `flutter_riverpod.dart` import then becomes unused and should be removed:
   `application/planning/planning_data_revision.dart`,
   `presentation/song_library/chordpro_import_controller.dart`,
   `presentation/song_library/song_library_browse_controller.dart`,
   `presentation/song_reader/session_scoped_reader_runtime_controller.dart`.
3. `overrideWithProvider` is gone. Twenty-one call sites, **all in tests**, take
   the shape
   `X.overrideWithProvider((arg) => FutureProvider.autoDispose((ref) async => expr))`
   and collapse to `X.overrideWith((ref, arg) async => expr)`. The family
   `overrideWith` takes the created value, not a provider
   (`riverpod-3.3.2/lib/src/core/family.dart:102`).
4. `AsyncValue.valueOrNull` is gone; `value` is now nullable and is its exact
   replacement (`riverpod-3.3.2/lib/src/core/async_value.dart:551`). Six files.
5. `Override` is no longer exported from `flutter_riverpod.dart`; it comes from
   `package:flutter_riverpod/misc.dart`. Two test files.

After all of that, `flutter analyze` is clean and **nine tests fail**.

## Deferred Because

The nine failures are not test-harness noise. They reproduce in isolation, not
only in a full-suite run, and they cluster entirely on the song reader's
error and failure paths:

- `test/integration/song_reader_flow_test.dart` — offline-authenticated reader
  when the session expires
- `test/presentation/song_reader/session_scoped_reader_context_provider_test.dart`
  — unavailable planning data returns an explicit failure result
- `test/presentation/song_reader/song_reader_screen_test.dart` — six cases:
  unavailable song, access denied, retryable backend failure, preserved-title
  tombstone, unresolved remote-delete conflict, unavailable planning context
- `test/router/app_router_test.dart` — scoped reader route resolving from a
  preserved planning slug when the canonical song is missing

At least one is a **production-visible** symptom rather than an assertion
mismatch: the reader's "This song is unavailable." state does not render at all.

The likely root cause is that Riverpod 3 wraps errors thrown inside a provider.
Its `Result` type distinguishes `valueOrProviderException` from
`valueOrRawException` (`riverpod-3.3.2/lib/src/common/result.dart:33-34`), which
is exactly the surface the reader's error taxonomy is built on — the taxonomy
that ARCH-3/UX-1 stabilised in phase 2 (ADR-023, ADR-024). Reconciling it means
auditing production error handling, not adjusting tests.

That is a slice with its own spec, plan and review round. It does not belong as a
tail-end commit in a pull request that also carries SEC-1, SEC-4 and the CI
gates, and `riverpod` is not an auth or security package — this phase
deliberately prioritised `supabase_flutter`, `gotrue` and `app_links` over the
cosmetic majors.

## What Covers It Instead

Nothing. Riverpod stays on 2.6.1 and the app keeps the 2.x error semantics. The
dependency-audit gate added in this slice checks that the lockfile is current
against its declared constraints, so it does **not** flag this — `^2.6.1`
resolves to the newest 2.x, and the gate is deliberately silent about majors
that need a migration.

## Trigger Condition

Take this on when any of these holds:

- the reader error taxonomy is being worked on anyway, so the audit is not
  overhead;
- a Riverpod 2.x security or correctness advisory appears;
- another dependency requires Riverpod 3 to resolve.

Start by reproducing the nine failures with the mechanical steps above, then
treat the error-wrapping change as the design question: decide whether the reader
unwraps `ProviderException` at the boundary or whether its error taxonomy is
restated in Riverpod 3 terms. Record that decision in an ADR — it changes how
every provider failure reaches the UI.
