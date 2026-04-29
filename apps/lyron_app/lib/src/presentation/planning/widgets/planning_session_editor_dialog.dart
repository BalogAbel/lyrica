import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/planning/session_song_picker.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class PlanningSessionEditorDialog extends ConsumerStatefulWidget {
  const PlanningSessionEditorDialog({
    super.key,
    required this.planId,
    required this.sessionId,
  });

  final String planId;
  final String sessionId;

  @override
  ConsumerState<PlanningSessionEditorDialog> createState() =>
      _PlanningSessionEditorDialogState();
}

class _PlanningSessionEditorDialogState
    extends ConsumerState<PlanningSessionEditorDialog> {
  late final TextEditingController _nameController;
  late final FocusNode _addSongFocusNode;
  var _initialized = false;
  var _saving = false;
  var _pickerOpen = false;
  var _addSongInFlight = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _addSongFocusNode = FocusNode(debugLabel: 'session-add-song-focus');
  }

  @override
  void dispose() {
    _addSongFocusNode.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    final detailAsync = ref.watch(planningPlanDetailProvider(widget.planId));
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
    ref.listen(activePlanningContextProvider, (previous, next) {
      if (!mounted || previous == next) {
        return;
      }

      if (_pickerOpen) {
        _dismissPicker();
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).maybePop();
      }
    });

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: detailAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text(AppStrings.planDetailLoadingMessage)),
          ),
          error: (_, _) => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text(AppStrings.planDetailLoadFailureMessage)),
          ),
          data: (detail) {
            final session = detail.sessions.firstWhereOrNull(
              (candidate) => candidate.id == widget.sessionId,
            );
            if (session == null) {
              return const SizedBox.shrink();
            }
            if (!_initialized) {
              _nameController.text = session.name;
              _initialized = true;
            }

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BackButton(onPressed: () => Navigator.of(context).pop()),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.sessionEditorTitleEdit,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              detail.plan.name,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saving
                            ? null
                            : () => _saveSession(context, detail, session),
                        child: const Text(AppStrings.planSaveAction),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: const ValueKey('session-editor-name'),
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: AppStrings.sessionNameLabel,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        AppStrings.sessionLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      Focus(
                        key: ValueKey('session-add-song-focus-${session.id}'),
                        focusNode: _addSongFocusNode,
                        child: TextButton.icon(
                          key: ValueKey('session-add-song-${session.id}'),
                          onPressed: _canAddSong()
                              ? () => _addSong(context, detail, session)
                              : null,
                          icon: const Icon(Icons.add),
                          label: const Text(
                            AppStrings.sessionItemAddSongAction,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!catalogState.hasCachedCatalog) ...[
                    const SizedBox(height: 8),
                    const Text(AppStrings.sessionItemSongUnavailableMessage),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: _SessionEditorBody(
                      planDetail: detail,
                      session: session,
                      onReorderItem: (oldIndex, newIndex) => _reorderItems(
                        context,
                        detail,
                        session,
                        oldIndex,
                        newIndex,
                      ),
                      onMoveItemUp: (item) =>
                          _reorderItem(context, detail, session, item, -1),
                      onMoveItemDown: (item) =>
                          _reorderItem(context, detail, session, item, 1),
                      onDeleteItem: (item) =>
                          _deleteItem(context, detail, session, item),
                      onDeleteSession: session.items.isEmpty
                          ? () => _deleteSession(context, detail, session)
                          : null,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  bool _canAddSong() {
    final catalogState = ref.read(catalogSnapshotStateProvider);
    return catalogState.hasCachedCatalog && !_pickerOpen && !_addSongInFlight;
  }

  Future<void> _saveSession(
    BuildContext context,
    PlanDetail detail,
    SessionSummary session,
  ) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }
    final nextName = _nameController.text.trim();
    if (nextName.isEmpty) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      await ref
          .read(planningWriteServiceProvider)
          .renameSession(
            context: PlanningWriteContext(
              userId: activeContext.userId,
              organizationId: activeContext.organizationId,
            ),
            draft: SessionRenameDraft(
              sessionId: session.id,
              planId: detail.plan.id,
              name: nextName,
            ),
          );
      if (!context.mounted) {
        return;
      }
      ref.invalidate(planningMutationEntriesProvider);
      ref.invalidate(planningPlanListProvider);
      ref.invalidate(planningPlanDetailProvider(detail.plan.id));
      Navigator.of(context).pop();
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _deleteSession(
    BuildContext context,
    PlanDetail detail,
    SessionSummary session,
  ) async {
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

    await ref
        .read(planningWriteServiceProvider)
        .deleteSession(
          context: PlanningWriteContext(
            userId: activeContext.userId,
            organizationId: activeContext.organizationId,
          ),
          draft: SessionDeleteDraft(
            sessionId: session.id,
            planId: detail.plan.id,
          ),
        );
    if (!context.mounted) {
      return;
    }
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(detail.plan.id));
    Navigator.of(context).pop();
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

  Future<void> _reorderItem(
    BuildContext context,
    PlanDetail detail,
    SessionSummary session,
    SessionItemSummary item,
    int delta,
  ) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }
    final currentOrder = session.items.map((value) => value.id).toList();
    final currentIndex = currentOrder.indexOf(item.id);
    final targetIndex = currentIndex + delta;
    if (currentIndex < 0 ||
        targetIndex < 0 ||
        targetIndex >= currentOrder.length) {
      return;
    }
    final movedId = currentOrder.removeAt(currentIndex);
    currentOrder.insert(targetIndex, movedId);
    await ref
        .read(planningWriteServiceProvider)
        .reorderSessionItems(
          context: PlanningWriteContext(
            userId: activeContext.userId,
            organizationId: activeContext.organizationId,
          ),
          draft: SessionItemReorderDraft(
            sessionId: session.id,
            planId: detail.plan.id,
            orderedSessionItemIds: currentOrder,
          ),
        );
    if (!context.mounted) {
      return;
    }
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(detail.plan.id));
  }

  Future<void> _reorderItems(
    BuildContext context,
    PlanDetail detail,
    SessionSummary session,
    int oldIndex,
    int newIndex,
  ) async {
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
            planId: detail.plan.id,
            orderedSessionItemIds: currentOrder,
          ),
        );
    if (!context.mounted) {
      return;
    }
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(detail.plan.id));
  }

  Future<void> _deleteItem(
    BuildContext context,
    PlanDetail detail,
    SessionSummary session,
    SessionItemSummary item,
  ) async {
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
            planId: detail.plan.id,
          ),
        );
    if (!context.mounted) {
      return;
    }
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(detail.plan.id));
  }
}

class _SessionEditorBody extends StatelessWidget {
  const _SessionEditorBody({
    required this.planDetail,
    required this.session,
    required this.onReorderItem,
    required this.onMoveItemUp,
    required this.onMoveItemDown,
    required this.onDeleteItem,
    required this.onDeleteSession,
  });

  final PlanDetail planDetail;
  final SessionSummary session;
  final void Function(int oldIndex, int newIndex) onReorderItem;
  final void Function(SessionItemSummary item) onMoveItemUp;
  final void Function(SessionItemSummary item) onMoveItemDown;
  final void Function(SessionItemSummary item) onDeleteItem;
  final VoidCallback? onDeleteSession;

  @override
  Widget build(BuildContext context) {
    if (session.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('No songs in this session yet.'),
          if (onDeleteSession != null) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: onDeleteSession,
              child: const Text(AppStrings.sessionDeleteAction),
            ),
          ],
        ],
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: session.items.length,
      onReorder: onReorderItem,
      itemBuilder: (context, index) {
        final item = session.items[index];
        final canMoveUp = index > 0;
        final canMoveDown = index < session.items.length - 1;
        return Padding(
          key: ValueKey(item.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReorderableDelayedDragStartListener(
                    index: index,
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${index + 1}. ${item.song.title}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      IconButton(
                        onPressed: canMoveUp ? () => onMoveItemUp(item) : null,
                        icon: const Icon(Icons.keyboard_arrow_up),
                        tooltip:
                            '${AppStrings.sessionItemMoveUpAction}: ${item.song.title}',
                      ),
                      IconButton(
                        onPressed: canMoveDown
                            ? () => onMoveItemDown(item)
                            : null,
                        icon: const Icon(Icons.keyboard_arrow_down),
                        tooltip:
                            '${AppStrings.sessionItemMoveDownAction}: ${item.song.title}',
                      ),
                      IconButton(
                        key: ValueKey('session-item-delete-${item.id}'),
                        onPressed: () => onDeleteItem(item),
                        icon: const Icon(Icons.delete_outline),
                        tooltip:
                            '${AppStrings.sessionItemDeleteAction}: ${item.song.title}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
