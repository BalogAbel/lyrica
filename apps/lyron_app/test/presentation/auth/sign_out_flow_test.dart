import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/presentation/auth/sign_out_flow.dart';
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

const _testContext = ActiveCatalogContext(
  userId: 'user-1',
  organizationId: 'org-1',
);

void main() {
  Future<Future<bool>> open(
    WidgetTester tester,
    int? pendingCount, {
    VoidCallback? onLostUnanswered,
  }) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showUnsyncedSignOutDialog(
                context,
                pendingCount: pendingCount,
                onLostUnanswered: onLostUnanswered,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('names a known count', (tester) async {
    await open(tester, 3);
    expect(find.text(AppStrings.unsyncedSignOutTitle), findsOneWidget);
    expect(
      find.text(AppStrings.unsyncedSignOutPendingMessage(count: 3)),
      findsOneWidget,
    );
  });

  testWidgets('says an unknown count is unknown', (tester) async {
    await open(tester, null);
    expect(
      find.text(AppStrings.unsyncedSignOutUnknownPendingMessage),
      findsOneWidget,
    );
  });

  testWidgets('confirm answers true', (tester) async {
    final result = await open(tester, 1);
    await tester.tap(find.text(AppStrings.unsyncedSignOutConfirmAction));
    await tester.pumpAndSettle();
    expect(await result, isTrue);
  });

  testWidgets('cancel and a barrier dismiss answer false', (tester) async {
    final cancelled = await open(tester, 1);
    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();
    expect(await cancelled, isFalse);

    final dismissed = await open(tester, 1);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(await dismissed, isFalse);
  });

  // FB16 (docs/specs/2026-10-12-sync-and-account-feedback.md): a navigator torn
  // down under the dialog (the router rebuilds on an auth change) never
  // completes the dialog's future. The dialog answers false itself and says it
  // was lost; a dialog the user answered must never be reported lost.
  group('a dialog lost unanswered (FB16)', () {
    testWidgets('a navigator torn down under it answers false and reports the '
        'loss once', (tester) async {
      var lost = 0;
      final result = await open(tester, 2, onLostUnanswered: () => lost += 1);
      bool? answer;
      unawaited(result.then((value) => answer = value));
      expect(find.text(AppStrings.unsyncedSignOutTitle), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(answer, isFalse);
      expect(lost, 1);
    });

    final answers = <String, (Future<void> Function(WidgetTester), bool)>{
      'Cancel': (
        (tester) => tester.tap(find.text(AppStrings.songCancelAction)),
        false,
      ),
      'Discard and sign out': (
        (tester) =>
            tester.tap(find.text(AppStrings.unsyncedSignOutConfirmAction)),
        true,
      ),
      'a barrier dismiss': (
        (tester) => tester.tapAt(const Offset(5, 5)),
        false,
      ),
    };
    for (final entry in answers.entries) {
      final (answer, expected) = entry.value;

      testWidgets('${entry.key} is never reported lost, settled or torn down '
          'mid-transition', (tester) async {
        var lost = 0;
        final settled = await open(
          tester,
          2,
          onLostUnanswered: () => lost += 1,
        );
        await answer(tester);
        await tester.pumpAndSettle();
        expect(await settled, expected);
        expect(lost, 0);

        // The transition has not finished when the tree goes away: the
        // route's future completed at pop time, before its entries are
        // disposed.
        final midTransition = await open(
          tester,
          2,
          onLostUnanswered: () => lost += 1,
        );
        await answer(tester);
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(await midTransition, expected);
        expect(lost, 0);
      });
    }
  });

  // The flow under a real MaterialApp: its root ScaffoldMessenger belongs to
  // the app and outlives the screen that took the tap (FB7). [replaced]
  // swaps that screen for another one, as the router does.
  Future<List<SignOutOutcome>> pumpFlow(
    WidgetTester tester, {
    required SignOutCommand command,
    ChordProImportState importState = const ImportIdle(),
    ValueNotifier<bool>? replaced,
  }) async {
    final outcomes = <SignOutOutcome>[];
    final importController = _StatefulImportController()
      ..setImportState(importState);
    final replacedNotifier = replaced ?? ValueNotifier<bool>(false);
    if (replaced == null) {
      addTearDown(replacedNotifier.dispose);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chordProImportControllerProvider.overrideWith(
            (_) => importController,
          ),
          signOutCommandProvider.overrideWithValue(command),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: replacedNotifier,
            builder: (_, isReplaced, _) => isReplaced
                ? const Scaffold(
                    key: ValueKey('replacement-screen'),
                    body: Text('replacement'),
                  )
                : Scaffold(
                    key: const ValueKey('sign-out-screen'),
                    body: Consumer(
                      builder: (context, ref, _) => TextButton(
                        onPressed: () async {
                          outcomes.add(
                            await signOutWithPendingWorkGuard(context, ref),
                          );
                        },
                        child: const Text('sign out'),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
    // Keep the autoDispose controller (and its seeded state) alive.
    ProviderScope.containerOf(
      tester.element(find.text('sign out')),
    ).listen(chordProImportControllerProvider, (_, _) {});
    return outcomes;
  }

  SignOutCommand commandWith({
    Future<int> Function()? count,
    Future<bool> Function()? sequence,
    void Function(Object error)? onError,
  }) => SignOutCommand(
    currentUserIdReader: () => 'user-1',
    countPendingWork: ({required userId}) => (count ?? () async => 0)(),
    signOut: (_) => (sequence ?? () async => true)(),
    reportError: (error, _) => onError?.call(error),
  );

  // SO7 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): every
  // sign-out control inherits the rule through the flow.
  Future<(SignOutOutcome, int)> signOutWithImportState(
    WidgetTester tester,
    ChordProImportState importState,
  ) async {
    var sequenceRuns = 0;
    final outcomes = await pumpFlow(
      tester,
      importState: importState,
      command: commandWith(
        sequence: () async {
          sequenceRuns += 1;
          return true;
        },
      ),
    );
    await tester.tap(find.text('sign out'));
    await tester.pumpAndSettle();
    return (outcomes.single, sequenceRuns);
  }

  // The truth table of isImportRunning, seen through the shared sign-out
  // path: a phase that writes or ends on its own refuses; every other state
  // runs the command. Awaiting duplicates writes nothing until the user
  // resolves them in the modal dialog.
  const emptyResult = ImportBatchResult(
    successes: [],
    duplicates: [],
    errors: [],
  );
  final refusing = <String, ChordProImportState>{
    'ImportPicking': const ImportPicking(),
    'ImportAnalysing': const ImportAnalysing(),
    'ImportCommitting': const ImportCommitting(),
  };
  for (final entry in refusing.entries) {
    // SF1: the refusal is its own outcome, so it is not mistaken for the
    // user's Cancel, and it says why.
    testWidgets('${entry.key} refuses the sign-out before the command with a '
        'message', (tester) async {
      final (outcome, sequenceRuns) = await signOutWithImportState(
        tester,
        entry.value,
      );
      expect(outcome, SignOutOutcome.blockedByImport);
      expect(sequenceRuns, 0);
      expect(
        find.text(
          'Sign-out is unavailable while an import is running. '
          'Try again when it finishes.',
        ),
        findsOneWidget,
      );
    });
  }

  final proceeding = <String, ChordProImportState>{
    'ImportIdle': const ImportIdle(),
    'ImportAwaitingDuplicateResolution':
        const ImportAwaitingDuplicateResolution(
          emptyResult,
          [],
          context: _testContext,
        ),
    'ImportDone': const ImportDone(result: emptyResult, skippedCount: 0),
    'ImportFailed': const ImportFailed('failed'),
  };
  for (final entry in proceeding.entries) {
    testWidgets('${entry.key} runs the command', (tester) async {
      final (outcome, sequenceRuns) = await signOutWithImportState(
        tester,
        entry.value,
      );
      expect(outcome, SignOutOutcome.signedOut);
      expect(sequenceRuns, 1);
    });
  }

  group('feedback per outcome (FB7)', () {
    Finder snackBar() => find.byType(SnackBar);

    // SF2: the sequence throws; the command reports it once and the user is
    // told that sign-out did not complete.
    testWidgets('a failing sequence shows the failed message (SF2)', (
      tester,
    ) async {
      final reported = <Object>[];
      final outcomes = await pumpFlow(
        tester,
        command: commandWith(
          sequence: () async => throw StateError('purge failed'),
          onError: reported.add,
        ),
      );
      await tester.tap(find.text('sign out'));
      await tester.pumpAndSettle();

      expect(outcomes, [SignOutOutcome.failed]);
      expect(reported, hasLength(1));
      expect(
        find.descendant(
          of: snackBar(),
          matching: find.text('Sign-out did not complete. Try again.'),
        ),
        findsOneWidget,
      );
    });

    // SF3: the sequence stopped because the signed-in user changed (SO6).
    testWidgets('a superseded sign-out shows the superseded message (SF3)', (
      tester,
    ) async {
      final outcomes = await pumpFlow(
        tester,
        command: commandWith(sequence: () async => false),
      );
      await tester.tap(find.text('sign out'));
      await tester.pumpAndSettle();

      expect(outcomes, [SignOutOutcome.superseded]);
      expect(
        find.descendant(
          of: snackBar(),
          matching: find.text(
            'The signed-in account changed, so this sign-out was stopped.',
          ),
        ),
        findsOneWidget,
      );
    });

    // SF4: the user's own choices, a completed sign-out and a double tap are
    // not failures and say nothing.
    testWidgets('Cancel shows no message (SF4)', (tester) async {
      var sequenceRuns = 0;
      final outcomes = await pumpFlow(
        tester,
        command: commandWith(
          count: () async => 2,
          sequence: () async {
            sequenceRuns += 1;
            return true;
          },
        ),
      );
      await tester.tap(find.text('sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.songCancelAction));
      await tester.pumpAndSettle();

      expect(outcomes, [SignOutOutcome.cancelled]);
      expect(sequenceRuns, 0);
      expect(snackBar(), findsNothing);
    });

    testWidgets('a barrier dismiss shows no message (SF4)', (tester) async {
      final outcomes = await pumpFlow(
        tester,
        command: commandWith(count: () async => 2),
      );
      await tester.tap(find.text('sign out'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(outcomes, [SignOutOutcome.cancelled]);
      expect(snackBar(), findsNothing);
    });

    testWidgets('a completed sign-out shows no message (SF4)', (tester) async {
      final outcomes = await pumpFlow(tester, command: commandWith());
      await tester.tap(find.text('sign out'));
      await tester.pumpAndSettle();

      expect(outcomes, [SignOutOutcome.signedOut]);
      expect(snackBar(), findsNothing);
    });

    testWidgets('a second tap while a run is in flight shows no message '
        '(SF4)', (tester) async {
      final count = Completer<int>();
      final outcomes = await pumpFlow(
        tester,
        command: commandWith(count: () => count.future),
      );
      await tester.tap(find.text('sign out'));
      await tester.pump();
      await tester.tap(find.text('sign out'));
      await tester.pump();
      expect(outcomes, [SignOutOutcome.alreadyRunning]);
      expect(snackBar(), findsNothing);

      count.complete(0);
      await tester.pumpAndSettle();
      expect(outcomes, [
        SignOutOutcome.alreadyRunning,
        SignOutOutcome.signedOut,
      ]);
      expect(snackBar(), findsNothing);
    });

    testWidgets('a context that unmounted before the dialog could open ends '
        'cancelled, silently (SF4)', (tester) async {
      final count = Completer<int>();
      final replaced = ValueNotifier<bool>(false);
      addTearDown(replaced.dispose);
      var sequenceRuns = 0;
      final outcomes = await pumpFlow(
        tester,
        replaced: replaced,
        command: commandWith(
          count: () => count.future,
          sequence: () async {
            sequenceRuns += 1;
            return true;
          },
        ),
      );
      await tester.tap(find.text('sign out'));
      await tester.pump();
      replaced.value = true;
      await tester.pump();
      expect(find.text('sign out'), findsNothing);

      count.complete(3);
      await tester.pumpAndSettle();

      expect(outcomes, [SignOutOutcome.cancelled]);
      expect(sequenceRuns, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(snackBar(), findsNothing);
    });

    // SF5: the messenger is captured before the first await. The screen that
    // took the tap is gone when the sequence fails; the app's messenger
    // shows the message on whatever replaced it.
    testWidgets('the message shows although the screen was replaced while the '
        'sequence ran (SF5)', (tester) async {
      final sequence = Completer<bool>();
      final replaced = ValueNotifier<bool>(false);
      addTearDown(replaced.dispose);
      final reported = <Object>[];
      final outcomes = await pumpFlow(
        tester,
        replaced: replaced,
        command: commandWith(
          sequence: () => sequence.future,
          onError: reported.add,
        ),
      );
      await tester.tap(find.text('sign out'));
      await tester.pump();

      replaced.value = true;
      await tester.pump();
      expect(find.text('sign out'), findsNothing);
      expect(find.text('replacement'), findsOneWidget);

      sequence.completeError(StateError('purge failed'));
      await tester.pumpAndSettle();

      expect(outcomes, [SignOutOutcome.failed]);
      expect(reported, hasLength(1));
      expect(
        find.descendant(
          of: snackBar(),
          matching: find.text('Sign-out did not complete. Try again.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('without a ScaffoldMessenger the outcome is still returned '
        'and nothing throws', (tester) async {
      final outcomes = <SignOutOutcome>[];
      final importController = _StatefulImportController()
        ..setImportState(const ImportCommitting());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chordProImportControllerProvider.overrideWith(
              (_) => importController,
            ),
          ],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Consumer(
              builder: (context, ref, _) => GestureDetector(
                onTap: () async {
                  outcomes.add(await signOutWithPendingWorkGuard(context, ref));
                },
                child: const Text('sign out'),
              ),
            ),
          ),
        ),
      );
      ProviderScope.containerOf(
        tester.element(find.text('sign out')),
      ).listen(chordProImportControllerProvider, (_, _) {});
      await tester.tap(find.text('sign out'));
      await tester.pumpAndSettle();

      expect(outcomes, [SignOutOutcome.blockedByImport]);
    });
  });

  group('signOutFeedbackMessage (FB7)', () {
    test('maps every outcome: a message only for the three that need one', () {
      final expected = <SignOutOutcome, String?>{
        SignOutOutcome.signedOut: null,
        SignOutOutcome.cancelled: null,
        SignOutOutcome.alreadyRunning: null,
        SignOutOutcome.blockedByImport:
            AppStrings.signOutBlockedByImportMessage,
        SignOutOutcome.failed: AppStrings.signOutFailedMessage,
        SignOutOutcome.superseded: AppStrings.signOutSupersededMessage,
      };
      // A new outcome value must be decided here.
      expect(expected.keys.toSet(), SignOutOutcome.values.toSet());
      for (final entry in expected.entries) {
        expect(
          signOutFeedbackMessage(entry.key),
          entry.value,
          reason: '${entry.key}',
        );
      }
    });

    test('the copy is the approved text', () {
      expect(
        AppStrings.signOutBlockedByImportMessage,
        'Sign-out is unavailable while an import is running. '
        'Try again when it finishes.',
      );
      expect(
        AppStrings.signOutFailedMessage,
        'Sign-out did not complete. Try again.',
      );
      expect(
        AppStrings.signOutSupersededMessage,
        'The signed-in account changed, so this sign-out was stopped.',
      );
    });
  });

  test('the count message is singular for one change', () {
    expect(
      AppStrings.unsyncedSignOutPendingMessage(count: 1),
      'You have 1 unsynced change. Signing out will permanently discard it.',
    );
    expect(
      AppStrings.unsyncedSignOutPendingMessage(count: 2),
      'You have 2 unsynced changes. Signing out will permanently discard '
      'them.',
    );
  });
}

class _FakeChordProImportService implements ChordProImportService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An import controller whose state the test sets directly.
class _StatefulImportController extends ChordProImportController {
  _StatefulImportController()
    : super(
        importService: _FakeChordProImportService(),
        contextReader: () => null,
      );

  void setImportState(ChordProImportState next) => state = next;
}
