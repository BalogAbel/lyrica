import 'package:drift/drift.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';

/// Fixed per-row allowance covering the non-text columns of a measured
/// table — integer keys, versions, positions and timestamps — plus a
/// nominal share of sqlite row overhead. Every text column is summed
/// explicitly rather than folded into this allowance. Deliberately coarse:
/// the accountant is a comparable estimate, not a true on-disk size.
const int kLocalStorageRowOverheadBytes = 64;

/// Measures the planning database's footprint from row content.
///
/// Uses `length(...)` over the text columns rather than a file size or a
/// browser quota API, so the same code runs on native and web and can be
/// exercised deterministically against an in-memory database.
class PlanningStorageAccountant {
  const PlanningStorageAccountant(this._database);

  final PlanningLocalDatabase _database;

  Future<int> measureMutationBytes({
    required String userId,
    required String organizationId,
  }) async {
    final row = await _database
        .customSelect(
          'SELECT COALESCE(SUM('
          'length(aggregate_type) + length(aggregate_id) + '
          'length(mutation_kind) + length(sync_status) + '
          'length(user_id) + length(organization_id) + '
          "length(COALESCE(plan_id, '')) + "
          "length(COALESCE(session_id, '')) + "
          "length(COALESCE(slug, '')) + "
          "length(COALESCE(name, '')) + "
          "length(COALESCE(description, '')) + "
          "length(COALESCE(song_id, '')) + "
          "length(COALESCE(song_title, '')) + "
          "length(COALESCE(ordered_sibling_ids, '')) + "
          "length(COALESCE(origin_snapshot_json, '')) + "
          "length(COALESCE(error_code, '')) + "
          "length(COALESCE(error_message, '')) + "
          '$kLocalStorageRowOverheadBytes'
          '), 0) AS byte_estimate '
          'FROM cached_planning_mutations '
          'WHERE user_id = ?1 AND organization_id = ?2',
          variables: [
            Variable<String>(userId),
            Variable<String>(organizationId),
          ],
          readsFrom: {_database.cachedPlanningMutations},
        )
        .getSingle();
    return row.read<int>('byte_estimate');
  }

  Future<int> measureMutationCount({
    required String userId,
    required String organizationId,
  }) async {
    final countExpression = _database.cachedPlanningMutations.aggregateId
        .count();
    final query = _database.selectOnly(_database.cachedPlanningMutations)
      ..addColumns([countExpression])
      ..where(
        _database.cachedPlanningMutations.userId.equals(userId) &
            _database.cachedPlanningMutations.organizationId.equals(
              organizationId,
            ),
      );
    final row = await query.getSingle();
    return row.read(countExpression) ?? 0;
  }

  /// Projection footprint across every cached owner. The projection is never
  /// evicted, so this is reported for the monitor rather than acted on.
  Future<int> measureProjectionBytes() async {
    final row = await _database
        .customSelect(
          'SELECT ('
          '(SELECT COALESCE(SUM(length(user_id) + length(organization_id) + '
          '$kLocalStorageRowOverheadBytes), 0) '
          'FROM planning_projection_owners) + '
          '(SELECT COALESCE(SUM(length(user_id) + length(organization_id) + '
          'length(plan_id) + length(slug) + length(name) + '
          "length(COALESCE(description, '')) + "
          '$kLocalStorageRowOverheadBytes), 0) '
          'FROM cached_planning_plans) + '
          '(SELECT COALESCE(SUM(length(user_id) + length(organization_id) + '
          'length(session_id) + length(plan_id) + '
          'length(slug) + length(name) + $kLocalStorageRowOverheadBytes), 0) '
          'FROM cached_planning_sessions) + '
          '(SELECT COALESCE(SUM(length(user_id) + length(organization_id) + '
          'length(session_item_id) + length(plan_id) + '
          'length(session_id) + length(song_id) + length(song_title) + '
          '$kLocalStorageRowOverheadBytes), 0) '
          'FROM cached_planning_session_items)'
          ') AS byte_estimate',
          readsFrom: {
            _database.planningProjectionOwners,
            _database.cachedPlanningPlans,
            _database.cachedPlanningSessions,
            _database.cachedPlanningSessionItems,
          },
        )
        .getSingle();
    return row.read<int>('byte_estimate');
  }
}
