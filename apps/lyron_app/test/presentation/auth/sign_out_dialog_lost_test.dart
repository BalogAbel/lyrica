import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/auth/active_membership_controller.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/sign_out_command.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/account/account_screen.dart';
import 'package:lyron_app/src/router/app_router.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

import '../../support/drift_test_setup.dart';

// SF9 / FB16 (docs/specs/2026-10-12-sync-and-account-feedback.md), under the
// REAL router. `appRouterProvider` watches the auth controller, so every auth
// state change builds a new GoRouter and tears down the navigator with every
// open dialog. A torn-down dialog route never completes its future: before
// FB16 the sign-out command waited on it forever with its lock held, and every
// later Sign out was `alreadyRunning`, which is silent.

const _signedInSession = AppAuthSession(
  userId: 'user-1',
  email: 'one@example.com',
);
const _otherSession = AppAuthSession(
  userId: 'user-2',
  email: 'two@example.com',
);

class _Repository implements AuthRepository {
  final sessions = StreamController<AppAuthSession?>.broadcast();

  @override
  Future<AppAuthSession?> restoreSession() async => _signedInSession;

  @override
  Stream<AppAuthSession?> watchSession() => sessions.stream;

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

// A null session keeps the user on file as `sessionExpired(user-1)` only when
// an identity is stored (ADR-035 D2); without one it is `signedOut`.
class _IdentityStore implements LastKnownIdentityStore {
  @override
  Future<LastKnownIdentity?> read() async => const LastKnownIdentity(
    userId: 'user-1',
    email: 'one@example.com',
    organizationId: 'org-1',
  );

  @override
  Future<void> write(LastKnownIdentity identity) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<EmptyMembershipResolutionOutcome> resolveEmptyMembership({
    required String userId,
  }) async => const EmptyMembershipResolutionIgnored();

  @override
  Future<bool> clearMembershipRevocation({required String userId}) async =>
      false;

  @override
  Future<bool> hasCurrentMembershipRevocationMarker({
    required String userId,
    required DateTime markedAt,
  }) async => false;
}

class _App {
  _App(this.tester, this.repository, this.controller, this.events);

  final WidgetTester tester;
  final _Repository repository;
  final AppAuthController controller;

  /// `sequence` once per sign-out sequence that ran, `report:<error>` for a
  /// reported error.
  final List<String> events;

  /// The router the app currently shows. It is a new object after every auth
  /// state change.
  GoRouter get router => ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  ).read(appRouterProvider);

  // The auth change builds the new router in the first frame; the sign-out
  // flow's snackbar is queued after it and mounts a frame or two later.
  Future<void> settle() async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> openAccount() async {
    unawaited(router.push(AppRoutes.account.path));
    await settle();
    expect(find.byType(AccountScreen), findsOneWidget);
  }

  Future<void> tapSignOut() async {
    await tester.tap(find.text(AppStrings.signOutAction));
    await settle();
  }

  Finder get confirmDialog =>
      find.text(AppStrings.unsyncedSignOutConfirmAction);

  Finder get failedMessage => find.descendant(
    of: find.byType(SnackBar),
    matching: find.text(AppStrings.signOutFailedMessage),
  );
}

Future<_App> _pumpApp(WidgetTester tester) async {
  final repository = _Repository();
  addTearDown(repository.sessions.close);
  final controller = AppAuthController(
    repository,
    lastKnownIdentityStore: _IdentityStore(),
  );
  await controller.restoreSession();
  expect(controller.state.status, AppAuthStatus.signedIn);

  final membership = ActiveMembershipController(
    currentUserIdReader: () => controller.state.currentUserId,
    knownOrganizationIdReader: () => 'org-1',
  );
  controller.addListener(membership.noteInputsChanged);

  final events = <String>[];
  // Two pending changes, so every Sign out asks first.
  final command = SignOutCommand(
    currentUserIdReader: () => controller.state.currentUserId,
    countPendingWork: ({required userId}) async => 2,
    signOut: (_) async {
      events.add('sequence');
      return true;
    },
    reportError: (error, _) => events.add('report:$error'),
  );

  const context = ActiveCatalogContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );
  await tester.pumpWidget(
    isolatedSongCatalogProviderScope(
      overrides: [
        appAuthControllerProvider.overrideWith((_) => controller),
        appAuthListenableProvider.overrideWithValue(controller),
        activeMembershipControllerProvider.overrideWith((_) => membership),
        signOutCommandProvider.overrideWithValue(command),
        // What the home route needs to build without a backend.
        activeCatalogContextProvider.overrideWithValue(context),
        catalogSnapshotStateProvider.overrideWithValue(
          const CatalogSnapshotState(
            context: context,
            connectionStatus: CatalogConnectionStatus.online,
            refreshStatus: CatalogRefreshStatus.idle,
            sessionStatus: CatalogSessionStatus.verified,
            hasCachedCatalog: true,
          ),
        ),
        songLibraryListProvider.overrideWith(
          (ref) async => const [
            SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy ut'),
          ],
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) =>
            MaterialApp.router(routerConfig: ref.watch(appRouterProvider)),
      ),
    ),
  );
  final app = _App(tester, repository, controller, events);
  await app.settle();
  return app;
}

void main() {
  suppressDriftMultipleDatabaseWarnings();

  setUp(() async {
    await closeSharedDatabases();
  });

  // Both causes rebuild the router: another account signing in (a sign-in in
  // another tab, a magic link), and the session ending for the same user.
  final causes = <String, ({AppAuthSession? session, AppAuthStatus status})>{
    'a user switch': (session: _otherSession, status: AppAuthStatus.signedIn),
    'a null session': (session: null, status: AppAuthStatus.sessionExpired),
  };

  for (final entry in causes.entries) {
    testWidgets('${entry.key} while the discard dialog is open: the dialog is '
        'gone, the user is told, and Sign out works again (SF9)', (
      tester,
    ) async {
      final app = await _pumpApp(tester);
      await app.openAccount();

      await app.tapSignOut();
      expect(app.confirmDialog, findsOneWidget);

      final previousRouter = app.router;
      app.repository.sessions.add(entry.value.session);
      await app.settle();

      // The mechanism: the auth change built another router, and the
      // navigator that held the dialog is gone.
      expect(app.controller.state.status, entry.value.status);
      expect(identical(app.router, previousRouter), isFalse);
      expect(app.confirmDialog, findsNothing);

      // Not silent: the sign-out did not complete, and nothing ran.
      expect(app.failedMessage, findsOneWidget);
      expect(app.events, isEmpty);

      // The command lock is free: the next Sign out asks again instead of
      // answering `alreadyRunning` in silence.
      await app.openAccount();
      await app.tapSignOut();
      expect(app.confirmDialog, findsOneWidget);
    });
  }

  testWidgets('a dialog the user answered is not reported lost (SF9)', (
    tester,
  ) async {
    final app = await _pumpApp(tester);
    await app.openAccount();

    await app.tapSignOut();
    expect(app.confirmDialog, findsOneWidget);

    await tester.tap(find.text(AppStrings.songCancelAction));
    await app.settle();

    expect(app.confirmDialog, findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(app.events, isEmpty);

    // A later auth change does not resurrect it as a loss.
    app.repository.sessions.add(_otherSession);
    await app.settle();
    expect(find.byType(SnackBar), findsNothing);

    // And the lock was released by the Cancel: Sign out asks again.
    await app.openAccount();
    await app.tapSignOut();
    expect(app.confirmDialog, findsOneWidget);
  });
}
