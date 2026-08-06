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
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_auth_repository.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_invitation_repository.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/drift_pending_local_work_reader.dart';
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
  final promptController = ref.read(reauthPromptControllerProvider);

  // Serializes signedIn-edge resolutions: only one persistIdentity call is
  // ever in flight at a time (see scheduleIdentityResolution below). Two
  // different-user signedIn edges arriving close together can therefore
  // never both reach ReauthPromptController.requestConfirmation while the
  // other's prompt is still unanswered -- the second is queued behind the
  // first's full resolution, including the wait for whatever dialog answer
  // it needed. See Finding 1 in the reauth review and the class doc on
  // ReauthPromptController.
  var resolutionChain = Future<void>.value();

  bool isCurrent(
    int generation,
    AppAuthStatus expectedStatus,
    AppAuthSession? expectedSession,
  ) {
    if (!epoch.isCurrent(generation)) return false;
    final liveState = authController.state;
    if (liveState.status != expectedStatus) return false;
    if (expectedStatus != AppAuthStatus.signedIn) return true;
    final liveSession = liveState.session;
    return expectedSession != null &&
        liveSession != null &&
        liveSession.userId == expectedSession.userId &&
        liveSession.email == expectedSession.email;
  }

  Future<void> persistIdentity(
    AppAuthState authState,
    int generation,
    AppAuthSession? capturedSession,
  ) async {
    if (!isCurrent(generation, authState.status, capturedSession)) return;

    switch (authState.status) {
      case AppAuthStatus.initializing:
        return;
      case AppAuthStatus.signedOut:
        if (!isCurrent(generation, AppAuthStatus.signedOut, null)) return;
        await identityStore.clear();
        return;
      case AppAuthStatus.sessionExpired:
        return;
      case AppAuthStatus.signedIn:
        final session = capturedSession;
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
        if (!isCurrent(generation, AppAuthStatus.signedIn, session)) return;

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
        if (!isCurrent(generation, AppAuthStatus.signedIn, session)) return;

        Future<bool> persistNewIdentity() async {
          if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
            // A verified-empty membership cleanup (or another superseding
            // resolution) advanced the epoch after this resolution passed
            // its entry check above. Re-checking here, immediately before
            // the terminal identity write, stops a superseded resolution
            // from clobbering a newer write -- see Finding 3.
            return false;
          }
          switch (resolution) {
            case ActiveOrganizationSelected(:final organizationId):
              if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
                return false;
              }
              await identityStore.write(
                LastKnownIdentity(
                  userId: session.userId,
                  email: session.email,
                  organizationId: organizationId,
                ),
              );
            case ActiveOrganizationVerifiedEmpty():
              if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
                return false;
              }
              await identityStore.clear();
            case ActiveOrganizationUnknownConnectivityFailure():
            case ActiveOrganizationUnknownNonConnectivityFailure():
            case null:
              if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
                return false;
              }
              await identityStore.write(
                LastKnownIdentity(
                  userId: session.userId,
                  email: session.email,
                  organizationId: null,
                ),
              );
          }
          return true;
        }

        // Returns null when a storage failure prevents determining the count.
        // Uncertainty must never authorise a silent wipe (ADR-020 / D5):
        // resolveReauth treats a null count the same as a nonzero one and
        // still requires confirmation. Unlike the rejected planning-only
        // count (D4), this is not a guess dressed up as a number -- "unknown"
        // stays representable all the way to the dialog instead of being
        // encoded as a fabricated count.
        Future<int?> countPriorPendingWork() async {
          final identity = priorIdentity!;
          if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
            return null;
          }
          try {
            final count = await ref
                .read(pendingLocalWorkCounterProvider)
                .count(userId: identity.userId);
            if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
              return null;
            }
            return count;
          } catch (_) {
            return null;
          }
        }

        Future<bool> cancelToPriorUser() async {
          if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
            return false;
          }
          final identity = priorIdentity!;
          final cancellation = authController.cancelReauthToPriorSession(
            AppAuthSession(userId: identity.userId, email: identity.email),
          );
          await cancellation;
          return true;
        }

        Future<bool> wipePriorAndProceed() async {
          if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
            return false;
          }
          final priorUserId = priorIdentity!.userId;
          try {
            final songDeletion = ref
                .read(songCatalogStoreProvider)
                .deleteCatalogsForUser(userId: priorUserId);
            final planningDeletion = ref
                .read(planningLocalStoreProvider)
                .deletePlanningDataForUser(userId: priorUserId);
            await Future.wait([songDeletion, planningDeletion]);
            // Being superseded from here on returns false even though the
            // deletion above already happened, so the reported outcome
            // understates what ran rather than overstating it. That is the
            // safe direction and it self-heals: the identity store still
            // holds the prior identity, so the superseding resolution reads
            // the same prior user, counts zero remaining work, and completes
            // the wipe-and-proceed path itself.
            if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
              // Same reasoning as persistNewIdentity's check, but ahead of
              // the clear that precedes it: don't let a superseded
              // resolution's clear-and-write race a concurrently firing
              // verified-empty cleanup for the same store -- see Finding 3.
              return false;
            }
            await identityStore.clear();
            if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
              return false;
            }
            return await persistNewIdentity();
          } catch (error, stackTrace) {
            // Finding 1 (PR #64 review): none of the above was wrapped, so
            // any throw -- a song or planning deletion failing, or the
            // identity-store clear/write failing -- used to rise straight
            // through resolveReauth to the outer fire-and-forget
            // catchError, which only prints in kDebugMode. In release that
            // left a PARTIAL wipe: the identity store still named the
            // prior user (never cleared), nothing shown to the user, and
            // the app signed in as the new user with the prior user's
            // leftover local data still on the device -- precisely the
            // outcome this slice exists to prevent.
            //
            // Chosen recovery: fall back to exactly the state an explicit
            // cancel produces (sessionExpired carrying the PRIOR user's
            // session), by calling the same cancelToPriorUser used for a
            // real user cancel. Two other options were weighed and
            // rejected:
            //  - "proceed anyway" (persist the new identity as if the wipe
            //    had succeeded) is the exact stranding this exists to
            //    prevent -- rejected outright.
            //  - "leave the resolution incomplete and retryable" without
            //    also converging state was rejected as the PRIMARY
            //    response: the live Supabase session is owned outside
            //    this listener and keeps presenting the device as the new
            //    user regardless of what this function does, so doing
            //    nothing here does not stop that presentation. Falling
            //    back to cancel does. Retryability is still preserved as
            //    a property of this choice, not abandoned: the identity
            //    store has not been cleared (the clear/write above never
            //    ran, or ran and this catch was reached from a later
            //    step -- either way the prior identity row is left
            //    exactly as wipePriorAndProceed found it, since the only
            //    write to it inside this function is the clear+persist
            //    pair immediately before a successful return), so the
            //    next signedIn edge for this prior user re-attempts the
            //    wipe cleanly. If cancelToPriorUser's own backend signOut
            //    fails too, Finding 2's fix still converges local state
            //    deterministically rather than throwing, so this call is
            //    always safe to await here without a nested try.
            //
            // A genuine deletion failure is reported the same way as a
            // reused `false`/[ReauthSuperseded] outcome from
            // resolveReauth's perspective (nothing claims a wipe that did
            // not fully happen), but the caller must not mistake this for
            // benign supersession-by-a-newer-edge: unlike that case,
            // nothing else is queued to retry automatically here except
            // the next real signedIn edge, so the failure is reported
            // unconditionally (not gated on kDebugMode) via
            // FlutterError.reportError instead of relying on that
            // generic backstop.
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'lastKnownIdentityPersistenceProvider',
                context: ErrorDescription(
                  'wipePriorAndProceed failed while resolving a '
                  'different-user sign-in; falling back to '
                  'cancelToPriorUser so the device does not present as '
                  'the new user with the prior user\'s data unresolved',
                ),
              ),
            );
            await cancelToPriorUser();
            return false;
          }
        }

        final outcome = await resolveReauth(
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
          isCurrent: () =>
              isCurrent(generation, AppAuthStatus.signedIn, session),
        );
        // Finding 3 (PR #64 review): this used to be a bare `await
        // resolveReauth(...)` with the returned Future<ReauthOutcome>
        // discarded -- the typed-result machinery reauth_resolution.dart's
        // own doc argues for at length ("must fail to compile rather than
        // silently") therefore had zero production effect; only tests ever
        // read it. Switching on it here, exhaustively over the *sealed*
        // ReauthOutcome, is what gives it one: a future outcome added to
        // the sealed class fails this switch to compile instead of
        // silently falling through unhandled, the same guarantee the
        // sealed class already gave the type system, now extended to this
        // call site.
        switch (outcome) {
          case ReauthProceededSameUser():
          case ReauthWipedPriorAndProceeded():
          case ReauthCancelledKeptPriorUser():
            // Each of these three already fully applied its effect INSIDE
            // the callback resolveReauth awaited before returning it here
            // (persistNewIdentity / wipePriorAndProceed / cancelToPriorUser
            // respectively): the identity store, and for a wipe or cancel
            // AppAuthController's status too, are already exactly where
            // they need to be by the time this line runs. There is nothing
            // further to apply -- this branch is the deliberate,
            // compile-checked acknowledgement of that, not the value being
            // dropped on the floor.
            break;
          case ReauthSuperseded():
            // A superseded resolution means a newer signedIn edge advanced
            // the epoch (and, if a dialog was open, completed it with
            // `.superseded`) before this resolution finished acting.
            // scheduleIdentityResolution enqueues that newer edge's own
            // persistIdentity call onto the SAME serial resolutionChain
            // before this resolution's future even settles (see its class
            // doc), so in the ordinary case a resolution that will see the
            // current, correct prior identity is already queued directly
            // behind this one: nothing here needs to retry it.
            //
            // The one path that reaches ReauthSuperseded WITHOUT a newer
            // edge queued behind it is Finding 1's wipe-failure fallback
            // (wipePriorAndProceed's catch, above): that call site already
            // both recovered (via cancelToPriorUser) and reported the
            // failure unconditionally via FlutterError.reportError,
            // specifically because THIS branch cannot distinguish "benign,
            // self-healing supersession" (the normal case) from "a genuine
            // failure that already recovered and already reported itself"
            // -- reporting again here would either double-report the real
            // failure or false-alarm on every ordinary overlapping-auth-
            // edge race, which this architecture treats as a normal,
            // expected occurrence (ADR-029 D3). A low-severity trace is
            // still useful for local debugging, so it is logged here
            // rather than silently dropped -- kDebugMode-gated is
            // appropriate for this branch specifically (unlike Finding 1's
            // unconditional report) because every path reaching here is
            // either already reported for real or genuinely benign.
            if (kDebugMode) {
              debugPrint(
                'lastKnownIdentityPersistenceProvider: reauth resolution '
                'for ${session.userId} was superseded before it could act',
              );
            }
        }
    }
  }

  void scheduleIdentityResolution(AppAuthState authState) {
    final generation = epoch.invalidate();
    promptController.supersedePending();
    final capturedSession = authState.session;
    final scheduled = resolutionChain.then(
      (_) => persistIdentity(authState, generation, capturedSession),
    );
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
  final reader = DriftPendingLocalWorkReader(
    planningDatabase: ref.watch(planningLocalDatabaseProvider),
    songDatabase: ref.watch(songCatalogDatabaseProvider),
  );
  return PendingLocalWorkCounter(
    readPlanningPendingWorkCount: reader.countPlanningPendingWork,
    readSongPendingWorkCount: reader.countSongPendingWork,
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
