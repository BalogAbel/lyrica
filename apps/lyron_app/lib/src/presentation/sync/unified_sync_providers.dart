import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';
import 'package:lyron_app/src/application/sync/foreground_sync_listener.dart';
import 'package:lyron_app/src/application/sync/online_transition_detector.dart';
import 'package:lyron_app/src/application/sync/unified_discard_controller.dart';
import 'package:lyron_app/src/application/sync/unified_manual_sync_controller.dart';
import 'package:lyron_app/src/application/sync/unified_row_recovery_controller.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';

final planningPlanTitlesProvider = Provider.autoDispose<Map<String, String>>((
  ref,
) {
  final summaries = ref.watch(planningPlanListProvider).value;
  if (summaries == null) return const {};
  return {for (final summary in summaries) summary.id: summary.name};
});

T _safeWatch<T>(T Function() read, T fallback) {
  try {
    return read();
  } catch (_) {
    return fallback;
  }
}

/// Local storage footprint (LF-T4) for the active planning context.
///
/// A [FutureProvider] because measuring runs real queries against the
/// planning and catalog databases; the aggregator below reads it through
/// `.valueOrNull`, the same pattern already used for [planningPlanListProvider]
/// via [planningPlanTitlesProvider].
final localStorageFootprintProvider =
    FutureProvider.autoDispose<LocalStorageFootprint>((ref) async {
      ref.watch(localStorageFootprintRevisionProvider);
      final context = ref.watch(activePlanningContextProvider);
      if (context == null) {
        return const LocalStorageFootprint.empty();
      }
      return ref
          .watch(localStorageMonitorProvider)
          .measure(
            userId: context.userId,
            organizationId: context.organizationId,
          );
    });

final unifiedSyncOverviewProvider = Provider.autoDispose<UnifiedSyncOverview>((
  ref,
) {
  final catalog = _safeWatch(
    () => ref.watch(catalogSnapshotStateProvider),
    const CatalogSnapshotState.initial(),
  );
  final songEntries = _safeWatch(
    () =>
        ref.watch(songMutationEntriesProvider).value ??
        const <SongMutationRecord>[],
    const <SongMutationRecord>[],
  );
  final planning = _safeWatch(
    () => ref.watch(planningSyncStateProvider),
    const PlanningSyncState.initial(),
  );
  final planningEntries = _safeWatch(
    () =>
        ref.watch(planningMutationEntriesProvider).value ??
        const <PlanningMutationRecord>[],
    const <PlanningMutationRecord>[],
  );
  final planTitles = _safeWatch(
    () => ref.watch(planningPlanTitlesProvider),
    const <String, String>{},
  );
  final isRunning = _safeWatch(
    () => ref.watch(unifiedManualSyncControllerProvider).isRunning,
    false,
  );
  final storageFootprint = _safeWatch(
    () =>
        ref.watch(localStorageFootprintProvider).value ??
        const LocalStorageFootprint.empty(),
    const LocalStorageFootprint.empty(),
  );
  final storagePressure = _safeWatch(
    () => ref.watch(localStorageBudgetProvider).classify(storageFootprint),
    LocalStoragePressure.ok,
  );

  // Drive the offline-to-online detector from changes seen by the overview
  // itself. This keeps the trigger wiring on the same active-organization
  // boundary that already feeds the header control, and avoids attaching
  // listeners at app boot before any signed-in workspace surface is mounted.
  try {
    ref.read(onlineTransitionDetectorProvider)
      ..updateCatalog(catalog)
      ..updatePlanning(planning);
    // Reading the foreground listener boots its lifecycle subscription.
    ref.read(foregroundSyncListenerProvider);
  } catch (_) {
    // Tests that do not wire the supporting providers can ignore the
    // trigger plumbing; widget rendering must not depend on it.
  }

  final base = computeUnifiedSyncOverview(
    UnifiedSyncOverviewInputs(
      catalog: catalog,
      songEntries: songEntries,
      planning: planning,
      planningEntries: planningEntries,
      planTitles: planTitles,
      songSyncing: isRunning,
      planningSyncing: isRunning,
    ),
  );

  return UnifiedSyncOverview(
    headerStatus: base.headerStatus,
    activity: base.activity,
    connectivity: base.connectivity,
    freshness: base.freshness,
    songRows: base.songRows,
    planRows: base.planRows,
    hasUnsyncedWork: base.hasUnsyncedWork,
    storagePressure: storagePressure,
    pendingMutationCount: storageFootprint.mutationCount,
  );
});

final unifiedManualSyncControllerProvider =
    ChangeNotifierProvider.autoDispose<UnifiedManualSyncController>((ref) {
      final controller = UnifiedManualSyncController(
        activeContextReader: () {
          final c = ref.read(activeCatalogContextProvider);
          if (c == null) return null;
          return UnifiedSyncActiveContext(
            userId: c.userId,
            organizationId: c.organizationId,
          );
        },
        syncSongMutations: (context) async {
          await ref
              .read(songMutationSyncControllerProvider)
              .syncPendingSongs(
                SongMutationContext(
                  userId: context.userId,
                  organizationId: context.organizationId,
                ),
              );
          ref.invalidate(songMutationEntriesProvider);
        },
        refreshSongCatalog: () =>
            ref.read(songCatalogControllerProvider).refreshCatalog(),
        syncPlanningMutations: (context) async {
          final planningContext = ref.read(activePlanningContextProvider);
          if (planningContext == null ||
              planningContext.userId != context.userId ||
              planningContext.organizationId != context.organizationId) {
            return;
          }
          await ref
              .read(planningMutationSyncControllerProvider)
              .syncPendingMutations(planningContext);
          ref.read(planningDataRevisionProvider.notifier).state += 1;
        },
        refreshPlanning: () async {
          await ref.read(planningSyncControllerProvider).refreshPlanning();
        },
      );
      return controller;
    });

final onlineTransitionDetectorProvider = Provider<OnlineTransitionDetector>((
  ref,
) {
  return OnlineTransitionDetector(
    onTransitionToOnline: () {
      unawaited(
        Future.microtask(() {
          ref.read(unifiedManualSyncControllerProvider).syncNow();
        }),
      );
    },
    // The underlying controllers already single-flight, dedup, and short-
    // circuit when there is nothing to sync, so firing on every reconnect
    // remains cheap and avoids reading the overview (which would create a
    // cycle through this provider).
    triggerWhenClean: true,
  );
});

final foregroundSyncListenerProvider = Provider<ForegroundSyncListener>((ref) {
  final listener = ForegroundSyncListener(
    foregroundState: ref.watch(appForegroundStateProvider),
    onResume: () async {
      await Future.microtask(() {});
      await ref.read(unifiedManualSyncControllerProvider).syncNow();
    },
  );
  ref.onDispose(listener.dispose);
  return listener;
});

final unifiedDiscardControllerProvider =
    Provider.autoDispose<UnifiedDiscardController>((ref) {
      return UnifiedDiscardController(
        activeContextReader: () {
          final c = ref.read(activeCatalogContextProvider);
          // A null catalog context here is what makes discardAll()'s
          // null-context branch return `discarded` (see that method's
          // doc): no active user/organization means nothing was pending
          // for this caller, so reporting "no work owed" as success is
          // intentional, not a swallowed failure.
          if (c == null) return null;
          return UnifiedDiscardContext(
            userId: c.userId,
            organizationId: c.organizationId,
          );
        },
        acquireSongDiscardLease: (ctx) => ref
            .read(songMutationSyncControllerProvider)
            .acquireDiscardLease(
              SongMutationContext(
                userId: ctx.userId,
                organizationId: ctx.organizationId,
              ),
            ),
        discardSongsWhileOwned: (ctx, lease) async {
          final link = ref.keepAlive();
          try {
            final entries = await ref.read(songMutationEntriesProvider.future);
            for (final entry in entries) {
              try {
                await lease.discardMine(songId: entry.id);
              } catch (_) {
                // Ownership is already held, so entry failures remain
                // best-effort without exposing a partial batch to sync.
              }
            }
            ref.invalidate(songMutationEntriesProvider);
            ref.invalidate(songLibraryListProvider);
          } finally {
            link.close();
          }
        },
        discardPlanning: (ctx) async {
          final link = ref.keepAlive();
          try {
            final planningContext = ref.read(activePlanningContextProvider);
            if (planningContext == null ||
                planningContext.userId != ctx.userId ||
                planningContext.organizationId != ctx.organizationId) {
              return;
            }
            final entries = await ref.read(
              planningMutationEntriesProvider.future,
            );
            final controller = ref.read(planningMutationSyncControllerProvider);
            for (final entry in entries) {
              try {
                await controller.discardMutation(
                  planningContext,
                  aggregateType: entry.kind.aggregateType,
                  aggregateId: entry.aggregateId,
                );
              } catch (_) {
                // best-effort: continue discarding remaining entries
              }
            }
            ref.read(planningDataRevisionProvider.notifier).state += 1;
            ref.invalidate(planningMutationEntriesProvider);
            ref.invalidate(planningPlanListProvider);
          } finally {
            link.close();
          }
        },
      );
    });

/// The `ref` half of the popup's per-row keep/discard/apply-to-group
/// actions -- see UnifiedRowRecoveryController's doc comment. Each step
/// takes `ref.keepAlive()` before its first `await` and releases it in a
/// `finally`, exactly like unifiedDiscardControllerProvider above, so the
/// mutation, the revision bump and the invalidations all still happen even
/// if the popup that started them has since closed.
final unifiedRowRecoveryControllerProvider =
    Provider.autoDispose<UnifiedRowRecoveryController>((ref) {
      return UnifiedRowRecoveryController(
        keepMineStep: (songId) async {
          final link = ref.keepAlive();
          try {
            final activeContext = ref.read(activeCatalogContextProvider);
            if (activeContext == null) return false;
            final songContext = SongMutationContext(
              userId: activeContext.userId,
              organizationId: activeContext.organizationId,
            );
            var hadFailure = false;
            try {
              await ref
                  .read(songMutationSyncControllerProvider)
                  .keepMine(songContext, songId: songId);
            } catch (_) {
              hadFailure = true;
            }
            ref.invalidate(songMutationEntriesProvider);
            ref.invalidate(songLibraryListProvider);
            return hadFailure;
          } finally {
            link.close();
          }
        },
        discardMineStep: (songId) async {
          final link = ref.keepAlive();
          try {
            final activeContext = ref.read(activeCatalogContextProvider);
            if (activeContext == null) {
              return UnifiedRowDiscardResult.discarded;
            }
            final songContext = SongMutationContext(
              userId: activeContext.userId,
              organizationId: activeContext.organizationId,
            );
            try {
              final result = await ref
                  .read(songMutationSyncControllerProvider)
                  .discardMine(songContext, songId: songId);
              ref.invalidate(songMutationEntriesProvider);
              ref.invalidate(songLibraryListProvider);
              return switch (result) {
                SongDiscardResult.discarded =>
                  UnifiedRowDiscardResult.discarded,
                SongDiscardResult.syncInProgress =>
                  UnifiedRowDiscardResult.syncInProgress,
              };
            } catch (_) {
              ref.invalidate(songMutationEntriesProvider);
              ref.invalidate(songLibraryListProvider);
              return UnifiedRowDiscardResult.failed;
            }
          } finally {
            link.close();
          }
        },
        applyToGroupStep: (refs, {required retry}) async {
          final link = ref.keepAlive();
          try {
            final planningContext = ref.read(activePlanningContextProvider);
            if (planningContext == null) return false;
            final controller = ref.read(planningMutationSyncControllerProvider);
            var hadFailure = false;
            for (final mref in refs) {
              try {
                if (retry) {
                  await controller.retryMutation(
                    planningContext,
                    aggregateType: mref.aggregateType,
                    aggregateId: mref.aggregateId,
                  );
                } else {
                  await controller.discardMutation(
                    planningContext,
                    aggregateType: mref.aggregateType,
                    aggregateId: mref.aggregateId,
                  );
                }
              } catch (_) {
                hadFailure = true;
              }
            }
            ref.read(planningDataRevisionProvider.notifier).state += 1;
            ref.invalidate(planningMutationEntriesProvider);
            ref.invalidate(planningPlanListProvider);
            return hadFailure;
          } finally {
            link.close();
          }
        },
      );
    });
