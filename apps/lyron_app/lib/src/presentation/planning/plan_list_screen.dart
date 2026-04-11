import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/planning/planning_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class PlanListScreen extends ConsumerWidget {
  const PlanListScreen({super.key});

  static const _contentWidth = 720.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(planningPlanListProvider);
    final mutationsAsync = ref.watch(planningMutationEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.planListTitle),
        actions: [
          TextButton(
            onPressed: () => _createPlan(context, ref),
            child: const Text(AppStrings.planCreateAction),
          ),
        ],
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentWidth),
            child: Column(
              children: [
                mutationsAsync.when(
                  data: (entries) => entries.isEmpty
                      ? const SizedBox.shrink()
                      : _PlanningMutationStatusSurface(entries: entries),
                  error: (_, _) => const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                ),
                Expanded(
                  child: plansAsync.when(
                    loading: () => const Center(
                      child: Text(AppStrings.planListLoadingMessage),
                    ),
                    error: (error, stackTrace) => _RetryableErrorState(
                      message: AppStrings.planListLoadFailureMessage,
                      onRetry: () => ref.invalidate(planningPlanListProvider),
                    ),
                    data: (plans) {
                      if (plans.isEmpty) {
                        return const Center(
                          child: Text(AppStrings.planListEmptyMessage),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.all(24),
                        itemCount: plans.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final plan = plans[index];

                          return ListTile(
                            title: Text(plan.name),
                            subtitle: _PlanSummarySubtitle(plan: plan),
                            onTap: () => context.push(
                              PlanningRoutes.planDetailLocation(plan.slug),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _createPlan(BuildContext context, WidgetRef ref) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }

    final draft = await showDialog<PlanCreateDraft>(
      context: context,
      builder: (context) => const _PlanEditorDialog(),
    );
    if (draft == null) {
      return;
    }

    final mutation = await ref
        .read(planningWriteServiceProvider)
        .createPlan(
          context: PlanningWriteContext(
            userId: activeContext.userId,
            organizationId: activeContext.organizationId,
          ),
          draft: draft,
        );
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    final plans = await ref.read(planningPlanListProvider.future);
    final routeSlug = plans
            .where((candidate) => candidate.id == mutation.aggregateId)
            .map((candidate) => candidate.slug)
            .firstOrNull ??
        mutation.slug ??
        mutation.aggregateId;
    if (!context.mounted) {
      return;
    }
    context.push(PlanningRoutes.planDetailLocation(routeSlug));
  }
}

class _PlanningMutationStatusSurface extends ConsumerWidget {
  const _PlanningMutationStatusSurface({required this.entries});

  final List<PlanningMutationRecord> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(
        children: entries
            .map(
              (entry) => Card(
                child: ListTile(
                  title: Text(entry.name ?? entry.slug ?? entry.aggregateId),
                  subtitle: Text(_messageFor(entry)),
                  trailing: entry.syncStatus == PlanningMutationSyncStatus.pending
                      ? null
                      : TextButton(
                          onPressed: () => _retryEntry(context, ref, entry),
                          child: const Text(AppStrings.retryAction),
                        ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> _retryEntry(
    BuildContext context,
    WidgetRef ref,
    PlanningMutationRecord entry,
  ) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }

    await ref
        .read(planningMutationSyncControllerProvider)
        .retryMutation(activeContext, aggregateId: entry.aggregateId);
    ref.read(planningDataRevisionProvider.notifier).state += 1;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
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

class _PlanEditorDialog extends StatefulWidget {
  const _PlanEditorDialog();

  @override
  State<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<_PlanEditorDialog> {
  late final TextEditingController _nameController = TextEditingController();
  late final TextEditingController _descriptionController =
      TextEditingController();
  late final TextEditingController _scheduledForController =
      TextEditingController();
  String? _scheduledForError;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _scheduledForController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.planEditorTitleCreate),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('plan-editor-name'),
              controller: _nameController,
              decoration: const InputDecoration(labelText: AppStrings.planNameLabel),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('plan-editor-description'),
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: AppStrings.planDescriptionLabel,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('plan-editor-scheduled-for'),
              controller: _scheduledForController,
              decoration: InputDecoration(
                labelText: AppStrings.planScheduledForLabel,
                errorText: _scheduledForError,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.songCancelAction),
        ),
        FilledButton(
          onPressed: () {
            final scheduledFor = _tryParseScheduledFor();
            if (_scheduledForController.text.trim().isNotEmpty &&
                scheduledFor == null) {
              setState(() {
                _scheduledForError = AppStrings.planScheduledForInvalidMessage;
              });
              return;
            }
            Navigator.of(context).pop(
              PlanCreateDraft(
                name: _nameController.text.trim(),
                description: _normalizeText(_descriptionController.text),
                scheduledFor: scheduledFor,
              ),
            );
          },
          child: const Text(AppStrings.planSaveAction),
        ),
      ],
    );
  }

  DateTime? _tryParseScheduledFor() {
    try {
      return _parseOptionalDateTime(_scheduledForController.text);
    } on FormatException {
      return null;
    }
  }
}

String? _normalizeText(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

DateTime? _parseOptionalDateTime(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return null;
  }

  return DateTime.parse(normalized).toUtc();
}

class _PlanSummarySubtitle extends StatelessWidget {
  const _PlanSummarySubtitle({required this.plan});

  final PlanSummary plan;

  @override
  Widget build(BuildContext context) {
    final scheduledFor = plan.scheduledFor;
    if (scheduledFor == null) {
      return const Text(AppStrings.planListUnscheduledLabel);
    }

    return Text(scheduledFor.toIso8601String());
  }
}

class _RetryableErrorState extends StatelessWidget {
  const _RetryableErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: const Text(AppStrings.retryAction),
          ),
        ],
      ),
    );
  }
}
