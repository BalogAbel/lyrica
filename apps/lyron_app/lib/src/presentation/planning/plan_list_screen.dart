import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_context_checks.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/planning/planning_routes.dart';
import 'package:lyron_app/src/presentation/planning/widgets/planning_workspace_shell.dart';
import 'package:lyron_app/src/presentation/shared/if_capability.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_header_control.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class PlanListScreen extends ConsumerWidget {
  const PlanListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(planningPlanListProvider);
    final orgId = ref.watch(activePlanningContextProvider)?.organizationId;

    return PlanningWorkspaceShell(
      title: AppStrings.planListTitle,
      headerSyncControl: const UnifiedSyncHeaderControl(),
      leading: context.canPop()
          ? BackButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                }
              },
            )
          : null,
      actions: [
        IfCapability(
          key: const Key('plan-create-button'),
          capability: Capability.managePlans,
          organizationId: orgId,
          child: IconButton(
            tooltip: AppStrings.planCreateAction,
            icon: const Icon(Icons.add),
            onPressed: () => _createPlan(context, ref),
          ),
        ),
      ],
      body: plansAsync.when(
        skipLoadingOnReload: true,
        loading: () =>
            const Center(child: Text(AppStrings.planListLoadingMessage)),
        error: (error, stackTrace) => _RetryableErrorState(
          message: AppStrings.planListLoadFailureMessage,
          onRetry: () => ref.invalidate(planningPlanListProvider),
        ),
        data: (plans) {
          if (plans.isEmpty) {
            return const Center(child: Text(AppStrings.planListEmptyMessage));
          }

          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: plans.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final plan = plans[index];

              return ListTile(
                title: Text(plan.name),
                subtitle: _PlanSummarySubtitle(plan: plan),
                onTap: () =>
                    context.push(PlanningRoutes.planDetailLocation(plan.slug)),
              );
            },
          );
        },
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

    final currentContext = ref.read(activePlanningContextProvider);
    if (currentContext == null ||
        !samePlanningContext(activeContext, currentContext)) {
      return;
    }

    final mutation = await ref
        .read(planningWriteServiceProvider)
        .createPlan(
          context: PlanningWriteContext(
            userId: currentContext.userId,
            organizationId: currentContext.organizationId,
          ),
          draft: draft,
        );
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    final plans = await ref.read(planningPlanListProvider.future);
    final routeSlug =
        plans
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

class _PlanEditorDialog extends ConsumerStatefulWidget {
  const _PlanEditorDialog();

  @override
  ConsumerState<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends ConsumerState<_PlanEditorDialog> {
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
    ref.listen(activePlanningContextProvider, (previous, next) {
      if (!mounted || previous == next) {
        return;
      }

      if (Navigator.of(context).canPop()) {
        Navigator.of(context).maybePop();
      }
    });

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
              decoration: const InputDecoration(
                labelText: AppStrings.planNameLabel,
              ),
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
    final description = plan.description?.trim();
    final scheduledFor = plan.scheduledFor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (description != null && description.isNotEmpty) Text(description),
        if (scheduledFor == null)
          const Text(AppStrings.planListUnscheduledLabel)
        else
          Text(_formatScheduledFor(context, scheduledFor)),
      ],
    );
  }
}

String _formatScheduledFor(BuildContext context, DateTime scheduledFor) {
  return MaterialLocalizations.of(
    context,
  ).formatMediumDate(scheduledFor.toLocal());
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
