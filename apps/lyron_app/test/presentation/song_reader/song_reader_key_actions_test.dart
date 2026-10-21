import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/capability_resolver.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/session_item_key_edit.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_key_actions.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_providers.dart';

import '../../support/plan_key_write_fakes.dart';

ResolvedSongKey _key(
  (int, SongKeyLayerId) transpose,
  (int, SongKeyLayerId) capo,
) => ResolvedSongKey(
  transpose: ResolvedSongKeyField(value: transpose.$1, source: transpose.$2),
  capo: ResolvedSongKeyField(value: capo.$1, source: capo.$2),
);

PlanDetail _detail() => PlanDetail(
  plan: PlanSummary(
    id: 'plan-1',
    slug: 'plan-one',
    name: 'Plan One',
    description: null,
    scheduledFor: null,
    updatedAt: DateTime(2026, 4, 1),
  ),
  sessions: const [
    SessionSummary(
      id: 'session-1',
      name: 'Main Set',
      position: 10,
      items: [
        SessionItemSummary(
          id: 'item-1',
          position: 10,
          song: SongSummary(id: 'song-1', title: 'Song One'),
        ),
      ],
    ),
  ],
);

class _GrantingGateway implements CapabilityGateway {
  _GrantingGateway(this._granted);

  final Set<Capability> _granted;

  @override
  Future<Set<Capability>> resolve(String organizationId) async => _granted;
}

class _FailingResolver extends CapabilityResolver {
  _FailingResolver() : super(gateway: _GrantingGateway(const {}));

  @override
  Future<bool> hasCapability(String organizationId, Capability capability) =>
      Future.error(StateError('offline'));
}

void main() {
  group('planKeyEditFor', () {
    const temporary = SongKeyLayerId.temporary;
    const plan = SongKeyLayerId.plan;
    const song = SongKeyLayerId.song;

    test('a temporary transpose is set, the plan capo is kept', () {
      expect(
        planKeyEditFor(_key((3, temporary), (2, plan))),
        SessionItemKeyEdit(
          transposeMode: SessionItemKeyFieldMode.set,
          transpose: 3,
          capoMode: SessionItemKeyFieldMode.keep,
        ),
      );
    });

    test('a temporary capo is set, the plan transpose is kept', () {
      expect(
        planKeyEditFor(_key((0, plan), (4, temporary))),
        SessionItemKeyEdit(
          transposeMode: SessionItemKeyFieldMode.keep,
          capoMode: SessionItemKeyFieldMode.set,
          capo: 4,
        ),
      );
    });

    test('both temporary fields are set', () {
      expect(
        planKeyEditFor(_key((-2, temporary), (5, temporary))),
        SessionItemKeyEdit(
          transposeMode: SessionItemKeyFieldMode.set,
          transpose: -2,
          capoMode: SessionItemKeyFieldMode.set,
          capo: 5,
        ),
      );
    });

    test('no temporary field gives no edit', () {
      expect(planKeyEditFor(_key((0, song), (2, plan))), isNull);
    });

    test('a temporary field outside the range gives no edit', () {
      expect(planKeyEditFor(_key((13, temporary), (0, song))), isNull);
      expect(planKeyEditFor(_key((0, song), (12, temporary))), isNull);
      expect(planKeyEditFor(_key((3, temporary), (12, temporary))), isNull);
    });

    test('values on the range edges are saved', () {
      expect(
        planKeyEditFor(_key((-11, temporary), (11, temporary))),
        SessionItemKeyEdit(
          transposeMode: SessionItemKeyFieldMode.set,
          transpose: -11,
          capoMode: SessionItemKeyFieldMode.set,
          capo: 11,
        ),
      );
    });
  });

  group('SongReaderKeyActions', () {
    test('none offers neither Reset nor Save to plan', () {
      expect(SongReaderKeyActions.none.isSaveToPlanAvailable, isFalse);
      expect(SongReaderKeyActions.none.onReset, isNull);
      expect(SongReaderKeyActions.none.onSaveToPlan, isNull);
    });
  });

  group('SongReaderPlanKeyWriter', () {
    late PlanKeyWriteHarness harness;
    late int detailBuilds;
    late int entryBuilds;

    ProviderContainer containerFor({ActivePlanningReadContext? context}) {
      final container = ProviderContainer(
        overrides: [
          activePlanningContextProvider.overrideWithValue(
            context ?? harness.context,
          ),
          planningWriteServiceProvider.overrideWithValue(harness.service),
          planningPlanDetailProvider('plan-1').overrideWith((ref) async {
            detailBuilds += 1;
            return harness.detail;
          }),
          planningMutationEntriesProvider.overrideWith((ref) async {
            entryBuilds += 1;
            return const [];
          }),
        ],
      );
      addTearDown(container.dispose);
      // Keep both alive, so an invalidation re-reads them.
      container.listen(planningPlanDetailProvider('plan-1'), (_, _) {});
      container.listen(planningMutationEntriesProvider, (_, _) {});
      return container;
    }

    setUp(() {
      harness = PlanKeyWriteHarness(detail: _detail());
      detailBuilds = 0;
      entryBuilds = 0;
    });

    final setTranspose3 = SessionItemKeyEdit(
      transposeMode: SessionItemKeyFieldMode.set,
      transpose: 3,
      capoMode: SessionItemKeyFieldMode.keep,
    );

    test('saveToPlan records the draft and the edit unchanged', () async {
      final container = containerFor();
      harness.syncGate.complete();

      final saved = await const SongReaderPlanKeyWriter().saveToPlan(
        container,
        planId: 'plan-1',
        sessionId: 'session-1',
        sessionItemId: 'item-1',
        edit: setTranspose3,
      );

      expect(saved, isTrue);
      expect(harness.recorded, hasLength(1));
      final draft = harness.recorded.single;
      expect(draft.planId, 'plan-1');
      expect(draft.sessionId, 'session-1');
      expect(draft.sessionItemId, 'item-1');
      expect(draft.edit, setTranspose3);
    });

    test('the plan detail and the mutation entries are invalidated when the '
        'edit is recorded, before the scheduler completes', () async {
      final container = containerFor();
      await pumpEventQueue();
      expect(detailBuilds, 1);
      expect(entryBuilds, 1);

      // The scheduler never completes (the sync attempt is still running).
      var completed = false;
      unawaited(
        const SongReaderPlanKeyWriter()
            .saveToPlan(
              container,
              planId: 'plan-1',
              sessionId: 'session-1',
              sessionItemId: 'item-1',
              edit: setTranspose3,
            )
            .whenComplete(() => completed = true),
      );
      await pumpEventQueue();

      expect(completed, isFalse);
      expect(detailBuilds, 2);
      expect(entryBuilds, 2);
      expect(
        container
            .read(planningPlanDetailProvider('plan-1'))
            .requireValue
            .sessions
            .single
            .items
            .single
            .planTranspose,
        3,
        reason: 'the re-read sees the recorded edit',
      );
    });

    test('saveToPlan returns true once the write completes', () async {
      final container = containerFor();
      var saved = false;
      unawaited(
        const SongReaderPlanKeyWriter()
            .saveToPlan(
              container,
              planId: 'plan-1',
              sessionId: 'session-1',
              sessionItemId: 'item-1',
              edit: setTranspose3,
            )
            .then((value) => saved = value),
      );
      await pumpEventQueue();
      expect(saved, isFalse);

      harness.syncGate.complete();
      await pumpEventQueue();
      expect(saved, isTrue);
    });

    test('without an active planning context nothing is written', () async {
      final container = ProviderContainer(
        overrides: [
          activePlanningContextProvider.overrideWithValue(null),
          planningWriteServiceProvider.overrideWithValue(harness.service),
        ],
      );
      addTearDown(container.dispose);

      final saved = await const SongReaderPlanKeyWriter().saveToPlan(
        container,
        planId: 'plan-1',
        sessionId: 'session-1',
        sessionItemId: 'item-1',
        edit: setTranspose3,
      );
      final cleared = await const SongReaderPlanKeyWriter().clearPlanValue(
        container,
        planId: 'plan-1',
        sessionId: 'session-1',
        sessionItemId: 'item-1',
      );

      expect(saved, isFalse);
      expect(cleared, isFalse);
      expect(harness.recorded, isEmpty);
    });

    test('clearPlanValue records clear for both fields', () async {
      final container = containerFor();
      harness.syncGate.complete();

      final cleared = await const SongReaderPlanKeyWriter().clearPlanValue(
        container,
        planId: 'plan-1',
        sessionId: 'session-1',
        sessionItemId: 'item-1',
      );

      expect(cleared, isTrue);
      expect(
        harness.recorded.single.edit,
        SessionItemKeyEdit(
          transposeMode: SessionItemKeyFieldMode.clear,
          capoMode: SessionItemKeyFieldMode.clear,
        ),
      );
    });

    test('a failed write propagates and invalidates nothing', () async {
      final container = containerFor();
      await pumpEventQueue();
      harness.recordError = StateError('item gone');

      await expectLater(
        const SongReaderPlanKeyWriter().saveToPlan(
          container,
          planId: 'plan-1',
          sessionId: 'session-1',
          sessionItemId: 'item-1',
          edit: setTranspose3,
        ),
        throwsStateError,
      );
      await pumpEventQueue();

      expect(detailBuilds, 1);
      expect(entryBuilds, 1);
    });
  });

  group('readerCanEditSessionsProvider', () {
    Future<bool> canEdit(CapabilityResolver resolver) async {
      final container = ProviderContainer(
        overrides: [capabilityResolverProvider.overrideWith((ref) => resolver)],
      );
      addTearDown(container.dispose);
      return container.read(readerCanEditSessionsProvider('org-1').future);
    }

    test('is true when the member can edit sessions', () async {
      expect(
        await canEdit(
          CapabilityResolver(
            gateway: _GrantingGateway({Capability.editSessions}),
          ),
        ),
        isTrue,
      );
    });

    test('is false when the member cannot edit sessions', () async {
      expect(
        await canEdit(
          CapabilityResolver(gateway: _GrantingGateway({Capability.editSongs})),
        ),
        isFalse,
      );
    });

    test('is false, not an error, when the capability read fails', () async {
      expect(await canEdit(_FailingResolver()), isFalse);
    });
  });
}
