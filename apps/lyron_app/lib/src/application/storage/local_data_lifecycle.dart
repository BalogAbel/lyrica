import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';

/// The exhaustive set of reasons local user data may be destroyed (D1).
///
/// There is deliberately no default value, no nullable reason, and no
/// catch-all "other" case anywhere a [PurgeReason] is required -- every
/// purge must name one of these four.
enum PurgeReason {
  userSignOut,
  accountDeleted,
  differentUserSignIn,
  membershipRevokedConfirmed,
}

/// Identifies which local store a purge (or, later, an eviction) event
/// targets, for the audit trail [LocalDataEventsRecorder] writes.
enum PurgeTarget { songCatalog, planningData, identity }

/// D5 (docs/specs/2026-08-19-local-data-durability-contract.md): the result
/// of [LocalDataLifecycle.resolveVerifiedEmptyMembership]. Deliberately
/// minimal -- Task 4.2 adds the variants for a confirmed purge and for a
/// purge pending user confirmation; this phase only ever quarantines.
enum MembershipRevocationResolution {
  /// This call recorded the first verified-empty-membership resolution for
  /// this user: the identity row's `membershipRevokedAt` marker was just
  /// set, and nothing was deleted.
  quarantined,

  /// A marker was already present for this user before this call; this
  /// call made no further changes. (Task 4.2 will replace this branch with
  /// the confirmed-purge decision -- see the `TODO` on
  /// [LocalDataLifecycle.resolveVerifiedEmptyMembership].)
  alreadyQuarantined,
}

/// Thrown by a mutation-service write guard when the acting user's local
/// data is in quarantine (D5, non-null `membershipRevokedAt`): reads stay
/// available, but no new local write is accepted until the quarantine is
/// resolved (Task 4.2/4.3).
class MembershipQuarantinedException implements Exception {
  const MembershipQuarantinedException(this.userId);

  final String userId;

  @override
  String toString() =>
      'MembershipQuarantinedException: local writes are blocked for '
      '$userId while its membership revocation is in quarantine';
}

/// The durable audit trail for [LocalDataLifecycle]'s purges.
///
/// The real Drift-backed implementation is a later task; this interface
/// only defines the contract [LocalDataLifecycle] depends on.
abstract interface class LocalDataEventsRecorder {
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  });

  /// Eviction events, recorded under a distinct non-purge `kind`. Promoted
  /// onto this interface with Phase 3 (docs/specs/2026-08-19-local-data
  /// -durability-contract.md); no call site exists yet -- schema/store
  /// readiness only, per ADR-035's Phase 2 notes.
  Future<void> recordEviction({
    required String target,
    String? userId,
    int? rowsAffected,
  });

  /// D4 (docs/specs/2026-08-19-local-data-durability-contract.md): records
  /// that an incoming empty `listSongs()` response was rejected against a
  /// non-empty stored snapshot -- a distinct audit `kind`, not a
  /// [PurgeReason] and not routed through [LocalDataLifecycle]'s purge
  /// primitives (this is not a purge; the cache is left untouched).
  Future<void> recordRejectedEmptySnapshot({
    required String userId,
    required String organizationId,
  });

  /// D6 (docs/specs/2026-08-19-local-data-durability-contract.md): records
  /// that a guarded local write failed with an exception that was NOT
  /// recognised as a concrete storage-exhaustion signal -- so, per D6's
  /// narrowed trigger, no eviction ran at all. A distinct audit `kind` from
  /// [recordEviction]: that method means "an eviction of N rows genuinely
  /// happened," this one means "no eviction ran, the write simply failed."
  /// Not a purge -- no [PurgeReason] applies here.
  Future<void> recordStorageWriteFailure({String? userId});

  /// D5 (docs/specs/2026-08-19-local-data-durability-contract.md): records
  /// the first verified-empty-membership resolution for a user -- a
  /// distinct audit `kind` ('quarantine'), not a purge: nothing is deleted
  /// when this is written. [reason] is a short machine-readable string
  /// (e.g. `'membershipRevokedFirstResolution'`), not a [PurgeReason] --
  /// none of the four purge reasons describe "nothing was deleted."
  Future<void> recordQuarantine({
    required PurgeTarget target,
    required String reason,
    String? userId,
  });
}

/// D7: the single gate every local-data purge primitive must be reached
/// through, requiring every call to name a real [PurgeReason].
///
/// Each destructive method here performs the underlying store's deletion,
/// THEN best-effort writes one audit record for it. If the underlying
/// deletion throws, the exception propagates unchanged and no audit record
/// is written -- a failure is reported, never silently claimed as a success.
/// The reverse must also hold: a deletion that already committed must never
/// be reported as failed just because the audit write itself failed
/// afterwards -- see [_recordBestEffort]. Callers (e.g.
/// `wipePriorAndProceedFor` in `auth_providers.dart`) fall back to
/// `cancelToPriorUser` on any exception from these methods, on the
/// documented assumption that an exception means the destructive part did
/// not commit; an audit-write failure must not violate that assumption.
///
/// The audit write is also dispatched with [unawaited], not awaited before
/// the destructive method's own `Future` resolves: the deletion/clear is
/// what these methods promise to complete, and callers that race a
/// currentness check against a `Future.wait` of several of these calls (see
/// `wipePriorAndProceedFor`) must see that resolve as soon as the data
/// itself is gone, not stalled behind a same-database-but-different-file
/// logging write that is already best-effort and cannot affect the outcome
/// either way.
class LocalDataLifecycle {
  LocalDataLifecycle({
    required this._songCatalogStore,
    required this._planningLocalStore,
    required this._identityStore,
    required this._noteLastKnownIdentity,
    required this._eventsRecorder,
  });

  final SongCatalogStore _songCatalogStore;
  final PlanningLocalStore _planningLocalStore;
  final LastKnownIdentityStore _identityStore;
  final void Function(LastKnownIdentity?) _noteLastKnownIdentity;
  final LocalDataEventsRecorder _eventsRecorder;

  Future<void> purgeSongCatalog({
    required String userId,
    required PurgeReason reason,
  }) async {
    await _songCatalogStore.deleteCatalogsForUser(userId: userId);
    unawaited(
      _recordBestEffort(
        target: PurgeTarget.songCatalog,
        reason: reason,
        userId: userId,
      ),
    );
  }

  Future<void> purgePlanningData({
    required String userId,
    required PurgeReason reason,
    bool Function()? shouldContinue,
  }) async {
    await _planningLocalStore.deletePlanningDataForUser(
      userId: userId,
      shouldContinue: shouldContinue,
    );
    unawaited(
      _recordBestEffort(
        target: PurgeTarget.planningData,
        reason: reason,
        userId: userId,
      ),
    );
  }

  /// [userId] is supplied by the caller when known, for audit attribution
  /// only -- it does not gate whether the clear happens. Deliberately does
  /// NOT read the identity store first to derive it: an extra read before
  /// the clear would (a) introduce a new failure mode that could abort a
  /// clear that previously ran unconditionally, and (b) insert an await
  /// point between the caller's currentness guard and the actual `clear()`,
  /// widening a race window `auth_providers.dart` explicitly guards against
  /// (see the comment on the `isCurrent` re-check ahead of
  /// `wipePriorAndProceedFor`'s clear). Most call sites already have the
  /// userId in hand from their own context.
  Future<void> clearIdentity({
    required PurgeReason reason,
    String? userId,
  }) async {
    await _identityStore.clear();
    _noteLastKnownIdentity(null);
    unawaited(
      _recordBestEffort(
        target: PurgeTarget.identity,
        reason: reason,
        userId: userId,
      ),
    );
  }

  /// Not a purge -- no reason required, no audit record.
  Future<void> writeIdentity(LastKnownIdentity identity) async {
    await _identityStore.write(identity);
    _noteLastKnownIdentity(identity);
  }

  /// D5 (docs/specs/2026-08-19-local-data-durability-contract.md, ADR-035
  /// Phase 4 mechanism decisions, "Gap 1"): the single gate both
  /// verified-empty-membership call sites (`auth_providers.dart`'s
  /// `persistNewIdentity`, `planning_providers.dart`'s
  /// `VerifiedEmptyMembershipCleanupCoordinator`) must call instead of
  /// purging directly. Reachable only from their `ActiveOrganizationVerifiedEmpty`
  /// branches -- an unverified resolution (connectivity failure, unknown
  /// failure, or any other outcome) never reaches this method, which is
  /// what keeps quarantine from ever being entered on anything less than a
  /// real verified-empty resolution.
  ///
  /// Task 4.1 implements only the first-resolution half: a null
  /// `membershipRevokedAt` on the caller's identity row is set to now, via
  /// the same non-destructive [writeIdentity] path every other identity
  /// write already uses -- nothing is purged. A non-null marker already
  /// present is a documented no-op for now; Task 4.2 replaces that branch
  /// with the confirmed-purge decision (pending-work check, then the same
  /// purgeSongCatalog/purgePlanningData/clearIdentity triple every other
  /// `membershipRevokedConfirmed` call site already uses).
  Future<MembershipRevocationResolution> resolveVerifiedEmptyMembership({
    required String userId,
  }) async {
    final existing = await _identityStore.read();
    // Defensive only (ADR-035): a different user's identity row reaching
    // here is already impossible in practice -- differentUserSignIn fully
    // clears the row via clearIdentity before a new one is written. Treated
    // as "no prior marker" rather than asserted against.
    final matchesCaller = existing != null && existing.userId == userId;

    if (matchesCaller && existing.membershipRevokedAt != null) {
      // TODO(Task 4.2): this is the second, independent verified-empty
      // resolution. Check PendingLocalWorkCounter.count(userId): zero ->
      // purgeSongCatalog + purgePlanningData + clearIdentity, all
      // PurgeReason.membershipRevokedConfirmed; nonzero or unreadable ->
      // surface a confirmation request instead of purging (ADR-035 Phase 4,
      // Gap 1 step 3 / Gap 3).
      return MembershipRevocationResolution.alreadyQuarantined;
    }

    final revokedAt = DateTime.now().toUtc();
    final quarantined = matchesCaller
        ? LastKnownIdentity(
            userId: existing.userId,
            email: existing.email,
            organizationId: existing.organizationId,
            updatedAt: existing.updatedAt,
            membershipRevokedAt: revokedAt,
          )
        : LastKnownIdentity(
            userId: userId,
            email: existing?.email ?? '',
            organizationId: null,
            membershipRevokedAt: revokedAt,
          );

    await writeIdentity(quarantined);
    unawaited(
      _recordQuarantineBestEffort(
        target: PurgeTarget.identity,
        reason: 'membershipRevokedFirstResolution',
        userId: userId,
      ),
    );

    return MembershipRevocationResolution.quarantined;
  }

  /// Writes the audit record without letting a failure here masquerade as a
  /// failure of the deletion/clear that already committed above it. Reported
  /// via [FlutterError.reportError] rather than rethrown, mirroring how this
  /// codebase already treats other post-commit, non-critical failures (see
  /// the `FlutterError.reportError` calls in `auth_providers.dart`).
  Future<void> _recordBestEffort({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {
    try {
      await _eventsRecorder.recordPurge(
        target: target,
        reason: reason,
        userId: userId,
        rowsAffected: rowsAffected,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'LocalDataLifecycle',
          context: ErrorDescription(
            'failed to write a local_data_events audit record for a '
            '$target purge (reason: $reason) that already completed -- the '
            'purge itself succeeded and is not affected',
          ),
        ),
      );
    }
  }

  /// Same best-effort shape as [_recordBestEffort], for the quarantine
  /// audit `kind`: the marker write it describes already committed by the
  /// time this runs, so a failure here must never be reported as though
  /// the quarantine itself failed to take effect.
  Future<void> _recordQuarantineBestEffort({
    required PurgeTarget target,
    required String reason,
    String? userId,
  }) async {
    try {
      await _eventsRecorder.recordQuarantine(
        target: target,
        reason: reason,
        userId: userId,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'LocalDataLifecycle',
          context: ErrorDescription(
            'failed to write a local_data_events audit record for a '
            '$target quarantine (reason: $reason) that already completed '
            '-- the quarantine marker itself was already set and is not '
            'affected',
          ),
        ),
      );
    }
  }
}
