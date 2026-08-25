import 'package:drift/drift.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';

import 'last_known_identity_database.dart';

class DriftLastKnownIdentityStore implements LastKnownIdentityStore {
  const DriftLastKnownIdentityStore(this._database);

  final LastKnownIdentityDatabase _database;

  factory DriftLastKnownIdentityStore.local() {
    return DriftLastKnownIdentityStore(LastKnownIdentityDatabase.local());
  }

  factory DriftLastKnownIdentityStore.inMemory() {
    return DriftLastKnownIdentityStore(LastKnownIdentityDatabase.inMemory());
  }

  @override
  Future<LastKnownIdentity?> read() async {
    final row = await _readRow();
    if (row == null) {
      return null;
    }

    return LastKnownIdentity(
      userId: row.userId,
      email: row.email,
      organizationId: row.organizationId,
      updatedAt: row.updatedAt,
    );
  }

  @override
  Future<void> write(LastKnownIdentity identity) async {
    // D5 (docs/specs/2026-08-19-local-data-durability-contract.md, ADR-035
    // Phase 4): write() must not silently destroy or inherit a
    // membershipRevokedAt marker. A same-user write preserves whatever
    // marker is already stored (it is simply not named in the update, so
    // the column keeps its prior value). A different-user write -- or a
    // write with no prior row -- always starts with no marker: a marker
    // must never carry over to another user. Reading the stored row and
    // deciding, then writing, must happen inside one transaction so no
    // interleaved marker mutation (resolveEmptyMembership /
    // clearMembershipRevocation, also single-transaction) can land between
    // the read and the write.
    await _database.transaction(() async {
      final existing = await _readRow();
      final sameUser = existing != null && existing.userId == identity.userId;
      await _database
          .into(_database.lastKnownIdentityRows)
          .insertOnConflictUpdate(
            LastKnownIdentityRowsCompanion.insert(
              rowId: const Value(1),
              userId: identity.userId,
              email: identity.email,
              organizationId: Value(identity.organizationId),
              updatedAt: Value(identity.updatedAt?.toUtc()),
              membershipRevokedAt: sameUser
                  ? const Value.absent()
                  : const Value(null),
            ),
          );
    });
  }

  @override
  Future<void> clear() async {
    await (_database.delete(
      _database.lastKnownIdentityRows,
    )..where((table) => table.rowId.equals(1))).go();
  }

  // D5.1 (docs/specs/2026-08-19-local-data-durability-contract.md, ADR-035
  // Phase 4): one atomic store operation -- read, decide, write -- never a
  // read in application code followed by a later write. Generalises Phase
  // 3's SongCatalogStore.resolveEmptySnapshot shape.
  @override
  Future<EmptyMembershipResolutionOutcome> resolveEmptyMembership({
    required String userId,
  }) async {
    return _database.transaction(() async {
      final row = await _readRow();
      if (row == null || row.userId != userId) {
        // No row to protect, or a row owned by a different user -- never
        // create or overwrite another user's row (closeout finding 5).
        return const EmptyMembershipResolutionIgnored();
      }

      final existingMarker = row.membershipRevokedAt;
      if (existingMarker != null) {
        // The marker is already set -- report it for the caller's cooldown
        // check, but do not clear or move it here. Only
        // clearMembershipRevocation (a freshly verified non-empty
        // resolution) or a different-user write clears it.
        return EmptyMembershipResolutionSecondConfirmationAvailable(
          markedAt: existingMarker,
        );
      }

      final markedAt = DateTime.now().toUtc();
      await (_database.update(
        _database.lastKnownIdentityRows,
      )..where((table) => table.rowId.equals(1))).write(
        LastKnownIdentityRowsCompanion(membershipRevokedAt: Value(markedAt)),
      );
      return EmptyMembershipResolutionMarkerRecorded(markedAt: markedAt);
    });
  }

  @override
  Future<bool> clearMembershipRevocation({required String userId}) async {
    return _database.transaction(() async {
      final row = await _readRow();
      if (row == null ||
          row.userId != userId ||
          row.membershipRevokedAt == null) {
        return false;
      }
      await (_database.update(
        _database.lastKnownIdentityRows,
      )..where((table) => table.rowId.equals(1))).write(
        const LastKnownIdentityRowsCompanion(membershipRevokedAt: Value(null)),
      );
      return true;
    });
  }

  @override
  Future<bool> hasCurrentMembershipRevocationMarker({
    required String userId,
    required DateTime markedAt,
  }) async {
    final row = await _readRow();
    if (row == null || row.userId != userId) {
      return false;
    }
    final marker = row.membershipRevokedAt;
    return marker != null && marker.isAtSameMomentAs(markedAt);
  }

  Future<LastKnownIdentityRow?> _readRow() {
    return (_database.select(
      _database.lastKnownIdentityRows,
    )..where((table) => table.rowId.equals(1))).getSingleOrNull();
  }
}
