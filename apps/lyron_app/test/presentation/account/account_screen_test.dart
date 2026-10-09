// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/presentation/account/account_screen.dart';
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
