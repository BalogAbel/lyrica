import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/capability_resolver.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/widgets/plan_song_item_row.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

PlanDetail _planDetailFixture({int? planTranspose, int? planCapo}) {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      slug: 'team-rehearsal',
      name: 'Team Rehearsal',
      description: null,
      scheduledFor: null,
      updatedAt: DateTime(2026, 1, 1),
    ),
    sessions: [
      SessionSummary(
        id: 'session-1',
        slug: 'warm-up',
        name: 'Warm-Up',
        position: 10,
        items: [
          SessionItemSummary(
            id: 'item-1',
            position: 10,
            song: const SongSummary(
              id: 'song-1',
              slug: 'zulu-song',
              title: 'Zulu Song',
            ),
            planTranspose: planTranspose,
            planCapo: planCapo,
          ),
        ],
      ),
    ],
  );
}

class _NoopPlanningRepository implements PlanningRepository {
  @override
  Future<List<PlanSummary>> listPlans() async => const [];

  @override
  Future<PlanDetail> getPlanDetail(String planId) async =>
      throw UnimplementedError();

  @override
  Future<PlanSummary?> getPlanSummaryBySlug(String planSlug) async => null;

  @override
  Future<PlanDetail?> getPlanDetailBySlug(String planSlug) async => null;
}

class _NoopPlanningMutationStore implements PlanningMutationStore {
  @override
  Future<void> convertStaleCreateTombstones({
    required String userId,
    required String organizationId,
  }) async {}

  // Stub for docs/specs/2026-08-06-in-flight-create-cancellation.md (D3):
  // none of these tests exercise the in-flight-create-cancellation
  // tombstone path, which is covered against the real
  // DriftPlanningMutationStore in
  // test/offline/adversarial/planning_in_flight_create_cancellation_test.dart.
  @override
  Future<bool> resolveCancelledCreate({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required bool created,
    int? acceptedBaseVersion,
  }) async => false;
  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) async {}

  @override
  Future<void> recordPlanDelete({
    required PlanningMutationContext context,
    required PlanningPlanDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> applyAcceptedWriteEffects({
    required String userId,
    required String organizationId,
    required PlanningMutationRecord accepted,
    required bool remoteResponse,
  }) async {}

  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemKeyEdit({
    required PlanningMutationContext context,
    required PlanningSessionItemKeyEditMutationDraft draft,
  }) async {}

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<List<PlanningMutationRecord>> readActionableMutations({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async => null;

  @override
  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  }) async => 'unused';

  @override
  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  }) async => 'unused';

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) async => false;

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
  }) async => null;

  @override
  Future<bool> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async => true;

  @override
  Future<bool> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    int? expectedRevision,
  }) async => false;

  @override
  Future<bool> discardMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async => false;
}

class _FakePlanningWriteService extends PlanningWriteService {
  _FakePlanningWriteService()
    : super(
        _NoopPlanningRepository(),
        mutationStore: _NoopPlanningMutationStore(),
        activeContextReader: () async => const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      );

  PlanningWriteContext? deletedContext;
  SessionItemDeleteDraft? deletedDraft;

  @override
  Future<void> deleteSessionItem({
    required PlanningWriteContext context,
    required SessionItemDeleteDraft draft,
  }) async {
    deletedContext = context;
    deletedDraft = draft;
  }
}

class _AllowAllCapabilityGateway implements CapabilityGateway {
  @override
  Future<Set<Capability>> resolve(String organizationId) async =>
      Capability.values.toSet();
}

Widget _harness({
  required PlanningWriteService writeService,
  int? planTranspose,
  int? planCapo,
}) {
  final planDetail = _planDetailFixture(
    planTranspose: planTranspose,
    planCapo: planCapo,
  );
  final session = planDetail.sessions.single;
  final item = session.items.single;

  return ProviderScope(
    overrides: [
      activePlanningContextProvider.overrideWithValue(
        const ActivePlanningReadContext(
          userId: 'user-1',
          organizationId: 'org-1',
        ),
      ),
      planningWriteServiceProvider.overrideWithValue(writeService),
      capabilityResolverProvider.overrideWith(
        (_) => CapabilityResolver(gateway: _AllowAllCapabilityGateway()),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: PlanSongItemRow(
          planDetail: planDetail,
          session: session,
          item: item,
          itemIndex: 0,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the item position and song title', (tester) async {
    await tester.pumpWidget(
      _harness(writeService: _FakePlanningWriteService()),
    );
    await tester.pumpAndSettle();

    expect(find.text('10. Zulu Song'), findsOneWidget);
  });

  testWidgets('tapping delete calls deleteSessionItem with the item draft', (
    tester,
  ) async {
    final writeService = _FakePlanningWriteService();

    await tester.pumpWidget(_harness(writeService: writeService));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byTooltip('${AppStrings.sessionItemDeleteAction}: Zulu Song'),
    );
    await tester.pumpAndSettle();

    expect(writeService.deletedContext?.organizationId, 'org-1');
    expect(writeService.deletedDraft?.sessionItemId, 'item-1');
    expect(writeService.deletedDraft?.sessionId, 'session-1');
    expect(writeService.deletedDraft?.planId, 'plan-1');
  });

  group('plan key chips (PS8)', () {
    const transposeKey = ValueKey('plan-session-item-transpose-item-1');
    const capoKey = ValueKey('plan-session-item-capo-item-1');

    testWidgets('shows transpose and capo chips below the title', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          writeService: _FakePlanningWriteService(),
          planTranspose: 2,
          planCapo: 3,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(transposeKey)).data,
        'Transpose +2',
      );
      expect(tester.widget<Text>(find.byKey(capoKey)).data, 'Capo 3');

      final titleY = tester.getCenter(find.text('10. Zulu Song')).dy;
      expect(
        tester.getCenter(find.byKey(transposeKey)).dy,
        greaterThan(titleY),
      );
      expect(tester.getCenter(find.byKey(capoKey)).dy, greaterThan(titleY));
    });

    testWidgets('a negative transpose shows only the transpose chip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(writeService: _FakePlanningWriteService(), planTranspose: -3),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(transposeKey)).data,
        'Transpose -3',
      );
      expect(find.byKey(capoKey), findsNothing);
    });

    testWidgets('a zero capo is a plan value and shows only the capo chip', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(writeService: _FakePlanningWriteService(), planCapo: 0),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(capoKey)).data, 'Capo 0');
      expect(find.byKey(transposeKey), findsNothing);
    });

    testWidgets('a zero transpose is a plan value and reads Transpose 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(writeService: _FakePlanningWriteService(), planTranspose: 0),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Text>(find.byKey(transposeKey)).data, 'Transpose 0');
      expect(find.byKey(capoKey), findsNothing);
    });

    testWidgets('a row without plan values has no chips and keeps its title', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(writeService: _FakePlanningWriteService()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(transposeKey), findsNothing);
      expect(find.byKey(capoKey), findsNothing);
      expect(find.byType(Wrap), findsNothing);
      expect(find.text('10. Zulu Song'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('plan-session-item-item-1')),
          matching: find.text('10. Zulu Song'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the chips use the colour scheme, not literals', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          writeService: _FakePlanningWriteService(),
          planTranspose: 2,
          planCapo: 1,
        ),
      );
      await tester.pumpAndSettle();

      final scheme = Theme.of(
        tester.element(find.byKey(transposeKey)),
      ).colorScheme;
      for (final key in [transposeKey, capoKey]) {
        final text = tester.widget<Text>(find.byKey(key));
        expect(text.style?.color, scheme.onPrimaryContainer);
        final box = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.byKey(key),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(
          (box.decoration as BoxDecoration).color,
          scheme.primaryContainer,
        );
      }
    });
  });
}
