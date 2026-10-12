import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/planning/planning_remote_refresh_repository.dart';
import 'package:lyron_app/src/application/planning/planning_sync_payload.dart';
import 'package:lyron_app/src/shared/keyset_paging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PlanningPageFetcher =
    Future<List<Map<String, dynamic>>> Function({
      required String organizationId,
      required String? after,
      required int limit,
    });

class SupabasePlanningRepository implements PlanningRemoteRefreshRepository {
  SupabasePlanningRepository(
    SupabaseClient client, {
    @visibleForTesting int pageSize = 500,
  }) : this.testing(
         pageSize: pageSize,
         fetchPlanPage: _keysetFetcher(
           client,
           table: 'plans',
           columns:
               'id, organization_id, slug, name, description, scheduled_for, updated_at, version, content_version',
         ),
         fetchSessionPage: _keysetFetcher(
           client,
           table: 'sessions',
           columns: 'id, plan_id, slug, name, position, version',
         ),
         fetchSessionItemPage: _keysetFetcher(
           client,
           table: 'session_items',
           columns: 'id, session_id, position, song:songs(id, slug, title)',
         ),
       );

  @visibleForTesting
  const SupabasePlanningRepository.testing({
    required this._fetchPlanPage,
    required this._fetchSessionPage,
    required this._fetchSessionItemPage,
    this._pageSize = 500,
  });

  final PlanningPageFetcher _fetchPlanPage;
  final PlanningPageFetcher _fetchSessionPage;
  final PlanningPageFetcher _fetchSessionItemPage;
  final int _pageSize;

  static PlanningPageFetcher _keysetFetcher(
    SupabaseClient client, {
    required String table,
    required String columns,
  }) {
    return ({
      required String organizationId,
      required String? after,
      required int limit,
    }) async {
      var query = client
          .from(table)
          .select(columns)
          .eq('organization_id', organizationId);
      if (after != null) {
        query = query.gt('id', after);
      }
      final rows = await query.order('id', ascending: true).limit(limit);
      return List<Map<String, dynamic>>.from(rows);
    };
  }

  Future<List<Map<String, dynamic>>> _readStream(
    PlanningPageFetcher fetchPage, {
    required String organizationId,
    required String stream,
    bool Function()? shouldContinue,
  }) {
    return readAllKeysetPages<Map<String, dynamic>, String>(
      fetchPage: ({required after, required limit}) =>
          fetchPage(organizationId: organizationId, after: after, limit: limit),
      keyOf: (row) => row['id'] as String,
      compareKeys: compareUuidKeys,
      pageSize: _pageSize,
      shouldContinue: shouldContinue,
      stream: stream,
    );
  }

  @override
  Future<PlanningSyncPayload> fetchPlanningSyncPayload({
    required String organizationId,
    bool Function()? shouldContinue,
  }) async {
    // I7 (docs/specs/2026-09-29-plan-delete-and-session-cascade.md; paging in
    // docs/specs/2026-10-12-paged-remote-pulls.md, PG5): three organization-
    // wide streams are read strictly in this order, each to its end before
    // the next starts: plans (including content_version), then sessions, then
    // session items. A concurrent write can therefore only leave a plan's
    // contentVersion behind the children read after it, never ahead. A child
    // whose parent is not in the already-read parent set (a session without
    // its plan, an item without its kept session) was created after that
    // parent stream was read and is dropped; the next refresh picks it up.
    final planRows = await _readStream(
      _fetchPlanPage,
      organizationId: organizationId,
      stream: 'plans',
      shouldContinue: shouldContinue,
    );
    final sessionRows = await _readStream(
      _fetchSessionPage,
      organizationId: organizationId,
      stream: 'sessions',
      shouldContinue: shouldContinue,
    );
    final itemRows = await _readStream(
      _fetchSessionItemPage,
      organizationId: organizationId,
      stream: 'session_items',
      shouldContinue: shouldContinue,
    );

    final plans = planRows.map(_mapPlan).toList(growable: false)
      ..sort((left, right) {
        final leftScheduled = left.scheduledFor;
        final rightScheduled = right.scheduledFor;
        if (leftScheduled == null && rightScheduled != null) {
          return 1;
        }
        if (leftScheduled != null && rightScheduled == null) {
          return -1;
        }
        if (leftScheduled != null && rightScheduled != null) {
          final scheduledComparison = leftScheduled.compareTo(rightScheduled);
          if (scheduledComparison != 0) {
            return scheduledComparison;
          }
        }

        final updatedComparison = right.updatedAt.compareTo(left.updatedAt);
        if (updatedComparison != 0) {
          return updatedComparison;
        }

        return left.id.compareTo(right.id);
      });

    final planIds = {for (final plan in plans) plan.id};
    final sessionsByPlan = <String, List<PlanningSyncSession>>{};
    final planIdBySession = <String, String>{};
    for (final row in sessionRows) {
      final session = _mapSession(row);
      if (!planIds.contains(session.planId)) {
        continue;
      }
      sessionsByPlan.putIfAbsent(session.planId, () => []).add(session);
      planIdBySession[session.id] = session.planId;
    }
    final itemsBySession = <String, List<PlanningSyncSessionItem>>{};
    for (final row in itemRows) {
      final sessionId = row['session_id'] as String;
      final planId = planIdBySession[sessionId];
      if (planId == null) {
        continue;
      }
      itemsBySession
          .putIfAbsent(sessionId, () => [])
          .add(_mapItem(row, planId: planId));
    }

    final syncSessions = <PlanningSyncSession>[];
    final syncItems = <PlanningSyncSessionItem>[];
    for (final plan in plans) {
      final sessions = [...?sessionsByPlan[plan.id]]
        ..sort((left, right) {
          final positionComparison = left.position.compareTo(right.position);
          if (positionComparison != 0) {
            return positionComparison;
          }
          return left.id.compareTo(right.id);
        });
      for (final session in sessions) {
        syncSessions.add(session);
        syncItems.addAll(
          [...?itemsBySession[session.id]]..sort((left, right) {
            final positionComparison = left.position.compareTo(right.position);
            if (positionComparison != 0) {
              return positionComparison;
            }
            return left.id.compareTo(right.id);
          }),
        );
      }
    }

    return PlanningSyncPayload(
      plans: plans,
      sessions: syncSessions,
      items: syncItems,
    );
  }

  PlanningSyncPlan _mapPlan(Map<String, dynamic> row) {
    return PlanningSyncPlan(
      id: row['id'] as String,
      slug: row['slug'] as String? ?? row['id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      scheduledFor: _parseNullableDateTime(row['scheduled_for']),
      updatedAt: _parseDateTime(row['updated_at']),
      version: (row['version'] as num?)?.toInt() ?? 1,
      contentVersion: (row['content_version'] as num?)?.toInt(),
    );
  }

  PlanningSyncSession _mapSession(Map<String, dynamic> row) {
    return PlanningSyncSession(
      id: row['id'] as String,
      planId: row['plan_id'] as String,
      slug: row['slug'] as String? ?? row['id'] as String,
      position: row['position'] as int,
      name: row['name'] as String,
      version: (row['version'] as num?)?.toInt() ?? 1,
    );
  }

  PlanningSyncSessionItem _mapItem(
    Map<String, dynamic> row, {
    required String planId,
  }) {
    final rawSong = row['song'];
    if (rawSong is! Map) {
      throw StateError(
        'Session item ${row['id']} is missing its readable song projection.',
      );
    }

    final song = Map<String, dynamic>.from(rawSong);
    return PlanningSyncSessionItem(
      id: row['id'] as String,
      planId: planId,
      sessionId: row['session_id'] as String,
      position: row['position'] as int,
      songId: song['id'] as String,
      songTitle: song['title'] as String,
    );
  }

  DateTime _parseDateTime(Object? value) {
    final parsed = _parseNullableDateTime(value);
    if (parsed == null) {
      throw StateError('Expected a non-null timestamp but received null.');
    }
    return parsed;
  }

  DateTime? _parseNullableDateTime(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.parse(value);
    }
    throw StateError('Unsupported timestamp value: $value');
  }
}
