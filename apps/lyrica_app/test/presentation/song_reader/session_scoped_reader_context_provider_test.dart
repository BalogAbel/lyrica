import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/domain/planning/plan_detail.dart';
import 'package:lyrica_app/src/domain/planning/plan_summary.dart';
import 'package:lyrica_app/src/domain/planning/planning_repository.dart';
import 'package:lyrica_app/src/domain/planning/session_item_summary.dart';
import 'package:lyrica_app/src/domain/planning/session_summary.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:lyrica_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyrica_app/src/presentation/song_reader/session_scoped_reader_context_provider.dart';

void main() {
  test(
    'warm-path uses already-loaded plan detail without a second fetch',
    () async {
      final repository = _FakePlanningRepository(
        planDetail: _planDetail(),
        throwOnGetPlanDetail: true,
      );
      final container = ProviderContainer(
        overrides: [planningRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        sessionScopedReaderContextProvider(
          SessionScopedReaderContextRequest(
            planId: 'plan-1',
            sessionId: 'session-1',
            sessionItemId: 'item-20',
            songId: 'song-2',
            warmPlanDetail: _planDetail(),
          ),
        ).future,
      );

      expect(result, isA<ResolvedSessionScopedReaderContextResult>());
      expect(repository.getPlanDetailCallCount, 0);
    },
  );

  test('cold direct entry resolves through planning provider path', () async {
    final repository = _FakePlanningRepository(planDetail: _planDetail());
    final container = ProviderContainer(
      overrides: [planningRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      sessionScopedReaderContextProvider(
        const SessionScopedReaderContextRequest(
          planId: 'plan-1',
          sessionId: 'session-1',
          sessionItemId: 'item-20',
          songId: 'song-2',
        ),
      ).future,
    );

    expect(result, isA<ResolvedSessionScopedReaderContextResult>());
    expect(repository.getPlanDetailCallCount, 1);
  });

  test('unavailable planning data returns explicit failure result', () async {
    final repository = _FakePlanningRepository(
      planDetail: _planDetail(),
      getPlanDetailError: StateError('unavailable'),
    );
    final container = ProviderContainer(
      overrides: [planningRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      sessionScopedReaderContextProvider(
        const SessionScopedReaderContextRequest(
          planId: 'plan-1',
          sessionId: 'session-1',
          sessionItemId: 'item-20',
          songId: 'song-2',
        ),
      ).future,
    );

    expect(
      result,
      const SessionScopedReaderContextFailureResult(
        SessionScopedReaderContextFailure.unavailablePlanDetail,
      ),
    );
  });
}

class _FakePlanningRepository implements PlanningRepository {
  _FakePlanningRepository({
    required this.planDetail,
    this.throwOnGetPlanDetail = false,
    this.getPlanDetailError,
  });

  final PlanDetail planDetail;
  final bool throwOnGetPlanDetail;
  final Object? getPlanDetailError;
  int getPlanDetailCallCount = 0;

  @override
  Future<PlanDetail> getPlanDetail(String planId) async {
    getPlanDetailCallCount += 1;

    if (throwOnGetPlanDetail) {
      throw StateError('warm path should not fetch');
    }

    if (getPlanDetailError != null) {
      throw getPlanDetailError!;
    }

    return planDetail;
  }

  @override
  Future<List<PlanSummary>> listPlans() async => const [];
}

PlanDetail _planDetail() {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      name: 'Plan',
      description: 'Desc',
      scheduledFor: DateTime(2026, 4, 1, 10),
      updatedAt: DateTime(2026, 4, 1, 9),
    ),
    sessions: const [
      SessionSummary(
        id: 'session-1',
        name: 'Main',
        position: 10,
        items: [
          SessionItemSummary(
            id: 'item-10',
            position: 10,
            song: SongSummary(id: 'song-1', title: 'Elso'),
          ),
          SessionItemSummary(
            id: 'item-20',
            position: 20,
            song: SongSummary(id: 'song-2', title: 'Masodik'),
          ),
          SessionItemSummary(
            id: 'item-30',
            position: 30,
            song: SongSummary(id: 'song-3', title: 'Harmadik'),
          ),
        ],
      ),
    ],
  );
}
