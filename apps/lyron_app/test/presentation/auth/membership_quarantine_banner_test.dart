import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/presentation/auth/membership_quarantine_banner.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class _TestAuthRepository implements AuthRepository {
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

/// A mutable fake so a test can change what the NEXT [read] returns --
/// mirrors how the real gate (LocalDataLifecycle.resolveVerifiedEmptyMembership)
/// changes what the durable store holds between one resolution and the next.
class _FakeLastKnownIdentityStore implements LastKnownIdentityStore {
  _FakeLastKnownIdentityStore({this.identity});

  LastKnownIdentity? identity;

  @override
  Future<LastKnownIdentity?> read() async => identity;

  @override
  Future<void> write(LastKnownIdentity identity) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets(
    'membership quarantine banner shows the explanatory message when '
    'membershipRevokedAt is set',
    (tester) async {
      final controller = AppAuthController(_TestAuthRepository());
      final identityStore = _FakeLastKnownIdentityStore(
        identity: LastKnownIdentity(
          userId: 'user-1',
          email: 'demo@lyron.local',
          organizationId: 'org-1',
          membershipRevokedAt: DateTime.utc(2026, 8, 22),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => controller),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MembershipQuarantineBanner()),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(AppStrings.membershipQuarantineMessage),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('membership-quarantine-banner')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'membership quarantine banner is hidden when there is no marker',
    (tester) async {
      final controller = AppAuthController(_TestAuthRepository());
      final identityStore = _FakeLastKnownIdentityStore(
        identity: const LastKnownIdentity(
          userId: 'user-1',
          email: 'demo@lyron.local',
          organizationId: 'org-1',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => controller),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MembershipQuarantineBanner()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(AppStrings.membershipQuarantineMessage), findsNothing);
      expect(
        find.byKey(const ValueKey('membership-quarantine-banner-empty')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'membership quarantine banner appears reactively once the '
    'quarantine revision provider bumps after the widget has already built',
    (tester) async {
      final controller = AppAuthController(_TestAuthRepository());
      final identityStore = _FakeLastKnownIdentityStore(
        identity: const LastKnownIdentity(
          userId: 'user-1',
          email: 'demo@lyron.local',
          organizationId: 'org-1',
        ),
      );
      final container = ProviderContainer(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => controller),
          lastKnownIdentityStoreProvider.overrideWithValue(identityStore),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: MembershipQuarantineBanner()),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('membership-quarantine-banner-empty')),
        findsOneWidget,
      );

      // Simulates the durable store gaining the marker (e.g. via
      // LocalDataLifecycle.resolveVerifiedEmptyMembership), then the same
      // revision bump that gate makes alongside its identity write.
      identityStore.identity = LastKnownIdentity(
        userId: 'user-1',
        email: 'demo@lyron.local',
        organizationId: 'org-1',
        membershipRevokedAt: DateTime.utc(2026, 8, 22),
      );
      container.read(membershipQuarantineRevisionProvider.notifier).state++;
      await tester.pump();
      await tester.pump();

      expect(
        find.text(AppStrings.membershipQuarantineMessage),
        findsOneWidget,
      );
    },
  );
}
