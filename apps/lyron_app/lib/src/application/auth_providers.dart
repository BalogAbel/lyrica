import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/active_organization_resolver.dart';
import 'package:lyron_app/src/application/auth/active_membership_controller.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/app_auth_state.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/auth/capability_resolver.dart';
import 'package:lyron_app/src/application/auth/deep_link_listener.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/pending_invite_token_controller.dart';
import 'package:lyron_app/src/application/auth/pending_local_work_counter.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
import 'package:lyron_app/src/application/auth/reauth_resolution.dart';
import 'package:lyron_app/src/application/auth/redeem_controller.dart';
import 'package:lyron_app/src/application/core_providers.dart';
import 'package:lyron_app/src/application/planning_providers.dart';
import 'package:lyron_app/src/application/song_catalog_providers.dart';
import 'package:lyron_app/src/application/song_library/drift_song_mutation_store.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
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
  // Guard the dart:io Platform lookup with kIsWeb: Platform.environment throws
  // UnsupportedError on Web. Native and tests keep the exact prior behavior.
  final database = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
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

  // Serializes signedIn-edge resolutions: only one persistIdentity call is
  // ever in flight at a time (see scheduleIdentityResolution below). Two
  // different-user signedIn edges arriving close together can therefore
  // never both reach ReauthPromptController.requestConfirmation while the
  // other's prompt is still unanswered -- the second is queued behind the
  // first's full resolution, including the wait for whatever dialog answer
  // it needed. See Finding 1 in the reauth review and the class doc on
  // ReauthPromptController.
  var resolutionChain = Future<void>.value();

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

        // Read the prior identity BEFORE anything on this edge can
        // overwrite it. This function is the sole writer to
        // LastKnownIdentityStore on the signedIn path itself (see the
        // switch below and the signedOut case above), so capturing the
        // prior value here -- ahead of the membership-resolution await and
        // any write/clear that follows on THIS edge -- makes the
        // different-user check correct by construction against races
        // within this function. That is narrower than "nothing else could
        // race it to the store": VerifiedEmptyMembershipCleanupCoordinator
        // (planning_providers.dart) also clears and writes the same store,
        // from its own independent listener, on a verified-empty-membership
        // event. That writer bumps `epoch` first, which is why the
        // terminal identity write below is re-checked against it
        // immediately before it runs, not only once up front. See ADR-020,
        // ADR-029, and Finding 3 in the reauth review.
        final priorIdentity = await identityStore.read();

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

        Future<void> persistNewIdentity() async {
          if (!epoch.isCurrent(generation)) {
            // A verified-empty membership cleanup (or another superseding
            // resolution) advanced the epoch after this resolution passed
            // its entry check above. Re-checking here, immediately before
            // the terminal identity write, stops a superseded resolution
            // from clobbering a newer write -- see Finding 3.
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

        // Returns null when the count cannot be determined (a storage
        // failure, or a prior identity with no cached organization id to
        // scope the query by). Uncertainty must never authorise a silent
        // wipe (ADR-020 / D5): resolveReauth treats a null count the same
        // as a nonzero one and still requires confirmation. Unlike the
        // rejected planning-only count (D4), this is not a guess dressed
        // up as a number -- "unknown" stays representable all the way to
        // the dialog instead of being encoded as a fabricated count.
        Future<int?> countPriorPendingWork() async {
          final organizationId = priorIdentity!.organizationId;
          if (organizationId == null) {
            return null;
          }
          try {
            return await ref
                .read(pendingLocalWorkCounterProvider)
                .count(
                  userId: priorIdentity.userId,
                  organizationId: organizationId,
                );
          } catch (_) {
            return null;
          }
        }

        Future<void> wipePriorAndProceed() async {
          final priorUserId = priorIdentity!.userId;
          await Future.wait([
            ref
                .read(songCatalogStoreProvider)
                .deleteCatalogsForUser(userId: priorUserId),
            ref
                .read(planningLocalStoreProvider)
                .deletePlanningDataForUser(userId: priorUserId),
          ]);
          if (!epoch.isCurrent(generation)) {
            // Same reasoning as persistNewIdentity's check, but ahead of
            // the clear that precedes it: don't let a superseded
            // resolution's clear-and-write race a concurrently firing
            // verified-empty cleanup for the same store -- see Finding 3.
            return;
          }
          await identityStore.clear();
          await persistNewIdentity();
        }

        Future<void> cancelToPriorUser() async {
          final identity = priorIdentity!;
          await authController.cancelReauthToPriorSession(
            AppAuthSession(userId: identity.userId, email: identity.email),
          );
        }

        await resolveReauth(
          newUserId: session.userId,
          priorUserId: priorIdentity?.userId,
          priorEmail: priorIdentity?.email,
          priorPendingCount: countPriorPendingWork,
          flushSameUser: persistNewIdentity,
          wipePriorAndProceed: wipePriorAndProceed,
          confirmDifferentUser: ref
              .read(reauthPromptControllerProvider)
              .requestConfirmation,
          cancelToPriorUser: cancelToPriorUser,
        );
    }
  }

  void scheduleIdentityResolution(AppAuthState authState) {
    final scheduled = resolutionChain.then((_) => persistIdentity(authState));
    // Keep the chain itself always-succeeding: one resolution failing must
    // not stall -- or, worse, silently poison -- every resolution queued
    // behind it. Each invocation's own failure is still delivered below,
    // via `scheduled`, not swallowed here.
    resolutionChain = scheduled.catchError((_, _) {});
    unawaited(
      scheduled.catchError((Object error, StackTrace stackTrace) {
        // An auth-path listener must never let an unhandled exception
        // escape, whatever its cause. Serializing resolutions above should
        // make ReauthPromptController's "already pending" StateError
        // unreachable in practice now (see its class doc), but this is the
        // backstop that guarantees it regardless.
        if (kDebugMode) {
          debugPrint(
            'lastKnownIdentityPersistenceProvider: resolution failed: '
            '$error\n$stackTrace',
          );
        }
      }),
    );
  }

  void authListener() {
    scheduleIdentityResolution(authController.state);
  }

  authController.addListener(authListener);
  ref.onDispose(() => authController.removeListener(authListener));
  scheduleIdentityResolution(authController.state);
});

/// Combined song + planning pending-work counter used when resolving a
/// different-user sign-in (ADR-029): the wipe deletes both subsystems, so
/// the confirmation prompt must state everything at stake, not just one
/// side of it.
final pendingLocalWorkCounterProvider = Provider<PendingLocalWorkCounter>((
  ref,
) {
  final songMutationStore = DriftSongMutationStore(
    songCatalogStore: ref.watch(songCatalogStoreProvider),
    planningLocalStore: ref.watch(planningLocalStoreProvider),
  );
  final planningMutationStore = ref.watch(planningMutationStoreProvider);
  return PendingLocalWorkCounter(
    readPlanningPendingMutations: planningMutationStore.readPendingMutations,
    readPendingSongs: songMutationStore.readPendingSongs,
    readConflictSongs: songMutationStore.readConflictSongs,
  );
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

/// App-scoped and NOT autoDispose: a pending different-user reauth prompt
/// must survive whatever screen is on top when it is requested. See
/// `ReauthPromptController` and `ReauthPromptHost`, and ADR-029.
final reauthPromptControllerProvider =
    ChangeNotifierProvider<ReauthPromptController>((_) {
      return ReauthPromptController();
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

final activeOrganizationResolverProvider = Provider<ActiveOrganizationResolver>(
  (ref) {
    return ActiveOrganizationResolver(
      resolveRawReader: ref.watch(activeOrganizationResolutionProvider),
      readUserId: () =>
          ref.read(appAuthControllerProvider).state.session?.userId,
      readCachedOrganizationId: ref
          .read(songCatalogStoreProvider)
          .readLatestCachedOrganizationId,
    );
  },
);

final membershipResolutionProvider =
    Provider<ActiveOrganizationResolutionReader>((ref) {
      return ref
          .watch(activeOrganizationResolverProvider)
          .resolveWithCachedFallback;
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
  return ref.watch(activeOrganizationResolverProvider).resolveOrganizationId;
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
