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
import 'package:lyron_app/src/shared/app_strings.dart';

class PlanDetailScreen extends ConsumerWidget {
  const PlanDetailScreen({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(planningPlanDetailProvider(planId));
    final mutationsAsync = ref.watch(planningMutationEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.planDetailTitle),
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
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            mutationsAsync.when(
              data: (entries) {
                final relevantEntries = entries
                    .where(
                      (entry) =>
                          entry.aggregateId == planId || entry.planId == planId,
                    )
                    .toList(growable: false);
                return relevantEntries.isEmpty
                    ? const SizedBox.shrink()
                    : _PlanningMutationStatusSurface(
                        entries: relevantEntries,
                        currentPlanId: planId,
                      );
              },
              error: (_, _) => const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
            ),
            Expanded(
              child: detailAsync.when(
                loading: () => const Center(
                  child: Text(AppStrings.planDetailLoadingMessage),
                ),
                error: (error, stackTrace) => _RetryableErrorState(
                  message: AppStrings.planDetailLoadFailureMessage,
                  onRetry: () =>
                      ref.invalidate(planningPlanDetailProvider(planId)),
                ),
                data: (PlanDetail detail) {
                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        detail.plan.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if ((detail.plan.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(detail.plan.description!),
                      ],
                      const SizedBox(height: 20),
                      for (final session in detail.sessions) ...[
                        _SessionCard(planDetail: detail, session: session),
                        const SizedBox(height: 16),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
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

    await ref
        .read(planningWriteServiceProvider)
        .editPlan(
          context: PlanningWriteContext(
            userId: activeContext.userId,
            organizationId: activeContext.organizationId,
          ),
          draft: draft,
        );
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

    await ref
        .read(planningWriteServiceProvider)
        .createSession(
          context: PlanningWriteContext(
            userId: activeContext.userId,
            organizationId: activeContext.organizationId,
          ),
          draft: SessionCreateDraft(planId: planId, name: draft),
        );
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planId));
  }
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard({required this.planDetail, required this.session});

  final PlanDetail planDetail;
  final SessionSummary session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionIndex = planDetail.sessions.indexWhere(
      (candidate) => candidate.id == session.id,
    );
    final canMoveUp = sessionIndex > 0;
    final canMoveDown =
        sessionIndex >= 0 && sessionIndex < planDetail.sessions.length - 1;
    final catalogState = ref.watch(catalogSnapshotStateProvider);
    final visibleSongs =
        ref.watch(songLibraryListProvider).valueOrNull ?? const <SongSummary>[];
    final canAddSong = catalogState.hasCachedCatalog && visibleSongs.isNotEmpty;

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
                IconButton(
                  onPressed: canMoveUp
                      ? () => _reorderSession(context, ref, -1)
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_up),
                  tooltip: '${AppStrings.sessionMoveUpAction}: ${session.name}',
                ),
                IconButton(
                  onPressed: canMoveDown
                      ? () => _reorderSession(context, ref, 1)
                      : null,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip:
                      '${AppStrings.sessionMoveDownAction}: ${session.name}',
                ),
                IconButton(
                  onPressed: () => _renameSession(context, ref),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: '${AppStrings.sessionRenameAction}: ${session.name}',
                ),
                if (session.items.isEmpty)
                  IconButton(
                    onPressed: () => _deleteSession(context, ref),
                    icon: const Icon(Icons.delete_outline),
                    tooltip:
                        '${AppStrings.sessionDeleteAction}: ${session.name}',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('${AppStrings.sessionLabel} ${session.position}'),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: canAddSong
                    ? () => _addSong(context, ref, visibleSongs)
                    : null,
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.sessionItemAddSongAction),
              ),
            ),
            if (!canAddSong)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(AppStrings.sessionItemSongUnavailableMessage),
              ),
            for (var index = 0; index < session.items.length; index += 1) ...[
              _SongItemRow(
                planDetail: planDetail,
                session: session,
                item: session.items[index],
                itemIndex: index,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _renameSession(BuildContext context, WidgetRef ref) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }

    final draft = await showDialog<String>(
      context: context,
      builder: (context) => _SessionEditorDialog(initialName: session.name),
    );
    if (draft == null) {
      return;
    }

    await ref
        .read(planningWriteServiceProvider)
        .renameSession(
          context: PlanningWriteContext(
            userId: activeContext.userId,
            organizationId: activeContext.organizationId,
          ),
          draft: SessionRenameDraft(
            sessionId: session.id,
            planId: planDetail.plan.id,
            name: draft,
          ),
        );
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planDetail.plan.id));
  }

  Future<void> _deleteSession(BuildContext context, WidgetRef ref) async {
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
            planId: planDetail.plan.id,
          ),
        );
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planDetail.plan.id));
  }

  Future<void> _reorderSession(
    BuildContext context,
    WidgetRef ref,
    int delta,
  ) async {
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
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planDetail.plan.id));
  }

  Future<void> _addSong(
    BuildContext context,
    WidgetRef ref,
    List<SongSummary> visibleSongs,
  ) async {
    final activeContext = ref.read(activePlanningContextProvider);
    if (activeContext == null) {
      return;
    }
    final existingSongIds = session.items.map((item) => item.song.id).toSet();
    final selectableSongs = visibleSongs
        .where((candidate) => !existingSongIds.contains(candidate.id))
        .toList(growable: false);
    final selectedSong = await showDialog<SongSummary>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.sessionItemSongPickerTitle),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: selectableSongs
                .map(
                  (song) => ListTile(
                    key: ValueKey('session-song-option-${song.id}'),
                    title: Text(song.title),
                    onTap: () => Navigator.of(context).pop(song),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
    if (selectedSong == null) {
      return;
    }

    await ref
        .read(planningWriteServiceProvider)
        .addSongSessionItem(
          context: PlanningWriteContext(
            userId: activeContext.userId,
            organizationId: activeContext.organizationId,
          ),
          draft: SessionItemCreateSongDraft(
            sessionId: session.id,
            planId: planDetail.plan.id,
            songId: selectedSong.id,
          ),
        );
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planDetail.plan.id));
  }
}

class _PlanningMutationStatusSurface extends ConsumerWidget {
  const _PlanningMutationStatusSurface({
    required this.entries,
    required this.currentPlanId,
  });

  final List<PlanningMutationRecord> entries;
  final String currentPlanId;

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
                  trailing:
                      entry.syncStatus == PlanningMutationSyncStatus.pending
                      ? null
                      : TextButton(
                          onPressed: () => _retryEntry(ref, entry),
                          child: const Text(AppStrings.retryAction),
                        ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> _retryEntry(WidgetRef ref, PlanningMutationRecord entry) async {
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
    ref.read(planningDataRevisionProvider.notifier).state += 1;
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(currentPlanId));
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
  State<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<_PlanEditorDialog> {
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

class _SessionEditorDialog extends StatefulWidget {
  const _SessionEditorDialog({this.initialName = ''});

  final String initialName;

  @override
  State<_SessionEditorDialog> createState() => _SessionEditorDialogState();
}

class _SessionEditorDialogState extends State<_SessionEditorDialog> {
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
    final resolvedSongSlug = ref
        .watch(songLibrarySongByIdProvider(item.song.id))
        .valueOrNull
        ?.slug;
    final canMoveUp = itemIndex > 0;
    final canMoveDown = itemIndex < session.items.length - 1;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            key: ValueKey('plan-session-item-${item.id}'),
            onTap: resolvedSongSlug == null
                ? null
                : () {
                    context.push(
                      PlanningRoutes.planSessionSongReaderLocation(
                        planSlug: planDetail.plan.slug,
                        sessionSlug: session.slug,
                        songSlug: resolvedSongSlug,
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
          onPressed: canMoveUp ? () => _reorderItem(context, ref, -1) : null,
          icon: const Icon(Icons.keyboard_arrow_up),
          tooltip: '${AppStrings.sessionItemMoveUpAction}: ${item.song.title}',
        ),
        IconButton(
          onPressed: canMoveDown ? () => _reorderItem(context, ref, 1) : null,
          icon: const Icon(Icons.keyboard_arrow_down),
          tooltip:
              '${AppStrings.sessionItemMoveDownAction}: ${item.song.title}',
        ),
        IconButton(
          onPressed: () => _deleteItem(context, ref),
          icon: const Icon(Icons.delete_outline),
          tooltip: '${AppStrings.sessionItemDeleteAction}: ${item.song.title}',
        ),
      ],
    );
  }

  Future<void> _reorderItem(
    BuildContext context,
    WidgetRef ref,
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
            planId: planDetail.plan.id,
            orderedSessionItemIds: currentOrder,
          ),
        );
    ref.invalidate(planningMutationEntriesProvider);
    ref.invalidate(planningPlanListProvider);
    ref.invalidate(planningPlanDetailProvider(planDetail.plan.id));
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
