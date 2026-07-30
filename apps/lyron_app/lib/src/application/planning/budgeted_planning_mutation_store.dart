import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_write_failure.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/song_catalog_evictor.dart';

/// Enforces the two storage ladders (LF-T3, LF-T4) around a
/// [PlanningMutationStore] delegate.
///
/// Writes that can introduce or grow a pending aggregate are guarded by the
/// mutation budget: after the write reaches the delegate, the local mutation
/// store's byte footprint is measured, and if it is now at or past
/// [LocalStorageBudget.mutationRefuseBytes], the write is undone -- via the
/// delegate's own `clearMutation` -- and a
/// [PlanningMutationBudgetExceededException] is thrown. The check runs
/// AFTER the write rather than before, because the decorator only has the
/// delegate's public surface to work with (no access to the underlying
/// storage transaction), so the only reliable way to know the true resulting
/// size of a write -- including a budget as small as one byte, which no
/// pre-write estimate could ever trip -- is to let it land and then measure.
/// Catalog eviction cannot relieve this refusal, because pending mutations
/// are never evictable -- attempting eviction here would only destroy cached
/// data for no benefit. The remedy is to sync or discard.
///
/// Known limitation: the undo is a full `clearMutation` on the aggregate.
/// For a brand-new aggregate (a `*Create` write) that is exactly right. For
/// a write that folds into an aggregate with mutation still pending from an
/// earlier, already-accepted write (for example a `recordPlanEdit` on a
/// plan whose create is still unsynced), the undo removes the whole pending
/// aggregate rather than just reverting this edit, because the delegate
/// exposes no "revert to previous version" primitive. This is not exercised
/// by the current tests, which only push a bare `recordPlanCreate` over
/// budget in an empty store.
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
    PlanningMutationContext context, {
    required String aggregateType,
    required String aggregateId,
    required Future<void> Function() write,
  }) async {
    try {
      await write();
    } on LocalPlanningSlugConflictException {
      // A domain rejection, not storage pressure. Retrying it would fail
      // identically and evicting would destroy cached data for nothing. It
      // also never reaches storage (the delegate validates before it
      // upserts anything), so there is nothing to undo and no budget check
      // to run.
      rethrow;
    } catch (_) {
      // Storage failure. Give up droppable catalog sources, then retry once.
      // Every record* write is an upsert keyed by aggregate, so the retry is
      // idempotent: a partially applied first attempt cannot duplicate.
      final freed = await _evictor.evictDroppable();
      try {
        await write();
      } catch (retryError) {
        throw LocalStorageWriteFailure(
          cause: retryError,
          bytesFreedByEviction: freed,
        );
      }
    }

    final mutationBytes = await _accountant.measureMutationBytes(
      userId: context.userId,
      organizationId: context.organizationId,
    );
    if (_budget.refusesNewMutation(mutationBytes)) {
      await _delegate.clearMutation(
        userId: context.userId,
        organizationId: context.organizationId,
        aggregateType: aggregateType,
        aggregateId: aggregateId,
      );
      throw PlanningMutationBudgetExceededException(
        mutationBytes: mutationBytes,
        refuseBytes: _budget.mutationRefuseBytes,
      );
    }
  }

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) => _guardedWrite(
    context,
    aggregateType: 'plan',
    aggregateId: draft.planId,
    write: () => _delegate.recordPlanCreate(context: context, draft: draft),
  );

  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) => _guardedWrite(
    context,
    aggregateType: 'plan',
    aggregateId: draft.planId,
    write: () => _delegate.recordPlanEdit(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) => _guardedWrite(
    context,
    aggregateType: 'session',
    aggregateId: draft.sessionId,
    write: () => _delegate.recordSessionCreate(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) => _guardedWrite(
    context,
    aggregateType: 'session',
    aggregateId: draft.sessionId,
    write: () => _delegate.recordSessionRename(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) => _guardedWrite(
    context,
    aggregateType: 'session',
    aggregateId: draft.sessionId,
    write: () => _delegate.recordSessionDelete(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) => _guardedWrite(
    context,
    aggregateType: 'session_order',
    aggregateId: draft.planId,
    write: () => _delegate.recordSessionReorder(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) => _guardedWrite(
    context,
    aggregateType: 'session_item',
    aggregateId: draft.sessionItemId,
    write: () =>
        _delegate.recordSessionItemCreateSong(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) => _guardedWrite(
    context,
    aggregateType: 'session_item',
    aggregateId: draft.sessionItemId,
    write: () =>
        _delegate.recordSessionItemDelete(context: context, draft: draft),
  );

  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) => _guardedWrite(
    context,
    aggregateType: 'session_item_order',
    aggregateId: draft.sessionId,
    write: () =>
        _delegate.recordSessionItemReorder(context: context, draft: draft),
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
