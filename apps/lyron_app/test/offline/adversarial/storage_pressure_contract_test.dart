import 'package:drift/backends.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/budgeted_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_recovery.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

import '../../support/drift_test_setup.dart';

/// LF-T4 contract: when persisting a mutation FAILS at the storage layer
/// (simulated with a [QueryExecutor] decorator that throws on every INSERT,
/// standing in for a quota/IO failure), the app must give up droppable
/// catalog sources, retry once, and then surface a typed
/// [LocalStorageWriteFailure] to the caller. A swallowed failure would lose
/// the user's offline edit with no signal that it never reached storage.
///
/// This was a characterization probe until the mutation budget and eviction
/// policy landed; it now enforces the policy rather than observing behaviour.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('BudgetedPlanningMutationStore (LF-T4 storage pressure)', () {
    test('a failed write evicts droppable catalog sources, retries once, and '
        'surfaces a typed failure', () async {
      final failingExecutor = _InsertFailingExecutor(NativeDatabase.memory());
      final database = PlanningLocalDatabase.connect(failingExecutor);
      final localStore = DriftPlanningLocalStore(database);
      final catalogDatabase = SongCatalogDatabase.inMemory();
      addTearDown(database.close);
      addTearDown(catalogDatabase.close);

      await catalogDatabase
          .into(catalogDatabase.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              songId: 'song-1',
              source: 'body ' * 200,
            ),
          );

      var storageRevisionCount = 0;
      final store = BudgetedPlanningMutationStore(
        delegate: DriftPlanningMutationStore(
          database: database,
          localStore: localStore,
        ),
        accountant: PlanningStorageAccountant(database),
        recovery: LocalStorageWriteRecovery(
          evictor: SongCatalogEvictor(
            database: catalogDatabase,
            accountant: CatalogStorageAccountant(catalogDatabase),
            onStorageFootprintChanged: () => storageRevisionCount += 1,
          ),
        ),
        budget: const LocalStorageBudget(),
      );

      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      await expectLater(
        () => store.recordPlanCreate(
          context: context,
          draft: const PlanningPlanCreateMutationDraft(
            planId: 'plan-local-1',
            slug: 'weekend-service',
            name: 'Weekend Service',
          ),
        ),
        throwsA(
          isA<LocalStorageWriteFailure>().having(
            (failure) => failure.cause,
            'cause',
            isA<StorageQuotaSimulatedException>(),
          ),
        ),
      );

      // The source deletion committed before the guarded retry failed, so its
      // revision is independent of the outer write action's final error.
      expect(storageRevisionCount, 1);

      // Eviction actually ran: the droppable source is gone.
      final remainingSources = await catalogDatabase
          .select(catalogDatabase.cachedCatalogSources)
          .get();
      expect(remainingSources, isEmpty);

      // The failed mutation must not be visible later either: it never
      // reached storage, so there is nothing to read back. This guards
      // against a "throws but partially commits anyway" false positive.
      final pending = await store.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      expect(pending, isEmpty);
    });

    test('a write that fails once and succeeds on retry lands the '
        'mutation, after evicting droppable catalog sources', () async {
      final budget = _InsertFailureBudget(failuresRemaining: 1);
      final failingExecutor = _InsertFailingExecutor(
        NativeDatabase.memory(),
        budget,
      );
      final database = PlanningLocalDatabase.connect(failingExecutor);
      final localStore = DriftPlanningLocalStore(database);
      final catalogDatabase = SongCatalogDatabase.inMemory();
      addTearDown(database.close);
      addTearDown(catalogDatabase.close);

      await catalogDatabase
          .into(catalogDatabase.cachedCatalogSources)
          .insert(
            CachedCatalogSourcesCompanion.insert(
              userId: 'user-1',
              organizationId: 'org-1',
              snapshotVersion: 1,
              songId: 'song-1',
              source: 'body ' * 200,
            ),
          );

      final store = BudgetedPlanningMutationStore(
        delegate: DriftPlanningMutationStore(
          database: database,
          localStore: localStore,
        ),
        accountant: PlanningStorageAccountant(database),
        recovery: LocalStorageWriteRecovery(
          evictor: SongCatalogEvictor(
            database: catalogDatabase,
            accountant: CatalogStorageAccountant(catalogDatabase),
          ),
        ),
        budget: const LocalStorageBudget(),
      );

      const context = PlanningMutationContext(
        userId: 'user-1',
        organizationId: 'org-1',
      );

      // Does NOT throw: the first attempt fails (simulated storage
      // pressure), eviction runs, and the retry succeeds.
      await store.recordPlanCreate(
        context: context,
        draft: const PlanningPlanCreateMutationDraft(
          planId: 'plan-local-1',
          slug: 'weekend-service',
          name: 'Weekend Service',
        ),
      );

      // Eviction actually ran: the droppable source is gone.
      final remainingSources = await catalogDatabase
          .select(catalogDatabase.cachedCatalogSources)
          .get();
      expect(remainingSources, isEmpty);

      // The mutation really landed on the retry -- it must be readable
      // afterwards, not silently lost.
      final pending = await store.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      expect(pending, hasLength(1));
      expect(pending.single.aggregateId, 'plan-local-1');
    });
  });
}

/// Thrown by [_InsertFailingExecutor] in place of a real quota/IO error.
class StorageQuotaSimulatedException implements Exception {
  @override
  String toString() =>
      'StorageQuotaSimulatedException: simulated INSERT failure';
}

/// Shared mutable failure budget for [_InsertFailingExecutor] and
/// [_InsertFailingTransactionExecutor]. `null` means "unlimited": every
/// insert fails, forever, which is what the original "fails forever"
/// contract test needs. A finite budget fails only the next N inserts and
/// then lets the rest through, which is what the retry-succeeds contract
/// test needs. It is shared by reference across every executor spawned
/// from the same root (`beginTransaction`/`beginExclusive`), since Drift
/// issues the actual `INSERT` through a fresh [TransactionExecutor], not
/// the top-level [QueryExecutor].
class _InsertFailureBudget {
  _InsertFailureBudget({int? failuresRemaining})
    : _failuresRemaining = failuresRemaining;

  int? _failuresRemaining;

  bool shouldFail() {
    final remaining = _failuresRemaining;
    if (remaining == null) {
      return true;
    }
    if (remaining <= 0) {
      return false;
    }
    _failuresRemaining = remaining - 1;
    return true;
  }
}

/// A [QueryExecutor] decorator that delegates everything to [_delegate]
/// except `runInsert`, which throws for as long as [_budget] says to. By
/// default the budget is unlimited, so every INSERT fails -- this
/// deterministically reproduces "the storage layer failed this write"
/// (e.g. disk full, quota exceeded) without depending on platform-specific
/// IO failures. A finite budget instead reproduces "the storage layer
/// failed this write, but recovered" -- the shape LF-T4's retry exists to
/// handle.
class _InsertFailingExecutor implements QueryExecutor {
  _InsertFailingExecutor(this._delegate, [_InsertFailureBudget? budget])
    : _budget = budget ?? _InsertFailureBudget();

  final QueryExecutor _delegate;
  final _InsertFailureBudget _budget;

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
  Future<int> runInsert(String statement, List<Object?> args) {
    if (_budget.shouldFail()) {
      throw StorageQuotaSimulatedException();
    }
    return _delegate.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _delegate.runUpdate(statement, args);

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
      _InsertFailingTransactionExecutor(_delegate.beginTransaction(), _budget);

  @override
  QueryExecutor beginExclusive() =>
      _InsertFailingExecutor(_delegate.beginExclusive(), _budget);

  @override
  Future<void> close() => _delegate.close();
}

/// Transaction-scoped counterpart of [_InsertFailingExecutor]. Drift runs
/// `into(...).insertOnConflictUpdate(...)` inside a `database.transaction`
/// block via a [TransactionExecutor], not the top-level [QueryExecutor], so
/// the insert-failing behaviour must be mirrored here too, sharing the same
/// [_budget] instance so a finite budget is honoured across attempts.
class _InsertFailingTransactionExecutor implements TransactionExecutor {
  _InsertFailingTransactionExecutor(this._delegate, this._budget);

  final TransactionExecutor _delegate;
  final _InsertFailureBudget _budget;

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
  Future<int> runInsert(String statement, List<Object?> args) {
    if (_budget.shouldFail()) {
      throw StorageQuotaSimulatedException();
    }
    return _delegate.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _delegate.runUpdate(statement, args);

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
      _InsertFailingTransactionExecutor(_delegate.beginTransaction(), _budget);

  @override
  QueryExecutor beginExclusive() =>
      _InsertFailingExecutor(_delegate.beginExclusive(), _budget);

  @override
  Future<void> send() => _delegate.send();

  @override
  Future<void> rollback() => _delegate.rollback();

  @override
  Future<void> close() => _delegate.close();
}
