import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';

/// Seeds one plan (`plan-1`, version 2) with a session (`session-1`) and an
/// item (`item-1`) as the active projection of `(user-1, organizationId)`.
Future<void> seedPlanningProjection(
  DriftPlanningLocalStore localStore, {
  required int contentVersion,
  String organizationId = 'org-1',
}) => localStore.replaceActiveProjection(
  userId: 'user-1',
  organizationId: organizationId,
  plans: [
    CachedPlanRecord(
      id: 'plan-1',
      slug: 'plan-1',
      name: 'Plan',
      description: null,
      scheduledFor: null,
      updatedAt: DateTime.utc(2026),
      version: 2,
      contentVersion: contentVersion,
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
  items: const [
    CachedSessionItemRecord(
      id: 'item-1',
      planId: 'plan-1',
      sessionId: 'session-1',
      position: 1,
      songId: 'song-1',
      songTitle: 'Song',
    ),
  ],
  refreshedAt: DateTime.utc(2026),
);

/// A scripted backend: every `syncMutation` call is recorded and answered by
/// the test's callback.
class ScriptedPlanningRemote implements PlanningMutationRemoteRepository {
  ScriptedPlanningRemote(this._respond);

  final Future<PlanningMutationRecord> Function(PlanningMutationRecord record)
  _respond;
  final List<PlanningMutationRecord> calls = [];

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) {
    calls.add(record);
    return _respond(record);
  }
}
