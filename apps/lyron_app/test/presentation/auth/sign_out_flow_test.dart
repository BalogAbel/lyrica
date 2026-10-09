import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/presentation/auth/sign_out_flow.dart';
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  Future<Future<bool>> open(WidgetTester tester, int? pendingCount) async {
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              result = showUnsyncedSignOutDialog(
                context,
                pendingCount: pendingCount,
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

  // SO7 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): every
  // sign-out control inherits the rule through the flow.
  Future<(SignOutOutcome, int)> signOutWithImportState(
    WidgetTester tester,
    ChordProImportState importState,
  ) async {
    var sequenceRuns = 0;
    final importController = _StatefulImportController()
      ..setImportState(importState);
    late SignOutOutcome outcome;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chordProImportControllerProvider.overrideWith(
            (_) => importController,
          ),
          signOutCommandProvider.overrideWithValue(
            SignOutCommand(
              currentUserIdReader: () => 'user-1',
              countPendingWork: ({required userId}) async => 0,
              signOut: (_) async {
                sequenceRuns += 1;
                return true;
              },
              reportError: (_, _) {},
            ),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () async {
                outcome = await signOutWithPendingWorkGuard(context, ref);
              },
              child: const Text('sign out'),
            ),
          ),
        ),
      ),
    );
    // Keep the autoDispose controller (and its seeded state) alive.
    ProviderScope.containerOf(
      tester.element(find.text('sign out')),
    ).listen(chordProImportControllerProvider, (_, _) {});
    await tester.tap(find.text('sign out'));
    await tester.pumpAndSettle();
    return (outcome, sequenceRuns);
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
    testWidgets('${entry.key} cancels the sign-out before the command', (
      tester,
    ) async {
      final (outcome, sequenceRuns) = await signOutWithImportState(
        tester,
        entry.value,
      );
      expect(outcome, SignOutOutcome.cancelled);
      expect(sequenceRuns, 0);
    });
  }

  final proceeding = <String, ChordProImportState>{
    'ImportIdle': const ImportIdle(),
    'ImportAwaitingDuplicateResolution':
        const ImportAwaitingDuplicateResolution(emptyResult, []),
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
