import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/auth/active_membership_controller.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/app_auth_state.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/capability_resolver.dart';
import 'package:lyron_app/src/application/auth/deep_link_listener.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/pending_invite_token_controller.dart';
import 'package:lyron_app/src/application/auth/redeem_controller.dart';
import 'package:lyron_app/src/application/core_providers.dart';
import 'package:lyron_app/src/application/song_catalog_providers.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_auth_repository.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_invitation_repository.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(ref.read(supabaseClientProvider));
});

final activeOrganizationResolutionProvider =
    Provider<ActiveOrganizationResolutionReader>((ref) {
      final client = ref.watch(supabaseClientProvider);

      return () {
        return resolveActiveOrganizationResolution(
          () async => client.rpc('current_organization_ids'),
        );
      };
    });

final appAuthControllerProvider = ChangeNotifierProvider<AppAuthController>((
  ref,
) {
  final controller = AppAuthController(
    ref.read(authRepositoryProvider),
    lastKnownIdentityStore: ref.read(lastKnownIdentityStoreProvider),
  );
  unawaited(controller.restoreSession());
  return controller;
});

final lastKnownIdentityDatabaseProvider = Provider<LastKnownIdentityDatabase>((
  ref,
) {
  final database = Platform.environment.containsKey('FLUTTER_TEST')
      ? LastKnownIdentityDatabase.inMemory()
      : LastKnownIdentityDatabase.local();
  ref.onDispose(database.close);
  return database;
});

final lastKnownIdentityStoreProvider = Provider<LastKnownIdentityStore>((ref) {
  return DriftLastKnownIdentityStore(
    ref.watch(lastKnownIdentityDatabaseProvider),
  );
});

final lastKnownIdentityPersistenceProvider = Provider<void>((ref) {
  final authController = ref.read(appAuthControllerProvider);
  final identityStore = ref.watch(lastKnownIdentityStoreProvider);
  final epoch = ref.watch(lastKnownIdentityPersistenceEpochProvider);

  Future<void> persistIdentity(AppAuthState authState) async {
    final generation = epoch.invalidate();

    switch (authState.status) {
      case AppAuthStatus.initializing:
        return;
      case AppAuthStatus.signedOut:
        await identityStore.clear();
        return;
      case AppAuthStatus.sessionExpired:
        return;
      case AppAuthStatus.signedIn:
        final session = authState.session;
        if (session == null) {
          return;
        }
        ActiveOrganizationResolution? resolution;
        try {
          resolution = await ref.read(membershipResolutionProvider)();
        } catch (_) {
          // Membership resolution unavailable (offline, a non-connectivity
          // error, or an uninitialized backend). Persist the identity with an
          // unknown organization instead of letting this fire-and-forget auth
          // listener throw an unhandled exception; the org is refined on a
          // later successful resolution.
          resolution = null;
        }
        final currentState = authController.state;
        final currentSession = currentState.session;
        if (currentState.status != AppAuthStatus.signedIn ||
            currentSession == null ||
            currentSession.userId != session.userId ||
            currentSession.email != session.email ||
            !epoch.isCurrent(generation)) {
          return;
        }
        switch (resolution) {
          case ActiveOrganizationSelected(:final organizationId):
            await identityStore.write(
              LastKnownIdentity(
                userId: session.userId,
                email: session.email,
                organizationId: organizationId,
              ),
            );
          case ActiveOrganizationVerifiedEmpty():
            await identityStore.clear();
          case ActiveOrganizationUnknownConnectivityFailure():
          case ActiveOrganizationUnknownNonConnectivityFailure():
          case null:
            await identityStore.write(
              LastKnownIdentity(
                userId: session.userId,
                email: session.email,
                organizationId: null,
              ),
            );
        }
    }
  }

  void authListener() {
    unawaited(persistIdentity(authController.state));
  }

  authController.addListener(authListener);
  ref.onDispose(() => authController.removeListener(authListener));
  unawaited(persistIdentity(authController.state));
});

final invitationRepositoryProvider = Provider<InvitationRepository>((ref) {
  return SupabaseInvitationRepository(ref.read(supabaseClientProvider));
});

final pendingInviteTokenControllerProvider =
    ChangeNotifierProvider<PendingInviteTokenController>((ref) {
      final controller = PendingInviteTokenController();
      return controller;
    });

final redeemControllerProvider = ChangeNotifierProvider<RedeemController>((
  ref,
) {
  return RedeemController(ref.read(invitationRepositoryProvider));
});

final deepLinkListenerProvider = Provider<DeepLinkListener>((ref) {
  final pending = ref.read(pendingInviteTokenControllerProvider);
  final stream = AppLinks().uriLinkStream;
  final listener = DeepLinkListener(stream: stream, pendingTokens: pending);
  ref.onDispose(() => listener.dispose());
  return listener;
});

final activeMembershipControllerProvider =
    ChangeNotifierProvider<ActiveMembershipController>(
      (_) => ActiveMembershipController(),
    );

/// Returns [resolution] unchanged unless it is an
/// [ActiveOrganizationUnknownConnectivityFailure] AND a [userId] is present AND
/// a cached organization id can be read for that user — in which case it returns
/// `ActiveOrganizationResolution.selected(cachedOrgId)`. If the cache read
/// throws, the original [resolution] is returned — the fallback is best-effort
/// and must never escalate a recoverable connectivity failure into a crash.
///
/// Extracted as a pure top-level function so it can be unit-tested without any
/// Riverpod or Supabase dependency.
Future<ActiveOrganizationResolution> resolveMembershipWithCachedFallback({
  required ActiveOrganizationResolution resolution,
  required String? userId,
  required Future<String?> Function({required String userId})
  readCachedOrganizationId,
}) async {
  if (resolution is! ActiveOrganizationUnknownConnectivityFailure) {
    return resolution;
  }
  if (userId == null) return resolution;
  try {
    final cachedOrgId = await readCachedOrganizationId(userId: userId);
    if (cachedOrgId == null) return resolution;
    return ActiveOrganizationResolution.selected(cachedOrgId);
  } catch (_) {
    // Best-effort fallback: a cache read error must not escalate a recoverable
    // connectivity failure into an unhandled crash. Keep the original
    // resolution so the gate shows the connectivity message instead.
    return resolution;
  }
}

final membershipResolutionProvider =
    Provider<ActiveOrganizationResolutionReader>((ref) {
      return () async {
        final resolution = await ref.read(
          activeOrganizationResolutionProvider,
        )();
        final userId = ref
            .read(appAuthControllerProvider)
            .state
            .session
            ?.userId;
        return resolveMembershipWithCachedFallback(
          resolution: resolution,
          userId: userId,
          readCachedOrganizationId: ref
              .read(songCatalogStoreProvider)
              .readLatestCachedOrganizationId,
        );
      };
    });

final membershipRefreshEffectProvider = Provider<void>((ref) {
  final membershipController = ref.read(activeMembershipControllerProvider);

  Future<void> refreshMembership() async {
    final reader = ref.read(membershipResolutionProvider);
    final result = await reader();
    membershipController.update(result);
  }

  ref.listen<AppAuthStatus>(
    appAuthControllerProvider.select((c) => c.state.status),
    (prev, next) {
      if (next == AppAuthStatus.signedIn && prev != AppAuthStatus.signedIn) {
        unawaited(refreshMembership());
      }
    },
    fireImmediately: true,
  );

  ref.listen<RedeemState>(redeemControllerProvider.select((c) => c.state), (
    prev,
    next,
  ) {
    if (next is RedeemStateSuccess && prev is! RedeemStateSuccess) {
      unawaited(refreshMembership());
    }
  });
});

final appAuthListenableProvider = Provider<Listenable>((ref) {
  ref.watch(lastKnownIdentityPersistenceProvider);
  return Listenable.merge([
    ref.read(appAuthControllerProvider),
    ref.read(activeMembershipControllerProvider),
  ]);
});

final activeOrganizationReaderProvider = Provider<ActiveOrganizationReader>((
  ref,
) {
  return () async {
    final resolution = await ref.read(activeOrganizationResolutionProvider)();
    return switch (resolution) {
      ActiveOrganizationSelected(:final organizationId) => organizationId,
      ActiveOrganizationVerifiedEmpty() => null,
      ActiveOrganizationUnknownConnectivityFailure() =>
        throw const SocketException(
          'active organization lookup temporarily unavailable',
        ),
      ActiveOrganizationUnknownNonConnectivityFailure() => throw StateError(
        'active organization lookup failed',
      ),
    };
  };
});

final capabilityResolverProvider = ChangeNotifierProvider<CapabilityResolver>((
  ref,
) {
  final client = ref.watch(supabaseClientProvider);
  final resolver = CapabilityResolver(
    gateway: SupabaseCapabilityGateway(client),
  );
  // Invalidate on any auth state change (sign-in, sign-out, token refresh).
  ref.listen<AppAuthController>(
    appAuthControllerProvider,
    (_, _) => resolver.invalidate(),
  );
  // Invalidate when a role upgrade completes via invitation redemption so
  // write affordances appear immediately without requiring a sign-out/in.
  ref.listen<RedeemState>(redeemControllerProvider.select((c) => c.state), (
    prev,
    next,
  ) {
    if (next is RedeemStateSuccess && prev is! RedeemStateSuccess) {
      resolver.invalidate();
    }
  });
  return resolver;
});
