import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/planning/planning_reorder_overlay.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_context_checks.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/planning/session_song_picker.dart';
import 'package:lyron_app/src/presentation/planning/widgets/plan_song_item_row.dart';
import 'package:lyron_app/src/presentation/planning/widgets/session_editor_dialog.dart';
import 'package:lyron_app/src/presentation/shared/if_capability.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void _handlePlanningAddSongError(
  WidgetRef ref,
  String planId, {
  required Object? error,
  required StackTrace? stackTrace,
  required String library,
}) {
  if (error != null && stackTrace != null) {
    debugPrint('$library failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  ref.invalidate(planningMutationEntriesProvider);
  ref.invalidate(planningPlanDetailProvider(planId));
}

class PlanSessionCard extends ConsumerStatefulWidget {
  const PlanSessionCard({
    super.key,
    required this.planDetail,
    required this.session,
    required this.sessionIndex,
    this.isProjectionSettled = true,
  });

  final PlanDetail planDetail;
  final SessionSummary session;
  final int sessionIndex;

  /// Whether [session] reflects a fully-settled projection rather than a
  /// value carried over from before the parent's provider started
  /// refreshing (see the equivalent check in PlanDetailScreen). Defaults to
  /// true so callers that never have a transient reload to worry about
  /// keep consulting the rule on every build.
  final bool isProjectionSettled;

  @override
  ConsumerState<PlanSessionCard> createState() => _PlanSessionCardState();
}

class _PlanSessionCardState extends ConsumerState<PlanSessionCard> {
  late final FocusNode _addSongFocusNode;
  List<String>? _optimisticItemOrder;
  var _itemReorderGeneration = 0;
  var _lastCompletedItemReorderGeneration = 0;
  // Whether the one-reload post-write grace (see resolveReorderOverlay) has
  // already been spent for the current optimistic item order.
  var _itemReorderPostWriteReloadConsumed = false;
  // Whether the guaranteed follow-up refresh (see build()) has already been
  // scheduled for the current optimistic item order. Without this, every
  // build after the grace is consumed would schedule another invalidate,
  // looping forever.
  var _itemReorderFollowUpScheduled = false;
  Future<void> _itemReorderTail = Future<void>.value();
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
    // Resolve (and, if settled, drop) the overlay against this fresh
    // projection before it is used to order the list below. This runs during
    // build, so the field is assigned directly rather than via setState —
    // the current build already sees the resolved value. Skip entirely when
    // the parent's projection is not settled (see isProjectionSettled doc):
    // that build carries a stale, pre-invalidate value, not a real arrival.
    if (widget.isProjectionSettled) {
      final priorOptimisticItemOrder = _optimisticItemOrder;
      final hasItemWriteInFlight =
          _itemReorderGeneration != _lastCompletedItemReorderGeneration;
      _optimisticItemOrder = resolveReorderOverlay(
        optimisticOrder: priorOptimisticItemOrder,
        projectionOrder: [for (final item in session.items) item.id],
        hasWriteInFlight: hasItemWriteInFlight,
        hasConsumedPostWriteReload: _itemReorderPostWriteReloadConsumed,
      );
      // The overlay survives a disagreeing projection with the write no
      // longer in flight only via the post-write grace (see
      // resolveReorderOverlay), so seeing it kept in that state is exactly
      // the "grace was just used" signal — record it so the next
      // disagreeing projection lets the projection win.
      if (!hasItemWriteInFlight &&
          priorOptimisticItemOrder != null &&
          _optimisticItemOrder == priorOptimisticItemOrder) {
        _itemReorderPostWriteReloadConsumed = true;
        // Consuming the grace only records that it was spent; nothing else
        // guarantees another build with a fresh projection ever arrives to
        // re-consult the rule and drop the overlay. Force exactly one
        // follow-up refresh so it does. Guarded by its own flag (reset
        // alongside the consumed flag whenever a new reorder starts) so
        // this fires once per consumed grace, not once per build -- once
        // the follow-up projection arrives, the rule above drops the
        // overlay and this block is no longer reached for this optimistic
        // order.
        if (!_itemReorderFollowUpScheduled) {
          _itemReorderFollowUpScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            this.ref.invalidate(
              planningPlanDetailProvider(widget.planDetail.plan.id),
            );
          });
        }
      }
    }
    final items = _orderedItems(session);
    final ref = this.ref;
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    final orgId = ref.watch(activePlanningContextProvider)?.organizationId;
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
                    child: const Center(child: Icon(Icons.drag_indicator)),
                  ),
                ),
                IfCapability(
                  capability: Capability.editSessions,
                  organizationId: orgId,
                  child: IconButton(
                    onPressed: () => _renameSession(context),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip:
                        '${AppStrings.sessionRenameAction}: ${session.name}',
                  ),
                ),
                if (session.items.isEmpty) ...[
                  const SizedBox(width: 8),
                  IfCapability(
                    key: Key('session-delete-button-${session.id}'),
                    capability: Capability.editSessions,
                    organizationId: orgId,
                    child: IconButton(
                      onPressed: () => _deleteSession(context, ref),
                      icon: const Icon(Icons.delete_outline),
                      tooltip:
                          '${AppStrings.sessionDeleteAction}: ${session.name}',
                    ),
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
                  _reorderItems(ref, oldIndex, newIndex),
              itemBuilder: (context, index) {
                final item = items[index];
                return Padding(
                  key: ValueKey(item.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: PlanSongItemRow(
                    planDetail: planDetail,
                    session: session,
                    item: item,
                    itemIndex: index,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            IfCapability(
              key: Key('session-item-add-button-${session.id}'),
              capability: Capability.editSessions,
              organizationId: orgId,
              child: Focus(
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
          SessionEditorDialog(initialName: widget.session.name),
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
          } on PlanningWriteContextMismatchException catch (e, st) {
            _handlePlanningAddSongError(
              ref,
              detail.plan.id,
              error: e,
              stackTrace: st,
              library: 'planning add song',
            );
            return false;
          } on DuplicateSessionSongException catch (e, st) {
            _handlePlanningAddSongError(
              ref,
              detail.plan.id,
              error: e,
              stackTrace: st,
              library: 'planning add song',
            );
            return true;
          } on PlanningSongUnavailableException catch (e, st) {
            _handlePlanningAddSongError(
              ref,
              detail.plan.id,
              error: e,
              stackTrace: st,
              library: 'planning add song',
            );
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

  void _reorderItems(WidgetRef ref, int oldIndex, int newIndex) {
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
        newIndex >= currentOrder.length ||
        oldIndex == newIndex) {
      return;
    }
    final movedId = currentOrder.removeAt(oldIndex);
    currentOrder.insert(newIndex, movedId);
    final generation = ++_itemReorderGeneration;
    _itemReorderPostWriteReloadConsumed = false;
    _itemReorderFollowUpScheduled = false;

    setState(() {
      _optimisticItemOrder = currentOrder;
    });

    final writeContext = PlanningWriteContext(
      userId: activeContext.userId,
      organizationId: activeContext.organizationId,
    );
    final planId = planDetail.plan.id;
    final queued = _itemReorderTail.then(
      (_) => _performItemReorder(
        ref,
        writeContext,
        planId,
        session.id,
        currentOrder,
        generation,
      ),
    );
    _itemReorderTail = queued.catchError((error, stackTrace) {
      _reportItemReorderError(error, stackTrace);
    });
    unawaited(_itemReorderTail);
  }

  Future<void> _performItemReorder(
    WidgetRef ref,
    PlanningWriteContext writeContext,
    String planId,
    String sessionId,
    List<String> currentOrder,
    int generation,
  ) async {
    try {
      await ref
          .read(planningWriteServiceProvider)
          .reorderSessionItems(
            context: writeContext,
            draft: SessionItemReorderDraft(
              sessionId: sessionId,
              planId: planId,
              orderedSessionItemIds: currentOrder,
            ),
          );
    } catch (error, stackTrace) {
      if (mounted && generation == _itemReorderGeneration) {
        setState(() {
          _optimisticItemOrder = null;
          _lastCompletedItemReorderGeneration = generation;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.planningReorderFailedMessage),
          ),
        );
      }
      if (generation != _itemReorderGeneration) {
        return;
      }
      _reportItemReorderError(error, stackTrace);
      return;
    }
    if (generation != _itemReorderGeneration) {
      return;
    }
    _lastCompletedItemReorderGeneration = generation;
    if (!mounted) return;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planId));
  }

  void _reportItemReorderError(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'planning item reorder',
      ),
    );
  }
}
