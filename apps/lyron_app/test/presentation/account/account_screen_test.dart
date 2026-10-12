// ignore_for_file: subtype_of_sealed_class
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_service.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/presentation/account/account_screen.dart';
import 'package:lyron_app/src/presentation/song_library/chordpro_import_controller.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class _StubRepo implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async => null;
  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();
  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {}
  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}

class _RecordingController extends AppAuthController {
  _RecordingController() : super(_StubRepo());
  bool deleted = false;
  bool signedOut = false;

  @override
  Future<void> deleteAccount() async {
    deleted = true;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

// SO8 (docs/specs/2026-10-07-sign-out-pending-work-guard.md): a repository
// whose restored session is user-1 and whose stream the test drives.
class _SwitchableUserRepo extends _StubRepo {
  final sessions = StreamController<AppAuthSession?>.broadcast();

  @override
  Future<AppAuthSession?> restoreSession() async =>
      const AppAuthSession(userId: 'user-1', email: 'one@example.com');

  @override
  Stream<AppAuthSession?> watchSession() => sessions.stream;
}

class _DeleteRecordingController extends AppAuthController {
  _DeleteRecordingController(super.repository);
  int deleteCalls = 0;

  @override
  Future<void> deleteAccount() async {
    deleteCalls += 1;
  }
}

// FB9 (docs/specs/2026-10-12-sync-and-account-feedback.md): the Delete-account
// RPC failed, offline or rejected.
class _FailingDeleteController extends AppAuthController {
  _FailingDeleteController(this.error) : super(_StubRepo());
  final Object error;
  int deleteCalls = 0;

  @override
  Future<void> deleteAccount() async {
    deleteCalls += 1;
    throw error;
  }
}

/// Records what the Account screen reports through `FlutterError.onError` for
/// the rest of the test. Everything else, including the test framework's own
/// report of an unhandled asynchronous error, is forwarded to the original
/// handler, so a regression fails the test instead of being swallowed.
List<FlutterErrorDetails> _recordAccountScreenReports() {
  final reported = <FlutterErrorDetails>[];
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.library == 'AccountScreen') {
      reported.add(details);
    } else {
      original?.call(details);
    }
  };
  addTearDown(() => FlutterError.onError = original);
  return reported;
}

const _deleteAccountFailedText =
    'Could not confirm the account deletion. Nothing was removed from this '
    'device. Check your connection and try again.';

void main() {
  testWidgets('delete confirmation triggers deleteAccount', (tester) async {
    final controller = _RecordingController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAuthControllerProvider.overrideWith((_) => controller)],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );

    await tester.tap(find.text('Delete account'));
    await tester.pump();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(controller.deleted, isTrue);
  });

  testWidgets(
    'delete confirmation deletes nothing when the user switched while the '
    'dialog was open (SO8, B3)',
    (tester) async {
      final repository = _SwitchableUserRepo();
      addTearDown(repository.sessions.close);
      final controller = _DeleteRecordingController(repository);
      await controller.restoreSession();
      expect(controller.state.currentUserId, 'user-1');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appAuthControllerProvider.overrideWith((_) => controller),
          ],
          child: const MaterialApp(home: AccountScreen()),
        ),
      );

      await tester.tap(find.text('Delete account'));
      await tester.pump();

      // A sign-in in another tab replaces the user while the dialog is open.
      repository.sessions.add(
        const AppAuthSession(userId: 'user-2', email: 'two@example.com'),
      );
      await tester.pump();
      expect(controller.state.currentUserId, 'user-2');

      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();

      expect(controller.deleteCalls, 0);
    },
  );

  Future<void> pumpAccountScreen(
    WidgetTester tester,
    AppAuthController controller,
  ) => tester.pumpWidget(
    ProviderScope(
      overrides: [appAuthControllerProvider.overrideWith((_) => controller)],
      child: const MaterialApp(home: AccountScreen()),
    ),
  );

  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.deleteAccountAction));
    await tester.pump();
    await tester.tap(find.text(AppStrings.deleteAccountConfirmAction));
    await tester.pumpAndSettle();
  }

  // DA1 (FB9): an escaped error was an unhandled asynchronous error, which
  // fails this test through the test zone; the screen now catches it.
  testWidgets('a failed Delete account shows the message, leaves no spinner '
      'and the tile works again (DA1)', (tester) async {
    _recordAccountScreenReports();
    final controller = _FailingDeleteController(StateError('rpc rejected'));
    await pumpAccountScreen(tester, controller);

    await confirmDelete(tester);

    expect(controller.deleteCalls, 1);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(_deleteAccountFailedText),
      ),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final tile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, AppStrings.deleteAccountAction),
    );
    expect(tile.onTap, isNotNull);

    // The tile can be used again: a second confirmation reaches the
    // controller.
    await confirmDelete(tester);
    expect(controller.deleteCalls, 2);
  });

  // DA2 (FB9, ADR-036): a defect is reported once with a static context and no
  // user data; an offline user is a condition, not a defect.
  testWidgets('a non-connectivity Delete account failure is reported once '
      'without user data (DA2)', (tester) async {
    final reported = _recordAccountScreenReports();
    final error = StateError('delete failed for owner@example.com');
    await pumpAccountScreen(tester, _FailingDeleteController(error));

    await confirmDelete(tester);

    expect(reported, hasLength(1));
    expect(reported.single.exception, same(error));
    expect(reported.single.library, 'AccountScreen');
    expect(reported.single.informationCollector, isNull);
    expect(
      reported.single.context.toString(),
      isNot(contains('owner@example.com')),
    );
    expect(find.text(_deleteAccountFailedText), findsOneWidget);
  });

  testWidgets('a connectivity Delete account failure is not reported but '
      'still shows the message (DA2)', (tester) async {
    final reported = _recordAccountScreenReports();
    await pumpAccountScreen(
      tester,
      _FailingDeleteController(const SocketException('offline')),
    );

    await confirmDelete(tester);

    expect(reported, isEmpty);
    expect(find.text(_deleteAccountFailedText), findsOneWidget);
  });

  SignOutCommand commandWith({
    required int pendingCount,
    required void Function() onSignOut,
  }) => SignOutCommand(
    currentUserIdReader: () => 'user-1',
    countPendingWork: ({required userId}) async => pendingCount,
    signOut: (_) async {
      onSignOut();
      return true;
    },
    reportError: (_, _) {},
  );

  testWidgets('Sign out asks with the pending count before signing out', (
    tester,
  ) async {
    var signedOut = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => _RecordingController()),
          signOutCommandProvider.overrideWithValue(
            commandWith(pendingCount: 2, onSignOut: () => signedOut = true),
          ),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );

    await tester.tap(find.text(AppStrings.signOutAction));
    await tester.pumpAndSettle();
    expect(
      find.text(AppStrings.unsyncedSignOutPendingMessage(count: 2)),
      findsOneWidget,
    );
    expect(signedOut, isFalse);

    await tester.tap(find.text(AppStrings.unsyncedSignOutConfirmAction));
    await tester.pumpAndSettle();
    expect(signedOut, isTrue);
  });

  // SF8 (SO7, FB7): the Account tile inherits the refusal through the shared
  // flow and now says why.
  testWidgets('Sign out while an import runs shows the message and does not '
      'sign out (SF8)', (tester) async {
    var signedOut = false;
    final importController = _StatefulImportController()
      ..setImportState(const ImportCommitting());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => _RecordingController()),
          chordProImportControllerProvider.overrideWith(
            (_) => importController,
          ),
          signOutCommandProvider.overrideWithValue(
            commandWith(pendingCount: 0, onSignOut: () => signedOut = true),
          ),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );
    // Keep the autoDispose controller (and its seeded state) alive.
    ProviderScope.containerOf(
      tester.element(find.byType(AccountScreen)),
    ).listen(chordProImportControllerProvider, (_, _) {});

    await tester.tap(find.text(AppStrings.signOutAction));
    await tester.pumpAndSettle();

    expect(signedOut, isFalse);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(
          'Sign-out is unavailable while an import is running. '
          'Try again when it finishes.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Cancel in the sign-out warning does not sign out', (
    tester,
  ) async {
    var signedOut = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => _RecordingController()),
          signOutCommandProvider.overrideWithValue(
            commandWith(pendingCount: 1, onSignOut: () => signedOut = true),
          ),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );

    await tester.tap(find.text(AppStrings.signOutAction));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();
    expect(signedOut, isFalse);
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
