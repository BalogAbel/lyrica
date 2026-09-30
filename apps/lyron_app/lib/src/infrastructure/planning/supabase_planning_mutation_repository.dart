import 'dart:io';

import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/shared/connectivity_failure.dart';
import 'package:lyron_app/src/shared/permanent_authorization_denial.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabasePlanningMutationRepository
    implements PlanningMutationRemoteRepository {
  SupabasePlanningMutationRepository(SupabaseClient client) : _rpc = client.rpc;

  const SupabasePlanningMutationRepository.testing({required this._rpc});

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

      final params = _paramsFor(record, organizationId: organizationId);

      final response = await _rpc(rpcName, params: params);
      final responseMap = switch (response) {
        List() when response.isEmpty =>
          throw const PlanningMutationSyncException(
            PlanningMutationSyncErrorCode.unknown,
            message: 'Planning mutation RPC returned an empty result set.',
          ),
        List() => response.first as Map,
        _ => response as Map,
      };
      final row = Map<String, dynamic>.from(responseMap);
      return _mapRow(record, row, organizationId: organizationId);
    } on Object catch (error) {
      throw _mapError(error);
    }
  }

  // Spec D4 (docs/specs/2026-09-29-plan-delete-and-session-cascade.md):
  // each kind sends exactly its RPC's parameters. A delete converted from a
  // tombstoned create (resolveCancelledCreate uses copyWith) still carries
  // the create's slug/name; sending those made PostgREST find no matching
  // function (PGRST202), which mapped to `unknown` and left the row pending
  // forever. Parameters a function declares are always sent, null included,
  // so a missing base surfaces as the RPC's own conflict instead.
  Map<String, dynamic> _paramsFor(
    PlanningMutationRecord record, {
    required String organizationId,
  }) {
    final organization = <String, dynamic>{'p_organization_id': organizationId};
    return switch (record.kind) {
      PlanningMutationKind.planCreate => {
        ...organization,
        'p_plan_id': record.aggregateId,
        'p_slug': record.slug,
        'p_name': record.name,
        'p_description': record.description,
        'p_scheduled_for': record.scheduledFor?.toIso8601String(),
      },
      PlanningMutationKind.planEdit => {
        ...organization,
        'p_plan_id': record.aggregateId,
        'p_base_version': record.baseVersion,
        'p_name': record.name,
        'p_description': record.description,
        'p_scheduled_for': record.scheduledFor?.toIso8601String(),
      },
      PlanningMutationKind.sessionCreate => {
        ...organization,
        'p_plan_id': record.planId,
        'p_session_id': record.aggregateId,
        'p_slug': record.slug,
        'p_name': record.name,
      },
      PlanningMutationKind.sessionRename => {
        ...organization,
        'p_session_id': record.aggregateId,
        'p_base_version': record.baseVersion,
        'p_name': record.name,
      },
      PlanningMutationKind.sessionDelete => {
        ...organization,
        'p_session_id': record.aggregateId,
        'p_base_version': record.baseVersion,
      },
      PlanningMutationKind.sessionReorder => {
        ...organization,
        'p_plan_id': record.planId ?? record.aggregateId,
        'p_base_version': record.baseVersion,
        'p_session_ids': record.orderedSiblingIds,
      },
      PlanningMutationKind.sessionItemCreateSong => {
        ...organization,
        'p_session_id': record.sessionId,
        'p_session_item_id': record.aggregateId,
        'p_song_id': record.songId,
        'p_base_version': record.baseVersion,
        'p_position': record.position,
      },
      PlanningMutationKind.sessionItemDelete => {
        ...organization,
        'p_session_id': record.sessionId,
        'p_session_item_id': record.aggregateId,
        'p_base_version': record.baseVersion,
      },
      PlanningMutationKind.sessionItemReorder => {
        ...organization,
        'p_session_id': record.sessionId,
        'p_base_version': record.baseVersion,
        'p_session_item_ids': record.orderedSiblingIds,
      },
    };
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
      acceptedPlanContentVersion:
          ((row['plan_content_version'] ?? row['content_version']) as num?)
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
      // spec D5.6 / ADR-035: permanent, terminal -- see
      // isPermanentAuthorizationDenial's doc comment for the full
      // rationale (shared with supabase_song_mutation_repository.dart).
      // `not_authorized` is this repository's own domain-specific signal
      // on top of that shared predicate.
      if (isPermanentAuthorizationDenial(error) ||
          message.contains('not_authorized')) {
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
