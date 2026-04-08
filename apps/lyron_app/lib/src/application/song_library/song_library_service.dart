import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/song_catalog_read_repository.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';

class SongLibraryService {
  static const _maxCreateSlugRetries = 100;

  SongLibraryService(
    this._repository, [
    SongMutationStore? mutationStore,
    SongIdGenerator? idGenerator,
  ]) : _mutationStore = mutationStore,
       _idGenerator = idGenerator ?? generateUuidV4;

  final SongCatalogReadRepository _repository;
  final SongMutationStore? _mutationStore;
  final SongIdGenerator _idGenerator;

  Future<List<SongSummary>> listSongs({required ActiveCatalogContext context}) {
    return _repository.listSongs(
      userId: context.userId,
      organizationId: context.organizationId,
    );
  }

  Future<SongSource> getSongSource({
    required ActiveCatalogContext context,
    required String songId,
  }) {
    return _repository.getSongSource(
      userId: context.userId,
      organizationId: context.organizationId,
      songId: songId,
    );
  }

  Future<SongSummary?> getSongSummaryBySlug({
    required ActiveCatalogContext context,
    required String songSlug,
  }) {
    return _repository.getSongSummaryBySlug(
      userId: context.userId,
      organizationId: context.organizationId,
      songSlug: songSlug,
    );
  }

  Future<SongMutationRecord> createSong({
    required ActiveCatalogContext context,
    required String title,
    required String chordproSource,
  }) async {
    final mutationStore = _requireMutationStore();
    final songId = _idGenerator();

    for (var attempt = 0; attempt < _maxCreateSlugRetries; attempt += 1) {
      final slug = await mutationStore.allocateUniqueSlug(
        userId: context.userId,
        organizationId: context.organizationId,
        title: title,
      );
      final record = SongMutationRecord(
        id: songId,
        organizationId: context.organizationId,
        slug: slug,
        title: title,
        chordproSource: chordproSource,
        version: 1,
        baseVersion: null,
        syncStatus: SongSyncStatus.pendingCreate,
      );
      try {
        await mutationStore.upsertSong(userId: context.userId, record: record);
        return record;
      } on Object catch (error) {
        if (error is! LocalSongSlugConflictException) {
          rethrow;
        }
      }
    }
    throw StateError(
      'Failed to allocate a unique local song slug after $_maxCreateSlugRetries attempts.',
    );
  }

  Future<SongMutationRecord> updateSong({
    required ActiveCatalogContext context,
    required String songId,
    required String title,
    required String chordproSource,
  }) async {
    final mutationStore = _requireMutationStore();
    final existing = await mutationStore.readById(
      userId: context.userId,
      organizationId: context.organizationId,
      songId: songId,
    );
    if (existing == null) {
      throw StateError('Song mutation record not found: $songId');
    }
    if (existing.syncStatus == SongSyncStatus.conflict) {
      throw SongConflictResolutionRequiredException(songId);
    }

    final updated = existing.copyWith(
      title: title,
      chordproSource: chordproSource,
      baseVersion: existing.version,
      syncStatus: existing.syncStatus == SongSyncStatus.pendingCreate
          ? SongSyncStatus.pendingCreate
          : SongSyncStatus.pendingUpdate,
      clearErrorCode: true,
      clearErrorMessage: true,
    );
    await mutationStore.upsertSong(userId: context.userId, record: updated);
    return updated;
  }

  Future<SongMutationRecord> deleteSong({
    required ActiveCatalogContext context,
    required String songId,
  }) async {
    final mutationStore = _requireMutationStore();
    final references = await mutationStore.countReferencingSessionItems(
      userId: context.userId,
      organizationId: context.organizationId,
      songId: songId,
    );
    if (references > 0) {
      throw SongDeleteBlockedException(songId);
    }

    final existing = await mutationStore.readById(
      userId: context.userId,
      organizationId: context.organizationId,
      songId: songId,
    );
    if (existing == null) {
      throw StateError('Song mutation record not found: $songId');
    }
    if (existing.syncStatus == SongSyncStatus.conflict) {
      throw SongConflictResolutionRequiredException(songId);
    }

    if (existing.syncStatus == SongSyncStatus.pendingCreate) {
      await mutationStore.deleteSong(
        userId: context.userId,
        organizationId: context.organizationId,
        songId: songId,
      );
      return existing.copyWith(syncStatus: SongSyncStatus.pendingDelete);
    }

    final deleted = existing.copyWith(
      baseVersion: existing.version,
      syncStatus: SongSyncStatus.pendingDelete,
      clearErrorCode: true,
      clearErrorMessage: true,
    );
    await mutationStore.upsertSong(userId: context.userId, record: deleted);
    return deleted;
  }

  SongMutationStore _requireMutationStore() {
    final mutationStore = _mutationStore;
    if (mutationStore == null) {
      throw StateError('Song mutation store is unavailable.');
    }
    return mutationStore;
  }
}
