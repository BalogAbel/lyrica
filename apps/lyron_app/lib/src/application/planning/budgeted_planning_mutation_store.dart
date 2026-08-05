import 'dart:async';

import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_recovery.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';

/// Enforces the two storage ladders (LF-T3, LF-T4) around a
/// [PlanningMutationStore] delegate.
///
/// Writes that can introduce or grow a pending aggregate are guarded by the
/// mutation budget: BEFORE the write reaches the delegate, the local
/// mutation store's current byte footprint is measured, and if it is
/// already at or past [LocalStorageBudget.mutationRefuseBytes], the write is
/// refused with a [PlanningMutationBudgetExceededException] and never
/// touches the delegate at all. A refusal therefore means "the store was
/// already over budget", not "this write would push it over" -- so the
/// store can overshoot the budget by at most one mutation. That is accepted:
/// the budget exists to bound growth, not to cap it to the byte, and the
/// accountant's byte count is an explicit proxy rather than a true size.
///
/// Nothing is ever undone, deleted, or rewritten to enforce this budget.
/// Pending mutations are unsynced user intent with no other copy, so a
/// refusal must never destroy one -- including, critically, a write that
/// folds into an aggregate with mutation still pending from an earlier
/// write (for example a `recordPlanEdit` on a plan whose create is still
/// unsynced): refusing the fold must leave that earlier pending mutation
/// completely intact. Catalog eviction cannot relieve a budget refusal
/// either, because pending mutations are never evictable -- attempting it
/// here would only destroy cached data for no benefit. The remedy is to
/// sync or discard.
///
/// Reads and slug allocation (`readPendingMutations`,
/// `readActionableMutations`, `readAllMutations`, `readMutation`,
/// `allocatePlanSlug`, `allocateSessionSlug`, `hasUnsyncedMutations`) pass
/// straight through, entirely outside the write queue: nothing about them
/// can race a write in a way that matters here.
///
/// `saveSyncAttemptResult`, `retryMutation` and `clearMutation` are never
/// budget-guarded -- guarding any of them would turn the budget into a trap
/// with no recovery path, and `clearMutation` in particular is the only way
/// out once the store is full. But all three DO go through the same
/// per-context write queue as the `record*` admissions (see `_writeQueue`
/// below), because a `record*` call's collapse decision
/// (`_collapsesPendingCreate`) and the delegate's own re-check inside its
/// transaction are two separate reads of the same aggregate -- without
/// shared queue ordering, a `clearMutation` for that aggregate could land in
/// between them (exactly what sync does immediately after a mutation is
/// accepted), so the delegate's re-check would find nothing to collapse and
/// write a brand-new row that never passed a budget check. Only
/// `saveSyncAttemptResult` additionally goes through the storage-recovery
/// boundary (see below): it is the one of the three that can grow the
/// stored record (it adds `errorCode`/`errorMessage`), and it is also the
/// durable marker `PlanningMutationSyncController._run` writes immediately
/// after a successful remote send, so a swallowed or unrecovered failure on
/// it would leave the record `pending` and cause the next sync to resend a
/// mutation the backend already accepted (ADR-019 exactly-once). Neither
/// `retryMutation` (it clears `errorCode`/`errorMessage` and rebases the
/// base version -- it does not meaningfully grow the row) nor
/// `clearMutation` (a pure delete) needs the recovery boundary; they only
/// need the same ordering.
///
/// `recordSessionDelete` and `recordSessionItemDelete` are budget-guarded
/// like every other `record*` write EXCEPT when the write itself would
/// shrink the store: if the aggregate they target still holds a pending
/// create (a session or session item that never reached the backend), the
/// delete collapses that create rather than adding a row, and is admitted
/// regardless of budget. That decision is read from the store, not inferred
/// from the method name -- a delete against an aggregate that is not a
/// pending create genuinely grows the store and stays subject to the
/// budget. See `_collapsesPendingCreate`.
///
/// The measure-check-write sequence for each `record*` call, and every
/// `saveSyncAttemptResult`/`retryMutation`/`clearMutation` call, is
/// serialised per `(userId, organizationId)` -- see `_writeQueue` -- so the
/// "at most one mutation past the threshold" bound above holds under
/// concurrency: only one write for a context is ever in flight at a time.
/// Writes for different contexts never block each other.
///
/// A `record*` write that reaches the delegate and fails at the storage
/// layer (not a domain rejection such as [LocalPlanningSlugConflictException])
/// is treated as storage pressure (LF-T4) by [LocalStorageWriteRecovery.guard],
/// the same shared boundary every other growing local write in the app uses
/// (D1): droppable catalog sources are evicted and the write is retried
/// once. `saveSyncAttemptResult` goes through the identical boundary, for
/// the reason above. Every guarded write is an upsert keyed by its
/// aggregate, so the retry is idempotent -- a partially applied first
/// attempt cannot duplicate. If the retry still fails, the failure is
/// surfaced as a typed [LocalStorageWriteFailure] rather than swallowed.
/// This class no longer implements that policy itself -- it only decides
/// WHEN to invoke `_recovery.guard` (after the budget/collapse admission, or
/// directly for `saveSyncAttemptResult`), not HOW a storage-layer failure
/// recovers.
class BudgetedPlanningMutationStore implements PlanningMutationStore {
  BudgetedPlanningMutationStore({
    required PlanningMutationStore delegate,
    required PlanningStorageAccountant accountant,
    required SongCatalogEvictor evictor,
    required LocalStorageBudget budget,
  }) : _delegate = delegate,
       _accountant = accountant,
       _recovery = LocalStorageWriteRecovery(evictor: evictor),
       _budget = budget;

  final PlanningMutationStore _delegate;
  final PlanningStorageAccountant _accountant;
  final LocalStorageWriteRecovery _recovery;
  final LocalStorageBudget _budget;

  // Per-(userId, organizationId) write queue, shared by the nine `record*`
  // admissions AND by saveSyncAttemptResult/retryMutation/clearMutation.
  // Two reasons this queue has to cover all of those, not just `record*`:
  //
  // 1. Without it, the measure, check and write in _admitAndWrite are three
  //    separate `await` points with nothing stopping a second `record*`
  //    call for the same context from measuring the same pre-write
  //    footprint and also passing the check -- overshooting the "at most
  //    one mutation past the threshold" guarantee.
  // 2. A `record*` collapse decision (`_collapsesPendingCreate`, read
  //    early, before the queued turn even starts) and the delegate's own
  //    re-check of the same aggregate (read late, inside its own
  //    transaction, once the queued turn runs) are two separate reads.
  //    `clearMutation` is exactly what sync calls, for that same aggregate,
  //    immediately after a mutation is accepted -- if it could run in
  //    between those two reads, the delegate would find nothing left to
  //    collapse and would write a brand-new row that never passed a budget
  //    check. Queuing clearMutation (and retryMutation, for the same
  //    aggregate-race reason) behind the same per-context turn closes that
  //    window: once a `record*` call's turn starts, no other write for the
  //    same context can run until it finishes.
  //
  // Keyed the same way as PlanningMutationSyncController._inFlight so a
  // write for one user/organization never blocks a write for another, but
  // unlike that single-flight map (which coalesces concurrent callers onto
  // ONE shared future), every call here must run its own write and report
  // its own outcome, so callers are chained onto the queue instead of being
  // handed someone else's future.
  final Map<String, Future<void>> _writeQueue = {};

  /// Chains [task] onto the per-`(userId, organizationId)` write queue and
  /// returns a future for its own outcome. No re-entrancy: [task] (and
  /// everything it calls -- `_admitAndWrite`, `_recovery.guard`,
  /// `_collapsesPendingCreate`'s `_delegate.readMutation`, every `_delegate`
  /// write) must never itself call back into `_enqueue`/`_guardedWrite`/
  /// `_recoveredWrite`/`_queuedWrite` for the SAME instance, or the second
  /// call would await a queue tail that can only resolve after the first
  /// call (which is what's blocking it) completes -- a self-deadlock. This
  /// holds here because `_delegate` is a plain `PlanningMutationStore`
  /// (`DriftPlanningMutationStore` in production) with no reference back to
  /// this decorator, so nothing it does can re-enter the queue.
  Future<T> _enqueue<T>(
    PlanningMutationContext context,
    Future<T> Function() task,
  ) {
    final key = '${context.userId}_${context.organizationId}';
    final previous = _writeQueue[key] ?? Future<void>.value();

    // `previous` is always already-settled-safe (see `tail` below), so
    // chaining onto it just waits for our turn -- it never itself throws.
    final result = previous.then((_) => task());

    // Publish our own completion, success or failure, as the new queue tail
    // so the next call for this context waits for us. Neutralise the error
    // for chaining purposes only: one write's failure must never poison the
    // queue for the next write on the same context. `result` (returned
    // below) still carries the real outcome back to this call's caller.
    final tail = result.then((_) {}, onError: (_) {});
    _writeQueue[key] = tail;
    unawaited(
      tail.whenComplete(() {
        // Only drop the entry if nothing has queued behind us -- a
        // concurrent call may already have replaced it with its own tail.
        if (identical(_writeQueue[key], tail)) {
          _writeQueue.remove(key);
        }
      }),
    );

    return result;
  }

  /// Queued budget/collapse admission followed by the storage-recovery
  /// boundary. Used by the nine `record*` methods.
  Future<void> _guardedWrite(
    PlanningMutationContext context,
    Future<void> Function() write, {
    Future<bool> Function()? isCollapse,
  }) => _enqueue(
    context,
    () => _admitAndWrite(context, write, isCollapse: isCollapse),
  );

  /// Queued, but with no budget admission -- just the storage-recovery
  /// boundary. Used by `saveSyncAttemptResult`: it can grow the stored
  /// record (it adds `errorCode`/`errorMessage`) so a storage failure on it
  /// needs the same evict-and-retry-once treatment as a `record*` write,
  /// but it must never be refused for budget reasons -- see the class doc
  /// for why (the ADR-019 exactly-once marker).
  Future<T> _recoveredWrite<T>(
    PlanningMutationContext context,
    Future<T> Function() write,
  ) => _enqueue(context, () => _recovery.guard(write));

  /// Queued, with neither budget admission nor the recovery boundary. Used
  /// by `retryMutation` and `clearMutation`: neither can meaningfully grow
  /// the store (see the class doc), so there is nothing to recover from --
  /// they only need the same ordering as every other write for this
  /// context.
  Future<T> _queuedWrite<T>(
    PlanningMutationContext context,
    Future<T> Function() write,
  ) => _enqueue(context, write);

  Future<void> _admitAndWrite(
    PlanningMutationContext context,
    Future<void> Function() write, {
    Future<bool> Function()? isCollapse,
  }) async {
    if (isCollapse == null || !await isCollapse()) {
      final mutationBytes = await _accountant.measureMutationBytes(
        userId: context.userId,
        organizationId: context.organizationId,
      );
      if (_budget.refusesNewMutation(mutationBytes)) {
        throw PlanningMutationBudgetExceededException(
          mutationBytes: mutationBytes,
          refuseBytes: _budget.mutationRefuseBytes,
        );
      }
    }

    // The domain-rejection / Error / storage-pressure policy itself lives in
    // LocalStorageWriteRecovery.guard now, shared with every other growing
    // local write (D1). LocalPlanningSlugConflictException implements
    // LocalStorageDomainRejection, so it still passes through untouched
    // there exactly as it did when this class caught it directly.
    await _recovery.guard(write);
  }

  /// Whether a delete targeting `(aggregateType, aggregateId)` would
  /// collapse a still-pending create rather than grow the store -- i.e. the
  /// existing mutation row at that aggregate key is [pendingCreateKind].
  ///
  /// This must decide from store state, not from the calling method's name:
  /// a delete against an aggregate with no pending create (including one
  /// with no local mutation at all, or one folded into pending edit/rename)
  /// genuinely adds a row and stays subject to the budget.
  ///
  /// Mirrors, rather than duplicates, the delegate's own collapse check
  /// (`existing?.kind == <pendingCreateKind>` in
  /// DriftPlanningMutationStore.recordSessionDelete /
  /// recordSessionItemDelete) so the two can never disagree: both read
  /// through the same [PlanningMutationStore.readMutation] contract keyed by
  /// the same `(aggregateType, aggregateId)`, and both compare only `kind`.
  Future<bool> _collapsesPendingCreate({
    required PlanningMutationContext context,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationKind pendingCreateKind,
  }) async {
    final existing = await _delegate.readMutation(
      userId: context.userId,
      organizationId: context.organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
    );
    return existing?.kind == pendingCreateKind;
  }

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordPlanCreate(context: context, draft: draft),
  );

  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordPlanEdit(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionCreate(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionRename(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionDelete(context: context, draft: draft),
    isCollapse: () => _collapsesPendingCreate(
      context: context,
      aggregateType: PlanningMutationKind.sessionDelete.aggregateType,
      aggregateId: draft.sessionId,
      pendingCreateKind: PlanningMutationKind.sessionCreate,
    ),
  );

  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionReorder(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionItemCreateSong(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionItemDelete(context: context, draft: draft),
    isCollapse: () => _collapsesPendingCreate(
      context: context,
      aggregateType: PlanningMutationKind.sessionItemDelete.aggregateType,
      aggregateId: draft.sessionItemId,
      pendingCreateKind: PlanningMutationKind.sessionItemCreateSong,
    ),
  );

  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) => _guardedWrite(
    context,
    () => _delegate.recordSessionItemReorder(context: context, draft: draft),
  );

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  }) => _delegate.readPendingMutations(
    userId: userId,
    organizationId: organizationId,
  );

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) => _delegate.readActionableMutations(
    userId: userId,
    organizationId: organizationId,
  );

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) => _delegate.readAllMutations(
    userId: userId,
    organizationId: organizationId,
  );

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => _delegate.readMutation(
    userId: userId,
    organizationId: organizationId,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
  );

  @override
  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  }) => _delegate.allocatePlanSlug(
    userId: userId,
    organizationId: organizationId,
    name: name,
  );

  @override
  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  }) => _delegate.allocateSessionSlug(
    userId: userId,
    organizationId: organizationId,
    planId: planId,
    name: name,
  );

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) =>
      _delegate.hasUnsyncedMutations(userId: userId);

  @override
  Future<int?> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  }) => _recoveredWrite(
    PlanningMutationContext(userId: userId, organizationId: organizationId),
    () => _delegate.saveSyncAttemptResult(
      userId: userId,
      organizationId: organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      syncStatus: syncStatus,
      errorCode: errorCode,
      errorMessage: errorMessage,
      expectedRevision: expectedRevision,
    ),
  );

  @override
  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => _queuedWrite(
    PlanningMutationContext(userId: userId, organizationId: organizationId),
    () => _delegate.retryMutation(
      userId: userId,
      organizationId: organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
    ),
  );

  @override
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  }) => _queuedWrite(
    PlanningMutationContext(userId: userId, organizationId: organizationId),
    () => _delegate.clearMutation(
      userId: userId,
      organizationId: organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      expectedRevision: expectedRevision,
    ),
  );
}
