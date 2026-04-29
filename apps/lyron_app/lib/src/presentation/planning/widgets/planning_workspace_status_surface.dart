import 'package:flutter/material.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class PlanningWorkspaceStatusSurface extends StatelessWidget {
  const PlanningWorkspaceStatusSurface({
    super.key,
    required this.entries,
    required this.onRetry,
    required this.onKeepMine,
    required this.onDiscardMine,
  });

  final List<PlanningMutationRecord> entries;
  final Future<void> Function(PlanningMutationRecord entry) onRetry;
  final Future<void> Function(PlanningMutationRecord entry) onKeepMine;
  final Future<void> Function(PlanningMutationRecord entry) onDiscardMine;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.name ?? entry.slug ?? entry.aggregateId,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(_messageFor(entry)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      _ActionCluster(
                        entry: entry,
                        onRetry: onRetry,
                        onKeepMine: onKeepMine,
                        onDiscardMine: onDiscardMine,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  String _messageFor(PlanningMutationRecord entry) {
    return switch (entry.errorCode) {
      PlanningMutationSyncErrorCode.authorizationDenied =>
        AppStrings.planAuthorizationRevokedMessage,
      PlanningMutationSyncErrorCode.dependencyBlocked =>
        AppStrings.sessionDeleteBlockedMessage,
      PlanningMutationSyncErrorCode.remoteMissing =>
        AppStrings.planRemoteMissingMessage,
      PlanningMutationSyncErrorCode.conflict => AppStrings.planConflictMessage,
      PlanningMutationSyncErrorCode.connectivityFailure =>
        AppStrings.planMutationPendingMessage,
      PlanningMutationSyncErrorCode.unknown =>
        entry.errorMessage ?? AppStrings.planMutationPendingMessage,
      null => entry.errorMessage ?? AppStrings.planMutationPendingMessage,
    };
  }
}

class _ActionCluster extends StatelessWidget {
  const _ActionCluster({
    required this.entry,
    required this.onRetry,
    required this.onKeepMine,
    required this.onDiscardMine,
  });

  final PlanningMutationRecord entry;
  final Future<void> Function(PlanningMutationRecord entry) onRetry;
  final Future<void> Function(PlanningMutationRecord entry) onKeepMine;
  final Future<void> Function(PlanningMutationRecord entry) onDiscardMine;

  @override
  Widget build(BuildContext context) {
    if (entry.syncStatus == PlanningMutationSyncStatus.pending) {
      return const SizedBox.shrink();
    }

    if (entry.syncStatus == PlanningMutationSyncStatus.conflict) {
      return Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: () => onKeepMine(entry),
            child: const Text(AppStrings.songKeepMineAction),
          ),
          TextButton(
            onPressed: () => onDiscardMine(entry),
            child: const Text(AppStrings.songDiscardMineAction),
          ),
        ],
      );
    }

    return TextButton(
      onPressed: () => onRetry(entry),
      child: const Text(AppStrings.retryAction),
    );
  }
}
