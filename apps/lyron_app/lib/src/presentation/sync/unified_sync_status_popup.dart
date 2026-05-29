import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/sync/unified_discard_controller.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class UnifiedSyncStatusPopup extends ConsumerWidget {
  const UnifiedSyncStatusPopup({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const UnifiedSyncStatusPopup(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(unifiedSyncOverviewProvider);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStrings.unifiedSyncPopupTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (overview.hasUnsyncedWork) ...[
                    TextButton(
                      key: const ValueKey('unified-sync-popup-discard-all'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => unawaited(
                        _confirmDiscardAll(context, ref, overview),
                      ),
                      child: const Text(AppStrings.unifiedSyncDiscardAllAction),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton.icon(
                    key: const ValueKey('unified-sync-popup-sync-now'),
                    onPressed: () {
                      unawaited(
                        ref.read(unifiedManualSyncControllerProvider).syncNow(),
                      );
                    },
                    icon: const Icon(Icons.sync),
                    label: const Text(AppStrings.unifiedSyncNowAction),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(child: _PopupBody(overview: overview)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDiscardAll(
    BuildContext context,
    WidgetRef ref,
    UnifiedSyncOverview overview,
  ) async {
    final songCount = overview.songRows.length;
    final planCount = overview.planRows.length;
    final message =
        '${AppStrings.unifiedSyncDiscardAllMessagePrefix} '
        '($songCount songs, $planCount plans). This cannot be undone.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.unifiedSyncDiscardAllTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.songCancelAction),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.unifiedSyncDiscardAllConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    await ref.read(unifiedDiscardControllerProvider).discardAll();
  }
}

class _PopupBody extends StatelessWidget {
  const _PopupBody({required this.overview});

  final UnifiedSyncOverview overview;

  @override
  Widget build(BuildContext context) {
    if (!overview.hasUnsyncedWork) {
      return const Center(
        key: ValueKey('unified-sync-popup-empty'),
        child: Text(AppStrings.unifiedSyncEmptyMessage),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        if (overview.songRows.isNotEmpty) ...[
          Text(
            AppStrings.unifiedSyncSongsHeading,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final row in overview.songRows) _SongRowTile(row: row),
          const SizedBox(height: 12),
        ],
        if (overview.planRows.isNotEmpty) ...[
          Text(
            AppStrings.unifiedSyncPlansHeading,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final row in overview.planRows) _PlanRowTile(row: row),
        ],
      ],
    );
  }
}

class _SongRowTile extends ConsumerWidget {
  const _SongRowTile({required this.row});

  final UnifiedSyncSongRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: ValueKey('unified-sync-song-row-${row.songId}'),
      title: Text(row.title),
      subtitle: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          _StateChip(label: _songStateLabel(row.entityState)),
          _ReasonChip(reason: row.reasonCode),
        ],
      ),
      trailing: row.severity == UnifiedSyncRowSeverity.conflict
          ? Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: ValueKey('unified-sync-song-keep-${row.songId}'),
                  onPressed: () => unawaited(_keepMine(ref)),
                  child: const Text(AppStrings.songKeepMineAction),
                ),
                TextButton(
                  key: ValueKey('unified-sync-song-discard-${row.songId}'),
                  onPressed: () => unawaited(_discardMine(ref)),
                  child: const Text(AppStrings.songDiscardMineAction),
                ),
              ],
            )
          : null,
    );
  }

  SongMutationContext? _context(WidgetRef ref) {
    final c = ref.read(activeCatalogContextProvider);
    if (c == null) return null;
    return SongMutationContext(
      userId: c.userId,
      organizationId: c.organizationId,
    );
  }

  Future<void> _keepMine(WidgetRef ref) async {
    final ctx = _context(ref);
    if (ctx == null) return;
    await ref
        .read(songMutationSyncControllerProvider)
        .keepMine(ctx, songId: row.songId);
    ref.invalidate(songMutationEntriesProvider);
    ref.invalidate(songLibraryListProvider);
  }

  Future<void> _discardMine(WidgetRef ref) async {
    final ctx = _context(ref);
    if (ctx == null) return;
    await ref
        .read(songMutationSyncControllerProvider)
        .discardMine(ctx, songId: row.songId);
    ref.invalidate(songMutationEntriesProvider);
    ref.invalidate(songLibraryListProvider);
  }

  String _songStateLabel(SongSyncStatus state) {
    return switch (state) {
      SongSyncStatus.pendingCreate => AppStrings.unifiedSyncSongStateCreated,
      SongSyncStatus.pendingDelete => AppStrings.unifiedSyncSongStateRemoved,
      SongSyncStatus.conflict => AppStrings.unifiedSyncSongStateEditedConflict,
      SongSyncStatus.pendingUpdate ||
      SongSyncStatus.synced => AppStrings.unifiedSyncSongStateEdited,
    };
  }
}

class _PlanRowTile extends ConsumerWidget {
  const _PlanRowTile({required this.row});

  final UnifiedSyncPlanRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: ValueKey('unified-sync-plan-row-${row.planId}'),
      title: Text(row.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReasonChip(reason: row.reasonCode),
          for (final entry in row.nestedSummaries)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $entry',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
      trailing: _actions(ref),
    );
  }

  Widget? _actions(WidgetRef ref) {
    return switch (row.severity) {
      UnifiedSyncRowSeverity.conflict => Wrap(
          spacing: 8,
          children: [
            TextButton(
              key: ValueKey('unified-sync-plan-keep-${row.planId}'),
              onPressed: () => unawaited(_applyToGroup(ref, retry: true)),
              child: const Text(AppStrings.songKeepMineAction),
            ),
            TextButton(
              key: ValueKey('unified-sync-plan-discard-${row.planId}'),
              onPressed: () => unawaited(_applyToGroup(ref, retry: false)),
              child: const Text(AppStrings.songDiscardMineAction),
            ),
          ],
        ),
      UnifiedSyncRowSeverity.retryableFailure => TextButton(
          key: ValueKey('unified-sync-plan-retry-${row.planId}'),
          onPressed: () => unawaited(_applyToGroup(ref, retry: true)),
          child: const Text(AppStrings.retryAction),
        ),
      UnifiedSyncRowSeverity.pending => null,
    };
  }

  Future<void> _applyToGroup(WidgetRef ref, {required bool retry}) async {
    final ctx = ref.read(activePlanningContextProvider);
    if (ctx == null) return;
    final controller = ref.read(planningMutationSyncControllerProvider);
    for (final mref in row.mutationRefs) {
      if (retry) {
        await controller.retryMutation(
          ctx,
          aggregateType: mref.aggregateType,
          aggregateId: mref.aggregateId,
        );
      } else {
        await controller.discardMutation(
          ctx,
          aggregateType: mref.aggregateType,
          aggregateId: mref.aggregateId,
        );
      }
    }
    ref.read(planningDataRevisionProvider.notifier).state += 1;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label), visualDensity: VisualDensity.compact);
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.reason});
  final UnifiedSyncReasonCode reason;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (reason) {
      UnifiedSyncReasonCode.pendingLocal => (
        AppStrings.unifiedSyncReasonPendingLocal,
        scheme.tertiary,
      ),
      UnifiedSyncReasonCode.syncFailed => (
        AppStrings.unifiedSyncReasonSyncFailed,
        Colors.amber.shade800,
      ),
      UnifiedSyncReasonCode.conflict => (
        AppStrings.unifiedSyncReasonConflict,
        scheme.error,
      ),
      UnifiedSyncReasonCode.authorizationDenied => (
        AppStrings.unifiedSyncReasonAuthorizationDenied,
        scheme.error,
      ),
      UnifiedSyncReasonCode.dependencyBlocked => (
        AppStrings.unifiedSyncReasonDependencyBlocked,
        scheme.error,
      ),
      UnifiedSyncReasonCode.remoteMissing => (
        AppStrings.unifiedSyncReasonRemoteMissing,
        scheme.error,
      ),
      UnifiedSyncReasonCode.unknown => (
        AppStrings.unifiedSyncReasonUnknown,
        Colors.amber.shade800,
      ),
    };
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color),
    );
  }
}
