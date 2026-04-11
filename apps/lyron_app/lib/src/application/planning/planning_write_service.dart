import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';

class PlanningWriteContext {
  const PlanningWriteContext({
    required this.userId,
    required this.organizationId,
  });

  final String userId;
  final String organizationId;
}

class PlanCreateDraft {
  const PlanCreateDraft({
    required this.name,
    this.description,
    this.scheduledFor,
  });

  final String name;
  final String? description;
  final DateTime? scheduledFor;
}

class PlanEditDraft {
  const PlanEditDraft({
    required this.planId,
    required this.name,
    this.description,
    this.scheduledFor,
  });

  final String planId;
  final String name;
  final String? description;
  final DateTime? scheduledFor;
}

class SessionCreateDraft {
  const SessionCreateDraft({required this.planId, required this.name});

  final String planId;
  final String name;
}

class SessionRenameDraft {
  const SessionRenameDraft({
    required this.sessionId,
    required this.planId,
    required this.name,
  });

  final String sessionId;
  final String planId;
  final String name;
}

class SessionDeleteDraft {
  const SessionDeleteDraft({required this.sessionId, required this.planId});

  final String sessionId;
  final String planId;
}

class SessionReorderDraft {
  const SessionReorderDraft({
    required this.planId,
    required this.orderedSessionIds,
  });

  final String planId;
  final List<String> orderedSessionIds;
}

class SessionItemCreateSongDraft {
  const SessionItemCreateSongDraft({
    required this.sessionId,
    required this.planId,
    required this.songId,
  });

  final String sessionId;
  final String planId;
  final String songId;
}

class SessionItemDeleteDraft {
  const SessionItemDeleteDraft({
    required this.sessionItemId,
    required this.sessionId,
    required this.planId,
  });

  final String sessionItemId;
  final String sessionId;
  final String planId;
}

class SessionItemReorderDraft {
  const SessionItemReorderDraft({
    required this.sessionId,
    required this.planId,
    required this.orderedSessionItemIds,
  });

  final String sessionId;
  final String planId;
  final List<String> orderedSessionItemIds;
}

class SessionDeleteBlockedException implements Exception {
  const SessionDeleteBlockedException(this.sessionId);

  final String sessionId;
}

class DuplicateSessionSongException implements Exception {
  const DuplicateSessionSongException(this.sessionId, this.songId);

  final String sessionId;
  final String songId;
}

class PlanningSongUnavailableException implements Exception {
  const PlanningSongUnavailableException(this.songId);

  final String songId;
}

class PlanningWriteContextMismatchException implements Exception {
  const PlanningWriteContextMismatchException();
}

typedef PlanningWriteActiveContextReader =
    Future<ActivePlanningReadContext?> Function();
typedef PlanningWriteSyncScheduler =
    Future<void> Function(PlanningWriteContext context);
typedef PlanningVisibleSongReader =
    Future<List<SongSummary>> Function({
      required String userId,
      required String organizationId,
    });

class PlanningWriteService {
  static const _positionStep = 1;

  PlanningWriteService(
    this._repository, {
    required PlanningMutationStore mutationStore,
    PlanningVisibleSongReader? listVisibleSongs,
    required PlanningWriteActiveContextReader activeContextReader,
    PlanningWriteSyncScheduler? syncScheduler,
    PlanningIdGenerator? idGenerator,
  }) : _mutationStore = mutationStore,
       _listVisibleSongs = listVisibleSongs ?? _defaultVisibleSongs,
       _activeContextReader = activeContextReader,
       _syncScheduler = syncScheduler,
       _idGenerator = idGenerator ?? generatePlanningUuidV4;

  final PlanningRepository _repository;
  final PlanningMutationStore _mutationStore;
  final PlanningVisibleSongReader _listVisibleSongs;
  final PlanningWriteActiveContextReader _activeContextReader;
  final PlanningWriteSyncScheduler? _syncScheduler;
  final PlanningIdGenerator _idGenerator;

  static Future<List<SongSummary>> _defaultVisibleSongs({
    required String userId,
    required String organizationId,
  }) async => const [];

  Future<PlanningMutationRecord> createPlan({
    required PlanningWriteContext context,
    required PlanCreateDraft draft,
  }) async {
    await _requireMatchingContext(context);
    final planId = _idGenerator();
    final slug = await _mutationStore.allocatePlanSlug(
      userId: context.userId,
      organizationId: context.organizationId,
      name: draft.name,
    );
    await _mutationStore.recordPlanCreate(
      context: PlanningMutationContext(
        userId: context.userId,
        organizationId: context.organizationId,
      ),
      draft: PlanningPlanCreateMutationDraft(
        planId: planId,
        slug: slug,
        name: draft.name,
        description: draft.description,
        scheduledFor: draft.scheduledFor,
      ),
    );
    final createdRecord = await _mutationStore.readMutation(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: PlanningMutationKind.planCreate.aggregateType,
      aggregateId: planId,
    );
    await _scheduleSync(context);
    return createdRecord!;
  }

  Future<void> editPlan({
    required PlanningWriteContext context,
    required PlanEditDraft draft,
  }) {
    return _editPlanInternal(context: context, draft: draft);
  }

  Future<void> createSession({
    required PlanningWriteContext context,
    required SessionCreateDraft draft,
  }) async {
    await _requireMatchingContext(context);
    final detail = await _repository.getPlanDetail(draft.planId);
    final nextPosition = detail.sessions.isEmpty
        ? _positionStep
        : detail.sessions.last.position + _positionStep;
    final sessionId = _idGenerator();
    final slug = await _mutationStore.allocateSessionSlug(
      userId: context.userId,
      organizationId: context.organizationId,
      planId: draft.planId,
      name: draft.name,
    );
    await _mutationStore.recordSessionCreate(
      context: PlanningMutationContext(
        userId: context.userId,
        organizationId: context.organizationId,
      ),
      draft: PlanningSessionCreateMutationDraft(
        sessionId: sessionId,
        planId: draft.planId,
        slug: slug,
        name: draft.name,
        position: nextPosition,
      ),
    );
    await _scheduleSync(context);
  }

  Future<void> renameSession({
    required PlanningWriteContext context,
    required SessionRenameDraft draft,
  }) {
    return _renameSessionInternal(context: context, draft: draft);
  }

  Future<void> deleteSession({
    required PlanningWriteContext context,
    required SessionDeleteDraft draft,
  }) async {
    await _requireMatchingContext(context);
    final detail = await _repository.getPlanDetail(draft.planId);
    final session = detail.sessions.firstWhere(
      (candidate) => candidate.id == draft.sessionId,
    );
    if (session.items.isNotEmpty) {
      throw SessionDeleteBlockedException(draft.sessionId);
    }

    await _mutationStore.recordSessionDelete(
      context: PlanningMutationContext(
        userId: context.userId,
        organizationId: context.organizationId,
      ),
      draft: PlanningSessionDeleteMutationDraft(
        sessionId: draft.sessionId,
        planId: draft.planId,
        baseVersion: session.version,
      ),
    );
    await _scheduleSync(context);
  }

  Future<void> reorderSessions({
    required PlanningWriteContext context,
    required SessionReorderDraft draft,
  }) async {
    await _requireMatchingContext(context);
    final detail = await _repository.getPlanDetail(draft.planId);
    await _mutationStore.recordSessionReorder(
      context: PlanningMutationContext(
        userId: context.userId,
        organizationId: context.organizationId,
      ),
      draft: PlanningSessionReorderMutationDraft(
        planId: draft.planId,
        orderedSessionIds: draft.orderedSessionIds,
        baseVersion: detail.plan.version,
      ),
    );
    await _scheduleSync(context);
  }

  Future<void> addSongSessionItem({
    required PlanningWriteContext context,
    required SessionItemCreateSongDraft draft,
  }) async {
    await _requireMatchingContext(context);
    final detail = await _repository.getPlanDetail(draft.planId);
    final session = detail.sessions.firstWhere(
      (candidate) => candidate.id == draft.sessionId,
    );
    if (session.items.any((item) => item.song.id == draft.songId)) {
      throw DuplicateSessionSongException(draft.sessionId, draft.songId);
    }

    final visibleSongs = await _listVisibleSongs(
      userId: context.userId,
      organizationId: context.organizationId,
    );
    final song = visibleSongs.where(
      (candidate) => candidate.id == draft.songId,
    );
    if (song.isEmpty) {
      throw PlanningSongUnavailableException(draft.songId);
    }

    final nextPosition = session.items.isEmpty
        ? _positionStep
        : session.items.last.position + _positionStep;
    await _mutationStore.recordSessionItemCreateSong(
      context: PlanningMutationContext(
        userId: context.userId,
        organizationId: context.organizationId,
      ),
      draft: PlanningSessionItemCreateSongMutationDraft(
        sessionItemId: _idGenerator(),
        sessionId: draft.sessionId,
        planId: draft.planId,
        songId: draft.songId,
        songTitle: song.first.title,
        position: nextPosition,
        baseVersion: session.version,
      ),
    );
    await _scheduleSync(context);
  }

  Future<void> deleteSessionItem({
    required PlanningWriteContext context,
    required SessionItemDeleteDraft draft,
  }) async {
    await _requireMatchingContext(context);
    final detail = await _repository.getPlanDetail(draft.planId);
    final session = detail.sessions.firstWhere(
      (candidate) => candidate.id == draft.sessionId,
    );
    await _mutationStore.recordSessionItemDelete(
      context: PlanningMutationContext(
        userId: context.userId,
        organizationId: context.organizationId,
      ),
      draft: PlanningSessionItemDeleteMutationDraft(
        sessionItemId: draft.sessionItemId,
        sessionId: draft.sessionId,
        planId: draft.planId,
        baseVersion: session.version,
      ),
    );
    await _scheduleSync(context);
  }

  Future<void> reorderSessionItems({
    required PlanningWriteContext context,
    required SessionItemReorderDraft draft,
  }) async {
    await _requireMatchingContext(context);
    final detail = await _repository.getPlanDetail(draft.planId);
    final session = detail.sessions.firstWhere(
      (candidate) => candidate.id == draft.sessionId,
    );
    await _mutationStore.recordSessionItemReorder(
      context: PlanningMutationContext(
        userId: context.userId,
        organizationId: context.organizationId,
      ),
      draft: PlanningSessionItemReorderMutationDraft(
        sessionId: draft.sessionId,
        planId: draft.planId,
        orderedSessionItemIds: draft.orderedSessionItemIds,
        baseVersion: session.version,
      ),
    );
    await _scheduleSync(context);
  }

  Future<void> _editPlanInternal({
    required PlanningWriteContext context,
    required PlanEditDraft draft,
  }) async {
    await _requireMatchingContext(context);
    final detail = await _repository.getPlanDetail(draft.planId);
    await _mutationStore.recordPlanEdit(
      context: PlanningMutationContext(
        userId: context.userId,
        organizationId: context.organizationId,
      ),
      draft: PlanningPlanEditMutationDraft(
        planId: draft.planId,
        name: draft.name,
        description: draft.description,
        scheduledFor: draft.scheduledFor,
        baseVersion: detail.plan.version,
      ),
    );
    await _scheduleSync(context);
  }

  Future<void> _renameSessionInternal({
    required PlanningWriteContext context,
    required SessionRenameDraft draft,
  }) async {
    await _requireMatchingContext(context);
    final detail = await _repository.getPlanDetail(draft.planId);
    final session = detail.sessions.firstWhere(
      (candidate) => candidate.id == draft.sessionId,
    );
    await _mutationStore.recordSessionRename(
      context: PlanningMutationContext(
        userId: context.userId,
        organizationId: context.organizationId,
      ),
      draft: PlanningSessionRenameMutationDraft(
        sessionId: draft.sessionId,
        planId: draft.planId,
        name: draft.name,
        baseVersion: session.version,
      ),
    );
    await _scheduleSync(context);
  }

  Future<void> _requireMatchingContext(PlanningWriteContext context) async {
    final activeContext = await _activeContextReader();
    if (activeContext == null ||
        activeContext.userId != context.userId ||
        activeContext.organizationId != context.organizationId) {
      throw const PlanningWriteContextMismatchException();
    }
  }

  Future<void> _scheduleSync(PlanningWriteContext context) async {
    final syncScheduler = _syncScheduler;
    if (syncScheduler == null) {
      return;
    }
    await syncScheduler(context);
  }
}
