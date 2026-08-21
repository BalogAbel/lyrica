import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
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
import 'package:lyron_app/src/application/provider_retry_policy.dart';
import 'package:lyron_app/src/application/song_catalog_providers.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_controller.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_auth_repository.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_invitation_repository.dart';
import 'package:lyron_app/src/offline/auth/drift_last_known_identity_store.dart';
import 'package:lyron_app/src/offline/auth/drift_pending_local_work_reader.dart';
import 'package:lyron_app/src/offline/auth/last_known_identity_database.dart';
import 'package:lyron_app/src/offline/local_data_events/drift_local_data_events_store.dart';
import 'package:lyron_app/src/offline/local_data_events/local_data_events_database.dart';

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

final localDataEventsDatabaseProvider = Provider<LocalDataEventsDatabase>((
  ref,
) {
  final database = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
      ? LocalDataEventsDatabase.inMemory()
      : LocalDataEventsDatabase.local();
  ref.onDispose(database.close);
  return database;
});

final localDataEventsRecorderProvider = Provider<LocalDataEventsRecorder>((
  ref,
) {
  return DriftLocalDataEventsStore(ref.watch(localDataEventsDatabaseProvider));
});

final localDataEventsReaderProvider = Provider<LocalDataEventsReader>((ref) {
  return DriftLocalDataEventsStore(ref.watch(localDataEventsDatabaseProvider));
});

/// autoDispose: this backs a diagnostics-only screen, so the query result
/// need not be kept alive once nothing is watching it (matches
/// songCatalogControllerProvider's autoDispose convention for one-off screen
/// data elsewhere in this file's neighborhood).
final localDataEventsRecordsProvider =
    FutureProvider.autoDispose<List<LocalDataEventRecord>>((ref) {
      return ref.watch(localDataEventsReaderProvider).readRecent(limit: 200);
    }, retry: noAutomaticProviderRetry);

final localDataLifecycleProvider = Provider<LocalDataLifecycle>((ref) {
  return LocalDataLifecycle(
    songCatalogStore: ref.watch(songCatalogStoreProvider),
    planningLocalStore: ref.watch(planningLocalStoreProvider),
    identityStore: ref.watch(lastKnownIdentityStoreProvider),
    noteLastKnownIdentity: (identity) {
      ref.read(appAuthControllerProvider).noteLastKnownIdentity(identity);
    },
    eventsRecorder: ref.watch(localDataEventsRecorderProvider),
  );
});

final lastKnownIdentityPersistenceProvider = Provider<void>((ref) {
  final authController = ref.read(appAuthControllerProvider);
  final identityStore = ref.watch(lastKnownIdentityStoreProvider);
  final epoch = ref.watch(lastKnownIdentityPersistenceEpochProvider);
  final promptController = ref.read(reauthPromptControllerProvider);
  final lifecycle = ref.read(localDataLifecycleProvider);

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
        // AppAuthStatus.signedOut is only reachable via an explicit sign-out
        // act or "no identity to protect" (D2) -- this code cannot currently
        // distinguish an explicit sign-out from account deletion
        // (AppAuthController.deleteAccount() sets the identical
        // _isSigningOut flag and converges to the identical signedOut status
        // as signOut() -- there is no discriminator anywhere in
        // AppAuthState). PurgeReason.userSignOut is used for both today;
        // distinguishing them would require adding a discriminator to
        // AppAuthState, out of this task's scope.
        await lifecycle.clearIdentity(reason: PurgeReason.userSignOut);
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
              final identity = LastKnownIdentity(
                userId: session.userId,
                email: session.email,
                organizationId: organizationId,
              );
              await lifecycle.writeIdentity(identity);
            case ActiveOrganizationVerifiedEmpty():
              if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
                return false;
              }
              // This is a single fresh verifiedEmpty membership resolution
              // at sign-in time -- the closest of the 4 documented
              // PurgeReasons, though D5's "two consecutive confirmations
              // before purge" quarantine gate is not yet built (that's
              // Phase 4) -- this call only ever clears the identity row,
              // never the song catalog or planning data, so its blast
              // radius stays small even before Phase 4 lands.
              await lifecycle.clearIdentity(
                reason: PurgeReason.membershipRevokedConfirmed,
              );
            case ActiveOrganizationUnknownConnectivityFailure():
            case ActiveOrganizationUnknownNonConnectivityFailure():
            case null:
              if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
                return false;
              }
              final identity = LastKnownIdentity(
                userId: session.userId,
                email: session.email,
                organizationId: null,
              );
              await lifecycle.writeIdentity(identity);
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
        // M4 (PR #64 review): each of these three takes `identity` as a
        // parameter rather than unwrapping `priorIdentity!` itself. The call
        // site below only ever builds a closure that calls one of these
        // (via `() => countPriorPendingWorkFor(identity)` etc.) on the
        // branch where `priorIdentity` has already been null-checked once,
        // so the compiler -- not `resolveReauth`'s current branching --
        // enforces that `identity` is never null here. A future contract
        // change in `resolveReauth` that called one of these on the
        // same-user path would now fail to compile instead of crashing on
        // the destructive wipe path.
        Future<int?> countPriorPendingWorkFor(
          LastKnownIdentity identity,
        ) async {
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

        Future<bool> cancelToPriorUserFor(LastKnownIdentity identity) async {
          if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
            return false;
          }
          final cancellation = authController.cancelReauthToPriorSession(
            AppAuthSession(userId: identity.userId, email: identity.email),
          );
          await cancellation;
          return true;
        }

        Future<bool> wipePriorAndProceedFor(LastKnownIdentity identity) async {
          if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
            return false;
          }
          final priorUserId = identity.userId;
          // Finding A (PR #64 review, 2026-08-06 remediation round): this
          // try USED to also wrap persistNewIdentity() below, on the
          // reasoning that any failure in this function should fall back to
          // cancelToPriorUserFor. That reasoning was wrong for exactly this
          // step: cancelToPriorUserFor converges to sessionExpired carrying
          // the PRIOR user's session, which is only a truthful fallback
          // while the prior user's local data (and identity row) might
          // still be intact -- i.e. while the destructive part below has
          // not yet fully committed. Once the deletions and the clear have
          // committed, the prior user's data is genuinely gone, so
          // "sessionExpired as the prior user" would assert an offline-
          // authenticated identity for a user this function just erased
          // every local trace of. The try is scoped to exactly that
          // destructive part -- the two deletions and the clear -- so only
          // a failure that can still be truthfully undone by "fall back to
          // the prior user" takes that path. persistNewIdentity() runs
          // after the try and is handled on its own terms below.
          try {
            final songDeletion = lifecycle.purgeSongCatalog(
              userId: priorUserId,
              reason: PurgeReason.differentUserSignIn,
            );
            final planningDeletion = lifecycle.purgePlanningData(
              userId: priorUserId,
              reason: PurgeReason.differentUserSignIn,
            );
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
            await lifecycle.clearIdentity(
              reason: PurgeReason.differentUserSignIn,
            );
          } catch (error, stackTrace) {
            // A song/planning deletion failed, or identityStore.clear()
            // itself failed. Either way the destructive part did not fully
            // commit: at worst the deletions ran partially, but the clear
            // never landed, so the identity store still names the prior
            // user exactly as this function found it (the only write this
            // try makes to the store is the clear itself -- there is no
            // earlier write in this try to have landed instead). Falling
            // back to cancelToPriorUserFor is therefore still truthful
            // here: the prior user's identity row genuinely still describes
            // an account whose local data has not been confirmed wiped, so
            // presenting the app as offline-authenticated as that user
            // while flagging the failure is accurate, and the next real
            // signedIn edge for this user retries the wipe cleanly.
            //
            // "Proceed anyway" (persist the new identity as if the wipe had
            // succeeded) is the exact stranding this exists to prevent --
            // rejected outright, same as before. "Leave the resolution
            // incomplete and retryable" without also converging state is
            // rejected as the PRIMARY response for the same reason as
            // before: the live Supabase session is owned outside this
            // listener and keeps presenting the device as the new user
            // regardless of what this function does, so doing nothing here
            // does not stop that presentation -- falling back to cancel
            // does.
            //
            // cancelToPriorUserFor's own backend signOut() failing does not
            // make this await unsafe: Finding 2's fix in
            // cancelReauthToPriorSession still converges local state to
            // sessionExpired/prior-session deterministically on that path
            // rather than throwing. A second, independent way this await
            // could still fail is _setState's call to notifyListeners() --
            // but that cannot escape here either: Flutter's own
            // ChangeNotifier.notifyListeners() (foundation/change_notifier
            // .dart) already wraps EACH listener call in its own try/catch
            // and reports a synchronous listener exception via
            // FlutterError.reportError itself, continuing to notify the
            // remaining listeners rather than rethrowing past its own call.
            // Both of this await's failure modes are therefore already
            // handled before they would reach here, which is what actually
            // makes it safe to await without a nested try -- not merely
            // signOut() succeeding.
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
            await cancelToPriorUserFor(identity);
            return false;
          }
          if (!isCurrent(generation, AppAuthStatus.signedIn, session)) {
            return false;
          }
          try {
            return await persistNewIdentity();
          } catch (error, stackTrace) {
            // The destructive part above already committed: the prior
            // user's local data and identity row are genuinely gone. Only
            // the terminal write of the NEW identity failed here, so
            // falling back to cancelToPriorUserFor -- which asserts
            // sessionExpired as the PRIOR user -- would now be the
            // misleading claim this finding exists to remove: there is no
            // local data left to truthfully return to, and a cold restart
            // in this window reads a null identity and yields signedOut,
            // never the prior user, so that fallback's implied "next
            // signedIn edge retries the wipe" has nothing to detect.
            //
            // Instead: report the failure unconditionally (the same
            // reasoning as the destructive-part catch above -- nothing else
            // is queued to retry this automatically) and leave the live
            // AppAuthController state untouched. That state was already
            // set to signedIn as the new user by the auth stream before
            // this listener ran and stays exactly that -- which is the
            // truthful state, since the new user genuinely is signed in.
            // LastKnownIdentityStore is left empty (cleared, never
            // rewritten): honest about there being no currently-persisted
            // identity, rather than resurrecting a prior-user row with
            // nothing behind it. This self-heals the same way the rest of
            // this listener does -- any later signedIn edge for the same
            // new user (a token refresh, a foreground resume, a manual
            // re-sign-in after a cold restart's forced signedOut) re-reads
            // a null prior identity and retries persistNewIdentity() on its
            // own same-user path.
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'lastKnownIdentityPersistenceProvider',
                context: ErrorDescription(
                  'wipePriorAndProceed: the prior user\'s data was wiped '
                  'and the identity store cleared, but persisting the new '
                  'identity failed; leaving the store empty rather than '
                  'falsely restoring the prior user\'s offline-'
                  'authenticated state',
                ),
              ),
            );
            return false;
          }
        }

        // M4 (PR #64 review): `priorIdentity` is null-checked exactly once,
        // here, and only the non-null branch builds closures that read it
        // (via the promoted `identity` local) -- `countPriorPendingWorkFor`,
        // `wipePriorAndProceedFor`, and `cancelToPriorUserFor` above no
        // longer unwrap `priorIdentity!` themselves. The null branch's
        // stand-ins are never actually invoked: resolveReauth only calls
        // `priorPendingCount`/`wipePriorAndProceed`/`cancelToPriorUser` on
        // the different-user path, which requires a non-null `priorUserId`
        // -- but that safety used to depend on resolveReauth's own
        // branching; a contract change there would now fail to compile
        // instead of crashing `priorIdentity!` on the destructive wipe path.
        final ReauthOutcome outcome;
        final identity = priorIdentity;
        if (identity == null) {
          outcome = await resolveReauth(
            newUserId: session.userId,
            priorUserId: null,
            priorEmail: null,
            priorPendingCount: () async => null,
            flushSameUser: persistNewIdentity,
            wipePriorAndProceed: () async => false,
            confirmDifferentUser: ref
                .read(reauthPromptControllerProvider)
                .requestConfirmation,
            cancelToPriorUser: () async => false,
            isCurrent: () =>
                isCurrent(generation, AppAuthStatus.signedIn, session),
          );
        } else {
          outcome = await resolveReauth(
            newUserId: session.userId,
            priorUserId: identity.userId,
            priorEmail: identity.email,
            priorPendingCount: () => countPriorPendingWorkFor(identity),
            flushSameUser: persistNewIdentity,
            wipePriorAndProceed: () => wipePriorAndProceedFor(identity),
            confirmDifferentUser: ref
                .read(reauthPromptControllerProvider)
                .requestConfirmation,
            cancelToPriorUser: () => cancelToPriorUserFor(identity),
            isCurrent: () =>
                isCurrent(generation, AppAuthStatus.signedIn, session),
          );
        }
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
            // Two paths reach ReauthSuperseded WITHOUT a newer edge queued
            // behind it, both inside wipePriorAndProceedFor's two catches
            // above: Finding 1's destructive-part failure (recovers via
            // cancelToPriorUser) and Finding A's persistNewIdentity-only
            // failure (recovers by leaving the live state untouched and the
            // identity store empty, 2026-08-06 remediation round). Both
            // call sites already reported their failure unconditionally via
            // FlutterError.reportError before returning false, specifically
            // because THIS branch cannot distinguish "benign, self-healing
            // supersession" (the normal case) from "a genuine failure that
            // already recovered and already reported itself" -- reporting
            // again here would either double-report a real failure or
            // false-alarm on every ordinary overlapping-auth-edge race,
            // which this architecture treats as a normal, expected
            // occurrence (ADR-029 D3). A low-severity trace is still useful
            // for local debugging, so it is logged here rather than
            // silently dropped -- kDebugMode-gated is appropriate for this
            // branch specifically (unlike either catch's unconditional
            // report) because every path reaching here is either already
            // reported for real or genuinely benign.
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
