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
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/planning/planning_routes.dart';
import 'package:lyron_app/src/presentation/planning/session_song_picker.dart';
import 'package:lyron_app/src/presentation/planning/widgets/planning_workspace_shell.dart';
import 'package:lyron_app/src/presentation/planning/widgets/planning_workspace_status_surface.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class PlanDetailScreen extends ConsumerWidget {
  const PlanDetailScreen({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(planningPlanDetailProvider(planId));
    final mutationsAsync = ref.watch(planningMutationEntriesProvider);

    return PlanningWorkspaceShell(
      title: AppStrings.planDetailTitle,
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
        loading: () =>
            const Center(child: Text(AppStrings.planDetailLoadingMessage)),
        error: (error, stackTrace) => _RetryableErrorState(
          message: AppStrings.planDetailLoadFailureMessage,
          onRetry: () => ref.invalidate(planningPlanDetailProvider(planId)),
        ),
        data: (PlanDetail detail) {
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
                if (detail.sessions.isEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(AppStrings.sessionListEmptyMessage),
                ],
                const SizedBox(height: 20),
              ],
            ),
            itemCount: detail.sessions.length,
            onReorder: (oldIndex, newIndex) =>
                _reorderSessions(context, ref, detail, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final session = detail.sessions[index];
              return _SessionCard(
                key: ValueKey(session.id),
                planDetail: detail,
                session: session,
                sessionIndex: index,
              );
            },
          );
        },
      ),
    );
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
        currentContext.userId != activeContext.userId ||
        currentContext.organizationId != activeContext.organizationId) {
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
        currentContext.userId != activeContext.userId ||
        currentContext.organizationId != activeContext.organizationId) {
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

    if (!context.mounted) return;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(detail.plan.id));
  }
}

class _SessionCard extends ConsumerStatefulWidget {
  const _SessionCard({
    super.key,
    required this.planDetail,
    required this.session,
    required this.sessionIndex,
  });

  final PlanDetail planDetail;
  final SessionSummary session;
  final int sessionIndex;

  @override
  ConsumerState<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends ConsumerState<_SessionCard> {
  late final FocusNode _addSongFocusNode;
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
    final ref = this.ref;
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    final sessionIndex = planDetail.sessions.indexWhere(
      (candidate) => candidate.id == session.id,
    );
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
                  child: Text(
                    session.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ReorderableDelayedDragStartListener(
                  index: widget.sessionIndex,
                  child: SizedBox(
                    key: ValueKey('session-drag-handle-${session.id}'),
                    width: 40,
                    height: 40,
                    child: Tooltip(
                      message:
                          '${AppStrings.sessionReorderAction}: ${session.name}',
                      child: const Center(child: Icon(Icons.drag_indicator)),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: sessionIndex > 0
                      ? () => _reorderSession(context, ref, -1)
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: '${AppStrings.sessionMoveUpAction}: ${session.name}',
                ),
                IconButton(
                  onPressed:
                      sessionIndex >= 0 &&
                          sessionIndex < planDetail.sessions.length - 1
                      ? () => _reorderSession(context, ref, 1)
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip:
                      '${AppStrings.sessionMoveDownAction}: ${session.name}',
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
              itemCount: session.items.length,
              onReorder: (oldIndex, newIndex) =>
                  _reorderItems(context, ref, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final item = session.items[index];
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
        currentContext.userId != activeContext.userId ||
        currentContext.organizationId != activeContext.organizationId) {
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
        (currentCatalogContext.userId != activeCatalogContext.userId ||
            currentCatalogContext.organizationId !=
                activeCatalogContext.organizationId)) {
      return;
    }
    final currentContext = ref.read(activePlanningContextProvider);
    if (currentContext == null ||
        currentContext.userId != activeContext.userId ||
        currentContext.organizationId != activeContext.organizationId) {
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
              (currentCatalogContext.userId != activeContext.userId ||
                  currentCatalogContext.organizationId !=
                      activeContext.organizationId)) {
            return false;
          }
          final currentContext = ref.read(activePlanningContextProvider);
          if (currentContext == null ||
              currentContext.userId != activeContext.userId ||
              currentContext.organizationId != activeContext.organizationId) {
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

  Future<void> _reorderSession(
    BuildContext context,
    WidgetRef ref,
    int delta,
  ) async {
    final planDetail = widget.planDetail;
    final session = widget.session;
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }
    final currentOrder = planDetail.sessions.map((value) => value.id).toList();
    final currentIndex = currentOrder.indexOf(session.id);
    final targetIndex = currentIndex + delta;
    if (currentIndex < 0 ||
        targetIndex < 0 ||
        targetIndex >= currentOrder.length) {
      return;
    }
    final movedId = currentOrder.removeAt(currentIndex);
    currentOrder.insert(targetIndex, movedId);
    if (!context.mounted) return;
    await ref
        .read(planningWriteServiceProvider)
        .reorderSessions(
          context: PlanningWriteContext(
            userId: activeContext.userId,
            organizationId: activeContext.organizationId,
          ),
          draft: SessionReorderDraft(
            planId: planDetail.plan.id,
            orderedSessionIds: currentOrder,
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

    final currentOrder = session.items.map((value) => value.id).toList();
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
            child: Tooltip(
              message:
                  '${AppStrings.sessionItemReorderAction}: ${item.song.title}',
              child: const Center(child: Icon(Icons.drag_indicator)),
            ),
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
