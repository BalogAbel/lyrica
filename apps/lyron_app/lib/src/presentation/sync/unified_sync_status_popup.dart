import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
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

class _SongRowTile extends StatelessWidget {
  const _SongRowTile({required this.row});

  final UnifiedSyncSongRow row;

  @override
  Widget build(BuildContext context) {
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
    );
  }

  String _songStateLabel(Object state) {
    final name = state.toString();
    if (name.contains('pendingCreate')) {
      return AppStrings.unifiedSyncSongStateCreated;
    }
    if (name.contains('pendingUpdate')) {
      return AppStrings.unifiedSyncSongStateEdited;
    }
    if (name.contains('pendingDelete')) {
      return AppStrings.unifiedSyncSongStateRemoved;
    }
    if (name.contains('conflict')) {
      return AppStrings.unifiedSyncSongStateEditedConflict;
    }
    return AppStrings.unifiedSyncSongStateEdited;
  }
}

class _PlanRowTile extends StatelessWidget {
  const _PlanRowTile({required this.row});

  final UnifiedSyncPlanRow row;

  @override
  Widget build(BuildContext context) {
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
    );
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
