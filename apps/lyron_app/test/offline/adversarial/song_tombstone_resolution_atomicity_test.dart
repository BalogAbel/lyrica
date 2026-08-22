import 'package:drift/backends.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_recovery.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

import '../../support/drift_test_setup.dart';
import '../../support/insert_failing_executor.dart'
    show StorageQuotaSimulatedException;

/// N1 (human review, second remediation round on PR #64): the review's
/// literal claim -- "there is no transaction around the read and the write"
/// in `DriftSongCatalogStore._resolveCancelledSongCreate` -- does not hold
/// against the current code: `resolveCancelledSongCreate` (the public
/// method) already wraps the private read-check-write in
/// `_database.transaction()` (commit `baf3c23`, present before this round
/// started). Verified here rather than assumed: Drift serialises every
/// statement against a single-connection database while a transaction is
/// open, so nothing can land between the read and the write of that one
/// transaction.
///
/// What actually IS missing, verified against the planning twin
/// (`DriftPlanningMutationStore.resolveCancelledCreate`, wrapped by
/// `BudgetedPlanningMutationStore._recoveredWrite`):
///
/// 1. `resolveCancelledSongCreate` never went through the storage-recovery
///    boundary (`_guarded`) the way every other growing write in this class
///    does, and the way the planning twin does -- a storage-pressure
///    failure on the created:true write escaped as a raw exception instead
///    of the typed `LocalStorageWriteFailure` every sibling produces.
/// 2. There is no per-context write queue for song mutations (unlike
///    planning's `BudgetedPlanningMutationStore._enqueue`), so nothing
///    coordinates `resolveCancelledSongCreate` (transactional, atomic
///    against itself) against a SEPARATE call to `saveSongMutation` for the
///    SAME row -- reachable via `SongLibraryService.updateSong` racing a
///    stale songId reference against the tombstone's own resolution. This
///    is worse than "an edit gets lost": the CONFIRMED DELETE intent the
///    tombstone represents is what silently disappears, replaced by an
///    ordinary update, with no error and no future retry -- the opposite
///    direction from how the review framed it, and arguably worse because
///    it is the user's explicit delete that vanishes, not a later edit.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('resolveCancelledSongCreate storage recovery (N1)', () {
    Future<
      ({
        SongCatalogDatabase failingDatabase,
        DriftSongCatalogStore store,
        SongCatalogDatabase evictionDatabase,
        int Function() revisionCount,
      })
    >
    buildGuardedStore() async {
      final failingExecutor = _UpdateFailingExecutor(NativeDatabase.memory());
      final failingDatabase = SongCatalogDatabase.connect(failingExecutor);
      final evictionDatabase = SongCatalogDatabase.inMemory();

      // Seeded under a DIFFERENT (userId, organizationId) than the guarded
      // write below ('user-1'/'org-1'): since ADR-028's 2026-08-22
      // amendment, the active context a guarded catalog write is FOR is
      // excluded entirely from reactive eviction, so seeding under that
      // same active pair would mean nothing is ever evicted here. A
      // matching cached_catalog_snapshots row is also required -- without
      // one it is an "orphan" excluded from eviction for the unrelated
      // reason that there is nowhere to record sourcesEvictedAt.
      await evictionDatabase
          .into(evictionDatabase.cachedCatalogSnapshots)
          .insert(
            CachedCatalogSnapshotsCompanion.insert(
              userId: 'user-other',
              organizationId: 'org-other',
              snapshotVersion: 1,
              refreshedAt: DateTime.utc(2026, 7, 30),
            ),
          );
      await evictionDatabase
          .into(evictionDatabase.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-other',
              organizationId: 'org-other',
              snapshotVersion: 1,
              songId: 'droppable-song',
              source: 'body ' * 200,
            ),
          );

      var revisionCount = 0;
      final recovery = LocalStorageWriteRecovery(
        evictor: SongCatalogEvictor(
          database: evictionDatabase,
          accountant: CatalogStorageAccountant(evictionDatabase),
          onStorageFootprintChanged: () => revisionCount += 1,
        ),
      );
      final store = DriftSongCatalogStore(
        failingDatabase,
        writeRecovery: recovery,
      );

      return (
        failingDatabase: failingDatabase,
        store: store,
        evictionDatabase: evictionDatabase,
        revisionCount: () => revisionCount,
      );
    }

    test('a failed resolveCancelledSongCreate write evicts droppable catalog '
        'sources, retries once, and surfaces a typed LocalStorageWriteFailure '
        '-- not a raw storage exception', () async {
      final built = await buildGuardedStore();
      addTearDown(built.failingDatabase.close);
      addTearDown(built.evictionDatabase.close);

      // Seed the cancelling tombstone directly -- an INSERT, unaffected by
      // the executor's UPDATE-only failure.
      await built.store.saveSongMutation(
        const SongCatalogMutationDraft(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
          slug: 'alpha',
          title: 'Alpha',
          source: '{title: Alpha}',
          syncStatus: SongSyncStatus.cancelling,
        ),
      );

      await expectLater(
        () => built.store.resolveCancelledSongCreate(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
          created: true,
          acceptedVersion: 5,
        ),
        throwsA(
          isA<LocalStorageWriteFailure>().having(
            (failure) => failure.cause,
            'cause',
            isA<StorageQuotaSimulatedException>(),
          ),
        ),
        reason:
            'a storage-layer failure on this write must be recovered '
            '(evict + retry once) and, on final failure, wrapped as the '
            'same typed failure every other growing write in this class '
            'produces -- not escape as a raw exception the caller has no '
            'contract for',
      );

      expect(
        built.revisionCount(),
        1,
        reason: 'eviction must have actually run once',
      );
    });
  });

  group(
    'saveSongMutation refuses to overwrite a cancelling tombstone (N1)',
    () {
      test('a stale-reference edit reaching a cancelling tombstone is refused, '
          'not silently applied -- and the tombstone resolution that follows '
          'still sees the original, untouched row', () async {
        final database = SongCatalogDatabase.inMemory();
        addTearDown(database.close);
        final store = DriftSongCatalogStore(database);

        await store.saveSongMutation(
          const SongCatalogMutationDraft(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-1',
            slug: 'alpha',
            title: 'Alpha',
            source: '{title: Alpha}',
            syncStatus: SongSyncStatus.cancelling,
          ),
        );

        // No concurrency needed to expose this: BEFORE this fix,
        // saveSongMutation had no awareness of `cancelling` at all -- an
        // ordinary, purely sequential call reaching a tombstoned songId
        // (e.g. a `SongLibraryService.updateSong` call from a UI screen
        // that opened the song before it was deleted) silently succeeded,
        // overwriting the delete intent with a normal pendingUpdate. This
        // is the shape a stale UI reference takes in production: no
        // artificial timing required, just a call the app can make.
        await expectLater(
          () => store.saveSongMutation(
            const SongCatalogMutationDraft(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-1',
              slug: 'alpha',
              title: 'Alpha',
              source: '{title: Edited via a stale reference}',
              syncStatus: SongSyncStatus.pendingUpdate,
            ),
          ),
          throwsA(isA<LocalSongTombstoneConflictException>()),
          reason:
              'only resolveCancelledSongCreate may move a row off '
              '`cancelling` -- an ordinary write must be refused outright, '
              'not silently bury the user\'s already-confirmed delete '
              'intent under a normal update with no error and no trace',
        );

        final afterRefusedEdit = await store.readSongMutationBySongId(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        expect(
          afterRefusedEdit!.syncStatus,
          SongSyncStatus.cancelling.value,
          reason: 'the refused edit must not have landed at all',
        );
        expect(afterRefusedEdit.source, '{title: Alpha}');

        // The tombstone's OWN resolution -- unaffected by the refused edit
        // -- still runs correctly afterwards.
        final resolved = await store.resolveCancelledSongCreate(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
          created: true,
          acceptedVersion: 5,
        );
        expect(resolved, isTrue);

        final afterResolve = await store.readSongMutationBySongId(
          userId: 'user-1',
          organizationId: 'org-1',
          songId: 'song-1',
        );
        expect(
          afterResolve!.syncStatus,
          SongSyncStatus.pendingDelete.value,
          reason:
              'the confirmed delete intent must survive and reach a real '
              'pending delete -- the object exists on the backend now, and '
              'nothing else will ever trigger its deletion if this is lost',
        );
        expect(afterResolve.source, '{title: Alpha}');
      });

      test(
        'the pre-existing behaviour is unchanged for an ordinary (non-'
        'cancelling) row -- this guard is scoped to tombstones only',
        () async {
          final database = SongCatalogDatabase.inMemory();
          addTearDown(database.close);
          final store = DriftSongCatalogStore(database);

          await store.saveSongMutation(
            const SongCatalogMutationDraft(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-1',
              slug: 'alpha',
              title: 'Alpha',
              source: '{title: Alpha}',
              syncStatus: SongSyncStatus.pendingCreate,
            ),
          );

          // An ordinary edit onto a non-tombstoned row is untouched by this
          // fix and must keep succeeding exactly as before.
          await store.saveSongMutation(
            const SongCatalogMutationDraft(
              userId: 'user-1',
              organizationId: 'org-1',
              songId: 'song-1',
              slug: 'alpha',
              title: 'Alpha',
              source: '{title: Edited normally}',
              syncStatus: SongSyncStatus.pendingCreate,
            ),
          );

          final after = await store.readSongMutationBySongId(
            userId: 'user-1',
            organizationId: 'org-1',
            songId: 'song-1',
          );
          expect(after!.source, '{title: Edited normally}');
        },
      );
    },
  );
}

/// Like `InsertFailingExecutor` (test/support/insert_failing_executor.dart),
/// but fails `runUpdate` instead of `runInsert` -- resolveCancelledSongCreate's
/// created:true write (N1) is a targeted `UPDATE ... WHERE syncStatus =
/// cancelling`, not an insert, so the shared insert-failing executor cannot
/// exercise it. Unlimited budget: every UPDATE fails, forever. INSERT/DELETE
/// pass straight through, so seeding via saveSongMutation (an INSERT) is
/// unaffected.
class _UpdateFailingExecutor implements QueryExecutor {
  _UpdateFailingExecutor(this._delegate);

  final QueryExecutor _delegate;

  @override
  SqlDialect get dialect => _delegate.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _delegate.ensureOpen(user);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _delegate.runSelect(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _delegate.runInsert(statement, args);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    throw StorageQuotaSimulatedException();
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _delegate.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _delegate.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _delegate.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() =>
      _UpdateFailingTransactionExecutor(_delegate.beginTransaction());

  @override
  QueryExecutor beginExclusive() =>
      _UpdateFailingExecutor(_delegate.beginExclusive());

  @override
  Future<void> close() => _delegate.close();
}

class _UpdateFailingTransactionExecutor implements TransactionExecutor {
  _UpdateFailingTransactionExecutor(this._delegate);

  final TransactionExecutor _delegate;

  @override
  bool get supportsNestedTransactions => _delegate.supportsNestedTransactions;

  @override
  SqlDialect get dialect => _delegate.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _delegate.ensureOpen(user);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _delegate.runSelect(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _delegate.runInsert(statement, args);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) {
    throw StorageQuotaSimulatedException();
  }

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _delegate.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _delegate.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _delegate.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() =>
      _UpdateFailingTransactionExecutor(_delegate.beginTransaction());

  @override
  QueryExecutor beginExclusive() =>
      _UpdateFailingExecutor(_delegate.beginExclusive());

  @override
  Future<void> send() => _delegate.send();

  @override
  Future<void> rollback() => _delegate.rollback();

  @override
  Future<void> close() => _delegate.close();
}
