import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/auth/reauth_prompt_controller.dart';
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

/// YELLOW 3 (final whole-branch review, D5.4): why an authorized purge
/// (two counted confirmations) did not run in
/// [LocalDataLifecycle.maybePurgeForMembershipRevocation]. Distinguished so
/// the audit trail -- the diagnostic explaining why a purge that was
/// authorized did not happen -- can tell these apart, not merely record
/// that it didn't happen.
enum MembershipRevocationPurgeDeclineReason {
  /// The user explicitly declined the confirmation dialog.
  cancelled,

  /// A newer prompt superseded this one before it was answered.
  superseded,

  /// [ReauthPromptController.requestConfirmation] could not show a prompt
  /// (a different prompt was already pending) and threw `StateError`.
  promptUnavailable,

  /// On re-entry, the identity row no longer exists, belongs to a
  /// different user, or carries a different `membershipRevokedAt` than the
  /// one this decision was authorized against (D5.5 rule 3) -- a
  /// concurrent non-empty resolution or another purge changed the premise.
  markerChanged,

  /// On re-entry, the pending-work count is unknown or grew past the count
  /// named to the user in the confirmation dialog (D5.5 rule 3).
  pendingWorkIncreased,
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

  /// YELLOW 3 (final whole-branch review, D5.4): records that a purge
  /// [maybePurgeForMembershipRevocation] authorized (two counted
  /// confirmations) did NOT run -- cancelled or dismissed, superseded, the
  /// confirmation prompt could not be shown, or the purge's premises no
  /// longer held on re-entry. Not a purge -- no [PurgeReason] applies --
  /// but this is the diagnostic that explains why an authorized purge did
  /// not happen; without it, the audit trail is silent on the exact cases
  /// D5.4 exists to make safe.
  Future<void> recordMembershipRevocationPurgeDeclined({
    required String userId,
    required MembershipRevocationPurgeDeclineReason reason,
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
  Future<void> clearIdentity({required PurgeReason reason, String? userId}) {
    return _runOnChain(
      () => _clearIdentityLocked(reason: reason, userId: userId),
    );
  }

  /// The body [clearIdentity] runs as one link of [_runOnChain]. Extracted
  /// so [maybePurgeForMembershipRevocation] -- which is already executing
  /// inside its own chain link when it needs to clear the identity row --
  /// can call this directly instead of re-entering [_runOnChain], which
  /// would deadlock (a chain link can never wait on a second enqueue of
  /// itself; see that method's doc).
  Future<void> _clearIdentityLocked({
    required PurgeReason reason,
    String? userId,
  }) async {
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
      await _identityStore.write(identity);
      // Only after the store write has actually committed. Resetting the
      // tracking first would, on a failed write, leave the prior user's
      // marker fully intact in storage while this process forgot that it
      // was the one that recorded it -- and a marker this process does not
      // remember recording is treated as "from an earlier launch," which
      // skips the D5.3 cooldown entirely and collapses the two-confirmation
      // gate to one. Nothing can interleave between the write and this
      // reset: the whole method is one link of [_runOnChain].
      if (_markerRecordedForUserId != null &&
          _markerRecordedForUserId != identity.userId) {
        _resetMembershipRevocationTracking();
      }
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
          final elapsed = _monotonicNow() - _markerRecordedAtMonotonic!;
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

  /// D5.4/D5.5 -- Step 2: consumes a [MembershipRevocationPurgeAuthorized]
  /// outcome from [resolveVerifiedEmptyMembership] and runs (or correctly
  /// declines to run) the actual purge.
  ///
  /// Shape, per D5.5 rule 2 ("no user interaction inside the chain"):
  /// 1. Inside the chain: read the current pending-work count.
  /// 2. Outside the chain (no chain slot held): if the count is nonzero or
  ///    unknown (`null`), await [requestConfirmation]. Zero skips this step
  ///    entirely -- no dialog.
  /// 3. Re-enter the chain: re-validate that the identity row still exists,
  ///    still belongs to [userId], and still carries a
  ///    `membershipRevokedAt` equal to [markedAt] (D5.5 rule 3) -- a
  ///    concurrent non-empty resolution, a different-user write, or another
  ///    purge must be able to cancel this one. Also re-validate that the
  ///    current pending-work count is no greater than the count the
  ///    confirmation named (an unknown/`null` count at step 1 is never
  ///    compared numerically here -- it was already the maximally-cautious
  ///    case at step 2, so nothing stricter to re-check). Any mismatch
  ///    aborts: nothing is deleted, the marker is left exactly as found.
  /// 4. On a genuine go-ahead: purge the song catalog, planning data, and
  ///    identity row for [userId], each through the existing primitives
  ///    with `PurgeReason.membershipRevokedConfirmed`, each with its own
  ///    audit record.
  ///
  /// [requestConfirmation] must never be awaited while holding a chain slot
  /// -- an unanswered dialog would otherwise block every other identity
  /// mutation in the app, including the very `clearMembershipRevocation`
  /// call a concurrent non-empty resolution needs to cancel this purge (the
  /// discarded first attempt's root cause -- see the Phase 4 closeout in
  /// docs/plans/2026-08-19-local-data-durability-contract.md). A prompt that
  /// cannot be shown -- [ReauthPromptController.requestConfirmation] throws
  /// `StateError` when a different prompt is already pending -- is treated
  /// as "not confirmed," never rethrown: a caller reached from a
  /// fire-and-forget auth listener must not let an uncaught exception vanish
  /// into the zone (closeout yellow risk 3), and a prompt that could not be
  /// shown is not a confirmation.
  ///
  /// Returns `true` only if a purge actually ran, so callers know whether to
  /// reset any of their own in-memory read state (ADR-020: reads must not be
  /// reset on a resolution that deleted nothing).
  Future<bool> maybePurgeForMembershipRevocation({
    required String userId,
    required DateTime markedAt,
    required Future<int?> Function() countPendingWork,
    required Future<ReauthPromptResult> Function({required int? pendingCount})
    requestConfirmation,
  }) async {
    final initialCount = await _runOnChain(() => countPendingWork());

    if (initialCount == null || initialCount != 0) {
      final ReauthPromptResult result;
      try {
        result = await requestConfirmation(pendingCount: initialCount);
      } on StateError {
        // A different prompt is already pending (closeout yellow risk 3,
        // e.g. a concurrent different-user reauth prompt). Not a
        // confirmation -- abort without deleting anything.
        unawaited(
          _recordMembershipRevocationPurgeDeclinedBestEffort(
            userId,
            MembershipRevocationPurgeDeclineReason.promptUnavailable,
          ),
        );
        return false;
      }
      switch (result) {
        case ReauthPromptResult.confirmed:
          break;
        case ReauthPromptResult.cancelled:
          unawaited(
            _recordMembershipRevocationPurgeDeclinedBestEffort(
              userId,
              MembershipRevocationPurgeDeclineReason.cancelled,
            ),
          );
          return false;
        case ReauthPromptResult.superseded:
          unawaited(
            _recordMembershipRevocationPurgeDeclinedBestEffort(
              userId,
              MembershipRevocationPurgeDeclineReason.superseded,
            ),
          );
          return false;
      }
    }

    return _runOnChain(() async {
      final premisesHold = await _identityStore
          .hasCurrentMembershipRevocationMarker(
            userId: userId,
            markedAt: markedAt,
          );
      if (!premisesHold) {
        unawaited(
          _recordMembershipRevocationPurgeDeclinedBestEffort(
            userId,
            MembershipRevocationPurgeDeclineReason.markerChanged,
          ),
        );
        return false;
      }
      if (initialCount != null) {
        final currentCount = await countPendingWork();
        if (currentCount == null || currentCount > initialCount) {
          unawaited(
            _recordMembershipRevocationPurgeDeclinedBestEffort(
              userId,
              MembershipRevocationPurgeDeclineReason.pendingWorkIncreased,
            ),
          );
          return false;
        }
      }

      try {
        await purgeSongCatalog(
          userId: userId,
          reason: PurgeReason.membershipRevokedConfirmed,
        );
        await purgePlanningData(
          userId: userId,
          reason: PurgeReason.membershipRevokedConfirmed,
        );
        await _clearIdentityLocked(
          reason: PurgeReason.membershipRevokedConfirmed,
          userId: userId,
        );
      } catch (error, stackTrace) {
        // Every caller of this method is reached from a fire-and-forget auth
        // or refresh listener, so an exception escaping here would vanish
        // into the zone unreported and leave a half-purged device behind
        // (mirrors the ADR-029 Finding 1 fix on the sibling
        // `wipePriorAndProceedFor` wipe path).
        //
        // Reporting `false` rather than rethrowing is the conservative
        // claim: a partial purge is not a completed one, so callers must not
        // reset their read state as though it were. The marker is
        // deliberately left set, so a later counted confirmation re-runs the
        // purge -- each primitive deletes by `userId` and is idempotent, so
        // repeating the already-committed part is harmless.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'LocalDataLifecycle',
            context: ErrorDescription(
              'a confirmed membership-revocation purge for $userId failed '
              'part way through -- the device may be partially purged, the '
              'revocation marker is left set so a later confirmation can '
              'retry it',
            ),
          ),
        );
        return false;
      }
      return true;
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
      await _eventsRecorder.recordMembershipRevocationCleared(userId: userId);
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

  /// YELLOW 3: mirrors [_recordBestEffort]'s failure isolation for the
  /// declined-purge audit trail -- a failure writing this record must never
  /// make the (already-correct) decision not to purge look like it failed.
  Future<void> _recordMembershipRevocationPurgeDeclinedBestEffort(
    String userId,
    MembershipRevocationPurgeDeclineReason reason,
  ) async {
    try {
      await _eventsRecorder.recordMembershipRevocationPurgeDeclined(
        userId: userId,
        reason: reason,
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'LocalDataLifecycle',
          context: ErrorDescription(
            'failed to write a local_data_events audit record for a '
            'declined membership-revocation purge ($reason) for $userId -- '
            'the decision not to purge is unaffected',
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
