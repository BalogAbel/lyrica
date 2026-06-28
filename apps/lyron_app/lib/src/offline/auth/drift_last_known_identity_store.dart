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
    await _database.into(_database.lastKnownIdentityRows).insertOnConflictUpdate(
      LastKnownIdentityRowsCompanion.insert(
        rowId: const Value(1),
        userId: identity.userId,
        email: identity.email,
        organizationId: Value(identity.organizationId),
        updatedAt: Value(identity.updatedAt?.toUtc()),
      ),
    );
  }

  @override
  Future<void> clear() async {
    await (_database.delete(_database.lastKnownIdentityRows)
          ..where((table) => table.rowId.equals(1)))
        .go();
  }

  Future<LastKnownIdentityRow?> _readRow() {
    return (_database.select(_database.lastKnownIdentityRows)
          ..where((table) => table.rowId.equals(1)))
        .getSingleOrNull();
  }
}
