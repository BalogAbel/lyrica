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
}

/// D7: the single gate every local-data purge primitive must be reached
/// through, requiring every call to name a real [PurgeReason].
///
/// Each destructive method here performs the underlying store's deletion and
/// then writes exactly one audit record for it. If the underlying deletion
/// throws, the exception propagates unchanged and no audit record is
/// written -- a failure is reported, never silently claimed as a success.
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
    await _eventsRecorder.recordPurge(
      target: PurgeTarget.songCatalog,
      reason: reason,
      userId: userId,
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
    await _eventsRecorder.recordPurge(
      target: PurgeTarget.planningData,
      reason: reason,
      userId: userId,
    );
  }

  /// Reads the identity BEFORE clearing it, so the audit record can still
  /// attribute a `userId` -- the durable row is about to be deleted so this
  /// is the last chance to know whose identity it was.
  Future<void> clearIdentity({required PurgeReason reason}) async {
    final identity = await _identityStore.read();
    await _identityStore.clear();
    _noteLastKnownIdentity(null);
    await _eventsRecorder.recordPurge(
      target: PurgeTarget.identity,
      reason: reason,
      userId: identity?.userId,
    );
  }

  /// Not a purge -- no reason required, no audit record.
  Future<void> writeIdentity(LastKnownIdentity identity) async {
    await _identityStore.write(identity);
    _noteLastKnownIdentity(identity);
  }
}
