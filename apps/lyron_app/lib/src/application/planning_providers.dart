import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:lyron_app/src/application/auth/app_auth_state.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
import 'package:lyron_app/src/application/auth_providers.dart';
import 'package:lyron_app/src/application/core_providers.dart';
import 'package:lyron_app/src/application/planning/active_planning_context_controller.dart';
import 'package:lyron_app/src/application/planning/budgeted_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/song_catalog_providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_mutation_repository.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';
import 'package:lyron_app/src/infrastructure/song_library/local_first_song_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

typedef VerifiedEmptyMembershipCleanupHandler =
    Future<void> Function({required String userId});

final class VerifiedEmptyMembershipCleanupCoordinator {
  VerifiedEmptyMembershipCleanupCoordinator({
    required this._localDataLifecycle,
    required this._countPendingWork,
    required this._requestConfirmation,
    required this._invalidateLastKnownIdentityPersistence,
  });

  final LocalDataLifecycle _localDataLifecycle;
  // Honest-null count, same contract as auth_providers.dart's
  // countPriorPendingWorkFor: a storage failure becomes "unknown" here, not
  // a silently-assumed zero (ADR-020/D5.4).
  final Future<int?> Function({required String userId}) _countPendingWork;
  final Future<ReauthPromptResult> Function({required int? pendingCount})
  _requestConfirmation;
  // D5.4/D5.5 -- Step 2: restores the invalidation Step 1 removed as
  // newly-unused. Fired only when a purge actually ran, so the next
  // signedIn-edge resolution on auth_providers.dart's serial chain sees a
  // fresh epoch and does not act on a now-stale generation captured before
  // the identity row was cleared.
  final Future<void> Function() _invalidateLastKnownIdentityPersistence;
  final _handlers = <VerifiedEmptyMembershipCleanupHandler>{};

  void addHandler(VerifiedEmptyMembershipCleanupHandler handler) {
    _handlers.add(handler);
  }

  void removeHandler(VerifiedEmptyMembershipCleanupHandler handler) {
    _handlers.remove(handler);
  }

  // D5 (docs/specs/2026-08-19-local-data-durability-contract.md, ADR-035
  // Phase 4, Task 4.2 -- Step 2 of 2): routes the resolution through
  // LocalDataLifecycle's two-confirmation gate and reports whether a purge
  // actually ran, so callers (e.g. SongCatalogController) know whether to
  // reset their own in-memory read state -- ADR-020 requires reads stay
  // unchanged on anything short of a genuine purge. On anything short of a
  // second, confirmed, genuine purge (MembershipRevocationIgnored,
  // MembershipRevocationMarkerRecorded, or a PurgeAuthorized decision whose
  // pending-work check/confirmation/re-validation ultimately declines to
  // purge), this deletes nothing and runs neither the identity-epoch
  // invalidation nor any registered planning cleanup handler -- those only
  // run once a purge has genuinely happened.
  Future<bool> handleVerifiedEmptyMembership({required String userId}) async {
    final decision = await _localDataLifecycle.resolveVerifiedEmptyMembership(
      userId: userId,
    );
    switch (decision) {
      case MembershipRevocationIgnored():
      case MembershipRevocationMarkerRecorded():
        return false;
      case MembershipRevocationPurgeAuthorized(:final markedAt):
        final purged = await _localDataLifecycle
            .maybePurgeForMembershipRevocation(
              userId: userId,
              markedAt: markedAt,
              countPendingWork: () => _countPendingWork(userId: userId),
              requestConfirmation: _requestConfirmation,
            );
        if (!purged) {
          return false;
        }
        await _invalidateLastKnownIdentityPersistence();
        // YELLOW 8 (final whole-branch review): iterate a snapshot, not the
        // live Set. A handler firing here can itself call removeHandler
        // (e.g. a provider disposing while this purge is committing) --
        // mutating _handlers while it is being iterated throws
        // ConcurrentModificationError out of this fire-and-forget listener
        // AFTER the purge has already committed.
        //
        // FIX 4 (re-review): run the snapshot with Future.wait, not a
        // sequential await loop. These handlers all run AFTER the purge has
        // already committed, so a handler that throws must not stop later
        // handlers from running at all -- a skipped one would leave its
        // controller holding state for data that has already been deleted.
        // Future.wait runs every handler and still propagates the first
        // error to this call's caller.
        await Future.wait(
          _handlers
              .toList(growable: false)
              .map((handler) => handler(userId: userId)),
        );
        return true;
    }
  }
}

final verifiedEmptyMembershipCleanupCoordinatorProvider =
    Provider<VerifiedEmptyMembershipCleanupCoordinator>((ref) {
      return VerifiedEmptyMembershipCleanupCoordinator(
        localDataLifecycle: ref.watch(localDataLifecycleProvider),
        countPendingWork: ({required userId}) async {
          try {
            return await ref
                .read(pendingLocalWorkCounterProvider)
                .count(userId: userId);
          } catch (_) {
            return null;
          }
        },
        requestConfirmation: ref
            .read(reauthPromptControllerProvider)
            .requestMembershipRevocationConfirmation,
        invalidateLastKnownIdentityPersistence: () async {
          ref.read(lastKnownIdentityPersistenceEpochProvider).invalidate();
        },
      );
    });

final planningLocalStoreProvider = Provider<PlanningLocalStore>((ref) {
  return DriftPlanningLocalStore(
    ref.watch(planningLocalDatabaseProvider),
    onStorageFootprintChanged: ref.watch(localStorageFootprintChangedProvider),
    writeRecovery: ref.watch(localStorageWriteRecoveryProvider),
  );
});

final planningMutationStoreProvider = Provider<PlanningMutationStore>((ref) {
  return BudgetedPlanningMutationStore(
    delegate: DriftPlanningMutationStore(
      database: ref.watch(planningLocalDatabaseProvider),
      localStore: ref.watch(planningLocalStoreProvider),
      onStorageFootprintChanged: ref.watch(
        localStorageFootprintChangedProvider,
      ),
    ),
    accountant: ref.watch(planningStorageAccountantProvider),
    // Shared storage-recovery boundary (D1, ADR-028): the same instance the
    // song catalog and planning local stores use, so eviction-and-retry
    // behaves identically regardless of which write triggered it (PR #64
    // review, M1) -- this class used to build its own, which made ADR-028's
    // "one shared boundary" claim false for this path.
    recovery: ref.watch(localStorageWriteRecoveryProvider),
    budget: ref.watch(localStorageBudgetProvider),
  );
});

final planningLocalReadRepositoryProvider =
    Provider<PlanningLocalReadRepository>((ref) {
      return PlanningLocalReadRepository(
        store: ref.watch(planningLocalStoreProvider),
        mutationStore: ref.watch(planningMutationStoreProvider),
        contextReader: () async {
          final syncState = ref.read(planningSyncStateProvider);
          final userId = syncState.userId;
          final organizationId = syncState.organizationId;
          if (userId == null || organizationId == null) {
            return null;
          }
          return ActivePlanningReadContext(
            userId: userId,
            organizationId: organizationId,
          );
        },
      );
    });

final planningWriteServiceProvider = Provider<PlanningWriteService>((ref) {
  return PlanningWriteService(
    ref.watch(planningRepositoryProvider),
    mutationStore: ref.watch(planningMutationStoreProvider),
    listVisibleSongs: ({required userId, required organizationId}) {
      return LocalFirstSongRepository(
        ref.read(songCatalogStoreProvider),
      ).listSongs(userId: userId, organizationId: organizationId);
    },
    activeContextReader: () async => ref.read(activePlanningContextProvider),
    syncScheduler: (context) async {
      final activeContext = ref.read(activePlanningContextProvider);
      if (activeContext == null ||
          activeContext.userId != context.userId ||
          activeContext.organizationId != context.organizationId) {
        return;
      }
      try {
        await ref
            .read(planningMutationSyncControllerProvider)
            .syncPendingMutations(activeContext);
      } finally {
        ref.read(planningMutationRevisionProvider.notifier).state += 1;
      }
    },
  );
});

final planningRemoteRefreshRepositoryProvider =
    Provider<PlanningRemoteRefreshRepository>((ref) {
      return SupabasePlanningRepository(ref.watch(supabaseClientProvider));
    });

final planningMutationRemoteRepositoryProvider =
    Provider<PlanningMutationRemoteRepository>((ref) {
      return SupabasePlanningMutationRepository(
        ref.watch(supabaseClientProvider),
      );
    });

final planningMutationSyncControllerProvider =
    Provider<PlanningMutationSyncController>((ref) {
      return PlanningMutationSyncController(
        mutationStore: () => ref.read(planningMutationStoreProvider),
        remoteRepository: () =>
            ref.read(planningMutationRemoteRepositoryProvider),
        refreshPlanning: () =>
            ref.read(planningSyncControllerProvider).refreshPlanning(),
        shouldReconcileAcceptedMutation: (context) async {
          final activeContext = ref.read(activePlanningContextProvider);
          return activeContext != null &&
              activeContext.userId == context.userId &&
              activeContext.organizationId == context.organizationId;
        },
        reconcileAcceptedMutation: PlanningMutationReconciler(
          localStore: () => ref.read(planningLocalStoreProvider),
        ).reconcile,
      );
    });

final planningRepositoryProvider = Provider<PlanningRepository>((ref) {
  return ref.watch(planningLocalReadRepositoryProvider);
});

final activePlanningContextControllerProvider =
    ChangeNotifierProvider<ActivePlanningContextController>((ref) {
      final authController = ref.read(appAuthControllerProvider);
      final controller = ActivePlanningContextController(
        authSessionReader: () => authController.state.session,
        organizationReader: () => ref.read(activeOrganizationReaderProvider)(),
        latestOrganizationReader: ({required userId}) {
          return ref
              .read(planningLocalStoreProvider)
              .readLatestCachedOrganizationId(userId: userId);
        },
        onVerifiedEmptyMembership: ({required userId}) => ref
            .read(verifiedEmptyMembershipCleanupCoordinatorProvider)
            .handleVerifiedEmptyMembership(userId: userId),
        // RED 2 (final whole-branch review, D5.2): a fresh, online,
        // authenticated non-empty resolution seen by this controller's own
        // refresh must also be able to clear an outstanding
        // membership-revocation marker.
        onVerifiedNonEmptyMembership: ({required userId}) => ref
            .read(localDataLifecycleProvider)
            .clearMembershipRevocation(userId: userId),
      );

      void handleAuthStateChanged(AppAuthState authState) {
        switch (authState.status) {
          case AppAuthStatus.initializing:
            return;
          case AppAuthStatus.signedOut:
            controller.resetForSessionLifecycle();
            return;
          case AppAuthStatus.sessionExpired:
            return;
          case AppAuthStatus.signedIn:
            unawaited(
              controller.refresh(allowCachedFallback: controller.state == null),
            );
            return;
        }
      }

      void authListener() {
        handleAuthStateChanged(authController.state);
      }

      ref.listen<ActiveCatalogContext?>(activeCatalogContextProvider, (
        _,
        next,
      ) {
        controller.syncToCatalogContext(next);
      });

      authController.addListener(authListener);
      ref.onDispose(() => authController.removeListener(authListener));
      handleAuthStateChanged(authController.state);
      return controller;
    });

final activePlanningContextProvider = Provider<ActivePlanningReadContext?>((
  ref,
) {
  return ref.watch(activePlanningContextControllerProvider).state;
});

final planningSyncControllerProvider =
    ChangeNotifierProvider<PlanningSyncController>((ref) {
      final authController = ref.read(appAuthControllerProvider);
      final cleanupCoordinator = ref.watch(
        verifiedEmptyMembershipCleanupCoordinatorProvider,
      );
      final controller = PlanningSyncController(
        localStore: () => ref.read(planningLocalStoreProvider),
        localDataLifecycle: ref.watch(localDataLifecycleProvider),
        remoteRepository: () =>
            ref.read(planningRemoteRefreshRepositoryProvider),
        authSessionReader: () => authController.state.session,
        lastKnownIdentityReader: () {
          final identity = authController.lastKnownIdentity;
          if (identity == null) return null;
          return (
            userId: identity.userId,
            organizationId: identity.organizationId,
          );
        },
      );
      Future<void> handleVerifiedEmptyMembership({required String userId}) {
        return controller.handleVerifiedEmptyMembership(userId: userId);
      }

      cleanupCoordinator.addHandler(handleVerifiedEmptyMembership);
      ref.onDispose(
        () => cleanupCoordinator.removeHandler(handleVerifiedEmptyMembership),
      );

      void handleAuthStateChanged(AppAuthState authState) {
        switch (authState.status) {
          case AppAuthStatus.initializing:
            return;
          case AppAuthStatus.signedOut:
            unawaited(controller.handleExplicitSignOut());
            return;
          case AppAuthStatus.sessionExpired:
            unawaited(controller.handleSessionExpired());
            unawaited(controller.handleOfflineAuthenticated());
            return;
          case AppAuthStatus.signedIn:
            return;
        }
      }

      ref.listen<ActivePlanningReadContext?>(activePlanningContextProvider, (
        _,
        next,
      ) {
        unawaited(controller.handleActiveContextChanged(next));
      });

      void authListener() {
        handleAuthStateChanged(authController.state);
      }

      authController.addListener(authListener);
      ref.onDispose(() => authController.removeListener(authListener));
      final activeContext = ref.read(activePlanningContextProvider);
      if (activeContext != null) {
        unawaited(controller.handleActiveContextChanged(activeContext));
      }
      handleAuthStateChanged(authController.state);
      return controller;
    });

final planningSyncStateProvider = Provider<PlanningSyncState>((ref) {
  return ref.watch(planningSyncControllerProvider).state;
});
