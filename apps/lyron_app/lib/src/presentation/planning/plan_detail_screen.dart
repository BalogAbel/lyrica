import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/planning/planning_data_revision.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_context_checks.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/planning/planning_routes.dart';
import 'package:lyron_app/src/presentation/planning/session_song_picker.dart';
import 'package:lyron_app/src/presentation/planning/widgets/planning_workspace_shell.dart';
import 'package:lyron_app/src/presentation/planning/widgets/planning_workspace_status_surface.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class PlanDetailScreen extends ConsumerStatefulWidget {
  const PlanDetailScreen({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends ConsumerState<PlanDetailScreen> {
  List<String>? _optimisticSessionOrder;
  var _sessionReorderGeneration = 0;

  String get planId => widget.planId;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final detailAsync = ref.watch(planningPlanDetailProvider(planId));
    final mutationsAsync = ref.watch(planningMutationEntriesProvider);
    final mutationEntries =
        mutationsAsync.valueOrNull ?? const <PlanningMutationRecord>[];

    return PlanningWorkspaceShell(
      title: AppStrings.planDetailTitle,
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
        TextButton(
          onPressed: () => _editPlan(context, ref),
          child: const Text(AppStrings.planEditAction),
        ),
        TextButton(
          onPressed: () => _createSession(context, ref),
          child: const Text(AppStrings.sessionCreateAction),
        ),
      ],
      statusSurface: mutationsAsync.when(
        skipLoadingOnReload: true,
        data: (entries) {
          final relevantEntries = entries
              .where(
                (entry) =>
                    entry.aggregateId == planId || entry.planId == planId,
              )
              .toList(growable: false);
          if (relevantEntries.isEmpty) {
            return null;
          }
          return PlanningWorkspaceStatusSurface(
            entries: relevantEntries,
            onRetry: (entry) => _retryMutation(context, ref, entry),
            onKeepMine: (entry) => _keepMine(context, ref, entry),
            onDiscardMine: (entry) => _discardMine(context, ref, entry),
          );
        },
        error: (_, _) => null,
        loading: () => null,
      ),
      body: detailAsync.when(
        skipLoadingOnReload: true,
        loading: () =>
            const Center(child: Text(AppStrings.planDetailLoadingMessage)),
        error: (error, stackTrace) => _RetryableErrorState(
          message: AppStrings.planDetailLoadFailureMessage,
          onRetry: () => ref.invalidate(planningPlanDetailProvider(planId)),
        ),
        data: (PlanDetail detail) {
          final sessions = _orderedSessions(detail);
          final orderedDetail = PlanDetail(
            plan: detail.plan,
            sessions: sessions,
          );
          final planInlineStatus = planningInlineMutationStatusFor(
            mutationEntries.where(
              (entry) =>
                  entry.aggregateId == detail.plan.id &&
                  (entry.kind == PlanningMutationKind.planCreate ||
                      entry.kind == PlanningMutationKind.planEdit),
            ),
          );
          return ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: EdgeInsets.zero,
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      detail.plan.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (planInlineStatus != null)
                      PlanningInlineMutationStatusBadge(
                        key: ValueKey('plan-local-status-${detail.plan.id}'),
                        status: planInlineStatus,
                      ),
                  ],
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
            onReorder: (oldIndex, newIndex) => _reorderSessions(
              context,
              ref,
              orderedDetail,
              oldIndex,
              newIndex,
            ),
            itemBuilder: (context, index) {
              final session = sessions[index];
              return _SessionCard(
                key: ValueKey(session.id),
                planDetail: orderedDetail,
                session: session,
                sessionIndex: index,
                mutationEntries: mutationEntries,
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
      builder: (context) => _PlanEditorDialog(
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
      builder: (context) => const _SessionEditorDialog(),
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

  Future<void> _retryMutation(
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
        .retryMutation(
          activeContext,
          aggregateType: entry.kind.aggregateType,
          aggregateId: entry.aggregateId,
        );
    if (!context.mounted) {
      return;
    }
    ref.read(planningDataRevisionProvider.notifier).state += 1;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planId));
  }

  Future<void> _keepMine(
    BuildContext context,
    WidgetRef ref,
    PlanningMutationRecord entry,
  ) async {
    await _retryMutation(context, ref, entry);
  }

  Future<void> _discardMine(
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
        .discardMutation(
          activeContext,
          aggregateType: entry.kind.aggregateType,
          aggregateId: entry.aggregateId,
        );
    if (!context.mounted) {
      return;
    }
    ref.read(planningDataRevisionProvider.notifier).state += 1;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planId));
  }

  Future<void> _reorderSessions(
    BuildContext context,
    WidgetRef ref,
    PlanDetail detail,
    int oldIndex,
    int newIndex,
  ) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }

    final currentOrder = detail.sessions.map((value) => value.id).toList();
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (oldIndex < 0 ||
        oldIndex >= currentOrder.length ||
        newIndex < 0 ||
        newIndex >= currentOrder.length) {
      return;
    }
    final movedId = currentOrder.removeAt(oldIndex);
    currentOrder.insert(newIndex, movedId);
    final generation = ++_sessionReorderGeneration;

    setState(() {
      _optimisticSessionOrder = currentOrder;
    });

    try {
      await ref
          .read(planningWriteServiceProvider)
          .reorderSessions(
            context: PlanningWriteContext(
              userId: activeContext.userId,
              organizationId: activeContext.organizationId,
            ),
            draft: SessionReorderDraft(
              planId: detail.plan.id,
              orderedSessionIds: currentOrder,
            ),
          );
    } catch (_) {
      if (mounted && generation == _sessionReorderGeneration) {
        setState(() {
          _optimisticSessionOrder = null;
        });
      }
      if (generation != _sessionReorderGeneration) {
        return;
      }
      rethrow;
    }

    if (generation != _sessionReorderGeneration) {
      return;
    }
    if (!context.mounted) return;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(detail.plan.id));
  }
}

String _formatScheduledFor(BuildContext context, DateTime scheduledFor) {
  return MaterialLocalizations.of(
    context,
  ).formatMediumDate(scheduledFor.toLocal());
}

class _SessionCard extends ConsumerStatefulWidget {
  const _SessionCard({
    super.key,
    required this.planDetail,
    required this.session,
    required this.sessionIndex,
    required this.mutationEntries,
  });

  final PlanDetail planDetail;
  final SessionSummary session;
  final int sessionIndex;
  final List<PlanningMutationRecord> mutationEntries;

  @override
  ConsumerState<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends ConsumerState<_SessionCard> {
  late final FocusNode _addSongFocusNode;
  List<String>? _optimisticItemOrder;
  var _itemReorderGeneration = 0;
  var _pickerOpen = false;
  var _addSongInFlight = false;

  @override
  void initState() {
    super.initState();
    _addSongFocusNode = FocusNode(debugLabel: 'session-add-song-focus');
  }

  @override
  void dispose() {
    _addSongFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final planDetail = widget.planDetail;
    final session = widget.session;
    final items = _orderedItems(session);
    final inlineStatus = planningInlineMutationStatusFor(
      widget.mutationEntries.where(
        (entry) =>
            entry.aggregateId == session.id || entry.sessionId == session.id,
      ),
    );
    final ref = this.ref;
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    ref.listen(activePlanningContextProvider, (previous, next) {
      if (!mounted || !_pickerOpen || previous == next) {
        return;
      }

      _dismissPicker();
    });
    ref.listen(catalogSnapshotStateProvider.select((state) => state.context), (
      previous,
      next,
    ) {
      if (!mounted || !_pickerOpen || previous == next) {
        return;
      }

      _dismissPicker();
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        session.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (inlineStatus != null)
                        PlanningInlineMutationStatusBadge(
                          key: ValueKey('session-local-status-${session.id}'),
                          status: inlineStatus,
                        ),
                    ],
                  ),
                ),
                ReorderableDelayedDragStartListener(
                  index: widget.sessionIndex,
                  child: SizedBox(
                    key: ValueKey('session-drag-handle-${session.id}'),
                    width: 40,
                    height: 40,
                    child: const Center(child: Icon(Icons.drag_indicator)),
                  ),
                ),
                IconButton(
                  onPressed: () => _renameSession(context),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '${AppStrings.sessionRenameAction}: ${session.name}',
                ),
                if (session.items.isEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _deleteSession(context, ref),
                    icon: const Icon(Icons.delete_outline),
                    tooltip:
                        '${AppStrings.sessionDeleteAction}: ${session.name}',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text('${AppStrings.sessionLabel} ${session.position}'),
            const SizedBox(height: 12),
            if (session.items.isEmpty) ...[
              const Text(AppStrings.sessionItemsEmptyMessage),
              const SizedBox(height: 12),
            ],
            ReorderableListView.builder(
              buildDefaultDragHandles: false,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              onReorder: (oldIndex, newIndex) =>
                  _reorderItems(context, ref, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final item = items[index];
                return Padding(
                  key: ValueKey(item.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SongItemRow(
                    planDetail: planDetail,
                    session: session,
                    item: item,
                    itemIndex: index,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Focus(
              key: ValueKey('session-add-song-focus-${session.id}'),
              focusNode: _addSongFocusNode,
              child: TextButton.icon(
                key: ValueKey('session-add-song-${session.id}'),
                onPressed: _canAddSong()
                    ? () => _addSong(context, planDetail, session)
                    : null,
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.sessionItemAddSongAction),
              ),
            ),
            if (!catalogState.hasCachedCatalog) ...[
              const SizedBox(height: 8),
              const Text(AppStrings.sessionItemSongUnavailableMessage),
            ],
          ],
        ),
      ),
    );
  }

  bool _canAddSong() {
    final catalogState = ref.read(catalogSnapshotStateProvider);
    return catalogState.hasCachedCatalog && !_pickerOpen && !_addSongInFlight;
  }

  List<SessionItemSummary> _orderedItems(SessionSummary session) {
    final order = _optimisticItemOrder;
    if (order == null || order.length != session.items.length) {
      return session.items;
    }
    final itemsById = {for (final item in session.items) item.id: item};
    if (itemsById.length != order.length) {
      return session.items;
    }
    for (final itemId in order) {
      if (!itemsById.containsKey(itemId)) {
        return session.items;
      }
    }
    return [for (final itemId in order) itemsById[itemId]!];
  }

  Future<void> _renameSession(BuildContext context) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }

    final nextName = await showDialog<String>(
      context: context,
      builder: (context) =>
          _SessionEditorDialog(initialName: widget.session.name),
    );
    if (nextName == null ||
        nextName.isEmpty ||
        nextName == widget.session.name) {
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
        .renameSession(
          context: PlanningWriteContext(
            userId: currentContext.userId,
            organizationId: currentContext.organizationId,
          ),
          draft: SessionRenameDraft(
            sessionId: widget.session.id,
            planId: widget.planDetail.plan.id,
            name: nextName,
          ),
        );

    if (!context.mounted) return;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(widget.planDetail.plan.id));
  }

  Future<void> _addSong(
    BuildContext context,
    PlanDetail detail,
    SessionSummary session,
  ) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }
    final activeCatalogContext = ref.read(catalogSnapshotStateProvider).context;
    final visibleSongsState = ref.read(songLibraryListProvider);
    final existingSongIds = session.items.map((item) => item.song.id).toSet();
    final selectableSongs = visibleSongsState.valueOrNull;
    final FutureOr<List<SongSummary>> eligibleSongs =
        selectableSongs == null || visibleSongsState.isLoading
        ? ref.read(songLibraryListProvider.future).then((songs) {
            return songs
                .where((candidate) => !existingSongIds.contains(candidate.id))
                .toList(growable: false);
          })
        : selectableSongs
              .where((candidate) => !existingSongIds.contains(candidate.id))
              .toList(growable: false);

    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) {
      return;
    }
    final currentCatalogContext = ref
        .read(catalogSnapshotStateProvider)
        .context;
    if (currentCatalogContext != null &&
        activeCatalogContext != null &&
        !sameCatalogContext(activeCatalogContext, currentCatalogContext)) {
      return;
    }
    final currentContext = ref.read(activePlanningContextProvider);
    if (currentContext == null ||
        !samePlanningContext(activeContext, currentContext)) {
      return;
    }

    setState(() {
      _pickerOpen = true;
    });
    try {
      final selectedSong = await showSessionSongPicker(
        context: context,
        eligibleSongs: eligibleSongs,
        onPick: (song) async {
          final currentCatalogContext = ref
              .read(catalogSnapshotStateProvider)
              .context;
          if (currentCatalogContext != null &&
              activeCatalogContext != null &&
              !sameCatalogContext(
                activeCatalogContext,
                currentCatalogContext,
              )) {
            return false;
          }
          final currentContext = ref.read(activePlanningContextProvider);
          if (currentContext == null ||
              !samePlanningContext(activeContext, currentContext)) {
            return false;
          }

          setState(() {
            _addSongInFlight = true;
          });
          try {
            await ref
                .read(planningWriteServiceProvider)
                .addSongSessionItem(
                  context: PlanningWriteContext(
                    userId: currentContext.userId,
                    organizationId: currentContext.organizationId,
                  ),
                  draft: SessionItemCreateSongDraft(
                    sessionId: session.id,
                    planId: detail.plan.id,
                    songId: song.id,
                  ),
                );
            ref.invalidate(planningMutationEntriesProvider);
            ref.invalidate(planningPlanListProvider);
            ref.invalidate(planningPlanDetailProvider(detail.plan.id));
            return true;
          } on PlanningWriteContextMismatchException {
            ref.invalidate(planningMutationEntriesProvider);
            ref.invalidate(planningPlanDetailProvider(detail.plan.id));
            return false;
          } on DuplicateSessionSongException {
            ref.invalidate(planningMutationEntriesProvider);
            ref.invalidate(planningPlanDetailProvider(detail.plan.id));
            return true;
          } on PlanningSongUnavailableException {
            ref.invalidate(planningMutationEntriesProvider);
            ref.invalidate(planningPlanDetailProvider(detail.plan.id));
            return false;
          } finally {
            if (mounted) {
              setState(() {
                _addSongInFlight = false;
              });
            }
          }
        },
      );
      if (selectedSong == null || !context.mounted) {
        return;
      }
      ref.invalidate(planningPlanDetailProvider(detail.plan.id));
    } finally {
      if (mounted) {
        setState(() {
          _pickerOpen = false;
        });
        _addSongFocusNode.requestFocus();
      }
    }
  }

  void _dismissPicker() {
    if (!_pickerOpen) {
      return;
    }

    setState(() {
      _pickerOpen = false;
    });
    final navigator = Navigator.of(context, rootNavigator: true);
    if (!navigator.canPop()) {
      return;
    }
    navigator.maybePop();
  }

  Future<void> _deleteSession(BuildContext context, WidgetRef ref) async {
    final planDetail = widget.planDetail;
    final session = widget.session;
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.sessionDeleteConfirmTitle),
        content: const Text(AppStrings.sessionDeleteConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.songCancelAction),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.sessionDeleteConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    if (!context.mounted) return;
    await ref
        .read(planningWriteServiceProvider)
        .deleteSession(
          context: PlanningWriteContext(
            userId: activeContext.userId,
            organizationId: activeContext.organizationId,
          ),
          draft: SessionDeleteDraft(
            sessionId: session.id,
            planId: planDetail.plan.id,
          ),
        );

    if (!context.mounted) return;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planDetail.plan.id));
  }

  Future<void> _reorderItems(
    BuildContext context,
    WidgetRef ref,
    int oldIndex,
    int newIndex,
  ) async {
    final planDetail = widget.planDetail;
    final session = widget.session;
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }

    final currentOrder = _orderedItems(
      session,
    ).map((value) => value.id).toList();
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (oldIndex < 0 ||
        oldIndex >= currentOrder.length ||
        newIndex < 0 ||
        newIndex >= currentOrder.length) {
      return;
    }
    final movedId = currentOrder.removeAt(oldIndex);
    currentOrder.insert(newIndex, movedId);
    final generation = ++_itemReorderGeneration;

    setState(() {
      _optimisticItemOrder = currentOrder;
    });

    try {
      await ref
          .read(planningWriteServiceProvider)
          .reorderSessionItems(
            context: PlanningWriteContext(
              userId: activeContext.userId,
              organizationId: activeContext.organizationId,
            ),
            draft: SessionItemReorderDraft(
              sessionId: session.id,
              planId: planDetail.plan.id,
              orderedSessionItemIds: currentOrder,
            ),
          );
    } catch (_) {
      if (mounted && generation == _itemReorderGeneration) {
        setState(() {
          _optimisticItemOrder = null;
        });
      }
      if (generation != _itemReorderGeneration) {
        return;
      }
      rethrow;
    }
    if (generation != _itemReorderGeneration) {
      return;
    }
    if (!context.mounted) return;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planDetail.plan.id));
  }
}

class _PlanEditorDialog extends ConsumerStatefulWidget {
  const _PlanEditorDialog({
    required this.planId,
    required this.initialName,
    this.initialDescription,
    this.initialScheduledFor,
  });

  final String planId;
  final String initialName;
  final String? initialDescription;
  final DateTime? initialScheduledFor;

  @override
  ConsumerState<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends ConsumerState<_PlanEditorDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.initialDescription ?? '');
  late final TextEditingController _scheduledForController =
      TextEditingController(
        text: widget.initialScheduledFor?.toUtc().toIso8601String() ?? '',
      );
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
      title: const Text(AppStrings.planEditorTitleEdit),
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
              PlanEditDraft(
                planId: widget.planId,
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

class _SessionEditorDialog extends ConsumerStatefulWidget {
  const _SessionEditorDialog({this.initialName = ''});

  final String initialName;

  @override
  ConsumerState<_SessionEditorDialog> createState() =>
      _SessionEditorDialogState();
}

class _SessionEditorDialogState extends ConsumerState<_SessionEditorDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _nameController.dispose();
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

    final isRename = widget.initialName.isNotEmpty;

    return AlertDialog(
      title: Text(
        isRename
            ? AppStrings.sessionEditorTitleRename
            : AppStrings.sessionEditorTitleCreate,
      ),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('session-editor-name'),
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: AppStrings.sessionNameLabel,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.songCancelAction),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_nameController.text.trim()),
          child: const Text(AppStrings.planSaveAction),
        ),
      ],
    );
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

class _SongItemRow extends ConsumerWidget {
  const _SongItemRow({
    required this.planDetail,
    required this.session,
    required this.item,
    required this.itemIndex,
  });

  final PlanDetail planDetail;
  final SessionSummary session;
  final SessionItemSummary item;
  final int itemIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        ReorderableDelayedDragStartListener(
          index: itemIndex,
          child: SizedBox(
            key: ValueKey('session-item-drag-handle-${item.id}'),
            width: 40,
            height: 40,
            child: const Center(child: Icon(Icons.drag_indicator)),
          ),
        ),
        Expanded(
          child: InkWell(
            key: ValueKey('plan-session-item-${item.id}'),
            onTap: () {
              context.push(
                PlanningRoutes.planSessionSongReaderLocation(
                  planSlug: planDetail.plan.slug,
                  sessionSlug: session.slug,
                  songSlug: item.song.slug,
                ),
                extra: planDetail,
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text('${item.position}. ${item.song.title}')),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => _deleteItem(context, ref),
          icon: const Icon(Icons.delete_outline),
          tooltip: '${AppStrings.sessionItemDeleteAction}: ${item.song.title}',
        ),
      ],
    );
  }

  Future<void> _deleteItem(BuildContext context, WidgetRef ref) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }
    await ref
        .read(planningWriteServiceProvider)
        .deleteSessionItem(
          context: PlanningWriteContext(
            userId: activeContext.userId,
            organizationId: activeContext.organizationId,
          ),
          draft: SessionItemDeleteDraft(
            sessionItemId: item.id,
            sessionId: session.id,
            planId: planDetail.plan.id,
          ),
        );
    if (!context.mounted) return;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planDetail.plan.id));
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
