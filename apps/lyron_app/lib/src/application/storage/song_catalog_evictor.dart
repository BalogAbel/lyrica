import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

/// The only eviction the app performs.
///
/// Deletes cached song **sources** for songs that carry no pending song
/// mutation. Sources are the largest cached payload and are re-fetchable, so
/// they are the one thing that can be given up under storage pressure.
///
/// Never touched: pending song mutations and pending planning mutations
/// (unsynced intent), cached summaries (they back the browsable list), the
/// planning projection (offline it is the only readable view) and the
/// last-known identity store (ADR-020).
///
/// This is local storage policy, never an authorization decision.
class SongCatalogEvictor {
  const SongCatalogEvictor({
    required SongCatalogDatabase database,
    required CatalogStorageAccountant accountant,
  }) : _database = database,
       _accountant = accountant;

  final SongCatalogDatabase _database;
  final CatalogStorageAccountant _accountant;

  /// Returns the estimated bytes freed.
  ///
  /// `measureDroppableBytes()` and the `DELETE` below are two separate,
  /// un-transacted statements, so a write landing between them can make the
  /// returned figure diverge from what was actually deleted -- it is a
  /// best-effort estimate for diagnostics only (it currently only ever ends
  /// up inside [LocalStorageWriteFailure.toString]). This does NOT affect
  /// correctness of the deletion itself: the `DELETE`'s own `NOT EXISTS`
  /// re-evaluates at delete time, so protected rows (songs with a pending
  /// mutation) are never removed regardless of what ran in between. If this
  /// figure is ever used for something user-facing rather than diagnostics,
  /// both statements would need to run inside one transaction first.
  Future<int> evictDroppable() async {
    final droppableBytes = await _accountant.measureDroppableBytes();
    if (droppableBytes == 0) {
      return 0;
    }
    await _database.customStatement(
      'DELETE FROM cached_catalog_sources AS s '
      'WHERE NOT EXISTS ('
      'SELECT 1 FROM cached_catalog_song_mutations AS m '
      'WHERE m.user_id = s.user_id '
      'AND m.organization_id = s.organization_id '
      'AND m.song_id = s.song_id)',
    );
    return droppableBytes;
  }
}
