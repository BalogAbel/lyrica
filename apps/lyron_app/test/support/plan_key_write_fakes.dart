import 'dart:async';

import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';

/// A real [PlanningWriteService] over a fake repository and mutation store,
/// for the reader's plan-key tests.
///
/// The store records every key edit, can hold a record open ([recordGate]) or
/// fail it ([recordError]), and applies a completed edit to [detail], which
/// the repository returns -- so a test that serves [detail] as the live plan
/// detail sees what the merged read would show once the edit is recorded. The
/// sync scheduler waits on [syncGate], which the test completes (or never
/// does).
class PlanKeyWriteHarness {
  PlanKeyWriteHarness({
    required this.detail,
    this.context = const ActivePlanningReadContext(
      userId: 'user-1',
      organizationId: 'org-1',
    ),
  }) {
    final store = _KeyEditStore(this);
    service = PlanningWriteService(
      _DetailRepository(this),
      mutationStore: store,
      activeContextReader: () async => context,
      syncScheduler: (_) => syncGate.future,
    );
  }

  /// What the repository returns: the plan detail the merged read gives.
  PlanDetail detail;
  final ActivePlanningReadContext context;

  /// The key edits the store was asked to record, in order, counted on entry
  /// (before [recordGate]).
  final recorded = <PlanningSessionItemKeyEditMutationDraft>[];

  /// While set, a record waits on it before it completes.
  Completer<void>? recordGate;

  /// While set, a record throws it (after [recordGate]).
  Object? recordError;

  /// What the sync scheduler awaits.
  final syncGate = Completer<void>();

  late final PlanningWriteService service;
}

class _DetailRepository implements PlanningRepository {
  _DetailRepository(this._harness);

  final PlanKeyWriteHarness _harness;

  @override
  Future<PlanDetail> getPlanDetail(String planId) async => _harness.detail;

  @override
  Future<List<PlanSummary>> listPlans() => throw UnimplementedError();

  @override
  Future<PlanSummary?> getPlanSummaryBySlug(String planSlug) =>
      throw UnimplementedError();

  @override
  Future<PlanDetail?> getPlanDetailBySlug(String planSlug) =>
      throw UnimplementedError();
}

class _KeyEditStore implements PlanningMutationStore {
  _KeyEditStore(this._harness);

  final PlanKeyWriteHarness _harness;

  @override
  Future<void> recordSessionItemKeyEdit({
    required PlanningMutationContext context,
    required PlanningSessionItemKeyEditMutationDraft draft,
  }) async {
    _harness.recorded.add(draft);
    final gate = _harness.recordGate;
    if (gate != null) {
      await gate.future;
    }
    final error = _harness.recordError;
    if (error != null) {
      throw error;
    }
    _harness.detail = _withKeyEdit(_harness.detail, draft);
  }

  // The service touches nothing else of the store on the key-edit path.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PlanDetail _withKeyEdit(
  PlanDetail detail,
  PlanningSessionItemKeyEditMutationDraft draft,
) {
  return PlanDetail(
    plan: detail.plan,
    sessions: [
      for (final session in detail.sessions)
        SessionSummary(
          id: session.id,
          slug: session.slug,
          name: session.name,
          position: session.position,
          version: session.version,
          items: [
            for (final item in session.items)
              if (item.id != draft.sessionItemId)
                item
              else
                _itemWithKey(item, draft),
          ],
        ),
    ],
  );
}

SessionItemSummary _itemWithKey(
  SessionItemSummary item,
  PlanningSessionItemKeyEditMutationDraft draft,
) {
  final key = draft.edit.applyTo(
    transpose: item.planTranspose,
    capo: item.planCapo,
  );
  return SessionItemSummary(
    id: item.id,
    slug: item.slug,
    position: item.position,
    song: item.song,
    version: item.version + 1,
    planTranspose: key.transpose,
    planCapo: key.capo,
  );
}
