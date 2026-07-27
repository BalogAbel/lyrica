import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_reorder_overlay.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_context_checks.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/planning/planning_routes.dart';
import 'package:lyron_app/src/presentation/planning/widgets/plan_editor_dialog.dart';
import 'package:lyron_app/src/presentation/planning/widgets/plan_session_card.dart';
import 'package:lyron_app/src/presentation/planning/widgets/planning_workspace_shell.dart';
import 'package:lyron_app/src/presentation/planning/widgets/retryable_error_state.dart';
import 'package:lyron_app/src/presentation/planning/widgets/scheduled_for_field.dart';
import 'package:lyron_app/src/presentation/planning/widgets/session_editor_dialog.dart';
import 'package:lyron_app/src/presentation/shared/if_capability.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_header_control.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class PlanDetailScreen extends ConsumerStatefulWidget {
  const PlanDetailScreen({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends ConsumerState<PlanDetailScreen> {
  PlanDetail? _latestPlanDetail;
  List<String>? _optimisticSessionOrder;
  var _sessionReorderGeneration = 0;
  var _lastCompletedSessionReorderGeneration = 0;
  Future<void> _sessionReorderTail = Future<void>.value();

  String get planId => widget.planId;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final detailAsync = ref.watch(planningPlanDetailProvider(planId));
    final orgId = ref.watch(activePlanningContextProvider)?.organizationId;

    return PlanningWorkspaceShell(
      title: AppStrings.planDetailTitle,
      headerSyncControl: const UnifiedSyncHeaderControl(),
      leading: BackButton(
        onPressed: () {
          if (context.canPop()) {
            context.pop();
            return;
          }
          context.go(PlanningRoutes.planListPath);
        },
      ),
      actions: [
        IfCapability(
          key: const Key('plan-edit-button'),
          capability: Capability.managePlans,
          organizationId: orgId,
          child: IconButton(
            tooltip: AppStrings.planEditAction,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editPlan(context, ref),
          ),
        ),
        IfCapability(
          key: const Key('session-create-button'),
          capability: Capability.editSessions,
          organizationId: orgId,
          child: IconButton(
            tooltip: AppStrings.sessionCreateAction,
            icon: const Icon(Icons.playlist_add),
            onPressed: () => _createSession(context, ref),
          ),
        ),
      ],
      body: detailAsync.when(
        skipLoadingOnReload: true,
        loading: () =>
            const Center(child: Text(AppStrings.planDetailLoadingMessage)),
        error: (error, stackTrace) => RetryableErrorState(
          message: AppStrings.planDetailLoadFailureMessage,
          onRetry: () => ref.invalidate(planningPlanDetailProvider(planId)),
        ),
        data: (PlanDetail detail) {
          _latestPlanDetail = detail;
          // Resolve (and, if settled, drop) the overlay against this fresh
          // projection before it is used to order the list below. This runs
          // during build, so the field is assigned directly rather than via
          // setState — the current build already sees the resolved value.
          _optimisticSessionOrder = resolveReorderOverlay(
            optimisticOrder: _optimisticSessionOrder,
            projectionOrder: [
              for (final session in detail.sessions) session.id,
            ],
            hasWriteInFlight:
                _sessionReorderGeneration !=
                _lastCompletedSessionReorderGeneration,
          );
          final sessions = _orderedSessions(detail);
          final orderedDetail = PlanDetail(
            plan: detail.plan,
            sessions: sessions,
          );
          return ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: EdgeInsets.zero,
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.plan.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if ((detail.plan.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(detail.plan.description!),
                ],
                if (detail.plan.scheduledFor != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _formatScheduledFor(context, detail.plan.scheduledFor!),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (sessions.isEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(AppStrings.sessionListEmptyMessage),
                ],
                const SizedBox(height: 20),
              ],
            ),
            itemCount: sessions.length,
            onReorder: (oldIndex, newIndex) =>
                _reorderSessions(ref, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final session = sessions[index];
              return PlanSessionCard(
                key: ValueKey(session.id),
                planDetail: orderedDetail,
                session: session,
                sessionIndex: index,
              );
            },
          );
        },
      ),
    );
  }

  List<SessionSummary> _orderedSessions(PlanDetail detail) {
    final order = _optimisticSessionOrder;
    if (order == null || order.length != detail.sessions.length) {
      return detail.sessions;
    }
    final sessionsById = {
      for (final session in detail.sessions) session.id: session,
    };
    if (sessionsById.length != order.length) {
      return detail.sessions;
    }
    for (final sessionId in order) {
      if (!sessionsById.containsKey(sessionId)) {
        return detail.sessions;
      }
    }
    return [for (final sessionId in order) sessionsById[sessionId]!];
  }

  Future<void> _editPlan(BuildContext context, WidgetRef ref) async {
    final activeContext = ref.read(activePlanningContextProvider);
    final detail = await ref.read(planningPlanDetailProvider(planId).future);
    if (activeContext == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final draft = await showDialog<PlanEditDraft>(
      context: context,
      builder: (context) => PlanEditorDialog(
        planId: detail.plan.id,
        initialName: detail.plan.name,
        initialDescription: detail.plan.description,
        initialScheduledFor: detail.plan.scheduledFor,
      ),
    );
    if (draft == null) {
      return;
    }

    final currentContext = ref.read(activePlanningContextProvider);
    if (currentContext == null ||
        !samePlanningContext(activeContext, currentContext)) {
      return;
    }

    if (!context.mounted) return;
    await ref
        .read(planningWriteServiceProvider)
        .editPlan(
          context: PlanningWriteContext(
            userId: currentContext.userId,
            organizationId: currentContext.organizationId,
          ),
          draft: draft,
        );

    if (!context.mounted) return;
    ref.read(planningDataRevisionProvider.notifier).state += 1;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planId));
  }

  Future<void> _createSession(BuildContext context, WidgetRef ref) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }

    final draft = await showDialog<String>(
      context: context,
      builder: (context) => const SessionEditorDialog(),
    );
    if (draft == null) {
      return;
    }

    final currentContext = ref.read(activePlanningContextProvider);
    if (currentContext == null ||
        !samePlanningContext(activeContext, currentContext)) {
      return;
    }

    if (!context.mounted) return;
    await ref
        .read(planningWriteServiceProvider)
        .createSession(
          context: PlanningWriteContext(
            userId: currentContext.userId,
            organizationId: currentContext.organizationId,
          ),
          draft: SessionCreateDraft(planId: planId, name: draft),
        );

    if (!context.mounted) return;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planId));
  }

  void _reorderSessions(WidgetRef ref, int oldIndex, int newIndex) {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }

    final planDetail = _latestPlanDetail;
    if (planDetail == null) {
      return;
    }
    final currentOrder = _orderedSessions(
      planDetail,
    ).map((value) => value.id).toList();
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (oldIndex < 0 ||
        oldIndex >= currentOrder.length ||
        newIndex < 0 ||
        newIndex >= currentOrder.length ||
        oldIndex == newIndex) {
      return;
    }
    final movedId = currentOrder.removeAt(oldIndex);
    currentOrder.insert(newIndex, movedId);
    final generation = ++_sessionReorderGeneration;

    setState(() {
      _optimisticSessionOrder = currentOrder;
    });

    final writeContext = PlanningWriteContext(
      userId: activeContext.userId,
      organizationId: activeContext.organizationId,
    );
    final planId = planDetail.plan.id;
    final queued = _sessionReorderTail.then(
      (_) => _performSessionReorder(
        ref,
        writeContext,
        planId,
        currentOrder,
        generation,
      ),
    );
    _sessionReorderTail = queued.catchError((error, stackTrace) {
      _reportReorderError(
        error,
        stackTrace,
        library: 'planning session reorder queue',
      );
    });
    unawaited(_sessionReorderTail);
  }

  Future<void> _performSessionReorder(
    WidgetRef ref,
    PlanningWriteContext writeContext,
    String planId,
    List<String> currentOrder,
    int generation,
  ) async {
    try {
      await ref
          .read(planningWriteServiceProvider)
          .reorderSessions(
            context: writeContext,
            draft: SessionReorderDraft(
              planId: planId,
              orderedSessionIds: currentOrder,
            ),
          );
    } catch (error, stackTrace) {
      if (mounted && generation == _sessionReorderGeneration) {
        setState(() {
          _optimisticSessionOrder = null;
          _lastCompletedSessionReorderGeneration = generation;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.planningReorderFailedMessage),
          ),
        );
      }
      if (generation != _sessionReorderGeneration) {
        return;
      }
      _reportReorderError(
        error,
        stackTrace,
        library: 'planning session reorder',
      );
      return;
    }

    if (generation != _sessionReorderGeneration) {
      return;
    }
    _lastCompletedSessionReorderGeneration = generation;
    if (!mounted) return;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planId));
  }

  void _reportReorderError(
    Object error,
    StackTrace stackTrace, {
    required String library,
  }) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: library,
      ),
    );
  }
}

String _formatScheduledFor(BuildContext context, DateTime scheduledFor) {
  return formatScheduledForInstant(context, scheduledFor);
}
