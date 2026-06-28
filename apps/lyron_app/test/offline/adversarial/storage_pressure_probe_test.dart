import 'package:drift/backends.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

import '../../support/drift_test_setup.dart';

/// LF-T4 (characterization probe): when persisting a mutation FAILS at the
/// storage layer (simulated here with a [QueryExecutor] decorator that
/// throws on every INSERT statement, standing in for a quota/IO failure),
/// the failure must be OBSERVABLE to the caller, not silently swallowed. A
/// swallowed failure would lose the user's offline edit without any signal
/// that it never reached local storage.
///
/// This probe documents CURRENT behaviour: [DriftPlanningMutationStore]
/// does not catch-and-ignore around its inserts, so a storage failure
/// propagates as a thrown exception out of the public write method. The
/// broader storage-eviction / quota-management policy (what the app does
/// in response to such a failure) is OUT OF SCOPE and deferred.
///
/// Note: closing the in-memory Drift connection before writing was tried
/// first and rejected as a fault injector -- drift transparently re-opens
/// a fresh (empty) in-memory database on the next statement, so the write
/// "succeeds" against a different database instead of failing. The
/// throwing-executor decorator below fails the actual INSERT statement
/// deterministically, which is what this probe needs.
void main() {
  suppressDriftMultipleDatabaseWarnings();

  group('DriftPlanningMutationStore (LF-T4 storage-pressure probe)', () {
    test('recordPlanCreate throws when the storage layer write fails '
        'instead of silently dropping the mutation', () async {
      final failingExecutor = _InsertFailingExecutor(NativeDatabase.memory());
      final database = PlanningLocalDatabase.connect(failingExecutor);
      final localStore = DriftPlanningLocalStore(database);
      final store = DriftPlanningMutationStore(
        database: database,
        localStore: localStore,
      );
      addTearDown(database.close);

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
        throwsA(isA<StorageQuotaSimulatedException>()),
      );

      // The failed mutation must not be visible later either: it never
      // reached storage, so there is nothing to read back. This guards
      // against a "throws but partially commits anyway" false positive.
      final pending = await store.readPendingMutations(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      expect(pending, isEmpty);
    });
  });
}

/// Thrown by [_InsertFailingExecutor] in place of a real quota/IO error.
class StorageQuotaSimulatedException implements Exception {
  @override
  String toString() =>
      'StorageQuotaSimulatedException: simulated INSERT failure';
}

/// A [QueryExecutor] decorator that delegates everything to [_delegate]
/// except `runInsert`, which always throws. This deterministically
/// reproduces "the storage layer failed this write" (e.g. disk full,
/// quota exceeded) without depending on platform-specific IO failures.
class _InsertFailingExecutor implements QueryExecutor {
  _InsertFailingExecutor(this._delegate);

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
  Future<int> runInsert(String statement, List<Object?> args) {
    throw StorageQuotaSimulatedException();
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
      _InsertFailingTransactionExecutor(_delegate.beginTransaction());

  @override
  QueryExecutor beginExclusive() =>
      _InsertFailingExecutor(_delegate.beginExclusive());

  @override
  Future<void> close() => _delegate.close();
}

/// Transaction-scoped counterpart of [_InsertFailingExecutor]. Drift runs
/// `into(...).insertOnConflictUpdate(...)` inside a `database.transaction`
/// block via a [TransactionExecutor], not the top-level [QueryExecutor], so
/// the insert-failing behaviour must be mirrored here too.
class _InsertFailingTransactionExecutor implements TransactionExecutor {
  _InsertFailingTransactionExecutor(this._delegate);

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
  Future<int> runInsert(String statement, List<Object?> args) {
    throw StorageQuotaSimulatedException();
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
      _InsertFailingTransactionExecutor(_delegate.beginTransaction());

  @override
  QueryExecutor beginExclusive() =>
      _InsertFailingExecutor(_delegate.beginExclusive());

  @override
  Future<void> send() => _delegate.send();

  @override
  Future<void> rollback() => _delegate.rollback();

  @override
  Future<void> close() => _delegate.close();
}
