import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';

void main() {
  test('listPlans returns summaries in deterministic slice order', () async {
    final repository = SupabasePlanningRepository.testing(
      listPlanRows: () async => [
        {
          'id': 'plan-c',
          'name': 'Null Scheduled',
          'description': 'Null scheduled description',
          'scheduled_for': null,
          'updated_at': '2026-03-31T10:00:00Z',
        },
        {
          'id': 'plan-b',
          'name': 'Later Tie Break',
          'description': 'Later description',
          'scheduled_for': '2026-04-06T09:00:00Z',
          'updated_at': '2026-03-31T09:00:00Z',
        },
        {
          'id': 'plan-a',
          'name': 'Earlier',
          'description': 'Earlier description',
          'scheduled_for': '2026-04-05T09:00:00Z',
          'updated_at': '2026-03-31T08:00:00Z',
        },
        {
          'id': 'plan-d',
          'name': 'Earlier Tie Break',
          'description': 'Tie break description',
          'scheduled_for': '2026-04-06T09:00:00Z',
          'updated_at': '2026-03-31T11:00:00Z',
        },
        {
          'id': 'plan-z',
          'name': 'Id Tie Break Later',
          'description': 'Same schedule and update time',
          'scheduled_for': '2026-04-07T09:00:00Z',
          'updated_at': '2026-03-31T07:00:00Z',
        },
        {
          'id': 'plan-y',
          'name': 'Id Tie Break Earlier',
          'description': 'Same schedule and update time',
          'scheduled_for': '2026-04-07T09:00:00Z',
          'updated_at': '2026-03-31T07:00:00Z',
        },
      ],
      getPlanRow: (planId) async => null,
      listSessionRows: (planId) async => const [],
    );

    final plans = await repository.listPlans();

    expect(plans, [
      PlanSummary(
        id: 'plan-a',
        name: 'Earlier',
        description: 'Earlier description',
        scheduledFor: DateTime.utc(2026, 4, 5, 9),
        updatedAt: DateTime.utc(2026, 3, 31, 8),
      ),
      PlanSummary(
        id: 'plan-d',
        name: 'Earlier Tie Break',
        description: 'Tie break description',
        scheduledFor: DateTime.utc(2026, 4, 6, 9),
        updatedAt: DateTime.utc(2026, 3, 31, 11),
      ),
      PlanSummary(
        id: 'plan-b',
        name: 'Later Tie Break',
        description: 'Later description',
        scheduledFor: DateTime.utc(2026, 4, 6, 9),
        updatedAt: DateTime.utc(2026, 3, 31, 9),
      ),
      PlanSummary(
        id: 'plan-y',
        name: 'Id Tie Break Earlier',
        description: 'Same schedule and update time',
        scheduledFor: DateTime.utc(2026, 4, 7, 9),
        updatedAt: DateTime.utc(2026, 3, 31, 7),
      ),
      PlanSummary(
        id: 'plan-z',
        name: 'Id Tie Break Later',
        description: 'Same schedule and update time',
        scheduledFor: DateTime.utc(2026, 4, 7, 9),
        updatedAt: DateTime.utc(2026, 3, 31, 7),
      ),
      PlanSummary(
        id: 'plan-c',
        name: 'Null Scheduled',
        description: 'Null scheduled description',
        scheduledFor: null,
        updatedAt: DateTime.utc(2026, 3, 31, 10),
      ),
    ]);
  });

  test(
    'getPlanDetail returns ordered sessions and song-backed items',
    () async {
      final repository = SupabasePlanningRepository.testing(
        listPlanRows: () async => const [],
        getPlanRow: (planId) async => {
          'id': planId,
          'name': 'Team Rehearsal',
          'description': 'Multi-session rehearsal fixture',
          'scheduled_for': null,
          'updated_at': '2026-03-31T09:00:00Z',
        },
        listSessionRows: (planId) async => [
          {
            'id': 'session-2',
            'name': 'Run-Through',
            'position': 20,
            'session_items': [
              {
                'id': 'item-2',
                'position': 20,
                'song': {'id': 'song-2', 'title': 'A mi Istenünk'},
              },
              {
                'id': 'item-1',
                'position': 10,
                'song': {'id': 'song-1', 'title': 'A forrásnál'},
              },
            ],
          },
          {
            'id': 'session-1',
            'name': 'Warm-Up',
            'position': 10,
            'session_items': [
              {
                'id': 'item-3',
                'position': 10,
                'song': {'id': 'song-3', 'title': 'Egy út'},
              },
            ],
          },
        ],
      );

      final detail = await repository.getPlanDetail('plan-1');

      expect(
        detail,
        PlanDetail(
          plan: PlanSummary(
            id: 'plan-1',
            name: 'Team Rehearsal',
            description: 'Multi-session rehearsal fixture',
            scheduledFor: null,
            updatedAt: DateTime.utc(2026, 3, 31, 9),
          ),
          sessions: [
            SessionSummary(
              id: 'session-1',
              name: 'Warm-Up',
              position: 10,
              items: const [
                SessionItemSummary(
                  id: 'item-3',
                  position: 10,
                  song: SongSummary(id: 'song-3', title: 'Egy út'),
                ),
              ],
            ),
            SessionSummary(
              id: 'session-2',
              name: 'Run-Through',
              position: 20,
              items: const [
                SessionItemSummary(
                  id: 'item-1',
                  position: 10,
                  song: SongSummary(id: 'song-1', title: 'A forrásnál'),
                ),
                SessionItemSummary(
                  id: 'item-2',
                  position: 20,
                  song: SongSummary(id: 'song-2', title: 'A mi Istenünk'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  test(
    'getPlanDetail fails when a session item song cannot be resolved',
    () async {
      final repository = SupabasePlanningRepository.testing(
        listPlanRows: () async => const [],
        getPlanRow: (planId) async => {
          'id': planId,
          'name': 'Broken Plan',
          'description': 'Broken description',
          'scheduled_for': null,
          'updated_at': '2026-03-31T09:00:00Z',
        },
        listSessionRows: (planId) async => [
          {
            'id': 'session-1',
            'name': 'Warm-Up',
            'position': 10,
            'session_items': [
              {'id': 'item-1', 'position': 10, 'song': null},
            ],
          },
        ],
      );

      await expectLater(
        repository.getPlanDetail('plan-1'),
        throwsA(isA<StateError>()),
      );
    },
  );
}
