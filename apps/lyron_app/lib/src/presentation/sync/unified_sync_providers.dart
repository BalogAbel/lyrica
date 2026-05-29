import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/sync/foreground_sync_listener.dart';
import 'package:lyron_app/src/application/sync/online_transition_detector.dart';
import 'package:lyron_app/src/application/sync/unified_discard_controller.dart';
import 'package:lyron_app/src/application/sync/unified_manual_sync_controller.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';

final planningPlanTitlesProvider = Provider.autoDispose<Map<String, String>>((
  ref,
) {
  final summaries = ref.watch(planningPlanListProvider).valueOrNull;
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

final unifiedSyncOverviewProvider = Provider.autoDispose<UnifiedSyncOverview>((
  ref,
) {
  final catalog = _safeWatch(
    () => ref.watch(catalogSnapshotStateProvider),
    const CatalogSnapshotState.initial(),
  );
  final songEntries = _safeWatch(
    () =>
        ref.watch(songMutationEntriesProvider).valueOrNull ??
        const <SongMutationRecord>[],
    const <SongMutationRecord>[],
  );
  final planning = _safeWatch(
    () => ref.watch(planningSyncStateProvider),
    const PlanningSyncState.initial(),
  );
  final planningEntries = _safeWatch(
    () =>
        ref.watch(planningMutationEntriesProvider).valueOrNull ??
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

  return computeUnifiedSyncOverview(
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
          if (c == null) return null;
          return UnifiedDiscardContext(
            userId: c.userId,
            organizationId: c.organizationId,
          );
        },
        discardSongs: (ctx) async {
          final entries = await ref.read(songMutationEntriesProvider.future);
          final controller = ref.read(songMutationSyncControllerProvider);
          final songContext = SongMutationContext(
            userId: ctx.userId,
            organizationId: ctx.organizationId,
          );
          for (final entry in entries) {
            try {
              await controller.discardMine(songContext, songId: entry.id);
            } catch (_) {
              // best-effort: continue discarding remaining entries
            }
          }
          ref.invalidate(songMutationEntriesProvider);
          ref.invalidate(songLibraryListProvider);
        },
        discardPlanning: (ctx) async {
          final planningContext = ref.read(activePlanningContextProvider);
          if (planningContext == null ||
              planningContext.userId != ctx.userId ||
              planningContext.organizationId != ctx.organizationId) {
            return;
          }
          final entries =
              await ref.read(planningMutationEntriesProvider.future);
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
        },
      );
    });
