import 'dart:async';

import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
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
/// Reads, slug allocation, sync bookkeeping, retry and discard
/// (`readPendingMutations`, `readActionableMutations`, `readAllMutations`,
/// `readMutation`, `allocatePlanSlug`, `allocateSessionSlug`,
/// `hasUnsyncedMutations`, `saveSyncAttemptResult`, `retryMutation`,
/// `clearMutation`) pass straight through unguarded. In particular,
/// `clearMutation` must never be budget-guarded: once the store is full, it
/// is the only way out, and guarding it would turn the budget into a trap
/// with no recovery path.
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
/// The measure-check-write sequence for each `record*` call is serialised
/// per `(userId, organizationId)` -- see `_writeQueue` -- so the "at most
/// one mutation past the threshold" bound above holds under concurrency:
/// only one admission can be in flight per context at a time. Writes for
/// different contexts never block each other.
///
/// A write that reaches the delegate and fails at the storage layer (not a
/// domain rejection such as [LocalPlanningSlugConflictException]) is treated
/// as storage pressure (LF-T4): droppable catalog sources are evicted and
/// the write is retried once. Every guarded write is an upsert keyed by its
/// aggregate, so the retry is idempotent -- a partially applied first
/// attempt cannot duplicate. If the retry still fails, the failure is
/// surfaced as a typed [LocalStorageWriteFailure] rather than swallowed.
class BudgetedPlanningMutationStore implements PlanningMutationStore {
  BudgetedPlanningMutationStore({
    required PlanningMutationStore delegate,
    required PlanningStorageAccountant accountant,
    required SongCatalogEvictor evictor,
    required LocalStorageBudget budget,
  }) : _delegate = delegate,
       _accountant = accountant,
       _evictor = evictor,
       _budget = budget;

  final PlanningMutationStore _delegate;
  final PlanningStorageAccountant _accountant;
  final SongCatalogEvictor _evictor;
  final LocalStorageBudget _budget;

  // Per-(userId, organizationId) write queue. Without this, the measure,
  // check and write in _admitAndWrite are three separate `await` points with
  // nothing stopping a second `record*` call for the same context from
  // measuring the same pre-write footprint and also passing the check --
  // overshooting the "at most one mutation past the threshold" guarantee.
  // Keyed the same way as PlanningMutationSyncController._inFlight so a
  // write for one user/organization never blocks a write for another, but
  // unlike that single-flight map (which coalesces concurrent callers onto
  // ONE shared future), every `record*` call must run its own write and
  // report its own outcome, so callers are chained onto the queue instead of
  // being handed someone else's future.
  final Map<String, Future<void>> _writeQueue = {};

  Future<void> _guardedWrite(
    PlanningMutationContext context,
    Future<void> Function() write, {
    Future<bool> Function()? isCollapse,
  }) {
    final key = '${context.userId}_${context.organizationId}';
    final previous = _writeQueue[key] ?? Future<void>.value();

    // `previous` is always already-settled-safe (see `tail` below), so
    // chaining onto it just waits for our turn -- it never itself throws.
    final result = previous.then(
      (_) => _admitAndWrite(context, write, isCollapse: isCollapse),
    );

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

    try {
      await write();
    } on LocalPlanningSlugConflictException {
      // A domain rejection, not storage pressure. Retrying it would fail
      // identically and evicting would destroy cached data for nothing.
      rethrow;
    } on Exception catch (error) {
      // Catch Exception, not Object: by Dart convention Error subclasses
      // (ArgumentError, StateError, TypeError, ...) mean a programming
      // defect, never storage pressure. If a corrupted `mutation_kind` made
      // `planningMutationKindFromValue` throw an ArgumentError, or any other
      // real bug threw from inside write(), it must propagate as itself --
      // not get misreported as storage pressure, trigger a pointless
      // eviction, and get retried into the same failure.
      //
      // Storage failure. Give up droppable catalog sources, then retry once.
      // Every record* write is an upsert keyed by aggregate, so the retry is
      // idempotent: a partially applied first attempt cannot duplicate.
      final int freed;
      try {
        freed = await _evictor.evictDroppable();
      } on Exception {
        // Eviction itself failed -- plausibly the same condition (disk
        // full, quota) that broke the original write. Don't retry the
        // write into a store we couldn't even evict from; surface the
        // ORIGINAL write error, since that's what the caller actually
        // needs to see. The eviction failure is a secondary symptom, not
        // reported bytes freed since none were freed.
        throw LocalStorageWriteFailure(cause: error, bytesFreedByEviction: 0);
      }
      try {
        await write();
      } catch (retryError) {
        throw LocalStorageWriteFailure(
          cause: retryError,
          bytesFreedByEviction: freed,
        );
      }
    }
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
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) => _delegate.saveSyncAttemptResult(
    userId: userId,
    organizationId: organizationId,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
    syncStatus: syncStatus,
    errorCode: errorCode,
    errorMessage: errorMessage,
  );

  @override
  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => _delegate.retryMutation(
    userId: userId,
    organizationId: organizationId,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
  );

  @override
  Future<void> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) => _delegate.clearMutation(
    userId: userId,
    organizationId: organizationId,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
  );
}
