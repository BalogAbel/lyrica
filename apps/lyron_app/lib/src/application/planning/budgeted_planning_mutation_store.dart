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

  Future<void> _guardedWrite(
    PlanningMutationContext context,
    Future<void> Function() write,
  ) async {
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
