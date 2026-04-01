import 'package:flutter/foundation.dart';
import 'package:lyrica_app/src/domain/planning/plan_detail.dart';
import 'package:lyrica_app/src/domain/planning/plan_summary.dart';
import 'package:lyrica_app/src/domain/planning/planning_repository.dart';
import 'package:lyrica_app/src/domain/planning/session_item_summary.dart';
import 'package:lyrica_app/src/domain/planning/session_summary.dart';
import 'package:lyrica_app/src/domain/song/song_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ListPlanRows = Future<List<Map<String, dynamic>>> Function();
typedef GetPlanRow = Future<Map<String, dynamic>?> Function(String planId);
typedef ListSessionRows =
    Future<List<Map<String, dynamic>>> Function(String planId);

class SupabasePlanningRepository implements PlanningRepository {
  SupabasePlanningRepository(SupabaseClient client)
    : this.testing(
        listPlanRows: () async {
          final rows = await client
              .from('plans')
              .select('id, name, description, scheduled_for, updated_at');
          return List<Map<String, dynamic>>.from(rows);
        },
        getPlanRow: (planId) async {
          final row = await client
              .from('plans')
              .select('id, name, description, scheduled_for, updated_at')
              .eq('id', planId)
              .maybeSingle();
          return row == null ? null : Map<String, dynamic>.from(row);
        },
        listSessionRows: (planId) async {
          final rows = await client
              .from('sessions')
              .select(
                'id, name, position, session_items(id, position, song:songs(id, title))',
              )
              .eq('plan_id', planId)
              .order('position', ascending: true)
              .order(
                'position',
                ascending: true,
                referencedTable: 'session_items',
              );
          return List<Map<String, dynamic>>.from(rows);
        },
      );

  @visibleForTesting
  SupabasePlanningRepository.testing({
    required ListPlanRows listPlanRows,
    required GetPlanRow getPlanRow,
    required ListSessionRows listSessionRows,
  }) : _listPlanRows = listPlanRows,
       _getPlanRow = getPlanRow,
       _listSessionRows = listSessionRows;

  final ListPlanRows _listPlanRows;
  final GetPlanRow _getPlanRow;
  final ListSessionRows _listSessionRows;

  @override
  Future<List<PlanSummary>> listPlans() async {
    final rows = await _listPlanRows();
    final plans = rows.map(_mapPlanSummary).toList(growable: false);

    final sortedPlans = plans.toList(growable: false)
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

    return sortedPlans;
  }

  @override
  Future<PlanDetail> getPlanDetail(String planId) async {
    final planRow = await _getPlanRow(planId);
    if (planRow == null) {
      throw StateError('Plan not found: $planId');
    }

    final sessionRows = await _listSessionRows(planId);
    final sessions = sessionRows.map(_mapSessionSummary).toList(growable: false)
      ..sort((left, right) => left.position.compareTo(right.position));

    return PlanDetail(plan: _mapPlanSummary(planRow), sessions: sessions);
  }

  PlanSummary _mapPlanSummary(Map<String, dynamic> row) {
    return PlanSummary(
      id: row['id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      scheduledFor: _parseNullableDateTime(row['scheduled_for']),
      updatedAt: _parseDateTime(row['updated_at']),
    );
  }

  SessionSummary _mapSessionSummary(Map<String, dynamic> row) {
    final rawItems = row['session_items'] as List<dynamic>? ?? const [];
    final items =
        rawItems
            .map(
              (item) => _mapSessionItemSummary(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => left.position.compareTo(right.position));

    return SessionSummary(
      id: row['id'] as String,
      name: row['name'] as String,
      position: row['position'] as int,
      items: items,
    );
  }

  SessionItemSummary _mapSessionItemSummary(Map<String, dynamic> row) {
    final rawSong = row['song'];
    if (rawSong is! Map) {
      throw StateError(
        'Session item ${row['id']} is missing its readable song projection.',
      );
    }

    final song = Map<String, dynamic>.from(rawSong);
    return SessionItemSummary(
      id: row['id'] as String,
      position: row['position'] as int,
      song: SongSummary(
        id: song['id'] as String,
        title: song['title'] as String,
      ),
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
