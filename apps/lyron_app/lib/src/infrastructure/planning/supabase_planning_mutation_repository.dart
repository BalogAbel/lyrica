import 'dart:io';

import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/shared/connectivity_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabasePlanningMutationRepository
    implements PlanningMutationRemoteRepository {
  SupabasePlanningMutationRepository(SupabaseClient client) : _rpc = client.rpc;

  const SupabasePlanningMutationRepository.testing({
    required Future<dynamic> Function(String fn, {Map<String, dynamic>? params})
    rpc,
  }) : _rpc = rpc;

  final Future<dynamic> Function(String fn, {Map<String, dynamic>? params})
  _rpc;

  @override
  Future<PlanningMutationRecord> syncMutation({
    required String organizationId,
    required PlanningMutationRecord record,
  }) async {
    try {
      final rpcName = switch (record.kind) {
        PlanningMutationKind.planCreate => 'create_plan',
        PlanningMutationKind.planEdit => 'update_plan_fields',
        PlanningMutationKind.sessionCreate => 'create_session',
        PlanningMutationKind.sessionRename => 'rename_session',
        PlanningMutationKind.sessionDelete => 'delete_empty_session',
        PlanningMutationKind.sessionReorder => 'reorder_plan_sessions',
        PlanningMutationKind.sessionItemCreateSong =>
          'create_song_session_item',
        PlanningMutationKind.sessionItemDelete => 'delete_session_item',
        PlanningMutationKind.sessionItemReorder => 'reorder_session_items',
      };

      final params = <String, dynamic>{
        'p_organization_id': organizationId,
        if (record.kind == PlanningMutationKind.planCreate ||
            record.kind == PlanningMutationKind.planEdit)
          'p_plan_id': record.aggregateId,
        if (record.kind == PlanningMutationKind.sessionCreate)
          'p_plan_id': record.planId,
        if (record.kind == PlanningMutationKind.sessionReorder)
          'p_plan_id': record.planId ?? record.aggregateId,
        if (record.kind == PlanningMutationKind.sessionRename ||
            record.kind == PlanningMutationKind.sessionDelete ||
            record.kind == PlanningMutationKind.sessionItemCreateSong ||
            record.kind == PlanningMutationKind.sessionItemDelete ||
            record.kind == PlanningMutationKind.sessionItemReorder)
          'p_session_id': record.aggregateId,
        if (record.kind == PlanningMutationKind.sessionItemCreateSong ||
            record.kind == PlanningMutationKind.sessionItemDelete ||
            record.kind == PlanningMutationKind.sessionItemReorder)
          'p_session_id': record.sessionId,
        if (record.kind == PlanningMutationKind.sessionCreate)
          'p_session_id': record.aggregateId,
        if (record.kind == PlanningMutationKind.sessionReorder)
          'p_session_ids': record.orderedSiblingIds,
        if (record.kind == PlanningMutationKind.sessionItemReorder)
          'p_session_item_ids': record.orderedSiblingIds,
        if (record.kind == PlanningMutationKind.sessionItemCreateSong)
          'p_session_item_id': record.aggregateId,
        if (record.kind == PlanningMutationKind.sessionItemCreateSong)
          'p_song_id': record.songId,
        if (record.kind == PlanningMutationKind.sessionItemCreateSong)
          'p_position': record.position,
        if (record.kind == PlanningMutationKind.sessionItemDelete)
          'p_session_item_id': record.aggregateId,
        if (record.slug != null) 'p_slug': record.slug,
        if (record.name != null) 'p_name': record.name,
        if (record.description != null ||
            record.kind == PlanningMutationKind.planCreate ||
            record.kind == PlanningMutationKind.planEdit)
          'p_description': record.description,
        if (record.scheduledFor != null ||
            record.kind == PlanningMutationKind.planCreate ||
            record.kind == PlanningMutationKind.planEdit)
          'p_scheduled_for': record.scheduledFor?.toIso8601String(),
        if (record.baseVersion != null) 'p_base_version': record.baseVersion,
      };

      final response = await _rpc(rpcName, params: params);
      final row = Map<String, dynamic>.from(response as Map);
      return _mapRow(record, row, organizationId: organizationId);
    } on Object catch (error) {
      throw _mapError(error);
    }
  }

  PlanningMutationRecord _mapRow(
    PlanningMutationRecord original,
    Map<String, dynamic> row, {
    required String organizationId,
  }) {
    final orderedSiblingIdsValue =
        row['ordered_session_ids'] ?? row['ordered_session_item_ids'];
    final orderedSiblingPositionsValue =
        row['ordered_session_positions'] ??
        row['ordered_session_item_positions'];
    return original.copyWith(
      aggregateId: (row['id'] ?? original.aggregateId) as String,
      organizationId: (row['organization_id'] ?? organizationId) as String,
      planId: (row['plan_id'] ?? original.planId) as String?,
      sessionId: (row['session_id'] ?? original.sessionId) as String?,
      slug: (row['slug'] ?? original.slug) as String?,
      position: ((row['position'] ?? original.position) as num?)?.toInt(),
      songId: (row['song_id'] ?? original.songId) as String?,
      songTitle: (row['song_title'] ?? original.songTitle) as String?,
      orderedSiblingIds: orderedSiblingIdsValue is List
          ? orderedSiblingIdsValue
                .map((value) => value.toString())
                .toList(growable: false)
          : original.orderedSiblingIds,
      orderedSiblingPositions: orderedSiblingPositionsValue is List
          ? orderedSiblingPositionsValue
                .map((value) => (value as num).toInt())
                .toList(growable: false)
          : original.orderedSiblingPositions,
      baseVersion: ((row['version'] ?? row['deleted_version']) as num?)
          ?.toInt(),
      clearErrorCode: true,
      clearErrorMessage: true,
      syncStatus: PlanningMutationSyncStatus.pending,
    );
  }

  PlanningMutationSyncException _mapError(Object error) {
    if (error is PlanningMutationSyncException) {
      return error;
    }
    if (isConnectivityFailure(error) || error is SocketException) {
      return const PlanningMutationSyncException(
        PlanningMutationSyncErrorCode.connectivityFailure,
      );
    }
    if (error is PostgrestException) {
      final message = error.message.toLowerCase();
      if (error.code == '42501' || message.contains('not_authorized')) {
        return PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.authorizationDenied,
          message: error.message,
        );
      }
      if (error.code == 'P0002' || message.contains('not_found')) {
        return PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.remoteMissing,
          message: error.message,
        );
      }
      if (error.code == 'P0001' && message.contains('conflict')) {
        return PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.conflict,
          message: error.message,
        );
      }
      if (error.code == 'P0001' && message.contains('blocked')) {
        return PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.dependencyBlocked,
          message: error.message,
        );
      }
      if (error.code == 'P0001' &&
          (message.contains('duplicate') || message.contains('out_of_scope'))) {
        return PlanningMutationSyncException(
          PlanningMutationSyncErrorCode.dependencyBlocked,
          message: error.message,
        );
      }
    }
    return PlanningMutationSyncException(
      PlanningMutationSyncErrorCode.unknown,
      message: error.toString(),
    );
  }
}
