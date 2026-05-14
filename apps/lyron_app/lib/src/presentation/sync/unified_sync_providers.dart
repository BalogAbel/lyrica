import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/sync/unified_manual_sync_controller.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_library/song_library_providers.dart';

final planningPlanTitlesProvider = Provider.autoDispose<Map<String, String>>((
  ref,
) {
  final summaries = ref.watch(planningPlanListProvider).valueOrNull;
  if (summaries == null) return const {};
  return {for (final summary in summaries) summary.id: summary.name};
});

final unifiedSyncOverviewProvider = Provider.autoDispose<UnifiedSyncOverview>((
  ref,
) {
  final catalog = ref.watch(catalogSnapshotStateProvider);
  final songEntries =
      ref.watch(songMutationEntriesProvider).valueOrNull ??
          const <SongMutationRecord>[];
  final planning = ref.watch(planningSyncStateProvider);
  final planningEntries =
      ref.watch(planningMutationEntriesProvider).valueOrNull ??
          const <PlanningMutationRecord>[];
  final planTitles = ref.watch(planningPlanTitlesProvider);
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
