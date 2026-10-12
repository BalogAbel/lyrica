import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reads the backend's planning data for [organizationId] the way a refresh
/// does (`fetchPlanningSyncPayload`), for integration tests that compare the
/// backend state with a local projection.
Future<PlanningSyncPayload> readBackendPlanningPayload(
  SupabaseClient client, {
  required String organizationId,
  int pageSize = 500,
}) {
  return SupabasePlanningRepository(
    client,
    pageSize: pageSize,
  ).fetchPlanningSyncPayload(organizationId: organizationId);
}

/// One plan with its ordered sessions and items, as the backend holds it.
///
/// Throws [StateError] when [planId] is not readable in [organizationId]
/// (absent, or hidden by row level security).
Future<PlanDetail> readBackendPlanDetail(
  SupabaseClient client, {
  required String organizationId,
  required String planId,
}) async {
  final payload = await readBackendPlanningPayload(
    client,
    organizationId: organizationId,
  );

  final matches = payload.plans.where((plan) => plan.id == planId);
  if (matches.isEmpty) {
    throw StateError('Plan not found: $planId');
  }
  final plan = matches.single;

  final sessions = [
    for (final session in payload.sessions.where((s) => s.planId == planId))
      SessionSummary(
        id: session.id,
        slug: session.slug,
        name: session.name,
        position: session.position,
        version: session.version,
        items: [
          for (final item in payload.items.where(
            (i) => i.sessionId == session.id,
          ))
            SessionItemSummary(
              id: item.id,
              position: item.position,
              song: SongSummary(id: item.songId, title: item.songTitle),
            ),
        ],
      ),
  ];

  return PlanDetail(
    plan: PlanSummary(
      id: plan.id,
      slug: plan.slug,
      name: plan.name,
      description: plan.description,
      scheduledFor: plan.scheduledFor,
      updatedAt: plan.updatedAt,
      version: plan.version,
      contentVersion: plan.contentVersion,
    ),
    sessions: sessions,
  );
}
