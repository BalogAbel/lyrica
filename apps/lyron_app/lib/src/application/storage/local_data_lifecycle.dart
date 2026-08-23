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

/// The outcome of one [LocalDataLifecycle.resolveVerifiedEmptyMembership]
/// call (D5, spec section D5 / ADR-035 Phase 4).
sealed class MembershipRevocationDecision {
  const MembershipRevocationDecision();
}

/// Why a resolution counted for nothing. A diagnostics screen and Step 2
/// (the purge/confirmation caller) both want to tell these apart, even
/// though none of them purge or move the marker.
enum MembershipRevocationIgnoredReason {
  /// The stored identity row belongs to a different user than the one this
  /// resolution is for.
  notThisUser,

  /// There is no stored identity row at all.
  noRow,

  /// A marker is already set, but the monotonic cooldown separating the two
  /// confirmations (D5.3) has not yet elapsed since this process recorded
  /// it.
  insideCooldown,
}

final class MembershipRevocationIgnored extends MembershipRevocationDecision {
  const MembershipRevocationIgnored(this.reason);

  final MembershipRevocationIgnoredReason reason;

  @override
  bool operator ==(Object other) =>
      other is MembershipRevocationIgnored && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;
}

/// The first counted confirmation: the marker was recorded. Nothing is
/// deleted.
final class MembershipRevocationMarkerRecorded
    extends MembershipRevocationDecision {
  const MembershipRevocationMarkerRecorded();
}

/// The second counted confirmation, cooldown-separated from the first:
/// [markedAt] is the timestamp the marker was originally recorded at, kept
/// as the re-validation token a later purge step re-checks against on
/// re-entry (D5.5 rule 3). Step 1 deliberately deletes nothing on this
/// outcome -- see the class doc on [LocalDataLifecycle
/// .resolveVerifiedEmptyMembership].
final class MembershipRevocationPurgeAuthorized
    extends MembershipRevocationDecision {
  const MembershipRevocationPurgeAuthorized({required this.markedAt});

  final DateTime markedAt;
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

  /// D5.2 (docs/specs/2026-08-19-local-data-durability-contract.md, ADR-035
  /// Phase 4): records that a fresh, online, authenticated empty membership
  /// resolution set the `membershipRevokedAt` marker on the identity row
  /// for [userId]. Neither this nor [recordMembershipRevocationCleared] is
  /// a purge -- no [PurgeReason] applies to either -- but both edges must
  /// be audited: this is the diagnostic proving a purge nearly happened,
  /// the first thing anyone looks for if a data-loss report arrives.
  Future<void> recordMembershipRevocationMarked({required String userId});

  /// D5.2: records that a freshly verified non-empty membership resolution
  /// cleared the `membershipRevokedAt` marker for [userId]. Without this,
  /// a device that reached one confirmation and then recovered leaves no
  /// trace of it at all.
  Future<void> recordMembershipRevocationCleared({required String userId});
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
///
/// D5.5 (normative concurrency model): every identity and marker mutation --
/// [writeIdentity], [clearIdentity], [resolveVerifiedEmptyMembership], and
/// [clearMembershipRevocation] -- is serialized on one global FIFO chain,
/// never keyed by `userId`. `LastKnownIdentity` is a single global row
/// (`rowId = 1`) and this repository's device model excludes multi-account
/// use, so a per-user key would serialize two writers of the same row
/// against nothing (the root cause of the discarded first attempt at this
/// gate -- see the Phase 4 closeout in `docs/plans/2026-08-19-local-data
/// -durability-contract.md`). The chain survives an action throwing: the
/// error goes to that caller, the chain itself stays usable for the next
/// enqueued action (see [_runOnChain]).
class LocalDataLifecycle {
  LocalDataLifecycle({
    required this._songCatalogStore,
    required this._planningLocalStore,
    required this._identityStore,
    required this._noteLastKnownIdentity,
    required this._eventsRecorder,
    Duration Function()? monotonicNow,
    this.membershipConfirmationCooldown = const Duration(seconds: 60),
  }) : _monotonicNow = monotonicNow ?? _startProcessWideStopwatch();

  final SongCatalogStore _songCatalogStore;
  final PlanningLocalStore _planningLocalStore;
  final LastKnownIdentityStore _identityStore;
  final void Function(LastKnownIdentity?) _noteLastKnownIdentity;
  final LocalDataEventsRecorder _eventsRecorder;

  /// D5.3: the monotonic clock the membership-revocation cooldown is
  /// measured against. Defaults to a `Stopwatch` started at construction
  /// time (one per [LocalDataLifecycle] instance, which in production is
  /// one per process) -- injectable so the cooldown is deterministically
  /// testable without a real 60-second wait, and so a device clock
  /// adjustment can never shorten it (spec D5.3, ADR-035: `DateTime.now()`
  /// differences are forbidden here).
  final Duration Function() _monotonicNow;

  /// D5.3: how long the second confirmation must be separated from the
  /// first, measured on [_monotonicNow].
  final Duration membershipConfirmationCooldown;

  static Duration Function() _startProcessWideStopwatch() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  /// D5.5 rule 1: the single serialization chain guarding every identity
  /// and marker mutation. Always resolves; a rejected link is never left on
  /// this field (see [_runOnChain]), so the chain can never wedge itself
  /// permanently even if every caller ignores the error it hands back.
  Future<void> _mutationChain = Future<void>.value();

  /// D5.3: tracks whether THIS process is the one that recorded the
  /// currently-outstanding marker, and if so, when (on [_monotonicNow]).
  /// Both are cleared together -- see [_resetMembershipRevocationTracking]
  /// -- whenever the underlying marker itself is known to be gone (a
  /// cleared marker, a different-user write, or an identity clear).
  ///
  /// When [_markerRecordedForUserId] is `null`, or does not match the
  /// `userId` a later resolution names, the marker (if the store reports
  /// one) was not set by this process's tracking -- most commonly because
  /// it was recorded on an earlier launch. Per D5.3, separate launches are
  /// independent events by construction, so no cooldown check applies in
  /// that case at all.
  String? _markerRecordedForUserId;
  Duration? _markerRecordedAtMonotonic;

  /// Runs [action] after every previously enqueued action on the identity
  /// chain has finished, and before any action enqueued after it starts.
  /// [action]'s own result/error is returned to this call's caller
  /// unchanged; a thrown error is NOT allowed to propagate onto the shared
  /// chain future itself, or every subsequent enqueued action would fail
  /// immediately without ever running (Future.then forwards a prior link's
  /// error past the callback). This is what "the chain must survive an
  /// action throwing" (D5.5 rule 1) means in practice.
  Future<T> _runOnChain<T>(Future<T> Function() action) {
    final result = _mutationChain.then((_) => action());
    _mutationChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  void _resetMembershipRevocationTracking() {
    _markerRecordedForUserId = null;
    _markerRecordedAtMonotonic = null;
  }

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

  /// [userId], when supplied, both gates whether the clear happens AND is
  /// what gets recorded on the audit row: the clear only proceeds if the
  /// currently stored row belongs to [userId] (D5.5 rule 5 / closeout
  /// finding 4 -- the discarded first attempt at this gate cleared the
  /// identity row unconditionally, which let a stale confirmation for one
  /// user delete a different user's row). `userId: null` is the explicit
  /// sign-out path: there is no owner to check against, so it keeps
  /// clearing unconditionally, exactly as before.
  ///
  /// This reads the store before clearing when [userId] is supplied --
  /// previously deliberately avoided (see git history) to keep the caller's
  /// currentness guard from racing a concurrent write between the read and
  /// the clear. That race is now closed a different way: this whole method
  /// runs as one link of [_runOnChain], so no other identity mutation can
  /// interleave between this read and this clear regardless.
  Future<void> clearIdentity({
    required PurgeReason reason,
    String? userId,
  }) {
    return _runOnChain(() async {
      if (userId != null) {
        final current = await _identityStore.read();
        if (current == null || current.userId != userId) {
          return;
        }
      }
      await _identityStore.clear();
      _noteLastKnownIdentity(null);
      _resetMembershipRevocationTracking();
      unawaited(
        _recordBestEffort(
          target: PurgeTarget.identity,
          reason: reason,
          userId: userId,
        ),
      );
    });
  }

  /// Not a purge -- no reason required, no audit record.
  ///
  /// D5.1's write() contract on the store preserves an existing
  /// `membershipRevokedAt` marker for a same-user write and resets it for a
  /// different user (or a first write); this method's own
  /// this-process-recorded-the-marker tracking (used by
  /// [resolveVerifiedEmptyMembership]'s cooldown check) is kept in sync
  /// with that same rule.
  Future<void> writeIdentity(LastKnownIdentity identity) {
    return _runOnChain(() async {
      if (_markerRecordedForUserId != null &&
          _markerRecordedForUserId != identity.userId) {
        _resetMembershipRevocationTracking();
      }
      await _identityStore.write(identity);
      _noteLastKnownIdentity(identity);
    });
  }

  /// D5.1/D5.5: the counted-resolution entry point. Callers must only pass
  /// [userId] from a fresh, online, authenticated `ActiveOrganizationVerifiedEmpty`
  /// resolution (D5.2) -- connectivity failures, non-connectivity failures,
  /// caught exceptions, cached/fallback resolutions, and offline-
  /// authenticated paths must never reach this method.
  ///
  /// Deliberate Step 1 scope (docs/plans/2026-08-19-local-data-durability
  /// -contract.md, Task 4.1): [MembershipRevocationPurgeAuthorized] deletes
  /// NOTHING here. A later step consumes that outcome to run the actual
  /// purge (through [purgeSongCatalog]/[purgePlanningData]/[clearIdentity],
  /// each with `PurgeReason.membershipRevokedConfirmed`) behind the pending-
  /// work check and confirmation dialog D5.4 requires, re-validating this
  /// decision's premises on re-entry per D5.5 rule 3. Until that lands, a
  /// second counted confirmation is a deliberate, audited no-op -- see the
  /// class doc's "membership revocation purges nothing at all after Step 1"
  /// note.
  Future<MembershipRevocationDecision> resolveVerifiedEmptyMembership({
    required String userId,
  }) {
    return _runOnChain(() async {
      final outcome = await _identityStore.resolveEmptyMembership(
        userId: userId,
      );
      switch (outcome) {
        case EmptyMembershipResolutionIgnored():
          // The store deliberately collapses "no row" and "row owned by a
          // different user" into one outcome (D5.1) -- nothing was written
          // either way. This extra read is purely for the caller-facing
          // diagnostic reason and does not feed back into any decision; it
          // is still one local-store operation inside this same chain link,
          // so nothing can interleave between it and the resolution above.
          final current = await _identityStore.read();
          final reason = current == null
              ? MembershipRevocationIgnoredReason.noRow
              : MembershipRevocationIgnoredReason.notThisUser;
          return MembershipRevocationIgnored(reason);

        case EmptyMembershipResolutionMarkerRecorded():
          _markerRecordedForUserId = userId;
          _markerRecordedAtMonotonic = _monotonicNow();
          unawaited(_recordMembershipRevocationMarkedBestEffort(userId));
          return const MembershipRevocationMarkerRecorded();

        case EmptyMembershipResolutionSecondConfirmationAvailable(
          :final markedAt,
        ):
          final recordedByThisProcess =
              _markerRecordedForUserId == userId &&
              _markerRecordedAtMonotonic != null;
          if (!recordedByThisProcess) {
            // Either an earlier launch recorded it, or this process never
            // tracked it -- D5.3: separate launches are independent events
            // by construction, so no cooldown check applies at all.
            return MembershipRevocationPurgeAuthorized(markedAt: markedAt);
          }
          final elapsed =
              _monotonicNow() - _markerRecordedAtMonotonic!;
          if (elapsed >= membershipConfirmationCooldown) {
            return MembershipRevocationPurgeAuthorized(markedAt: markedAt);
          }
          return const MembershipRevocationIgnored(
            MembershipRevocationIgnoredReason.insideCooldown,
          );
      }
    });
  }

  /// D5.2: clears the membership-revocation marker for [userId]'s row --
  /// the only event that clears it is a freshly verified non-empty
  /// membership resolution. A no-op (no audit record) when there was no
  /// marker to clear, so an ordinary sign-in never writes a spurious audit
  /// row.
  Future<void> clearMembershipRevocation({required String userId}) {
    return _runOnChain(() async {
      final cleared = await _identityStore.clearMembershipRevocation(
        userId: userId,
      );
      if (!cleared) {
        return;
      }
      _resetMembershipRevocationTracking();
      unawaited(_recordMembershipRevocationClearedBestEffort(userId));
    });
  }

  /// Mirrors [_recordBestEffort]'s failure isolation: an audit-write
  /// failure here must never make the marker-set store operation that
  /// already committed look like it failed.
  Future<void> _recordMembershipRevocationMarkedBestEffort(
    String userId,
  ) async {
    try {
      await _eventsRecorder.recordMembershipRevocationMarked(userId: userId);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'LocalDataLifecycle',
          context: ErrorDescription(
            'failed to write a local_data_events audit record for a '
            'membership-revocation marker that was already recorded for '
            '$userId -- the marker itself is unaffected',
          ),
        ),
      );
    }
  }

  Future<void> _recordMembershipRevocationClearedBestEffort(
    String userId,
  ) async {
    try {
      await _eventsRecorder.recordMembershipRevocationCleared(
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
            'membership-revocation marker that was already cleared for '
            '$userId -- the clear itself is unaffected',
          ),
        ),
      );
    }
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
}
