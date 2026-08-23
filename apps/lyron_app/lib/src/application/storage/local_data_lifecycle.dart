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
/// of [LocalDataLifecycle.resolveVerifiedEmptyMembership].
enum MembershipRevocationResolution {
  /// This call recorded the first verified-empty-membership resolution for
  /// this user: the identity row's `membershipRevokedAt` marker was just
  /// set, and nothing was deleted.
  quarantined,

  /// A marker was already present for this user before this call (the
  /// second, independent verified-empty resolution) and the purge triple
  /// (`purgeSongCatalog` + `purgePlanningData` + `clearIdentity`, all
  /// [PurgeReason.membershipRevokedConfirmed]) ran -- either because
  /// [LocalDataLifecycle.resolveVerifiedEmptyMembership]'s `countPendingWork`
  /// callback reported zero pending work (no confirmation needed, nothing to
  /// lose), or because it reported nonzero/unreadable work and the caller's
  /// `requestConfirmation` callback resolved `true`.
  purgedConfirmed,

  /// A marker was already present for this user before this call, pending
  /// work was nonzero or unreadable, and `requestConfirmation` resolved
  /// `false` (declined, dismissed, or superseded). Nothing was purged; the
  /// user remains quarantined exactly as before this call -- the marker is
  /// untouched.
  confirmationDeclined,
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
  /// The first-resolution half sets a null `membershipRevokedAt` on the
  /// caller's identity row to now, via the same non-destructive
  /// [writeIdentity] path every other identity write already uses -- nothing
  /// is purged. A non-null marker already present (the second, independent
  /// resolution) runs the confirmed-purge decision (Task 4.2, ADR-035 Phase
  /// 4 "Gap 1" step 3): [countPendingWork] is consulted, and either the same
  /// purgeSongCatalog/purgePlanningData/clearIdentity triple every other
  /// `membershipRevokedConfirmed` call site already uses runs directly (zero
  /// pending work), or [requestConfirmation] is awaited first (nonzero or
  /// unreadable pending work -- an unreadable count is treated exactly like
  /// a nonzero one, never as "safe to skip", mirroring ADR-029 D5).
  ///
  /// [countPendingWork] and [requestConfirmation] are only ever invoked on
  /// the second-resolution branch -- a first resolution always quarantines
  /// without consulting either. [countPendingWork] returning `null` means
  /// "could not be determined" (a storage failure, say), which
  /// [requestConfirmation] must still be asked about, never treated as zero.
  ///
  /// [email] must be the caller's own live-session email (found in scope at
  /// both call sites via the `AppAuthSession`/handler chain that is actively
  /// resolving), never a value read back off any stored row -- see the
  /// comment ahead of the `matchesCaller` branch below for why.
  Future<MembershipRevocationResolution> resolveVerifiedEmptyMembership({
    required String userId,
    required String email,
    required Future<int?> Function() countPendingWork,
    required Future<bool> Function(int? pendingCount) requestConfirmation,
  }) async {
    final existing = await _identityStore.read();
    // Defensive only (ADR-035): a different user's identity row reaching
    // here is already impossible in practice -- differentUserSignIn fully
    // clears the row via clearIdentity before a new one is written. Treated
    // as "no prior marker" rather than asserted against.
    final matchesCaller = existing != null && existing.userId == userId;

    if (matchesCaller && existing.membershipRevokedAt != null) {
      // Second, independent verified-empty resolution (independent by
      // construction -- see the "Freshness" note in ADR-035's Gap 1: each
      // call site only ever reaches this branch off a genuine new RPC round
      // trip, never a replay of the first). Uncertainty must never authorise
      // a silent purge, so a null count is asked about exactly like a
      // nonzero one.
      final pendingCount = await countPendingWork();
      if (pendingCount != 0) {
        final confirmed = await requestConfirmation(pendingCount);
        if (!confirmed) {
          return MembershipRevocationResolution.confirmationDeclined;
        }
      }
      await purgeSongCatalog(
        userId: userId,
        reason: PurgeReason.membershipRevokedConfirmed,
      );
      await purgePlanningData(
        userId: userId,
        reason: PurgeReason.membershipRevokedConfirmed,
      );
      await clearIdentity(
        reason: PurgeReason.membershipRevokedConfirmed,
        userId: userId,
      );
      return MembershipRevocationResolution.purgedConfirmed;
    }

    final revokedAt = DateTime.now().toUtc();
    // [email] is always the caller's OWN, live-session email -- passed in
    // by both call sites from the AppAuthSession that is actively resolving
    // right now, never read off a stored row. That is deliberate: `existing`
    // here covers two distinct, both-reachable sub-cases, and neither one
    // may ever legitimately contribute its own `email` to the row being
    // written for `userId` below.
    //   1. existing == null: a fresh device / first-ever sign-in whose live
    //      membership check resolves verified-empty before any
    //      LastKnownIdentity row has ever existed for this user. Ordinary,
    //      not defensive -- there is simply no row yet to read an email
    //      from, so [email] is the only correct source.
    //   2. existing != null but existing.userId != userId (matchesCaller is
    //      false): the defensive case described above -- a stale row left
    //      by a different user. Falling back to `existing.email` here would
    //      durably attach that OTHER user's real email address to this
    //      user's new identity row (see PR review on Task 4.1: this row
    //      feeds AppAuthController._stateForSession, which would then show
    //      the wrong account's email in the offline-authenticated banner).
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
            email: email,
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
