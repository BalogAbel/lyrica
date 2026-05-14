import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/sync/foreground_sync_listener.dart';
import 'package:lyron_app/src/application/sync/online_transition_detector.dart';
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
  return computeUnifiedSyncOverview(
    UnifiedSyncOverviewInputs(
      catalog: catalog,
      songEntries: songEntries,
      planning: planning,
      planningEntries: planningEntries,
      planTitles: planTitles,
    ),
  );
});

final unifiedManualSyncControllerProvider =
    Provider.autoDispose<UnifiedManualSyncController>((ref) {
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
      ref.onDispose(controller.dispose);
      return controller;
    });

final onlineTransitionDetectorProvider = Provider<OnlineTransitionDetector>((
  ref,
) {
  final detector = OnlineTransitionDetector(
    onTransitionToOnline: () {
      ref.read(unifiedManualSyncControllerProvider).syncNow();
    },
    triggerWhenClean: false,
    hasUnsyncedWorkReader: () =>
        ref.read(unifiedSyncOverviewProvider).hasUnsyncedWork,
  );

  ref.listen(catalogSnapshotStateProvider, (_, next) {
    detector.updateCatalog(next);
  });
  ref.listen(planningSyncStateProvider, (_, next) {
    detector.updatePlanning(next);
  });
  return detector;
});

final foregroundSyncListenerProvider = Provider<ForegroundSyncListener>((ref) {
  final listener = ForegroundSyncListener(
    foregroundState: ref.watch(appForegroundStateProvider),
    onResume: () async {
      await ref.read(unifiedManualSyncControllerProvider).syncNow();
    },
  );
  ref.onDispose(listener.dispose);
  return listener;
});
