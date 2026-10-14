import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/session_item_key_edit.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_mutation_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Adversarial coverage for the session item key edit's sync lifecycle
/// (docs/specs/2026-10-13-personal-song-settings.md, PS15 no self-conflict,
/// PS16 Keep mine / retry, C1-C6, C10, C11).
///
/// Real in-memory Drift stores, the real `PlanningMutationSyncController`, the
/// real `SupabasePlanningMutationRepository` (so the server-state check that
/// decides an own write runs for real) over a scripted `set_session_item_key`
/// RPC that follows PS12's order: no-op first, then OCC, then write.
void main() {
  const context = PlanningMutationContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );
  const readContext = ActivePlanningReadContext(
    userId: 'user-1',
    organizationId: 'org-1',
  );

  late PlanningLocalDatabase db;
  late DriftPlanningLocalStore localStore;
  late _HookedStore store;
  late PlanningLocalReadRepository reads;
  late _KeyServer server;
  late PlanningMutationSyncController controller;

  // The post-sync refresh. Defaults to "the server answered": the projection
  // is replaced with the server's truth. A test swaps it to block or fail.
  late Future<bool> Function() refresh;
  var reconcileAllowed = true;

  Future<void> projectServer() => localStore.replaceActiveProjection(
    userId: 'user-1',
    organizationId: 'org-1',
    plans: [
      CachedPlanRecord(
        id: 'plan-1',
        slug: 'plan-1',
        name: 'Plan',
        description: null,
        scheduledFor: null,
        updatedAt: DateTime.utc(2026),
        version: 2,
        contentVersion: server.contentVersion,
      ),
    ],
    sessions: const [
      CachedSessionRecord(
        id: 'session-1',
        planId: 'plan-1',
        position: 1,
        name: 'S',
        version: 2,
      ),
    ],
    items: [
      CachedSessionItemRecord(
        id: 'item-1',
        planId: 'plan-1',
        sessionId: 'session-1',
        position: 1,
        songId: 'song-1',
        songTitle: 'Song',
        version: server.version,
        transpose: server.transpose,
        capo: server.capo,
      ),
    ],
    refreshedAt: DateTime.utc(2026),
  );

  setUp(() async {
    db = PlanningLocalDatabase.inMemory();
    localStore = DriftPlanningLocalStore(db);
    store = _HookedStore(database: db, localStore: localStore);
    reads = PlanningLocalReadRepository(
      store: localStore,
      mutationStore: store,
      contextReader: () async => readContext,
    );
    server = _KeyServer();
    reconcileAllowed = true;
    refresh = () async {
      await projectServer();
      return true;
    };
    await projectServer();
    final remote = SupabasePlanningMutationRepository.testing(rpc: server.rpc);
    final reconciler = PlanningMutationReconciler(localStore: () => localStore);
    controller = PlanningMutationSyncController(
      mutationStore: () => store,
      remoteRepository: () => remote,
      refreshPlanning: () => refresh(),
      shouldReconcileAcceptedMutation: (_) async => reconcileAllowed,
      reconcileAcceptedMutation: (ctx, record) =>
          reconciler.reconcile(ctx, record),
    );
  });

  tearDown(() async {
    await db.close();
  });

  SessionItemKeyEdit transposeTo(int value) => SessionItemKeyEdit(
    transposeMode: SessionItemKeyFieldMode.set,
    transpose: value,
    capoMode: SessionItemKeyFieldMode.keep,
  );

  SessionItemKeyEdit capoTo(int value) => SessionItemKeyEdit(
    transposeMode: SessionItemKeyFieldMode.keep,
    capoMode: SessionItemKeyFieldMode.set,
    capo: value,
  );

  Future<SessionItemSummary> mergedItem() async {
    final detail = await reads.getPlanDetail('plan-1');
    return detail.sessions
        .firstWhere((session) => session.id == 'session-1')
        .items
        .firstWhere((item) => item.id == 'item-1');
  }

  /// What the planning UI does: the draft's base is the item's version and
  /// key in the merged read. (A fold keeps the row's FIRST base, so a draft
  /// built while a row is pending only matters when no row exists.)
  Future<void> editKey(SessionItemKeyEdit edit) async {
    final item = await mergedItem();
    await store.recordSessionItemKeyEdit(
      context: context,
      draft: PlanningSessionItemKeyEditMutationDraft(
        sessionItemId: 'item-1',
        sessionId: 'session-1',
        planId: 'plan-1',
        edit: edit,
        baseVersion: item.version,
        baseTranspose: item.planTranspose,
        baseCapo: item.planCapo,
      ),
    );
  }

  Future<PlanningMutationRecord?> keyRow() => store.readMutation(
    userId: 'user-1',
    organizationId: 'org-1',
    aggregateType: 'session_item_key',
    aggregateId: 'item-1',
  );

  Future<SessionItemSummary> projectedItem() async {
    final detail = await localStore.readPlanDetail(
      userId: 'user-1',
      organizationId: 'org-1',
      planId: 'plan-1',
    );
    return detail!.sessions
        .firstWhere((session) => session.id == 'session-1')
        .items
        .firstWhere((item) => item.id == 'item-1');
  }

  Future<void> sync() => controller.syncPendingMutations(readContext);

  test('C1: a second edit after an accepted one carries the reconciled item '
      'version and is accepted (no self-conflict)', () async {
    await editKey(transposeTo(2));
    await sync();

    expect(server.sends.single.baseVersion, 1);
    expect(await keyRow(), isNull);
    final afterFirst = await projectedItem();
    expect(afterFirst.version, 2);
    expect(afterFirst.planTranspose, 2);

    await editKey(capoTo(3));
    final row = await keyRow();
    expect(row!.baseVersion, 2, reason: 'built from the merged read');
    expect(row.keyBaseTranspose, 2);
    await sync();

    expect(server.sends.map((send) => send.baseVersion), [1, 2]);
    expect(server.version, 3);
    expect(server.capo, 3);
    expect(await keyRow(), isNull);
  });

  for (final refreshWorks in [true, false]) {
    test(
      'C3: a resend after a lost response gets the no-op success and '
      'reconciles (post-sync refresh ${refreshWorks ? 'ok' : 'failed'})',
      () async {
        if (!refreshWorks) {
          refresh = () async => false;
        }
        await editKey(transposeTo(2));
        server.loseNextResponse = true;

        await sync();
        expect(server.version, 2, reason: 'the server committed');
        final stranded = await keyRow();
        expect(stranded!.syncStatus, PlanningMutationSyncStatus.pending);
        expect(stranded.baseVersion, 1);

        await sync();

        expect(server.sends.map((send) => send.baseVersion), [1, 1]);
        expect(server.version, 2, reason: 'the resend wrote nothing');
        expect(await keyRow(), isNull);
        final item = await projectedItem();
        expect(item.version, 2);
        expect(item.planTranspose, 2);
        expect(item.planCapo, isNull);
      },
    );
  }

  test('C4a: an edit folded while the first send is in flight is rebased '
      'onto the returned item version and then accepted', () async {
    await editKey(transposeTo(2));
    final gate = server.armGate();
    final run = sync();
    await gate.entered.future;

    await editKey(capoTo(3));
    final folded = await keyRow();
    expect(folded!.syncStatus, PlanningMutationSyncStatus.pending);
    expect(folded.baseVersion, 1);

    gate.release.complete();
    await run;

    final row = await keyRow();
    expect(row, isNotNull);
    expect(row!.syncStatus, PlanningMutationSyncStatus.pending);
    expect(row.baseVersion, 2);
    expect(row.keyBaseTranspose, 2);
    expect(row.keyBaseCapo, isNull);
    expect(
      row.keyEdit,
      SessionItemKeyEdit(
        transposeMode: SessionItemKeyFieldMode.set,
        transpose: 2,
        capoMode: SessionItemKeyFieldMode.set,
        capo: 3,
      ),
    );

    await sync();

    expect(server.sends.map((send) => send.baseVersion), [1, 2]);
    expect(server.version, 3);
    expect(server.transpose, 2);
    expect(server.capo, 3);
    expect(await keyRow(), isNull);
  });

  test('C4b: an edit folded onto an accepted-but-uncleared row is rebased by '
      'the batch-end effects and then accepted', () async {
    final refreshEntered = Completer<void>();
    final refreshRelease = Completer<void>();
    refresh = () async {
      refreshEntered.complete();
      await refreshRelease.future;
      await projectServer();
      return true;
    };
    await editKey(transposeTo(2));
    final run = sync();
    await refreshEntered.future;

    expect(
      (await keyRow())!.syncStatus,
      PlanningMutationSyncStatus.accepted,
      reason: 'the refresh is blocked, so the row sits accepted',
    );
    await editKey(capoTo(3));

    refreshRelease.complete();
    await run;

    final row = await keyRow();
    expect(row, isNotNull, reason: 'the clear was skipped: revision moved');
    expect(row!.syncStatus, PlanningMutationSyncStatus.pending);
    expect(row.baseVersion, 2);
    expect(row.keyBaseTranspose, 2);
    expect(row.keyBaseCapo, isNull);

    refresh = () async {
      await projectServer();
      return true;
    };
    await sync();

    expect(server.sends.map((send) => send.baseVersion), [1, 2]);
    expect(server.capo, 3);
    expect(await keyRow(), isNull);
  });

  test('C4c: an edit recorded inside the accepted write is rebased by the '
      'extra effects call and then accepted', () async {
    store.beforeAcceptedWrite = () => editKey(capoTo(3));
    await editKey(transposeTo(2));

    await sync();

    final row = await keyRow();
    expect(row, isNotNull);
    expect(row!.syncStatus, PlanningMutationSyncStatus.pending);
    expect(row.baseVersion, 2);
    expect(row.keyBaseTranspose, 2);
    expect(row.keyBaseCapo, isNull);

    await sync();

    expect(server.sends.map((send) => send.baseVersion), [1, 2]);
    expect(server.capo, 3);
    expect(await keyRow(), isNull);
  });

  for (final refreshWorks in [true, false]) {
    test('C4d: an edit recorded inside the batch-end clear is rebased by the '
        'extra effects call and then accepted (refresh '
        '${refreshWorks ? 'ok' : 'failed'})', () async {
      if (!refreshWorks) {
        refresh = () async => false;
      }
      store.beforeClear = () => editKey(capoTo(3));
      await editKey(transposeTo(2));

      await sync();

      final row = await keyRow();
      expect(row, isNotNull);
      expect(row!.syncStatus, PlanningMutationSyncStatus.pending);
      expect(row.baseVersion, 2);
      expect(row.keyBaseTranspose, 2);
      expect(row.keyBaseCapo, isNull);

      await sync();

      expect(server.sends.map((send) => send.baseVersion), [1, 2]);
      expect(server.capo, 3);
      expect(await keyRow(), isNull);
    });
  }

  test(
    'C11: a no-op success over a foreign write is not rebased -- the '
    'folded row keeps its base and its next send is a visible conflict',
    () async {
      await editKey(transposeTo(2));
      final gate = server.armGate();
      final run = sync();
      await gate.entered.future;

      // A foreign device set the same transpose AND a capo: the first send
      // becomes a no-op success that returns version 2 = base + 1, but with a
      // kept field (capo 5) that differs from the sent base values.
      server.foreignWrite(transpose: 2, capo: 5);
      await editKey(transposeTo(4));

      gate.release.complete();
      await run;

      final row = await keyRow();
      expect(row, isNotNull);
      expect(row!.syncStatus, PlanningMutationSyncStatus.pending);
      expect(row.baseVersion, 1, reason: 'R == b + 1 alone must not rebase');
      expect(row.keyBaseTranspose, isNull);
      expect(row.keyBaseCapo, isNull);

      await sync();

      final conflicted = await keyRow();
      expect(conflicted!.syncStatus, PlanningMutationSyncStatus.conflict);
      expect(conflicted.errorCode, PlanningMutationSyncErrorCode.conflict);
      expect(server.sends.last.baseVersion, 1);
      expect(server.capo, 5, reason: 'the foreign write was not overwritten');
    },
  );

  for (final status in [
    PlanningMutationSyncStatus.sending,
    PlanningMutationSyncStatus.accepted,
  ]) {
    test('not while ${status.name}: an own-write response leaves a row whose '
        'own accept write or clear is still to apply untouched', () async {
      await editKey(transposeTo(2));
      final recorded = (await keyRow())!;
      await store.saveSyncAttemptResult(
        userId: 'user-1',
        organizationId: 'org-1',
        aggregateType: 'session_item_key',
        aggregateId: 'item-1',
        syncStatus: status,
        expectedRevision: recorded.localRevision,
      );
      final before = (await keyRow())!;

      await store.applyAcceptedWriteEffects(
        userId: 'user-1',
        organizationId: 'org-1',
        accepted: before.copyWith(
          baseVersion: 2,
          acceptedOwnKeyVersion: 2,
          acceptedPlanContentVersion: 4,
          keyEdit: SessionItemKeyEdit(
            transposeMode: SessionItemKeyFieldMode.set,
            transpose: 2,
            capoMode: SessionItemKeyFieldMode.clear,
          ),
        ),
        remoteResponse: true,
      );

      final after = (await keyRow())!;
      expect(after.localRevision, before.localRevision);
      expect(after.syncStatus, status);
      expect(after.baseVersion, 1);
    });
  }

  test('a crash-resumed accepted marker never rebases: no response, no own '
      'version', () async {
    await editKey(transposeTo(2));
    final before = (await keyRow())!;
    final syncedShape = before.copyWith(
      baseVersion: 2,
      acceptedPlanContentVersion: 4,
      keyEdit: SessionItemKeyEdit(
        transposeMode: SessionItemKeyFieldMode.set,
        transpose: 2,
        capoMode: SessionItemKeyFieldMode.clear,
      ),
    );

    // The durable marker is the row as persisted: it never carries the
    // in-memory own version, and `_run` passes remoteResponse: false.
    await store.applyAcceptedWriteEffects(
      userId: 'user-1',
      organizationId: 'org-1',
      accepted: syncedShape,
      remoteResponse: false,
    );
    // Even a response-shaped record is not rebased without a response flag.
    await store.applyAcceptedWriteEffects(
      userId: 'user-1',
      organizationId: 'org-1',
      accepted: syncedShape.copyWith(acceptedOwnKeyVersion: 2),
      remoteResponse: false,
    );

    final after = (await keyRow())!;
    expect(after.localRevision, before.localRevision);
    expect(after.baseVersion, 1);
  });

  test('C5: Keep mine rebases onto the ITEM version and values in the '
      'projection, then the retry is accepted', () async {
    for (var i = 0; i < 3; i += 1) {
      server.foreignWrite(transpose: 5, capo: null);
    }
    expect(server.version, 4);
    await editKey(capoTo(2));
    await sync();
    expect(
      (await keyRow())!.syncStatus,
      PlanningMutationSyncStatus.conflict,
      reason: 'the stale base 1 conflicts with server version 4',
    );

    // A refresh now shows the item at version 4. The session (2) and plan (2)
    // versions are deliberately different from the item's.
    await projectServer();
    expect((await projectedItem()).version, 4);

    final reset = await store.retryMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session_item_key',
      aggregateId: 'item-1',
    );
    expect(reset, isTrue);
    final rebased = (await keyRow())!;
    expect(rebased.syncStatus, PlanningMutationSyncStatus.pending);
    expect(rebased.baseVersion, 4);
    expect(rebased.keyBaseTranspose, 5);
    expect(rebased.keyBaseCapo, isNull);

    await sync();

    expect(server.sends.last.baseVersion, 4);
    expect(server.version, 5);
    expect(server.transpose, 5);
    expect(server.capo, 2);
    expect(await keyRow(), isNull);
  });

  test('C5: Keep mine of an item missing from the projection keeps the base '
      'and the base values (fail-safe)', () async {
    server.foreignWrite(transpose: 5, capo: null);
    await editKey(capoTo(2));
    await sync();
    expect((await keyRow())!.syncStatus, PlanningMutationSyncStatus.conflict);
    await localStore.replaceActiveProjection(
      userId: 'user-1',
      organizationId: 'org-1',
      plans: [
        CachedPlanRecord(
          id: 'plan-1',
          slug: 'plan-1',
          name: 'Plan',
          description: null,
          scheduledFor: null,
          updatedAt: DateTime.utc(2026),
          version: 2,
          contentVersion: 3,
        ),
      ],
      sessions: const [
        CachedSessionRecord(
          id: 'session-1',
          planId: 'plan-1',
          position: 1,
          name: 'S',
          version: 2,
        ),
      ],
      items: const [],
      refreshedAt: DateTime.utc(2026),
    );

    await store.retryMutation(
      userId: 'user-1',
      organizationId: 'org-1',
      aggregateType: 'session_item_key',
      aggregateId: 'item-1',
    );

    final row = (await keyRow())!;
    expect(row.syncStatus, PlanningMutationSyncStatus.pending);
    expect(row.baseVersion, 1);
    expect(row.keyBaseTranspose, isNull);
    expect(row.keyBaseCapo, isNull);
  });

  test('C6: a retry of a connectivity-failed (pending) key edit resends the '
      'ORIGINAL base even after a refresh moved the item', () async {
    await editKey(capoTo(2));
    server.failNext = const SocketException('offline');
    await sync();
    final failed = (await keyRow())!;
    expect(failed.syncStatus, PlanningMutationSyncStatus.pending);
    expect(failed.errorCode, PlanningMutationSyncErrorCode.connectivityFailure);

    server.foreignWrite(transpose: 7, capo: null);
    await projectServer();
    expect((await projectedItem()).version, 2);

    await controller.retryMutation(
      readContext,
      aggregateType: 'session_item_key',
      aggregateId: 'item-1',
      expectedStatus: PlanningMutationSyncStatus.pending,
    );

    expect(server.sends.last.baseVersion, 1);
    expect(
      (await keyRow())!.syncStatus,
      PlanningMutationSyncStatus.conflict,
      reason: 'only a visible conflict is rebased onto the projection',
    );
  });

  test('C6: a retry of a failedRemoteDelete key edit resends the ORIGINAL '
      'base', () async {
    await editKey(capoTo(2));
    server.failNext = PostgrestException(
      message: 'session_item_not_found',
      code: 'P0002',
    );
    await sync();
    expect(
      (await keyRow())!.syncStatus,
      PlanningMutationSyncStatus.failedRemoteDelete,
    );

    server.foreignWrite(transpose: 7, capo: null);
    await projectServer();

    await controller.retryMutation(
      readContext,
      aggregateType: 'session_item_key',
      aggregateId: 'item-1',
      expectedStatus: PlanningMutationSyncStatus.failedRemoteDelete,
    );

    expect(server.sends.last.baseVersion, 1);
    expect((await keyRow())!.syncStatus, PlanningMutationSyncStatus.conflict);
  });

  test('C10 (inherited gap, '
      'docs/deferred/2026-09-30-content-version-advance-on-context-switch.md): '
      'an accepted key edit whose reconcile a context switch skips leaves the '
      'projection at the old item version, and the next edit shows one '
      'visible false conflict', () async {
    // The same switch the sync controller tests use for the boundary change:
    // the post-sync refresh does not run for this context and
    // `shouldReconcileAcceptedMutation` is false. The accepted row clears
    // without the item reaching the projection (S5b decides the fix).
    refresh = () async => false;
    reconcileAllowed = false;
    await editKey(transposeTo(2));
    await sync();

    expect(await keyRow(), isNull);
    expect(server.version, 2);
    expect(
      (await projectedItem()).version,
      1,
      reason: 'pinned as KNOWN behavior: the reconcile never ran',
    );

    reconcileAllowed = true;
    await editKey(transposeTo(4));
    expect((await keyRow())!.baseVersion, 1);
    await sync();

    expect(
      (await keyRow())!.syncStatus,
      PlanningMutationSyncStatus.conflict,
      reason: 'one visible false conflict; Keep mine resolves it',
    );
  });
}

/// The real store, with two seams that let a test land a local edit INSIDE a
/// store call the sync controller makes (the narrow windows C4c / C4d).
class _HookedStore extends DriftPlanningMutationStore {
  _HookedStore({required super.database, required super.localStore});

  /// Runs once, before the real `accepted` status write.
  Future<void> Function()? beforeAcceptedWrite;

  /// Runs once, before the real `clearMutation`.
  Future<void> Function()? beforeClear;

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
  }) async {
    final hook = beforeAcceptedWrite;
    if (hook != null && syncStatus == PlanningMutationSyncStatus.accepted) {
      beforeAcceptedWrite = null;
      await hook();
    }
    return super.saveSyncAttemptResult(
      userId: userId,
      organizationId: organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      syncStatus: syncStatus,
      errorCode: errorCode,
      errorMessage: errorMessage,
      expectedRevision: expectedRevision,
    );
  }

  @override
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  }) async {
    final hook = beforeClear;
    if (hook != null) {
      beforeClear = null;
      await hook();
    }
    return super.clearMutation(
      userId: userId,
      organizationId: organizationId,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      expectedRevision: expectedRevision,
    );
  }
}

class _Gate {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();
}

class _KeySend {
  const _KeySend(this.baseVersion);
  final int? baseVersion;
}

/// A scripted `set_session_item_key` (PS12 order: no-op, then OCC, then
/// write) for one item, `item-1` of `session-1` in `plan-1`.
class _KeyServer {
  int version = 1;
  int? transpose;
  int? capo;
  int contentVersion = 3;

  final List<_KeySend> sends = [];

  /// Blocks the next call after the request is captured, before the server
  /// evaluates it.
  _Gate? _gate;

  /// Thrown by the next call before anything is evaluated.
  Object? failNext;

  /// The next write commits, then the response is lost.
  bool loseNextResponse = false;

  _Gate armGate() => _gate = _Gate();

  /// A write from another device: version and content version move.
  void foreignWrite({required int? transpose, required int? capo}) {
    version += 1;
    contentVersion += 1;
    this.transpose = transpose;
    this.capo = capo;
  }

  Map<String, dynamic> _row() => {
    'id': 'item-1',
    'organization_id': 'org-1',
    'plan_id': 'plan-1',
    'session_id': 'session-1',
    'version': version,
    'transpose': transpose,
    'capo': capo,
    'plan_content_version': contentVersion,
  };

  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) async {
    if (fn != 'set_session_item_key') {
      throw StateError('unexpected rpc $fn');
    }
    final p = params!;
    sends.add(_KeySend(p['p_base_version'] as int?));
    final gate = _gate;
    if (gate != null) {
      _gate = null;
      gate.entered.complete();
      await gate.release.future;
    }
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    final transposeMode = p['p_transpose_mode'] as String;
    final capoMode = p['p_capo_mode'] as String;
    final wantedTranspose = p['p_transpose'] as int?;
    final wantedCapo = p['p_capo'] as int?;

    bool holds(String mode, int? wanted, int? current) => switch (mode) {
      'set' => wanted == current,
      'clear' => current == null,
      _ => true,
    };

    // PS12 step 6: every set/clear field already holds -> current row.
    if (holds(transposeMode, wantedTranspose, transpose) &&
        holds(capoMode, wantedCapo, capo)) {
      return _row();
    }
    // PS12 step 7: OCC on the item version.
    if (p['p_base_version'] != version) {
      throw PostgrestException(
        message: 'session_item_version_conflict',
        code: 'P0001',
      );
    }
    // PS12 step 8: write.
    version += 1;
    contentVersion += 1;
    if (transposeMode == 'set') transpose = wantedTranspose;
    if (transposeMode == 'clear') transpose = null;
    if (capoMode == 'set') capo = wantedCapo;
    if (capoMode == 'clear') capo = null;
    final row = _row();
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const SocketException('response lost');
    }
    return row;
  }
}
