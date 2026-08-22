// Shared fault-injection shape for storage-pressure tests, extracted from
// test/offline/adversarial/storage_pressure_contract_test.dart so every test
// that needs to simulate "the storage layer failed this write" (a quota/IO
// failure) can reuse the same executor-decorator instead of each inventing
// its own. storage_pressure_contract_test.dart itself keeps its own private
// copy unchanged -- it is pinned as a regression contract and must not be
// touched by this widening.

import 'package:drift/backends.dart';
import 'package:lyron_app/src/application/storage/local_storage_exhaustion_signal.dart';

/// Thrown by [InsertFailingExecutor] in place of a real quota/IO error.
///
/// Implements [LocalStorageExhaustionSignal]: this class already represents
/// "genuine storage exhaustion" by name and by every existing test's intent
/// (LF-T4's evict-and-retry path), so after [LocalStorageWriteRecovery.guard]
/// narrowed its trigger to concrete exhaustion signals only (D6), this
/// exception must keep opting into that treatment explicitly rather than
/// falling through to the new "any other Exception surfaces immediately, no
/// eviction" branch.
class StorageQuotaSimulatedException implements LocalStorageExhaustionSignal {
  @override
  String toString() =>
      'StorageQuotaSimulatedException: simulated INSERT failure';
}

/// Shared mutable failure budget for [InsertFailingExecutor] and
/// [InsertFailingTransactionExecutor]. `null` means "unlimited": every
/// insert fails, forever. A finite budget fails only the next N inserts and
/// then lets the rest through, reproducing "the storage layer failed this
/// write, but recovered" -- the shape a retry-succeeds test needs. It is
/// shared by reference across every executor spawned from the same root
/// (`beginTransaction`/`beginExclusive`), since Drift issues the actual
/// `INSERT` through a fresh [TransactionExecutor], not the top-level
/// [QueryExecutor].
class InsertFailureBudget {
  InsertFailureBudget({this._failuresRemaining});

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
/// without depending on platform-specific IO failures.
class InsertFailingExecutor implements QueryExecutor {
  InsertFailingExecutor(this._delegate, [InsertFailureBudget? budget])
    : _budget = budget ?? InsertFailureBudget();

  final QueryExecutor _delegate;
  final InsertFailureBudget _budget;

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
      InsertFailingTransactionExecutor(_delegate.beginTransaction(), _budget);

  @override
  QueryExecutor beginExclusive() =>
      InsertFailingExecutor(_delegate.beginExclusive(), _budget);

  @override
  Future<void> close() => _delegate.close();
}

/// Transaction-scoped counterpart of [InsertFailingExecutor]. Drift runs
/// batched/upsert writes inside a `database.transaction` block via a
/// [TransactionExecutor], not the top-level [QueryExecutor], so the
/// insert-failing behaviour must be mirrored here too, sharing the same
/// [_budget] instance so a finite budget is honoured across attempts.
class InsertFailingTransactionExecutor implements TransactionExecutor {
  InsertFailingTransactionExecutor(this._delegate, this._budget);

  final TransactionExecutor _delegate;
  final InsertFailureBudget _budget;

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
      InsertFailingTransactionExecutor(_delegate.beginTransaction(), _budget);

  @override
  QueryExecutor beginExclusive() =>
      InsertFailingExecutor(_delegate.beginExclusive(), _budget);

  @override
  Future<void> send() => _delegate.send();

  @override
  Future<void> rollback() => _delegate.rollback();

  @override
  Future<void> close() => _delegate.close();
}
